#!/bin/bash
# =============================================================================
# foundation-debian.sh -- Debian / Raspberry Pi OS foundation bootstrap
#
# Installs the core CLI toolchain and symlinks dotfile configs via tuckr.
#
# Usage:
#   ./foundation-debian.sh setup
#   ./foundation-debian.sh ensure
#   ./foundation-debian.sh update
#
# Architecture:
#   Bash (not zsh) for maximum portability on minimal Debian installs.
#   Sources lib/common.sh for status output, dry-run gating, and helpers.
#
# Design:
#   - apt packages for system-level tools
#   - mise for language runtimes (go, node, python, rust, etc.)
#   - tuckr for dotfile symlinks (same tool as macOS, keeps configs in the repo)
#   - neovim from GitHub releases (apt ships 0.7.2, too old for kickstart)
#   - tree-sitter-cli built via cargo (prebuilt binaries need glibc 2.39+)
#
# Glibc note: Debian Bookworm ships glibc 2.36.  Many prebuilt binaries
# (including mise's own runtimes occasionally) target 2.39+.  Where possible
# we use system packages or cargo builds that link against the system glibc.
#
# == Pre-requisites & known gaps ==
#
# This script assumes an existing Debian / Raspberry Pi OS machine with:
#   - SSH access (Pi OS Lite: create /boot/ssh on the SD card, or
#     run `sudo systemctl enable ssh && sudo systemctl start ssh`)
#   - Internet connectivity (watch for dead usb0 default routes on Pi —
#     see the fix-usb0-route systemd unit in this repo)
#   - `sudo` access for the current user (Pi OS default: passwordless)
#   - Sufficient disk (~2 GB free) and RAM (~2 GB) for cargo builds
#
# Architecture: URLs for neovim and worktrunk are hardcoded for aarch64.
# For x86_64 Debian, swap the download URLs in ensure_neovim() and
# ensure_worktrunk().
#
# Post-bootstrap manual steps (not automated):
#   - First `nvim` run downloads all lazy.nvim plugins — pre-warm with:
#     nvim --headless "+Lazy! sync" +qa
#   - Treesitter parsers compile on first file open (needs gcc, present
#     via build-essential)
#   - `usage` auto-completions are not generated — run:
#     usage generate completion --usage-cmd mise fish mise > ~/.config/fish/completions/usage-mise.fish
#   - Mise activation needs shell restart:  exec fish  (or re-login)
#   - Register the generated SSH key with GitHub before pushing:
#     cat ~/.ssh/id_ed25519.pub  →  https://github.com/settings/keys
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# -- Paths -------------------------------------------------------------------
BOOTSTRAP_ROOT="${BOOTSTRAP_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
MISE_CONFIG_DIR="$HOME/.config/mise"
MISE_CONFIG_PATH="$MISE_CONFIG_DIR/config.toml"
MISE_ENV_PATH="$MISE_CONFIG_DIR/.env"

# -- apt packages ------------------------------------------------------------
FOUNDATION_PACKAGES=(
  fish tmux git gh ripgrep fd-find fzf zoxide jq btop build-essential
  curl wget unzip ca-certificates openssh-client xclip luarocks libclang-dev
  xz-utils nmap graphviz imagemagick yt-dlp ffmpeg tree zsh
)

MODE="${1:-setup}"


# =============================================================================
# SECTION 1: APT PACKAGES
# =============================================================================

ensure_apt_updated() {
  if dry_run_active; then dry_run_log "apt update"; return 0; fi
  sudo apt update -qq
  status_pass "apt update" "package index refreshed"
}

