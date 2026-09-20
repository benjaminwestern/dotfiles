---
type: Runbook
title: Local Engram memory
description: Operate, verify and back up local memory shared by coding clients.
tags: [engram, memory, workstation]
status: Active
---

# Local Engram memory

Engram is pinned through mise and stores local memory in
`~/.engram/engram.db`. Cloud autosync, Git sync and remote memory are disabled.
Files remain local, although a recalled memory becomes part of the requesting
model's context.

## Installed components

- OpenCode and Codex launch the pinned binary through `mise exec`, avoiding
  operating-system-specific executable paths.
- `engram-context.py` resolves private organisation workspaces without embedding
  their names or paths in this repository.
- `engram-backup.py` exports all projects to a private timestamped backup.
- `AGENTS.md` defines shared scope and recall policy for coding clients.
- `opencode/plugins/engram/` is a Node-based OpenCode V2 server plugin, with an
  adjacent `engram.ts` shim for V1. It serves Desktop, CLI and TUI clients. MCP
  access works without it, but prompt capture, session registration, passive
  capture and compaction context do not.

## Private organisation registry

Store organisation mappings in `~/.engram/organisations.tsv` with mode `600`.
Use one tab-separated row per workspace:

```text
# name<TAB>project<TAB>workspace root
example<TAB>org-example<TAB>~/code/work/example-repos
```

Replace each `<TAB>` marker with a tab character. Override the file location with
`ENGRAM_ORGANISATIONS_FILE`. Keep the real registry outside Git.

The resolver matches the working directory first, then follows linked-worktree
Git metadata back to the primary checkout. It never infers ownership from a
repository basename or remote URL.

## Verify operation

```sh
mise ls github:Gentleman-Programming/engram
engram version
engram doctor
engram projects list
engram stats --all
engram cloud status
python ~/.local/bin/engram-context.py <directory>
codex mcp get engram --json
opencode2 mcp list
opencode2 plugin list
python ~/.dotfiles/engram/test-context.py
bun ~/.dotfiles/engram/test-opencode-plugin.ts
```

Restart clients after changing global instructions, MCP configuration or the
OpenCode plugin. Existing sessions may retain their previous instructions and
MCP processes.

## Back up and upgrade

Back up before an Engram upgrade or bulk import:

```sh
python ~/.local/bin/engram-backup.py
```

The helper writes a mode-`600` full export under `~/.engram/backups/`. Test a
restore against a separate temporary `ENGRAM_DATA_DIR` before merging it into
the live store.

For an upgrade:

1. Install and test the candidate version separately.
2. Update the version in `mise/config.toml`, `opencode/opencode.json`, the
   OpenCode plugin and `configure-clients.py` together.
3. Run `python3 ~/.dotfiles/engram/configure-clients.py`.
4. Restart the local service and verify MCP and plugin status in an ordinary
   disposable session.

The helper owns the local Codex and OpenCode MCP launch settings. Native Engram
setup is not required and may write legacy or non-canonical client settings.

## Private imports

Keep source archives, candidate facts, project registries, provenance and
one-off import tooling under `~/.engram/imports/`. Do not commit organisation
names, source paths, raw conversations or review queues to this repository.
