/** Inject mise's project environment into OpenCode shell commands. */

import { execFile } from "node:child_process"
import { promisify } from "node:util"

const execFileAsync = promisify(execFile)
const CACHE_TTL_MS = 5000
const cache = new Map<string, { env: Record<string, string>; at: number }>()

async function miseEnvironment(cwd: string): Promise<Record<string, string> | undefined> {
  const cached = cache.get(cwd)
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) return cached.env
  try {
    const result = await execFileAsync("mise", ["env", "--json"], {
      cwd,
      windowsHide: true,
      maxBuffer: 1024 * 1024,
    })
    const parsed = JSON.parse(result.stdout) as Record<string, unknown>
    const env = Object.fromEntries(
      Object.entries(parsed)
        .filter((entry): entry is [string, string | number | boolean] => (
          entry[1] !== undefined && entry[1] !== null
        ))
        .map(([key, value]) => [key, String(value)]),
    )
    cache.set(cwd, { env, at: Date.now() })
    return env
  } catch {
    return undefined
  }
}

async function setupV2(context: any): Promise<void> {
  await context.shell.hook("create.before", async (event: any) => {
    const env = await miseEnvironment(event.cwd)
    if (env) Object.assign(event.env, env)
  })
}

async function setupV1(): Promise<Record<string, any>> {
  return {
    "shell.env": async (input: any, output: any) => {
      const env = await miseEnvironment(input.cwd)
      if (env) Object.assign(output.env, env)
    },
  }
}

export default {
  id: "mise.environment",
  setup: setupV2,
  server: setupV1,
}
