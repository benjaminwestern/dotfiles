#!/bin/bash
# =============================================================================
# bootstrap-debian.sh -- Debian / Raspberry Pi OS bootstrap entrypoint
#
# Dispatches to foundation-debian.sh for the actual work.  Mirrors the
# pattern of bootstrap-macos.zsh: foundation, audit, and personal targets.
#
# Usage:
#   ./bootstrap-debian.sh foundation setup
#   ./bootstrap-debian.sh ensure
#   ./bootstrap-debian.sh audit
#
# The "personal" target is a no-op placeholder until a personal layer
# is implemented for Linux.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage:
  bootstrap-debian.sh [foundation|ensure|update|audit|personal] [args]

Targets:
  foundation  Runs foundation-debian.sh (apt packages, mise, configs)
  audit       Placeholder for future audit work
  personal    Placeholder for future personal-layer work

Convenience:
  setup, ensure, and update are aliased to foundation with the same mode.

Examples:
  ./Other/scripts/linux/bootstrap-debian.sh foundation setup
  ./Other/scripts/linux/bootstrap-debian.sh ensure
  ./Other/scripts/linux/bootstrap-debian.sh update --dry-run
EOF
}

if [[ $# -eq 0 ]]; then
  exec bash "$SCRIPT_DIR/foundation-debian.sh" setup
fi

case "$1" in
  -h|--help|help)
    usage
    exit 0
    ;;
  foundation)
    shift
    exec bash "$SCRIPT_DIR/foundation-debian.sh" "${1:-setup}"
    ;;
  audit|personal)
    note "Linux $1 layer is not yet implemented (foundation only)."
    ;;
  setup|ensure|update)
    exec bash "$SCRIPT_DIR/foundation-debian.sh" "$1"
    ;;
  *)
    printf 'Unknown bootstrap-debian target or mode: %s\n\n' "$1" >&2
    usage >&2
    exit 1
    ;;
esac
