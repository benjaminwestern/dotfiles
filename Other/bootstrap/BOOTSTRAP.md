# Unified Bootstrap Guide

This is the single source of truth for taking a fresh machine to a working shell, runtime manager, and personal config. It covers macOS, native Windows, and the supported apt/pacman Linux families, plus every ordering gotcha and manual workaround we hit while bringing this repo online.

## The SSH chicken-and-egg problem

`git/github-ssh.inc` contains:

```ini
[url "git@github.com:"]
    insteadOf = https://github.com
```

Once an active Git config includes this file, **every** `git clone https://github.com/...` is rewritten to use SSH. On a fresh machine with no SSH key registered at GitHub, those operations fail with permission denied. This affects:

- The initial dotfiles clone
- `cargo install --git https://github.com/...`
- `pipx`/`uv` installing from git URLs
- The TPM clone inside `mise run bootstrap`
- Any other tool that shells out to `git` for a GitHub HTTPS URL

### Workaround

Use `GIT_CONFIG_GLOBAL=/dev/null` to bypass `~/.gitconfig` for the specific command:

```bash
GIT_CONFIG_GLOBAL=/dev/null git clone https://github.com/benjaminwestern/dotfiles ~/.dotfiles
GIT_CONFIG_GLOBAL=/dev/null cargo install --git https://github.com/owner/repo
GIT_CONFIG_GLOBAL=/dev/null pipx install git+https://github.com/owner/repo
```

The bootstrap deliberately does not generate or import SSH keys. Generated Git
configs include the safe shared settings immediately but add the GitHub rewrite
only after `ssh -T git@github.com` proves that key and host trust are ready.
Keep using the per-command `GIT_CONFIG_GLOBAL=/dev/null` bypass for recovery
commands that must use HTTPS before then.

## macOS bootstrap

Use the public loader on a fresh machine:

```bash
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh \
  | bash
```

That is the complete starting point. The loader attaches the interactive flow
to the terminal, opens and waits for Apple's Command Line Tools installer when
needed, clones the repository with Git configuration disabled, installs
Homebrew, installs mise through its standalone installer, installs Gum through
mise, and then presents the action/profile/shell/stage menus. Password,
installer, trust, and licence decisions remain visible in the same terminal.

After Brewfile application installation, bootstrap verifies Chrome's deep code
signature, expected Google signing identity, and Gatekeeper acceptance when the
bundle is quarantined. A failed assessment stops the run instead of leaving a
supposedly successful but unlaunchable browser.

### Profiles and adopter inputs

The mandatory foundation is deliberately small: Homebrew, standalone mise,
and mise-managed Gum. The Gum interface explains and then exposes three
editable presets:

| Preset | Defaults |
| --- | --- |
| `work` | Ben's package, app, tool, and dotfile catalogues; all macOS preferences; Fish; home layout; remote access; Rosetta; Git identity; Zscaler auto-detection |
| `home` | Ben's complete setup without Zscaler |
| `minimal` | Neutral adopter baseline: Ben's catalogues off; zsh unchanged; device naming, Git identity, and `~/code` selected; other personal/system stages off |

Before applying anything, the operator can independently enable or disable
Ben's Homebrew package catalogue, Brewfile apps/fonts, mise tools, dotfiles,
`~/code`, the Downloads-to-iCloud link, Git identity, remote access, Rosetta,
login-shell change, Zscaler, and each macOS preference group. The latter are
hostname, Dock, desktop, Chrome handlers, menu bar/clock, mouse, power, Finder,
screenshots, and Touch ID sudo.

The root Audit action first asks for a perspective: general machine inventory,
or comparison with explicit `minimal`, `home`, or `work` defaults. The automatic
audit after bootstrap instead compares with the exact saved customised plan.

When the Downloads link is selected, bootstrap replaces an absent folder or a
fresh folder containing only Finder's `.localized` and `.DS_Store` metadata.
It clears the stock deny-delete ACL only after that safety check. Any real
download or unexpected symlink is preserved for manual reconciliation.

