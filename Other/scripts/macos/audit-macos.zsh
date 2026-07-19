#!/bin/zsh
# =============================================================================
# audit-macos.zsh -- Standalone macOS machine state audit
#
# Performs a comprehensive, read-only audit of the current machine state. This
# is the same pre-flight inventory used by foundation-macos.zsh, plus extended
# checks for the personal layer (mise dotfiles, brew bundle, mise tools, symlinks).
#
# Can be run at any time without making changes. Use it to:
#   - See what's installed before running the bootstrap
#   - Verify the bootstrap completed correctly after running it
#   - Diagnose drift between the expected and actual state
#   - Feed into the "ensure" / "update" modes with a known baseline
#
# Usage:
#   ./audit-macos.zsh --general           # Current machine, no profile drift
#   ./audit-macos.zsh --profile home      # Compare with a profile preset
#   ./audit-macos.zsh --expect-state      # Compare with the saved custom plan
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

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
MISE_CONFIG_PATH="$HOME/.config/mise/config.toml"
MISE_ENV_PATH="$HOME/.config/mise/.env"
CERTS_DIR="$HOME/certs"
GOLDEN_BUNDLE_PATH="$CERTS_DIR/golden_pem.pem"

# Resolve tools from the active shell first, then from mise. The standalone
# audit may be launched before shell activation, so PATH alone is not enough to
# distinguish an absent tool from an installed-but-inactive mise tool.
audit_tool_path() {
  local tool="${1:?audit_tool_path requires a tool name}"
  bootstrap_tool_path "$tool"
}

# Query effective handlers from LaunchServices rather than trusting preference
# records alone. The public setters are deprecated/restricted on Tahoe, but the
# copy APIs remain the authoritative read-only verification surface.
audit_launchservices_handlers_json() {
  macos_launchservices_handlers_json
}

audit_pmset_ac_value() {
  local key="${1:?audit_pmset_ac_value requires a key}"
  pmset -g custom 2>/dev/null | awk -v key="$key" '
    /AC Power:/ { in_ac = 1; next }
    /Battery Power:/ { in_ac = 0; next }
    in_ac && $1 == key { print $2; exit }
  '
}

# -- Flags --------------------------------------------------------------------
AUDIT_SECTION=""   # empty = all sections
AUDIT_JSON=0
AUDIT_CONTEXT="general" # general | profile | state
AUDIT_PROFILE=""

# Resolve read-only expectations for the selected audit perspective. A profile
# comparison uses preset defaults only. Saved-plan mode overlays state-file
# customisations, with missing keys inheriting the saved profile exactly as a
# subsequent ensure run would resolve them. General inventory renders no drift.
audit_load_expectations() {
  local profile setting component value use_state=false
  if [[ "$AUDIT_CONTEXT" == "state" ]]; then
    profile="$(state_get DEVICE_PROFILE)"
    [[ -n "$profile" ]] || profile="minimal"
    use_state=true
  elif [[ "$AUDIT_CONTEXT" == "profile" ]]; then
    profile="$AUDIT_PROFILE"
  else
    # General inventory never renders drift, but initialise the resolved
    # variables so shared read-only collectors remain safe under `set -u`.
    profile="minimal"
  fi
  typeset -g RESOLVED_PROFILE="$profile"
  if [[ "$use_state" == true ]]; then
    typeset -g RESOLVED_SHELL="$(state_get PREFERRED_SHELL)"
    [[ -n "$RESOLVED_SHELL" ]] || RESOLVED_SHELL="fish"
  elif [[ "$profile" == "minimal" ]]; then
    typeset -g RESOLVED_SHELL="zsh"
  else
    typeset -g RESOLVED_SHELL="fish"
  fi

  for setting in ZSCALER DOTFILES PACKAGES APPLICATIONS MACOS_DEFAULTS \
    REMOTE_ACCESS ROSETTA MISE_TOOLS SHELL_DEFAULT CODE_DIRECTORY \
    DOWNLOADS_LINK GIT_IDENTITY; do
    value=""
    [[ "$use_state" == true ]] && value="$(state_get "ENABLE_${setting}")"
    [[ -n "$value" ]] || value="$(get_profile_default "$profile" "ENABLE_${setting}")"
    typeset -g "RESOLVED_${setting}=${value:-false}"
  done

  typeset -g RESOLVED_DEVICE_NAME=""
  [[ "$use_state" == true ]] && RESOLVED_DEVICE_NAME="$(state_get DEVICE_NAME)"
  [[ -n "$RESOLVED_DEVICE_NAME" ]] || RESOLVED_DEVICE_NAME="$(default_device_name)"
  typeset -g RESOLVED_GIT_USER_NAME=""
  typeset -g RESOLVED_GIT_USER_EMAIL=""
  if [[ "$use_state" == true ]]; then
    RESOLVED_GIT_USER_NAME="$(state_get GIT_USER_NAME)"
    RESOLVED_GIT_USER_EMAIL="$(state_get GIT_USER_EMAIL)"
  fi
  if [[ "$RESOLVED_GIT_IDENTITY" == "true" ]]; then
    [[ -n "$RESOLVED_GIT_USER_NAME" ]] \
      || RESOLVED_GIT_USER_NAME="$(git config --global --includes --get user.name 2>/dev/null || true)"
    [[ -n "$RESOLVED_GIT_USER_EMAIL" ]] \
      || RESOLVED_GIT_USER_EMAIL="$(git config --global --includes --get user.email 2>/dev/null || true)"
  fi

  for component in HOSTNAME DOCK DESKTOP DEFAULT_APPS MENU_BAR MOUSE POWER FINDER SCREENSHOTS TOUCH_ID; do
    value=""
    [[ "$use_state" == true ]] && value="$(state_get "MACOS_${component}")"
    [[ -n "$value" ]] || value="$(get_profile_default "$profile" "MACOS_${component}")"
    typeset -g "RESOLVED_MACOS_${component}=${value:-false}"
  done
}

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
      --general)
        AUDIT_CONTEXT="general"
        AUDIT_PROFILE=""
        shift
        ;;
      --profile)
        [[ $# -ge 2 ]] || fail "--profile requires one of: minimal, home, work"
        case "$2" in
          minimal|home|work) ;;
          *) fail "Unknown audit profile: $2 (use: minimal, home, work)" ;;
        esac
        AUDIT_CONTEXT="profile"
        AUDIT_PROFILE="$2"
        shift 2
        ;;
      --expect-state)
        AUDIT_CONTEXT="state"
        AUDIT_PROFILE=""
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
  --general            Inventory current machine state without profile drift
  --profile <name>     Compare with minimal, home, or work profile defaults
  --expect-state       Compare with the exact last resolved bootstrap plan
  --section <name>     Audit only a specific section:
                         tools    - Full package catalogue, managers, runtimes
                         shell    - Shell config ownership and /etc/shells
                         configs  - Dotfiles, state file, mise config, certs
                         personal - Current managed state, then bootstrap drift
                         all      - Everything (default)
  --json               Output results as JSON (machine-readable)
  --non-interactive    Suppress gum-styled output
  -h, --help           Show this help text

