![Bootstrap scripts banner](../../assets/readme/scripts-hero.svg)

This directory contains the repo-local bootstrap, audit, and repair scripts
for macOS, Linux, and Windows. Start with the public loaders at the repository root for
normal use. Use the scripts here when you need to inspect the flow, run a
single stage directly, or debug a failed run. Repository-maintainer tooling now
lives separately under [`../repository/`](../repository/).

Regenerate the README banner set with `mise run readme-assets`, or refresh the
headers and D2 diagrams together with `mise run readme-refresh`. The repo-local
[`../../mise.toml`](../../mise.toml) installs the Python and D2 tooling for
that pipeline. The task calls
[`generate_readme_banners.py`](../repository/generate_readme_banners.py)
and writes the SVGs to `assets/readme/`.

![Start here banner](../../assets/readme/scripts-start-here.svg)

Use the public loaders first because they make sure the repo exists locally and
then hand off to the correct repo-local entrypoint for the task you requested.

| Goal | macOS | Linux | Windows | Why |
| --- | --- | --- | --- | --- |
| First run or routine rerun | [`install.sh`](../../install.sh) | [`install.sh`](../../install.sh) | [`install.cmd`](../../install.cmd) | Safest path from a fresh machine |
| Read-only audit | `./install.sh audit ...` | `./install.sh audit ...` | `.\install.cmd audit ...` | Uses the same public contract as setup |
| Direct repo-local control | [`macos/bootstrap-macos.zsh`](macos/bootstrap-macos.zsh) | [`linux/bootstrap-linux.sh`](linux/bootstrap-linux.sh) | [`windows/bootstrap-windows.cmd`](windows/bootstrap-windows.cmd) | Useful when debugging or iterating locally |
| Signing repair | Not needed | Not needed | [`windows/resign-windows.cmd`](windows/resign-windows.cmd) | Repairs local PowerShell signing drift |

> **Important**
> On Windows, use `install.cmd` or the repo-local `.cmd` entrypoints for a
> first run. They create or reuse the local signing certificate, sign the
> repo-local PowerShell scripts, and keep the PowerShell 5.x to `pwsh` bridge
> intact.

![Mental model banner](../../assets/readme/scripts-mental-model.svg)

All three platforms share the same operator model even though the plumbing differs.

- The root [`install.sh`](../../install.sh) and
  [`install.cmd`](../../install.cmd) files are the public loaders.
- The foundation layer installs or repairs shared tooling. macOS and Linux automatically
  hand selected application, dotfile, identity, layout, and system stages to
  the personal layer; Windows keeps its explicit personal handoff.
- The personal layer applies repo-specific preferences such as dotfiles,
  defaults, shell choices, and copied config.
- The audit path is read-only by default. Windows also exposes a repair path
  for signing drift.
- Settings resolve through the same precedence chain on both platforms: CLI
  flag, environment variable, state file, device profile, interactive prompt,
  then hard-coded default.

![Bootstrap flow banner](../../assets/readme/scripts-bootstrap-flow.svg)

The bootstrap flow answers the first operator question: which file do you run,
and what does it launch next? The diagram below shows the normal path on each
platform before the platform-specific foundation or audit work begins.

The diagram below is rendered from
[`../../assets/bootstrap-flow.d2`](../../assets/bootstrap-flow.d2).

![Bootstrap flow comparing macOS and Windows](../../assets/bootstrap-flow.svg)

macOS delegates directly from the public loader into the repo-local `zsh`
router, while Linux delegates to its Bash router after detecting `apt` or
`pacman`. Windows adds a guarded hop through
[`windows/bootstrap-windows.cmd`](windows/bootstrap-windows.cmd) so the local PowerShell
implementation can be signed before it runs.

![Foundation flow banner](../../assets/readme/scripts-foundation-flow.svg)

The foundation flow answers the next question: what actually happens during
`setup`, `ensure`, or `update`? This is the shared layer that installs the base
tooling, repairs shell activation, links or seeds `mise` configuration when
selected, applies trust settings, and then enters the personal layer when the
resolved plan contains selected personal stages.