The current macOS username is detected for home paths and sharing ACLs and is
never renamed. The device name is separately prompted and applied to
ComputerName, LocalHostName, and HostName. If `~/.gitconfig` is absent,
bootstrap creates a user-owned file containing the selected author identity.
When Ben's dotfiles are selected it also includes `git/config.shared`. If a config already exists, the interactive
flow offers to replace it. Declining replacement—or running non-interactively—
preserves it and adds the identity through `~/.config/git/bootstrap-user.inc`.
The legacy tracked wrapper remains valid for Ben's existing symlink, but mise
no longer owns `~/.gitconfig` as a mandatory dotfile target.

Or clone first and run locally:

```bash
GIT_CONFIG_GLOBAL=/dev/null git clone \
  https://github.com/benjaminwestern/dotfiles ~/.dotfiles
~/.dotfiles/install.sh
```

On a factory Mac, use the remote loader rather than trying to clone manually:
`/usr/bin/git` is only an Xcode shim until Command Line Tools are installed.

Routine maintenance:

```bash
~/.dotfiles/install.sh ensure
~/.dotfiles/install.sh update
mise doctor
mise up
mise bootstrap dotfiles status --missing
mise bootstrap mise-shell-activate status --missing
```

## Linux bootstrap

Ubuntu, Debian, Mint, 64-bit Raspberry Pi OS, Arch, CachyOS, Manjaro, and
EndeavourOS use the same public loader. Do not pre-install mise or manually
replay its package commands: the loader installs standalone mise, installs Gum
through mise, detects `apt` versus `pacman`, and then presents the editable
profile plan.

```bash
# Canonical fresh-machine path
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh \
  | bash

# Non-interactive plan selection (sudo/chsh authentication remains visible)
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh \
  | bash -s -- setup --profile home --shell fish --device-name dev-linux \
      --git-name "Ada Lovelace" --git-email ada@example.com --non-interactive
```

The Linux `home` preset reconciles native packages with mise's system-package
manager, system-wide Flatpak applications with mise's Flatpak manager, declared
AUR applications with interactive `paru` PKGBUILD review on pacman-family
systems, the
shared versioned toolset, Ben's dotfiles, `~/code`, Git identity, hostname,
SSH and PC/SC services, Fish/Fisher, TPM, and browser/PDF defaults. PC/SC
activation follows native package selection because it supports the declared
YubiKey stack. `work` adds Zscaler auto-detection. `minimal` leaves Ben's
catalogues disabled and collects only the adopter-owned identity and naming
values. Each independently selectable setting can be changed in the Gum plan
or with the same `--enable-*`/`--disable-*` overrides as macOS.

Administrator authentication can appear when native packages, system
Flatpaks, hostname, SSH, or login-shell state changes. The script deliberately
does not put the password in configuration or feed it through a pipe. A full
home toolset on a small ARM64 VM can take several minutes because `resvg` and
`tlrc` compile from their official Rust crates when no upstream ARM64 archive
exists.

Desktop applications target x86_64 and ARM64: VS Code is installed on both,
Google Chrome is selected on x86_64, and Chromium is selected on ARM64. The
cross-platform Zen Flatpak becomes the HTTP/HTTPS/HTML handler, while Chrome or
Chromium handles PDFs. Flatpak is system-wide because that is the ownership
model of mise's Flatpak backend.

After convergence, run all three audit perspectives and the idempotence check:

```bash
~/.dotfiles/install.sh audit --general
~/.dotfiles/install.sh audit --profile home
~/.dotfiles/install.sh audit --expect-state
~/.dotfiles/install.sh ensure --dry-run
```

The general audit inventories the machine without declaring intentional
omissions as drift. The profile audit compares with a clean preset. The saved
plan audit compares with the exact previous customisation. A converged dry run
reports zero fixes.

### Existing desktop installations

The bootstrap installs VS Code through system Flatpak, including on ARM64.
Existing non-skeleton shell files and directories are preserved; untouched
`/etc/skel` shell files are safe to replace with the selected dotfile links.
Distribution desktop customisation outside the declared bootstrap surfaces is
left alone. The exception is `~/.config/hypr`, which is a whole-directory
managed target on Linux. Preserve it explicitly with `--preserve
~/.config/hypr` when adopting the bootstrap without its CachyOS Hyprland setup.

