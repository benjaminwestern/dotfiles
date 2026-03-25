#!/bin/bash
set -euo pipefail

###############################################################################
# bootstrap.sh -- Cross-platform entrypoint for dotfiles bootstrapping
#
# This script is the single entrypoint for provisioning a new machine or
# keeping an existing one up to date. It detects the current operating system
# and delegates to the appropriate platform-specific foundation script.
#
# ---- Two-layer architecture ------------------------------------------------
#
# Layer 1: Foundation (platform-specific)
#   Installs core tooling that every machine needs regardless of who owns it.
#   Examples: Homebrew, core CLI utilities, shell configuration, Tuckr links.
#   Scripts:
#     macOS   → Other/scripts/foundation-macos.zsh
#     Windows → Other/scripts/foundation-windows.ps1
#
# Layer 2: Personal (optional, runs after foundation)
#   Applies user-specific configuration: app preferences, credentials setup,
#   GUI app installation, etc. Triggered by passing --personal.
#   Scripts:
#     macOS   → Other/scripts/personal-bootstrap-macos.zsh
#     Windows → Other/scripts/personal-bootstrap-windows.ps1
#
# ---- Flag resolution order -------------------------------------------------
#
# Every feature flag is resolved through a five-step cascade. The first source
# that provides a value wins:
#
#   1. CLI flag          (--enable-zscaler / --disable-gui)
#   2. Environment var   (ENABLE_ZSCALER=true)
#   3. State file        (~/.dotfiles-state, persisted between runs)
#   4. Device profile    (--profile work → enables work-apps, zscaler, etc.)
#   5. Interactive prompt (unless --non-interactive, then falls to default)
#   6. Default           (usually false / disabled)
#
# The foundation script is responsible for implementing steps 2-6. This
# entrypoint handles step 1 (CLI parsing) and exports the results as env vars
# so child scripts can read them.
#
# ---- Usage examples --------------------------------------------------------
#
#   # Fresh macOS work machine with Fish shell:
#   ./bootstrap.sh setup --shell fish --profile work
#
#   # Keep everything up to date, also run personal layer:
#   ./bootstrap.sh ensure --personal
#
#   # Update with specific feature toggles:
#   ./bootstrap.sh update --enable-work-apps --disable-home-apps
#
#   # Run only the personal layer, no prompts:
#   ./bootstrap.sh personal --non-interactive --shell zsh
#
#   # Windows (this script does not run on Windows; use PowerShell):
#   pwsh -File Other/scripts/foundation-windows.ps1 setup
#
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
MODE=""
PREFERRED_SHELL=""
DEVICE_PROFILE=""
NON_INTERACTIVE=0
DRY_RUN=0
ENABLE_PERSONAL=0
DOTFILES_REPO="https://github.com/benjaminwestern/dotfiles.git"
PERSONAL_SCRIPT=""
AUDIT_ARGS=""

# Associative array is not portable in older bash; track dynamic ENABLE_*
# flags as a newline-separated list of "VAR=VALUE" pairs.
_DYNAMIC_FLAGS=""

# display_message -- Print a clearly delimited status line to stdout
#
# Checks: nothing
# Side effects: writes to stdout
display_message() {
  echo -e "\n>>> $1 <<<\n"
}

# usage -- Print full help text and exit
#
# Checks: nothing
# Side effects: writes to stdout
usage() {
  cat <<'EOF'
Usage:
  bootstrap.sh <setup|ensure|update|personal|audit> [options]

Options:
  --shell <fish|zsh>       Set preferred shell (persisted to state file)
  --profile <work|home|minimal>  Set device profile preset
  --enable-<flag>          Enable a feature flag (e.g. --enable-zscaler)
  --disable-<flag>         Disable a feature flag (e.g. --disable-work-apps)
  --personal               Run the personal layer after foundation
  --non-interactive        Disable all interactive prompts
  --dry-run                Show what would happen without making any changes
  --dotfiles-repo <url>    Override dotfiles repository URL
  --personal-script <path> Override personal bootstrap script path

Feature flags: zscaler, work-apps, home-apps, gui, tuckr, macos-defaults,
               rosetta, mise-tools, shell-default

Examples:
  bootstrap.sh setup --shell fish --profile work
  bootstrap.sh ensure --personal
  bootstrap.sh update --enable-work-apps --disable-home-apps
  bootstrap.sh personal --non-interactive --shell zsh
  bootstrap.sh setup --dry-run --shell fish --profile work
  bootstrap.sh audit                            # Full read-only machine state audit
  bootstrap.sh audit --section tools            # Audit only tools
  bootstrap.sh audit --json                     # Machine-readable JSON output

Windows:
  This script does not run on Windows. Use PowerShell directly:
  pwsh -File Other/scripts/foundation-windows.ps1 setup

Linux:
  Not yet implemented.
EOF
}

# _flag_name_to_var -- Convert a kebab-case flag name to an ENABLE_* variable
#
# Checks: nothing
# Side effects: writes to stdout
#
# Example: "work-apps" → "ENABLE_WORK_APPS"
_flag_name_to_var() {
  local raw="$1"
  local upper
  upper="$(echo "$raw" | tr '[:lower:]-' '[:upper:]_')"
  echo "ENABLE_${upper}"
}