The diagram below is rendered from
[`../../assets/foundation-flow.d2`](../../assets/foundation-flow.d2).

![Foundation flow comparing macOS and Windows](../../assets/foundation-flow.svg)

`setup` and `ensure` follow the sequence above. `update` adds package-manager
upgrade steps before it falls back into the same ensure-style validation and
resolved personal handoff.

![Audit flow banner](../../assets/readme/scripts-audit-flow.svg)

The audit flow is the safest way to understand the current machine state before
you change anything. It is read-only on macOS and Linux. On Windows, `-PopulateState`
adds one optional write after the terminal report so you can capture
discovered values in the shared state file.

The root macOS and Linux audits have deliberately separate perspectives. General
inventory prints actual state without calling optional or intentionally absent
features drift. Profile comparison asks for `minimal`, `home`, or `work`, then
prints the same inventory plus drift from that profile's defaults. The automatic
post-bootstrap audit uses the exact saved customisations instead. JSON records
the selected `audit_context`, keeps foundational state under `system`, `shell`,
`tools`, and `configs`, and uses `current` plus `drift` for comparisons.

The diagram below is rendered from
[`../../assets/audit-flow.d2`](../../assets/audit-flow.d2).

![Audit flow comparing macOS and Windows](../../assets/audit-flow.svg)

Use `--json` on macOS and Linux. On Windows, use `--json` and `--populate-state`
through [`install.cmd`](../../install.cmd), or use `-Json` and
`-PopulateState` when you call the repo-local wrappers directly.

![Script ownership banner](../../assets/readme/scripts-ownership-map.svg)

Treat this as an operator-facing entrypoint map. The table shows what you run
for each stage. On Windows, the `.cmd` wrappers are the normal entry surface.
The `.ps1` files sit behind them and only matter when you are debugging the
implementation layer directly.

| Stage | macOS entrypoint | Linux entrypoint | Windows entrypoint | Use when |
| --- | --- | --- | --- | --- |
| Public loader | [`install.sh`](../../install.sh) | [`install.sh`](../../install.sh) | [`install.cmd`](../../install.cmd) | First run or normal rerun from the repo root |
| Repo-local router | [`macos/bootstrap-macos.zsh`](macos/bootstrap-macos.zsh) | [`linux/bootstrap-linux.sh`](linux/bootstrap-linux.sh) | [`windows/bootstrap-windows.cmd`](windows/bootstrap-windows.cmd) | Platform-local dispatch and focused debugging |
| Foundation | [`macos/foundation-macos.zsh`](macos/foundation-macos.zsh) | [`linux/foundation-linux.sh`](linux/foundation-linux.sh) | [`windows/foundation-windows.cmd`](windows/foundation-windows.cmd) | `setup`, `ensure`, or `update` |
| Personal layer | [`macos/personal-bootstrap-macos.zsh`](macos/personal-bootstrap-macos.zsh) | Integrated selected stages | [`windows/personal-bootstrap-windows.cmd`](windows/personal-bootstrap-windows.cmd) | Personal reconciliation after foundation |
| Audit | [`macos/audit-macos.zsh`](macos/audit-macos.zsh) | [`linux/audit-linux.sh`](linux/audit-linux.sh) | [`windows/audit-windows.cmd`](windows/audit-windows.cmd) | Read-only inspection of machine state |
| Optional WSL | n/a | Reuses the Linux entrypoints | [`windows/wsl-bootstrap-windows.cmd`](windows/wsl-bootstrap-windows.cmd) | Add an independently auditable Linux layer to Windows |
| Repair | Not needed | Not needed | [`windows/resign-windows.cmd`](windows/resign-windows.cmd) | PowerShell signing drift on Windows |

Windows PowerShell implementation files:
- [`windows/foundation-windows.ps1`](windows/foundation-windows.ps1)
- [`windows/personal-bootstrap-windows.ps1`](windows/personal-bootstrap-windows.ps1)
- [`windows/audit-windows.ps1`](windows/audit-windows.ps1)
- [`windows/wsl-bootstrap-windows.ps1`](windows/wsl-bootstrap-windows.ps1)
- [`windows/resign-windows.ps1`](windows/resign-windows.ps1)

