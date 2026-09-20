/**
 * Engram lifecycle integration for OpenCode V2.
 *
 * This is a server plugin, so one implementation covers Desktop, CLI and TUI
 * clients. It uses only Node APIs and keeps a V1 `server()` entrypoint while
 * the two OpenCode generations are installed side by side.
 */

import { spawn } from "node:child_process"
import { existsSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const ENGRAM_VERSION = "2.0.0-rc.10"
const ENGRAM_PORT = Number.parseInt(process.env.ENGRAM_PORT ?? "7437", 10)
const ENGRAM_URL = `http://127.0.0.1:${ENGRAM_PORT}`

const ENGRAM_TOOLS = new Set([
  "mem_search",
  "mem_save",
  "mem_update",
  "mem_delete",
  "mem_suggest_topic_key",
  "mem_save_prompt",
  "mem_session_summary",
  "mem_context",
  "mem_stats",
  "mem_timeline",
  "mem_get_observation",
  "mem_session_start",
  "mem_session_end",
  "mem_capture_passive",
])

const SESSION_WRITE_TOOLS = new Set([
  "mem_save",
  "mem_save_prompt",
  "mem_session_summary",
  "mem_capture_passive",
])

const MEMORY_INSTRUCTIONS = `## Engram persistent memory

- Save durable decisions, fixes, discoveries, conventions and preferences as soon as they are established.
- Search targeted personal, organisation and repository scopes when prior context could help.
- Treat memory operations as internal bookkeeping and finish them before the user-facing response.
- Before declaring substantial work complete, save the structured session summary required by the active AGENTS.md policy.
- After compaction, persist the compacted summary before continuing.
`

const MEMORY_NUDGE = "MEMORY REMINDER: It has been at least 15 minutes since the last saved memory. Save any durable decisions, discoveries, completed work or non-obvious findings now."

type SessionInfo = {
  id: string
  parentID?: string
  projectID?: string
}

type SessionGetter = (sessionID: string) => Promise<SessionInfo | undefined>

function canonicalToolName(tool: string): string {
  const value = tool.toLowerCase()
  return value.startsWith("engram_") ? value.slice("engram_".length) : value
}

function stripPrivateTags(value: string): string {
  return value.replace(/<private>[\s\S]*?<\/private>/gi, "[REDACTED]").trim()
}

function truncate(value: string, maximum: number): string {
  return value.length > maximum ? `${value.slice(0, maximum)}...` : value
}

function toEpochSeconds(timestamp: string): number | null {
  if (!timestamp) return null
  const normalized = timestamp.replace(" ", "T")
  const withZone = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(normalized) ? normalized : `${normalized}Z`
  const milliseconds = new Date(withZone).getTime()
  return Number.isNaN(milliseconds) ? null : Math.floor(milliseconds / 1000)
}

export function shouldNudgeForObservations(
  observations: unknown,
  nowSeconds: number,
  sessionStarted: number | null,
  thresholdSeconds = 900,
): boolean {
  if (!Array.isArray(observations)) return false
  if (observations.length === 0) {
    return sessionStarted !== null && nowSeconds - sessionStarted >= thresholdSeconds
  }
  const createdAt = observations[0]?.created_at
  if (typeof createdAt !== "string") return false
  const latest = toEpochSeconds(createdAt)
  return latest !== null && nowSeconds - latest >= thresholdSeconds
}

function resolveMise(): string {
  const executable = process.platform === "win32" ? "mise.exe" : "mise"
  const candidates = [
    process.env.MISE_BIN,
    join(homedir(), ".local", "bin", executable),
    process.env.LOCALAPPDATA
      ? join(process.env.LOCALAPPDATA, "mise", "bin", executable)
      : undefined,
  ].filter((candidate): candidate is string => Boolean(candidate))
  return candidates.find(existsSync) ?? "mise"
}

function engramCommand(...args: string[]): string[] {
  return [
    resolveMise(),
    "exec",
    `github:Gentleman-Programming/engram@${ENGRAM_VERSION}`,
    "--",
    "engram",
    ...args,
  ]
}

async function engramFetch(
  path: string,
  options: { method?: string; body?: unknown; timeout?: number } = {},
): Promise<any | null> {
  try {
    const response = await fetch(`${ENGRAM_URL}${path}`, {
      method: options.method ?? "GET",
      headers: options.body ? { "Content-Type": "application/json" } : undefined,
      body: options.body ? JSON.stringify(options.body) : undefined,
      signal: AbortSignal.timeout(options.timeout ?? 3000),
    })
    if (!response.ok) return null
    const text = await response.text()
    return text ? JSON.parse(text) : {}
  } catch {
    return null
  }
}

async function ensureEngramServer(): Promise<void> {
  const health = await engramFetch("/health", { timeout: 500 })
  if (health) return
  try {
    const [command, ...args] = engramCommand("serve")
    const child = spawn(command, args, {
      detached: true,
      stdio: "ignore",
      windowsHide: true,
      env: {
        ...process.env,
        ENGRAM_CLOUD_AUTOSYNC: "0",
        ENGRAM_NO_UPDATE_CHECK: "1",
      },
    })
    child.unref()
  } catch {
    return
  }
  for (let attempt = 0; attempt < 10; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 100))
    if (await engramFetch("/health", { timeout: 250 })) return
  }
}