# parse_args -- Parse all command-line arguments into global variables
#
# Checks: validates mode is not set twice, required values are present
# Side effects: sets MODE, PREFERRED_SHELL, DEVICE_PROFILE, NON_INTERACTIVE,
#               ENABLE_PERSONAL, DOTFILES_REPO, PERSONAL_SCRIPT, and any
#               dynamic ENABLE_* flags via _DYNAMIC_FLAGS
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      setup|ensure|update|personal|audit)
        if [[ -n "$MODE" ]]; then
          display_message "ERROR: Mode already set to '$MODE'"
          exit 1
        fi
        MODE="$1"
        shift
        # Audit mode: pass all remaining arguments through to the audit script
        if [[ "$MODE" == "audit" ]]; then
          AUDIT_ARGS="$*"
          return 0
        fi
        ;;
      --shell)
        [[ $# -ge 2 ]] || { display_message "ERROR: --shell requires a value"; exit 1; }
        PREFERRED_SHELL="$2"
        shift 2
        ;;
      --profile)
        [[ $# -ge 2 ]] || { display_message "ERROR: --profile requires a value"; exit 1; }
        DEVICE_PROFILE="$2"
        shift 2
        ;;
      --enable-*)
        local flag_name="${1#--enable-}"
        local var_name
        var_name="$(_flag_name_to_var "$flag_name")"
        _DYNAMIC_FLAGS="${_DYNAMIC_FLAGS:+${_DYNAMIC_FLAGS}$'\n'}${var_name}=true"
        shift
        ;;
      --disable-*)
        local flag_name="${1#--disable-}"
        local var_name
        var_name="$(_flag_name_to_var "$flag_name")"
        _DYNAMIC_FLAGS="${_DYNAMIC_FLAGS:+${_DYNAMIC_FLAGS}$'\n'}${var_name}=false"
        shift
        ;;
      --personal)
        ENABLE_PERSONAL=1
        shift
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --dotfiles-repo)
        [[ $# -ge 2 ]] || { display_message "ERROR: --dotfiles-repo requires a value"; exit 1; }
        DOTFILES_REPO="$2"
        shift 2
        ;;
      --personal-script)
        [[ $# -ge 2 ]] || { display_message "ERROR: --personal-script requires a value"; exit 1; }
        PERSONAL_SCRIPT="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        display_message "ERROR: Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "$MODE" ]]; then
    MODE="setup"
  fi
}

# detect_os -- Return a normalised OS identifier string
#
# Checks: uname -s output
# Side effects: writes to stdout
detect_os() {
  case "$(uname -s)" in
    Darwin)        echo "macos"       ;;
    Linux)         echo "linux"       ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)             echo "unsupported" ;;
  esac
}

# export_flags -- Export every parsed value as an environment variable
#
# Checks: nothing
# Side effects: exports MODE, PREFERRED_SHELL, DEVICE_PROFILE,
#               NON_INTERACTIVE, ENABLE_PERSONAL, DOTFILES_REPO,
#               PERSONAL_SCRIPT, BOOTSTRAP_ROOT, and all dynamic ENABLE_* vars
export_flags() {
  export MODE
  export PREFERRED_SHELL
  export DEVICE_PROFILE
  export NON_INTERACTIVE
  export DRY_RUN
  export ENABLE_PERSONAL
  export DOTFILES_REPO
  export PERSONAL_SCRIPT
  export BOOTSTRAP_ROOT="$SCRIPT_DIR"

  # Export each dynamic ENABLE_* flag
  if [[ -n "$_DYNAMIC_FLAGS" ]]; then
    while IFS='=' read -r var_name var_value; do
      export "${var_name}=${var_value}"
    done <<< "$_DYNAMIC_FLAGS"
  fi
}

###############################################################################
# Main
###############################################################################

parse_args "$@"
OS="$(detect_os)"
export_flags

display_message "Bootstrap Entry"
display_message "OS: $OS | Mode: $MODE"
if [[ "$DRY_RUN" -eq 1 ]]; then
  display_message "DRY RUN — no changes will be made"
fi

# Audit mode is a direct handoff to the audit script — no foundation needed
if [[ "$MODE" == "audit" ]]; then
  case "$OS" in
    macos)   exec /bin/zsh "$SCRIPT_DIR/Other/scripts/audit-macos.zsh" ${AUDIT_ARGS} ;;
    windows)
      WIN_AUDIT_ARGS=""
      [[ -n "${AUDIT_ARGS:-}" ]] && WIN_AUDIT_ARGS="$AUDIT_ARGS"
      display_message "Windows audit: Run directly: pwsh -File $SCRIPT_DIR/Other/scripts/audit-windows.ps1 $WIN_AUDIT_ARGS"
      exit 1
      ;;
    linux)   display_message "Linux audit not yet implemented"; exit 1 ;;
    *)       display_message "Unsupported OS: $(uname -s)"; exit 1 ;;
  esac
fi

case "$OS" in
  macos)   exec /bin/zsh "$SCRIPT_DIR/Other/scripts/foundation-macos.zsh"  ;;
  linux)   display_message "Linux is not implemented yet"; exit 1 ;;
  windows)
    WIN_ARGS="-Mode $MODE"
    [[ -n "${PREFERRED_SHELL:-}" ]] && WIN_ARGS="$WIN_ARGS -Shell $PREFERRED_SHELL"
    [[ -n "${DEVICE_PROFILE:-}" ]]  && WIN_ARGS="$WIN_ARGS -Profile_ $DEVICE_PROFILE"
    [[ "$DRY_RUN" -eq 1 ]]         && WIN_ARGS="$WIN_ARGS -DryRun"
    [[ "$ENABLE_PERSONAL" -eq 1 ]] && WIN_ARGS="$WIN_ARGS -Personal"
    display_message "Windows detected. Run: pwsh -File $SCRIPT_DIR/Other/scripts/foundation-windows.ps1 $WIN_ARGS"
    exit 1
    ;;
  *)       display_message "Unsupported OS: $(uname -s)"; exit 1 ;;
esac