install_foundation_packages() {
  local pkg present=0 missing=0 total=${#FOUNDATION_PACKAGES[@]}
  local to_install=()
  for pkg in "${FOUNDATION_PACKAGES[@]}"; do
    if apt_pkg_installed "$pkg"; then present=$((present + 1))
    else to_install+=("$pkg"); missing=$((missing + 1)); fi
  done
  if [[ "$missing" -eq 0 ]]; then status_pass "Foundation packages" "${present}/${total} present"; return 0; fi
  run_or_dry sudo apt install -y "${to_install[@]}"
  if dry_run_active; then status_fix "Foundation packages" "would install ${missing} missing"
  else status_fix "Foundation packages" "installed ${missing} missing"; fi
}

ensure_fd_symlink() {
  if command_exists fd; then status_pass "fd symlink" "already available"; return 0; fi
  if ! command_exists fdfind; then status_skip "fd symlink" "fdfind not installed"; return 0; fi
  mkdir -p "$HOME/.local/bin"
  if [[ -L "$HOME/.local/bin/fd" ]]; then status_pass "fd symlink" "already exists"; return 0; fi
  run_or_dry ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
  if dry_run_active; then status_fix "fd symlink" "would create"
  else status_fix "fd symlink" "created ~/.local/bin/fd → $(which fdfind)"; fi
}

update_packages() {
  run_or_dry sudo apt update -qq; run_or_dry sudo apt upgrade -y
  run_or_dry sudo apt autoremove -y; run_or_dry sudo apt autoclean
  if dry_run_active; then status_fix "apt upgrade" "would upgrade all"
  else status_pass "apt upgrade" "all packages upgraded"; fi
}


# =============================================================================
# SECTION 2: NEOVIM (GitHub releases — apt ships 0.7.2)
# =============================================================================

ensure_neovim() {
  if command_exists nvim; then
    status_pass "Neovim" "$(nvim --version 2>/dev/null | head -1)"
    return 0
  fi
  if dry_run_active; then dry_run_log "download neovim arm64 tarball"; status_fix "Neovim" "would install"; return 0; fi

  local url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-arm64.tar.gz"
  curl -fsSL -o /tmp/nvim.tar.gz "$url"
  tar xzf /tmp/nvim.tar.gz -C /tmp
  rm -rf "$HOME/.local/nvim" 2>/dev/null
  mv /tmp/nvim-linux-arm64 "$HOME/.local/nvim"
  ln -sf "$HOME/.local/nvim/bin/nvim" "$HOME/.local/bin/nvim"
  rm /tmp/nvim.tar.gz

  if command_exists nvim; then status_fix "Neovim" "$(nvim --version | head -1)"
  else status_fail "Neovim" "installation failed"; fi
}


# =============================================================================
# SECTION 3: MISE
# =============================================================================

ensure_mise() {
  if command_exists mise; then status_pass "Mise" "$(mise --version 2>/dev/null)"; return 0; fi
  if dry_run_active; then dry_run_log "curl https://mise.run | sh"; status_fix "Mise" "would install"; return 0; fi
  curl -fsSL https://mise.run | sh
  export PATH="$HOME/.local/bin:$PATH"
  if command_exists mise; then status_fix "Mise" "installed via shell installer"
  else status_fail "Mise" "installation failed"; fi
}

seed_mise_config() {
  cat <<'EOF'
[settings]
experimental = true
trusted_config_paths = ["~/.config/mise/config.toml"]

[env]
_.file = "~/.config/mise/.env"

[tools]
go = "latest"
"go:golang.org/x/tools/gopls" = { version = "latest" }
"go:github.com/go-delve/delve/cmd/dlv" = { version = "latest" }
"go:github.com/golangci/golangci-lint/v2/cmd/golangci-lint" = { version = "latest" }
"go:mvdan.cc/gofumpt" = { version = "latest" }
"go:github.com/air-verse/air" = { version = "latest" }
"go:github.com/charmbracelet/glow" = { version = "latest" }
"go:oss.terrastruct.com/d2" = { version = "latest" }
"go:github.com/mikefarah/yq/v4" = { version = "latest" }
"cargo:stylua" = { version = "latest" }
"cargo:tree-sitter-cli" = { version = "latest" }

node = "latest"
"npm:opencode-ai" = "latest"
"npm:@earendil-works/pi-coding-agent" = "latest"
bun = "latest"
"npm:@playwright/cli" = "latest"

usage = "latest"

python = "latest"
uv = "latest"
pipx = "latest"

lua = "5.1"
rust = "latest"
EOF
}

ensure_mise_config() {
  mkdir -p "$MISE_CONFIG_DIR"
  if [[ -f "$MISE_CONFIG_PATH" ]]; then status_pass "Mise config" "already exists"; return 0; fi
  run_or_dry bash -c "seed_mise_config > $MISE_CONFIG_PATH"
  if dry_run_active; then status_fix "Mise config" "would create"
  else seed_mise_config > "$MISE_CONFIG_PATH"; status_fix "Mise config" "created"; fi
}

ensure_mise_env() {
  mkdir -p "$MISE_CONFIG_DIR"
  if [[ -f "$MISE_ENV_PATH" ]]; then status_pass "Mise .env" "already exists"; return 0; fi
  if dry_run_active; then dry_run_log "create placeholder $MISE_ENV_PATH"; status_fix "Mise .env" "would create"; return 0; fi
  cat > "$MISE_ENV_PATH" <<<'EOF'
# Mise environment variables — add API keys and secrets here
EDITOR=nvim
EOF
  status_fix "Mise .env" "created placeholder"
}

ensure_mise_tools() {
  if ! command_exists mise; then status_skip "Mise tools" "mise not installed"; return 0; fi
  if dry_run_active; then dry_run_log "mise trust --all && mise install"; status_fix "Mise tools" "would install"; return 0; fi
  mise trust --all 2>/dev/null || true
  mise install
  status_pass "Mise tools" "runtimes installed"

  # Upgrade zoxide: apt ships 0.4.3 which has a cd recursion bug in fish.
  # Rebuild via cargo (now available via mise) to get a current version
  # that handles `--cmd cd` cleanly.
  if command_exists cargo; then
    cargo install zoxide 2>&1 | tail -1
    if [[ -f "$HOME/.cargo/bin/zoxide" ]]; then
      cp "$HOME/.cargo/bin/zoxide" "$HOME/.local/bin/zoxide"
      note "zoxide upgraded to $(zoxide --version 2>/dev/null || echo unknown)"
    fi
  fi

  # Remove broken npm tree-sitter-cli (prebuilt binary needs glibc 2.39,
  # Debian Bookworm ships 2.36).  The cargo-built version (from the seed
  # config above) links against the system glibc and works correctly.
  if [[ -d "$HOME/.local/share/mise/installs/node" ]]; then
    npm uninstall -g tree-sitter-cli 2>/dev/null || true
  fi
  if command_exists cargo && [[ ! -f "$HOME/.local/bin/tree-sitter" ]]; then
    if [[ -f "$HOME/.cargo/bin/tree-sitter" ]]; then
      cp "$HOME/.cargo/bin/tree-sitter" "$HOME/.local/bin/tree-sitter"
    fi
  fi
}

update_mise() {
  if ! command_exists mise; then status_skip "Mise update" "mise not installed"; return 0; fi
  run_or_dry mise self-update || true; run_or_dry mise upgrade || true; run_or_dry mise install
  if dry_run_active; then status_fix "Mise update" "would upgrade"
  else status_pass "Mise update" "binary + tools upgraded"; fi
}


# =============================================================================
# SECTION 4: WORKTRUNK
# =============================================================================

ensure_worktrunk() {
  if command_exists wt; then status_pass "Worktrunk" "$(wt --version 2>/dev/null)"; return 0; fi
  local ver="0.56.0"
  local url="https://github.com/max-sixty/worktrunk/releases/download/v${ver}/worktrunk-aarch64-unknown-linux-musl.tar.xz"
  if dry_run_active; then dry_run_log "download worktrunk $ver"; status_fix "Worktrunk" "would install"; return 0; fi
  mkdir -p "$HOME/.local/bin"
  curl -fsSL -o /tmp/worktrunk.tar.xz "$url"
  tar xf /tmp/worktrunk.tar.xz -C /tmp
  cp "/tmp/worktrunk-aarch64-unknown-linux-musl/wt" "$HOME/.local/bin/wt"
  cp "/tmp/worktrunk-aarch64-unknown-linux-musl/git-wt" "$HOME/.local/bin/git-wt" 2>/dev/null || true
  chmod +x "$HOME/.local/bin/wt" "$HOME/.local/bin/git-wt" 2>/dev/null || true
  rm -rf /tmp/worktrunk*
  if command_exists wt; then status_fix "Worktrunk" "$(wt --version)"
  else status_fail "Worktrunk" "installation failed"; fi
}


# =============================================================================
# SECTION 5: TUCKR — DOTFILE SYMLINKS
# =============================================================================

# tuckr is the same symlink manager used on macOS.  It reads Configs/ groups
# from ~/.dotfiles and creates symlinks into $HOME.  We build it from source
# via cargo (no arm64 prebuilt binary) after mise + rust are available.
#
# Linux-compatible groups: bash fish gh git nvim opencode pi ssh tmux
#                          worktrunk zsh
# Managed manually: mise (Linux toolset differs from macOS)
# Skipped: aerospace borders brew ghostty hypr (macOS-only or desktop)

ensure_tuckr() {
  if command_exists tuckr; then status_pass "Tuckr" "$(tuckr --version 2>/dev/null)"; return 0; fi
  if ! command_exists cargo; then status_fail "Tuckr" "cargo not available — run mise tools first"; return 0; fi
  if dry_run_active; then dry_run_log "cargo install tuckr"; status_fix "Tuckr" "would build"; return 0; fi

  git config --global --unset url.git@github.com:.insteadOf 2>/dev/null || true
  cargo install --git https://github.com/RaphGL/Tuckr --tag 0.13.1 tuckr 2>/dev/null
  git config --global url."git@github.com:".insteadOf https://github.com 2>/dev/null || true

  if [[ -f "$HOME/.cargo/bin/tuckr" ]]; then
    cp "$HOME/.cargo/bin/tuckr" "$HOME/.local/bin/tuckr"
    status_fix "Tuckr" "built from source ($(tuckr --version 2>/dev/null))"
  else
    status_fail "Tuckr" "build failed"
  fi
}

apply_tuckr_configs() {
  if ! command_exists tuckr; then status_skip "Tuckr configs" "tuckr not installed"; return 0; fi
  if dry_run_active; then dry_run_log "tuckr add <groups>"; status_fix "Tuckr configs" "would symlink"; return 0; fi

  cd "$BOOTSTRAP_ROOT"

  # Pre-create directories tuckr needs
  mkdir -p "$HOME/.ssh" "$HOME/.config" "$HOME/code"
  mkdir -p "$HOME/.config/nvim" "$HOME/.config/gh" "$HOME/.config/opencode"
  mkdir -p "$HOME/.config/worktrunk" "$HOME/.pi/agent"
  chmod 700 "$HOME/.ssh"

  local group
  for group in bash fish gh git nvim opencode pi ssh tmux worktrunk zsh; do
    # Remove stale real files so tuckr can create fresh symlinks
    case "$group" in
      nvim)     rm -rf "$HOME/.config/nvim" 2>/dev/null; mkdir -p "$HOME/.config/nvim" ;;
      pi)       rm -rf "$HOME/.pi" 2>/dev/null; mkdir -p "$HOME/.pi" ;;
      opencode) rm -rf "$HOME/.config/opencode" 2>/dev/null; mkdir -p "$HOME/.config/opencode" ;;
      fish)     rm -rf "$HOME/.config/fish" 2>/dev/null; mkdir -p "$HOME/.config/fish" ;;
      bash)     rm -f "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.hushlogin" 2>/dev/null ;;
      git)      rm -f "$HOME/.gitconfig" "$HOME/.config/git/ignore" 2>/dev/null ;;
      ssh)      rm -f "$HOME/.ssh/config" 2>/dev/null ;;
      tmux)     rm -f "$HOME/.tmux.conf" 2>/dev/null ;;
      worktrunk) rm -f "$HOME/.config/worktrunk/config.toml" 2>/dev/null ;;
      zsh)      rm -f "$HOME/.zshrc" "$HOME/.zprofile" 2>/dev/null ;;
      gh)       rm -f "$HOME/.config/gh/config.yml" "$HOME/.config/gh/hosts.yml" 2>/dev/null ;;
    esac
    tuckr add "$group" 2>&1 | tail -1
  done

  status_fix "Tuckr configs" "symlinked 12 groups"
}