The default is a general current-state inventory. `--profile` adds drift against
that profile's defaults; `--expect-state` uses the exact saved, editable plan.
The audit is read-only and never installs, writes, repairs, arms an authenticated
restart, or restarts the Mac.
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
    local mise_tools_json="{}" mise_tool_counts="" mise_missing=""
    mise_tools_json="$(bootstrap_mise ls --json 2>/dev/null || printf '{}')"
    mise_tool_counts="$(printf '%s\n' "$mise_tools_json" | jq -r '
      [to_entries[].value[]?] as $tools
      | [($tools | map(select(.installed == true)) | length), ($tools | length)] | @tsv
    ' 2>/dev/null || true)"
    if [[ -n "$mise_tool_counts" ]]; then
      local installed_tools total_tools
      IFS=$'\t' read -r installed_tools total_tools <<< "$mise_tool_counts"
      _inventory_line "  Configured tools:" "$installed_tools/$total_tools installed"
      mise_missing="$(printf '%s\n' "$mise_tools_json" | jq -r '
        to_entries[] as $tool | $tool.value[]? | select(.installed != true)
        | "\($tool.key)@\(.version)"
      ')"
      while IFS= read -r tool; do
        [[ -n "$tool" ]] && _inventory_line "    Missing:" "$tool"
      done <<< "$mise_missing"
    else
      _inventory_line "  Configured tools:" "could not read status"
    fi
  else
    _inventory_line "Mise:" "NOT INSTALLED"
  fi

  # The complete declarative package catalogue, not a hand-picked sample.
  local package_counts="" package_missing="" installed_count=0 total_count=0 missing_count=0
  package_counts="$(bootstrap_package_counts 2>/dev/null || true)"
  if [[ -n "$package_counts" ]]; then
    IFS=$'\t' read -r installed_count total_count missing_count <<< "$package_counts"
    _inventory_line "Declarative packages:" "$installed_count/$total_count installed"
    local package_status_json="" package version state
    package_status_json="$(bootstrap_package_status_json)"
    while IFS=$'\t' read -r package version state; do
      [[ -n "$package" ]] && _inventory_line "  $package:" "${version:-none} ($state)"
    done <<< "$(printf '%s\n' "$package_status_json" | jq -r '
      to_entries[] as $manager
      | $manager.value.packages[]?
      | [$manager.key + ":" + .package, (.installed_version // "none"), .state]
      | @tsv
    ')"
    package_missing="$(bootstrap_package_missing_lines 2>/dev/null || true)"
    if [[ -n "$package_missing" ]]; then
      while IFS=$'\t' read -r package state; do
        [[ -n "$package" ]] && _inventory_line "  Missing:" "$package ($state)"
      done <<< "$package_missing"
    fi
  else
    _inventory_line "Declarative packages:" "not discoverable from the active mise config"
  fi

  # Additional tools (not in foundation but expected after personal layer)
  local extra_tools=(mise gum gcloud tmux nvim fish lazygit)
  for tool in "${extra_tools[@]}"; do
    local tool_path=""
    tool_path="$(audit_tool_path "$tool" || true)"
    if [[ -n "$tool_path" ]]; then
      local ver=""
      case "$tool" in
        fish)    ver="$("$tool_path" --version 2>/dev/null | head -1)" ;;
        gum)     ver="$("$tool_path" --version 2>/dev/null | head -1)" ;;
        gcloud)  ver="$("$tool_path" version 2>/dev/null | head -1)" ;;
        mise)    ver="$("$tool_path" --version 2>/dev/null | head -1)" ;;
        tmux)    ver="$("$tool_path" -V 2>/dev/null)" ;;
        nvim)    ver="$("$tool_path" --version 2>/dev/null | head -1)" ;;
        lazygit) ver="$("$tool_path" --version 2>/dev/null | head -1)" ;;
      esac
      _inventory_line "$tool:" "${ver:-installed} ($tool_path)"
    else
      _inventory_line "$tool:" "not installed"
    fi
  done

  echo ""
}


