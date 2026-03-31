#!/bin/zsh
# =============================================================================
# audit-macos.zsh -- Standalone macOS machine state audit
#
# Performs a comprehensive, read-only audit of the current machine state. This
# is the same pre-flight inventory used by foundation-macos.zsh, plus extended
# checks for the personal layer (tuckr, brew bundle, mise tools, symlinks).
#
# Can be run at any time without making changes. Use it to:
#   - See what's installed before running the bootstrap
#   - Verify the bootstrap completed correctly after running it
#   - Diagnose drift between the expected and actual state
#   - Feed into the "ensure" / "update" modes with a known baseline
#
# Usage:
#   ./audit-macos.zsh                     # Full audit with gum-styled output
#   ./audit-macos.zsh --section tools     # Audit only the tools section
#   ./audit-macos.zsh --json              # Output machine-readable JSON
#   NON_INTERACTIVE=1 ./audit-macos.zsh   # No gum dependency
#   ./bootstrap-macos.zsh audit --json    # Repo-local entrypoint path
#
# Exit codes:
#   0 -- audit completed (does not mean everything is installed)
#   1 -- audit script itself failed to run
#
# This script is PURELY read-only. It never installs, writes, or modifies
# anything on the system.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.zsh"

# -- Constants that the audit needs but are defined in foundation-macos.zsh ---
# We duplicate them here so the audit can run standalone without sourcing the
# full foundation script.
# NOTE: mise is NOT in this list — it can be installed via Homebrew OR shell
# installer. It has a dedicated check below.
FOUNDATION_BREW_PACKAGES=(git gh jq yq fzf fd ripgrep zoxide lazygit openssl gum)
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
MISE_CONFIG_PATH="$HOME/.config/mise/config.toml"
MISE_ENV_PATH="$HOME/.config/mise/.env"
CERTS_DIR="$HOME/certs"
GOLDEN_BUNDLE_PATH="$CERTS_DIR/golden_pem.pem"

# -- Flags --------------------------------------------------------------------
AUDIT_SECTION=""   # empty = all sections
AUDIT_JSON=0

# =============================================================================
# SECTION 1: ARGUMENT PARSING
# =============================================================================

# parse_audit_args -- Parse CLI arguments for the audit script
#
# Checks: Validates known flags.
# Gates: None.
# Side effects: Sets AUDIT_SECTION and AUDIT_JSON globals.
# Idempotency: Overwrites with same values each time.
parse_audit_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --section)
        [[ $# -ge 2 ]] || { fail "--section requires a value (tools, shell, configs, personal, all)"; }
        AUDIT_SECTION="$2"
        shift 2
        ;;
      --json)
        AUDIT_JSON=1
        shift
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      -h|--help)
        audit_usage
        exit 0
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done
}

# audit_usage -- Print help text
audit_usage() {
  cat <<'EOF'
Usage: audit-macos.zsh [options]

Options:
  --section <name>     Audit only a specific section:
                         tools    - Package managers, CLI tools, runtimes
                         shell    - Shell config, profile blocks, /etc/shells
                         configs  - Dotfiles, state file, mise config, certs
                         personal - Tuckr, brew bundle, macOS defaults
                         all      - Everything (default)
  --json               Output results as JSON (machine-readable)
  --non-interactive    Suppress gum-styled output
  -h, --help           Show this help text

This script is read-only. It never installs, writes, or modifies anything.
EOF
}


# =============================================================================
# SECTION 2: EXTENDED AUDIT CHECKS
# =============================================================================

