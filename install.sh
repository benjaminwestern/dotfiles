#!/bin/bash
set -euo pipefail

###############################################################################
# install.sh -- Remote/local macOS bootstrap entrypoint
#
# This script is the public Unix entrypoint for the dotfiles bootstrap. It can
# be run from a local repository checkout or streamed remotely via curl. It
# ensures the dotfiles repository is available on disk, then delegates to the
# repo-local macOS bootstrap entrypoint.
#
# Windows uses install.cmd instead.
###############################################################################

DEFAULT_DOTFILES_REPO="https://github.com/benjaminwestern/dotfiles.git"
DEFAULT_ARCHIVE_URL="https://github.com/benjaminwestern/dotfiles/archive/refs/heads/main.tar.gz"

MODE=""
PREFERRED_SHELL=""
DEVICE_PROFILE=""
NON_INTERACTIVE=0
DRY_RUN=0
ENABLE_PERSONAL=0
DOTFILES_REPO="${DOTFILES_REPO:-$DEFAULT_DOTFILES_REPO}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
PERSONAL_SCRIPT=""
AUDIT_ARGS=()
_DYNAMIC_FLAGS=""
RUN_ROOT=""
ARCHIVE_RUN_ROOT=""

SELF_PATH="${BASH_SOURCE[0]:-}"
SELF_DIR=""
if [[ -n "$SELF_PATH" ]] && [[ -f "$SELF_PATH" ]]; then
  SELF_DIR="$(cd "$(dirname "$SELF_PATH")" && pwd)"
fi

display_message() {
  echo -e "\n>>> $1 <<<\n"
}

fail() {
  display_message "ERROR: $1"
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  install.sh <setup|ensure|update|personal|audit> [options]

Options:
  --shell <fish|zsh>       Set preferred shell (persisted to state file)
  --profile <work|home|minimal>  Set device profile preset
  --enable-<flag>          Enable a feature flag (for example, --enable-zscaler)
  --disable-<flag>         Disable a feature flag (for example, --disable-work-apps)
  --personal               Run the personal layer after foundation
  --non-interactive        Disable all interactive prompts
  --dry-run                Show what would happen without making any changes
  --dotfiles-repo <url>    Override dotfiles repository URL
  --dotfiles-dir <path>    Override the local dotfiles checkout path
  --personal-script <path> Override personal bootstrap script path

Feature flags: zscaler, work-apps, home-apps, gui, tuckr, macos-defaults,
               rosetta, mise-tools, shell-default

Repo-local scripts:
  Other/scripts/macos/bootstrap-macos.zsh
  Other/scripts/macos/foundation-macos.zsh
  Other/scripts/macos/personal-bootstrap-macos.zsh
  Other/scripts/macos/audit-macos.zsh

Examples:
  install.sh setup --shell fish --profile work
  install.sh ensure --personal
  install.sh update --enable-work-apps --disable-home-apps
  install.sh personal --non-interactive --shell zsh
  install.sh setup --dry-run --shell fish --profile work
  install.sh audit
  install.sh audit --section tools
  install.sh audit --json

Windows:
  Use install.cmd instead.

Linux:
  Not yet implemented.
EOF
}

