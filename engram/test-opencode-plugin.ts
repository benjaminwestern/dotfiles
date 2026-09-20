#!/usr/bin/env bun

import assert from "node:assert/strict"
import plugin, { shouldNudgeForObservations } from "../opencode/plugins/engram/index.ts"
import v1Shim, { Engram as v1Plugin } from "../opencode/plugins/engram.ts"

type Hook = (event: any) => Promise<void> | void

class EventQueue implements AsyncIterable<any> {
  private values: any[] = []
  private waiters: Array<(result: IteratorResult<any>) => void> = []
  private closed = false

  push(value: any): void {
    const waiter = this.waiters.shift()
    if (waiter) waiter({ value, done: false })
    else this.values.push(value)
  }

  close(): void {
    this.closed = true
    for (const waiter of this.waiters.splice(0)) waiter({ value: undefined, done: true })
  }

  [Symbol.asyncIterator](): AsyncIterator<any> {
    return {
      next: () => {
        if (this.values.length > 0) return Promise.resolve({ value: this.values.shift(), done: false })
        if (this.closed) return Promise.resolve({ value: undefined, done: true })
        return new Promise((resolve) => this.waiters.push(resolve))
      },
    }
  }
}

const originalFetch = globalThis.fetch
const requests: Array<{ method: string; path: string; body: any }> = []

globalThis.fetch = async (input, init = {}) => {
  const url = new URL(typeof input === "string" ? input : input.url)
  const method = init.method ?? "GET"
  const body = typeof init.body === "string" ? JSON.parse(init.body) : undefined
  requests.push({ method, path: `${url.pathname}${url.search}`, body })

  if (url.pathname === "/health") return Response.json({ status: "ok" })
  if (url.pathname === "/project/current") return Response.json({ project: "plugin-test" })
  if (url.pathname === "/context/compaction") return Response.json({ context: "session-only memory" })
  if (url.pathname === "/observations") {
    return Response.json([{ created_at: new Date().toISOString() }])
  }
  if (url.pathname.startsWith("/sessions/") && method === "GET") {
    return Response.json({ started_at: "2026-09-20 00:00:00" })
  }
  return Response.json({ status: "ok" }, { status: method === "POST" ? 201 : 200 })
}

try {
  assert.equal(plugin.id, "engram.lifecycle")
  assert.equal(typeof plugin.setup, "function")
  assert.equal(typeof plugin.server, "function")
  assert.equal(v1Shim.id, "engram.lifecycle.v1")
  assert.equal(typeof v1Shim.server, "function")
  assert.equal(typeof v1Plugin, "function")

  const now = Math.floor(Date.now() / 1000)
  assert.equal(shouldNudgeForObservations([], now, now - 901), true)
  assert.equal(shouldNudgeForObservations([], now, now - 899), false)
  assert.equal(shouldNudgeForObservations(null, now, now - 901), false)

  const sessions = new Map([
    ["ses_root", { id: "ses_root", projectID: "project-id" }],
    ["ses_child", { id: "ses_child", parentID: "ses_root", projectID: "project-id" }],
  ])
  const sessionHooks = new Map<string, Hook>()
  const toolHooks = new Map<string, Hook>()
  const events = new EventQueue()
  let mcpCommand: string[] = []

  const cleanup = await plugin.setup({
    location: {
      directory: "/portable/project",
      project: { id: "project-id" },
    },
    mcp: {
      transform: async (callback: (editor: any) => void) => callback({
        set: (name: string, config: any) => {
          assert.equal(name, "engram")
          mcpCommand = config.command
        },
      }),
    },
    session: {
      get: async ({ sessionID }: any) => sessions.get(sessionID),
      hook: async (name: string, callback: Hook) => sessionHooks.set(name, callback),
    },
    tool: {
      hook: async (name: string, callback: Hook) => toolHooks.set(name, callback),
    },
    event: {
      subscribe: ({ signal }: any) => {
        signal.addEventListener("abort", () => events.close(), { once: true })
        return events
      },
    },
  } as any)

  assert.equal(mcpCommand.at(-2), "mcp")
  assert.equal(mcpCommand.at(-1), "--tools=agent")
  assert.deepEqual([...sessionHooks.keys()].sort(), ["compaction", "context", "prompt"])
  assert.deepEqual([...toolHooks.keys()].sort(), ["execute.after", "execute.before"])

  const system = [{ type: "text", text: "base instructions" }]
  await sessionHooks.get("context")!({ sessionID: "ses_root", system })
  assert.equal(system.length, 1, "system instructions stay in one text part")
  assert.match(system[0].text, /Engram persistent memory/)

  await sessionHooks.get("prompt")!({
    sessionID: "ses_root",
    prompt: { text: "Capture this durable user prompt." },
  })
  await sessionHooks.get("prompt")!({
    sessionID: "ses_child",
    prompt: { text: "Do not capture a child prompt." },
  })
  assert.equal(requests.filter((request) => request.path === "/prompts").length, 1)

  const write = { title: "test" }
  await toolHooks.get("execute.before")!({
    sessionID: "ses_child",
    tool: "engram_mem_save",
    input: write,
  })
  assert.equal((write as any).session_id, "ses_root")

  await toolHooks.get("execute.after")!({
    sessionID: "ses_child",
    tool: "subagent",
    status: "completed",
    result: { content: "A sufficiently long subagent result that should be captured as passive memory." },
  })
  const passive = requests.find((request) => request.path === "/observations/passive")
  assert.equal(passive?.body.session_id, "ses_root")

  const compaction = [{ type: "text", text: "compact" }]
  await sessionHooks.get("compaction")!({ sessionID: "ses_root", system: compaction })
  assert.match(compaction[0].text, /session-only memory/)

  events.push({ type: "session.created", data: { sessionID: "ses_root", projectID: "project-id" } })
  events.push({
    type: "session.created",
    data: { sessionID: "ses_child", parentID: "ses_root", projectID: "project-id" },
  })
  events.push({ type: "session.deleted", data: { sessionID: "ses_child" } })
  await Bun.sleep(10)
  assert.equal(
    requests.filter((request) => request.path === "/sessions/ses_root/end").length,
    0,
    "deleting a child must not close its root",
  )
  events.push({ type: "session.deleted", data: { sessionID: "ses_root" } })
  await Bun.sleep(10)
  assert.equal(requests.filter((request) => request.path === "/sessions/ses_root/end").length, 1)
  await cleanup()

  const v1Sessions = new Map([
    ["ses_v1", { id: "ses_v1", projectID: "v1-project" }],
  ])
  const v1 = await v1Plugin({
    directory: "/portable/v1-project",
    project: { id: "v1-project" },
    client: {
      session: {
        get: async ({ path }: any) => ({ data: v1Sessions.get(path.id) }),
      },
    },
  } as any)
  await v1.event({
    event: {
      type: "session.created",
      properties: { info: v1Sessions.get("ses_v1") },
    },
  })
  const v1Write = { args: {} }
  await v1["tool.execute.before"](
    { sessionID: "ses_v1", tool: "engram_mem_save" },
    v1Write,
  )
  assert.equal(v1Write.args.session_id, "ses_v1")
  await v1.dispose()

  console.log("PASS OpenCode V1/V2 Engram lifecycle checks")
} finally {
  globalThis.fetch = originalFetch
}