### Platform-specific mise config

`~/.config/mise` is a directory symlink to `~/.dotfiles/mise`. It contains:

- `config.toml` — shared config (tools, env, aliases, tasks, dotfiles)
- `config.linux.toml` — apt/pacman packages, Linux tools, dotfiles, and login shell
- `config.macos.toml` — brew packages and macOS login shell
- `miserc.toml` — enables `auto_env = true` so mise loads the right platform file

The architecture-aware Linux Flatpak catalogue lives in
`Other/scripts/linux/lib/common.sh`.

`auto_env` is required because mise does not auto-load `mise.{linux,macos}.toml`
by default. The `miserc.toml` turns it on early, before config discovery finishes.

Routine maintenance goes through the same public contract:

```bash
~/.dotfiles/install.sh ensure
~/.dotfiles/install.sh ensure --dry-run
~/.dotfiles/install.sh update
~/.dotfiles/install.sh audit --expect-state
```

## Native Windows bootstrap

Use the batch loader from PowerShell, Windows PowerShell, or `cmd.exe`. The
`.cmd` first hop is intentional: it can establish a safe PowerShell execution
policy and install PowerShell 7 before any implementation script must parse.

```powershell
# Canonical fresh-machine path
curl.exe -fsSL -o "$env:TEMP\install.cmd" `
  "https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.cmd"
& "$env:TEMP\install.cmd" setup

# Fully specified home plan
& "$env:TEMP\install.cmd" setup --profile home `
  --device-name windows-arm `
  --git-name "Ada Lovelace" --git-email ada@example.com `
  --non-interactive
```

The loader downloads only the public Windows bootstrap files into an exact
temporary directory. Scoop is the native precursor and application manager;
it installs Git, OpenSSL, PowerShell 7, the Visual C++ runtime, and mise before
the normal foundation starts. `RemoteSigned` is set for the current user only
when no Group Policy controls execution. Existing `AllSigned` policy is
respected through the local signing path rather than weakened.

The three presets have the same meaning as macOS and Linux:

| Preset | Native Windows defaults |
| --- | --- |
| `home` | Ben's native package, application/font, mise, dotfile, Git/SSH/config, `~/code`, hostname, OpenSSH, terminal, and shell catalogue; Zscaler off |
| `work` | The `home` catalogue plus Zscaler detection and trust configuration |
| `minimal` | Scoop, PowerShell 7, Git, OpenSSL, mise, and adopter-selected naming/identity/layout only; Ben's catalogues remain off |

Every plan value can be changed with the same `--enable-*` or `--disable-*`
contract. Windows exposes `packages`, `applications`, `mise-tools`, `dotfiles`,
`code-directory`, `downloads-link`, `git-identity`, `windows-defaults`,
`remote-access`, and `zscaler`, plus `--device-name`, `--git-name`,
`--git-email`, and `--downloads-target`. The normal interactive path explains
the presets and collects adopter-owned values; passwords and API keys are never
accepted as command-line options.

### Windows parity and ownership

The goal is functional parity, not pretending Unix-only applications exist on
Windows:

- Windows Terminal with PowerShell 7 replaces Ghostty with Fish.
- Ditto replaces Maccy, DBeaver replaces DBngin, PowerToys replaces the macOS
  window-management utilities, and MiKTeX replaces MacTeX.
- `scc` is the ARM64 code-counter equivalent because `tokei` 14 publishes no
  Windows binary and otherwise requires the full MSVC build toolchain.
- Scoop owns upstream Windows bundles for gcloud, skaffold, Lua/StyLua,
  mitmproxy, ngrok, VS Code, Chrome, Obsidian, Podman Desktop, Yubico
  Authenticator, Codex, and the Nerd Fonts. Signed x64 bundles are used under
  Windows ARM emulation only when upstream has no ARM64 build.
