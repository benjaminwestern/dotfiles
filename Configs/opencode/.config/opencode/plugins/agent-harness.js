import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { fileURLToPath } from "node:url"

const pluginFile = fileURLToPath(import.meta.url)
const pluginRealPath = safeRealPath(pluginFile) ?? pluginFile
const defaultHelperArgs = ["--runtime", "opencode", "--provenance", "native_plugin"]

const forwardedEvents = new Set([
  "session.created",
  "session.status",
  "session.idle",
  "session.error",
  "permission.asked",
  "permission.replied",
])

function safeRealPath(target) {
  try {
    return fs.realpathSync(target)
  } catch {
    return undefined
  }
}

function pick(value, ...segments) {
  let current = value
  for (const segment of segments) {
    if (current == null || typeof current !== "object") return undefined
    current = current[segment]
  }
  return current
}

function stringValue(value) {
  if (typeof value !== "string") return undefined
  return value.length > 0 ? value : undefined
}

function numberValue(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined
}

function firstString(...values) {
  for (const value of values) {
    const candidate = stringValue(value)
    if (candidate) return candidate
    if (Array.isArray(value)) {
      for (const item of value) {
        const arrayCandidate = stringValue(item)
        if (arrayCandidate) return arrayCandidate
      }
    }
  }
  return undefined
}

function firstNumber(...values) {
  for (const value of values) {
    const candidate = numberValue(value)
    if (candidate !== undefined) return candidate
  }
  return undefined
}

function helperArgs() {
  return {
    helperArgs: defaultHelperArgs,
  }
}

function harnessHome() {
  const configured = stringValue(process.env.AGENT_HARNESS_HOME)
  if (configured) return path.resolve(configured)
  return path.join(os.homedir(), ".agent-harnesses")
}

function helperConfigPath(directory) {
  if (directory) {
    const repoLocal = path.resolve(
      directory,
      ".agent-harnesses",
      "opencode",
      "plugin-config.json",
    )
    if (fs.existsSync(repoLocal)) return repoLocal
  }

  return path.join(harnessHome(), "opencode", "plugin-config.json")
}

function helperConfig(directory) {
  try {
    const text = fs.readFileSync(helperConfigPath(directory), "utf8")
    const config = JSON.parse(text)
    const helperPath = stringValue(config?.helperPath)
    const helperArgs = Array.isArray(config?.helperArgs)
      ? config.helperArgs.filter((item) => typeof item === "string")
      : defaultHelperArgs
    return { helperPath, helperArgs }
  } catch {
    return helperArgs()
  }
}

function helperBinaryPath(directory, helperPath) {
  if (helperPath) return helperPath
  if (directory) {
    return path.resolve(directory, ".agent-harnesses", "opencode", "bin", "agent_harness")
  }
  return path.join(harnessHome(), "bin", "agent_harness")
}

function helperInvocation(directory) {
  const config = helperConfig(directory)
  const binary = helperBinaryPath(directory, config.helperPath)
  if (!fs.existsSync(binary)) return undefined
  return [binary, ...config.helperArgs]
}

function hasProjectLocalOverride(directory) {
  const projectPlugin = safeRealPath(
    path.resolve(directory, ".opencode", "plugins", "agent-harness.js"),
  )
  return projectPlugin !== undefined && projectPlugin !== pluginRealPath
}

async function emit(payload) {
  const spawnArgs = helperInvocation(payload.cwd)
  if (!spawnArgs) return
  const proc = Bun.spawn(spawnArgs, {
    env: process.env,
    stdin: new Blob([JSON.stringify(payload)]).stream(),
    stdout: "ignore",
    stderr: "ignore",
  })
  await proc.exited
}

function eventEnvelope(event, directory, worktree) {
  const properties = pick(event, "properties")
  return {
    hook_event_name: event?.type ?? "runtime.event",
    event,
    cwd: directory,
    worktree,
    session_id: firstString(
      pick(properties, "sessionID"),
      pick(properties, "info", "id"),
    ),
    turn_id: firstString(
      pick(properties, "tool", "messageID"),
    ),
    tool_call_id: firstString(
      pick(properties, "tool", "callID"),
    ),
    tool_name: firstString(
      pick(properties, "permission"),
    ),
    command: firstString(
      pick(properties, "metadata", "command"),
      pick(properties, "patterns"),
    ),
    title: firstString(
      pick(properties, "info", "title"),
    ),
    reason: firstString(
      pick(properties, "reply"),
      pick(properties, "error", "type"),
      pick(properties, "error", "message"),
    ),
  }
}

function toolEnvelope(hookEventName, input, output, directory, worktree) {
  return {
    hook_event_name: hookEventName,
    input,
    output,
    cwd: directory,
    worktree,
    session_id: firstString(input?.sessionID),
    tool_call_id: firstString(input?.callID),
    tool_name: firstString(input?.tool),
    command: firstString(
      pick(output, "args", "command"),
      pick(input, "args", "command"),
    ),
    title: firstString(output?.title),
    reason: firstString(
      pick(output, "metadata", "error"),
      pick(output, "output"),
    ),
    exit_code: firstNumber(
      pick(output, "metadata", "exitCode"),
      pick(output, "metadata", "exit_code"),
    ),
  }
}

export const AgentHarnessPlugin = async ({ directory, worktree }) => {
  if (hasProjectLocalOverride(directory)) {
    return {}
  }

  return {
    event: async ({ event }) => {
      if (!forwardedEvents.has(event?.type)) return
      await emit(eventEnvelope(event, directory, worktree))
    },
    "tool.execute.before": async (input, output) => {
      await emit(toolEnvelope("tool.execute.before", input, output, directory, worktree))
    },
    "tool.execute.after": async (input, output) => {
      await emit(toolEnvelope("tool.execute.after", input, output, directory, worktree))
    },
  }
}
