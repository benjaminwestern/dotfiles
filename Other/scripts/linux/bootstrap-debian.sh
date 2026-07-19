#!/usr/bin/env bash
# Compatibility entrypoint. The generic Linux bootstrap now detects apt versus
# pacman and supports Debian, Ubuntu, Mint, Arch, CachyOS, and derivatives.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "$SCRIPT_DIR/bootstrap-linux.sh" "$@"
