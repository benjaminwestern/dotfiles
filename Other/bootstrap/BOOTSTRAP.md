# Unified Bootstrap Guide

This is the single source of truth for taking a fresh machine to a working shell, runtime manager, and personal config. It covers macOS and the supported apt/pacman Linux families, plus every ordering gotcha and manual workaround we hit while bringing this repo online.

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
mise dotfiles status
```

## Linux bootstrap

Ubuntu, Debian, Mint, Raspberry Pi OS, Arch, CachyOS, Manjaro, and
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
manager, system-wide Flatpak applications with mise's Flatpak manager, the
shared versioned toolset, Ben's dotfiles, `~/code`, Git identity, hostname,
SSH service, Fish/Fisher, TPM, and browser/PDF defaults. `work` adds Zscaler
auto-detection. `minimal` leaves Ben's catalogues disabled and collects only
the adopter-owned identity and naming values. Every stage can be toggled in
the Gum plan or with the same `--enable-*`/`--disable-*` overrides as macOS.

Administrator authentication can appear when native packages, system
Flatpaks, hostname, SSH, or login-shell state changes. The script deliberately
does not put the password in configuration or feed it through a pipe. A full
home toolset on a small ARM64 VM can take several minutes because `resvg` and
`tlrc` compile from their official Rust crates when no upstream ARM64 archive
exists.

Desktop applications are architecture-aware: VS Code is installed everywhere,
Google Chrome is selected on x86_64, and Chromium is selected on ARM64. The
selected browser becomes the HTTP/HTTPS/HTML and PDF handler. Flatpak is
system-wide because that is the ownership model of mise's Flatpak backend.

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

### Omarchy and other existing desktops

The bootstrap now installs VS Code through system Flatpak, including on ARM64.
Existing non-skeleton shell files and directories are preserved; untouched
`/etc/skel` shell files are safe to replace with the selected dotfile links.
Distribution desktop customisation outside the declared bootstrap surfaces is
left alone.

### Platform-specific mise config

`~/.config/mise` is a directory symlink to `~/.dotfiles/mise`. It contains:

- `config.toml` — shared config (tools, env, aliases, tasks, dotfiles)
- `config.linux.toml` — apt/pacman packages, Flatpak apps, Linux tools, and login shell
- `config.macos.toml` — brew packages and macOS login shell
- `miserc.toml` — enables `auto_env = true` so mise loads the right platform file

`auto_env` is required because mise does not auto-load `mise.{linux,macos}.toml`
by default. The `miserc.toml` turns it on early, before config discovery finishes.

Routine maintenance goes through the same public contract:

```bash
~/.dotfiles/install.sh ensure
~/.dotfiles/install.sh ensure --dry-run
~/.dotfiles/install.sh update
~/.dotfiles/install.sh audit --expect-state
```

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

Dotfile collision policy, Git identity, Fisher, TPM, host settings, services,
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
mise dotfiles apply
```

### 6. Real files can block dotfiles apply

If a target path exists as a real file or directory, mise refuses to overwrite it. We hit this with:

- `~/.config/ghostty/config`
- `~/.config/opencode/plugins`

Remove or back them up, then rerun `mise dotfiles apply`.

### 7. `~/.pi` was a stale directory symlink

In the old layout `~/.pi` symlinked to `~/.dotfiles/Configs/pi/.pi`. The new layout manages individual files under `~/.pi/agent/`. Remove the old symlink and recreate the parent directory:

```bash
rm ~/.pi
mkdir -p ~/.pi/agent
mise dotfiles apply
```

### 8. TPM clone fails without `GIT_CONFIG_GLOBAL=/dev/null`

The bootstrap task clones `tmux-plugins/tpm` over HTTPS. It always uses
`GIT_CONFIG_GLOBAL=/dev/null` so an existing or bootstrap-managed GitHub rewrite
cannot redirect that prerequisite clone.

### 9. `.env` is not created automatically

`mise/.example.env` is tracked; `mise/.env` is gitignored. Copy and edit it per machine:

```bash
cp ~/.dotfiles/mise/.example.env ~/.config/mise/.env
```

### 10. Some dotfiles are platform-only

`~/.aerospace.toml`, `~/.config/ghostty/config`, and `~/Brewfile` are declared for macOS. On Arch they show as `applied` symlinks even though the tools themselves may not be installed.

### 11. `mise doctor` PATH warning

`~/.local/share/omarchy/bin` may take precedence over mise shims in `PATH`. This is a warning, not an error, but be aware if tools resolve unexpectedly.

### 12. SSH key generation is manual

`mise run bootstrap` no longer creates an SSH key. Generate one yourself when you need git push/pull access:

```bash
ssh-keygen -t ed25519 -C "$USER@$(hostname)"
cat ~/.ssh/id_ed25519.pub
```

Then add the public key to GitHub at https://github.com/settings/keys.

### 13. Scroll direction defaults to Apple-style natural scrolling

The Hyprland input config in `~/.config/hypr/input.conf` enables natural scrolling for both mice and trackpads:

```ini
input {
  natural_scroll = true

  touchpad {
    natural_scroll = true
    # ...
  }
}
```