# audit_shell -- Audit shell configuration state
#
# What: Checks current login shell, shell binaries, /etc/shells registration,
#       and shell configuration ownership.
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

  # Shell configuration ownership. The marker-delimited foundation blocks are
  # only fallbacks for a bootstrap without the personal dotfiles layer.
  local zsh_config_mode fish_config_mode
  zsh_config_mode="$(detect_zsh_config_mode)"
  fish_config_mode="$(detect_fish_config_mode)"

  case "$zsh_config_mode" in
    dotfiles)
      _inventory_line "Zsh configuration:" "managed by dotfiles (.zprofile + .zshrc)"
      ;;
    fallback)
      _inventory_line "Zsh configuration:" "foundation fallback block"
      ;;
    *)
      _inventory_line "Zsh configuration:" "not configured"
      ;;
  esac

  case "$fish_config_mode" in
    dotfiles)
      _inventory_line "Fish configuration:" "managed by dotfiles → $(/usr/bin/readlink "$HOME/.config/fish" 2>/dev/null || printf '%s' "$DOTFILES_DIR/fish")"
      ;;
    fallback)
      _inventory_line "Fish configuration:" "foundation fallback block"
      ;;
    *)
      _inventory_line "Fish configuration:" "not configured"
      ;;
  esac

  # Fisher may be a user function or a package-manager vendor function. Inspect
  # both locations without starting Fish: launching it can write universal
  # variable state beneath the managed ~/.config/fish symlink.
  local fisher_path="" fisher_version=""
  local fisher_candidate
  for fisher_candidate in \
    "$HOME/.config/fish/functions/fisher.fish" \
    "/opt/homebrew/share/fish/vendor_functions.d/fisher.fish" \
    "/usr/local/share/fish/vendor_functions.d/fisher.fish" \
    "$HOME/.local/share/fish/vendor_functions.d/fisher.fish" \
    "/usr/share/fish/vendor_functions.d/fisher.fish"; do
    if [[ -f "$fisher_candidate" ]]; then
      fisher_path="$fisher_candidate"
      break
    fi
  done
  if [[ -n "$fisher_path" ]]; then
    if command_exists brew; then
      fisher_version="$(brew list --versions fisher 2>/dev/null | awk '{print $2}' | head -1)"
    fi
    _inventory_line "Fisher:" "${fisher_version:+$fisher_version }installed ($fisher_path)"
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
    branch="$(bootstrap_git -C "$DOTFILES_DIR" branch --show-current 2>/dev/null || echo "unknown")"
    _inventory_line "  Branch:" "$branch"
    local status_count
    status_count="$(bootstrap_git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$status_count" -eq 0 ]]; then
      _inventory_line "  Working tree:" "clean"
    else
      _inventory_line "  Working tree:" "$status_count uncommitted changes"
    fi
    local remote_url
    remote_url="$(bootstrap_git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || echo "none")"
    _inventory_line "  Remote:" "$remote_url"
  else
    _inventory_line "Dotfiles repo:" "NOT FOUND at $DOTFILES_DIR"
  fi

  # State file
  if [[ -f "$STATE_FILE_PATH" ]]; then
    _inventory_line "State file:" "present at $STATE_FILE_PATH"
    # Use the state reader so shell-escaped adopter values render normally.
    local key val
    local -a state_keys
    state_keys=(
      DEVICE_PROFILE PREFERRED_SHELL DEVICE_NAME
      ENABLE_PACKAGES ENABLE_APPLICATIONS ENABLE_MISE_TOOLS ENABLE_DOTFILES
      ENABLE_CODE_DIRECTORY ENABLE_DOWNLOADS_LINK ENABLE_GIT_IDENTITY
      ENABLE_MACOS_DEFAULTS ENABLE_REMOTE_ACCESS ENABLE_ROSETTA
      ENABLE_SHELL_DEFAULT ENABLE_ZSCALER
      MACOS_HOSTNAME MACOS_DOCK MACOS_DESKTOP MACOS_DEFAULT_APPS
      MACOS_MENU_BAR MACOS_MOUSE MACOS_POWER MACOS_FINDER
      MACOS_SCREENSHOTS MACOS_TOUCH_ID
    )
    for key in "${state_keys[@]}"; do
      val="$(state_get "$key")"
      [[ -n "$val" ]] && _inventory_line "  $key:" "$val"
    done
    local missing_state_keys="" missing_state_count=0
    missing_state_keys="$(state_missing_keys)"
    if [[ -z "$missing_state_keys" ]]; then
      _inventory_line "  State schema:" "current ($(bootstrap_state_keys | wc -l | tr -d ' ') keys)"
    else
      missing_state_count="$(printf '%s\n' "$missing_state_keys" | sed '/^$/d' | wc -l | tr -d ' ')"
      _inventory_line "  State schema:" "incomplete ($missing_state_count current keys absent)"
      while IFS= read -r key; do
        [[ -n "$key" ]] && _inventory_line "    Missing key:" "$key"
      done <<< "$missing_state_keys"
    fi
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
    _inventory_line "  Permissions:" "$(stat -f '%Sp (%Lp)' "$MISE_ENV_PATH" 2>/dev/null || echo unknown)"
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