Support libraries:
- [`macos/lib/common.zsh`](macos/lib/common.zsh)
- [`linux/lib/common.sh`](linux/lib/common.sh)
- [`windows/lib/common.ps1`](windows/lib/common.ps1)
- [`windows/lib/windows-precursor.ps1`](windows/lib/windows-precursor.ps1)
- [`windows/lib/signing-helpers-windows.ps1`](windows/lib/signing-helpers-windows.ps1)

The naming convention is purpose-first and OS-suffixed:
`bootstrap-<os>`, `foundation-<os>`, `personal-bootstrap-<os>`, and
`audit-<os>`, with `wsl-bootstrap-windows` as the explicit optional layer.
Windows keeps `.cmd` as the operator-facing wrapper layer and
`.ps1` as the implementation layer. The directory split mirrors that model:
`macos/`, `linux/`, and `windows/`.

![Shared contract banner](../../assets/readme/scripts-shared-contract.svg)

These defaults and conventions stay stable across all three platforms, so you can
reason about the bootstrap without memorising every implementation detail.

| Contract | Value |
| --- | --- |
| State file | `~/.config/dotfiles/state.env` |
| Resolution precedence | CLI flag, environment variable, state file, device profile, interactive prompt, hard-coded default |
| Modes | `setup`, `ensure`, `update`, `personal`, `audit` |
| Dry-run | `--dry-run` on macOS/Linux, `-DryRun` on Windows; inspect current state and print only required repairs without applying them |
| Profiles | `work` (Ben's work setup), `home` (Ben's personal setup), `minimal` (neutral adopter baseline) |
| First-run recommendation | Use the public loaders, not the direct implementation files |

![Profiles and flags banner](../../assets/readme/scripts-profiles-flags.svg)

Profiles keep the common path short. Individual flags let you override that
path when a machine needs something different.

| Platform | Scope | Flags |
| --- | --- | --- |
| macOS | Ben's catalogues | `packages`, `applications`, `mise-tools`, `dotfiles` |
| macOS | Adopter layout and identity | `code-directory`, `downloads-link`, `git-identity` plus `--device-name`, `--git-name`, `--git-email` |
| macOS | System stages | `macos-defaults`, `remote-access`, `rosetta`, `shell-default`, `zscaler` |
| macOS | Preference groups | `macos-hostname`, `macos-dock`, `macos-desktop`, `macos-default-apps`, `macos-menu-bar`, `macos-mouse`, `macos-power`, `macos-finder`, `macos-screenshots`, `macos-touch-id` |
| Linux | Ben's catalogues | `packages`, `applications`, `mise-tools`, `dotfiles` |
| Linux | Adopter layout and identity | `code-directory`, `downloads-link`, `git-identity` plus `--device-name`, `--git-name`, `--git-email` |
| Linux | System stages | `linux-defaults`, `linux-hostname`, `linux-default-apps`, `remote-access`, `shell-default`, `zscaler` |
| Windows | Ben's catalogues | `packages`, `applications`, `mise-tools`, `dotfiles` |
| Windows | Adopter layout and identity | `code-directory`, `downloads-link`, `git-identity` plus `--device-name`, `--git-name`, `--git-email` |
| Windows | System stages | `windows-defaults`, `remote-access`, `zscaler` |
| Windows | Personal-layer overrides | `git-config`, `ssh-config`, `mise-config`, `opencode-config`, `profile-extras` |

![Recommended commands banner](../../assets/readme/scripts-recommended-commands.svg)

These commands cover the common operator paths without dropping into the
implementation files too early.

### macOS

Use the root loader for normal setup and audit work. Drop to the repo-local
router only when you need to inspect or debug a local stage directly.

```bash
# Factory Mac: no separate prerequisite commands
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh | bash

# Existing checkout
./install.sh
./install.sh ensure
./install.sh update
./install.sh audit --general
./install.sh audit --profile home
./install.sh audit --json
./Other/scripts/macos/bootstrap-macos.zsh ensure --shell fish --profile work
```