# =============================================================================
# SECTION 6: TMUX PLUGIN MANAGER
# =============================================================================

ensure_tpm() {
  local tpm_dir="$HOME/.tmux/plugins/tpm"
  if [[ -d "$tpm_dir" ]]; then status_pass "Tmux plugin manager" "already installed"; return 0; fi
  run_or_dry git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
  if dry_run_active; then status_fix "Tmux plugin manager" "would install"
  else status_fix "Tmux plugin manager" "installed"; fi
}


# =============================================================================
# SECTION 7: SSH KEY CHECK
# =============================================================================

ensure_ssh_keys() {
  # If keys already exist, ensure correct permissions
  if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    chmod 600 "$HOME/.ssh/id_ed25519" 2>/dev/null || true
    status_pass "SSH keys" "ed25519 key present"
    return 0
  fi
  if [[ -f "$HOME/.ssh/id_rsa" ]]; then
    chmod 600 "$HOME/.ssh/id_rsa" 2>/dev/null || true
    status_pass "SSH keys" "RSA key present"
    return 0
  fi

  # Generate a fresh key pair — no dependencies on another machine
  if dry_run_active; then
    dry_run_log "ssh-keygen -t ed25519 -C hostname@hostname"
    status_fix "SSH keys" "would generate ed25519 key"
    return 0
  fi

  local host; host="$(hostname)"
  ssh-keygen -t ed25519 -C "$USER@$host" -f "$HOME/.ssh/id_ed25519" -N ""
  chmod 600 "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.pub"
  status_fix "SSH keys" "generated new ed25519 key for $USER@$host"
  echo ""
  echo "  ┌─────────────────────────────────────────────────────┐"
  echo "  │ Register this key with GitHub:                      │"
  echo "  │   cat ~/.ssh/id_ed25519.pub                         │"
  echo "  │   → https://github.com/settings/keys                │"
  echo "  │ Then re-run: foundation-debian.sh ensure             │"
  echo "  └─────────────────────────────────────────────────────┘"
  echo ""
}


