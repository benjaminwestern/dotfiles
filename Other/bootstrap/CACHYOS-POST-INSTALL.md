# CachyOS Post-Install Contract

This is the operator-facing ledger for applying these dotfiles after installing
CachyOS. It describes the current item set and execution order for a native
CachyOS machine. The implementation remains authoritative when this document
and the code disagree.

The package and tool declarations use `latest`. The catalogue membership is
explicit, but installed versions are intentionally not locked.

## Base Image Assumptions

The managed desktop configuration targets the CachyOS Hyprland Noctalia image.
It assumes the base installation already provides:

```text
Hyprland with Lua configuration support
Noctalia
UWSM
NetworkManager with its service active
Dolphin
GNOME Text Editor
GNOME Calculator
hyprpicker
xhost
dbus-update-activation-environment
```

The bootstrap does not currently install or audit those desktop prerequisites.
It owns `~/.config/hypr` as a whole-directory symlink, so this desktop contract
should not be applied to another Hyprland setup unless that path is explicitly
preserved.

## Canonical Commands

```bash
# Fresh CachyOS installation
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh \
  | bash

# Repeatable convergence and inspection
~/.dotfiles/install.sh ensure
~/.dotfiles/install.sh ensure --dry-run
~/.dotfiles/install.sh update
~/.dotfiles/install.sh audit --general
~/.dotfiles/install.sh audit --profile home
~/.dotfiles/install.sh audit --expect-state
```

## Profile Defaults

| Setting | `home` | `work` | `minimal` |
| --- | --- | --- | --- |
| Preferred shell | Fish | Fish | Bash |
| Native package catalogue | On | On | Off |
| Application catalogue | On | On | Off |
| Mise tool catalogue | On | On | Off |
| Managed dotfiles | On | On | Off |
| Create `~/code` | On | On | On |
| Git identity | On | On | On |
| Hostname | On | On | On |
| Browser/PDF defaults | On | On | Off |
| SSH service | On | On | Off |
| PC/SC smart-card service | On | On | Off |
| Change login shell | On | On | Off |
| Zscaler trust | Off | Auto-detect | Off |

The interactive plan can change each independently selectable setting. PC/SC
service activation follows the native package selection because it supports the
declared YubiKey stack. Saved choices are written to
`~/.config/dotfiles/state.env` and reused by `ensure` and `audit --expect-state`.

## Apply Order

The Linux foundation executes these actions in order:

1. Detect CachyOS and select pacman.
2. Install or update standalone Mise, with minimum version `2026.7.14`.
3. Install Gum through Mise.
4. Resolve, display, and confirm the selected profile and overrides.
5. Save the resolved plan in `~/.config/dotfiles/state.env`.
6. Install the mandatory native baseline.
7. Ensure the persistent checkout exists at `~/.dotfiles`.
8. Link or seed `~/.config/mise` and create private `mise/.env` state.
9. In `update` mode, upgrade the selected native package catalogue.
10. Reconcile the selected native package catalogue and greetd keyring PAM hooks.
11. Add system Flathub and reconcile the selected Flatpak and AUR applications.
12. Create `~/code` and optionally manage the Downloads symlink.
13. Apply selected dotfiles and Git identity.
14. Install Tmux Plugin Manager.
15. Remove conflicting CachyOS Pure prompt packages when Fish is selected.
16. Install and reconcile Fisher plugins.
17. Apply shell fallback configuration when tracked dotfiles are disabled.
18. Configure optional Zscaler trust.
19. Set the hostname.
20. Install and enable OpenSSH server access.
21. Enable PC/SC smart-card socket activation.
22. Set browser and PDF MIME defaults.
23. Set the login shell and shell activation blocks.
24. Install the selected Mise tool catalogue.
25. Validate core tools and managed dotfile status.

## Mandatory Baseline

Every profile installs these native packages before optional catalogues:

```text
ca-certificates
curl
git
openssh
bash
tar
```

Standalone Mise and Mise-managed Gum are also mandatory.

## Home And Work Native Packages

The pacman catalogue in `mise/config.linux.toml` is:

```text
bash
git
gnome-keyring
tree
tmux
fish
fisher
graphviz
usbutils
fprintd
libfprint
yubikey-manager
python-pyscard
ccid
pcsclite
gnupg
pinentry
nmap
wireguard-tools
nm-connection-editor
7zip
automake
gcc
pkgconf
luarocks
wget
coreutils
ffmpeg
imagemagick
podman
podman-compose
ghostty
noctalia
satty
base-devel
curl
unzip
openssh
xclip
clang
xz
zsh
flatpak
```

The bootstrap does not remove undeclared packages. Alacritty is not declared and
will therefore not be reinstalled after its manual removal.

## Home And Work Applications

Mise installs these as system Flatpaks:

```text
com.visualstudio.code       Visual Studio Code
com.google.Chrome           Google Chrome on x86_64
org.chromium.Chromium       Chromium instead of Chrome on ARM64
app.zen_browser.zen         Zen Browser
md.obsidian.Obsidian        Obsidian
com.yubico.yubioath         Yubico Authenticator on x86_64
```

Only one of Chrome or Chromium is selected for a given architecture. Flathub
does not currently publish an ARM64 Yubico Authenticator ref, so that GUI is
selected only on x86_64; the native YubiKey CLI and PC/SC stack remain selected.

