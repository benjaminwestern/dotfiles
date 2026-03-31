#!/bin/zsh
# =============================================================================
# common.zsh -- Shared library for macOS bootstrap scripts
#
# Sourced by both foundation-macos.zsh and personal-bootstrap-macos.zsh.
# Pure zsh. Compatible with `set -euo pipefail`.
#
# Sections:
#   1. Constants
#   2. Core Utilities
#   3. Status Output
#   4. Gum / UI
#   5. State File
#   6. Resolution
#   7. Managed Block Writer
# =============================================================================

# Guard against double-sourcing. If _COMMON_ZSH_LOADED is already set, return
# immediately so that functions and counters are not redefined.
if [[ "${_COMMON_ZSH_LOADED:-0}" -eq 1 ]]; then
  return 0
fi
typeset -g _COMMON_ZSH_LOADED=1

# =============================================================================
# SECTION 1: CONSTANTS
# =============================================================================

# -- State file path ----------------------------------------------------------
# The state file is a simple KEY=VALUE env file that persists resolved settings
# across bootstrap runs. It lives outside the dotfiles repo so it is specific
# to the current machine.
typeset -g STATE_FILE_PATH="$HOME/.config/dotfiles/state.env"

# -- Status symbols -----------------------------------------------------------
# Unicode glyphs used by the status_* family of functions. Defined once here so
# every call site stays consistent and the symbols are easy to change.
typeset -g STATUS_SYM_PASS="\u2713"   # check mark
typeset -g STATUS_SYM_FAIL="\u2717"   # ballot x
typeset -g STATUS_SYM_SKIP="\u25CB"   # white circle

# -- Dracula palette ----------------------------------------------------------
# Canonical hex values from https://draculatheme.com/contribute. Used by
# setup_gum_theme and available to any caller that sources this library.
typeset -g DRACULA_BG="#282a36"
typeset -g DRACULA_FG="#f8f8f2"
typeset -g DRACULA_SELECTION="#44475a"
typeset -g DRACULA_COMMENT="#6272a4"
typeset -g DRACULA_CYAN="#8be9fd"
typeset -g DRACULA_GREEN="#50fa7b"
typeset -g DRACULA_ORANGE="#ffb86c"
typeset -g DRACULA_PINK="#ff79c6"
typeset -g DRACULA_PURPLE="#bd93f9"
typeset -g DRACULA_RED="#ff5555"
typeset -g DRACULA_YELLOW="#f1fa8c"

# -- Managed block markers ----------------------------------------------------
# Delimiters injected into config files by write_managed_block(). Each pair
# fences a block of content that the bootstrap owns and may overwrite.
typeset -g PROFILE_BEGIN="# >>> foundation-bootstrap >>>"
typeset -g PROFILE_END="# <<< foundation-bootstrap <<<"
typeset -g MISE_BEGIN="# >>> foundation-seed >>>"
typeset -g MISE_END="# <<< foundation-seed <<<"
typeset -g ZSCALER_ENV_BEGIN="# >>> zscaler-bootstrap >>>"
typeset -g ZSCALER_ENV_END="# <<< zscaler-bootstrap <<<"

# -- NON_INTERACTIVE flag -----------------------------------------------------
# When set to "1", all interactive prompts are suppressed. Callers can export
# this before sourcing the library, or pass it on the command line.
typeset -g NON_INTERACTIVE="${NON_INTERACTIVE:-0}"

# -- DRY_RUN flag --------------------------------------------------------------
# When set to "1", the bootstrap runs the entire resolution, pre-flight, and
# validation pipeline but NEVER executes any destructive command. Instead it
# prints what WOULD happen. This lets you verify the full plan on a real machine
# without changing anything.
#
# What counts as "destructive":
#   - Installing software (brew install, scoop install, mise install, softwareupdate)
#   - Writing or modifying files (write_managed_block, Set-Content, tee, etc.)
#   - Changing system state (chsh, sudo, defaults write, killall, git config --global)
#   - Network fetches that trigger installs (curl | bash, Homebrew installer)
#
# What still runs in dry-run mode:
#   - Pre-flight inventory (read-only detection)
#   - Flag resolution (reads state file, prompts user)
#   - Validation checks (command_exists, file existence, version queries)
#   - Status output (shows what would pass/fix/skip/fail)
#   - State file writes (so subsequent dry-runs remember the resolved flags)
typeset -g DRY_RUN="${DRY_RUN:-0}"

# dry_run_active -- Check whether dry-run mode is enabled
#
# Checks: DRY_RUN global variable.
# Gates: None.
# Side effects: None.
# Idempotency: Pure query.
#
# Returns:
#   0 if dry-run is active, 1 otherwise.
dry_run_active() {
  [[ "$DRY_RUN" == "1" ]]
}

# dry_run_log -- Print a dry-run notice for a command that would be skipped
#
# Checks: None — always prints.
# Gates: Should only be called when dry_run_active is true.
# Side effects: Writes to stdout.
# Idempotency: Pure output.
#
# Arguments:
#   $1 -- Short label for the action (e.g. "brew install git")
dry_run_log() {
  printf "  \033[35m[dry-run]\033[0m would run: %s\n" "$1"
}

# run_or_dry -- Execute a command, or log it if dry-run is active
#
# What: The core dry-run gate. Every destructive command in the bootstrap should
#       be routed through this function. If DRY_RUN=1, the command is logged but
#       not executed. If DRY_RUN=0, the command runs normally.
# Why:  Centralises the dry-run check so individual functions don't need to
#       duplicate the if/else pattern. Ensures nothing slips through.
# Checks: DRY_RUN flag.
# Gates: None — delegates to the caller's judgement about what is destructive.
# Side effects: Either executes the command or prints what would have run.
# Idempotency: Depends on the underlying command.
#
# Arguments:
#   $@ -- The full command and its arguments.
#
# Returns:
#   0 in dry-run mode (simulates success).
#   The command's actual exit code in normal mode.
#
# Usage:
#   run_or_dry brew install git
#   run_or_dry sudo sh -c "echo /opt/homebrew/bin/fish >> /etc/shells"
#   run_or_dry chsh -s /opt/homebrew/bin/fish
run_or_dry() {
  if dry_run_active; then
    dry_run_log "$*"
    return 0
  fi
  "$@"
}


# =============================================================================
# SECTION 2: CORE UTILITIES
# =============================================================================

# command_exists -- Check whether a command is available on PATH
#
# Checks: Uses `command -v` which is a POSIX built-in and does not fork.
# Gates: None.
# Side effects: None.
# Idempotency: Pure query -- always safe to call.
#
# Arguments:
#   $1 -- The name of the command to look up.
#
# Returns:
#   0 if the command exists, 1 otherwise.
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# fail -- Print an error message to stderr and exit with code 1
#
# Checks: None.
# Gates: None.
# Side effects: Terminates the running script.
# Idempotency: N/A -- the process ends.
#
# Arguments:
#   $1 -- The error message to display.
fail() {
  printf '\033[31mERROR:\033[0m %s\n' "$1" >&2
  exit 1
}


