# Bootstrap Refactor TODO

Tracking the current state of the bootstrap refactor. The two-layer
architecture is implemented on macOS and Windows, with public loaders at the
repo root and repo-local platform bootstrap logic under `Other/scripts`. This
document captures what is done and what remains.

## Completed

- Public entrypoints (`install.sh` and `install.cmd`) with full flag parsing for
  modes
  (`setup`, `ensure`, `update`, `personal`), shell choice, device profiles, and
  personal layer enablement
- macOS foundation (`foundation-macos.zsh`) with feature flags, gum-driven
  status output, shell choice, Zscaler trust detection, and ensure-style
  validation
- macOS personal layer (`personal-bootstrap-macos.zsh`) with flag-driven
  execution of dotfiles checkout, brew bundle, tuckr, shell default, macOS
  defaults, and Rosetta targets
- Shared zsh library (`lib/common.zsh`) with state file management
  (`~/.config/dotfiles/state.env`), six-level resolution precedence chain,
  device profile presets, gum-based interactive prompts, and status output
- Windows foundation (`foundation-windows.ps1`) with real Scoop implementation,
  Zscaler trust detection, code signing certificate management, and
  work/home/minimal mode differentiation
- Shared PowerShell library (`lib/common.ps1`) for Windows state management and
  resolution
- Brewfile GUI conditional gated by `ENABLE_GUI` feature flag
- Legacy `macos-bootstrap.sh` retired and replaced by the two-layer architecture
- `macos-defaults.sh` cleaned up and integrated as a personal layer target
- Pre-flight inventory (`preflight_inventory()`) snapshots machine state before
  any changes — tool availability, shell state, macOS specifics, config state,
  and runtime versions via `PREFLIGHT_*` globals
- Dry-run mode (`--dry-run`) for previewing the full bootstrap pipeline without
  making changes — all destructive commands wrapped in `run_or_dry()`, status
  output uses "would ..." phrasing, pre-flight and validation still run normally
- Standalone macOS audit script (`audit-macos.zsh`) with section filtering
  (`--section tools|shell|configs|personal`) and JSON output (`--json`); also
  accessible via `install.sh audit`
- Tested dry-run and audit on a live macOS machine — both run cleanly with
  correct pass/fix/skip/fail status output
- Windows audit script (`audit-windows.ps1`) with section filtering
  (`-Section tools|shell|configs|signing|zscaler`) and JSON output (`-Json`);
  covers Scoop, mise, execution policy, code signing health, Zscaler trust,
  and cert-sensitive tool validation
- Mise separated from foundation package lists on both macOS and Windows —
  dedicated `ensure_mise()` / `Ensure-Mise` handles dual install path
  (Homebrew/Scoop or shell installer) with correct signing under AllSigned
- Windows personal layer (`personal-bootstrap-windows.ps1`) with real target
  implementations: dotfiles repo clone/pull, git config copy, SSH config copy,
  mise config copy (config.toml + .env + scripts), opencode config copy
  (opencode.json + plugins), PowerShell profile extras via managed block
  (navigation aliases, git aliases, zoxide/fzf/starship integrations). All
  targets are flag-gated, idempotent (SHA256 hash comparison before copy),
  and emit proper Write-Status* output
- Windows dry-run mode (`-DryRun`) across all Windows scripts — `Invoke-OrDry`
  and `Test-DryRun` in `lib/common.ps1`, all destructive operations in
  `foundation-windows.ps1` and `personal-bootstrap-windows.ps1` gated, status
  output uses "would ..." phrasing, `Write-ManagedBlock` dry-run aware,
  `install.cmd` threads `-DryRun` into the repo-local Windows bootstrap
- Windows audit state population (`-PopulateState` on `audit-windows.ps1`) —
  discovers machine state (shell, profile, Zscaler, mise) and writes to
  `~/.config/dotfiles/state.env` so bootstrap can use detected values as
  baseline without re-prompting
- Windows first-run bootstrap chain implemented end to end:
  `install.cmd` → `bootstrap-windows.cmd` → `windows-precursor.ps1` →
  `foundation-windows.ps1` / `audit-windows.ps1`
- Windows signing repair path implemented via `resign-windows.cmd` and
  `resign-windows.ps1`
- Real Windows validation completed for:
  - `audit-windows.ps1`
  - `audit-windows.ps1 -Json`
  - `foundation-windows.ps1 -Mode ensure -NonInteractive -DryRun`
  - `foundation-windows.ps1 -Mode update -NonInteractive -DryRun`
  - `foundation-windows.ps1 -Mode ensure -NonInteractive`
  - final verification audit after foundation

## Remaining

- Test `foundation-macos.zsh` on a real bare Mac and tighten the script based
  on actual output and validation results
- Test `personal-bootstrap-windows.ps1` on a real Windows machine
- Linux foundation (not started)
- CI/CD pipeline for bootstrap testing on ephemeral VMs
