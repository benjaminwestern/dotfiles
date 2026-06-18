# Unified Bootstrap Guide

This is the single source of truth for taking a fresh machine to a working shell, runtime manager, and personal config. It covers both macOS and Arch Linux, plus every ordering gotcha and manual workaround we hit while bringing this repo online.

## The SSH chicken-and-egg problem

`git/.gitconfig` contains:

```ini
[url "git@github.com:"]
    insteadOf = https://github.com
```

Once this file is symlinked into `~/.gitconfig`, **every** `git clone https://github.com/...` is rewritten to use SSH. On a fresh machine with no SSH key registered at GitHub, those operations fail with permission denied. This affects:

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

The bootstrap task generates an SSH key, but you must still register the public key at GitHub manually before normal git operations work.

## macOS bootstrap

Use the public loader on a fresh machine:

```bash
# Install mise standalone first (do NOT use Homebrew for mise itself)
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"

curl -fsSL https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh \
  | bash -s -- setup --shell fish --profile work --personal
```

Or clone first and run locally:

```bash
# Install mise standalone first (do NOT use Homebrew for mise itself)
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"

git clone https://github.com/benjaminwestern/dotfiles ~/.dotfiles
~/.dotfiles/install.sh setup --shell fish --profile work --personal
```

Routine maintenance:

```bash
~/.dotfiles/install.sh ensure --personal
~/.dotfiles/install.sh update
mise doctor
mise up
mise dotfiles status
```

## Arch Linux bootstrap

The Arch `mise` package in pacman is too old for `mise bootstrap` and `[dotfiles]`, so install the standalone binary first.

```bash
# 1. Install mise standalone (do NOT use pacman for mise itself)
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"

# 2. Clone dotfiles with HTTPS (SSH key doesn't exist yet)
GIT_CONFIG_GLOBAL=/dev/null git clone https://github.com/benjaminwestern/dotfiles ~/.dotfiles

# 3. Bootstrap system packages, dotfile symlinks, and default shell
mise bootstrap

# 4. Install language runtimes and tools
mise install

# 5. Install TPM
mise run bootstrap

# 6. Register a new SSH key at GitHub manually, then restart the shell
exec fish
```

### Install VS Code on Omarchy

VS Code is not installed by the bootstrap. On Omarchy, install it with:

```bash
omarchy install vscode
```

This uses the Omarchy wrapper to install `visual-studio-code-bin` and apply the current theme.

### Platform-specific mise config

`~/.config/mise` is a directory symlink to `~/.dotfiles/mise`. It contains:

- `config.toml` — shared config (tools, env, aliases, tasks, dotfiles)
- `config.linux.toml` — pacman packages and Linux login shell
- `config.macos.toml` — brew packages and macOS login shell
- `miserc.toml` — enables `auto_env = true` so mise loads the right platform file

`auto_env` is required because mise does not auto-load `mise.{linux,macos}.toml`
by default. The `miserc.toml` turns it on early, before config discovery finishes.

Routine maintenance:

```bash
mise doctor
mise up
mise dotfiles status
mise run bundle-update
```

## What `mise bootstrap` does

1. Reads `[bootstrap.packages]` and installs system packages:
   - macOS: `brew:*` formulae
   - Arch: `pacman:*` packages
2. Reads `[bootstrap.user]` and sets the login shell (Arch only; macOS uses `install.sh`)
3. Reads `[dotfiles]` and symlinks config from `~/.dotfiles/` into `~/$HOME`

Then `mise install` installs everything in `[tools]`.

## The unified config layout

A single file, `~/.dotfiles/mise/config.toml`, is shared by both platforms:

- macOS gets it via mise `[dotfiles]`
- Arch gets it via a symlink: `~/.config/mise` → `~/.dotfiles/mise`

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

### 2. Initial clone must bypass `~/.gitconfig`

Run `GIT_CONFIG_GLOBAL=/dev/null git clone ...` before the SSH key exists. Once `~/.gitconfig` is symlinked, every HTTPS GitHub URL becomes SSH.

### 3. `~/.config/mise` must be a directory symlink

Originally only `~/.config/mise/config.toml` was symlinked. After the `Configs/` → root restructure, `~/.config/mise` itself is symlinked to `~/.dotfiles/mise` so task scripts resolve correctly.

### 4. Old `Configs/` symlinks break after restructure

If upgrading from the old layout, symlinks still point to `~/.dotfiles/Configs/...`. Delete the stale directory and reapply:

```bash
rm -rf ~/.dotfiles/Configs
mise dotfiles apply
```

### 5. Real files can block dotfiles apply

If a target path exists as a real file or directory, mise refuses to overwrite it. We hit this with:

- `~/.config/ghostty/config`
- `~/.config/opencode/plugins`

Remove or back them up, then rerun `mise dotfiles apply`.

### 6. `~/.pi` was a stale directory symlink

In the old layout `~/.pi` symlinked to `~/.dotfiles/Configs/pi/.pi`. The new layout manages individual files under `~/.pi/agent/`. Remove the old symlink and recreate the parent directory:

```bash
rm ~/.pi
mkdir -p ~/.pi/agent
mise dotfiles apply
```

### 7. TPM clone fails without `GIT_CONFIG_GLOBAL=/dev/null`

The bootstrap task clones `tmux-plugins/tpm` over HTTPS. Because `~/.gitconfig` is already in place, the task uses `GIT_CONFIG_GLOBAL=/dev/null` to avoid the SSH rewrite.

### 8. `.env` is not created automatically

`mise/.example.env` is tracked; `mise/.env` is gitignored. Copy and edit it per machine:

```bash
cp ~/.dotfiles/mise/.example.env ~/.config/mise/.env
```

### 9. Some dotfiles are platform-only

`~/.aerospace.toml`, `~/.config/ghostty/config`, and `~/Brewfile` are declared for macOS. On Arch they show as `applied` symlinks even though the tools themselves may not be installed.

### 10. `mise doctor` PATH warning

`~/.local/share/omarchy/bin` may take precedence over mise shims in `PATH`. This is a warning, not an error, but be aware if tools resolve unexpectedly.

### 11. SSH key generation is manual

`mise run bootstrap` no longer creates an SSH key. Generate one yourself when you need git push/pull access:

```bash
ssh-keygen -t ed25519 -C "$USER@$(hostname)"
cat ~/.ssh/id_ed25519.pub
```

Then add the public key to GitHub at https://github.com/settings/keys.

### 12. Scroll direction defaults to Apple-style natural scrolling

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

### 13. Manual font installs

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

# SSH key exists
ls ~/.ssh/id_ed25519
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
mise run bootstrap      # SSH key + TPM
mise dotfiles apply     # re-converge symlinks
```

For any git operation that must use HTTPS before the SSH key is registered, prefix with `GIT_CONFIG_GLOBAL=/dev/null`.
