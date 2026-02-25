#!/bin/bash

# Universal Bootstrap Script
# Detects OS and calls the appropriate bootstrap script
# Usage: ./bootstrap.sh [computer_name]

set -euo pipefail

# === Configuration ===
SCRIPT_COMPUTER_NAME="${1:-$(hostname -s)}"
DOTFILES_DIR="$HOME/.dotfiles"

# === Helper Functions ===
function display_message() {
  echo -e "\n>>> $1 <<<\n"
}

function detect_os() {
  case "$(uname -s)" in
    Darwin)
      echo "macos"
      ;;
    Linux)
      echo "linux"
      ;;
    *)
      echo "unsupported"
      ;;
  esac
}

# === Main ===
display_message "Universal Bootstrap Script"
display_message "Detecting operating system..."

OS=$(detect_os)

case "$OS" in
  macos)
    display_message "macOS detected - Starting macOS bootstrap"
    if [ -f "$DOTFILES_DIR/Other/scripts/macos-bootstrap.sh" ]; then
      exec "$DOTFILES_DIR/Other/scripts/macos-bootstrap.sh" "$SCRIPT_COMPUTER_NAME"
    else
      display_message "ERROR: macOS bootstrap script not found at $DOTFILES_DIR/Other/scripts/macos-bootstrap.sh"
      exit 1
    fi
    ;;
  
  linux)
    display_message "Linux detected"
    if [ -f "$DOTFILES_DIR/Other/scripts/linux-bootstrap.sh" ]; then
      display_message "Starting Linux bootstrap"
      exec "$DOTFILES_DIR/Other/scripts/linux-bootstrap.sh" "$SCRIPT_COMPUTER_NAME"
    else
      display_message "ERROR: Linux bootstrap not yet implemented"
      display_message "To set up Linux manually:"
      echo "  1. Install your package manager (apt, dnf, pacman, etc.)"
      echo "  2. Install git, fish, and basic tools"
      echo "  3. Clone: git clone https://github.com/benjaminwestern/.dotfiles ~/.dotfiles"
      echo "  4. Manually symlink configs or use tuckr if available"
      echo "  5. Install mise: curl https://mise.run | sh"
      echo "  6. Run: mise up"
      exit 1
    fi
    ;;
  
  unsupported)
    display_message "ERROR: Unsupported operating system: $(uname -s)"
    exit 1
    ;;
esac
