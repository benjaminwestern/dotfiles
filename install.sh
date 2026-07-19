#!/bin/bash
set -euo pipefail

###############################################################################
# install.sh -- Remote/local macOS and Linux bootstrap entrypoint
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
DEVICE_NAME=""
DOWNLOADS_TARGET=""
GIT_USER_NAME=""
GIT_USER_EMAIL=""
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
INTERACTIVE_TTY=""

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
  install.sh [setup|ensure|update|personal|audit] [options]

With no arguments on macOS or Linux, the normal interface is an interactive
Gum workflow after the mandatory platform prerequisites are ready.

Options:
  --shell <fish|zsh|bash>  Set preferred shell (bash is Linux-only)
  --profile <work|home|minimal>  Set device profile preset
  --device-name <name>     Set the platform hostname/computer name
  --downloads-target <path>  Linux: absolute directory for an optional Downloads link
  --git-name <name>        Seed the Git author name
  --git-email <address>    Seed the Git author email
  --enable-<flag>          Enable a feature flag (for example, --enable-zscaler)
  --disable-<flag>         Disable a feature flag (for example, --disable-zscaler)
  --personal               Run the personal layer after foundation
  --non-interactive        Disable all interactive prompts
  --dry-run                Inspect drift and print only required repairs; do not apply them
  --dotfiles-repo <url>    Override dotfiles repository URL
  --dotfiles-dir <path>    Override the local dotfiles checkout path
  --personal-script <path> Override personal bootstrap script path

Profiles are editable presets:
  work     Ben's complete setup plus Zscaler auto-detection
  home     Ben's complete personal setup without Zscaler
  minimal  Neutral baseline for other adopters. The platform prerequisite
           layer, standalone mise, and mise-managed Gum are installed while
           Ben's catalogues start disabled. Device name, Git identity, and
           ~/code are prompted.

Feature flags:
  packages, applications, mise-tools, dotfiles, code-directory,
  downloads-link, git-identity, macos-defaults, remote-access, rosetta,
  shell-default, zscaler

Linux system flags:
  linux-defaults, linux-hostname, linux-default-apps

Granular macOS flags:
  macos-hostname, macos-dock, macos-desktop, macos-default-apps,
  macos-menu-bar, macos-mouse, macos-power, macos-finder,
  macos-screenshots, macos-touch-id

Audit perspectives:
  audit --general          Current-machine inventory only (default)
  audit --profile home     Compare with home, work, or minimal defaults
  audit --expect-state     Compare with the exact last saved bootstrap plan

The current signed-in macOS account is detected and never renamed. Interactive
runs explain every stage and allow all preset choices to be changed before
anything planned is applied. Full Xcode and App Store inventory remain manual.
Git identity is written into a new user-owned ~/.gitconfig; when one already
exists, interactive runs offer replacement and the safe fallback preserves it
with a machine-local identity include.

Repo-local scripts:
  Other/scripts/macos/bootstrap-macos.zsh
  Other/scripts/macos/foundation-macos.zsh
  Other/scripts/macos/personal-bootstrap-macos.zsh
  Other/scripts/macos/audit-macos.zsh
  Other/scripts/linux/bootstrap-linux.sh
  Other/scripts/linux/foundation-linux.sh
  Other/scripts/linux/audit-linux.sh

Examples:
  curl -fsSL https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh | bash
  install.sh
  install.sh setup --shell fish --profile work
  install.sh setup --profile minimal --shell zsh --device-name ada-mac \
    --git-name "Ada Lovelace" --git-email ada@example.com
  install.sh ensure --personal
  install.sh update --dry-run
  install.sh personal --non-interactive --shell zsh
  install.sh setup --dry-run --shell fish --profile work
  install.sh audit
  install.sh audit --profile home
  install.sh audit --profile minimal
  install.sh audit --expect-state
  install.sh audit --section tools
  install.sh audit --json

  # Linux: provide adopter values without the Gum questions
  curl -fsSL https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh \
    | bash -s -- setup --profile home --shell fish --device-name dev-linux \
        --git-name "Ada Lovelace" --git-email ada@example.com --non-interactive

Linux:
  Supports apt distributions (Debian, Ubuntu, Mint, Raspberry Pi OS) and
  pacman distributions (Arch, CachyOS, Manjaro, EndeavourOS). The same
  work/home/minimal presets are editable, and the signed-in account is never
  renamed. Native packages and Flatpak apps are reconciled through mise;
  standalone mise and Gum require no manual prerequisite commands. Use
  audit --general, audit --profile NAME, or audit --expect-state.

Windows:
  Use install.cmd instead.

EOF
}