This makes content follow your finger, matching macOS / Apple trackpad behavior. To revert to traditional scrolling, set both values to `false` and run `hyprctl reload`.

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

## Purging Omarchy default apps

Omarchy installs a mix of **pacman packages** and **web-app/TUI wrappers** that all show up in the `Super+Space` Walker launcher via `.desktop` files.

| App source | Desktop file location | Removal |
|---|---|---|
| Pacman packages | `/usr/share/applications/*.desktop` | `sudo pacman -Rns <package>` or `omarchy pkg drop <package>` |
| Web app / TUI wrappers | `~/.local/share/applications/*.desktop` | `rm ~/.local/share/applications/<name>.desktop` |

Find what owns a system `.desktop` entry:

```bash
pacman -Qo /usr/share/applications/typora.desktop
```

List everything that appears in `Super+Space`:

```bash
find /usr/share/applications ~/.local/share/applications -name "*.desktop" -type f
```

### Web app wrappers installed by Omarchy

Omarchy creates these in `~/.local/share/applications/` with icons in `~/.local/share/applications/icons/`:

```bash
rm ~/.local/share/applications/{HEY,Basecamp,ChatGPT,Fizzy,WhatsApp,YouTube,X,Discord,GitHub,Zoom,Google\ Contacts,Google\ Maps,Google\ Messages,Google\ Photos}.desktop
rm ~/.local/share/applications/icons/{HEY,Basecamp,ChatGPT,Fizzy,WhatsApp,YouTube,X,Discord,GitHub,Zoom,Google\ Contacts,Google\ Maps,Google\ Messages,Google\ Photos}.png
```

HEY is also registered as the default `mailto:` handler. Remove that registration:

```bash
xdg-mime default xdg-open.desktop x-scheme-handler/mailto
```

Or edit `~/.config/mimeapps.list` and delete the `mailto=HEY.desktop` line.

### TUI wrappers

The Docker entry launches `lazydocker` inside a terminal tile. It is created by `omarchy-tui-install`. Remove the wrapper and, if desired, the underlying packages:

```bash
rm ~/.local/share/applications/Docker.desktop
rm ~/.local/share/applications/icons/Docker.png
sudo pacman -Rns docker docker-buildx docker-compose lazydocker
```

### Keybindings in Hyprland

Some apps also have keyboard shortcuts in `~/.config/hypr/bindings.conf`, e.g.:

```ini
bindd = SUPER SHIFT, A, ChatGPT, exec, omarchy-launch-webapp "https://chatgpt.com"
bindd = SUPER SHIFT, D, Docker, exec, omarchy-launch-tui lazydocker
bindd = SUPER SHIFT, E, Email, exec, omarchy-launch-webapp "https://app.hey.com"
bindd = SUPER SHIFT, C, Calendar, exec, omarchy-launch-webapp "https://app.hey.com/calendar/weeks/"
```

Delete the matching lines and reload:

```bash
hyprctl reload
hyprctl configerrors
```

### Refresh the launcher

After removing `.desktop` files, restart Walker so the changes appear in `Super+Space`:

```bash
omarchy restart walker
```

Or run:

```bash
omarchy-launch-walker
```

and press `Escape` to close it.

## Validation checklist

After bootstrap, confirm:

```bash
# mise is the standalone version, not pacman
mise version

# config loads with no errors
mise doctor

# all dotfiles are symlinks to the flat repo layout
mise dotfiles status

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

Add these to `mise/config.linux.toml` under `[bootstrap.packages]`:

```toml
"pacman:usbutils" = "latest"    # lsusb
"pacman:fprintd" = "latest"     # fingerprint daemon (includes PAM module on Arch)
"pacman:libfprint" = "latest"   # fingerprint driver library
```

Then install them:

```bash
mise bootstrap packages install -y
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

## YubiKey (Arch / macOS)

### Bootstrap packages

Add these to `mise/config.linux.toml` under `[bootstrap.packages]`:

```toml
"pacman:yubikey-manager" = "latest"   # ykman CLI for YubiKey management
"pacman:python-pyscard" = "latest"    # smart card Python bindings
"pacman:ccid" = "latest"              # smart card driver for YubiKey
"pacman:pcsclite" = "latest"          # PC/SC smart card daemon
"pacman:gnupg" = "latest"             # GPG for OpenPGP applet + ssh-agent
"pacman:pinentry" = "latest"          # GPG passphrase entry
```

Then install them:

```bash
mise bootstrap packages install -y
```

### YubiKey tools on Arch

Use `ykman` as the reliable full YubiKey manager on Arch. The CLI detects the key correctly and covers OpenPGP, PIV, FIDO2, and OATH:

```bash
ykman list
ykman info
ykman openpgp info
ykman piv info
ykman fido info
ykman oath accounts list
```

For a supported GUI, use **Yubico Authenticator**. Install the source-built AUR package, not `yubico-authenticator-bin`; the `-bin` package pulls in `zenity`, which is intentionally not part of this setup.

```bash
omarchy pkg aur add yubico-authenticator
```

If `zenity` was installed while testing the `-bin` package, remove it:

```bash
omarchy pkg drop zenity
```