The streamed no-argument path is the canonical fresh-machine flow. It keeps the
script stream separate from `/dev/tty`, uses the terminal only for operator
input, and owns Command Line Tools, repository cloning, Homebrew, standalone
mise, mise-managed Gum, and the remaining selected stages in one run.

Homebrew, standalone mise, and mise-managed Gum are the mandatory foundation.
The interactive menu has an explanation page, then treats each profile as an
editable preset. `minimal` leaves all Ben's catalogues off by
default and prompts for adopter-owned values such as device name and Git author
identity. It defaults to creating `~/code`; the Downloads-to-iCloud link is an
explicit choice. The current macOS account supplies home paths and service ACLs
but is never renamed.

Git configuration is user-owned rather than a required mise symlink. With no
`~/.gitconfig`, bootstrap generates one from the selected identity and, when
Ben's dotfiles are selected, the tracked `git/config.shared`. When a config exists, the interactive flow offers
replacement; preserving it writes `~/.config/git/bootstrap-user.inc` and adds
only that include. Generated configs activate the separate GitHub SSH rewrite
only after SSH authentication succeeds. Ben's legacy symlink remains valid.

The Downloads option safely replaces an absent folder or a fresh folder that
contains only `.localized` and `.DS_Store`. It clears macOS's stock deny-delete
ACL only after that check and refuses to overwrite real files or an unexpected
symlink.

`./install.sh ensure --dry-run` is the repair preview. It uses the same
authoritative checks as the audit and reports only real drift: missing
declarative packages, missing or outdated Brewfile entries, unapplied dotfiles,
effective Git identity or configuration-mode differences, individual macOS
preference changes, and remote-service or ACL differences. It does not write the state file, apply
defaults, install software, change services, or refresh the dotfiles remote.

Chrome remains declared in the Brewfile, but it is a vendor-self-updating cask.
Bootstrap audit, ensure, and update commands set Homebrew's supported
`HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1` policy: Homebrew owns whether Chrome
is installed, while Chrome owns its privileged in-place updates. Ordinary
formulae and non-self-updating casks continue to be upgraded by Homebrew.
Bootstrap and audit also verify Chrome's deep signature, Google signing identity,
and Gatekeeper assessment when quarantined; a broken installation cannot be
reported as successful.

The macOS preference groups have these exact effects:

| Group | Applied behavior |
| --- | --- |
| Hostname | Sets `ComputerName`, `LocalHostName`, and `HostName` to the separately chosen device name; it never renames the account |
| Dock | Moves the Dock left, enables immediate auto-hide, clears the factory entries, pins installed Ghostty and Chrome, removes folders/Recents |
| Desktop | Hides desktop and Stage Manager widgets and disables click-wallpaper-to-show-desktop |
| Default apps | Makes Chrome the HTTP, HTTPS, HTML, XHTML, and PDF handler while preserving unrelated LaunchServices records |
| Menu bar | Shows Wi-Fi, Bluetooth, and Sound; shows battery percentage when present; hides Spotlight; uses `DDD DD MMM` and 24-hour `HH:MM:SS` |
| Mouse | Disables pointer acceleration with `com.apple.mouse.scaling = -1` |
| Power | Mac mini: display/disk sleep 10 minutes, system sleep off, restart after power loss, network wake/keepalive on. MacBook Air/Pro: display/disk sleep 10 minutes and system sleep 20 minutes |
| Finder | Shows path/status bars, all extensions, and `~/Library`; suppresses the extension-change warning but preserves the empty-Trash warning |
| Screenshots | Uses PNG |
| Touch ID | Enables Touch ID for `sudo`, including inside tmux, through `/etc/pam.d/sudo_local` and Homebrew `pam-reattach` |

#### FileVault, authenticated restart, and headless access

The macOS bootstrap enables Remote Login and Screen Sharing when that personal
stage is selected, and its Mac-mini power profile keeps the machine awake,
network-reachable, and configured to restart after power restoration. It does
not enable or disable FileVault, stage a FileVault key, restart the Mac, or
automatically invoke `fdesetup authrestart`. Those are security-sensitive,
operator-owned actions.