# =============================================================================
# SECTION 2b: PRE-FLIGHT INVENTORY
# =============================================================================
#
# The pre-flight inventory runs BEFORE any changes are made. It snapshots every
# relevant tool, config, and system setting so the user can see what's already
# in place — and so the scripts can make smarter decisions about what to skip.
#
# The inventory is printed as a human-readable block and also populates global
# variables (PREFLIGHT_*) that subsequent ensure_* functions can reference.

# _inventory_line -- Print a single inventory row
#
# Checks: None — display only.
# Gates: None.
# Side effects: Writes to stdout.
# Idempotency: Pure output.
#
# Arguments:
#   $1 -- Label (left column)
#   $2 -- Value (right column)
_inventory_line() {
  printf "  %-30s %s\n" "$1" "$2"
}

# preflight_inventory -- Snapshot the current machine state
#
# What: Detects and prints the status of every tool, config, and system setting
#       that the bootstrap might touch. Populates PREFLIGHT_* global variables
#       so ensure_* functions can make informed decisions.
# Why:  Prevents blind re-installs, surfaces unexpected configurations, and
#       gives the user confidence about what the bootstrap will (and won't) do.
# Checks: command -v for tools, file existence for configs, /etc/shells, $SHELL,
#         uname -m, process checks.
# Gates: None — always runs.
# Side effects: Sets PREFLIGHT_* global variables. Writes to stdout.
# Idempotency: Pure detection — no system modifications.
preflight_inventory() {
  typeset -g PREFLIGHT_HOMEBREW=""
  typeset -g PREFLIGHT_HOMEBREW_VERSION=""
  typeset -g PREFLIGHT_BREW_PACKAGES_PRESENT=()
  typeset -g PREFLIGHT_BREW_PACKAGES_MISSING=()
  typeset -g PREFLIGHT_GUM=""
  typeset -g PREFLIGHT_MISE=""
  typeset -g PREFLIGHT_MISE_VERSION=""
  typeset -g PREFLIGHT_SHELL_CURRENT=""
  typeset -g PREFLIGHT_SHELL_FISH=""
  typeset -g PREFLIGHT_SHELL_ZSH=""
  typeset -g PREFLIGHT_FISH_IN_SHELLS=""
  typeset -g PREFLIGHT_ZSH_BREW_IN_SHELLS=""
  typeset -g PREFLIGHT_DOTFILES_DIR=""
  typeset -g PREFLIGHT_TUCKR=""
  typeset -g PREFLIGHT_STATE_FILE=""
  typeset -g PREFLIGHT_MISE_CONFIG=""
  typeset -g PREFLIGHT_ZSCALER=""
  typeset -g PREFLIGHT_ROSETTA=""
  typeset -g PREFLIGHT_ARCH=""
  typeset -g PREFLIGHT_PROFILE_BLOCK_ZSH=""
  typeset -g PREFLIGHT_PROFILE_BLOCK_FISH=""

  note "Pre-flight inventory — scanning what is already in place..."
  echo ""

  # -- Package managers --------------------------------------------------------
  if command_exists brew; then
    PREFLIGHT_HOMEBREW="installed"
    PREFLIGHT_HOMEBREW_VERSION="$(brew --version 2>/dev/null | head -1 || echo "unknown")"
  else
    PREFLIGHT_HOMEBREW="missing"
    PREFLIGHT_HOMEBREW_VERSION=""
  fi
  _inventory_line "Homebrew:" "${PREFLIGHT_HOMEBREW_VERSION:-not installed}"

  # -- Foundation packages (only check if brew exists) -------------------------
  if [[ "$PREFLIGHT_HOMEBREW" == "installed" ]] && (( ${+FOUNDATION_BREW_PACKAGES} )); then
    local pkg
    for pkg in "${FOUNDATION_BREW_PACKAGES[@]}"; do
      if brew list "$pkg" >/dev/null 2>&1; then
        PREFLIGHT_BREW_PACKAGES_PRESENT+=("$pkg")
      else
        PREFLIGHT_BREW_PACKAGES_MISSING+=("$pkg")
      fi
    done
    local total=${#FOUNDATION_BREW_PACKAGES[@]}
    local present=${#PREFLIGHT_BREW_PACKAGES_PRESENT[@]}
    _inventory_line "Foundation packages:" "${present}/${total} present"
    if [[ ${#PREFLIGHT_BREW_PACKAGES_MISSING[@]} -gt 0 ]]; then
      _inventory_line "  Missing:" "${PREFLIGHT_BREW_PACKAGES_MISSING[*]}"
    fi
  elif [[ "$PREFLIGHT_HOMEBREW" != "installed" ]]; then
    _inventory_line "Foundation packages:" "cannot check (brew not installed)"
  else
    _inventory_line "Foundation packages:" "skipped (package list not defined)"
  fi

  # -- Key tools ---------------------------------------------------------------
  # Mise can be installed via Homebrew or the shell installer. We track both
  # the presence and the install method so update_mise() knows which path to use.
  typeset -g PREFLIGHT_MISE_METHOD=""
  if command_exists mise; then
    PREFLIGHT_MISE="installed"
    PREFLIGHT_MISE_VERSION="$(mise --version 2>/dev/null || echo "unknown")"
    if command_exists brew && brew list mise >/dev/null 2>&1; then
      PREFLIGHT_MISE_METHOD="homebrew"
    elif [[ -x "$HOME/.local/bin/mise" ]]; then
      PREFLIGHT_MISE_METHOD="shell installer"
    else
      PREFLIGHT_MISE_METHOD="unknown"
    fi
  else
    PREFLIGHT_MISE="missing"
    PREFLIGHT_MISE_VERSION=""
    PREFLIGHT_MISE_METHOD=""
  fi
  if [[ -n "$PREFLIGHT_MISE_VERSION" ]]; then
    _inventory_line "Mise:" "$PREFLIGHT_MISE_VERSION ($PREFLIGHT_MISE_METHOD)"
  else
    _inventory_line "Mise:" "not installed"
  fi

  if command_exists gum; then
    PREFLIGHT_GUM="installed"
  else
    PREFLIGHT_GUM="missing"
  fi
  _inventory_line "Gum:" "$PREFLIGHT_GUM"

  if command_exists tuckr; then
    PREFLIGHT_TUCKR="installed"
  else
    PREFLIGHT_TUCKR="missing"
  fi
  _inventory_line "Tuckr:" "$PREFLIGHT_TUCKR"

  # -- Shell state -------------------------------------------------------------
  PREFLIGHT_SHELL_CURRENT="$SHELL"
  _inventory_line "Current login shell:" "$PREFLIGHT_SHELL_CURRENT"

  if [[ -x /opt/homebrew/bin/fish ]]; then
    PREFLIGHT_SHELL_FISH="/opt/homebrew/bin/fish"
  elif [[ -x /usr/local/bin/fish ]]; then
    PREFLIGHT_SHELL_FISH="/usr/local/bin/fish"
  else
    PREFLIGHT_SHELL_FISH="not installed"
  fi
  _inventory_line "Fish:" "$PREFLIGHT_SHELL_FISH"

  if [[ -x /opt/homebrew/bin/zsh ]]; then
    PREFLIGHT_SHELL_ZSH="/opt/homebrew/bin/zsh (brew)"
  else
    PREFLIGHT_SHELL_ZSH="/bin/zsh (system)"
  fi
  _inventory_line "Zsh:" "$PREFLIGHT_SHELL_ZSH"

  # Check /etc/shells for the preferred shells
  if grep -qx "/opt/homebrew/bin/fish" /etc/shells 2>/dev/null || grep -qx "/usr/local/bin/fish" /etc/shells 2>/dev/null; then
    PREFLIGHT_FISH_IN_SHELLS="yes"
  else
    PREFLIGHT_FISH_IN_SHELLS="no"
  fi
  _inventory_line "Fish in /etc/shells:" "$PREFLIGHT_FISH_IN_SHELLS"

  # -- Dotfiles and configs ----------------------------------------------------
  if [[ -d "${DOTFILES_DIR:-$HOME/.dotfiles}/.git" ]]; then
    PREFLIGHT_DOTFILES_DIR="present"
  else
    PREFLIGHT_DOTFILES_DIR="absent"
  fi
  _inventory_line "Dotfiles repo:" "$PREFLIGHT_DOTFILES_DIR"

  if [[ -f "$STATE_FILE_PATH" ]]; then
    PREFLIGHT_STATE_FILE="present"
  else
    PREFLIGHT_STATE_FILE="absent (first run)"
  fi
  _inventory_line "State file:" "$PREFLIGHT_STATE_FILE"

  if [[ -f "${HOME}/.config/mise/config.toml" ]]; then
    PREFLIGHT_MISE_CONFIG="present"
  else
    PREFLIGHT_MISE_CONFIG="absent"
  fi
  _inventory_line "Mise config:" "$PREFLIGHT_MISE_CONFIG"

  # -- Profile blocks ----------------------------------------------------------
  if [[ -f "$HOME/.zshrc" ]] && grep -qF "foundation-bootstrap" "$HOME/.zshrc" 2>/dev/null; then
    PREFLIGHT_PROFILE_BLOCK_ZSH="present"
  else
    PREFLIGHT_PROFILE_BLOCK_ZSH="absent"
  fi
  _inventory_line "Zsh profile block:" "$PREFLIGHT_PROFILE_BLOCK_ZSH"

  if [[ -f "$HOME/.config/fish/conf.d/00-foundation.fish" ]]; then
    PREFLIGHT_PROFILE_BLOCK_FISH="present"
  else
    PREFLIGHT_PROFILE_BLOCK_FISH="absent"
  fi
  _inventory_line "Fish profile block:" "$PREFLIGHT_PROFILE_BLOCK_FISH"

  # -- System state ------------------------------------------------------------
  PREFLIGHT_ARCH="$(uname -m)"
  _inventory_line "Architecture:" "$PREFLIGHT_ARCH"

  if [[ "$PREFLIGHT_ARCH" == "arm64" ]]; then
    if pgrep -q oahd 2>/dev/null; then
      PREFLIGHT_ROSETTA="installed"
    else
      PREFLIGHT_ROSETTA="not installed"
    fi
    _inventory_line "Rosetta 2:" "$PREFLIGHT_ROSETTA"
  else
    PREFLIGHT_ROSETTA="n/a"
    _inventory_line "Rosetta 2:" "not needed (Intel)"
  fi

  # -- Zscaler -----------------------------------------------------------------
  # Quick check: if certs dir and golden bundle already exist, note it.
  # Full Zscaler detection is expensive (TLS probe), so we just check artifacts.
  if [[ -f "${HOME}/certs/golden_pem.pem" ]]; then
    PREFLIGHT_ZSCALER="trust chain present"
  elif [[ -f "${HOME}/.config/mise/.env" ]] && grep -q "ZSCALER" "${HOME}/.config/mise/.env" 2>/dev/null; then
    PREFLIGHT_ZSCALER="env vars present (no bundle)"
  else
    PREFLIGHT_ZSCALER="not configured"
  fi
  _inventory_line "Zscaler trust:" "$PREFLIGHT_ZSCALER"

  echo ""
}


# =============================================================================
# SECTION 3: STATUS OUTPUT
# =============================================================================

# Global counters that track how many steps fell into each outcome. These are
# accumulated by the status_* functions and printed by status_summary.
typeset -g _STATUS_PASSED=0
typeset -g _STATUS_FIXED=0
typeset -g _STATUS_SKIPPED=0
typeset -g _STATUS_FAILED=0

# status_pass -- Record and display a passing (already-correct) step
#
# Checks: Nothing -- the caller has already verified the condition.
# Gates: None.
# Side effects: Increments _STATUS_PASSED. Writes to stdout.
# Idempotency: Safe to call multiple times; counter increments each time.
#
# Arguments:
#   $1 -- Short description of what was checked (max ~45 chars for alignment).
#   $2 -- (optional) Detail string shown in parentheses after the description.
#
# Output format (with gum):
#   Green styled "  <check> Description                 (detail)"
# Output format (plain):
#   Same layout via printf, using ANSI green.
status_pass() {
  local desc="${1:?status_pass requires a description}"
  local detail="${2:-}"
  (( _STATUS_PASSED++ )) || true

  local detail_part=""
  if [[ -n "$detail" ]]; then
    detail_part="($detail)"
  fi

  if use_gum; then
    gum style --foreground="$DRACULA_GREEN" \
      "$(printf '  %s %-45s %s' "$STATUS_SYM_PASS" "$desc" "$detail_part")"
  else
    printf '  \033[32m%s\033[0m %-45s %s\n' "$STATUS_SYM_PASS" "$desc" "$detail_part"
  fi
}

# status_fix -- Record and display a step that required remediation
#
# Checks: Nothing -- the caller performed the fix before calling this.
# Gates: None.
# Side effects: Increments _STATUS_FIXED. Writes to stdout.
# Idempotency: Safe to call multiple times; counter increments each time.
#
# Arguments:
#   $1 -- Short description of what was fixed.
#   $2 -- (optional) Action that was taken, shown after an em-dash.
#
# Output format:
#   Yellow "  <cross> Description                 -- action"
status_fix() {
  local desc="${1:?status_fix requires a description}"
  local action="${2:-}"
  (( _STATUS_FIXED++ )) || true

  local action_part=""
  if [[ -n "$action" ]]; then
    action_part="— $action"
  fi

  if use_gum; then
    gum style --foreground="$DRACULA_YELLOW" \
      "$(printf '  %s %-45s %s' "$STATUS_SYM_FAIL" "$desc" "$action_part")"
  else
    printf '  \033[33m%s\033[0m %-45s %s\n' "$STATUS_SYM_FAIL" "$desc" "$action_part"
  fi
}

# status_skip -- Record and display a step that was intentionally skipped
#
# Checks: Nothing -- the caller determined the skip condition.
# Gates: None.
# Side effects: Increments _STATUS_SKIPPED. Writes to stdout.
# Idempotency: Safe to call multiple times; counter increments each time.
#
# Arguments:
#   $1 -- Short description of what was skipped.
#   $2 -- (optional) Reason for the skip, shown after an em-dash.
#
# Output format:
#   Gray "  <circle> Description                 -- reason"
status_skip() {
  local desc="${1:?status_skip requires a description}"
  local reason="${2:-}"
  (( _STATUS_SKIPPED++ )) || true

  local reason_part=""
  if [[ -n "$reason" ]]; then
    reason_part="— $reason"
  fi

  if use_gum; then
    gum style --foreground="$DRACULA_COMMENT" \
      "$(printf '  %s %-45s %s' "$STATUS_SYM_SKIP" "$desc" "$reason_part")"
  else
    printf '  \033[90m%s\033[0m %-45s %s\n' "$STATUS_SYM_SKIP" "$desc" "$reason_part"
  fi
}

# status_fail -- Record and display a fatal failure, then exit
#
# Checks: Nothing -- the caller detected the failure.
# Gates: None.
# Side effects: Increments _STATUS_FAILED. Writes to stdout. Calls fail().
# Idempotency: N/A -- the process exits.
#
# Arguments:
#   $1 -- Short description of what failed.
#   $2 -- (optional) Detail about the failure.
status_fail() {
  local desc="${1:?status_fail requires a description}"
  local detail="${2:-}"
  (( _STATUS_FAILED++ )) || true

  local detail_part=""
  if [[ -n "$detail" ]]; then
    detail_part="($detail)"
  fi

  if use_gum; then
    gum style --foreground="$DRACULA_RED" \
      "$(printf '  %s %-45s %s' "$STATUS_SYM_FAIL" "$desc" "$detail_part")"
  else
    printf '  \033[31m%s\033[0m %-45s %s\n' "$STATUS_SYM_FAIL" "$desc" "$detail_part"
  fi

  fail "$desc${detail:+: $detail}"
}

# status_summary -- Print a one-line summary of all status counters
#
# Checks: Reads the four global counters.
# Gates: None.
# Side effects: Writes to stdout.
# Idempotency: Always safe; reads counters without modifying them.
#
# Arguments:
#   $1 -- A label prefix (e.g. "Foundation", "Personal").
#
# Output example:
#   "Foundation: 11 passed, 2 fixed, 1 skipped, 0 failed"
status_summary() {
  local label="${1:?status_summary requires a label}"
  local line
  line=$(printf '%s: %d passed, %d fixed, %d skipped, %d failed' \
    "$label" "$_STATUS_PASSED" "$_STATUS_FIXED" "$_STATUS_SKIPPED" "$_STATUS_FAILED")

  if use_gum; then
    gum style --foreground="$DRACULA_FG" --bold "$line"
  else
    printf '\033[1m%s\033[0m\n' "$line"
  fi
}

# run_step -- Execute a command with optional gum spinner and status tracking
#
# Checks: Whether gum is available for spinner display.
# Gates: use_gum() controls spinner vs. plain output.
# Side effects: Runs the provided command. Emits status_pass on success or
#               status_fail on failure.
# Idempotency: Depends entirely on the wrapped command.
#
# Arguments:
#   $1       -- Human-readable title for the step.
#   $2..$N   -- Command and arguments to execute.
#
# If gum is available, the command runs behind a spinner. On success,
# status_pass is emitted. On failure, status_fail is emitted (which exits).
# If gum is NOT available, the title is printed, the command runs directly,
# and the same pass/fail logic applies.
run_step() {
  local title="${1:?run_step requires a title}"
  shift

  if use_gum; then
    if gum spin --title="$title" -- "$@"; then
      status_pass "$title"
    else
      status_fail "$title" "command exited non-zero"
    fi
  else
    printf '  -> %s\n' "$title"
    if "$@"; then
      status_pass "$title"
    else
      status_fail "$title" "command exited non-zero"
    fi
  fi
}


# =============================================================================
# SECTION 4: GUM / UI
# =============================================================================

# use_gum -- Determine whether gum-based UI should be used
#
# Checks: gum on PATH, stdout is a TTY, NON_INTERACTIVE is not "1".
# Gates: NON_INTERACTIVE envvar.
# Side effects: None.
# Idempotency: Pure query.
#
# Returns:
#   0 if gum should be used, 1 otherwise.
use_gum() {
  command_exists gum && [[ -t 1 ]] && [[ "$NON_INTERACTIVE" != "1" ]]
}

# setup_gum_theme -- Export GUM_* environment variables for Dracula theming
#
# Checks: None.
# Gates: None -- always exports; gum ignores them when not invoked.
# Side effects: Sets ~15 environment variables.
# Idempotency: Overwrites the same vars with the same values each time.
setup_gum_theme() {
  # Choose widget -- cursor, selected item, header
  export GUM_CHOOSE_CURSOR_FOREGROUND="$DRACULA_PURPLE"
  export GUM_CHOOSE_SELECTED_FOREGROUND="$DRACULA_GREEN"
  export GUM_CHOOSE_HEADER_FOREGROUND="$DRACULA_FG"

  # Input widget -- prompt, cursor, header
  export GUM_INPUT_PROMPT_FOREGROUND="$DRACULA_PURPLE"
  export GUM_INPUT_CURSOR_FOREGROUND="$DRACULA_PINK"
  export GUM_INPUT_HEADER_FOREGROUND="$DRACULA_FG"

  # Confirm widget -- prompt and selected button
  export GUM_CONFIRM_PROMPT_FOREGROUND="$DRACULA_FG"
  export GUM_CONFIRM_SELECTED_BACKGROUND="$DRACULA_COMMENT"
  export GUM_CONFIRM_SELECTED_FOREGROUND="$DRACULA_FG"

  # Spinner widget -- spinner glyph, title, style
  export GUM_SPIN_SPINNER_FOREGROUND="$DRACULA_CYAN"
  export GUM_SPIN_TITLE_FOREGROUND="$DRACULA_FG"
  export GUM_SPIN_SPINNER="minidot"

  # Filter widget -- indicator, match highlight, prompt
  export GUM_FILTER_INDICATOR_FOREGROUND="$DRACULA_PURPLE"
  export GUM_FILTER_MATCH_FOREGROUND="$DRACULA_GREEN"
  export GUM_FILTER_PROMPT_FOREGROUND="$DRACULA_FG"
}

# panel -- Display text inside a bordered box
#
# Checks: use_gum() for rendering path.
# Gates: None.
# Side effects: Writes to stdout.
# Idempotency: Pure output function.
#
# Arguments:
#   $1 -- The text to display. May contain newlines.
panel() {
  local text="${1:?panel requires text}"
  if use_gum; then
    gum style --border="normal" --foreground="$DRACULA_COMMENT" --padding="1 2" "$text"
  else
    printf '%s\n' "---"
    printf '%b\n' "$text"
    printf '%s\n' "---"
  fi
}

# note -- Display informational text in the foreground color
#
# Checks: use_gum() for rendering path.
# Gates: None.
# Side effects: Writes to stdout.
# Idempotency: Pure output function.
#
# Arguments:
#   $1 -- The text to display.
note() {
  local text="${1:?note requires text}"
  if use_gum; then
    gum style --foreground="$DRACULA_FG" "$text"
  else
    printf '%s\n' "$text"
  fi
}

# success -- Display text in green (success color)
#
# Checks: use_gum() for rendering path.
# Gates: None.
# Side effects: Writes to stdout.
# Idempotency: Pure output function.
#
# Arguments:
#   $1 -- The text to display.
success() {
  local text="${1:?success requires text}"
  if use_gum; then
    gum style --foreground="$DRACULA_GREEN" "$text"
  else
    printf '\033[32m%s\033[0m\n' "$text"
  fi
}

# warn -- Display text in orange (warning color)
#
# Checks: use_gum() for rendering path.
# Gates: None.
# Side effects: Writes to stdout.
# Idempotency: Pure output function.
#
# Arguments:
#   $1 -- The text to display.
warn() {
  local text="${1:?warn requires text}"
  if use_gum; then
    gum style --foreground="$DRACULA_ORANGE" "$text"
  else
    printf '\033[33m%s\033[0m\n' "$text"
  fi
}


# =============================================================================
# SECTION 5: STATE FILE
# =============================================================================

# state_ensure_dir -- Create the state file's parent directory if it is missing
#
# Checks: Whether ~/.config/dotfiles exists.
# Gates: None.
# Side effects: May create directory.
# Idempotency: mkdir -p is inherently idempotent.
state_ensure_dir() {
  mkdir -p "$(dirname "$STATE_FILE_PATH")"
}

# state_read -- Source the state file into the current shell environment
#
# Checks: Whether the state file exists.
# Gates: None.
# Side effects: Defines/overwrites shell variables from the file.
# Idempotency: Safe to call repeatedly; values are overwritten with the same
#              content each time.
#
# The state file is expected to contain lines of the form KEY=VALUE (no export,
# no quoting). Blank lines and comment lines (starting with #) are ignored by
# the shell's `source` built-in.
state_read() {
  if [[ -f "$STATE_FILE_PATH" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE_PATH"
  fi
}

# state_get -- Retrieve a single value from the state file by key
#
# Checks: Whether the state file exists and contains the key.
# Gates: None.
# Side effects: None (reads only).
# Idempotency: Pure query.
#
# Arguments:
#   $1 -- The key to look up (e.g. "DEVICE_PROFILE").
#
# Prints the value to stdout. Prints nothing if the key is absent.
state_get() {
  local key="${1:?state_get requires a key}"
  if [[ -f "$STATE_FILE_PATH" ]]; then
    grep "^${key}=" "$STATE_FILE_PATH" 2>/dev/null | cut -d'=' -f2- || true
  fi
}

# state_set -- Set a single key-value pair in the state file (idempotent)
#
# Checks: Whether the key already exists in the file.
# Gates: None.
# Side effects: Rewrites the state file via atomic temp-file swap.
# Idempotency: If the key already has the given value, the file content is
#              unchanged (though it is still rewritten atomically).
#
# Arguments:
#   $1 -- The key to set.
#   $2 -- The value to assign.
#
# Implementation:
#   1. Ensure the parent directory exists.
#   2. Read the current file (if any) into a temp file, replacing the line for
#      the given key if it exists, or appending it if not.
#   3. Atomically move the temp file over the original.
state_set() {
  local key="${1:?state_set requires a key}"
  local value="${2:?state_set requires a value}"

  state_ensure_dir

  local tmp_file
  tmp_file="$(mktemp "${STATE_FILE_PATH}.XXXXXX")"

  local found=0
  if [[ -f "$STATE_FILE_PATH" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == "${key}="* ]]; then
        printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
        found=1
      else
        printf '%s\n' "$line" >> "$tmp_file"
      fi
    done < "$STATE_FILE_PATH"
  fi

  if [[ "$found" -eq 0 ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
  fi

  mv -f "$tmp_file" "$STATE_FILE_PATH"
}

# state_write_all -- Persist all RESOLVED_* globals to the state file
#
# Checks: None -- blindly writes whatever is in the RESOLVED_* variables.
# Gates: None.
# Side effects: Overwrites STATE_FILE_PATH with a complete snapshot.
# Idempotency: Produces the same file given the same RESOLVED_* values.
#
# Takes no arguments. Reads from the following global variables that
# resolve_all_flags populates:
#   RESOLVED_SHELL, RESOLVED_PROFILE, RESOLVED_ZSCALER, RESOLVED_WORK_APPS,
#   RESOLVED_HOME_APPS, RESOLVED_GUI, RESOLVED_TUCKR, RESOLVED_MACOS_DEFAULTS,
#   RESOLVED_ROSETTA, RESOLVED_MISE_TOOLS, RESOLVED_SHELL_DEFAULT
#
# File format:
#   - Header comment with generation timestamp.
#   - One KEY=VALUE per line, no quoting, no export.
state_write_all() {
  state_ensure_dir

  local tmp_file
  tmp_file="$(mktemp "${STATE_FILE_PATH}.XXXXXX")"

  cat > "$tmp_file" <<EOF
# dotfiles state file -- auto-generated by common.zsh
# last written: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
# Do not edit manually; values are overwritten on each bootstrap run.
PREFERRED_SHELL=${RESOLVED_SHELL:-}
DEVICE_PROFILE=${RESOLVED_PROFILE:-}
ENABLE_ZSCALER=${RESOLVED_ZSCALER:-}
ENABLE_WORK_APPS=${RESOLVED_WORK_APPS:-}
ENABLE_HOME_APPS=${RESOLVED_HOME_APPS:-}
ENABLE_GUI=${RESOLVED_GUI:-}
ENABLE_TUCKR=${RESOLVED_TUCKR:-}
ENABLE_MACOS_DEFAULTS=${RESOLVED_MACOS_DEFAULTS:-}
ENABLE_ROSETTA=${RESOLVED_ROSETTA:-}
ENABLE_MISE_TOOLS=${RESOLVED_MISE_TOOLS:-}
ENABLE_SHELL_DEFAULT=${RESOLVED_SHELL_DEFAULT:-}
EOF

  mv -f "$tmp_file" "$STATE_FILE_PATH"
}


# =============================================================================
# SECTION 6: RESOLUTION
# =============================================================================
#
# The resolution engine walks a strict precedence chain for every configurable
# setting. The chain (highest to lowest priority):
#
#   1. CLI flag value        -- passed directly as a function argument
#   2. Environment variable  -- read from the caller's environment
#   3. State file value      -- persisted from a previous run
#   4. Device profile preset -- a named bundle of defaults (work/home/minimal)
#   5. Interactive gum prompt-- only when stdin is a TTY and gum is available
#   6. Hard-coded default    -- the last non-interactive fallback
#   7. Fail                  -- only for PREFERRED_SHELL which has no safe default
#
# This design means:
#   - Explicit flags always win.
#   - Previous choices are remembered.
#   - Profiles provide sensible bundles.
#   - First-run prompts fill in the gaps interactively.
#   - CI/headless runs use hard defaults without hanging on prompts.

# resolve_setting -- Walk the resolution chain for a single setting
#
# Checks: Each source in precedence order until a non-empty value is found.
# Gates: Interactive prompt is gated on use_gum().
# Side effects: May prompt the user via gum choose.
# Idempotency: Deterministic given the same inputs and environment.
#
# Arguments:
#   $1 -- key           : The setting name (used for prompt display).
#   $2 -- cli_val       : Value from CLI flag (may be empty).
#   $3 -- env_val       : Value from environment variable (may be empty).
#   $4 -- state_val     : Value from state file (may be empty).
#   $5 -- profile_default: Value from the device profile preset (may be empty).
#   $6 -- hard_default  : Hard-coded fallback (may be empty).
#   $7 -- prompt_label  : Label for the gum prompt. If empty, skip prompting.
#
# Prints the resolved value to stdout. Returns 1 if no value could be resolved.
resolve_setting() {
  local key="${1:?resolve_setting requires a key}"
  local cli_val="${2:-}"
  local env_val="${3:-}"
  local state_val="${4:-}"
  local profile_default="${5:-}"
  local hard_default="${6:-}"
  local prompt_label="${7:-}"

  # 1. CLI flag
  if [[ -n "$cli_val" ]]; then
    printf '%s' "$cli_val"
    return 0
  fi

  # 2. Environment variable
  if [[ -n "$env_val" ]]; then
    printf '%s' "$env_val"
    return 0
  fi

  # 3. State file
  if [[ -n "$state_val" ]]; then
    printf '%s' "$state_val"
    return 0
  fi

  # 4. Device profile preset
  if [[ -n "$profile_default" ]]; then
    printf '%s' "$profile_default"
    return 0
  fi

  # 5. Interactive gum prompt
  if [[ -n "$prompt_label" ]] && use_gum; then
    local answer
    answer="$(gum input --header="$prompt_label" --placeholder="Enter value for $key")"
    if [[ -n "$answer" ]]; then
      printf '%s' "$answer"
      return 0
    fi
  fi

  # 6. Hard default
  if [[ -n "$hard_default" ]]; then
    printf '%s' "$hard_default"
    return 0
  fi

  # 7. No value resolved
  return 1
}

# resolve_shell_preference -- Resolve PREFERRED_SHELL with constrained choices
#
# Checks: Walks the resolution chain with "fish" and "zsh" as the only valid
#         interactive options.
# Gates: use_gum() for the interactive prompt.
# Side effects: May prompt the user.
# Idempotency: Deterministic given the same inputs.
#
# Arguments:
#   $1 -- cli_val : Value from CLI --shell flag (may be empty).
#
# Prints "fish" or "zsh" to stdout. Calls fail() if no value can be resolved
# (this is the only setting where an unresolved value is a fatal error, because
# there is no universally safe default -- the user must choose).
resolve_shell_preference() {
  local cli_val="${1:-}"
  local env_val="${PREFERRED_SHELL:-}"
  local state_val
  state_val="$(state_get PREFERRED_SHELL)"

  # If we have a value from the top-priority sources, use it directly.
  local resolved=""
  if [[ -n "$cli_val" ]]; then
    resolved="$cli_val"
  elif [[ -n "$env_val" ]]; then
    resolved="$env_val"
  elif [[ -n "$state_val" ]]; then
    resolved="$state_val"
  elif use_gum; then
    # Interactive prompt with constrained choices
    resolved="$(gum choose --header="Select your preferred shell" "fish" "zsh")"
  fi

  if [[ -z "$resolved" ]]; then
    fail "PREFERRED_SHELL could not be resolved. Pass --shell <fish|zsh>, set the PREFERRED_SHELL env var, or run interactively."
  fi

  # Validate the value
  case "$resolved" in
    fish|zsh) ;;
    *) fail "PREFERRED_SHELL must be 'fish' or 'zsh', got: $resolved" ;;
  esac

  printf '%s' "$resolved"
}

# resolve_device_profile -- Resolve DEVICE_PROFILE with constrained choices
#
# Checks: Walks the resolution chain with "work", "home", "minimal" as valid
#         options.
# Gates: use_gum() for the interactive prompt.
# Side effects: May prompt the user.
# Idempotency: Deterministic given the same inputs.
#
# Arguments:
#   $1 -- cli_val : Value from CLI --profile flag (may be empty).
#
# Prints one of "work", "home", or "minimal" to stdout. Falls back to
# "minimal" as the hard default.
resolve_device_profile() {
  local cli_val="${1:-}"
  local env_val="${DEVICE_PROFILE:-}"
  local state_val
  state_val="$(state_get DEVICE_PROFILE)"

  local resolved=""
  if [[ -n "$cli_val" ]]; then
    resolved="$cli_val"
  elif [[ -n "$env_val" ]]; then
    resolved="$env_val"
  elif [[ -n "$state_val" ]]; then
    resolved="$state_val"
  elif use_gum; then
    resolved="$(gum choose --header="Select device profile" "work" "home" "minimal")"
  fi

  # Hard default
  if [[ -z "$resolved" ]]; then
    resolved="minimal"
  fi

  # Validate
  case "$resolved" in
    work|home|minimal) ;;
    *) fail "DEVICE_PROFILE must be 'work', 'home', or 'minimal', got: $resolved" ;;
  esac

  printf '%s' "$resolved"
}

# get_profile_default -- Look up a preset value for a given profile and flag
#
# Checks: None.
# Gates: None.
# Side effects: None.
# Idempotency: Pure lookup function.
#
# Arguments:
#   $1 -- profile  : One of "work", "home", "minimal".
#   $2 -- flag_key : One of the ENABLE_* setting names.
#
# Prints the preset value to stdout. Prints nothing if the profile or key is
# unknown (the caller can treat empty as "no preset").
#
# Profile presets encode the default boolean flags for each device role:
#
#   | Flag                  | work  | home  | minimal |
#   |-----------------------|-------|-------|---------|
#   | ENABLE_ZSCALER        | auto  | false | false   |
#   | ENABLE_WORK_APPS      | true  | false | false   |
#   | ENABLE_HOME_APPS      | false | true  | false   |
#   | ENABLE_GUI            | true  | true  | false   |
#   | ENABLE_TUCKR          | true  | true  | true    |
#   | ENABLE_MACOS_DEFAULTS | true  | true  | false   |
#   | ENABLE_ROSETTA         | true  | true  | false   |
#   | ENABLE_MISE_TOOLS     | true  | true  | true    |
#   | ENABLE_SHELL_DEFAULT  | true  | true  | true    |
get_profile_default() {
  local profile="${1:?get_profile_default requires a profile}"
  local flag_key="${2:?get_profile_default requires a flag_key}"

  case "${profile}:${flag_key}" in
    # -- work profile --
    work:ENABLE_ZSCALER)        printf 'auto'  ;;
    work:ENABLE_WORK_APPS)      printf 'true'  ;;
    work:ENABLE_HOME_APPS)      printf 'false' ;;
    work:ENABLE_GUI)            printf 'true'  ;;
    work:ENABLE_TUCKR)          printf 'true'  ;;
    work:ENABLE_MACOS_DEFAULTS) printf 'true'  ;;
    work:ENABLE_ROSETTA)        printf 'true'  ;;
    work:ENABLE_MISE_TOOLS)     printf 'true'  ;;
    work:ENABLE_SHELL_DEFAULT)  printf 'true'  ;;

    # -- home profile --
    home:ENABLE_ZSCALER)        printf 'false' ;;
    home:ENABLE_WORK_APPS)      printf 'false' ;;
    home:ENABLE_HOME_APPS)      printf 'true'  ;;
    home:ENABLE_GUI)            printf 'true'  ;;
    home:ENABLE_TUCKR)          printf 'true'  ;;
    home:ENABLE_MACOS_DEFAULTS) printf 'true'  ;;
    home:ENABLE_ROSETTA)        printf 'true'  ;;
    home:ENABLE_MISE_TOOLS)     printf 'true'  ;;
    home:ENABLE_SHELL_DEFAULT)  printf 'true'  ;;

    # -- minimal profile --
    minimal:ENABLE_ZSCALER)        printf 'false' ;;
    minimal:ENABLE_WORK_APPS)      printf 'false' ;;
    minimal:ENABLE_HOME_APPS)      printf 'false' ;;
    minimal:ENABLE_GUI)            printf 'false' ;;
    minimal:ENABLE_TUCKR)          printf 'true'  ;;
    minimal:ENABLE_MACOS_DEFAULTS) printf 'false' ;;
    minimal:ENABLE_ROSETTA)        printf 'false' ;;
    minimal:ENABLE_MISE_TOOLS)     printf 'true'  ;;
    minimal:ENABLE_SHELL_DEFAULT)  printf 'true'  ;;

    # Unknown combination -- return nothing
    *) ;;
  esac
}

