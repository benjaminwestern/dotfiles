/** OpenCode V1 compatibility shim; V2 loads the configured package directory. */

import plugin from "./engram/index.ts"

export const Engram = plugin.server

export default {
  id: "engram.lifecycle.v1",
  setup() {},
  server: plugin.server,
}