- Mise owns the shared portable runtimes and CLI releases. `MISE_CONFIG_DIR`
  points at the complete repository `mise` directory during installation so
  both `config.toml` and `config.windows.toml` participate. Pointing only
  `MISE_GLOBAL_CONFIG_FILE` at the base file is incorrect because it suppresses
  the sibling platform config.
- Python and uv remain Mise-managed. SQLFluff is installed by uv's real binary;
  invoking Mise's pipx backend through the Windows uv shim recursively enters
  the parent Mise installation. Mitmproxy uses its official Windows bundle
  because its Python dependencies do not publish Windows ARM wheels.
- Podman Desktop is installed without creating, initializing, or starting a
  Podman machine.

The personal layer copies selected files on Windows rather than creating Unix
symlinks. It creates or updates `~/.dotfiles`, Git and SSH config, the entire
public mise config set, OpenCode config, and managed PowerShell profile blocks.
It never invents SSH keys and never copies `~/.config/mise/.env` from the public
repository. Copy private keys and that secret env file through a separately
authenticated channel when explicitly required.

Computer rename is staged immediately but requires a restart. OpenSSH Server is
enabled, started, and set to Automatic before that restart is requested. The
bootstrap does not restart the machine itself.

### Optional WSL layer

Native Windows is a complete target on its own. WSL is selected separately and
uses the same Linux bootstrap already proven on Ubuntu and Debian:

```powershell
& "$HOME\.dotfiles\install.cmd" wsl --profile home
```

The default distribution is Ubuntu and the default Linux user is the current
Windows username. Override those adopter-owned values when needed:

```powershell
& "$HOME\.dotfiles\install.cmd" wsl --profile minimal `
  --wsl-distribution Ubuntu --wsl-version auto --wsl-user ada --wsl-shell bash `
  --device-name ada-wsl --git-name "Ada Lovelace" `
  --git-email ada@example.com
