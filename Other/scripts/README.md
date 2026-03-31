# Bootstrap scripts

This directory contains the repo-local bootstrap, audit, and repair scripts
for macOS and Windows. Use the public loaders at the repository root by
default. This README is the single source of truth for the bootstrap contract,
the files that perform work on each platform, the supported flags, and the
end-to-end flow. It replaces the old per-platform runbooks.

## Naming convention

The repo-local script names use the Windows layout as the baseline. Shared
workflows use the same purpose-first, OS-suffixed pattern on both platforms:
`bootstrap-<os>`, `foundation-<os>`, `personal-bootstrap-<os>`, and
`audit-<os>`. On Windows, the operator-facing entrypoints use `.cmd`, and the
implementation files use `.ps1` with the same base name. Windows-only repair
and helper files keep the `-windows` suffix. The root `install.sh` and
`install.cmd` keep their historical names because they are the public remote
entrypoints.

Use this matrix as the canonical map of script names:

| Purpose | macOS entrypoint | Windows entrypoint | Windows implementation |
| --- | --- | --- | --- |
| Public loader | [`install.sh`](../../install.sh) | [`install.cmd`](../../install.cmd) | Not needed |
| Repo-local bootstrap | [`bootstrap-macos.zsh`](bootstrap-macos.zsh) | [`bootstrap-windows.cmd`](bootstrap-windows.cmd) | Not needed |
| Foundation | [`foundation-macos.zsh`](foundation-macos.zsh) | [`foundation-windows.cmd`](foundation-windows.cmd) | [`foundation-windows.ps1`](foundation-windows.ps1) |
| Personal layer | [`personal-bootstrap-macos.zsh`](personal-bootstrap-macos.zsh) | [`personal-bootstrap-windows.cmd`](personal-bootstrap-windows.cmd) | [`personal-bootstrap-windows.ps1`](personal-bootstrap-windows.ps1) |
| Audit | [`audit-macos.zsh`](audit-macos.zsh) | [`audit-windows.cmd`](audit-windows.cmd) | [`audit-windows.ps1`](audit-windows.ps1) |
| Repair | Not needed | [`resign-windows.cmd`](resign-windows.cmd) | [`resign-windows.ps1`](resign-windows.ps1) |
| OS-specific helpers | [`defaults-macos.sh`](defaults-macos.sh), [`lib/common.zsh`](lib/common.zsh) | [`lib/common.ps1`](lib/common.ps1), [`lib/windows-precursor.ps1`](lib/windows-precursor.ps1), [`lib/signing-helpers-windows.ps1`](lib/signing-helpers-windows.ps1) | Top-level [`signing-helpers-windows.ps1`](signing-helpers-windows.ps1) remains only as a compatibility shim |

## Public entrypoints

Start with the public loaders on a fresh machine. They make sure the dotfiles
repo exists locally before they hand off to the repo-local scripts in this
directory.

| Platform | File | Purpose | Help |
| --- | --- | --- | --- |
| macOS | [`install.sh`](../../install.sh) | Public loader for setup, ensure, update, personal, and audit | `./install.sh --help` |
| Windows | [`install.cmd`](../../install.cmd) | Public loader for setup, ensure, update, personal, and audit | `.\install.cmd --help` |

Use the repo-local entrypoints only when you need explicit control of the
platform scripts or when you are debugging a failed run.

## Supported modes

The public loaders share the same high-level operating modes across both
platforms.

| Mode | Effect |
| --- | --- |
| `setup` | Run the full foundation flow and optionally hand off to the personal layer |
| `ensure` | Re-run idempotently and repair drift |
| `update` | Upgrade package-manager-managed state, then re-run ensure |
| `personal` | Run only the repo-specific personal layer |
| `audit` | Run the read-only machine audit |

## Shared contract

Both platforms follow the same operating model even though the implementation
details differ.

- State file: `~/.config/dotfiles/state.env`
- Resolution precedence: CLI flag, environment variable, state file, device
  profile preset, interactive prompt, then hard-coded default
- Dry-run: prints what would change without making destructive changes
- Profiles: `work`, `home`, and `minimal`
- First-run recommendation: use the public loader, not a direct repo-local
  script invocation

## macOS flow

The macOS bootstrap is a direct `zsh` flow. It does not need an intermediate
wrapper or shell-version bridge.

### Files that perform the macOS work

These are the files that actually implement the macOS bootstrap behavior.

- [`install.sh`](../../install.sh) parses the public CLI, resolves or clones
  the repo, exports flags, and dispatches to the repo-local scripts.
