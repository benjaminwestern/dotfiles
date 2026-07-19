#!/bin/zsh
# =============================================================================
# foundation-macos.zsh -- macOS foundation bootstrap
#
# Installs and configures the core tooling layer that every macOS machine needs
# regardless of personal preferences: Homebrew, standalone mise, mise-managed
# Gum, shell activation, and any explicitly selected catalogue or system stage.
#
# Can be invoked in two ways:
#   1. Via install.sh or bootstrap-macos.zsh
#   2. Directly: ./foundation-macos.zsh setup --shell fish --profile work
#
# Architecture:
#   Sources lib/common.zsh for all shared utilities (status output, state file,
#   flag resolution, managed block writer, gum UI helpers).
#
# Design principles:
#   - Absolute idempotency: check before act, never destructive
#   - Feature-flag gating: every function respects RESOLVED_* flags
#   - Status output: every ensure/check emits status_pass/fix/skip/fail
#   - Shell-aware: writes correct profile block for RESOLVED_SHELL
# =============================================================================

set -euo pipefail


# =============================================================================
# SECTION 1: HEADER & CONSTANTS
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.zsh"

# -- Mise paths ---------------------------------------------------------------
MISE_CONFIG_DIR="$HOME/.config/mise"
MISE_CONFIG_PATH="$MISE_CONFIG_DIR/config.toml"
MISE_ENV_PATH="$MISE_CONFIG_DIR/.env"

# -- Certificate / Zscaler paths ---------------------------------------------
CERTS_DIR="$HOME/certs"
ZSCALER_CHAIN_PATH="$CERTS_DIR/zscaler_chain.pem"
GOLDEN_BUNDLE_PATH="$CERTS_DIR/golden_pem.pem"

# -- Bootstrap root -----------------------------------------------------------
# When called directly (not via install.sh), BOOTSTRAP_ROOT defaults to the
# dotfiles repository root (three levels above this script).
BOOTSTRAP_ROOT="${BOOTSTRAP_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

# -- MODE env var -------------------------------------------------------------
# May be pre-set by install.sh or the caller's environment.
MODE="${MODE:-}"


# =============================================================================
# SECTION 2: ARGUMENT PARSING
# =============================================================================

# parse_foundation_args -- Parse CLI arguments for direct invocation
#
# What: Accepts the same flags as install.sh so the foundation script can be
#       run standalone without the public loader or bootstrap-macos.zsh.
# Why:  Enables direct execution for testing, CI, or users who prefer to skip
#       the entrypoint.
# Checks: Validates mode is not set twice; required values have arguments.
# Gates: None (always runs).
# Side effects: Populates CLI_* global variables used by resolve_all_flags.
# Idempotency: Overwrites CLI_* vars with the same values each time.
#
# Stores results in:
#   CLI_SHELL, CLI_PROFILE, CLI_ENABLE_ZSCALER, CLI_ENABLE_DOTFILES,
#   CLI_ENABLE_APPLICATIONS, CLI_ENABLE_MACOS_DEFAULTS,
#   CLI_ENABLE_REMOTE_ACCESS, CLI_ENABLE_ROSETTA, CLI_ENABLE_MISE_TOOLS,
#   CLI_ENABLE_SHELL_DEFAULT, NON_INTERACTIVE, ENABLE_PERSONAL
typeset -g CLI_SHELL=""
typeset -g CLI_PROFILE=""
typeset -g CLI_ENABLE_ZSCALER=""
typeset -g CLI_ENABLE_DOTFILES=""
typeset -g CLI_ENABLE_APPLICATIONS=""
typeset -g CLI_ENABLE_MACOS_DEFAULTS=""
typeset -g CLI_ENABLE_REMOTE_ACCESS=""
typeset -g CLI_ENABLE_ROSETTA=""
typeset -g CLI_ENABLE_MISE_TOOLS=""
typeset -g CLI_ENABLE_SHELL_DEFAULT=""
typeset -g CLI_ENABLE_PACKAGES=""
typeset -g CLI_ENABLE_CODE_DIRECTORY=""
typeset -g CLI_ENABLE_DOWNLOADS_LINK=""
typeset -g CLI_ENABLE_GIT_IDENTITY=""
typeset -g CLI_DEVICE_NAME=""
typeset -g CLI_GIT_USER_NAME=""
typeset -g CLI_GIT_USER_EMAIL=""
typeset -g CLI_MACOS_HOSTNAME=""
typeset -g CLI_MACOS_DOCK=""
typeset -g CLI_MACOS_DESKTOP=""
typeset -g CLI_MACOS_DEFAULT_APPS=""
typeset -g CLI_MACOS_MENU_BAR=""
typeset -g CLI_MACOS_MOUSE=""
typeset -g CLI_MACOS_POWER=""
typeset -g CLI_MACOS_FINDER=""
typeset -g CLI_MACOS_SCREENSHOTS=""
typeset -g CLI_MACOS_TOUCH_ID=""

foundation_usage() {
  cat <<'EOF'
Usage:
  foundation-macos.zsh [setup|ensure|update|personal] [options]

With no mode, launches the gum action/profile/plan menus.

Options:
  --shell <fish|zsh>       Set preferred shell
  --profile <work|home|minimal>
                           Set device profile preset
  --enable-<flag>          Enable a feature flag
  --disable-<flag>         Disable a feature flag
  --personal               Run the personal layer after foundation
  --device-name <name>     Set ComputerName, LocalHostName, and HostName
  --git-name <name>        Seed the Git author name
  --git-email <address>    Seed the Git author email
  --non-interactive        Disable interactive prompts
  --dry-run                Inspect drift and print only required repairs; do not apply them
  --dotfiles-repo <url>    Override dotfiles repository URL
  --personal-script <path> Override the personal bootstrap script path

Feature flags:
  packages, applications, mise-tools, dotfiles, code-directory,
  downloads-link, git-identity, macos-defaults, remote-access, rosetta,
  shell-default, zscaler

Granular macOS flags:
  macos-hostname, macos-dock, macos-desktop, macos-default-apps,
  macos-menu-bar, macos-mouse, macos-power, macos-finder,
  macos-screenshots, macos-touch-id

macOS group effects:
  hostname      Set the three machine names, never the signed-in account
  dock          Left, instant auto-hide, Ghostty + Chrome pins only
  desktop       Hide widgets and disable click-wallpaper-to-show-desktop
  default-apps  Chrome for web, HTML, and PDF handlers
  menu-bar      Wi-Fi, Bluetooth, Sound, optional battery; hide Spotlight;
                DDD DD MMM and 24-hour HH:MM:SS
  mouse         Disable mouse acceleration
  power         Headless Mac mini policy or shared MacBook sleep policy
  finder        Path/status bars, extensions, Library visibility, warnings
  screenshots   PNG format
  touch-id      Touch ID sudo, including inside tmux, through sudo_local

Profiles:
  work     Ben's complete work setup: Homebrew CLI catalogue, Brewfile,
           mise tools, dotfiles, all macOS preferences, remote access,
           Rosetta, Fish, home layout, Git identity, and Zscaler auto-detection.
  home     Ben's complete personal setup; the same broad configuration
           without Zscaler.
  minimal  Neutral adoption baseline: Homebrew, standalone mise, mise-managed
           Gum, device naming, Git identity, and ~/code. Ben's package,
           application, tool, and dotfile catalogues are off by default.

Interactive runs show these presets as editable defaults. Every stage and each
macOS preference group can be selected or deselected before anything planned
is applied. The signed-in macOS account is detected automatically and is never
renamed by this bootstrap.

Examples:
  ./foundation-macos.zsh setup --shell fish --profile work
  ./foundation-macos.zsh setup --profile minimal --shell zsh \
    --device-name ada-mac --git-name "Ada Lovelace" --git-email ada@example.com
  ./foundation-macos.zsh ensure
  ./foundation-macos.zsh update --dry-run
EOF
}