```

The WSL layer performs these bounded stages:

1. Enable WSL with Microsoft's supported `wsl --install --no-launch` path;
   enable Virtual Machine Platform when WSL 2 is selected.
2. Stop when Windows reports a restart boundary. It never restarts the machine
   itself; rerun the same command after signing back in.
3. Install or initialize the selected ARM64/x64 distribution for the host,
   create the Linux user, enable systemd, and make that user the default.
4. Add a temporary passwordless sudo rule only for the Linux bootstrap, invoke
   the public `install.sh` with the selected `home`, `work`, or `minimal`
   profile, then remove the temporary rule even when the bootstrap fails.
5. Leave secrets separate. The public repository and command line never carry
   the Windows or Linux Mise `.env`, SSH private keys, or account passwords.

WSL does not initialize Podman, apply Windows packages again, or impose memory,
CPU, job, or resume limits. Windows and Linux package managers retain ownership
of their respective layers.

The WSL plan accepts the same Linux-relevant `--enable-*`/`--disable-*`
overrides as `install.sh`. Use `--wsl-shell fish|zsh|bash` and
`--wsl-downloads-target /absolute/linux/path` for WSL-owned values; the native
Windows `--shell` and `--downloads-target` options remain separate.

`auto` selects WSL 2 for a new distribution and preserves the version of an
existing distribution. On a nested VM that does not expose Hyper-V, rerun with
`--wsl-version 1`. WSL 1 is a supported Windows/Linux integration path but has
no managed VM, full Linux kernel, full system-call compatibility, or systemd;
the script therefore keeps the portable CLI, Mise, Fish, dotfile, identity,
hostname, code-directory, and audit stages while skipping Flatpak applications,
WireGuard, NetworkManager GUI, YubiKey device packages and services, desktop
MIME defaults, duplicate Linux SSH, SQLFluff, and mitmproxy. The last two remain
Mise-owned on WSL 2 and ordinary Linux but
are excluded on WSL 1 because its filesystem copy path repeatedly returns
`ENOMEM` while uv constructs their environments. WSL 2 keeps the complete
Linux profile. The WSL orchestrator itself runs without interactive shell
startup files, and the shared Bash/Zsh/Fish configs move an ordinary WSL login
from the native Windows home to Linux home before activating Mise.

Audit both perspectives after convergence:

```powershell
& "$HOME\.dotfiles\install.cmd" audit
& "$HOME\.dotfiles\install.cmd" audit --profile home
& "$HOME\.dotfiles\install.cmd" audit --section wsl --profile home
& "$HOME\.dotfiles\install.cmd" ensure --dry-run
```

The general audit runs without loading arbitrary user profile code and reports
the current machine. The profile comparison checks the selected Scoop
catalogue, Mise toolset, dotfiles, identity, layout, hostname, remote access,
and Zscaler posture. `--populate-state` is the only audit option that writes,
and it says so explicitly. The WSL section is also read-only. A general audit
reports features, restart state, and distributions; a profile audit additionally
delegates to the Linux audit inside the selected distribution.

## What `mise bootstrap` does

The Linux orchestrator uses mise's bootstrap capabilities in bounded stages:

1. A minimal explicit `apt:*` or `pacman:*` set brings Git and download tools
   online.
2. The selected native catalogue is reconciled from
   `[bootstrap.packages]` with `mise bootstrap packages apply`.
3. The selected system Flatpaks are applied through the same mise interface.
4. `mise install` reconciles the shared and Linux-specific `[tools]` set.
5. `mise bootstrap user apply` owns Fish registration and the login-shell
   change when Fish is selected.
6. The platform bootstrap ensures Fisher is available and runs `fisher update`
   after deploying dotfiles, making `fish_plugins` the cross-platform plugin
   manifest. On CachyOS it also removes the distro Pure prompt packages without
   recursively removing their utility dependencies.

Dotfile collision policy, Git identity, Fisher plugins, TPM, host settings, services,
and desktop defaults remain explicit script stages so they can be audited and
enabled independently.

The macOS loader does not run that monolithic sequence. It links the repository
mise config only when Ben's packages, tools, or dotfiles were selected, invokes
the package catalogue and tools independently, and hands selected application,
dotfile, identity, layout, and system stages to the personal layer.

## The unified config layout

A single file, `~/.dotfiles/mise/config.toml`, is shared across platforms:

- On macOS, the foundation links `~/.config/mise` to `~/.dotfiles/mise`
  before using any selected Ben catalogue. A neutral `minimal` run with those
  catalogues disabled leaves an adopter's mise config alone.
- Linux gets the same directory symlink whenever Ben's dotfiles are selected.

Because `~/.config/mise` is a **directory** symlink, both `config.toml` and the task scripts in `scripts/` resolve through the same link. Machine-local secrets live in `~/.config/mise/.env`, which is gitignored.

## Gotchas we hit bringing this device online

### 1. Mise must be the standalone binary

**Never install mise via a package manager** (pacman, Homebrew, etc.). The system packages are often too old and do not support `mise bootstrap`, `[dotfiles]`, or platform-specific config (`auto_env`). Always use the official installer:

```bash
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"
```

Then verify with `mise version` and `mise doctor`.

### 2. Pacman mise is too old

### 3. Initial clone must bypass `~/.gitconfig`

Run `GIT_CONFIG_GLOBAL=/dev/null git clone ...` before the SSH key exists. The
generated config activates the GitHub HTTPS-to-SSH include only after SSH
authentication succeeds; the bypass also protects recovery on machines with an
older or independently managed rewrite.

### 4. `~/.config/mise` must be a directory symlink

Originally only `~/.config/mise/config.toml` was symlinked. After the `Configs/` → root restructure, `~/.config/mise` itself is symlinked to `~/.dotfiles/mise` so task scripts resolve correctly.

### 5. Old `Configs/` symlinks break after restructure

If upgrading from the old layout, symlinks still point to `~/.dotfiles/Configs/...`. Delete the stale directory and reapply:

```bash
rm -rf ~/.dotfiles/Configs
mise bootstrap dotfiles apply --force --yes
```

### 6. Real files are takeover candidates

The bootstrap applies declared dotfiles with mise's force mode after the plan is
confirmed. Use `--preserve <path>` before the run for a target that must remain
user-owned, and `--clear-preserve` to clear saved exceptions. Common historical
conflicts include:

- `~/.config/ghostty/config`
- `~/.config/opencode/plugins`

Direct recovery uses `mise bootstrap dotfiles apply --force --yes`.

### 7. `~/.pi` was a stale directory symlink

In the old layout `~/.pi` symlinked to `~/.dotfiles/Configs/pi/.pi`. The new layout manages individual files under `~/.pi/agent/`. Remove the old symlink and recreate the parent directory:

```bash
rm ~/.pi
mkdir -p ~/.pi/agent
mise bootstrap dotfiles apply --force --yes
```

### 8. TPM clone fails without `GIT_CONFIG_GLOBAL=/dev/null`

The bootstrap task clones `tmux-plugins/tpm` over HTTPS. It always uses
`GIT_CONFIG_GLOBAL=/dev/null` so an existing or bootstrap-managed GitHub rewrite
cannot redirect that prerequisite clone.

### 9. `.env` is machine-private

The bootstrap creates `~/.config/mise/.env` with mode `600` when it is absent.
The file is gitignored and must be populated per machine with any private values
needed by the declared tools.

### 10. Some dotfiles are platform-only

`~/.aerospace.toml` and `~/Brewfile` are macOS-only. Ghostty configuration is
shared, while `~/.config/hypr` is Linux-only.

### 11. `mise doctor` PATH warning

Use `type -a <tool>` and `command -v <tool>` when `mise doctor` reports PATH
ordering problems. Mise shims should precede distribution or user-local copies
of the same managed tool.

### 12. SSH key generation is manual

`mise run bootstrap` no longer creates an SSH key. Generate one yourself when you need git push/pull access:

```bash
ssh-keygen -t ed25519 -C "$USER@$(hostname)"
cat ~/.ssh/id_ed25519.pub
```

Then add the public key to GitHub at https://github.com/settings/keys.

### 13. Scroll direction defaults to Apple-style natural scrolling

The canonical Lua settings are in `hypr/config/inputs.lua` and summarized in
`hypr/README.md`. Natural scrolling is enabled for mice and touchpads. To
restore traditional scrolling, set both `natural_scroll` values to `false` and
run `hyprctl reload full-reset`.

### 14. Manual font installs

Some fonts are not packaged and must be installed from upstream releases. Example: `psudoFont Liga Mono` from <https://github.com/psudo-dev/psudofont-liga-mono>:

```bash
mkdir -p ~/.local/share/fonts/psudofont-liga-mono
cd /tmp
curl -sL -o psudofont.zip https://github.com/psudo-dev/psudofont-liga-mono/releases/download/v.2.2.0/psudoFont_Liga_Mono_V.2.2.0.zip
unzip -q psudofont.zip
cp psudoFont_Liga_Mono_V.2.2.0/*.ttf ~/.local/share/fonts/psudofont-liga-mono/
fc-cache -fv ~/.local/share/fonts/psudofont-liga-mono
```

## Validation checklist

After bootstrap, confirm:

```bash
# mise is the standalone version, not pacman
mise version

# config loads with no errors
mise doctor

# all dotfiles are symlinks to the flat repo layout
mise bootstrap dotfiles status --missing
mise bootstrap mise-shell-activate status --missing

# env vars are present
mise env | grep -E 'EDITOR|PITCHFORK|OPENCODE'

# login shell is fish
echo $SHELL

# SSH key exists when this machine is intended to have one
test -f ~/.ssh/id_ed25519 && echo "SSH key present" || echo "SSH key is still manual"
```

## Fingerprint authentication (Arch / fprintd)

On supported hardware, fingerprint auth can replace or supplement passwords for `sudo`, `su`, login, SDDM, and Hyprlock.

### Supported devices

Check the device with `lsusb` and the libfprint device list at <https://fprint.freedesktop.org/supported-devices.html>.

### Bootstrap packages

The home/work pacman catalogue already includes:

```toml
"pacman:usbutils" = "latest"    # lsusb
"pacman:fprintd" = "latest"     # fingerprint daemon (includes PAM module on Arch)
"pacman:libfprint" = "latest"   # fingerprint driver library
```

Reconcile them through the normal bootstrap:

```bash
~/.dotfiles/install.sh ensure
```

### Enroll fingers

```bash
fprintd-list $(whoami)
fprintd-enroll -f right-index-finger $(whoami)
fprintd-enroll -f left-index-finger $(whoami)
fprintd-verify $(whoami)
```

### Configure PAM

Arch bundles `pam_fprintd.so` with the `fprintd` package. Add fingerprint as `sufficient` in `/etc/pam.d/system-auth`:

```
-auth      [success=3 default=ignore]  pam_systemd_home.so
auth       sufficient                  pam_fprintd.so
auth       [success=1 default=bad]     pam_unix.so          try_first_pass nullok
```

Also add it to `/etc/pam.d/su` so `su` supports fingerprint:

```
auth       sufficient      pam_fprintd.so
auth       required        pam_unix.so
```

This enables fingerprint for:

- `sudo` (via `system-auth`)
- `su` (direct)
- TTY login → `system-local-login` → `system-login` → `system-auth`
- SDDM graphical login → `system-login` → `system-auth`
- `hyprlock` → `login` → `system-auth`

### Test

```bash
sudo -k
sudo whoami
su - $(whoami)
```

Fingerprint runs first; password fallback still works if you cancel or the scan fails.

## YubiKey (Linux / macOS)

### Bootstrap packages

The home/work apt and pacman catalogues include their platform equivalents:

```toml
"apt:yubikey-manager" = "latest"
"apt:python3-pyscard" = "latest"
"apt:libccid" = "latest"
"apt:pcscd" = "latest"
"apt:gnupg" = "latest"
"apt:pinentry-curses" = "latest"

"pacman:yubikey-manager" = "latest"   # ykman CLI for YubiKey management
"pacman:python-pyscard" = "latest"    # smart card Python bindings
"pacman:ccid" = "latest"              # smart card driver for YubiKey
"pacman:pcsclite" = "latest"          # PC/SC smart card daemon
"pacman:gnupg" = "latest"             # GPG for OpenPGP applet + ssh-agent
"pacman:pinentry" = "latest"          # GPG passphrase entry
```

Reconcile them through the normal bootstrap:

```bash
~/.dotfiles/install.sh ensure
```

### YubiKey tools on Linux

Use `ykman` as the full Linux YubiKey manager. The CLI covers OpenPGP, PIV,
FIDO2, and OATH:

```bash
ykman list
ykman info
ykman openpgp info
ykman piv info
ykman fido info
ykman oath accounts list
```

For a supported GUI, use **Yubico Authenticator**. On x86_64, the Linux
application catalogue installs Yubico's recommended system Flatpak from
Flathub. Flathub does not currently publish an ARM64 ref:

```bash
flatpak run com.yubico.yubioath
```

The bootstrap also enables PC/SC socket activation for OpenPGP, PIV, OATH, and
other smart-card access:

```bash
sudo systemctl enable --now pcscd.socket
```

The former `yubikey-manager-qt` GUI reached end of life on February 19, 2026.
Yubico Authenticator replaces it and avoids the obsolete AUR package, Python
wrapper, and custom desktop-entry workaround.

### macOS YubiKey tools

On macOS, `mise` installs the `ykman` Homebrew formula for CLI management:

```toml
"brew:ykman" = "latest"
```

The GUI is a separate Homebrew cask in `brew/Brewfile`:

```ruby
cask "yubico-authenticator"
```

Use `ykman` for full CLI management and **Yubico Authenticator** for the supported GUI.

## Recovering from a partial bootstrap

The bootstrap is idempotent. If something fails partway through, fix the blocker and rerun the same step:

```bash
mise bootstrap          # system packages + dotfiles + shell
mise install --yes      # tools
mise run bootstrap      # TPM + declared post-bootstrap extras
mise bootstrap dotfiles apply --force --yes
mise bootstrap mise-shell-activate apply --yes
```

For any git operation that must use HTTPS before the SSH key is registered, prefix with `GIT_CONFIG_GLOBAL=/dev/null`.