# audit_tools -- Audit package managers, CLI tools, and runtimes
#
# What: Checks availability and versions of all foundation tools plus
#       additional tools that the personal layer installs.
# Checks: command -v, brew list, mise list.
# Gates: None — always runs.
# Side effects: Writes to stdout only.
# Idempotency: Pure detection — no system modifications.
audit_tools() {
  note "── Tools & Package Managers ──"
  echo ""

  # Homebrew
  if command_exists brew; then
    _inventory_line "Homebrew:" "$(brew --version 2>/dev/null | head -1)"
  else
    _inventory_line "Homebrew:" "NOT INSTALLED"
  fi

  # Foundation packages
  if command_exists brew; then
    local pkg missing_list=()
    local present=0 missing=0
    for pkg in "${FOUNDATION_BREW_PACKAGES[@]}"; do
      if brew list "$pkg" >/dev/null 2>&1; then
        present=$((present + 1))
      else
        missing=$((missing + 1))
        missing_list+=("$pkg")
      fi
    done
    _inventory_line "Foundation packages:" "${present}/${#FOUNDATION_BREW_PACKAGES[@]} present"
    if [[ ${#missing_list[@]} -gt 0 ]]; then
      _inventory_line "  Missing:" "${missing_list[*]}"
    fi
  else
    _inventory_line "Foundation packages:" "cannot check (brew not installed)"
  fi

  # Mise (installed via Homebrew OR shell installer — not in foundation packages)
  if command_exists mise; then
    local mise_ver mise_method
    mise_ver="$(mise --version 2>/dev/null || echo "unknown")"
    if command_exists brew && brew list mise >/dev/null 2>&1; then
      mise_method="homebrew"
    elif [[ -x "$HOME/.local/bin/mise" ]]; then
      mise_method="shell installer (~/.local/bin)"
    else
      mise_method="unknown method"
    fi
    _inventory_line "Mise:" "$mise_ver ($mise_method)"
    # Count installed tools
    local tool_count
    tool_count="$(mise list 2>/dev/null | wc -l | tr -d ' ')"
    _inventory_line "  Installed tools:" "$tool_count"
  else
    _inventory_line "Mise:" "NOT INSTALLED"
  fi

  # Additional tools (not in foundation but expected after personal layer)
  local extra_tools=(tuckr tmux nvim yazi fish lazygit)
  for tool in "${extra_tools[@]}"; do
    if command_exists "$tool"; then
      local ver=""
      case "$tool" in
        fish)    ver="$(fish --version 2>/dev/null | head -1)" ;;
        tmux)    ver="$(tmux -V 2>/dev/null)" ;;
        nvim)    ver="$(nvim --version 2>/dev/null | head -1)" ;;
        lazygit) ver="$(lazygit --version 2>/dev/null | head -1)" ;;
        tuckr)   ver="installed" ;;
        yazi)    ver="$(yazi --version 2>/dev/null | head -1)" ;;
      esac
      _inventory_line "$tool:" "${ver:-installed}"
    else
      _inventory_line "$tool:" "not installed"
    fi
  done

  echo ""
}


# audit_shell -- Audit shell configuration state
#
# What: Checks current login shell, shell binaries, /etc/shells registration,
#       and managed profile blocks.
# Checks: $SHELL, file existence, grep for markers.
# Gates: None.
# Side effects: Writes to stdout only.
# Idempotency: Pure detection.
audit_shell() {
  note "── Shell Configuration ──"
  echo ""

  _inventory_line "Current \$SHELL:" "$SHELL"
  _inventory_line "Running shell:" "$ZSH_VERSION (zsh)"

  # Fish
  if [[ -x /opt/homebrew/bin/fish ]]; then
    _inventory_line "Fish binary:" "/opt/homebrew/bin/fish"
  elif [[ -x /usr/local/bin/fish ]]; then
    _inventory_line "Fish binary:" "/usr/local/bin/fish"
  else
    _inventory_line "Fish binary:" "not installed"
  fi

  # Zsh
  if [[ -x /opt/homebrew/bin/zsh ]]; then
    _inventory_line "Zsh binary:" "/opt/homebrew/bin/zsh (brew)"
  fi
  _inventory_line "System zsh:" "/bin/zsh ($(zsh --version 2>/dev/null | head -1))"

  # /etc/shells registration
  local shells_content
  shells_content="$(cat /etc/shells 2>/dev/null)"
  if echo "$shells_content" | grep -qx "/opt/homebrew/bin/fish"; then
    _inventory_line "Fish in /etc/shells:" "yes"
  else
    _inventory_line "Fish in /etc/shells:" "NO"
  fi
  if echo "$shells_content" | grep -qx "/opt/homebrew/bin/zsh"; then
    _inventory_line "Brew zsh in /etc/shells:" "yes"
  else
    _inventory_line "Brew zsh in /etc/shells:" "no (system zsh is in /etc/shells)"
  fi

  # Managed profile blocks
  if [[ -f "$HOME/.zshrc" ]] && grep -qF "$PROFILE_BEGIN" "$HOME/.zshrc" 2>/dev/null; then
    _inventory_line "Zsh profile block:" "present"
  else
    _inventory_line "Zsh profile block:" "absent"
  fi

  if [[ -f "$HOME/.config/fish/conf.d/00-foundation.fish" ]]; then
    _inventory_line "Fish profile block:" "present"
    if grep -qF "foundation-bootstrap" "$HOME/.config/fish/conf.d/00-foundation.fish" 2>/dev/null; then
      _inventory_line "  Contains markers:" "yes"
    else
      _inventory_line "  Contains markers:" "NO (file exists but not managed)"
    fi
  else
    _inventory_line "Fish profile block:" "absent"
  fi

  # Fisher (fish plugin manager)
  if [[ -f "$HOME/.config/fish/functions/fisher.fish" ]]; then
    _inventory_line "Fisher:" "installed"
  else
    _inventory_line "Fisher:" "not installed"
  fi

  echo ""
}