_flag_name_to_var() {
  local raw="$1"
  local upper
  if [[ "$raw" == macos-* && "$raw" != "macos-defaults" ]]; then
    raw="${raw#macos-}"
    upper="$(echo "$raw" | tr '[:lower:]-' '[:upper:]_')"
    echo "MACOS_${upper}"
    return 0
  fi
  if [[ "$raw" == linux-* && "$raw" != "linux-defaults" ]]; then
    raw="${raw#linux-}"
    upper="$(echo "$raw" | tr '[:lower:]-' '[:upper:]_')"
    echo "LINUX_${upper}"
    return 0
  fi
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
      --device-name)
        [[ $# -ge 2 ]] || fail "--device-name requires a value"
        DEVICE_NAME="$2"
        shift 2
        ;;
      --downloads-target)
        [[ $# -ge 2 ]] || fail "--downloads-target requires a value"
        DOWNLOADS_TARGET="$2"
        _DYNAMIC_FLAGS="${_DYNAMIC_FLAGS:+${_DYNAMIC_FLAGS}$'\n'}ENABLE_DOWNLOADS_LINK=true"
        shift 2
        ;;
      --git-name)
        [[ $# -ge 2 ]] || fail "--git-name requires a value"
        GIT_USER_NAME="$2"
        _DYNAMIC_FLAGS="${_DYNAMIC_FLAGS:+${_DYNAMIC_FLAGS}$'\n'}ENABLE_GIT_IDENTITY=true"
        shift 2
        ;;
      --git-email)
        [[ $# -ge 2 ]] || fail "--git-email requires a value"
        GIT_USER_EMAIL="$2"
        _DYNAMIC_FLAGS="${_DYNAMIC_FLAGS:+${_DYNAMIC_FLAGS}$'\n'}ENABLE_GIT_IDENTITY=true"
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
  export PREFERRED_SHELL
  export DEVICE_PROFILE
  export DEVICE_NAME
  export DOWNLOADS_TARGET
  export GIT_USER_NAME
  export GIT_USER_EMAIL
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
  if [[ -n "$SELF_DIR" ]] \
    && [[ -f "$SELF_DIR/Other/scripts/macos/bootstrap-macos.zsh" ]] \
    && [[ -f "$SELF_DIR/Other/scripts/linux/bootstrap-linux.sh" ]]; then
    printf '%s\n' "$SELF_DIR"
    return 0
  fi

  return 1
}

have_git() {
  local git_path=""
  git_path="$(command -v git 2>/dev/null || true)"
  [[ -n "$git_path" ]] || return 1

  # A factory macOS image exposes /usr/bin/git as an Xcode shim before the
  # Command Line Tools payload exists. `command -v` alone therefore produces a
  # false positive and makes the loader attempt its clone too early.
  if [[ "$(uname -s)" == "Darwin" && "$git_path" == "/usr/bin/git" ]] \
    && ! xcode-select -p >/dev/null 2>&1; then
    return 1
  fi

  bootstrap_git --version >/dev/null 2>&1
}

bootstrap_git() {
  GIT_CONFIG_GLOBAL=/dev/null command git "$@"
}

configure_interactive_input() {
  [[ "$OS" == "macos" || "$OS" == "linux" ]] || return 0
  [[ "$NON_INTERACTIVE" -eq 0 ]] || return 0
  [[ "$MODE" != "audit" ]] || return 0
  [[ -t 0 ]] && return 0

  if { true </dev/tty; } 2>/dev/null; then
    INTERACTIVE_TTY="/dev/tty"
  else
    fail "Interactive bootstrap requires a terminal; use --non-interactive only after prerequisites are already available"
  fi
}

read_from_operator() {
  local prompt="$1"
  if [[ -n "$INTERACTIVE_TTY" ]]; then
    read -r -p "$prompt" </dev/tty
  else
    read -r -p "$prompt"
  fi
}

ensure_macos_repo_prerequisites() {
  [[ "$OS" == "macos" ]] || return 0
  [[ "$MODE" != "audit" ]] || return 0

  # Local and already-cloned entrypoints do not need Git just to start.
  local local_root=""
  if local_root="$(local_repo_root 2>/dev/null)"; then
    return 0
  fi
  if [[ -f "$DOTFILES_DIR/Other/scripts/macos/bootstrap-macos.zsh" \
    && -f "$DOTFILES_DIR/Other/scripts/linux/bootstrap-linux.sh" ]]; then
    return 0
  fi
  if have_git; then
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    display_message "DRY RUN: Command Line Tools would be installed before cloning $DOTFILES_REPO"
    return 0
  fi
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    fail "A fresh Mac requires the interactive Command Line Tools installer before the repository can be cloned"
  fi

  display_message "Installing Apple's Command Line Tools"
  xcode-select --install >/dev/null 2>&1 || true
  echo "The Apple installer is open. Choose Continue, accept the licence, and wait for it to finish."

  while ! xcode-select -p >/dev/null 2>&1; do
    read_from_operator "Press Return after the Command Line Tools installer has completed: "
    if ! xcode-select -p >/dev/null 2>&1; then
      echo "Command Line Tools are not ready yet; finish the Apple installer before continuing."
    fi
  done

  if ! have_git; then
    fail "Command Line Tools completed, but Git is still unavailable"
  fi
  display_message "Command Line Tools and Apple Git are ready"
}

clone_repo_with_git() {
  display_message "Cloning dotfiles repo to $DOTFILES_DIR"
  bootstrap_git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
}

download_repo_archive() {
  [[ "$DOTFILES_REPO" == "$DEFAULT_DOTFILES_REPO" ]] || \
    fail "git is required when --dotfiles-repo is not the default repository"

  local temp_root
  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-install.XXXXXX")"
  local archive_path="$temp_root/dotfiles-main.tar.gz"

  display_message "Downloading temporary dotfiles archive"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$DEFAULT_ARCHIVE_URL" -o "$archive_path"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$archive_path" "$DEFAULT_ARCHIVE_URL"
  else
    fail "Downloading the bootstrap archive requires curl or wget"
  fi
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
    bootstrap_git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    return
  fi

  display_message "WARNING: bootstrap ran from a temporary archive because git is unavailable; dotfiles repo was not persisted"
}

run_macos_entrypoint() {
  local exit_code

  if [[ -z "$MODE" ]]; then
    if [[ -n "$INTERACTIVE_TTY" ]]; then
      /bin/zsh "$RUN_ROOT/Other/scripts/macos/bootstrap-macos.zsh" </dev/tty
    else
      /bin/zsh "$RUN_ROOT/Other/scripts/macos/bootstrap-macos.zsh"
    fi
    exit_code=$?
  elif [[ "$MODE" == "audit" ]]; then
    if [[ ${#AUDIT_ARGS[@]} -gt 0 ]]; then
      /bin/zsh "$RUN_ROOT/Other/scripts/macos/bootstrap-macos.zsh" audit "${AUDIT_ARGS[@]}"
    else
      /bin/zsh "$RUN_ROOT/Other/scripts/macos/bootstrap-macos.zsh" audit
    fi
    exit_code=$?
  elif [[ "$MODE" == "personal" ]]; then
    if [[ -n "$INTERACTIVE_TTY" ]]; then
      /bin/zsh "$RUN_ROOT/Other/scripts/macos/bootstrap-macos.zsh" personal </dev/tty
    else
      /bin/zsh "$RUN_ROOT/Other/scripts/macos/bootstrap-macos.zsh" personal
    fi
    exit_code=$?
  else
    if [[ -n "$INTERACTIVE_TTY" ]]; then
      /bin/zsh "$RUN_ROOT/Other/scripts/macos/bootstrap-macos.zsh" "$MODE" </dev/tty
    else
      /bin/zsh "$RUN_ROOT/Other/scripts/macos/bootstrap-macos.zsh" "$MODE"
    fi
    exit_code=$?
  fi

  maybe_persist_repo_after_archive_run
  exit "$exit_code"
}

parse_args "$@"
OS="$(detect_os)"
if [[ -z "$MODE" && "$OS" != "macos" ]]; then
  MODE="setup"
fi
configure_interactive_input
ensure_macos_repo_prerequisites
ensure_run_root
export_flags

QUIET_ENTRY=0
if [[ "$MODE" == "audit" ]]; then
  if [[ ${#AUDIT_ARGS[@]} -gt 0 ]]; then
    for audit_arg in "${AUDIT_ARGS[@]}"; do
      if [[ "$audit_arg" == "--json" ]]; then
        QUIET_ENTRY=1
        break
      fi
    done
  fi
fi

if [[ "$QUIET_ENTRY" -eq 0 ]]; then
  display_message "Install Entry"
  display_message "OS: $OS | Mode: ${MODE:-interactive}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    display_message "DRY RUN — no changes will be made"
  fi
fi

run_linux_entrypoint() {
  local exit_code
  local -a args=()
  if [[ "$MODE" == "audit" && ${#AUDIT_ARGS[@]} -gt 0 ]]; then
    args=(audit "${AUDIT_ARGS[@]}")
  else
    args=("$MODE")
  fi
  if [[ -n "$INTERACTIVE_TTY" && "$MODE" != "audit" ]]; then
    /bin/bash "$RUN_ROOT/Other/scripts/linux/bootstrap-linux.sh" "${args[@]}" </dev/tty
  else
    /bin/bash "$RUN_ROOT/Other/scripts/linux/bootstrap-linux.sh" "${args[@]}"
  fi
  exit_code=$?
  maybe_persist_repo_after_archive_run
  exit "$exit_code"
}

case "$OS" in
  macos)
    run_macos_entrypoint
    ;;
  windows)
    fail "Windows detected. Use install.cmd instead."
    ;;
  linux)
    run_linux_entrypoint
    ;;
  *)
    fail "Unsupported OS: $(uname -s)"
    ;;
esac