- [`bootstrap-macos.zsh`](bootstrap-macos.zsh) is the repo-local macOS
  entrypoint. It dispatches to the foundation, audit, or personal scripts.
- [`foundation-macos.zsh`](foundation-macos.zsh) applies the shared macOS
  foundation: Homebrew, foundation packages, `mise`, managed shell activation,
  Zscaler trust, `mise` tools, and validation.
- [`personal-bootstrap-macos.zsh`](personal-bootstrap-macos.zsh) applies the
  repo-specific macOS layer: Brewfile reconciliation, Tuckr, default shell,
  macOS defaults, and Rosetta.
- [`audit-macos.zsh`](audit-macos.zsh) reports current macOS machine state
  without modifying it.
- [`defaults-macos.sh`](defaults-macos.sh) applies macOS system settings when
  the personal layer enables that step.
- [`lib/common.zsh`](lib/common.zsh) provides shared state management,
  resolution, dry-run gating, interactive prompts, status output, and managed
  block helpers.

### End-to-end macOS flow

This is the execution order for a normal macOS bootstrap run.

1. [`install.sh`](../../install.sh) parses the requested mode and flags, then
   ensures the repo is present locally.
2. It delegates to [`bootstrap-macos.zsh`](bootstrap-macos.zsh).
3. For `setup`, `ensure`, and `update`,
   [`bootstrap-macos.zsh`](bootstrap-macos.zsh) dispatches to
   [`foundation-macos.zsh`](foundation-macos.zsh).
4. [`foundation-macos.zsh`](foundation-macos.zsh) sources
   [`lib/common.zsh`](lib/common.zsh), resolves all flags, applies the macOS
   foundation, and optionally calls
   [`personal-bootstrap-macos.zsh`](personal-bootstrap-macos.zsh) when
   `--personal` is set.
5. For `personal`, [`bootstrap-macos.zsh`](bootstrap-macos.zsh) runs
   [`personal-bootstrap-macos.zsh`](personal-bootstrap-macos.zsh) directly.
6. For `audit`, [`bootstrap-macos.zsh`](bootstrap-macos.zsh) runs
   [`audit-macos.zsh`](audit-macos.zsh) directly.

### macOS options

These are the public options that matter when you run the macOS loader.

The macOS public loader accepts these options:

- `--shell <fish|zsh>`
- `--profile <work|home|minimal>`
- `--enable-<flag>`
- `--disable-<flag>`
- `--personal`
- `--non-interactive`
- `--dry-run`
- `--dotfiles-repo <url>`
- `--dotfiles-dir <path>`
- `--personal-script <path>`

The macOS feature flags are:

- `zscaler`
- `work-apps`
- `home-apps`
- `gui`
- `tuckr`
- `macos-defaults`
- `rosetta`
- `mise-tools`
- `shell-default`

### Direct macOS help

The repo-local macOS scripts also expose their own direct help surfaces.

```bash
./Other/scripts/bootstrap-macos.zsh --help
./Other/scripts/foundation-macos.zsh --help
./Other/scripts/personal-bootstrap-macos.zsh --help
./Other/scripts/audit-macos.zsh --help
```

## Windows flow

The Windows bootstrap has one extra layer because it must be safe on machines
that still start in Windows PowerShell 5.x or under an effective `AllSigned`
policy.

### Files that perform the Windows work

These are the files that implement the Windows bootstrap behavior. The `.cmd`
files are the supported operator-facing entrypoints. The `.ps1` files are the
implementation layer they protect.

- [`install.cmd`](../../install.cmd) parses the public CLI, resolves or clones
  the repo, exports flags, and delegates into the repo-local Windows wrapper.
- [`bootstrap-windows.cmd`](bootstrap-windows.cmd) is the first-run-safe
  repo-local Windows entrypoint. It ensures the local signing certificate
  exists, signs the repo-local `.ps1` files, and launches the selected target.
- [`foundation-windows.cmd`](foundation-windows.cmd),
  [`audit-windows.cmd`](audit-windows.cmd),
  [`personal-bootstrap-windows.cmd`](personal-bootstrap-windows.cmd), and
  [`resign-windows.cmd`](resign-windows.cmd) are the single-purpose Windows
  entrypoints. They all route through [`bootstrap-windows.cmd`](bootstrap-windows.cmd).
- [`lib/windows-precursor.ps1`](lib/windows-precursor.ps1) bridges Windows
  PowerShell 5.x to PowerShell 7 by ensuring Scoop and `pwsh` exist and then
  re-running the same target under `pwsh`.
