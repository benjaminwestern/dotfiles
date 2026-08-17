# Noctalia configuration

This directory contains the curated, cross-machine Noctalia configuration and
is deployed to `~/.config/noctalia` by mise's Linux dotfile mapping.

Noctalia loads and merges every top-level `*.toml` file in this directory. The
configuration is split by concern so bar and widget experiments remain easy to
review:

- `config.toml` controls shell behavior and services.
- `bar.toml` controls bar geometry and layout.
- `theme.toml` controls the Noctalia palette and the existing app templates.
- `widgets.toml` controls individual bar widgets.

## Ownership boundaries

Do not copy `~/.local/state/noctalia` into this repository. It contains
GUI-managed overrides, monitor-specific layout, histories, caches, and runtime
state. Noctalia loads `settings.toml` from that directory after these files, so
machine-local GUI experiments can override the curated base safely.

Generated theme outputs such as `noctalia.css`, `noctalia.conf`, and
`noctalia.theme` also remain untracked. Track custom palette and template source
files here when they are introduced, not their generated outputs.

Ghostty is intentionally not included in Noctalia's app-template list. Its
cross-platform configuration remains owned by the existing Ghostty dotfiles.

Validate the effective configuration with:

```sh
noctalia config validate
```

Use `noctalia config export merged` to inspect GUI overrides before promoting
selected settings into these files.