Keep `pcscd` enabled for OpenPGP/PIV/smartcard access:

```bash
sudo systemctl enable --now pcscd
```

Because this dotfiles setup puts mise shims before `/usr/bin`, Yubico Authenticator's helper can accidentally launch with mise Python. Use a launcher wrapper that forces system Python:

```bash
cat > ~/.local/bin/yubico-authenticator-launcher <<'EOF'
#!/bin/bash
export PATH="/usr/bin:$PATH"
exec /usr/bin/yubico-authenticator
EOF
chmod +x ~/.local/bin/yubico-authenticator-launcher
```

Override the desktop entry so `Super+Space` launches the wrapper:

```ini
[Desktop Entry]
Name=Yubico Authenticator
GenericName=Yubico Authenticator
Exec=/home/benjaminwestern/.local/bin/yubico-authenticator-launcher
Icon=com.yubico.yubioath
Type=Application
Categories=Utility;
Keywords=Yubico;Authenticator;
```

Save that as `~/.local/share/applications/com.yubico.yubioath.desktop`.

### Omarchy / Hyprland integration for Yubico Authenticator

On Omarchy, Hyprland config lives under `~/.config/hypr/` and should not be managed by this dotfiles repo. The default files can always be restored from Omarchy's shipped config:

```bash
cp ~/.local/share/omarchy/config/hypr/hyprland.conf ~/.config/hypr/hyprland.conf
cp ~/.local/share/omarchy/config/hypr/bindings.conf ~/.config/hypr/bindings.conf
```

To add a quick keybind for Yubico Authenticator, edit `~/.config/hypr/bindings.conf` (restore the Omarchy file first if you overwrote it):

```ini
bindd = SUPER ALT, Y, Yubico Authenticator, exec, uwsm-app -- /home/benjaminwestern/.local/bin/yubico-authenticator-launcher
```

Then restart Walker and reload Hyprland:

```bash
omarchy restart walker
hyprctl reload
```

Current HP setup notes:

- Removed the broken/deprecated `yubikey-manager-qt` package.
- Do not use `yubico-authenticator-bin`; it pulled in `zenity`, which was removed.
- Installed `yubico-authenticator` from AUR source build, plus its AUR dependency `python-zxing-cpp`.
- Added `~/.local/bin/yubico-authenticator-launcher` so the app helper uses system Python instead of mise Python.
- Overrode `~/.local/share/applications/com.yubico.yubioath.desktop` so Walker launches the wrapper.
- Added `SUPER ALT + Y` in `~/.config/hypr/bindings.conf` to launch the wrapper.
- Verified `ykman list` sees `YubiKey 5C NFC (5.7.1)` and Yubico Authenticator opens correctly.

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

## Trackpad configuration (Hyprland)

The local `~/.config/hypr/input.conf` overrides Omarchy's default touchpad behavior. The current setup uses macOS-style physical clicks and 3-finger gestures:

```ini
input {
  natural_scroll = true

  touchpad {
    natural_scroll = true

    # Disable tap-to-click; require physical clicks
    tap-to-click = false

    # Single physical click = left click; two-finger click = right click
    clickfinger_behavior = true

    # Disable tap-and-drag and drag lock
    tap-and-drag = false
    drag_lock = false

    scroll_factor = 0.4
  }
}

# macOS-style 3-finger trackpad gestures
gesture = 3, horizontal, workspace
gesture = 3, up, fullscreen
gesture = 3, down, fullscreen, 0
```

- 3-finger swipe left/right → switch workspaces
- 3-finger swipe up → fullscreen active window
- 3-finger swipe down → un-fullscreen active window

To pop a window out as floating and pinned above others, use Omarchy's `SUPER + O` binding or `hyprctl dispatch togglefloating && hyprctl dispatch pin`.

## Waybar configuration

`~/.config/waybar/config.jsonc` overrides Omarchy's default Waybar config. The current tweaks are:

### Battery percentage always visible

Battery shows `{capacity}%` in every state (charging, discharging, plugged, full) instead of only an icon when unplugged:

```json
"battery": {
  "format": "{capacity}% {icon}",
  "format-discharging": "{capacity}% {icon}",
  "format-charging": "{capacity}% {icon}",
  "format-plugged": "{capacity}% 🔌",
  "format-full": "{capacity}% 🔋"
}
```

### Plain system tray

The default Omarchy `group/tray-expander` drawer (a clickable arrow that reveals tray icons) is unreliable — clicks do not open it. Replaced with a plain `tray` module in `modules-right` so tray icons are always visible:

```json
"modules-right": [
  "tray",
  "bluetooth",
  "network",
  "pulseaudio",
  "cpu",
  "battery"
]
```

## Recovering from a partial bootstrap

The bootstrap is idempotent. If something fails partway through, fix the blocker and rerun the same step:

```bash
mise bootstrap          # system packages + dotfiles + shell
mise install            # tools
mise run bootstrap      # TPM + declared post-bootstrap extras
mise dotfiles apply     # re-converge symlinks
```

For any git operation that must use HTTPS before the SSH key is registered, prefix with `GIT_CONFIG_GLOBAL=/dev/null`.