parse_foundation_args() {
  # If install.sh already parsed, these env vars will be set. Use them as
  # starting values so CLI flags here can override.
  CLI_SHELL="${PREFERRED_SHELL:-}"
  CLI_PROFILE="${DEVICE_PROFILE:-}"
  CLI_ENABLE_ZSCALER="${ENABLE_ZSCALER:-}"
  CLI_ENABLE_DOTFILES="${ENABLE_DOTFILES:-}"
  CLI_ENABLE_APPLICATIONS="${ENABLE_APPLICATIONS:-}"
  CLI_ENABLE_MACOS_DEFAULTS="${ENABLE_MACOS_DEFAULTS:-}"
  CLI_ENABLE_REMOTE_ACCESS="${ENABLE_REMOTE_ACCESS:-}"
  CLI_ENABLE_ROSETTA="${ENABLE_ROSETTA:-}"
  CLI_ENABLE_MISE_TOOLS="${ENABLE_MISE_TOOLS:-}"
  CLI_ENABLE_SHELL_DEFAULT="${ENABLE_SHELL_DEFAULT:-}"
  CLI_ENABLE_PACKAGES="${ENABLE_PACKAGES:-}"
  CLI_ENABLE_CODE_DIRECTORY="${ENABLE_CODE_DIRECTORY:-}"
  CLI_ENABLE_DOWNLOADS_LINK="${ENABLE_DOWNLOADS_LINK:-}"
  CLI_ENABLE_GIT_IDENTITY="${ENABLE_GIT_IDENTITY:-}"
  CLI_DEVICE_NAME="${DEVICE_NAME:-}"
  CLI_GIT_USER_NAME="${GIT_USER_NAME:-}"
  CLI_GIT_USER_EMAIL="${GIT_USER_EMAIL:-}"
  CLI_MACOS_HOSTNAME="${MACOS_HOSTNAME:-}"
  CLI_MACOS_DOCK="${MACOS_DOCK:-}"
  CLI_MACOS_DESKTOP="${MACOS_DESKTOP:-}"
  CLI_MACOS_DEFAULT_APPS="${MACOS_DEFAULT_APPS:-}"
  CLI_MACOS_MENU_BAR="${MACOS_MENU_BAR:-}"
  CLI_MACOS_MOUSE="${MACOS_MOUSE:-}"
  CLI_MACOS_POWER="${MACOS_POWER:-}"
  CLI_MACOS_FINDER="${MACOS_FINDER:-}"
  CLI_MACOS_SCREENSHOTS="${MACOS_SCREENSHOTS:-}"
  CLI_MACOS_TOUCH_ID="${MACOS_TOUCH_ID:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      setup|ensure|update|personal)
        if [[ -n "$MODE" ]]; then
          fail "Mode already set to '$MODE'; cannot set again to '$1'"
        fi
        MODE="$1"
        shift
        ;;
      --shell)
        [[ $# -ge 2 ]] || fail "--shell requires a value"
        CLI_SHELL="$2"
        shift 2
        ;;
      --profile)
        [[ $# -ge 2 ]] || fail "--profile requires a value"
        CLI_PROFILE="$2"
        shift 2
        ;;
      --enable-zscaler)     CLI_ENABLE_ZSCALER="true";  shift ;;
      --disable-zscaler)    CLI_ENABLE_ZSCALER="false"; shift ;;
      --enable-dotfiles)    CLI_ENABLE_DOTFILES="true";  shift ;;
      --disable-dotfiles)   CLI_ENABLE_DOTFILES="false"; shift ;;
      --enable-applications)  CLI_ENABLE_APPLICATIONS="true";  shift ;;
      --disable-applications) CLI_ENABLE_APPLICATIONS="false"; shift ;;
      --enable-macos-defaults)  CLI_ENABLE_MACOS_DEFAULTS="true";  shift ;;
      --disable-macos-defaults) CLI_ENABLE_MACOS_DEFAULTS="false"; shift ;;
      --enable-remote-access)  CLI_ENABLE_REMOTE_ACCESS="true";  shift ;;
      --disable-remote-access) CLI_ENABLE_REMOTE_ACCESS="false"; shift ;;
      --enable-rosetta)     CLI_ENABLE_ROSETTA="true";  shift ;;
      --disable-rosetta)    CLI_ENABLE_ROSETTA="false"; shift ;;
      --enable-mise-tools)  CLI_ENABLE_MISE_TOOLS="true";  shift ;;
      --disable-mise-tools) CLI_ENABLE_MISE_TOOLS="false"; shift ;;
      --enable-shell-default)  CLI_ENABLE_SHELL_DEFAULT="true";  shift ;;
      --disable-shell-default) CLI_ENABLE_SHELL_DEFAULT="false"; shift ;;
      --personal)
        ENABLE_PERSONAL=1
        shift
        ;;
      --device-name)
        [[ $# -ge 2 ]] || fail "--device-name requires a value"
        CLI_DEVICE_NAME="$2"
        shift 2
        ;;
      --git-name)
        [[ $# -ge 2 ]] || fail "--git-name requires a value"
        CLI_GIT_USER_NAME="$2"
        CLI_ENABLE_GIT_IDENTITY="true"
        shift 2
        ;;
      --git-email)
        [[ $# -ge 2 ]] || fail "--git-email requires a value"
        CLI_GIT_USER_EMAIL="$2"
        CLI_ENABLE_GIT_IDENTITY="true"
        shift 2
        ;;
      --enable-packages)    CLI_ENABLE_PACKAGES="true"; shift ;;
      --disable-packages)   CLI_ENABLE_PACKAGES="false"; shift ;;
      --enable-code-directory)  CLI_ENABLE_CODE_DIRECTORY="true"; shift ;;
      --disable-code-directory) CLI_ENABLE_CODE_DIRECTORY="false"; shift ;;
      --enable-downloads-link)  CLI_ENABLE_DOWNLOADS_LINK="true"; shift ;;
      --disable-downloads-link) CLI_ENABLE_DOWNLOADS_LINK="false"; shift ;;
      --enable-git-identity)    CLI_ENABLE_GIT_IDENTITY="true"; shift ;;
      --disable-git-identity)   CLI_ENABLE_GIT_IDENTITY="false"; shift ;;
      --enable-macos-hostname)  CLI_MACOS_HOSTNAME="true"; shift ;;
      --disable-macos-hostname) CLI_MACOS_HOSTNAME="false"; shift ;;
      --enable-macos-dock)      CLI_MACOS_DOCK="true"; shift ;;
      --disable-macos-dock)     CLI_MACOS_DOCK="false"; shift ;;
      --enable-macos-desktop)   CLI_MACOS_DESKTOP="true"; shift ;;
      --disable-macos-desktop)  CLI_MACOS_DESKTOP="false"; shift ;;
      --enable-macos-default-apps)  CLI_MACOS_DEFAULT_APPS="true"; shift ;;
      --disable-macos-default-apps) CLI_MACOS_DEFAULT_APPS="false"; shift ;;
      --enable-macos-menu-bar)  CLI_MACOS_MENU_BAR="true"; shift ;;
      --disable-macos-menu-bar) CLI_MACOS_MENU_BAR="false"; shift ;;
      --enable-macos-mouse)     CLI_MACOS_MOUSE="true"; shift ;;
      --disable-macos-mouse)    CLI_MACOS_MOUSE="false"; shift ;;
      --enable-macos-power)     CLI_MACOS_POWER="true"; shift ;;
      --disable-macos-power)    CLI_MACOS_POWER="false"; shift ;;
      --enable-macos-finder)    CLI_MACOS_FINDER="true"; shift ;;
      --disable-macos-finder)   CLI_MACOS_FINDER="false"; shift ;;
      --enable-macos-screenshots)  CLI_MACOS_SCREENSHOTS="true"; shift ;;
      --disable-macos-screenshots) CLI_MACOS_SCREENSHOTS="false"; shift ;;
      --enable-macos-touch-id)  CLI_MACOS_TOUCH_ID="true"; shift ;;
      --disable-macos-touch-id) CLI_MACOS_TOUCH_ID="false"; shift ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --dotfiles-repo)
        [[ $# -ge 2 ]] || fail "--dotfiles-repo requires a value"
        DOTFILES_REPO="$2"
        shift 2
        ;;
      --personal-script)
        [[ $# -ge 2 ]] || fail "--personal-script requires a value"
        PERSONAL_SCRIPT="$2"
        shift 2
        ;;
      -h|--help)
        foundation_usage
        exit 0
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done
}


# =============================================================================
# SECTION 3: HOMEBREW
# =============================================================================

# ensure_homebrew -- Install Homebrew if it is not already present
#
# What: Checks for brew on PATH. If missing, verifies Xcode CLT are installed
#       (required by the Homebrew installer), then runs the official install
#       script with its prompts attached to the current terminal.
# Why:  Homebrew is the package manager for everything else in the foundation.
# Checks: command_exists brew, xcode-select -p
# Gates: None (always runs).
# Side effects: May install Xcode CLT (triggers Apple UI), may install Homebrew.
# Idempotency: No-op if brew is already on PATH.
#
# Status:
#   pass  -- Homebrew already installed
#   fix   -- Homebrew was just installed
#   fail  -- Xcode CLT could not be completed in the current session
ensure_homebrew() {
  # Use pre-flight data if available to avoid redundant checks
  if [[ "${PREFLIGHT_HOMEBREW:-}" == "installed" ]] || command_exists brew; then
    status_pass "Homebrew" "${PREFLIGHT_HOMEBREW_VERSION:-already installed}"
    return 0
  fi

  # Xcode CLT are required before Homebrew can be installed
  if ! xcode-select -p >/dev/null 2>&1; then
    if dry_run_active; then
      dry_run_log "xcode-select --install"
      status_fix "Homebrew" "would trigger Xcode CLT install"
      return 0
    fi
    if [[ "$NON_INTERACTIVE" == "1" || ! -t 0 ]]; then
      status_fail "Homebrew" "Command Line Tools require interactive installation"
      return 1
    fi
    xcode-select --install || true
    note "The Command Line Tools installer is now open. Choose Continue, accept Apple's licence, and wait for installation to finish."

    while ! xcode-select -p >/dev/null 2>&1; do
      read -r "?Press Return after the Command Line Tools installer has completed: "
      if ! xcode-select -p >/dev/null 2>&1; then
        warn "Command Line Tools are not ready yet. Complete the installer before continuing."
      fi
    done
    status_fix "Xcode Command Line Tools" "installed after operator confirmation"
  fi

  if dry_run_active; then
    dry_run_log "install Homebrew via official installer"
    status_fix "Homebrew" "would install"
    return 0
  fi

  note "Homebrew may request your macOS password and require Return to continue. Its output remains attached to this terminal."
  if [[ "$NON_INTERACTIVE" == "1" || ! -t 0 ]]; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  status_fix "Homebrew" "installed"
}

# brew_shellenv -- Eval brew shellenv for the running zsh session
#
# What: Detects the Homebrew prefix (/opt/homebrew on ARM, /usr/local on Intel)
#       and evals brew shellenv to put brew and its packages on PATH.
# Why:  Needed immediately after installing Homebrew so subsequent commands
#       (brew install, mise, etc.) can be found.
# Checks: Tests for brew binary at both prefix locations.
# Gates: None.
# Side effects: Modifies PATH, HOMEBREW_PREFIX, etc. in the current shell.
# Idempotency: Safe to call repeatedly; shellenv is additive.
brew_shellenv() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

# ensure_mise_bootstrap_packages -- Install Homebrew formulae declared in mise [bootstrap.packages]
#
# What: Runs `mise bootstrap packages install` so mise owns the core Homebrew
#       formula layer (git, jq, fzf, etc.).
# Why:  Core CLI tools are defined in ~/.config/mise/config.toml under
#       [bootstrap.packages]. They must be present before language runtimes
#       (some mise tools expect these formulae on PATH) and before Zscaler
#       TLS configuration.
# Checks: None (mise bootstrap packages install is idempotent).
# Gates: RESOLVED_PACKAGES.
# Side effects: Installs/updates Homebrew formulae via mise.
# Idempotency: mise bootstrap packages install skips packages already at the desired version.
#
# Status:
#   pass -- mise bootstrap packages install succeeded
ensure_mise_bootstrap_packages() {
  if [[ "${RESOLVED_PACKAGES:-false}" != "true" ]]; then
    status_skip "Ben's Homebrew CLI catalogue" "disabled in bootstrap plan"
    return 0
  fi
  if dry_run_active; then
    local missing_lines="" missing_count=0
    missing_lines="$(bootstrap_package_missing_lines 2>/dev/null || true)"
    if [[ -z "$missing_lines" ]]; then
      status_pass "Mise bootstrap packages" "complete catalogue already installed"
      return 0
    fi
    missing_count="$(printf '%s\n' "$missing_lines" | sed '/^$/d' | wc -l | tr -d ' ')"
    local package state
    while IFS=$'\t' read -r package state; do
      [[ -n "$package" ]] || continue
      dry_run_log "INSTALL $package ($state)"
    done <<< "$missing_lines"
    local manager_plan=""
    manager_plan="$(bootstrap_mise bootstrap packages apply --dry-run 2>&1 || true)"
    [[ -n "$manager_plan" ]] && printf '%s\n' "$manager_plan"
    status_fix "Mise bootstrap packages" "would install $missing_count missing package(s)"
    return 0
  fi

  note "Mise may show the Homebrew package plan with Yes highlighted; press Return to begin installation."
  bootstrap_mise bootstrap packages install
  status_pass "Mise bootstrap packages" "installed"
}

# ensure_mise -- Install mise if not present (standalone installer)
#
# What: Checks whether mise is already available on PATH. If not, installs the
#       first-party standalone binary with the official shell installer.
# Why:  mise owns Gum in the mandatory baseline and optionally owns the selected
#       package and developer-tool catalogues. Its first-party installer works
#       without adding mise itself to a package-manager catalogue.
# Checks: command -v mise on PATH.
# Gates: None — mise is part of the mandatory foundation.
# Side effects: Installs mise binary via the official shell installer.
#               May modify PATH (shell installer places mise in ~/.local/bin).
# Idempotency: No-op if mise is already on PATH.
#
# Install priority:
#   1. Already installed (any method) → pass
#   2. Official standalone installer → ~/.local/bin/mise
#
# Status:
#   pass -- mise already installed (with version and install method)
#   fix  -- mise was just installed (via brew or shell installer)
ensure_mise() {
  if command_exists mise; then
    local ver
    ver="$(mise --version 2>/dev/null || echo "unknown")"
    local method="unknown"
    if brew list mise >/dev/null 2>&1; then
      method="homebrew"
    elif [[ -x "$HOME/.local/bin/mise" ]]; then
      method="shell installer"
    fi
    status_pass "Mise" "$ver ($method)"
    return 0
  fi

  if dry_run_active; then
    dry_run_log "curl https://mise.run | sh"
    status_fix "Mise" "would install the standalone binary"
    return 0
  fi

  curl -fsSL https://mise.run | sh
  export PATH="$HOME/.local/bin:$PATH"

  if command_exists mise; then
    status_fix "Mise" "installed via shell installer (~/.local/bin/mise)"
  else
    status_fail "Mise" "standalone installation failed"
  fi
}

# ensure_gum -- Install only gum through mise so the interactive plan can run
ensure_gum() {
  local gum_path=""
  gum_path="$(bootstrap_mise which gum 2>/dev/null || true)"
  if [[ ! -x "$gum_path" ]]; then
    gum_path="$(mise -C "$HOME" exec gum@latest -- command -v gum 2>/dev/null || true)"
  fi

  if [[ -x "$gum_path" ]]; then
    export PATH="$(dirname "$gum_path"):$PATH"
    status_pass "Gum" "managed by mise"
    return 0
  fi

  if dry_run_active; then
    status_fail "Gum" "not installed; interactive dry-run needs mise-managed gum"
    return 0
  fi

  note "Installing the gum interface as a single mise tool before showing the bootstrap menu."
  mise -C "$HOME" install gum@latest
  gum_path="$(mise -C "$HOME" exec gum@latest -- command -v gum 2>/dev/null || true)"
  if [[ ! -x "$gum_path" ]]; then
    status_fail "Gum" "mise installation completed but gum is unavailable"
    return 0
  fi
  export PATH="$(dirname "$gum_path"):$PATH"
  status_fix "Gum" "installed through mise"
}

ensure_selected_mise_config() {
  if [[ "${RESOLVED_PACKAGES:-false}" != "true" \
    && "${RESOLVED_MISE_TOOLS:-false}" != "true" \
    && "${RESOLVED_DOTFILES:-false}" != "true" ]]; then
    status_skip "Ben's mise configuration" "package, tool, and dotfile catalogues disabled"
    return 0
  fi
  ensure_seed_mise_config
}

# update_brew_packages -- Update, upgrade, and clean Homebrew
#
# What: Runs brew update, upgrade, cleanup, and autoremove in sequence.
# Why:  Keeps all Homebrew-managed software current and disk usage lean.
# Checks: None (brew handles its own state).
# Gates: MODE=update only (caller is responsible for gating).
# Side effects: Updates Homebrew index, upgrades all formulae/casks, removes
#               stale downloads and orphaned dependencies.
# Idempotency: Safe to run repeatedly; no-op if everything is current.
#
# Status:
#   pass -- "update + upgrade + cleanup complete"
update_brew_packages() {
  run_or_dry brew update
  # Let vendor-self-updating casks own their application updates while
  # Homebrew continues to upgrade formulae and ordinary casks.
  run_or_dry env HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1 brew upgrade
  run_or_dry brew cleanup
  run_or_dry brew autoremove
  if dry_run_active; then
    status_fix "Homebrew update" "would run update + upgrade + cleanup"
  else
    status_pass "Homebrew update" "update + upgrade + cleanup complete"
  fi
}


# =============================================================================
# SECTION 4: SHELL PROFILE
# =============================================================================

# profile_block_zsh -- Generate the zsh managed block content
#
# What: Produces the shell initialization lines for zsh, wrapped in managed
#       block markers. Each tool activation is guarded by command_exists so
#       the profile is safe even if a tool is not yet installed.
# Why:  Ensures brew, mise, and zoxide are activated in every new zsh session.
# Checks: None (pure string generation).
# Gates: None.
# Side effects: None.
# Idempotency: Always returns the same string.
profile_block_zsh() {
  cat <<'EOF'
# >>> foundation-bootstrap >>>
if command -v brew >/dev/null 2>&1; then eval "$(brew shellenv)"; fi
if command -v mise >/dev/null 2>&1; then eval "$(mise activate zsh)"; fi
if command -v zoxide >/dev/null 2>&1; then eval "$(zoxide init zsh)"; fi
# <<< foundation-bootstrap <<<
EOF
}

# profile_block_fish -- Generate the fish managed block content
#
# What: Produces the shell initialization lines for fish, wrapped in managed
#       block markers. Written to a conf.d file so fish sources it automatically.
#       Each tool activation is guarded by `type -q`.
# Why:  Ensures brew, mise, and zoxide are activated in every new fish session.
# Checks: None (pure string generation).
# Gates: None.
# Side effects: None.
# Idempotency: Always returns the same string.
profile_block_fish() {
  cat <<'EOF'
# >>> foundation-bootstrap >>>
if type -q brew; eval (brew shellenv); end
if type -q mise; mise activate fish | source; end
if type -q zoxide; zoxide init fish | source; end
# <<< foundation-bootstrap <<<
EOF
}

# ensure_profile_block -- Write the managed profile block for the resolved shell
#
# What: Determines the correct profile file and block content based on
#       RESOLVED_SHELL, then uses write_managed_block to idempotently write it.
# Why:  The user's preferred shell must have brew/mise/zoxide activation.
# Checks: Compares existing block content against desired content.
# Gates: None (always runs).
# Side effects: Creates or updates the shell profile file.
# Idempotency: No-op if the block is already present and correct.
#
# Status:
#   pass -- block already present and correct
#   fix  -- block written or updated
ensure_profile_block() {
  local target_file=""
  local block_content=""

  if [[ "${ENABLE_PERSONAL:-0}" == "1" \
    && "${RESOLVED_DOTFILES:-true}" == "true" ]]; then
    status_skip "Shell profile block" "personal layer will apply the tracked shell config"
    return 0
  fi

  if [[ "$RESOLVED_SHELL" == "fish" ]]; then
    target_file="$HOME/.config/fish/conf.d/00-foundation.fish"
    block_content="$(profile_block_fish)"
  else
    target_file="$HOME/.zshrc"
    block_content="$(profile_block_zsh)"
  fi

  # Check if block already exists and matches
  if [[ -f "$target_file" ]] && grep -qF "$PROFILE_BEGIN" "$target_file"; then
    # Extract current block and compare
    local current_block=""
    current_block="$(awk "/$PROFILE_BEGIN/,/$PROFILE_END/" "$target_file")"
    if [[ "$current_block" == "$block_content" ]]; then
      status_pass "Shell profile block" "$RESOLVED_SHELL profile up to date"
      return 0
    fi
  fi

  write_managed_block "$target_file" "$PROFILE_BEGIN" "$PROFILE_END" "$block_content"
  if dry_run_active; then
    status_fix "Shell profile block" "would write $RESOLVED_SHELL profile to $target_file"
  else
    status_fix "Shell profile block" "wrote $RESOLVED_SHELL profile to $target_file"
  fi
}

# activate_shell -- Activate brew, mise, and zoxide in the RUNNING zsh session
#
# What: Evals brew shellenv, mise activate zsh, and zoxide init zsh for the
#       current process. Only activates mise/zoxide if they exist on PATH.
# Why:  The foundation script itself always runs in zsh (regardless of
#       RESOLVED_SHELL), so we need these tools active for subsequent steps
#       like `mise install`.
# Checks: command_exists for mise and zoxide before eval.
# Gates: None.
# Side effects: Modifies PATH and shell state for the current process.
# Idempotency: Safe to call repeatedly; each eval is additive/overwriting.
activate_shell() {
  eval "$(brew shellenv)"

  if command_exists mise; then
    eval "$(mise activate zsh)"
  fi

  if command_exists zoxide; then
    eval "$(zoxide init zsh)"
  fi
}


# =============================================================================
# SECTION 5: MISE
# =============================================================================

# seed_mise_block -- Generate the seed mise config.toml content
#
# What: Produces a config.toml snippet with experimental settings, env file
#       reference, and a curated set of language runtimes and tools. Wrapped
#       in managed block markers.
# Why:  Gives every machine a consistent baseline of language runtimes without
#       requiring manual configuration.
# Checks: None (pure string generation).
# Gates: None.
# Side effects: None.
# Idempotency: Always returns the same string.
seed_mise_block() {
  cat <<'EOF'
# >>> foundation-seed >>>
[settings]
experimental = true

[env]
_.file = "~/.config/mise/.env"

[tools]
go = "latest"
node = "latest"
bun = "latest"
python = "latest"
uv = "latest"
zig = "latest"
terraform = "latest"
gcloud = "latest"
usage = "latest"
pkl = "latest"
hk = "latest"
fnox = "latest"
"go:oss.terrastruct.com/d2" = { version = "latest" }
"go:github.com/charmbracelet/glow" = { version = "latest" }
"go:github.com/charmbracelet/freeze" = { version = "latest" }
"go:github.com/charmbracelet/vhs" = { version = "latest" }
"npm:opencode-ai" = "latest"
"npm:@playwright/cli" = "latest"
# <<< foundation-seed <<<
EOF
}

# ensure_seed_mise_config -- Create or update the mise seed configuration
#
# What: If no mise config exists, creates it with the seed block. If one exists
#       with our managed markers, updates the managed section. If one exists
#       without markers, leaves it alone (user-managed config).
# Why:  Ensures mise knows which runtimes to install, but never overwrites
#       user customizations outside the managed block.
# Checks: File existence, presence of managed markers.
# Gates: None (always runs).
# Side effects: May create or modify ~/.config/mise/config.toml.
# Idempotency: No-op if config is already in the desired state.
#
# Status:
#   pass -- config exists with correct seed block
#   fix  -- config created or seed block updated
#   skip -- user config detected (no markers), left unchanged
ensure_seed_mise_config() {
  local repo_mise_dir="$BOOTSTRAP_ROOT/mise"

  # The repository config contains the complete tool and system-package
  # declaration. Prefer it to the fallback seed so the first run installs the
  # same state that subsequent mise dotfile runs will manage.
  if [[ -f "$repo_mise_dir/config.toml" ]]; then
    if [[ -L "$MISE_CONFIG_DIR" \
      && "$(/usr/bin/readlink "$MISE_CONFIG_DIR")" == "$repo_mise_dir" ]]; then
      status_pass "Mise config" "managed repository symlink already applied"
      return 0
    fi

    if [[ ! -e "$MISE_CONFIG_DIR" && ! -L "$MISE_CONFIG_DIR" ]]; then
      if dry_run_active; then
        dry_run_log "mkdir -p $HOME/.config && ln -s $repo_mise_dir $MISE_CONFIG_DIR"
        status_fix "Mise config" "would link the complete repository config"
      else
        mkdir -p "$HOME/.config"
        ln -s "$repo_mise_dir" "$MISE_CONFIG_DIR"
        status_fix "Mise config" "linked the complete repository config"
      fi
      return 0
    fi
  fi

  if dry_run_active && [[ ! -f "$MISE_CONFIG_PATH" ]]; then
    dry_run_log "mkdir -p $MISE_CONFIG_DIR and write seed config"
    status_fix "Mise seed config" "would create $MISE_CONFIG_PATH"
    return 0
  fi

  mkdir -p "$MISE_CONFIG_DIR"

  if [[ ! -f "$MISE_CONFIG_PATH" ]]; then
    seed_mise_block > "$MISE_CONFIG_PATH"
    status_fix "Mise seed config" "created $MISE_CONFIG_PATH"
    return 0
  fi

  if grep -qF "$MISE_BEGIN" "$MISE_CONFIG_PATH"; then
    # Check if existing block matches
    local current_block=""
    current_block="$(awk "/$MISE_BEGIN/,/$MISE_END/" "$MISE_CONFIG_PATH")"
    local desired_block=""
    desired_block="$(seed_mise_block)"

    if [[ "$current_block" == "$desired_block" ]]; then
      status_pass "Mise seed config" "already up to date"
    else
      write_managed_block "$MISE_CONFIG_PATH" "$MISE_BEGIN" "$MISE_END" "$desired_block"
      status_fix "Mise seed config" "updated managed block"
    fi
    return 0
  fi

  # Config exists but has no managed markers -- user owns it
  status_skip "Mise seed config" "user config detected at $MISE_CONFIG_PATH"
}

# ensure_mise_tools -- Install all tools defined in mise config
#
# What: Runs `mise install` to ensure every tool in config.toml is present at
#       the specified version.
# Why:  Language runtimes are needed for development and for Zscaler cert
#       bundle building (Python certifi).
# Checks: None (mise install is inherently idempotent).
# Gates: RESOLVED_MISE_TOOLS (skipped if "false").
# Side effects: Downloads and installs language runtimes.
# Idempotency: mise install skips tools that are already at the correct version.
#
# Status:
#   pass -- mise install succeeded
#   skip -- disabled by RESOLVED_MISE_TOOLS=false
ensure_mise_tools() {
  if [[ "${RESOLVED_MISE_TOOLS:-true}" != "true" ]]; then
    status_skip "Mise tools install" "disabled by flag"
    return 0
  fi

  if dry_run_active; then
    local missing_json="{}" missing_count=0
    missing_json="$(bootstrap_mise ls --missing --json 2>/dev/null || printf '{}')"
    if command_exists jq; then
      missing_count="$(printf '%s\n' "$missing_json" | jq '[to_entries[].value[]?] | length' 2>/dev/null || printf 0)"
    else
      missing_count="$(bootstrap_mise ls --missing --no-header 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
    fi
    if [[ "$missing_count" == "0" ]]; then
      status_pass "Mise tools install" "all declared tools installed"
      return 0
    fi
    bootstrap_mise install --dry-run 2>&1 || true
    status_fix "Mise tools install" "would install $missing_count missing tool(s)"
    return 0
  fi

  note "Mise may show a proposed installation with Yes selected; press Return to begin."
  bootstrap_mise install
  status_pass "Mise tools install" "complete"
}

# ensure_mise_python -- Stage Python before Zscaler and gcloud setup
ensure_mise_python() {
  if [[ "${RESOLVED_MISE_TOOLS:-true}" != "true" \
    && "${RESOLVED_ZSCALER:-false}" == "false" ]]; then
    status_skip "Mise Python prerequisite" "developer tools and Zscaler disabled"
    return 0
  fi

  local python_path=""
  python_path="$(bootstrap_mise which python 2>/dev/null || true)"
  if [[ -n "$python_path" && -x "$python_path" ]]; then
    status_pass "Mise Python prerequisite" "$($python_path --version 2>&1 | head -1)"
    return 0
  fi
  if dry_run_active; then
    bootstrap_mise install python@latest --dry-run 2>&1 || true
    status_fix "Mise Python prerequisite" "would install Python first"
    return 0
  fi
  note "Staging mise Python before Zscaler trust and the vfox gcloud installer."
  bootstrap_mise install python@latest
  status_pass "Mise Python prerequisite" "ready"
}

# ensure_mise_post_bootstrap -- Install TPM and its declared tmux plugins
ensure_mise_post_bootstrap() {
  if [[ "${RESOLVED_MISE_TOOLS:-true}" != "true" ]]; then
    status_skip "Mise post-bootstrap" "developer tools disabled"
    return 0
  fi

  if dry_run_active; then
    local -a missing_plugins=()
    local plugin_dir
    for plugin_dir in tpm tmux tmux-sensible; do
      [[ -d "$HOME/.tmux/plugins/$plugin_dir" ]] || missing_plugins+=("$plugin_dir")
    done
    if [[ ${#missing_plugins[@]} -eq 0 && -d "$HOME/.local/share/applications" ]]; then
      status_pass "Mise post-bootstrap" "TPM and declared plugins already installed"
      return 0
    fi
    dry_run_log "mise -C $HOME run bootstrap"
    status_fix "Mise post-bootstrap" "would install: ${missing_plugins[*]:-post-bootstrap directories}"
    return 0
  fi
  bootstrap_mise run bootstrap
  status_pass "Mise post-bootstrap" "TPM and declared plugins converged"
}

# update_mise -- Upgrade mise binary and all managed tools
#
# What: Upgrades the mise binary (via brew or self-update), then runs
#       `mise upgrade` and `mise install` to bring all tools to latest.
# Why:  Keeps runtimes current during update mode.
# Checks: Whether mise was installed via brew (to choose upgrade path).
# Gates: MODE=update and RESOLVED_MISE_TOOLS=true (caller gates MODE; this
#        function gates RESOLVED_MISE_TOOLS).
# Side effects: Upgrades binaries and runtimes.
# Idempotency: No-op if everything is already at latest.
#
# Status:
#   pass -- upgrade complete
#   skip -- disabled by RESOLVED_MISE_TOOLS=false
update_mise() {
  if [[ "${RESOLVED_MISE_TOOLS:-true}" != "true" ]]; then
    status_skip "Mise update" "disabled by flag"
    return 0
  fi

  if brew list mise >/dev/null 2>&1; then
    run_or_dry brew upgrade mise || true
  else
    run_or_dry mise -C "$HOME" self-update || true
  fi

  run_or_dry mise -C "$HOME" upgrade || true
  run_or_dry mise -C "$HOME" install
  if dry_run_active; then
    status_fix "Mise update" "would upgrade binary + tools"
  else
    status_pass "Mise update" "binary + tools upgraded"
  fi
}


# =============================================================================
# SECTION 6: ZSCALER
# =============================================================================

# detect_zscaler -- Probe TLS to detect Zscaler MITM proxy
#
# What: Connects to registry.npmjs.org via openssl s_client and inspects the
#       certificate issuer field for "Zscaler".
# Why:  When behind a Zscaler proxy, all TLS connections use Zscaler's CA.
#       Tools like npm, pip, and git will fail unless we inject the Zscaler
#       chain into their trust stores.
# Checks: TLS handshake to registry.npmjs.org:443.
# Gates: None.
# Side effects: None (read-only network probe).
# Idempotency: Pure detection -- safe to call repeatedly.
#
# Returns: 0 if Zscaler detected, 1 otherwise.
detect_zscaler() {
  local issuer
  issuer=$(openssl s_client -connect registry.npmjs.org:443 \
    -servername registry.npmjs.org < /dev/null 2>/dev/null |
    openssl x509 -noout -issuer 2>/dev/null || true)
  [[ "$issuer" == *Zscaler* ]]
}

# python_certifi_path -- Get the path to Python's certifi CA bundle
#
# What: Asks Python's bundled certifi package for its certificate bundle path.
# Why:  The golden bundle is built by concatenating certifi's bundle with the
#       Zscaler chain, giving tools a complete trust store.
# Checks: Requires python3 with pip's vendored certifi.
# Gates: None.
# Side effects: None.
# Idempotency: Pure query.
#
# Prints: The absolute path to cacert.pem, or empty string on failure.
python_certifi_path() {
  python3 -c 'import pip._vendor.certifi as c; print(c.where())' 2>/dev/null || true
}

# fetch_zscaler_chain -- Download the Zscaler certificate chain
#
# What: Uses openssl s_client with -showcerts to capture the full certificate
#       chain presented by Zscaler's proxy, extracts PEM blocks, and writes
#       them to ZSCALER_CHAIN_PATH.
# Why:  The chain file is needed to build the golden CA bundle.
# Checks: None (overwrites existing chain file).
# Gates: None.
# Side effects: Creates/overwrites ZSCALER_CHAIN_PATH.
# Idempotency: Produces the same output given the same network conditions.
fetch_zscaler_chain() {
  if dry_run_active; then
    dry_run_log "fetch Zscaler cert chain from registry.npmjs.org → $ZSCALER_CHAIN_PATH"
    return 0
  fi
  mkdir -p "$CERTS_DIR"
  openssl s_client -showcerts -connect registry.npmjs.org:443 \
    -servername registry.npmjs.org < /dev/null 2>/dev/null |
    awk '/-----BEGIN CERTIFICATE-----/{p=1}; p; /-----END CERTIFICATE-----/{p=0}' \
    > "$ZSCALER_CHAIN_PATH"
}

# validate_zscaler_chain -- Verify the fetched chain contains Zscaler certs
#
# What: Checks that the chain file exists, is non-empty, and that its first
#       certificate's issuer contains "Zscaler".
# Why:  Guards against corrupted or empty downloads before building the bundle.
# Checks: File existence, size, and issuer field.
# Gates: None.
# Side effects: None.
# Idempotency: Pure validation.
#
# Returns: 0 if valid, 1 otherwise.
validate_zscaler_chain() {
  [[ -s "$ZSCALER_CHAIN_PATH" ]] || return 1
  openssl x509 -in "$ZSCALER_CHAIN_PATH" -noout -issuer 2>/dev/null | grep -q "Zscaler"
}

# build_golden_bundle -- Concatenate certifi + Zscaler chain into golden bundle
#
# What: Finds the Python certifi CA bundle, concatenates it with the Zscaler
#       chain, and writes the result to GOLDEN_BUNDLE_PATH.
# Why:  The golden bundle is a complete trust store that includes both public
#       CAs and the corporate Zscaler CA, allowing all tools to verify TLS.
# Checks: python_certifi_path must return a valid path.
# Gates: None.
# Side effects: Creates/overwrites GOLDEN_BUNDLE_PATH.
# Idempotency: Produces the same output given the same inputs.
build_golden_bundle() {
  if dry_run_active; then
    dry_run_log "build golden CA bundle → $GOLDEN_BUNDLE_PATH"
    return 0
  fi
  local certifi_path
  certifi_path="$(python_certifi_path)"
  [[ -n "$certifi_path" ]] || fail "Unable to locate a Python certifi bundle via python3."
  cat "$certifi_path" "$ZSCALER_CHAIN_PATH" > "$GOLDEN_BUNDLE_PATH"
}

# zscaler_env_block -- Generate the env var block for Zscaler TLS trust
#
# What: Produces a block of environment variable assignments that point every
#       major tool's CA config at the golden bundle. Written to mise's .env
#       file so the vars are active in every shell session.
# Why:  Each tool has its own env var for custom CA bundles. Setting all of
#       them ensures no tool is left untrusted behind Zscaler.
# Checks: None (pure string generation).
# Gates: None.
# Side effects: None.
# Idempotency: Always returns the same string (for the same GOLDEN_BUNDLE_PATH).
zscaler_env_block() {
  cat <<EOF
# >>> zscaler-bootstrap >>>
ZSCALER_CERT_BUNDLE="$GOLDEN_BUNDLE_PATH"
ZSCALER_CERT_DIR="$CERTS_DIR"
SSL_CERT_FILE="$GOLDEN_BUNDLE_PATH"
SSL_CERT_DIR="$CERTS_DIR"
CERT_PATH="$GOLDEN_BUNDLE_PATH"
CERT_DIR="$CERTS_DIR"
REQUESTS_CA_BUNDLE="$GOLDEN_BUNDLE_PATH"
CURL_CA_BUNDLE="$GOLDEN_BUNDLE_PATH"
NODE_EXTRA_CA_CERTS="$GOLDEN_BUNDLE_PATH"
GRPC_DEFAULT_SSL_ROOTS_FILE_PATH="$GOLDEN_BUNDLE_PATH"
GIT_SSL_CAINFO="$GOLDEN_BUNDLE_PATH"
CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE="$GOLDEN_BUNDLE_PATH"
PIP_CERT="$GOLDEN_BUNDLE_PATH"
NPM_CONFIG_CAFILE="$GOLDEN_BUNDLE_PATH"
npm_config_cafile="$GOLDEN_BUNDLE_PATH"
AWS_CA_BUNDLE="$GOLDEN_BUNDLE_PATH"
# <<< zscaler-bootstrap <<<
EOF
}

# ensure_zscaler_env -- Write the Zscaler env block to mise's .env file
#
# What: Uses write_managed_block to idempotently write the TLS env vars into
#       the mise .env file so they are sourced on every shell activation.
# Why:  Mise's _.file directive reads this .env, making the vars available to
#       all tools activated by mise.
# Checks: Existing block content via write_managed_block.
# Gates: None.
# Side effects: Creates or modifies MISE_ENV_PATH.
# Idempotency: No-op if block is already present and correct.
ensure_zscaler_env() {
  write_managed_block "$MISE_ENV_PATH" "$ZSCALER_ENV_BEGIN" "$ZSCALER_ENV_END" "$(zscaler_env_block)"
}

# configure_tls_clients -- Set CA paths in pip and gcloud configs
#
# What: Configures pip's global cert and gcloud's custom CA cert file to point
#       at the golden bundle. Git uses GIT_SSL_CAINFO from mise's .env.
# Why:  Some tools read config files in addition to (or instead of) env vars.
# Checks: command_exists for python3 and gcloud before configuring them.
# Gates: None.
# Side effects: Modifies pip and gcloud config. Does not modify ~/.gitconfig.
# Idempotency: Overwrites the same settings with the same values.
configure_tls_clients() {
  if command_exists python3; then
    run_or_dry python3 -m pip config set global.cert "$GOLDEN_BUNDLE_PATH" >/dev/null 2>&1 || true
  fi

  if command_exists gcloud; then
    run_or_dry gcloud config set core/custom_ca_certs_file "$GOLDEN_BUNDLE_PATH" >/dev/null 2>&1 || true
  fi
}

# validate_zscaler_runtime -- Post-check: verify Zscaler trust is functional
#
# What: Verifies that the golden bundle exists, Git's environment is correct, and
#       npm ping works (if node/npm are available).
# Why:  Catches configuration drift or incomplete Zscaler setup.
# Checks: File existence, managed environment block, npm connectivity.
# Gates: None (called only when Zscaler is active).
# Side effects: None (read-only checks).
# Idempotency: Pure validation.
#
# Status:
#   pass/fail per individual check
validate_zscaler_runtime() {
  if [[ -f "$GOLDEN_BUNDLE_PATH" ]]; then
    status_pass "Zscaler: golden bundle exists"
  else
    status_fail "Zscaler: golden bundle exists" "file missing at $GOLDEN_BUNDLE_PATH"
  fi

  if [[ -f "$MISE_ENV_PATH" ]]; then
    status_pass "Zscaler: mise .env exists"
  else
    status_fail "Zscaler: mise .env exists" "file missing at $MISE_ENV_PATH"
  fi

  if grep -Fq "GIT_SSL_CAINFO=\"$GOLDEN_BUNDLE_PATH\"" "$MISE_ENV_PATH" 2>/dev/null; then
    status_pass "Zscaler: Git CA environment"
  else
    status_fail "Zscaler: Git CA environment" "GIT_SSL_CAINFO is not managed"
  fi

  if command_exists node && command_exists npm; then
    if npm ping >/dev/null 2>&1; then
      status_pass "Zscaler: npm ping"
    else
      status_fail "Zscaler: npm ping" "npm registry unreachable"
    fi
  fi

  if command_exists python3; then
    if python3 -m pip --version >/dev/null 2>&1; then
      status_pass "Zscaler: pip functional"
    else
      status_fail "Zscaler: pip functional" "pip command failed"
    fi
  fi
}

# handle_zscaler -- Orchestrator for all Zscaler TLS trust configuration
#
# What: Evaluates RESOLVED_ZSCALER to decide whether to configure Zscaler trust.
#       When proceeding: fetches chain, validates it, builds golden bundle,
#       writes env vars, activates shell, and configures TLS clients.
# Why:  Centralizes the Zscaler decision logic and execution sequence.
# Checks: RESOLVED_ZSCALER value, detect_zscaler() for auto mode.
# Gates: RESOLVED_ZSCALER (false=skip, auto=detect, true=force).
# Side effects: May create cert files, modify configs, write state.
# Idempotency: Re-running produces the same state if network conditions match.
#
# Status:
#   skip -- disabled by flag or auto-detect found no Zscaler
#   fix  -- Zscaler trust configured
#   pass -- Zscaler trust already configured (all validation checks pass)
handle_zscaler() {
  # Gate: disabled
  if [[ "${RESOLVED_ZSCALER:-false}" == "false" ]]; then
    status_skip "Zscaler trust" "disabled by flag"
    return 0
  fi

  # Gate: auto-detect
  if [[ "${RESOLVED_ZSCALER:-false}" == "auto" ]]; then
    if [[ -f "$GOLDEN_BUNDLE_PATH" ]] && [[ -f "$MISE_ENV_PATH" ]]; then
      note "Existing Zscaler trust artifacts found. Converging the work profile."
      RESOLVED_ZSCALER="true"
    elif detect_zscaler; then
      note "Zscaler detected on this network. Configuring TLS trust."
      RESOLVED_ZSCALER="true"
    else
      status_skip "Zscaler trust" "not detected on this network"
      return 0
    fi
  fi

  # Proceed: RESOLVED_ZSCALER=true or auto-detected
  # Check if already fully configured
  if [[ -f "$GOLDEN_BUNDLE_PATH" ]] && [[ -f "$MISE_ENV_PATH" ]]; then
    ensure_zscaler_env
    configure_tls_clients
    status_pass "Zscaler trust" "already configured"
    return 0
  fi

  fetch_zscaler_chain
  validate_zscaler_chain || fail "Detected active Zscaler, but failed to validate the fetched certificate chain."
  build_golden_bundle
  ensure_zscaler_env
  activate_shell
  configure_tls_clients
  status_fix "Zscaler trust" "configured"
}


# =============================================================================
# SECTION 7: VALIDATION
# =============================================================================

# validate_foundation -- Run individual checks and emit status per check
#
# What: Verifies that every critical tool is installed and functional. Checks
#       are conditional on feature flags where appropriate.
# Why:  Provides a clear pass/fail report at the end of the bootstrap run so
#       the user knows exactly what is working and what is not.
# Checks: command_exists and --version for each tool.
# Gates: RESOLVED_MISE_TOOLS for runtime checks, Zscaler state for TLS checks.
# Side effects: None (read-only validation).
# Idempotency: Pure validation -- safe to call any number of times.
#
# Status: emits pass/fail/skip per individual check.
validate_foundation() {
  # Core tools (always checked)
  if command_exists brew; then
    status_pass "Validate: brew"
  else
    status_fail "Validate: brew" "not found"
  fi

  if command_exists mise; then
    status_pass "Validate: mise"
  else
    status_fail "Validate: mise" "not found"
  fi

  if [[ "${RESOLVED_PACKAGES:-false}" != "true" ]]; then
    status_skip "Validate: Ben's CLI catalogue" "disabled"
  elif command_exists zoxide; then
    status_pass "Validate: zoxide"
  else
    status_fail "Validate: zoxide" "not found"
  fi

  if command_exists git; then
    status_pass "Validate: git"
  else
    status_fail "Validate: git" "not found"
  fi

  if command_exists openssl; then
    status_pass "Validate: openssl"
  else
    status_fail "Validate: openssl" "not found"
  fi

  # Runtime checks (conditional on RESOLVED_MISE_TOOLS)
  if [[ "${RESOLVED_MISE_TOOLS:-true}" == "true" ]]; then
    if command_exists node && node --version >/dev/null 2>&1; then
      status_pass "Validate: node" "$(node --version 2>/dev/null)"
    else
      status_fail "Validate: node" "not found or not working"
    fi

    if command_exists python && python --version >/dev/null 2>&1; then
      status_pass "Validate: python" "$(python --version 2>/dev/null)"
    else
      status_fail "Validate: python" "not found or not working"
    fi
  else
    status_skip "Validate: node" "mise-tools disabled"
    status_skip "Validate: python" "mise-tools disabled"
  fi

  # Zscaler checks (conditional on active Zscaler)
  local zscaler_active
  zscaler_active="$(state_get ENABLE_ZSCALER 2>/dev/null || true)"
  if [[ "$zscaler_active" == "true" ]] || [[ "${RESOLVED_ZSCALER:-false}" == "true" ]]; then
    validate_zscaler_runtime
  fi
}


# =============================================================================
# SECTION 8: PERSONAL HANDOFF
# =============================================================================

# personal_script_path -- Resolve the path to the personal bootstrap script
#
# What: Returns the absolute path to the personal-bootstrap-macos.zsh script.
#       Honors the PERSONAL_SCRIPT env var if set (supports both absolute and
#       relative paths). Falls back to the default location in the dotfiles repo.
# Why:  Allows overriding the personal script for testing or alternative configs.
# Checks: None.
# Gates: None.
# Side effects: None.
# Idempotency: Pure path resolution.
personal_script_path() {
  if [[ -n "${PERSONAL_SCRIPT:-}" ]]; then
    if [[ "$PERSONAL_SCRIPT" == /* ]]; then
      printf '%s\n' "$PERSONAL_SCRIPT"
    else
      printf '%s\n' "$BOOTSTRAP_ROOT/$PERSONAL_SCRIPT"
    fi
    return 0
  fi

  printf '%s\n' "$BOOTSTRAP_ROOT/Other/scripts/macos/personal-bootstrap-macos.zsh"
}

# run_personal_layer -- Execute the personal bootstrap script
#
# What: Resolves the personal script path and execs it, passing all relevant
#       env vars (MODE, DOTFILES_REPO, BOOTSTRAP_ROOT, all RESOLVED_* flags).
# Why:  The personal layer applies user-specific configuration on top of the
#       foundation.
# Checks: Verifies the script file exists.
# Gates: ENABLE_PERSONAL=1 (caller is responsible for checking).
# Side effects: Spawns a child zsh process running the personal script.
# Idempotency: Depends on the personal script's own idempotency.
#
# Status:
#   skip -- ENABLE_PERSONAL not set
run_personal_layer() {
  if [[ "${ENABLE_PERSONAL:-0}" != "1" ]]; then
    status_skip "Personal layer" "no personal stages selected"
    return 0
  fi

  local script_path
  script_path="$(personal_script_path)"

  if [[ ! -f "$script_path" ]]; then
    status_fail "Personal layer" "script not found at $script_path"
  fi

  note "Handing off to personal bootstrap: $script_path"
  DOTFILES_REPO="${DOTFILES_REPO:-}" \
    BOOTSTRAP_ROOT="$BOOTSTRAP_ROOT" \
    MODE="personal" \
    RESOLVED_SHELL="$RESOLVED_SHELL" \
    RESOLVED_PROFILE="$RESOLVED_PROFILE" \
    RESOLVED_ZSCALER="$RESOLVED_ZSCALER" \
    RESOLVED_DOTFILES="$RESOLVED_DOTFILES" \
    RESOLVED_PACKAGES="$RESOLVED_PACKAGES" \
    RESOLVED_APPLICATIONS="$RESOLVED_APPLICATIONS" \
    RESOLVED_MACOS_DEFAULTS="$RESOLVED_MACOS_DEFAULTS" \
    RESOLVED_REMOTE_ACCESS="$RESOLVED_REMOTE_ACCESS" \
    RESOLVED_ROSETTA="$RESOLVED_ROSETTA" \
    RESOLVED_MISE_TOOLS="$RESOLVED_MISE_TOOLS" \
    RESOLVED_SHELL_DEFAULT="$RESOLVED_SHELL_DEFAULT" \
    RESOLVED_CODE_DIRECTORY="$RESOLVED_CODE_DIRECTORY" \
    RESOLVED_DOWNLOADS_LINK="$RESOLVED_DOWNLOADS_LINK" \
    RESOLVED_GIT_IDENTITY="$RESOLVED_GIT_IDENTITY" \
    RESOLVED_DEVICE_NAME="$RESOLVED_DEVICE_NAME" \
    RESOLVED_GIT_USER_NAME="$RESOLVED_GIT_USER_NAME" \
    RESOLVED_GIT_USER_EMAIL="$RESOLVED_GIT_USER_EMAIL" \
    RESOLVED_MACOS_HOSTNAME="$RESOLVED_MACOS_HOSTNAME" \
    RESOLVED_MACOS_DOCK="$RESOLVED_MACOS_DOCK" \
    RESOLVED_MACOS_DESKTOP="$RESOLVED_MACOS_DESKTOP" \
    RESOLVED_MACOS_DEFAULT_APPS="$RESOLVED_MACOS_DEFAULT_APPS" \
    RESOLVED_MACOS_MENU_BAR="$RESOLVED_MACOS_MENU_BAR" \
    RESOLVED_MACOS_MOUSE="$RESOLVED_MACOS_MOUSE" \
    RESOLVED_MACOS_POWER="$RESOLVED_MACOS_POWER" \
    RESOLVED_MACOS_FINDER="$RESOLVED_MACOS_FINDER" \
    RESOLVED_MACOS_SCREENSHOTS="$RESOLVED_MACOS_SCREENSHOTS" \
    RESOLVED_MACOS_TOUCH_ID="$RESOLVED_MACOS_TOUCH_ID" \
    DRY_RUN="$DRY_RUN" \
    NON_INTERACTIVE="$NON_INTERACTIVE" \
    /bin/zsh "$script_path"
  status_pass "Personal layer" "completed"
}


# =============================================================================
# SECTION 9: MODE ORCHESTRATORS
# =============================================================================

# ensure_foundation -- Run all foundation steps in setup/ensure mode
#
# What: Sequential orchestrator for the full foundation provisioning flow.
# Why:  Provides a single entrypoint for the setup/ensure modes.
# Checks: Delegates to individual functions.
# Gates: Delegates to individual functions.
# Side effects: Installs software, writes configs, modifies shell state.
# Idempotency: Every step is individually idempotent.
ensure_foundation() {
  ensure_homebrew
  brew_shellenv
  ensure_mise
  ensure_selected_mise_config
  ensure_profile_block
  activate_shell
  ensure_mise_bootstrap_packages
  ensure_mise_python
  handle_zscaler
  ensure_mise_tools
  ensure_mise_post_bootstrap
  validate_foundation
  run_personal_layer
}

# update_foundation -- Run all foundation steps in update mode
#
# What: Sequential orchestrator for the update flow. Same as ensure but also
#       runs brew update/upgrade and mise upgrade.
# Why:  Provides a single entrypoint for the update mode.
# Checks: Delegates to individual functions.
# Gates: Delegates to individual functions.
# Side effects: Upgrades software, writes configs, modifies shell state.
# Idempotency: Every step is individually idempotent.
update_foundation() {
  ensure_homebrew
  brew_shellenv
  update_brew_packages
  ensure_mise
  ensure_selected_mise_config
  ensure_profile_block
  activate_shell
  ensure_mise_bootstrap_packages
  ensure_mise_python
  handle_zscaler
  update_mise
  ensure_mise_post_bootstrap
  validate_foundation
  run_personal_layer
}


# =============================================================================
# SECTION 10: MODE SELECTION
# =============================================================================

selection_has() {
  local selection="${1:-}"
  local item="${2:?selection_has requires an item}"
  printf '%s\n' "$selection" | grep -Fxq -- "$item"
}

show_interactive_help() {
  panel "What this bootstrap does\n\nMandatory foundation (every profile)\n  • Installs Apple Command Line Tools when a streamed first run needs them\n  • Installs Homebrew\n  • Installs standalone mise\n  • Installs Gum through mise so this interface works\n\nProfiles are editable presets\n  work     Ben's complete setup plus Zscaler auto-detection\n  home     Ben's complete personal setup without Zscaler\n  minimal  Neutral baseline for another adopter; Ben's package, app,\n           tool, and dotfile catalogues start disabled\n\nOptional stages\n  • Ben's Homebrew CLI catalogue, Brewfile apps/fonts, mise tools,\n    and dotfiles are four independent choices\n  • Device name, Git author identity, ~/code, Downloads-to-iCloud, login\n    shell, remote access, Rosetta, and Zscaler are independent choices\n  • macOS settings are split into hostname, Dock, desktop, default apps,\n    menu bar/clock, mouse, power, Finder, screenshots, and Touch ID sudo\n\nThe current macOS account ($(id -un)) is detected and never renamed. Full\nXcode and App Store application inventory remain manual. Administrator,\nthird-party trust, and licence prompts are never silently accepted."
}

run_interactive_audit_menu() {
  local audit_choice=""
  audit_choice="$(gum choose --header="Choose the audit perspective" \
    "General current-machine inventory" \
    "Compare with a bootstrap profile" \
    "Back")"

  case "$audit_choice" in
    "General current-machine inventory")
      exec /bin/zsh "$SCRIPT_DIR/audit-macos.zsh" --general
      ;;
    "Compare with a bootstrap profile")
      local profile_choice=""
      profile_choice="$(gum choose --header="Choose the bootstrap profile to compare" \
        "home — Ben's full personal setup" \
        "work — Ben's setup plus Zscaler" \
        "minimal — neutral baseline for other adopters" \
        "Back")"
      [[ "$profile_choice" == "Back" || -z "$profile_choice" ]] && return 0
      exec /bin/zsh "$SCRIPT_DIR/audit-macos.zsh" \
        --profile "${profile_choice%% —*}"
      ;;
    *) return 0 ;;
  esac
}

# select_interactive_plan -- Collect the normal operator workflow through gum
select_interactive_plan() {
  typeset -g INTERACTIVE_WORKFLOW=1

  local action=""
  while true; do
    action="$(gum choose --header="What do you want to do?" \
      "Bootstrap or repair this Mac" \
      "Update managed software" \
      "Run a read-only audit" \
      "Explain bootstrap and profiles" \
      "Quit")"

    if [[ "$action" == "Explain bootstrap and profiles" ]]; then
      show_interactive_help
      continue
    fi
    if [[ "$action" == "Run a read-only audit" ]]; then
      run_interactive_audit_menu
      continue
    fi
    break
  done

  case "$action" in
    "Bootstrap or repair this Mac") MODE="setup" ;;
    "Update managed software") MODE="update" ;;
    "Quit"|"") exit 0 ;;
  esac

  local profile_default="${DEVICE_PROFILE:-$(state_get DEVICE_PROFILE)}"
  [[ -n "$profile_default" ]] || profile_default="home"
  local work_profile="work — Ben's setup plus Zscaler"
  local home_profile="home — Ben's full personal setup"
  local minimal_profile="minimal — neutral baseline for other adopters"
  local -a profile_options
  case "$profile_default" in
    work) profile_options=("$work_profile" "$home_profile" "$minimal_profile") ;;
    minimal) profile_options=("$minimal_profile" "$home_profile" "$work_profile") ;;
    *) profile_options=("$home_profile" "$work_profile" "$minimal_profile") ;;
  esac
  local profile_choice=""
  profile_choice="$(gum choose --header="Choose an editable profile preset" \
    "${profile_options[@]}")"
  CLI_PROFILE="${profile_choice%% —*}"

  local shell_default="${PREFERRED_SHELL:-$(state_get PREFERRED_SHELL)}"
  [[ -n "$shell_default" ]] || {
    [[ "$CLI_PROFILE" == "minimal" ]] && shell_default="zsh" || shell_default="fish"
  }
  if [[ "$shell_default" == "zsh" ]]; then
    CLI_SHELL="$(gum choose --header="Choose the login shell" zsh fish)"
  else
    CLI_SHELL="$(gum choose --header="Choose the login shell" fish zsh)"
  fi

  local opt_packages="Ben's Homebrew CLI package catalogue"
  local opt_apps="Ben's Brewfile applications and fonts"
  local opt_dotfiles="Ben's managed dotfiles"
  local opt_tools="Ben's mise developer tools"
  local opt_code="Create ~/code"
  local opt_downloads="Link ~/Downloads to iCloud Drive"
  local opt_git="Seed Git author name and email"
  local opt_defaults="Choose macOS preference groups"
  local opt_remote="Remote Login and Screen Sharing"
  local opt_rosetta="Rosetta 2"
  local opt_shell="Set the selected login shell"
  local opt_zscaler="Work network and Zscaler trust"
  local -a feature_options
  feature_options=(
    "$opt_packages"
    "$opt_apps"
    "$opt_dotfiles"
    "$opt_tools"
    "$opt_code"
    "$opt_downloads"
    "$opt_git"
    "$opt_defaults"
    "$opt_remote"
    "$opt_rosetta"
    "$opt_shell"
    "$opt_zscaler"
  )

  local -a default_features
  [[ "$(get_profile_default "$CLI_PROFILE" ENABLE_PACKAGES)" == "true" ]] && default_features+=("$opt_packages")
  [[ "$(get_profile_default "$CLI_PROFILE" ENABLE_APPLICATIONS)" == "true" ]] && default_features+=("$opt_apps")
  [[ "$(get_profile_default "$CLI_PROFILE" ENABLE_DOTFILES)" == "true" ]] && default_features+=("$opt_dotfiles")
  [[ "$(get_profile_default "$CLI_PROFILE" ENABLE_MISE_TOOLS)" == "true" ]] && default_features+=("$opt_tools")
  [[ "$(get_profile_default "$CLI_PROFILE" ENABLE_CODE_DIRECTORY)" == "true" ]] && default_features+=("$opt_code")
  [[ "$(get_profile_default "$CLI_PROFILE" ENABLE_DOWNLOADS_LINK)" == "true" ]] && default_features+=("$opt_downloads")
  [[ "$(get_profile_default "$CLI_PROFILE" ENABLE_GIT_IDENTITY)" == "true" ]] && default_features+=("$opt_git")
  [[ "$(get_profile_default "$CLI_PROFILE" ENABLE_MACOS_DEFAULTS)" == "true" ]] && default_features+=("$opt_defaults")
  [[ "$(get_profile_default "$CLI_PROFILE" ENABLE_REMOTE_ACCESS)" == "true" ]] && default_features+=("$opt_remote")
  [[ "$(uname -m)" == "arm64" && "$(get_profile_default "$CLI_PROFILE" ENABLE_ROSETTA)" == "true" ]] && default_features+=("$opt_rosetta")
  [[ "$(get_profile_default "$CLI_PROFILE" ENABLE_SHELL_DEFAULT)" == "true" ]] && default_features+=("$opt_shell")
  [[ "$CLI_PROFILE" == "work" ]] && default_features+=("$opt_zscaler")
  local selected_defaults="${(j:,:)default_features}"

  local features=""
  features="$(gum choose --no-limit --height=16 \
    --header="Select stages (Space toggles; Return continues)" \
    --selected="$selected_defaults" \
    "${feature_options[@]}")"

  selection_has "$features" "$opt_packages" && CLI_ENABLE_PACKAGES="true" || CLI_ENABLE_PACKAGES="false"
  selection_has "$features" "$opt_apps" && CLI_ENABLE_APPLICATIONS="true" || CLI_ENABLE_APPLICATIONS="false"
  selection_has "$features" "$opt_dotfiles" && CLI_ENABLE_DOTFILES="true" || CLI_ENABLE_DOTFILES="false"
  selection_has "$features" "$opt_tools" && CLI_ENABLE_MISE_TOOLS="true" || CLI_ENABLE_MISE_TOOLS="false"
  selection_has "$features" "$opt_code" && CLI_ENABLE_CODE_DIRECTORY="true" || CLI_ENABLE_CODE_DIRECTORY="false"
  selection_has "$features" "$opt_downloads" && CLI_ENABLE_DOWNLOADS_LINK="true" || CLI_ENABLE_DOWNLOADS_LINK="false"
  selection_has "$features" "$opt_git" && CLI_ENABLE_GIT_IDENTITY="true" || CLI_ENABLE_GIT_IDENTITY="false"
  selection_has "$features" "$opt_defaults" && CLI_ENABLE_MACOS_DEFAULTS="true" || CLI_ENABLE_MACOS_DEFAULTS="false"
  selection_has "$features" "$opt_remote" && CLI_ENABLE_REMOTE_ACCESS="true" || CLI_ENABLE_REMOTE_ACCESS="false"
  selection_has "$features" "$opt_rosetta" && CLI_ENABLE_ROSETTA="true" || CLI_ENABLE_ROSETTA="false"
  selection_has "$features" "$opt_shell" && CLI_ENABLE_SHELL_DEFAULT="true" || CLI_ENABLE_SHELL_DEFAULT="false"
  if selection_has "$features" "$opt_zscaler"; then
    CLI_ENABLE_ZSCALER="auto"
  else
    CLI_ENABLE_ZSCALER="false"
  fi

  local mac_hostname="Machine name / hostname"
  local mac_dock="Dock layout and Ghostty/Chrome pins"
  local mac_desktop="Disable widgets and click-to-show-desktop"
  local mac_default_apps="Chrome browser and PDF handlers"
  local mac_menu="Menu bar icons and 24-hour clock"
  local mac_mouse="Disable mouse acceleration"
  local mac_power="Hardware-specific power and sleep policy"
  local mac_finder="Finder preferences and Library visibility"
  local mac_screenshots="PNG screenshots"
  local mac_touch="Touch ID for sudo (pam-reattach)"
  local -a mac_options mac_defaults
  mac_options=(
    "$mac_hostname" "$mac_dock" "$mac_desktop" "$mac_default_apps"
    "$mac_menu" "$mac_mouse" "$mac_power" "$mac_finder"
    "$mac_screenshots" "$mac_touch"
  )
  local mac_selection=""
  if [[ "$CLI_ENABLE_MACOS_DEFAULTS" == "true" ]]; then
    local mac_key
    local -a mac_keys
    mac_keys=(HOSTNAME DOCK DESKTOP DEFAULT_APPS MENU_BAR MOUSE POWER FINDER SCREENSHOTS TOUCH_ID)
    local i
    for (( i = 1; i <= ${#mac_options[@]}; i++ )); do
      mac_key="${mac_keys[$i]}"
      [[ "$(get_profile_default "$CLI_PROFILE" "MACOS_${mac_key}")" == "true" ]] \
        && mac_defaults+=("${mac_options[$i]}")
    done
    mac_selection="$(gum choose --no-limit --height=12 \
      --header="Select macOS preference groups" \
      --selected="${(j:,:)mac_defaults}" \
      "${mac_options[@]}")"
  fi

  selection_has "$mac_selection" "$mac_hostname" && CLI_MACOS_HOSTNAME="true" || CLI_MACOS_HOSTNAME="false"
  selection_has "$mac_selection" "$mac_dock" && CLI_MACOS_DOCK="true" || CLI_MACOS_DOCK="false"
  selection_has "$mac_selection" "$mac_desktop" && CLI_MACOS_DESKTOP="true" || CLI_MACOS_DESKTOP="false"
  selection_has "$mac_selection" "$mac_default_apps" && CLI_MACOS_DEFAULT_APPS="true" || CLI_MACOS_DEFAULT_APPS="false"
  selection_has "$mac_selection" "$mac_menu" && CLI_MACOS_MENU_BAR="true" || CLI_MACOS_MENU_BAR="false"
  selection_has "$mac_selection" "$mac_mouse" && CLI_MACOS_MOUSE="true" || CLI_MACOS_MOUSE="false"
  selection_has "$mac_selection" "$mac_power" && CLI_MACOS_POWER="true" || CLI_MACOS_POWER="false"
  selection_has "$mac_selection" "$mac_finder" && CLI_MACOS_FINDER="true" || CLI_MACOS_FINDER="false"
  selection_has "$mac_selection" "$mac_screenshots" && CLI_MACOS_SCREENSHOTS="true" || CLI_MACOS_SCREENSHOTS="false"
  selection_has "$mac_selection" "$mac_touch" && CLI_MACOS_TOUCH_ID="true" || CLI_MACOS_TOUCH_ID="false"

  if [[ "$CLI_MACOS_HOSTNAME" == "true" ]]; then
    local device_default="${DEVICE_NAME:-$(state_get DEVICE_NAME)}"
    [[ -n "$device_default" ]] || device_default="$(default_device_name)"
    CLI_DEVICE_NAME="$(gum input --header="Device name (does not rename account $(id -un))" \
      --value="$device_default")"
  fi

  if [[ "$CLI_ENABLE_GIT_IDENTITY" == "true" ]]; then
    local git_name_default="${GIT_USER_NAME:-$(state_get GIT_USER_NAME)}"
    local git_email_default="${GIT_USER_EMAIL:-$(state_get GIT_USER_EMAIL)}"
    [[ -n "$git_name_default" ]] || git_name_default="$(git config --global --includes --get user.name 2>/dev/null || true)"
    [[ -n "$git_email_default" ]] || git_email_default="$(git config --global --includes --get user.email 2>/dev/null || true)"
    if [[ -n "$git_name_default" ]]; then
      CLI_GIT_USER_NAME="$(gum input --header="Git author name" --value="$git_name_default")"
    else
      CLI_GIT_USER_NAME="$(gum input --header="Git author name" --placeholder="Ada Lovelace")"
    fi
    if [[ -n "$git_email_default" ]]; then
      CLI_GIT_USER_EMAIL="$(gum input --header="Git author email" --value="$git_email_default")"
    else
      CLI_GIT_USER_EMAIL="$(gum input --header="Git author email" --placeholder="ada@example.com")"
    fi
  fi

  if [[ "$CLI_ENABLE_APPLICATIONS" == "true" \
    || "$CLI_ENABLE_DOTFILES" == "true" \
    || "$CLI_ENABLE_MACOS_DEFAULTS" == "true" \
    || "$CLI_ENABLE_REMOTE_ACCESS" == "true" \
    || "$CLI_ENABLE_ROSETTA" == "true" \
    || "$CLI_ENABLE_SHELL_DEFAULT" == "true" \
    || "$CLI_ENABLE_CODE_DIRECTORY" == "true" \
    || "$CLI_ENABLE_DOWNLOADS_LINK" == "true" \
    || "$CLI_ENABLE_GIT_IDENTITY" == "true" ]]; then
    ENABLE_PERSONAL=1
  else
    ENABLE_PERSONAL=0
  fi
}

confirm_interactive_plan() {
  [[ "${INTERACTIVE_WORKFLOW:-0}" == "1" ]] || return 0

  local git_author_line=""
  if [[ "$RESOLVED_GIT_IDENTITY" == "true" ]]; then
    git_author_line="\nGit author: $RESOLVED_GIT_USER_NAME <$RESOLVED_GIT_USER_EMAIL>"
  fi
  panel "Bootstrap plan\n\nAction: $MODE\nProfile: $RESOLVED_PROFILE\nDetected account: $(id -un) (never renamed)\nDevice name: $RESOLVED_DEVICE_NAME\nShell: $RESOLVED_SHELL\nBen's CLI packages: $RESOLVED_PACKAGES\nBen's Brewfile apps/fonts: $RESOLVED_APPLICATIONS\nBen's dotfiles: $RESOLVED_DOTFILES\nBen's mise tools: $RESOLVED_MISE_TOOLS\nCreate ~/code: $RESOLVED_CODE_DIRECTORY\nLink Downloads to iCloud: $RESOLVED_DOWNLOADS_LINK\nSeed Git identity: $RESOLVED_GIT_IDENTITY${git_author_line}\nmacOS preferences: $RESOLVED_MACOS_DEFAULTS\n  hostname=$RESOLVED_MACOS_HOSTNAME dock=$RESOLVED_MACOS_DOCK desktop=$RESOLVED_MACOS_DESKTOP\n  default-apps=$RESOLVED_MACOS_DEFAULT_APPS menu-bar=$RESOLVED_MACOS_MENU_BAR mouse=$RESOLVED_MACOS_MOUSE\n  power=$RESOLVED_MACOS_POWER finder=$RESOLVED_MACOS_FINDER screenshots=$RESOLVED_MACOS_SCREENSHOTS touch-id=$RESOLVED_MACOS_TOUCH_ID\nRemote access: $RESOLVED_REMOTE_ACCESS\nRosetta: $RESOLVED_ROSETTA\nSet login shell: $RESOLVED_SHELL_DEFAULT\nZscaler: $RESOLVED_ZSCALER\n\nFull Xcode and App Store applications remain manual. Administrator and licence prompts stay attached to this terminal."

  local affirmative="Apply plan"
  dry_run_active && affirmative="Preview plan"
  if ! gum confirm --default --affirmative="$affirmative" --negative="Cancel" \
    "Continue with this plan?"; then
    warn "Bootstrap cancelled; no planned stages were run."
    exit 0
  fi
}

# select_mode -- Prompt the user to choose a mode if MODE is not set
#
# What: If MODE is empty and gum is available, presents an interactive chooser.
#       If MODE is empty and non-interactive, fails with an error.
# Why:  Supports both interactive first-run and CI/scripted invocations.
# Checks: MODE emptiness, use_gum() availability.
# Gates: NON_INTERACTIVE (fails if mode is empty and non-interactive).
# Side effects: Sets MODE global variable.
# Idempotency: No-op if MODE is already set.
select_mode() {
  if [[ -n "$MODE" ]]; then
    return 0
  fi

  if use_gum; then
    select_interactive_plan
    return 0
  fi

  # Non-interactive and no MODE -- cannot proceed
  fail "MODE is not set and running non-interactively. Pass a mode: setup, ensure, update, or personal."
}


# =============================================================================
# SECTION 11: MAIN
# =============================================================================

main() {
  # Phase 1: Parse args
  # Parse early so --help can exit cleanly before any bootstrap work runs.
  parse_foundation_args "$@"

  # Phase 2: Bootstrap the minimum UI dependencies. Gum remains mise-managed;
  # only that one tool is installed before the interactive plan is shown.
  ensure_homebrew
  brew_shellenv
  ensure_mise
  if [[ "$NON_INTERACTIVE" != "1" && -t 1 ]]; then
    ensure_gum
  fi

  # Phase 3: Set up UI
  setup_gum_theme

  # Phase 4: Pre-flight inventory
  # Snapshot everything that's already installed BEFORE making any changes.
  # Populates PREFLIGHT_* globals that ensure_* functions can reference.
  preflight_inventory

  # Phase 5: Read state and resolve all flags
  # The resolution engine walks CLI -> env -> state -> profile -> prompt -> default
  # for every configurable setting.
  state_read
  select_mode
  local component_override=""
  for component_override in \
    "$CLI_MACOS_HOSTNAME" "$CLI_MACOS_DOCK" "$CLI_MACOS_DESKTOP" \
    "$CLI_MACOS_DEFAULT_APPS" "$CLI_MACOS_MENU_BAR" "$CLI_MACOS_MOUSE" \
    "$CLI_MACOS_POWER" "$CLI_MACOS_FINDER" "$CLI_MACOS_SCREENSHOTS" \
    "$CLI_MACOS_TOUCH_ID"; do
    if [[ "$component_override" == "true" ]]; then
      CLI_ENABLE_MACOS_DEFAULTS="true"
      break
    fi
  done
  resolve_all_flags \
    "$CLI_SHELL" \
    "$CLI_PROFILE" \
    "$CLI_ENABLE_ZSCALER" \
    "$CLI_ENABLE_DOTFILES" \
    "$CLI_ENABLE_MACOS_DEFAULTS" \
    "$CLI_ENABLE_ROSETTA" \
    "$CLI_ENABLE_MISE_TOOLS" \
    "$CLI_ENABLE_SHELL_DEFAULT" \
    "$CLI_ENABLE_REMOTE_ACCESS" \
    "$CLI_ENABLE_APPLICATIONS" \
    "$CLI_ENABLE_PACKAGES" \
    "$CLI_ENABLE_CODE_DIRECTORY" \
    "$CLI_ENABLE_DOWNLOADS_LINK" \
    "$CLI_ENABLE_GIT_IDENTITY"
  resolve_macos_components
  resolve_adoption_values

  if [[ "$MODE" == "personal" \
    || "$RESOLVED_APPLICATIONS" == "true" \
    || "$RESOLVED_DOTFILES" == "true" \
    || "$RESOLVED_MACOS_DEFAULTS" == "true" \
    || "$RESOLVED_REMOTE_ACCESS" == "true" \
    || "$RESOLVED_ROSETTA" == "true" \
    || "$RESOLVED_SHELL_DEFAULT" == "true" \
    || "$RESOLVED_CODE_DIRECTORY" == "true" \
    || "$RESOLVED_DOWNLOADS_LINK" == "true" \
    || "$RESOLVED_GIT_IDENTITY" == "true" ]]; then
    ENABLE_PERSONAL=1
  fi
  confirm_interactive_plan
  state_write_all

  # Phase 5: Display config panel
  local dry_label=""
  if dry_run_active; then
    dry_label="\n*** DRY RUN — no changes will be made ***"
  fi
  panel "macOS foundation bootstrap\nMode: $MODE\nShell: $RESOLVED_SHELL\nProfile: $RESOLVED_PROFILE${dry_label}"

  # Phase 6: Dispatch
  case "$MODE" in
    setup|ensure)
      ensure_foundation
      ;;
    update)
      update_foundation
      ;;
    personal)
      validate_foundation
      run_personal_layer
      ;;
    *)
      fail "Unsupported mode: $MODE"
      ;;
  esac

  # Phase 7: Read-only convergence audit
  if ! dry_run_active; then
    note "Running the final read-only machine audit."
    NON_INTERACTIVE=1 /bin/zsh "$SCRIPT_DIR/audit-macos.zsh" \
      --expect-state --non-interactive
  fi

  # Phase 8: Summary
  status_summary "Foundation"
  success "Done."
}

main "$@"