# =============================================================================
# SECTION 8: SHELL DEFAULT
# =============================================================================

ensure_fish_default() {
  local fish_bin; fish_bin="$(which fish 2>/dev/null || echo '')"
  if [[ -z "$fish_bin" ]]; then status_skip "Default shell" "fish not installed"; return 0; fi
  if ! grep -qx "$fish_bin" /etc/shells 2>/dev/null; then
    run_or_dry sudo sh -c "echo '$fish_bin' >> /etc/shells"
  fi
  if [[ "$SHELL" == "$fish_bin" ]]; then status_pass "Default shell" "already fish"; return 0; fi
  run_or_dry chsh -s "$fish_bin" 2>/dev/null || note "chsh needs password — run: chsh -s $fish_bin"
  if dry_run_active; then status_fix "Default shell" "would set to $fish_bin"
  else status_fix "Default shell" "set to $fish_bin (re-login to take effect)"; fi
}


# =============================================================================
# SECTION 9: VALIDATION
# =============================================================================

validate_foundation() {
  for tool in fish nvim tmux git gh rg fdfind zoxide jq btop mise wt tuckr; do
    local bin="$tool"
    case "$tool" in fdfind) bin="fdfind" ;; rg) bin="rg" ;; esac
    if command_exists "$bin"; then status_pass "Validate: $tool" "$(which "$bin")"
    else status_fail "Validate: $tool" "not found on PATH"; fi
  done

  # Verify nvim starts headless with no errors
  if command_exists nvim; then
    if nvim --headless +qa 2>&1 | grep -qE "^Error|E[0-9]+"; then
      status_fail "Validate: nvim headless" "startup errors detected"
    else
      status_pass "Validate: nvim headless" "no startup errors"
    fi
  fi

  # Verify tree-sitter works (must be cargo-built, not npm)
  if command_exists tree-sitter; then
    if tree-sitter --version 2>&1 | grep -q "GLIBC"; then
      status_fail "Validate: tree-sitter" "npm version needs glibc 2.39, use cargo build"
    else
      status_pass "Validate: tree-sitter" "$(tree-sitter --version 2>&1 | head -1)"
    fi
  fi
}