On pacman-family systems, the application stage can also install this maintained
AUR package. It uses an existing `paru`, or installs `paru` from the
distribution repository when available. Missing AUR applications require an
interactive run and explicit PKGBUILD review:

```text
opencode-desktop-bin        OpenCode Desktop
```

## Home And Work Mise Tools

Shared tools from `mise/config.toml`:

```text
go
go:golang.org/x/tools/gopls
go:github.com/air-verse/air
github:golangci/golangci-lint
go:mvdan.cc/gofumpt
go:github.com/charmbracelet/glow
go:github.com/charmbracelet/freeze
go:github.com/charmbracelet/vhs
go:github.com/hashicorp/terraform-mcp-server/cmd/terraform-mcp-server
go:oss.terrastruct.com/d2
github:mikefarah/yq
go:github.com/swaggo/swag/cmd/swag
github:sqlc-dev/sqlc
go:github.com/GoogleCloudPlatform/cloud-sql-proxy/v2
cargo:stylua
github:tree-sitter/tree-sitter
node
bun
npm:opencode-ai
npm:@opencode-ai/cli
npm:@earendil-works/pi-coding-agent
npm:@playwright/cli
npm:@dataform/cli
npm:wrangler
npm:@googleworkspace/cli
npm:markit-ai
npm:@kitlangton/ghui
npm:hunkdiff
npm:@kitlangton/motel
python
uv
pipx
pipx:sqlfluff
pipx:mitmproxy
lua@5.1
rust
terraform
pitchfork
gcloud
skaffold
pkl
gum
hk
fnox
communique
usage
```

Linux additions from `mise/config.linux.toml`:

```text
neovim
fastfetch
lazygit
github-cli
gitleaks
jq
zoxide
fzf
fd
ripgrep
btop
yt-dlp
shellcheck
cmake
protobuf
tokei
cargo:resvg
cargo:tlrc
worktrunk
duckdb
caddy
kubectl
llama.cpp
```

## Managed Dotfile Targets

Home and work profiles manage these targets:

```text
~/.bash_profile
~/.bashrc
~/.config/fish
~/.config/gh/config.yml
~/.config/ghostty/config
~/.config/git/ignore
~/.config/hypr
~/.config/mise
~/.config/nvim
~/.config/opencode/opencode.json
~/.config/opencode/plugins
~/.config/pitchfork/Caddyfile
~/.config/pitchfork/config.toml
~/.config/worktrunk/config.toml
~/.hushlogin
~/.pi/agent/APPEND_SYSTEM.md
~/.pi/agent/extensions
~/.pi/agent/mcp.json
~/.pi/agent/model-system
~/.pi/agent/settings.json
~/.ssh/config
~/.tmux.conf
~/.zprofile
~/.zshrc
```

Mise applies dotfiles in force mode unless a target is passed through
`--preserve`. Mise and Fish receive dedicated bootstrap backups before takeover.

## System State Changes

| Surface | Home/work behavior |
| --- | --- |
| Hostname | Set to the selected device name |
| Login shell | Set to Fish by default |
| SSH | Install OpenSSH and enable `sshd.service` |
| Smart cards | Enable `pcscd.socket`, falling back to `pcscd.service` |
| Git credentials | Store machine-local HTTPS credentials in GNOME Keyring and unlock it through greetd PAM |
| Browser defaults | Assign HTTP, HTTPS, HTML, and XHTML to Zen; PDF to Chrome/Chromium |
| Flatpak | Add system Flathub and install system applications |
| Fish | Install Fisher and reconcile `fish_plugins` |
| Tmux | Clone TPM; `mise run bootstrap` installs declared plugins |
| Git | Generate or augment user-owned identity configuration |
| Zscaler | Work profile captures detected trust chain into private Mise state |

When Fish is selected on CachyOS, the bootstrap removes
`cachyos-fish-config` and `fish-pure-prompt`, preserves required dependencies,
and erases persistent `pure_*` Fish variables. These are the only intentional
CachyOS package removals.

## Manual And Excluded Actions

The bootstrap intentionally does not:

```text
generate or register SSH keys
enroll fingerprints or edit PAM outside the managed greetd keyring hooks
configure a firewall
create or start a Podman machine
create a WireGuard profile
configure YubiKey credentials
install the manually selected Ghostty font
remove arbitrary undeclared applications
reboot the machine
```

Fingerprint enrollment, other PAM changes, SSH credentials, WireGuard profiles,
and YubiKey personalization remain explicit operator actions.

## Validation

After a CachyOS run, use:

```bash
~/.dotfiles/install.sh audit --general
~/.dotfiles/install.sh audit --profile home
~/.dotfiles/install.sh audit --expect-state
~/.dotfiles/install.sh ensure --dry-run
```

The audit reports native packages, Flatpaks, tool and dotfile state, SSH,
PC/SC, greetd keyring PAM, and desktop defaults. A converged dry run should
report zero fixes.

## Implementation Sources

```text
install.sh
Other/scripts/linux/foundation-linux.sh
Other/scripts/linux/audit-linux.sh
Other/scripts/linux/lib/common.sh
mise/config.toml
mise/config.linux.toml
hypr/
```
