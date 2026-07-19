#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<'EOF'
Usage: bootstrap-linux.sh [foundation|audit|personal|setup|ensure|update] [args]

With no arguments, runs the interactive Linux setup workflow.

Targets:
  foundation  Reconcile baseline, packages, tools, settings, and personal stages
  audit       Read-only general/profile/saved-plan audit
  personal    Reconcile the selected personal stages through the same safe engine

Examples:
  ./Other/scripts/linux/bootstrap-linux.sh
  ./Other/scripts/linux/bootstrap-linux.sh setup --profile minimal
  ./Other/scripts/linux/bootstrap-linux.sh ensure --profile home --dry-run
  ./Other/scripts/linux/bootstrap-linux.sh audit --general
  ./Other/scripts/linux/bootstrap-linux.sh audit --profile work
  ./Other/scripts/linux/bootstrap-linux.sh audit --expect-state --json
EOF
}

if [[ $# -eq 0 ]]; then
  exec bash "$SCRIPT_DIR/foundation-linux.sh" setup
fi

case "$1" in
  -h|--help|help) usage ;;
  foundation) shift; exec bash "$SCRIPT_DIR/foundation-linux.sh" "$@" ;;
  audit) shift; exec bash "$SCRIPT_DIR/audit-linux.sh" "$@" ;;
  personal) shift; exec bash "$SCRIPT_DIR/foundation-linux.sh" personal "$@" ;;
  setup|ensure|update) exec bash "$SCRIPT_DIR/foundation-linux.sh" "$@" ;;
  *) printf 'Unknown Linux target or mode: %s\n\n' "$1" >&2; usage >&2; exit 1 ;;
esac