# resolve_all_flags -- Resolve every configurable flag using the full chain
#
# Checks: Resolves PREFERRED_SHELL, DEVICE_PROFILE, and all ENABLE_* flags.
# Gates: None directly, but delegates to resolve_setting/resolve_shell_preference
#        which are gated on use_gum().
# Side effects: Populates RESOLVED_* global variables. Calls state_write_all()
#               to persist the resolved values.
# Idempotency: Safe to call multiple times; overwrites globals and state file.
#
# Arguments (positional):
#   $1  -- cli_shell          : --shell flag value
#   $2  -- cli_profile        : --profile flag value
#   $3  -- cli_enable_zscaler : --zscaler flag value
#   $4  -- cli_enable_work    : --work-apps flag value
#   $5  -- cli_enable_home    : --home-apps flag value
#   $6  -- cli_enable_gui     : --gui flag value
#   $7  -- cli_enable_tuckr   : --tuckr flag value
#   $8  -- cli_enable_macos   : --macos-defaults flag value
#   $9  -- cli_enable_rosetta : --rosetta flag value
#   $10 -- cli_enable_mise    : --mise-tools flag value
#   $11 -- cli_enable_shell_default : --shell-default flag value
#
# After this function returns, the following globals are set:
#   RESOLVED_SHELL, RESOLVED_PROFILE, RESOLVED_ZSCALER, RESOLVED_WORK_APPS,
#   RESOLVED_HOME_APPS, RESOLVED_GUI, RESOLVED_TUCKR, RESOLVED_MACOS_DEFAULTS,
#   RESOLVED_ROSETTA, RESOLVED_MISE_TOOLS, RESOLVED_SHELL_DEFAULT
resolve_all_flags() {
  local cli_shell="${1:-}"
  local cli_profile="${2:-}"
  local cli_enable_zscaler="${3:-}"
  local cli_enable_work="${4:-}"
  local cli_enable_home="${5:-}"
  local cli_enable_gui="${6:-}"
  local cli_enable_tuckr="${7:-}"
  local cli_enable_macos="${8:-}"
  local cli_enable_rosetta="${9:-}"
  local cli_enable_mise="${10:-}"
  local cli_enable_shell_default="${11:-}"

  # Read current state file into environment (provides state_val fallbacks)
  state_read

  # -- Resolve profile first (other flags depend on it for profile defaults) --
  typeset -g RESOLVED_PROFILE
  RESOLVED_PROFILE="$(resolve_device_profile "$cli_profile")"

  # -- Resolve shell preference (special case: fails if unresolvable) --
  typeset -g RESOLVED_SHELL
  RESOLVED_SHELL="$(resolve_shell_preference "$cli_shell")"

  # -- Helper: resolve a boolean/string flag --
  # For each flag we pass:
  #   cli_val, env_val, state_val, profile_default, hard_default, prompt_label
  # We read env vars and state vars by their canonical names.

  typeset -g RESOLVED_ZSCALER
  RESOLVED_ZSCALER="$(resolve_setting "ENABLE_ZSCALER" \
    "$cli_enable_zscaler" \
    "${ENABLE_ZSCALER:-}" \
    "$(state_get ENABLE_ZSCALER)" \
    "$(get_profile_default "$RESOLVED_PROFILE" ENABLE_ZSCALER)" \
    "false" \
    "")"

  typeset -g RESOLVED_WORK_APPS
  RESOLVED_WORK_APPS="$(resolve_setting "ENABLE_WORK_APPS" \
    "$cli_enable_work" \
    "${ENABLE_WORK_APPS:-}" \
    "$(state_get ENABLE_WORK_APPS)" \
    "$(get_profile_default "$RESOLVED_PROFILE" ENABLE_WORK_APPS)" \
    "false" \
    "")"

  typeset -g RESOLVED_HOME_APPS
  RESOLVED_HOME_APPS="$(resolve_setting "ENABLE_HOME_APPS" \
    "$cli_enable_home" \
    "${ENABLE_HOME_APPS:-}" \
    "$(state_get ENABLE_HOME_APPS)" \
    "$(get_profile_default "$RESOLVED_PROFILE" ENABLE_HOME_APPS)" \
    "false" \
    "")"

  typeset -g RESOLVED_GUI
  RESOLVED_GUI="$(resolve_setting "ENABLE_GUI" \
    "$cli_enable_gui" \
    "${ENABLE_GUI:-}" \
    "$(state_get ENABLE_GUI)" \
    "$(get_profile_default "$RESOLVED_PROFILE" ENABLE_GUI)" \
    "false" \
    "")"

  typeset -g RESOLVED_TUCKR
  RESOLVED_TUCKR="$(resolve_setting "ENABLE_TUCKR" \
    "$cli_enable_tuckr" \
    "${ENABLE_TUCKR:-}" \
    "$(state_get ENABLE_TUCKR)" \
    "$(get_profile_default "$RESOLVED_PROFILE" ENABLE_TUCKR)" \
    "true" \
    "")"

  typeset -g RESOLVED_MACOS_DEFAULTS
  RESOLVED_MACOS_DEFAULTS="$(resolve_setting "ENABLE_MACOS_DEFAULTS" \
    "$cli_enable_macos" \
    "${ENABLE_MACOS_DEFAULTS:-}" \
    "$(state_get ENABLE_MACOS_DEFAULTS)" \
    "$(get_profile_default "$RESOLVED_PROFILE" ENABLE_MACOS_DEFAULTS)" \
    "false" \
    "")"

  typeset -g RESOLVED_ROSETTA
  RESOLVED_ROSETTA="$(resolve_setting "ENABLE_ROSETTA" \
    "$cli_enable_rosetta" \
    "${ENABLE_ROSETTA:-}" \
    "$(state_get ENABLE_ROSETTA)" \
    "$(get_profile_default "$RESOLVED_PROFILE" ENABLE_ROSETTA)" \
    "false" \
    "")"

  typeset -g RESOLVED_MISE_TOOLS
  RESOLVED_MISE_TOOLS="$(resolve_setting "ENABLE_MISE_TOOLS" \
    "$cli_enable_mise" \
    "${ENABLE_MISE_TOOLS:-}" \
    "$(state_get ENABLE_MISE_TOOLS)" \
    "$(get_profile_default "$RESOLVED_PROFILE" ENABLE_MISE_TOOLS)" \
    "true" \
    "")"

  typeset -g RESOLVED_SHELL_DEFAULT
  RESOLVED_SHELL_DEFAULT="$(resolve_setting "ENABLE_SHELL_DEFAULT" \
    "$cli_enable_shell_default" \
    "${ENABLE_SHELL_DEFAULT:-}" \
    "$(state_get ENABLE_SHELL_DEFAULT)" \
    "$(get_profile_default "$RESOLVED_PROFILE" ENABLE_SHELL_DEFAULT)" \
    "true" \
    "")"

  # Persist all resolved values to the state file
  state_write_all
}