There are two distinct restart paths:

| Restart path | FileVault behavior | Remote recovery |
| --- | --- | --- |
| Planned authenticated restart | `fdesetup` temporarily stages an additional unlock-key copy for the next boot | The next boot can pass FileVault without interactive unlock if the command succeeds |
| Normal or unexpected restart | No unlock key is staged; FileVault remains locked | On Apple silicon with macOS 26 or later, authenticate over pre-boot SSH, or unlock locally |

Before relying on either path, confirm the machine state:

```bash
./install.sh audit
fdesetup status
fdesetup supportsauthrestart
sudo fdesetup list
```

`supportsauthrestart` returning `true` reports hardware/OS capability only.
FileVault must also be on, and the authenticating account must be an enabled
FileVault user. Keep the personal recovery key somewhere secure and separate
from the Mac before testing any remote-only restart workflow.

For a planned restart, save all work and make sure a physical or recovery path
exists, then run:

```bash
sudo fdesetup authrestart -delayminutes 1
```

Expect administrator authentication and a FileVault password prompt; these may
appear as separate prompts even when the same account is used. With no
`-delayminutes` option, or with `0`, restart is immediate. A value of `-1`
stages the authenticated restart until the next manually initiated restart and
therefore leaves the reduced-protection window open longer; do not use it as a
routine bootstrap setting. Never put a FileVault password or recovery key in a
script, command line, state file, log, or persistent input plist.

An authenticated restart is deliberately temporary. According to the installed
`fdesetup(8)` manual, it reduces FileVault protection by retaining an additional
unlock-key copy in memory and, on supported hardware, the system controller.
After the subsequent boot unlocks successfully, that staged key is removed. It
does not permanently configure future reboots and does not help after a later
unexpected power loss.

For a normal or unexpected restart on Apple silicon with macOS 26 or later,
Remote Login and a supported pre-boot network are required. Connect from a
second machine using a FileVault-enabled account:

```bash
ssh <filevault-user>@<mac-host-or-address>
```

Use password authentication at the pre-boot prompt. The encrypted data volume
is still locked at that point, so the user's normal `~/.ssh/config`, public-key
authorizations, shell, and other files are unavailable. The pre-boot SSH
connection unlocks the volume rather than opening a shell; macOS disconnects
it while mounting the data volume and starting normal services. Wait, then
reconnect with the normal SSH configuration. Screen Sharing becomes useful
only after the volume has been unlocked and its dependent services have
started.

Apple documents these pre-boot network requirements:

- Ethernet must be open or otherwise unauthenticated.
- Wi-Fi must be a previously joined open network or WPA2 Personal/pre-shared-key
  network.
- If no supported network is available, local FileVault authentication is
  required.

`pmset autorestart 1` only powers the Mac back on after power is restored;
`womp`, `tcpkeepalive`, and `sleep 0` improve headless reachability but do not
bypass FileVault. Likewise, the `DisableFDEAutoLogin` audit value describes
whether macOS can hand the FileVault unlock credential to the login window; it
is not the ordinary unencrypted automatic-login preference.