# audit_personal -- Audit personal layer state (mise dotfiles, brew bundle, defaults)
#
# What: Checks mise dotfiles status, brew bundle satisfaction, and whether
#       macOS defaults have been applied.
# Checks: mise dotfiles status, brew bundle check, defaults read.
# Gates: None.
# Side effects: Writes to stdout only.
# Idempotency: Pure detection.
audit_personal() {
  note "── Personal Layer ──"
  echo ""

  if [[ "$AUDIT_CONTEXT" == "profile" ]]; then
    _inventory_line "Comparison context:" "$RESOLVED_PROFILE profile defaults"
  elif [[ "$AUDIT_CONTEXT" == "state" ]]; then
    _inventory_line "Comparison context:" "$RESOLVED_PROFILE profile plus saved customisations"
  else
    _inventory_line "Comparison context:" "general inventory (no bootstrap drift)"
  fi
  if [[ "$AUDIT_CONTEXT" != "general" ]]; then
    _inventory_line "  Expected catalogues:" "packages=$RESOLVED_PACKAGES applications=$RESOLVED_APPLICATIONS mise-tools=$RESOLVED_MISE_TOOLS dotfiles=$RESOLVED_DOTFILES"
    _inventory_line "  Expected home/system:" "code=$RESOLVED_CODE_DIRECTORY downloads-link=$RESOLVED_DOWNLOADS_LINK defaults=$RESOLVED_MACOS_DEFAULTS remote-access=$RESOLVED_REMOTE_ACCESS"
  fi

  # mise dotfiles
  if command_exists mise; then
    local dotfiles_json="" dotfiles_counts=""
    dotfiles_json="$(bootstrap_mise dotfiles status --json 2>/dev/null || true)"
    dotfiles_counts="$(printf '%s\n' "$dotfiles_json" | jq -r '
      [.files[], .edits[]?] as $items
      | [($items | map(select(.state == "applied")) | length), ($items | length)]
      | @tsv
    ' 2>/dev/null || true)"
    if [[ -n "$dotfiles_counts" ]]; then
      local applied_count total_count target state
      IFS=$'\t' read -r applied_count total_count <<< "$dotfiles_counts"
      _inventory_line "Mise dotfiles:" "$applied_count/$total_count applied"
      while IFS=$'\t' read -r target state; do
        [[ -n "$target" ]] && _inventory_line "  Drift:" "$target ($state)"
      done <<< "$(printf '%s\n' "$dotfiles_json" | jq -r '
        [.files[], .edits[]?][] | select(.state != "applied") | "\(.target)\t\(.state)"
      ')"
    else
      _inventory_line "Mise dotfiles:" "could not read status"
    fi
  else
    _inventory_line "Mise dotfiles:" "not installed"
  fi

  # Brew bundle check
  local brewfile="$DOTFILES_DIR/brew/Brewfile"
  if [[ -f "$brewfile" ]] && command_exists brew; then
    _inventory_line "Brewfile:" "present"
    local bundle_check
    bundle_check="$(HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1 \
      brew bundle check --verbose --file="$brewfile" 2>&1)" && {
      _inventory_line "  Bundle status:" "satisfied"
    } || {
      local missing_count missing_entries
      missing_entries="$(printf '%s\n' "$bundle_check" | sed -n 's/^→ //p')"
      missing_count="$(printf '%s\n' "$missing_entries" | sed '/^$/d' | wc -l | tr -d ' ')"
      _inventory_line "  Bundle status:" "NOT satisfied ($missing_count missing or outdated)"
      while IFS= read -r line; do
        [[ -n "$line" ]] && _inventory_line "    Drift:" "$line"
      done <<< "$missing_entries"
      if [[ -z "$missing_entries" ]]; then
        _inventory_line "    Error:" "$(printf '%s\n' "$bundle_check" | tail -1)"
      fi
    }
  else
    _inventory_line "Brewfile:" "not found or brew not installed"
  fi

  # Chrome is a vendor-self-updating cask. Confirm both the expected Google
  # signing identity and Gatekeeper acceptance whenever quarantine is present.
  local chrome_app="/Applications/Google Chrome.app"
  if [[ -d "$chrome_app" ]]; then
    local chrome_signing="" chrome_quarantine_count="0"
    chrome_signing="$(/usr/bin/codesign -dv --verbose=4 "$chrome_app" 2>&1 || true)"
    chrome_quarantine_count="$(/usr/bin/xattr -lr "$chrome_app" 2>/dev/null \
      | grep -c 'com.apple.quarantine:' || true)"
    if ! /usr/bin/codesign --verify --deep --strict "$chrome_app" >/dev/null 2>&1; then
      _inventory_line "Google Chrome:" "INVALID code signature"
    elif ! printf '%s\n' "$chrome_signing" | grep -qx 'Identifier=com.google.Chrome' \
      || ! printf '%s\n' "$chrome_signing" | grep -qx 'TeamIdentifier=EQHXZ8M8AV'; then
      _inventory_line "Google Chrome:" "unexpected signing identity"
    elif [[ "$chrome_quarantine_count" -gt 0 ]]; then
      local chrome_assessment=""
      if chrome_assessment="$(/usr/sbin/spctl --assess --type execute --verbose=4 \
        "$chrome_app" 2>&1)"; then
        _inventory_line "Google Chrome:" "Google signature valid; Gatekeeper accepted"
      else
        _inventory_line "Google Chrome:" "Gatekeeper assessment FAILED — $(printf '%s\n' "$chrome_assessment" | sed '/^$/d' | tail -1)"
      fi
    else
      _inventory_line "Google Chrome:" "Google signature valid; quarantine cleared"
    fi
  else
    _inventory_line "Google Chrome:" "not installed"
  fi

  # Key config file symlinks
  _check_config_link() {
    local path="$1" label="$2" expected="$3"
    if [[ -L "$path" ]]; then
      local target=""
      target="$(/usr/bin/readlink "$path" 2>/dev/null || true)"
      [[ -z "$target" ]] && target="unknown"
      if [[ "$path" -ef "$expected" ]]; then
        _inventory_line "$label:" "correct symlink → $expected"
      else
        _inventory_line "$label:" "WRONG symlink → $target (expected $expected)"
      fi
    elif [[ -e "$path" ]]; then
      _inventory_line "$label:" "WRONG type — present but not a symlink (expected $expected)"
    else
      _inventory_line "$label:" "MISSING — expected symlink → $expected"
    fi
  }
  local git_config_path="$HOME/.gitconfig"
  local git_config_mode="absent"
  if [[ -L "$git_config_path" ]]; then
    local git_config_target=""
    git_config_target="$(/usr/bin/readlink "$git_config_path" 2>/dev/null || true)"
    if [[ -e "$git_config_path" ]]; then
      git_config_mode="symlink"
      _inventory_line "Git config:" "valid symlink → ${git_config_target:-unknown}"
    else
      git_config_mode="broken symlink"
      _inventory_line "Git config:" "BROKEN symlink → ${git_config_target:-unknown}"
    fi
  elif [[ -f "$git_config_path" ]]; then
    if grep -Fqx '# Generated by benjaminwestern/dotfiles bootstrap' \
      "$git_config_path" 2>/dev/null; then
      git_config_mode="bootstrap-generated file"
    else
      git_config_mode="existing user file"
    fi
    _inventory_line "Git config:" "$git_config_mode"
  elif [[ -e "$git_config_path" ]]; then
    git_config_mode="wrong type"
    _inventory_line "Git config:" "WRONG type — expected a file or symlink"
  else
    _inventory_line "Git config:" "absent"
  fi
  _check_config_link "$HOME/.config/nvim"            "Neovim config"  "$DOTFILES_DIR/nvim"
  _check_config_link "$HOME/.tmux.conf"              "Tmux config"    "$DOTFILES_DIR/tmux/.tmux.conf"
  _check_config_link "$HOME/.config/fish"            "Fish config"    "$DOTFILES_DIR/fish"
  _check_config_link "$HOME/.config/ghostty/config"  "Ghostty config" "$DOTFILES_DIR/ghostty/config"
  _check_config_link "$HOME/.ssh/config"             "SSH config"     "$DOTFILES_DIR/ssh/config"

  _inventory_line "macOS account:" "$(id -un) (bootstrap never renames it)"
  _inventory_line "ComputerName:" "$(scutil --get ComputerName 2>/dev/null || echo unset)"
  _inventory_line "LocalHostName:" "$(scutil --get LocalHostName 2>/dev/null || echo unset)"
  _inventory_line "HostName:" "$(scutil --get HostName 2>/dev/null || echo unset)"

  local git_author_name git_author_email git_identity_mode="$git_config_mode"
  git_author_name="$(git config --global --includes --get user.name 2>/dev/null || true)"
  git_author_email="$(git config --global --includes --get user.email 2>/dev/null || true)"
  [[ -f "$HOME/.config/git/bootstrap-user.inc" ]] \
    && git_identity_mode="$git_config_mode + machine-local include"
  if [[ -n "$git_author_name" || -n "$git_author_email" ]]; then
    _inventory_line "Git author:" "${git_author_name:-unset} <${git_author_email:-unset}> ($git_identity_mode)"
  else
    _inventory_line "Git author:" "unset"
  fi
  local identity_file="$HOME/.config/git/bootstrap-user.inc"
  local identity_name="" identity_email="" identity_mode="absent" identity_include=false
  identity_name="$(git config --file "$identity_file" --get user.name 2>/dev/null || true)"
  identity_email="$(git config --file "$identity_file" --get user.email 2>/dev/null || true)"
  [[ -f "$identity_file" ]] && identity_mode="$(stat -f '%Lp' "$identity_file" 2>/dev/null || printf unknown)"
  if [[ -f "$git_config_path" ]] \
    && git config --file "$git_config_path" --get-all include.path 2>/dev/null \
      | grep -Fxq '~/.config/git/bootstrap-user.inc'; then
    identity_include=true
  fi
  if [[ -f "$identity_file" ]]; then
    _inventory_line "Identity include:" "${identity_name:-unset} <${identity_email:-unset}> (mode $identity_mode; linked=$identity_include)"
  else
    _inventory_line "Identity include:" "not used"
  fi
  if [[ "$AUDIT_CONTEXT" == "general" ]]; then
    :
  elif [[ "${RESOLVED_GIT_IDENTITY:-false}" != "true" ]]; then
    _inventory_line "  Git identity drift:" "comparison disabled by bootstrap profile"
  elif [[ "$AUDIT_CONTEXT" == "profile" ]]; then
    _inventory_line "  Git identity drift:" "name and email are adopter inputs; use saved-plan audit for exact comparison"
  else
    local identity_drift=()
    [[ "$git_config_mode" != "absent" && "$git_config_mode" != "broken symlink" \
      && "$git_config_mode" != "wrong type" ]] || identity_drift+=("Git config")
    [[ "$git_author_name" == "$RESOLVED_GIT_USER_NAME" ]] || identity_drift+=("effective name")
    [[ "$git_author_email" == "$RESOLVED_GIT_USER_EMAIL" ]] || identity_drift+=("effective email")
    if [[ ${#identity_drift[@]} -eq 0 ]]; then
      _inventory_line "  Git identity drift:" "none"
    else
      _inventory_line "  Git identity drift:" "${(j:, :)identity_drift}"
    fi
  fi

  local launchservices_json="{}"
  launchservices_json="$(audit_launchservices_handlers_json)"
  local chrome_default_browser chrome_pdf_viewer
  chrome_default_browser="$(printf '%s\n' "$launchservices_json" | jq -r '
    ([.http, .https, .html, .xhtml]
      | map((. // "") | ascii_downcase)
      | all(. == "com.google.chrome"))
  ' 2>/dev/null || echo false)"
  chrome_pdf_viewer="$(printf '%s\n' "$launchservices_json" | jq -r '
    (((.pdf // "") | ascii_downcase) == "com.google.chrome")
  ' 2>/dev/null || echo false)"
  if [[ "$chrome_default_browser" == "true" ]]; then
    _inventory_line "Default browser:" "Google Chrome"
  else
    _inventory_line "Default browser:" "not fully assigned to Google Chrome"
  fi
  if [[ "$chrome_pdf_viewer" == "true" ]]; then
    _inventory_line "PDF viewer:" "Google Chrome"
  else
    _inventory_line "PDF viewer:" "not assigned to Google Chrome"
  fi

  local icloud_downloads="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Downloads"
  if [[ -L "$HOME/Downloads" ]] \
    && [[ "$(/usr/bin/readlink "$HOME/Downloads" 2>/dev/null || true)" == "$icloud_downloads" ]]; then
    _inventory_line "Downloads:" "symlink → iCloud Drive Downloads"
  elif [[ -L "$HOME/Downloads" ]]; then
    _inventory_line "Downloads:" "unexpected symlink → $(/usr/bin/readlink "$HOME/Downloads" 2>/dev/null || echo unknown)"
  elif [[ -d "$HOME/Downloads" ]]; then
    _inventory_line "Downloads:" "local directory (not linked to iCloud Drive)"
  else
    _inventory_line "Downloads:" "absent"
  fi

  if [[ -d "$HOME/code" ]]; then
    _inventory_line "Code directory:" "present at $HOME/code"
  elif [[ -e "$HOME/code" || -L "$HOME/code" ]]; then
    _inventory_line "Code directory:" "path exists but is not a directory"
  else
    _inventory_line "Code directory:" "absent"
  fi

  note "  Current bootstrap-managed macOS state:"
  local group label current
  while IFS=$'\t' read -r group label current; do
    [[ -n "$group" ]] && _inventory_line "  $group / $label:" "$current"
  done <<< "$(macos_defaults_current_lines)"

  if [[ "$AUDIT_CONTEXT" != "general" ]]; then
    note "  Drift from bootstrap profile (${RESOLVED_PROFILE}):"
    local defaults_drift="" expected drift_count=0
    defaults_drift="$(macos_defaults_drift_lines)"
    if [[ -z "$defaults_drift" ]]; then
      _inventory_line "  macOS preferences:" "none"
    else
      while IFS=$'\t' read -r group label current expected; do
        [[ -n "$group" ]] || continue
        _inventory_line "  $group / $label:" "$current → $expected"
        drift_count=$((drift_count + 1))
      done <<< "$defaults_drift"
      _inventory_line "  macOS preference drift:" "$drift_count setting(s)"
    fi
  fi

  # This is deliberately observational. `fdesetup authrestart` temporarily
  # stages a FileVault unlock key and initiates/schedules a restart, so the
  # audit must never invoke it. `supportsauthrestart` reports capability only.
  note "  Boot and remote reachability:"
  local filevault_status authrestart_support fde_handoff remote_overrides
  filevault_status="$(fdesetup status 2>/dev/null || echo unknown)"
  authrestart_support="$(fdesetup supportsauthrestart 2>/dev/null || echo false)"
  fde_handoff="$(defaults read /Library/Preferences/com.apple.loginwindow DisableFDEAutoLogin 2>/dev/null || echo 0)"
  remote_overrides="$(launchctl print-disabled system 2>/dev/null || true)"
  _inventory_line "  FileVault:" "$filevault_status"
  _inventory_line "  Authenticated restart:" "$authrestart_support"
  if [[ "$fde_handoff" == "1" ]]; then
    _inventory_line "  FileVault login handoff:" "disabled"
  else
    _inventory_line "  FileVault login handoff:" "enabled"
  fi
  note "  Current remote-access state:"
  while IFS=$'\t' read -r group label current; do
    [[ -n "$group" ]] && _inventory_line "  $group / $label:" "$current"
  done <<< "$(remote_access_current_lines)"
  if [[ "$AUDIT_CONTEXT" != "general" ]]; then
    local access_drift=""
    access_drift="$(remote_access_drift_lines)"
    if [[ "${RESOLVED_REMOTE_ACCESS:-false}" != "true" ]]; then
      _inventory_line "  Remote-access drift:" "comparison disabled by resolved plan"
    elif [[ -z "$access_drift" ]]; then
      _inventory_line "  Remote-access drift:" "none"
    else
      while IFS=$'\t' read -r group label current expected; do
        [[ -n "$group" ]] && _inventory_line "  Drift $group / $label:" "$current → $expected"
      done <<< "$access_drift"
    fi
  fi
  local power_key
  for power_key in autorestart womp tcpkeepalive sleep; do
    local power_value=""
    power_value="$(audit_pmset_ac_value "$power_key")"
    _inventory_line "  AC $power_key:" "${power_value:-unset}"
  done

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
  local zsh_config_mode="" fish_config_mode=""

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
  zsh_config_mode="$(detect_zsh_config_mode)"
  fish_config_mode="$(detect_fish_config_mode)"

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

  local launchservices_json="{}"
  launchservices_json="$(audit_launchservices_handlers_json)"
  local chrome_default_browser chrome_pdf_viewer
  chrome_default_browser="$(printf '%s\n' "$launchservices_json" | jq -r '
    ([.http, .https, .html, .xhtml]
      | map((. // "") | ascii_downcase)
      | all(. == "com.google.chrome"))
  ' 2>/dev/null || echo false)"
  chrome_pdf_viewer="$(printf '%s\n' "$launchservices_json" | jq -r '
    (((.pdf // "") | ascii_downcase) == "com.google.chrome")
  ' 2>/dev/null || echo false)"

  local filevault_on authrestart_supported fde_handoff_enabled
  local remote_login_enabled screen_sharing_enabled remote_overrides
  filevault_on="$(fdesetup status 2>/dev/null | grep -q 'FileVault is On' && echo true || echo false)"
  authrestart_supported="$(fdesetup supportsauthrestart 2>/dev/null | grep -qx true && echo true || echo false)"
  fde_handoff_enabled="$([[ "$(defaults read /Library/Preferences/com.apple.loginwindow DisableFDEAutoLogin 2>/dev/null || echo 0)" != "1" ]] && echo true || echo false)"
  remote_overrides="$(launchctl print-disabled system 2>/dev/null || true)"
  remote_login_enabled="$(printf '%s\n' "$remote_overrides" | grep -Eq '"com\.openssh\.sshd"[[:space:]]*=>[[:space:]]*(enabled|false)' && echo true || echo false)"
  screen_sharing_enabled="$(printf '%s\n' "$remote_overrides" | grep -Eq '"com\.apple\.screensharing"[[:space:]]*=>[[:space:]]*(enabled|false)' && echo true || echo false)"

  local pkg_json="{}" dotfiles_applied=false
  pkg_json="$(bootstrap_package_status_json 2>/dev/null || printf '{}')"
  if command_exists mise; then
    dotfiles_applied="$(bootstrap_mise dotfiles status --json 2>/dev/null | jq -r '
      [.files[], .edits[]?] | all(.state == "applied")
    ' 2>/dev/null || printf false)"
  fi

  local current_macos_json='[]' macos_drift_json='[]'
  local current_remote_json='[]' remote_drift_json='[]' state_missing_json='[]'
  current_macos_json="$(macos_defaults_current_lines | jq -Rn '
    [inputs | split("\t") | select(length >= 3) | {group: .[0], setting: .[1], current: .[2]}]
  ')"
  current_remote_json="$(remote_access_current_lines | jq -Rn '
    [inputs | split("\t") | select(length >= 3) | {group: .[0], setting: .[1], current: .[2]}]
  ')"
  if [[ "$AUDIT_CONTEXT" != "general" ]]; then
    macos_drift_json="$(macos_defaults_drift_lines | jq -Rn '
      [inputs | split("\t") | select(length >= 4) | {group: .[0], setting: .[1], current: .[2], expected: .[3]}]
    ')"
    remote_drift_json="$(remote_access_drift_lines | jq -Rn '
      [inputs | split("\t") | select(length >= 4) | {group: .[0], setting: .[1], current: .[2], expected: .[3]}]
    ')"
  fi
  state_missing_json="$(state_missing_keys | jq -Rn '[inputs | select(length > 0)]')"

  local drift_profile_json="null"
  [[ "$AUDIT_CONTEXT" != "general" ]] && drift_profile_json="\"$RESOLVED_PROFILE\""

  cat <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "audit_context": "$AUDIT_CONTEXT",
  "system": {
    "architecture": "$arch",
    "macos_version": "$macos_version",
    "rosetta": $([[ "$rosetta" == "n/a" ]] && echo "null" || echo "$rosetta")
  },
  "boot": {
    "filevault": $filevault_on,
    "authenticated_restart_supported": $authrestart_supported,
    "filevault_login_handoff": $fde_handoff_enabled,
    "remote_login_enabled": $remote_login_enabled,
    "screen_sharing_enabled": $screen_sharing_enabled,
    "ac_autorestart": "$(audit_pmset_ac_value autorestart)",
    "ac_wake_on_network": "$(audit_pmset_ac_value womp)",
    "ac_tcp_keepalive": "$(audit_pmset_ac_value tcpkeepalive)",
    "ac_system_sleep": "$(audit_pmset_ac_value sleep)"
  },
  "shell": {
    "current": "$shell_current",
    "fish_binary": "$fish_bin",
    "fish_in_etc_shells": $(grep -qx "/opt/homebrew/bin/fish" /etc/shells 2>/dev/null && echo "true" || echo "false"),
    "zsh_configuration": "$zsh_config_mode",
    "fish_configuration": "$fish_config_mode",
    "zsh_configured": $([[ "$zsh_config_mode" != "none" ]] && echo "true" || echo "false"),
    "fish_configured": $([[ "$fish_config_mode" != "none" ]] && echo "true" || echo "false")
  },
  "tools": {
    "homebrew": "${homebrew_version:-null}",
    "mise": "${mise_version:-null}",
    "declarative_packages": $pkg_json,
    "mise_dotfiles_applied": $dotfiles_applied,
    "gum": $(audit_tool_path gum >/dev/null 2>&1 && echo "true" || echo "false")
  },
  "configs": {
    "dotfiles_repo": $dotfiles,
    "state_file": $state_file,
    "mise_config": $([[ -f "$MISE_CONFIG_PATH" ]] && echo "true" || echo "false"),
    "mise_env": $([[ -f "$MISE_ENV_PATH" ]] && echo "true" || echo "false"),
    "mise_env_mode": "$([[ -f "$MISE_ENV_PATH" ]] && stat -f '%Lp' "$MISE_ENV_PATH" 2>/dev/null || echo "")",
    "golden_ca_bundle": $([[ -f "$GOLDEN_BUNDLE_PATH" ]] && echo "true" || echo "false"),
    "code_directory": $([[ -d "$HOME/code" ]] && echo "true" || echo "false"),
    "downloads_icloud_link": $([[ -L "$HOME/Downloads" ]] && [[ "$(/usr/bin/readlink "$HOME/Downloads" 2>/dev/null || true)" == "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Downloads" ]] && echo "true" || echo "false"),
    "chrome_default_browser": $chrome_default_browser,
    "chrome_pdf_viewer": $chrome_pdf_viewer,
    "state_missing_keys": $state_missing_json
  },
  "current": {
    "macos_preferences": $current_macos_json,
    "remote_access": $current_remote_json
  },
  "drift": {
    "profile": $drift_profile_json,
    "macos_preferences": $macos_drift_json,
    "remote_access": $remote_drift_json
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
  audit_load_expectations

  if [[ "$AUDIT_JSON" -eq 1 ]]; then
    audit_json
    return 0
  fi

  local context_label="General current-machine inventory"
  [[ "$AUDIT_CONTEXT" == "profile" ]] \
    && context_label="Comparison with $RESOLVED_PROFILE profile defaults"
  [[ "$AUDIT_CONTEXT" == "state" ]] \
    && context_label="Comparison with saved $RESOLVED_PROFILE bootstrap plan"
  panel "macOS Machine Audit\n$(date '+%Y-%m-%d %H:%M:%S')\n$context_label\nRead-only — no changes will be made"

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