- [`foundation-windows.ps1`](foundation-windows.ps1) applies the shared
  Windows foundation: Scoop, foundation packages, `mise`, managed PowerShell
  profile activation, Windows Terminal defaults, Zscaler trust, and
  validation.
- [`personal-bootstrap-windows.ps1`](personal-bootstrap-windows.ps1) applies
  the repo-specific Windows layer: dotfiles checkout, Git config, SSH config,
  `mise` config, Opencode config, and PowerShell profile extras.
- [`audit-windows.ps1`](audit-windows.ps1) reports current Windows machine
  state, including outdated foundation Scoop packages and outdated `mise`
  tools, without modifying it.
- [`resign-windows.ps1`](resign-windows.ps1) repairs signing drift after
  updates or local edits.
- [`lib/signing-helpers-windows.ps1`](lib/signing-helpers-windows.ps1)
  provides the shared local certificate and signing helpers used by
  foundation, audit, and repair.
- [`signing-helpers-windows.ps1`](signing-helpers-windows.ps1) is a
  compatibility shim for older profile blocks and local imports.
- [`lib/common.ps1`](lib/common.ps1) provides shared state management,
  resolution, dry-run gating, status output, Windows Terminal helpers, and
  managed block helpers.

### End-to-end Windows flow

This is the execution order for a normal Windows bootstrap run.

1. [`install.cmd`](../../install.cmd) parses the requested mode and flags, then
   ensures the repo is present locally.
2. For normal Windows operations, it delegates to
   [`bootstrap-windows.cmd`](bootstrap-windows.cmd). The single-purpose
   wrappers such as [`foundation-windows.cmd`](foundation-windows.cmd) and
   [`audit-windows.cmd`](audit-windows.cmd) also delegate there.
3. [`bootstrap-windows.cmd`](bootstrap-windows.cmd) creates or reuses
   `LocalScoopSigner`, signs the repo-local Windows PowerShell scripts, and
   launches the selected `.ps1` target.
4. [`foundation-windows.ps1`](foundation-windows.ps1) and
   [`audit-windows.ps1`](audit-windows.ps1) immediately load
   [`lib/windows-precursor.ps1`](lib/windows-precursor.ps1).
5. If the current host is still Windows PowerShell 5.x, the precursor ensures
   Scoop exists, ensures `pwsh` exists, then re-runs the same target under
   PowerShell 7.
6. Once the target is running in `pwsh`,
   [`foundation-windows.ps1`](foundation-windows.ps1) applies the Windows
   foundation. When `--personal` is set, it hands off to
   [`personal-bootstrap-windows.ps1`](personal-bootstrap-windows.ps1).
7. For `audit`, the wrapper runs
   [`audit-windows.ps1`](audit-windows.ps1).
8. For manual signing repair, use
   [`resign-windows.cmd`](resign-windows.cmd). The wrapper enters
   [`resign-windows.ps1`](resign-windows.ps1) through the same protected path.

### Windows options

These are the public options that matter when you run the Windows loader.

The Windows public loader accepts these options:

- `--shell <pwsh>`
- `--profile <work|home|minimal>`
- `--enable-<flag>`
- `--disable-<flag>`
- `--personal`
- `--non-interactive`
- `--dry-run`
- `--dotfiles-repo <url>`
- `--dotfiles-dir <path>`
- `--personal-script <path>`
- `--section <name>` for `audit`
- `--json` for `audit`
- `--populate-state` for `audit`

The Windows foundation feature flags are:

- `zscaler`
- `mise-tools`

The Windows personal-layer feature flags are:

- `git-config`
- `ssh-config`
- `mise-config`
- `opencode-config`
- `profile-extras`

### Direct Windows help

Use these commands when you need help from the repo-local Windows entrypoints.

The repo-local Windows entrypoints expose both wrapper help and PowerShell
comment-based help. Use the `.cmd` commands for normal operations and
`Get-Help` only when you are inspecting the implementation layer directly.

```powershell
.\Other\scripts\bootstrap-windows.cmd --help
.\Other\scripts\foundation-windows.cmd --help
.\Other\scripts\audit-windows.cmd --help
.\Other\scripts\personal-bootstrap-windows.cmd --help
.\Other\scripts\resign-windows.cmd --help
Get-Help .\Other\scripts\foundation-windows.ps1 -Detailed
Get-Help .\Other\scripts\personal-bootstrap-windows.ps1 -Detailed
Get-Help .\Other\scripts\audit-windows.ps1 -Detailed
Get-Help .\Other\scripts\resign-windows.ps1 -Detailed
```

