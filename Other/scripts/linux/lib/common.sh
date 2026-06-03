#!/bin/bash
# =============================================================================
# common.sh -- Shared utilities for Linux/Debian bootstrap scripts
#
# Provides status-pass/fix/skip/fail reporting, dry-run gating, and
# package detection helpers.  Kept simpler than the macOS common.zsh
# because the Debian bootstrap targets a narrower surface (headless Pi /
# server) and does not need gum-powered UI, state-file persistence, or
# the full flag-resolution engine.
# =============================================================================

set -euo pipefail

# -- Colour output (safe for dumb terminals) --------------------------------
if [[ -t 1 ]]; then
  _BOLD="\033[1m"
  _GREEN="\033[32m"
  _YELLOW="\033[33m"
  _BLUE="\033[34m"
  _RED="\033[31m"
  _CYAN="\033[36m"
  _RESET="\033[0m"
else
  _BOLD="" _GREEN="" _YELLOW="" _BLUE="" _RED="" _CYAN="" _RESET=""
fi

# -- Global state ----------------------------------------------------------
DRY_RUN="${DRY_RUN:-0}"
PASS_COUNT=0
FIX_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

# -- Helpers ---------------------------------------------------------------

dry_run_active() { [[ "$DRY_RUN" == "1" ]]; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# -- Status output ---------------------------------------------------------

status_pass() {
  local label="$1" detail="${2:-}"
  PASS_COUNT=$((PASS_COUNT + 1))
  printf "${_GREEN}✓${_RESET} ${_BOLD}%s${_RESET} %s\n" "$label" "$detail"
}

status_fix() {
  local label="$1" detail="${2:-}"
  FIX_COUNT=$((FIX_COUNT + 1))
  printf "${_YELLOW}→${_RESET} ${_BOLD}%s${_RESET} %s\n" "$label" "$detail"
}

status_skip() {
  local label="$1" detail="${2:-}"
  SKIP_COUNT=$((SKIP_COUNT + 1))
  printf "${_CYAN}○${_RESET} ${_BOLD}%s${_RESET} %s\n" "$label" "$detail"
}

status_fail() {
  local label="$1" detail="${2:-}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "${_RED}✗${_RESET} ${_BOLD}%s${_RESET} %s\n" "$label" "$detail"
}

status_summary() {
  local title="${1:-Bootstrap}"
  echo ""
  printf "${_BOLD}%s summary:${_RESET} " "$title"
  printf "${_GREEN}%d pass${_RESET}, " "$PASS_COUNT"
  printf "${_YELLOW}%d fix${_RESET}, " "$FIX_COUNT"
  printf "${_CYAN}%d skip${_RESET}, " "$SKIP_COUNT"
  printf "${_RED}%d fail${_RESET}\n" "$FAIL_COUNT"
}

success() {
  echo ""
  printf "${_GREEN}${_BOLD}%s${_RESET}\n" "${1:-Done.}"
}

fail() {
  printf "${_RED}ERROR: %s${_RESET}\n" "$1" >&2
  exit 1
}

note() {
  printf "${_BLUE}→ %s${_RESET}\n" "$1"
}

# -- Dry-run wrapper -------------------------------------------------------

run_or_dry() {
  if dry_run_active; then
    printf "${_CYAN}[dry-run]${_RESET} %s\n" "$*"
  else
    "$@"
  fi
}

dry_run_log() {
  printf "${_CYAN}[dry-run]${_RESET} %s\n" "$1"
}

# -- Package detection -----------------------------------------------------

apt_pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}