async function resolveProject(directory: string): Promise<string> {
  const data = await engramFetch(`/project/current?cwd=${encodeURIComponent(directory)}`)
  const project = typeof data?.project === "string" ? data.project.trim() : ""
  if (project && project !== "unknown" && !data?.error_hint && !/[\\/]/.test(project)) {
    return project
  }
  return ""
}

function completedToolText(result: unknown): string {
  if (!result || typeof result !== "object") return ""
  const content = (result as { content?: unknown }).content
  if (typeof content === "string") return content.trim()
  if (Array.isArray(content)) {
    return content
      .filter((item): item is { type: string; text: string } => (
        Boolean(item) &&
        typeof item === "object" &&
        (item as any).type === "text" &&
        typeof (item as any).text === "string"
      ))
      .map((item) => item.text)
      .join("\n")
      .trim()
  }
  const output = (result as { output?: unknown }).output
  if (typeof output === "string") return output.trim()
  return output === undefined ? "" : JSON.stringify(output)
}

function appendSystem(system: Array<any>, text: string): void {
  const last = system.at(-1)
  if (last?.type === "text" && typeof last.text === "string") {
    last.text += `\n\n${text}`
  } else {
    system.push({ type: "text", text })
  }
}

class Lifecycle {
  private project = ""
  private readonly parents = new Map<string, string | null>()
  private readonly registered = new Set<string>()
  private readonly invalid = new Set<string>()
  private readonly closed = new Set<string>()
  private readonly closing = new Map<string, Promise<boolean>>()
  private readonly lastNudge = new Map<string, number>()

  constructor(
    private readonly directory: string,
    private readonly projectID: string | undefined,
    private readonly getSession: SessionGetter,
  ) {}

  async initialize(): Promise<void> {
    await ensureEngramServer()
    this.project = await resolveProject(this.directory)
  }

  cache(info: SessionInfo | undefined): void {
    if (!info?.id) return
    if (this.projectID && info.projectID !== this.projectID) return
    if (info.parentID !== undefined && (!info.parentID || typeof info.parentID !== "string")) return
    if (this.invalid.has(info.id) || (info.parentID && this.invalid.has(info.parentID))) {
      this.invalidate(info.id)
      return
    }
    this.parents.set(info.id, info.parentID ?? null)
  }

  invalidate(sessionID: string): void {
    const invalidated = new Set([sessionID])
    let changed = true
    while (changed) {
      changed = false
      for (const [child, parent] of this.parents) {
        if (parent && invalidated.has(parent) && !invalidated.has(child)) {
          invalidated.add(child)
          changed = true
        }
      }
    }
    for (const id of invalidated) {
      this.invalid.add(id)
      this.parents.delete(id)
      this.registered.delete(id)
      this.lastNudge.delete(id)
    }
  }

  async root(sessionID: string): Promise<string> {
    if (!sessionID || this.invalid.has(sessionID)) return ""
    const visited = new Set<string>()
    let current = sessionID
    while (current) {
      if (visited.has(current) || this.invalid.has(current)) return ""
      visited.add(current)
      if (!this.parents.has(current)) {
        let info: SessionInfo | undefined
        try {
          info = await this.getSession(current)
        } catch {
          return ""
        }
        if (!info?.id || info.id !== current) return ""
        if (this.projectID && info.projectID !== this.projectID) return ""
        this.cache(info)
      }
      const parent = this.parents.get(current)
      if (parent === null) return current
      if (!parent) return ""
      current = parent
    }
    return ""
  }

  async ensure(sessionID: string): Promise<string> {
    const root = await this.root(sessionID)
    if (!root) return ""
    if (!this.project) this.project = await resolveProject(this.directory)
    if (!this.project) return ""
    if (!this.registered.has(root)) {
      const result = await engramFetch("/sessions", {
        method: "POST",
        body: { id: root, project: this.project, directory: this.directory },
      })
      if (result === null) return ""
      this.registered.add(root)
    }
    return root
  }