_flag_name_to_var() {
  local raw="$1"
  local upper
  upper="$(echo "$raw" | tr '[:lower:]-' '[:upper:]_')"
  echo "ENABLE_${upper}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      setup|ensure|update|personal|audit)
        if [[ -n "$MODE" ]]; then
          fail "Mode already set to '$MODE'"
        fi
        MODE="$1"
        shift
        if [[ "$MODE" == "audit" ]]; then
          AUDIT_ARGS=("$@")
          return 0
        fi
        ;;
      --shell)
        [[ $# -ge 2 ]] || fail "--shell requires a value"
        PREFERRED_SHELL="$2"
        shift 2
        ;;
      --profile)
        [[ $# -ge 2 ]] || fail "--profile requires a value"
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
        [[ $# -ge 2 ]] || fail "--dotfiles-repo requires a value"
        DOTFILES_REPO="$2"
        shift 2
        ;;
      --dotfiles-dir)
        [[ $# -ge 2 ]] || fail "--dotfiles-dir requires a value"
        DOTFILES_DIR="$2"
        shift 2
        ;;
      --personal-script)
        [[ $# -ge 2 ]] || fail "--personal-script requires a value"
        PERSONAL_SCRIPT="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done

  if [[ -z "$MODE" ]]; then
    MODE="setup"
  fi
}

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unsupported" ;;
  esac
}

export_flags() {
  export MODE
  export PREFERRED_SHELL
  export DEVICE_PROFILE
  export NON_INTERACTIVE
  export DRY_RUN
  export ENABLE_PERSONAL
  export DOTFILES_REPO
  export DOTFILES_DIR
  export PERSONAL_SCRIPT
  export BOOTSTRAP_ROOT="$RUN_ROOT"

  if [[ -n "$_DYNAMIC_FLAGS" ]]; then
    while IFS='=' read -r var_name var_value; do
      export "${var_name}=${var_value}"
    done <<< "$_DYNAMIC_FLAGS"
  fi
}

local_repo_root() {
  if [[ -n "$SELF_DIR" ]] && [[ -f "$SELF_DIR/Other/scripts/macos/bootstrap-macos.zsh" ]]; then
    printf '%s\n' "$SELF_DIR"
    return 0
  fi

  return 1
}

have_git() {
  command -v git >/dev/null 2>&1
}

clone_repo_with_git() {
  display_message "Cloning dotfiles repo to $DOTFILES_DIR"
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
}

download_repo_archive() {
  [[ "$DOTFILES_REPO" == "$DEFAULT_DOTFILES_REPO" ]] || \
    fail "git is required when --dotfiles-repo is not the default repository"

  local temp_root
  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-install.XXXXXX")"
  local archive_path="$temp_root/dotfiles-main.tar.gz"

  display_message "Downloading temporary dotfiles archive"
  curl -fsSL "$DEFAULT_ARCHIVE_URL" -o "$archive_path"
  tar -xzf "$archive_path" -C "$temp_root"

  ARCHIVE_RUN_ROOT="$temp_root/dotfiles-main"
  RUN_ROOT="$ARCHIVE_RUN_ROOT"
}

ensure_run_root() {
  local local_root=""
  if local_root="$(local_repo_root 2>/dev/null)"; then
    RUN_ROOT="$local_root"
    return
  fi

  if [[ -f "$DOTFILES_DIR/Other/scripts/macos/bootstrap-macos.zsh" ]]; then
    RUN_ROOT="$DOTFILES_DIR"
    return
  fi

  if [[ -e "$DOTFILES_DIR" ]]; then
    fail "Path exists but does not contain the dotfiles bootstrap: $DOTFILES_DIR"
  fi

  if have_git; then
    clone_repo_with_git
    RUN_ROOT="$DOTFILES_DIR"
    return
  fi

  download_repo_archive
}

maybe_persist_repo_after_archive_run() {
  if [[ -z "$ARCHIVE_RUN_ROOT" ]]; then
    return
  fi

  if [[ -e "$DOTFILES_DIR" ]]; then
    return
  fi

  if have_git; then
    display_message "Cloning persistent dotfiles repo to $DOTFILES_DIR"
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    return
  fi

  display_message "WARNING: bootstrap ran from a temporary archive because git is unavailable; dotfiles repo was not persisted"
}

run_macos_entrypoint() {
  local exit_code

  if [[ "$MODE" == "audit" ]]; then
    /bin/zsh "$RUN_ROOT/Other/scripts/macos/bootstrap-macos.zsh" audit "${AUDIT_ARGS[@]}"
    exit_code=$?
  elif [[ "$MODE" == "personal" ]]; then
    /bin/zsh "$RUN_ROOT/Other/scripts/macos/bootstrap-macos.zsh" personal
    exit_code=$?
  else
    /bin/zsh "$RUN_ROOT/Other/scripts/macos/bootstrap-macos.zsh" "$MODE"
    exit_code=$?
  fi

  maybe_persist_repo_after_archive_run
  exit "$exit_code"
}

parse_args "$@"
OS="$(detect_os)"
ensure_run_root
export_flags

display_message "Install Entry"
display_message "OS: $OS | Mode: $MODE"
if [[ "$DRY_RUN" -eq 1 ]]; then
  display_message "DRY RUN — no changes will be made"
fi

case "$OS" in
  macos)
    run_macos_entrypoint
    ;;
  windows)
    fail "Windows detected. Use install.cmd instead."
    ;;
  linux)
    fail "Linux is not implemented yet"
    ;;
  *)
    fail "Unsupported OS: $(uname -s)"
    ;;
esac
