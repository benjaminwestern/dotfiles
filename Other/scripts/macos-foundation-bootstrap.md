# macOS foundation bootstrap

This runbook describes the current macOS bootstrap architecture as it exists in
this repository. It covers the public loader, the repo-local foundation script,
the shell and `mise` activation model, Zscaler trust handling, and the
relationship between the foundation and personal layers.

The goal is a repeatable macOS foundation that can be shared across machines,
re-run safely, and extended later by the personal bootstrap.

## Quick start

Use the public loader for normal setup, ensure, update, and audit runs. It
reuses `~/.dotfiles` when present, clones it when missing, and can run once
from a temporary GitHub archive when `git` is unavailable.

```bash
# Remote bootstrap
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh \
  | bash -s -- setup --shell fish --profile work --personal

# Local checkout bootstrap
git clone https://github.com/benjaminwestern/dotfiles ~/.dotfiles
~/.dotfiles/install.sh setup --shell fish --profile work --personal

# Minimal or repair flows
~/.dotfiles/install.sh setup --shell zsh --profile minimal --non-interactive
~/.dotfiles/install.sh ensure --personal
~/.dotfiles/install.sh update
~/.dotfiles/install.sh audit --json
```

The public loader is the supported entrypoint. Direct invocation of
`foundation-macos.zsh` is available for local testing and advanced recovery, but
it does not replace the convenience of `install.sh`.

## Entry points

The macOS bootstrap uses a simpler two-layer shape than the Windows path.

- `install.sh` is the public loader. It resolves the working checkout, parses
  the public flags, and delegates into the repo-local macOS scripts.
- `Other/scripts/foundation-macos.zsh` is the repo-local macOS foundation
  orchestrator. It owns Homebrew, the baseline package set, `mise`, managed
  shell activation, Zscaler trust, `mise` tool installation, and validation.
- `Other/scripts/personal-bootstrap-macos.zsh` is the repo-specific personal
  layer. It owns the full Brewfile reconciliation, Tuckr symlinking, shell
  default changes, macOS defaults, and Rosetta.
- `Other/scripts/audit-macos.zsh` is the read-only machine audit.

Unlike the Windows path, macOS does not need a CMD wrapper or a PowerShell
precursor bridge. The public loader can call the repo-local `zsh` scripts
directly.

## Foundation behaviour

The macOS foundation runs in a fixed order:

1. Ensure Homebrew exists.
2. Activate Homebrew in the current shell.
3. Ensure the macOS foundation package set is present.
4. Ensure `mise` is installed, preferring Homebrew and falling back to the
   first-party shell installer.
5. Write or repair the managed shell activation block.
6. Activate the current shell session.
7. Create or update the managed `mise` seed config.
8. Detect Zscaler via TLS probe and repair trust if required.
9. Run `mise install` when `ENABLE_MISE_TOOLS=true`.
10. Validate the resulting foundation.
11. Optionally hand off to the personal layer when `--personal` is set.

The macOS foundation package list is:

- `git`
- `gh`
- `jq`
- `yq`
- `fzf`
- `fd`
- `ripgrep`
- `zoxide`
- `lazygit`
- `openssl`
- `gum`

`mise` is managed separately because it can be installed by Homebrew or by the
first-party shell installer.

## Shell behaviour

The macOS foundation supports both `zsh` and `fish` as the managed interactive
shell targets. The chosen value comes from `--shell`, the environment, the
state file, the selected profile, or the interactive prompt flow.

The foundation writes or repairs a managed activation block for the resolved
shell:

- `zsh` receives a managed block in `~/.zshrc`.
- `fish` receives a managed block in the appropriate `conf.d` file.

That managed block activates Homebrew, `mise`, and `zoxide` in new shells. The
foundation does not change the account's default login shell. Default-shell
changes belong to the personal layer and remain gated by
`ENABLE_SHELL_DEFAULT`.

## Mise behaviour

The macOS foundation creates or updates a managed `mise` seed block in
`~/.config/mise/config.toml`. The current seed includes:

- `go`
- `node`
- `bun`
- `python`
- `uv`
- `zig`
- `terraform`
- `gcloud`
- `usage`
- `pkl`
- `hk`
- `fnox`
- `go:oss.terrastruct.com/d2`
- `go:github.com/charmbracelet/glow`
- `go:github.com/charmbracelet/freeze`
- `go:github.com/charmbracelet/vhs`
- `npm:opencode-ai`
- `npm:@playwright/cli`

When `ENABLE_MISE_TOOLS=true`, the foundation runs `mise install` after the
seed config and Zscaler trust are in place.

## Zscaler and TLS trust

The macOS foundation can detect and configure Zscaler trust without requiring a
separate manual path.

- Detection uses `openssl s_client` against `registry.npmjs.org` and inspects
  the issuer for Zscaler evidence.
- When Zscaler is active, the foundation captures the certificate chain into
  `~/certs/zscaler_chain.pem`.
- It then builds `~/certs/golden_pem.pem`, writes the managed Zscaler block to
  `~/.config/mise/.env`, re-activates the current shell, and validates that the
  trust bundle works for the relevant tools.

That sequencing is important. The trust bundle needs to exist before
`mise install` when your network requires TLS interception to reach external
registries.

## Managed outputs

The macOS foundation writes and maintains a small set of managed files and
settings.

- `~/.config/dotfiles/state.env` stores resolved preferences and discovered
  state for later runs.
- The managed shell activation block keeps Homebrew, `mise`, and `zoxide`
  active in future shells.
- `~/.config/mise/config.toml` receives the managed `mise` seed block.
- `~/.config/mise/.env` receives the managed Zscaler environment block when
  Zscaler trust is enabled.
- `~/certs/zscaler_chain.pem` and `~/certs/golden_pem.pem` store the generated
  trust material when Zscaler is active.

## Personal layer handoff

The macOS personal layer is optional and runs only when `--personal` is set.
It builds on a healthy foundation and owns:

- full Brewfile reconciliation
- Tuckr symlink application
- default-shell changes
- macOS defaults
- Rosetta installation on Apple Silicon

That separation is deliberate. The foundation remains shareable and
machine-safe, while the personal layer carries repository-specific workstation
preferences.

## Audit and validation

Use the macOS audit when you want a read-only view of the current machine
state.

```bash
~/.dotfiles/install.sh audit
~/.dotfiles/install.sh audit --section configs
~/.dotfiles/install.sh audit --json

# Repo-local direct invocation
./Other/scripts/audit-macos.zsh --section tools
```

The audit covers tool state, shell state, config state, and personal-layer
state. A healthy machine should show Homebrew available, the foundation package
set present, `mise` active, and the managed shell block in place.

## Advanced direct commands

Use `install.sh` for normal operations. Use these direct commands when you need
explicit control of the repo-local scripts.

```bash
# Repo-local foundation flows
./Other/scripts/foundation-macos.zsh setup --shell zsh --profile work
./Other/scripts/foundation-macos.zsh ensure --shell fish --profile home
./Other/scripts/foundation-macos.zsh update --non-interactive

# Repo-local audit
./Other/scripts/audit-macos.zsh --json
```

The repo-local scripts accept the same broad operating modes as `install.sh`,
but the public loader remains the default recommendation because it also handles
repo resolution on a fresh machine.