  async capturePrompt(sessionID: string, content: string): Promise<void> {
    const root = await this.ensure(sessionID)
    if (!root || root !== sessionID || content.trim().length <= 10) return
    await engramFetch("/prompts", {
      method: "POST",
      body: {
        session_id: root,
        content: stripPrivateTags(truncate(content.trim(), 2000)),
        project: this.project,
      },
    })
  }

  async attributeWrite(sessionID: string, tool: string, input: unknown): Promise<void> {
    if (!SESSION_WRITE_TOOLS.has(canonicalToolName(tool))) return
    const root = await this.ensure(sessionID)
    if (!root) throw new Error(`Engram could not register an authoritative session for ${tool}`)
    if (!input || typeof input !== "object" || Array.isArray(input)) {
      throw new Error(`Engram cannot attach a session ID to invalid arguments for ${tool}`)
    }
    ;(input as Record<string, unknown>).session_id = root
  }

  async captureTool(sessionID: string, tool: string, result: unknown): Promise<void> {
    if (ENGRAM_TOOLS.has(canonicalToolName(tool))) return
    const root = await this.ensure(sessionID)
    if (!root) return
    const name = canonicalToolName(tool)
    if (name !== "task" && name !== "subagent") return
    const text = completedToolText(result)
    if (text.length <= 50) return
    await engramFetch("/observations/passive", {
      method: "POST",
      body: {
        session_id: root,
        content: stripPrivateTags(text),
        project: this.project,
        source: "subagent-complete",
      },
    })
  }

  async compactionContext(sessionID: string): Promise<string> {
    const root = await this.ensure(sessionID)
    if (!root) return ""
    const data = await engramFetch(`/context/compaction?session_id=${encodeURIComponent(root)}`)
    const context = typeof data?.context === "string" ? data.context.trim() : ""
    return [
      context,
      "After compaction, persist the compacted summary with mem_session_summary before doing other work.",
    ].filter(Boolean).join("\n\n")
  }

  async nudge(sessionID: string): Promise<string> {
    const root = await this.ensure(sessionID)
    if (!root || root !== sessionID) return ""
    const threshold = Number.parseInt(process.env.ENGRAM_NUDGE_COOLDOWN_SECS ?? "900", 10)
    const thresholdSeconds = Number.isFinite(threshold) && threshold > 0 ? threshold : 900
    const nowSeconds = Math.floor(Date.now() / 1000)
    const previous = this.lastNudge.get(root)
    if (previous !== undefined && nowSeconds - previous < thresholdSeconds) return ""

    const session = await engramFetch(`/sessions/${encodeURIComponent(root)}`, { timeout: 250 })
    const sessionStarted = typeof session?.started_at === "string"
      ? toEpochSeconds(session.started_at)
      : null
    if (sessionStarted === null || nowSeconds - sessionStarted < 300) return ""

    const observations = await engramFetch(
      `/observations?project=${encodeURIComponent(this.project)}&limit=1&sort=created_at:desc`,
      { timeout: 250 },
    )
    if (!shouldNudgeForObservations(observations, nowSeconds, sessionStarted, thresholdSeconds)) return ""
    this.lastNudge.set(root, nowSeconds)
    return MEMORY_NUDGE
  }

  async close(sessionID: string): Promise<boolean> {
    if (this.parents.get(sessionID) !== null || !this.registered.has(sessionID)) return false
    if (this.closed.has(sessionID)) return true
    const active = this.closing.get(sessionID)
    if (active) return active
    const closing = engramFetch(`/sessions/${encodeURIComponent(sessionID)}/end`, { method: "POST" })
      .then((result) => {
        if (result === null) return false
        this.closed.add(sessionID)
        return true
      })
      .finally(() => this.closing.delete(sessionID))
    this.closing.set(sessionID, closing)
    return closing
  }

  async closeAll(): Promise<void> {
    await Promise.all([...this.registered].map((sessionID) => this.close(sessionID)))
  }
}

function v2SessionGetter(context: any): SessionGetter {
  return async (sessionID) => {
    const info = await context.session.get({ sessionID })
    return info ? { id: info.id, parentID: info.parentID, projectID: info.projectID } : undefined
  }
}

function v1SessionGetter(context: any): SessionGetter {
  return async (sessionID) => {
    const result = await context.client.session.get({ path: { id: sessionID } })
    const info = result?.data
    return info ? { id: info.id, parentID: info.parentID, projectID: info.projectID } : undefined
  }
}