# export_brew_env_vars -- Map resolved flags to Homebrew environment variables
#
# Checks: Reads RESOLVED_WORK_APPS, RESOLVED_HOME_APPS, RESOLVED_GUI.
# Gates: Only exports a var when the corresponding resolved flag is "true".
# Side effects: Exports HOMEBREW_WORK_APPS, HOMEBREW_HOME_APPS, HOMEBREW_GUI.
# Idempotency: Overwrites the same env vars each time.
#
# Homebrew bundle taps and the Brewfile can read these env vars to conditionally
# include/exclude groups of formulae and casks. For example:
#   brew "slack", if: ENV["HOMEBREW_WORK_APPS"] == "true"
export_brew_env_vars() {
  if [[ "${RESOLVED_WORK_APPS:-}" == "true" ]]; then
    export HOMEBREW_WORK_APPS=true
  fi

  if [[ "${RESOLVED_HOME_APPS:-}" == "true" ]]; then
    export HOMEBREW_HOME_APPS=true
  fi

  if [[ "${RESOLVED_GUI:-}" == "true" ]]; then
    export HOMEBREW_GUI=true
  fi
}


# =============================================================================
# SECTION 7: MANAGED BLOCK WRITER
# =============================================================================

# write_managed_block -- Idempotent marker-delimited block writer
#
# Checks: Whether the target file already contains the begin marker.
# Gates: None.
# Side effects: Creates or modifies the target file. Creates parent directories
#               if they do not exist.
# Idempotency: If the block content is identical, the file is rewritten with
#              the same content. If the markers are absent, the block is
#              appended. If the markers are present, the content between them
#              (inclusive) is replaced.
#
# Arguments:
#   $1 -- file_path     : Absolute path to the target file.
#   $2 -- begin_marker  : The opening fence line (e.g. "# >>> my-block >>>").
#   $3 -- end_marker    : The closing fence line (e.g. "# <<< my-block <<<").
#   $4 -- block_content : The full content to place between the markers
#                         (should include the markers themselves at the
#                         beginning and end).
#
# Implementation:
#   Uses a temp file and line-by-line processing instead of fragile Perl
#   one-liners. The algorithm:
#     1. If the file does not contain the begin marker, append block_content.
#     2. If the file contains the begin marker, copy lines before it, write
#        the new block_content, skip old lines until (and including) the end
#        marker, then copy lines after it.
#     3. Atomically move the temp file over the original.
write_managed_block() {
  local file_path="${1:?write_managed_block requires file_path}"
  local begin_marker="${2:?write_managed_block requires begin_marker}"
  local end_marker="${3:?write_managed_block requires end_marker}"
  local block_content="${4:?write_managed_block requires block_content}"

  # Dry-run: report what would happen without writing anything
  if dry_run_active; then
    if [[ ! -f "$file_path" ]]; then
      dry_run_log "create $file_path and write managed block"
    elif ! grep -qF "$begin_marker" "$file_path"; then
      dry_run_log "append managed block to $file_path"
    else
      dry_run_log "replace managed block in $file_path"
    fi
    return 0
  fi

  # Ensure parent directory and file exist
  mkdir -p "$(dirname "$file_path")"
  touch "$file_path"

  # Fast path: markers not present -- just append
  if ! grep -qF "$begin_marker" "$file_path"; then
    printf '\n%s\n' "$block_content" >> "$file_path"
    return 0
  fi

  # Slow path: replace the existing block
  local tmp_file
  tmp_file="$(mktemp "${file_path}.XXXXXX")"

  local inside_block=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == *"$begin_marker"* ]]; then
      # Write the new block content (which includes markers)
      printf '%s\n' "$block_content" >> "$tmp_file"
      inside_block=1
      continue
    fi

    if [[ "$inside_block" -eq 1 ]]; then
      # Skip old lines until we find the end marker
      if [[ "$line" == *"$end_marker"* ]]; then
        inside_block=0
      fi
      continue
    fi

    # Outside the block -- copy verbatim
    printf '%s\n' "$line" >> "$tmp_file"
  done < "$file_path"

  mv -f "$tmp_file" "$file_path"
}