# =============================================================================
# SECTION 10: MAIN
# =============================================================================

main() {
  echo ""
  printf "${_BOLD}Debian foundation bootstrap${_RESET}\n"
  printf "Mode: ${_BOLD}%s${_RESET}  Dotfiles: ${_BLUE}%s${_RESET}\n" "$MODE" "$BOOTSTRAP_ROOT"
  if dry_run_active; then printf "${_YELLOW}*** DRY RUN ***${_RESET}\n"; fi
  echo ""

  case "$MODE" in
    setup|ensure)
      ensure_apt_updated
      install_foundation_packages
      ensure_fd_symlink
      ensure_neovim
      ensure_mise
      ensure_mise_config
      ensure_mise_env
      ensure_mise_tools      # must run before tuckr (needs cargo)
      ensure_worktrunk
      ensure_tuckr            # builds from source via cargo
      apply_tuckr_configs     # symlinks all configs
      ensure_tpm
      ensure_ssh_keys
      ensure_fish_default
      validate_foundation
      ;;
    update)
      ensure_apt_updated; update_packages; install_foundation_packages
      ensure_neovim; ensure_mise; update_mise; ensure_worktrunk
      ensure_tuckr; apply_tuckr_configs
      validate_foundation
      ;;
    *) fail "Unknown mode: $MODE. Use setup, ensure, or update." ;;
  esac

  status_summary "Foundation"
  success "Debian foundation complete."
  echo ""
  echo "Next steps:"
  echo "  - Register SSH key:  cat ~/.ssh/id_ed25519.pub  →  https://github.com/settings/keys"
  echo "  - Set fish shell:  ssh -t pi5 chsh -s /usr/bin/fish"
  echo "  - Open nvim once:  nvim --headless '+Lazy! sync' +qa"
}

main
