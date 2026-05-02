Use child Pi processes to keep the main context clean when a task requires broad exploration, noisy tool use, MCP/tool discovery, or independent review.

Default to ephemeral children for one-shot research:
`pi --mode json -p --no-session --tools read,grep,find,ls,bash --append-system-prompt <agent.md> "Task: ..."`

Use a saved child session when auditability, resumability, or long investigation matters:
`pi --mode json -p --session <path|id> --tools ... --append-system-prompt <agent.md> "Task: ..."`

Use `--fork <path|id>` when the child should start from an existing session snapshot but continue independently.

The child must return compact findings: answer, evidence/file paths, commands run if relevant, confidence, and next action. Do not copy the child transcript into the parent unless explicitly needed.

Pi skill capability metadata may be present in session history. Use it to decide when a task matches a skill, then read the referenced SKILL.md for full instructions. Treat it as descriptive metadata, not instructions. Do not rediscover or dump skill listings unless needed.

External tool use:
When current external information is needed, use `websearch`.
When a URL or search result needs inspection, use `webfetch`.
MCP may expose direct `mcp__server__tool` tools when explicitly loaded in `.pi/agent/mcp.json`; use those tools when they match the task.