async function setupV2(context: any): Promise<() => Promise<void>> {
  const lifecycle = new Lifecycle(
    context.location.directory,
    context.location.project?.id,
    v2SessionGetter(context),
  )
  await lifecycle.initialize()

  await context.mcp.transform((editor: any) => {
    editor.set("engram", {
      type: "local",
      command: engramCommand("mcp", "--tools=agent"),
      disabled: false,
      environment: {
        ENGRAM_CLOUD_AUTOSYNC: "0",
        ENGRAM_NO_UPDATE_CHECK: "1",
      },
    })
  })

  await context.session.hook("prompt", async (event: any) => {
    await lifecycle.capturePrompt(event.sessionID, event.prompt.text ?? "")
  })

  await context.session.hook("context", async (event: any) => {
    await lifecycle.ensure(event.sessionID)
    appendSystem(event.system, MEMORY_INSTRUCTIONS)
    const nudge = await lifecycle.nudge(event.sessionID)
    if (nudge) appendSystem(event.system, nudge)
  })

  await context.session.hook("compaction", async (event: any) => {
    const memory = await lifecycle.compactionContext(event.sessionID)
    if (memory) appendSystem(event.system, memory)
  })

  await context.tool.hook("execute.before", async (event: any) => {
    await lifecycle.attributeWrite(event.sessionID, event.tool, event.input)
  })

  await context.tool.hook("execute.after", async (event: any) => {
    if (event.status === "completed") {
      await lifecycle.captureTool(event.sessionID, event.tool, event.result)
    }
  })

  const controller = new AbortController()
  void (async () => {
    try {
      for await (const event of context.event.subscribe({ signal: controller.signal })) {
        if (event.type === "session.created") {
          lifecycle.cache({
            id: event.data.sessionID,
            parentID: event.data.parentID,
            projectID: event.data.projectID,
          })
          if (!event.data.parentID) await lifecycle.ensure(event.data.sessionID)
        } else if (event.type === "session.deleted") {
          await lifecycle.close(event.data.sessionID)
          lifecycle.invalidate(event.data.sessionID)
        } else if (event.type === "location.shutdown") {
          await lifecycle.closeAll()
        }
      }
    } catch (error) {
      if (!controller.signal.aborted) console.error("Engram event subscription stopped", error)
    }
  })()

  return async () => {
    controller.abort()
    await lifecycle.closeAll()
  }
}

async function setupV1(context: any): Promise<Record<string, any>> {
  const lifecycle = new Lifecycle(context.directory, context.project?.id, v1SessionGetter(context))
  await lifecycle.initialize()

  return {
    dispose: () => lifecycle.closeAll(),

    event: async ({ event }: any) => {
      const info = event.properties?.info
      if (event.type === "session.created" || event.type === "session.updated") {
        lifecycle.cache(info)
        if (event.type === "session.created" && info?.id && !info.parentID) {
          await lifecycle.ensure(info.id)
        }
      } else if (event.type === "session.deleted" && info?.id) {
        await lifecycle.close(info.id)
        lifecycle.invalidate(info.id)
      }
    },

    "chat.message": async (input: any, output: any) => {
      const content = output.parts
        ?.filter((part: any) => part.type === "text")
        .map((part: any) => part.text ?? "")
        .join("\n") ?? ""
      await lifecycle.capturePrompt(input.sessionID, content)
    },

    "tool.execute.before": async (input: any, output: any) => {
      await lifecycle.attributeWrite(input.sessionID, input.tool, output.args)
    },

    "tool.execute.after": async (input: any, output: any) => {
      await lifecycle.captureTool(input.sessionID, input.tool, {
        content: [{ type: "text", text: output?.output ?? "" }],
      })
    },

    "experimental.chat.system.transform": async (input: any, output: any) => {
      if (output.system.length > 0) {
        output.system[output.system.length - 1] += `\n\n${MEMORY_INSTRUCTIONS}`
      } else {
        output.system.push(MEMORY_INSTRUCTIONS)
      }
      const nudge = await lifecycle.nudge(input.sessionID ?? "")
      if (nudge) output.system[output.system.length - 1] += `\n\n${nudge}`
    },

    "experimental.session.compacting": async (input: any, output: any) => {
      const memory = await lifecycle.compactionContext(input.sessionID)
      if (memory) output.context.push(memory)
    },
  }
}

export default {
  id: "engram.lifecycle",
  setup: setupV2,
  server: setupV1,
}
