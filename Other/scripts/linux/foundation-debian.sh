#!/usr/bin/env bash
# Compatibility entrypoint retained for old bookmarks and remote commands.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "$SCRIPT_DIR/foundation-linux.sh" "$@"