## Audit and repair entrypoints

Use the audit scripts when you want a read-only view of the current machine
state. Use the Windows re-sign flow when an `AllSigned` environment needs local
PowerShell wrappers to be signed again after updates.

- macOS audit: [`audit-macos.zsh`](audit-macos.zsh)
- Windows audit: [`audit-windows.cmd`](audit-windows.cmd) ->
  [`audit-windows.ps1`](audit-windows.ps1)
- Windows signing repair: [`resign-windows.cmd`](resign-windows.cmd) ->
  [`resign-windows.ps1`](resign-windows.ps1)

## Internal libraries

The platform scripts share small internal libraries instead of duplicating
common logic in every entrypoint.

- [`lib/common.zsh`](lib/common.zsh) is the shared macOS library.
- [`lib/common.ps1`](lib/common.ps1) is the shared Windows library.
- [`lib/windows-precursor.ps1`](lib/windows-precursor.ps1) handles the Windows
  PowerShell 5.x to PowerShell 7 bridge.
- [`lib/signing-helpers-windows.ps1`](lib/signing-helpers-windows.ps1)
  handles the local certificate and PowerShell signing helpers.

## Recommended operator paths

These are the normal entrypoints to use in practice.

```bash
# macOS
./install.sh --help
./install.sh setup --shell fish --profile work --personal
./install.sh audit --json
./Other/scripts/bootstrap-macos.zsh --help
```

```powershell
# Windows
.\install.cmd --help
.\install.cmd setup --profile work --personal
.\install.cmd audit --populate-state
.\Other\scripts\bootstrap-windows.cmd --help
.\Other\scripts\foundation-windows.cmd --help
.\Other\scripts\audit-windows.cmd --help
.\Other\scripts\personal-bootstrap-windows.cmd --help
.\Other\scripts\resign-windows.cmd --help
```

## FAQ

These are the operator questions that come up most often when the Windows
bootstrap contract looks unusual at first glance.

### Can I launch the Windows `.cmd` entrypoints from PowerShell or Windows PowerShell 5.1?

Yes. PowerShell can invoke the `.cmd` wrappers directly by path, for example
`& .\Other\scripts\foundation-windows.cmd -Mode ensure`. The wrapper then runs
under `cmd.exe`, which is exactly what the Windows bootstrap expects for the
first-hop launch path.

The main caveat is session scope. If a `.cmd` file changes environment
variables, those changes stay inside the child process and do not flow back
into the parent PowerShell session. That is acceptable here because the
Windows `.cmd` files are only bootstrap entrypoints. They launch the protected
PowerShell implementation, but they do not try to initialise your current
interactive session.

### Why does Windows keep both `.cmd` and `.ps1` files?

Windows uses `.cmd` as the operator-facing entrypoint layer and `.ps1` as the
implementation layer. This avoids a chicken-and-egg problem on fresh machines
or `AllSigned` machines where direct PowerShell execution may fail before the
local signing and PowerShell 7 precursor logic has run.

In practice, use the `.cmd` files for normal operation and use `Get-Help` on
the `.ps1` files only when you are inspecting or debugging the implementation.

## Roadmap

The bootstrap contract is in place on macOS and Windows. The remaining work is
mostly validation, automation, and the next platform expansion, not a rewrite
of the current two-layer design.

- Validate the macOS foundation flow on a true bare Mac and use those results
  to tighten pre-flight checks, validation, and repair paths.
- Validate the Windows personal layer on a real Windows machine so the repo
  copy, profile, SSH, Git, and config flows are proven outside dry-run paths.
- Add CI coverage on ephemeral macOS and Windows runners so `setup`, `ensure`,
  `update`, and `audit` stay exercised continuously.
- Add Linux only after the current macOS and Windows contract is stable enough
  to copy forward without creating a third naming or flow variant.

## TODO

These are the next concrete tasks to close against the roadmap above.

- Run [`foundation-macos.zsh`](foundation-macos.zsh) on a bare macOS machine
  and capture the validation gaps that need script changes.
- Run
  [`personal-bootstrap-windows.cmd`](personal-bootstrap-windows.cmd) end to
  end on a real Windows machine and fix any path, copy, or profile drift.
- Define the first CI matrix for [`install.sh`](../../install.sh),
  [`install.cmd`](../../install.cmd), and the direct audit and dry-run flows.
- When Linux starts, keep the same purpose-first naming contract used here so
  the next platform does not reintroduce naming drift.