References: [Apple Platform Security — Managing FileVault in
macOS](https://support.apple.com/guide/security/sec8447f5049/web), [Apple
Platform Deployment — Intro to
FileVault](https://support.apple.com/guide/deployment/dep82064ec40/web), and the
installed `man fdesetup` documentation.

### Linux

The same streamed loader owns the complete fresh-machine path on supported
apt and pacman distributions. It installs standalone mise and mise-managed
Gum, then uses mise for the native package and system Flatpak catalogues.

```bash
# Interactive profile editor
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh | bash

# Fully specified home plan
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh \
  | bash -s -- setup --profile home --shell fish --device-name dev-linux \
      --git-name "Ada Lovelace" --git-email ada@example.com --non-interactive

# Inventory, comparison, exact-plan audit, and repair preview
./install.sh audit --general
./install.sh audit --profile home
./install.sh audit --expect-state
./install.sh ensure --dry-run
```

The home plan installs the declared apt/pacman packages, architecture-aware
Flatpak applications, shared mise tools, Fish and Fisher, TPM, dotfiles, Git
identity, `~/code`, hostname, SSH, and browser/PDF handlers. Existing
user-owned dotfiles are preserved; an unchanged file copied from `/etc/skel`
is considered factory state and can be replaced by the requested dotfile
symlink. The audit resolves Flatpak desktop exports even over SSH, so its MIME
results match a graphical login rather than producing false drift.

On an already-converged machine, `ensure --dry-run` reports zero fixes. Sudo
or `chsh` authentication is only requested by an apply run when a privileged
surface actually needs reconciliation. The password is never saved or passed
as a bootstrap option.

### Windows

Use the root loader for normal setup and audit work. Use the repo-local `.cmd`
wrappers when you want a single-purpose entrypoint or a local repair path.

```powershell
.\install.cmd setup --profile work --personal
.\install.cmd ensure
.\install.cmd audit
.\install.cmd audit --profile home
.\install.cmd audit --populate-state
.\install.cmd wsl --profile home
.\install.cmd wsl --profile minimal --wsl-shell bash --disable-dotfiles
.\install.cmd audit --section wsl --profile home
.\Other\scripts\windows\bootstrap-windows.cmd audit -Section tools
.\Other\scripts\windows\resign-windows.cmd
```

![Direct help banner](../../assets/readme/scripts-direct-help.svg)

The fastest way to inspect a single entrypoint is to use its built-in help
surface. The `.cmd` wrappers are the normal Windows help path. `Get-Help` is
for inspecting the PowerShell implementation layer directly.

<details>
<summary>Show direct help commands</summary>

```bash
./Other/scripts/macos/bootstrap-macos.zsh --help
./Other/scripts/macos/foundation-macos.zsh --help
./Other/scripts/macos/personal-bootstrap-macos.zsh --help
./Other/scripts/macos/audit-macos.zsh --help
./Other/scripts/linux/bootstrap-linux.sh --help
./Other/scripts/linux/foundation-linux.sh --help
./Other/scripts/linux/audit-linux.sh --help
```

```powershell
.\Other\scripts\windows\bootstrap-windows.cmd --help
.\Other\scripts\windows\foundation-windows.cmd --help
.\Other\scripts\windows\audit-windows.cmd --help
.\Other\scripts\windows\personal-bootstrap-windows.cmd --help
.\Other\scripts\windows\wsl-bootstrap-windows.cmd --help
.\Other\scripts\windows\resign-windows.cmd --help
Get-Help .\Other\scripts\windows\foundation-windows.ps1 -Detailed
Get-Help .\Other\scripts\windows\personal-bootstrap-windows.ps1 -Detailed
Get-Help .\Other\scripts\windows\wsl-bootstrap-windows.ps1 -Detailed
Get-Help .\Other\scripts\windows\audit-windows.ps1 -Detailed
Get-Help .\Other\scripts\windows\resign-windows.ps1 -Detailed
```

</details>

![Manual recovery banner](../../assets/readme/scripts-manual-recovery.svg)

This section is an operator recovery reference for interrupted third-party or
Apple installers. None of these commands are prerequisites for the canonical
streamed loader.

<details>
<summary>Show manual macOS recovery steps</summary>

Use this only to recover a macOS run interrupted inside an Apple or third-party
installer. The normal recovery action is to finish or cancel that installer,
then re-enter the same idempotent loader and choose the same plan.

1. If Command Line Tools was interrupted, reopen its installer and wait for it
   to finish. The GUI's Continue and licence steps cannot be silently accepted.

   ```bash
   xcode-select --install
   xcode-select -p
   pkgutil --pkg-info=com.apple.pkg.CLTools_Executables
   ```

2. If the checkout was never created, clone it only after operational Git is
   available. Bypass any global HTTPS-to-SSH rewrite during this recovery clone.

   ```bash
   GIT_CONFIG_GLOBAL=/dev/null git clone \
     https://github.com/benjaminwestern/dotfiles "$HOME/.dotfiles"
   ```

3. Re-run the local loader. It will converge Homebrew, standalone mise,
   mise-managed Gum, configuration selection, packages, tools, and personal
   stages in the correct order. Select the same editable profile and stages as
   the interrupted run.

   ```bash
   "$HOME/.dotfiles/install.sh"
   ```

   If there is still no checkout, re-run the public loader instead:

   ```bash
   curl -fsSL \
     https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh \
     | bash
   ```

4. Run the read-only audit after convergence. Use a direct implementation
   entrypoint only for focused diagnosis; do not manually replay Brewfile,
   dotfile, shell-default, or macOS-default commands out of order.

   ```bash
   "$HOME/.dotfiles/install.sh" audit
   /bin/zsh "$HOME/.dotfiles/Other/scripts/macos/audit-macos.zsh"
   ```

</details>

![FAQ banner](../../assets/readme/scripts-faq.svg)

These are the questions that usually come up once you understand the normal
flow but want to know why Windows looks more defensive than macOS.

### Can I launch the Windows `.cmd` entrypoints from PowerShell or Windows PowerShell 5.1?

Yes. PowerShell can invoke the `.cmd` wrappers directly by path, for example
`& .\Other\scripts\windows\foundation-windows.cmd -Mode ensure`. The wrapper then runs
under `cmd.exe`, which is the intended first hop for the Windows bootstrap.

### Why does Windows keep both `.cmd` and `.ps1` files?

Windows uses `.cmd` as the operator-facing layer and `.ps1` as the
implementation layer. That split avoids a chicken-and-egg problem on fresh
machines or `AllSigned` machines where direct PowerShell execution can fail
before the local signing and PowerShell 7 precursor logic has run.

### What has been proven on Windows ARM?

The native `home` flow has been run end to end on a fresh Windows 11 ARM VM.
It bootstraps Scoop, PowerShell 7, Git, OpenSSL, mise, the native application
and font catalogue, the shared runtime/tool catalogue, the personal checkout,
Git/SSH/config copies, terminal profile, computer name, and OpenSSH service.
The general and profile audits were then run from the public `.cmd` entrypoint.
Where an ARM64 artifact exists it is preferred; explicitly catalogued x64
upstream bundles run through Windows ARM emulation. Podman Desktop installation
does not create or start a Podman machine.

The optional WSL contract is a separate `install.cmd wsl` target. It uses the
same Linux profile implementation rather than duplicating an alternate package
catalogue in PowerShell. The first run can stop at a required Windows restart;
the identical command then resumes with distribution/user initialization and
the Linux bootstrap. `audit --section wsl` reports the platform independently,
while `audit --profile NAME` also runs that profile's Linux audit when WSL is
present. No WSL resource limits or Podman machine initialization are applied.
The `home` flow and its profile audit have also been run end to end with Ubuntu
ARM64 under WSL 1 in the same nested VM. That proved the explicit WSL 1
compatibility subset, non-interactive Linux user/login-shell setup, repeatable
Mise ownership, and zero-drift audit. WSL 2 remains the preferred full-profile
path, but it could not be exercised in this guest because Parallels did not
expose nested virtualization. WSL orchestration starts explicitly in Linux
home and bypasses interactive startup files; normal Bash, Zsh, and Fish logins
also move from the mounted Windows home to Linux home before activating Mise.

![Validation roadmap banner](../../assets/readme/scripts-validation-roadmap.svg)

The bootstrap contract is in place on macOS, Linux, and Windows. The remaining work is
mostly about proving the current flow on real machines and in CI, not
redesigning the current two-layer model.

- Repeat the proven macOS flow on a second erased Mac to validate the neutral
  adopter prompts and confirm convergence independently of the first machine.
- Repeat the proven Windows 11 ARM native and WSL flows on x64 Windows.
- Repeat the proven Ubuntu ARM64 VM flow on clean x86_64 Ubuntu and one
  pacman-family desktop to validate the alternate Flatpak/browser and package
  branches.
- Add CI coverage on ephemeral macOS, Linux, and Windows runners so `setup`, `ensure`,
  `update`, and `audit` stay exercised continuously.
