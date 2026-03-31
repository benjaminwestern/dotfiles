#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  bootstrap-macos.zsh [foundation|audit|personal] [args]

Targets:
  foundation  Runs foundation-macos.zsh
  audit       Runs audit-macos.zsh
  personal    Runs personal-bootstrap-macos.zsh

Convenience:
  If the first argument is setup, ensure, or update, the wrapper
  treats it as a foundation mode and dispatches to foundation-macos.zsh.

Examples:
  ./Other/scripts/bootstrap-macos.zsh foundation setup --shell fish --profile work
  ./Other/scripts/bootstrap-macos.zsh ensure --shell fish --profile work
  ./Other/scripts/bootstrap-macos.zsh audit --json
  ./Other/scripts/bootstrap-macos.zsh personal --dry-run
EOF
}

if [[ $# -eq 0 ]]; then
  exec /bin/zsh "$SCRIPT_DIR/foundation-macos.zsh"
fi

case "$1" in
  -h|--help|help)
    usage
    exit 0
    ;;
  foundation)
    shift
    exec /bin/zsh "$SCRIPT_DIR/foundation-macos.zsh" "$@"
    ;;
  audit)
    shift
    exec /bin/zsh "$SCRIPT_DIR/audit-macos.zsh" "$@"
    ;;
  personal)
    shift
    exec /bin/zsh "$SCRIPT_DIR/personal-bootstrap-macos.zsh" "$@"
    ;;
  setup|ensure|update)
    exec /bin/zsh "$SCRIPT_DIR/foundation-macos.zsh" "$@"
    ;;
  *)
    printf 'Unknown bootstrap-macos target or mode: %s\n\n' "$1" >&2
    usage >&2
    exit 1
    ;;
esac