# audit_configs -- Audit configuration files and state
#
# What: Checks dotfiles repo, state file, mise config, certs, and key
#       symlinks/config files.
# Checks: File/directory existence, git status, state file contents.
# Gates: None.
# Side effects: Writes to stdout only.
# Idempotency: Pure detection.
audit_configs() {
  note "── Configuration & State ──"
  echo ""

  # Dotfiles repo
  if [[ -d "$DOTFILES_DIR/.git" ]]; then
    _inventory_line "Dotfiles repo:" "present at $DOTFILES_DIR"
    local branch
    branch="$(git -C "$DOTFILES_DIR" branch --show-current 2>/dev/null || echo "unknown")"
    _inventory_line "  Branch:" "$branch"
    local status_count
    status_count="$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$status_count" -eq 0 ]]; then
      _inventory_line "  Working tree:" "clean"
    else
      _inventory_line "  Working tree:" "$status_count uncommitted changes"
    fi
    local remote_url
    remote_url="$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || echo "none")"
    _inventory_line "  Remote:" "$remote_url"
  else
    _inventory_line "Dotfiles repo:" "NOT FOUND at $DOTFILES_DIR"
  fi

  # State file
  if [[ -f "$STATE_FILE_PATH" ]]; then
    _inventory_line "State file:" "present at $STATE_FILE_PATH"
    # Show key values from state file
    local key val
    while IFS='=' read -r key val; do
      [[ -z "$key" || "$key" == \#* ]] && continue
      _inventory_line "  $key:" "$val"
    done < "$STATE_FILE_PATH"
  else
    _inventory_line "State file:" "absent (first run or deleted)"
  fi

  # Mise config
  if [[ -f "$MISE_CONFIG_PATH" ]]; then
    _inventory_line "Mise config:" "present"
  else
    _inventory_line "Mise config:" "absent"
  fi

  # Mise env
  if [[ -f "$MISE_ENV_PATH" ]]; then
    _inventory_line "Mise .env:" "present"
    if grep -q "ZSCALER" "$MISE_ENV_PATH" 2>/dev/null; then
      _inventory_line "  Zscaler vars:" "present"
    fi
  else
    _inventory_line "Mise .env:" "absent"
  fi

  # Certificates
  if [[ -f "$GOLDEN_BUNDLE_PATH" ]]; then
    local cert_count
    cert_count="$(grep -c "BEGIN CERTIFICATE" "$GOLDEN_BUNDLE_PATH" 2>/dev/null || echo 0)"
    _inventory_line "Golden CA bundle:" "present ($cert_count certs)"
  else
    _inventory_line "Golden CA bundle:" "absent"
  fi

  # Architecture and system
  _inventory_line "Architecture:" "$(uname -m)"
  _inventory_line "macOS version:" "$(sw_vers -productVersion 2>/dev/null || echo "unknown")"

  if [[ "$(uname -m)" == "arm64" ]]; then
    if pgrep -q oahd 2>/dev/null; then
      _inventory_line "Rosetta 2:" "installed"
    else
      _inventory_line "Rosetta 2:" "NOT INSTALLED"
    fi
  else
    _inventory_line "Rosetta 2:" "n/a (Intel)"
  fi

  echo ""
}


# audit_personal -- Audit personal layer state (tuckr, brew bundle, defaults)
#
# What: Checks tuckr symlink status, brew bundle satisfaction, and whether
#       macOS defaults have been applied.
# Checks: tuckr status, brew bundle check, defaults read.
# Gates: None.
# Side effects: Writes to stdout only.
# Idempotency: Pure detection.
audit_personal() {
  note "── Personal Layer ──"
  echo ""

  # Tuckr symlinks
  if command_exists tuckr; then
    _inventory_line "Tuckr:" "installed"
    # Run tuckr status and display its output directly — it has its own
    # formatted table with symlink/not-symlinked columns.
    (cd "$DOTFILES_DIR" 2>/dev/null && tuckr status 2>&1) || _inventory_line "  Status:" "could not run tuckr status"
  else
    _inventory_line "Tuckr:" "not installed"
  fi

  # Brew bundle check
  local brewfile="$DOTFILES_DIR/Configs/brew/Brewfile"
  if [[ -f "$brewfile" ]] && command_exists brew; then
    _inventory_line "Brewfile:" "present"
    local bundle_check
    bundle_check="$(brew bundle check --file="$brewfile" 2>&1)" && {
      _inventory_line "  Bundle status:" "satisfied"
    } || {
      local missing_count
      missing_count="$(echo "$bundle_check" | grep -c "needs to be installed" || echo "?")"
      _inventory_line "  Bundle status:" "NOT satisfied ($missing_count missing)"
      # Show first few missing
      echo "$bundle_check" | grep "needs to be installed" | head -5 | while IFS= read -r line; do
        _inventory_line "    " "$line"
      done
    }
  else
    _inventory_line "Brewfile:" "not found or brew not installed"
  fi

  # Key config file symlinks
  _check_config_link() {
    local path="$1" label="$2"
    if [[ -L "$path" ]]; then
      local target=""
      target="$(/usr/bin/readlink "$path" 2>/dev/null || true)"
      [[ -z "$target" ]] && target="unknown"
      _inventory_line "$label:" "symlink → $target"
    elif [[ -f "$path" ]]; then
      _inventory_line "$label:" "file (not symlink)"
    else
      _inventory_line "$label:" "absent"
    fi
  }
  _check_config_link "$HOME/.gitconfig"              "Git config"
  _check_config_link "$HOME/.config/nvim/init.lua"   "Neovim config"
  _check_config_link "$HOME/.config/tmux/tmux.conf"  "Tmux config"
  _check_config_link "$HOME/.config/fish/config.fish" "Fish config"
  _check_config_link "$HOME/.config/ghostty/config"  "Ghostty config"
  _check_config_link "$HOME/.ssh/config"             "SSH config"

  # macOS defaults spot-checks
  note "  macOS defaults (spot-check):"
  local dock_autohide
  dock_autohide="$(defaults read com.apple.dock autohide 2>/dev/null || echo "unset")"
  _inventory_line "  Dock auto-hide:" "$dock_autohide"

  local dock_position
  dock_position="$(defaults read com.apple.dock orientation 2>/dev/null || echo "unset")"
  _inventory_line "  Dock position:" "$dock_position"

  local finder_extensions
  finder_extensions="$(defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null || echo "unset")"
  _inventory_line "  Show file extensions:" "$finder_extensions"

  local screenshot_type
  screenshot_type="$(defaults read com.apple.screencapture type 2>/dev/null || echo "unset")"
  _inventory_line "  Screenshot format:" "$screenshot_type"

  echo ""
}


# =============================================================================
# SECTION 3: JSON OUTPUT
# =============================================================================

# audit_json -- Output the full audit as a JSON object
#
# What: Collects all the same checks as the section functions but formats
#       the results as a JSON document. Useful for piping into jq, logging
#       to a file, or feeding into a CI check.
# Checks: Same as individual audit functions.
# Gates: None.
# Side effects: Writes to stdout (JSON).
# Idempotency: Pure detection.
audit_json() {
  local homebrew_version="" mise_version="" arch="" macos_version=""
  local shell_current="" fish_bin="" rosetta="" dotfiles="" state_file=""

  # Gather data
  if command_exists brew; then
    homebrew_version="$(brew --version 2>/dev/null | head -1)"
  fi
  if command_exists mise; then
    mise_version="$(mise --version 2>/dev/null)"
  fi
  arch="$(uname -m)"
  macos_version="$(sw_vers -productVersion 2>/dev/null || echo "unknown")"
  shell_current="$SHELL"

  if [[ -x /opt/homebrew/bin/fish ]]; then
    fish_bin="/opt/homebrew/bin/fish"
  elif [[ -x /usr/local/bin/fish ]]; then
    fish_bin="/usr/local/bin/fish"
  else
    fish_bin=""
  fi

  if [[ "$arch" == "arm64" ]]; then
    rosetta="$(pgrep -q oahd 2>/dev/null && echo "true" || echo "false")"
  else
    rosetta="n/a"
  fi

  dotfiles="$([[ -d "$DOTFILES_DIR/.git" ]] && echo "true" || echo "false")"
  state_file="$([[ -f "$STATE_FILE_PATH" ]] && echo "true" || echo "false")"

  # Build foundation package status
  local pkg_json="{"
  local first=true
  if command_exists brew; then
    local installed=""
    for pkg in "${FOUNDATION_BREW_PACKAGES[@]}"; do
      installed="$(brew list "$pkg" >/dev/null 2>&1 && echo "true" || echo "false")"
      if [[ "$first" == "true" ]]; then
        first=false
      else
        pkg_json+=","
      fi
      pkg_json+="\"$pkg\":$installed"
    done
  fi
  pkg_json+="}"

  cat <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "system": {
    "architecture": "$arch",
    "macos_version": "$macos_version",
    "rosetta": $([[ "$rosetta" == "n/a" ]] && echo "null" || echo "$rosetta")
  },
  "shell": {
    "current": "$shell_current",
    "fish_binary": "$fish_bin",
    "fish_in_etc_shells": $(grep -qx "/opt/homebrew/bin/fish" /etc/shells 2>/dev/null && echo "true" || echo "false"),
    "zsh_profile_block": $([[ -f "$HOME/.zshrc" ]] && grep -qF "$PROFILE_BEGIN" "$HOME/.zshrc" 2>/dev/null && echo "true" || echo "false"),
    "fish_profile_block": $([[ -f "$HOME/.config/fish/conf.d/00-foundation.fish" ]] && echo "true" || echo "false")
  },
  "tools": {
    "homebrew": "${homebrew_version:-null}",
    "mise": "${mise_version:-null}",
    "foundation_packages": $pkg_json,
    "tuckr": $(command_exists tuckr && echo "true" || echo "false"),
    "gum": $(command_exists gum && echo "true" || echo "false")
  },
  "configs": {
    "dotfiles_repo": $dotfiles,
    "state_file": $state_file,
    "mise_config": $([[ -f "$MISE_CONFIG_PATH" ]] && echo "true" || echo "false"),
    "golden_ca_bundle": $([[ -f "$GOLDEN_BUNDLE_PATH" ]] && echo "true" || echo "false")
  }
}
EOF
}


# =============================================================================
# SECTION 4: MAIN
# =============================================================================

main() {
  parse_audit_args "$@"
  setup_gum_theme

  if [[ "$AUDIT_JSON" -eq 1 ]]; then
    audit_json
    return 0
  fi

  panel "macOS Machine Audit\n$(date '+%Y-%m-%d %H:%M:%S')\nRead-only — no changes will be made"

  local section="${AUDIT_SECTION:-all}"

  case "$section" in
    tools)    audit_tools ;;
    shell)    audit_shell ;;
    configs)  audit_configs ;;
    personal) audit_personal ;;
    all)
      audit_tools
      audit_shell
      audit_configs
      audit_personal
      ;;
    *)
      fail "Unknown section: $section (use: tools, shell, configs, personal, all)"
      ;;
  esac

  success "Audit complete."
}

main "$@"
