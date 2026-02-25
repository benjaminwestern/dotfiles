#!/bin/bash

# macOS Bootstrap Script
# Sets up a new macOS machine from 0 to fully functional work environment
# Usage: ./macos-bootstrap.sh [computer_name]

set -euo pipefail

# === Configuration ===
SCRIPT_COMPUTER_NAME="${1:-macbook-pro}"
DOTFILES_REPO="https://github.com/benjaminwestern/dotfiles"
DOTFILES_DIR="$HOME/.dotfiles"

# === Helper Functions ===
function display_message() {
  echo -e "\n>>> $1 <<<\n"
}

function check_exit_status() {
  if [ $? -ne 0 ]; then
    display_message "ERROR: $1 failed. Check logs above."
    exit 1
  fi
}

function command_exists() {
  command -v "$1" &> /dev/null
}

# === Main Setup ===
display_message "Starting macOS Bootstrap for $SCRIPT_COMPUTER_NAME"

# 1. Install Xcode Command Line Tools
display_message "Step 1: Checking Xcode Command Line Tools"
if ! xcode-select -p &> /dev/null; then
  display_message "Installing Xcode Command Line Tools..."
  xcode-select --install
  display_message "Please complete the Xcode Command Line Tools installation dialog, then re-run this script."
  exit 0
fi
display_message "Xcode Command Line Tools already installed"

# 2. Install Homebrew
display_message "Step 2: Checking Homebrew"
if ! command_exists brew; then
  display_message "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  
  # Add Homebrew to PATH for Apple Silicon
  if [ -d "/opt/homebrew/bin" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
  fi
  check_exit_status "Homebrew installation"
fi
display_message "Homebrew ready: $(brew --version | head -1)"

# 3. Clone dotfiles repository
display_message "Step 3: Cloning dotfiles repository"
if [ -d "$DOTFILES_DIR" ]; then
  display_message "Dotfiles already exist at $DOTFILES_DIR, pulling latest..."
  cd "$DOTFILES_DIR" && git pull
else
  display_message "Cloning dotfiles from $DOTFILES_REPO..."
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  check_exit_status "Git clone"
fi

# 4. Convert git remote from HTTPS to SSH
display_message "Step 4: Converting git remote to SSH"
cd "$DOTFILES_DIR"
if git remote -v | grep -q "https://github.com"; then
  git remote set-url origin "git@github.com:benjaminwestern/dotfiles.git"
  display_message "Git remote converted to SSH"
else
  display_message "Git remote already using SSH or not HTTPS"
fi

# 5. Install Homebrew packages
display_message "Step 5: Installing Homebrew packages"
brew bundle --file="$DOTFILES_DIR/Configs/brew/Brewfile"
check_exit_status "Brew bundle"

# 6. Add fish to shells and set as default
display_message "Step 6: Setting up Fish shell"
FISH_PATH="/opt/homebrew/bin/fish"
if [ ! -f "$FISH_PATH" ]; then
  FISH_PATH="/usr/local/bin/fish"  # Intel Mac fallback
fi

if ! grep -q "$FISH_PATH" /etc/shells; then
  display_message "Adding fish to /etc/shells..."
  sudo sh -c "echo $FISH_PATH >> /etc/shells"
fi

if [ "$SHELL" != "$FISH_PATH" ]; then
  display_message "Setting fish as default shell..."
  chsh -s "$FISH_PATH"
  display_message "Shell changed to fish (will take effect after login)"
else
  display_message "Fish is already the default shell"
fi

# 7. Pre-create directories to ensure tuckr symlinks files, not entire directories
display_message "Step 7: Pre-creating directories for safe symlinking"
# Create .ssh directory so tuckr symlinks individual files (config) rather than the whole dir
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
display_message "Created ~/.ssh/ (permissions 700)"

# Create .config directory so tuckr symlinks subdirectories (nvim, fish, mise) rather than the root
mkdir -p "$HOME/.config"
display_message "Created ~/.config/"

# 8. Symlink dotfiles with tuckr
display_message "Step 8: Symlinking dotfiles with tuckr"
if command_exists tuckr; then
  cd "$DOTFILES_DIR"
  tuckr add \*
  check_exit_status "Tuckr symlink"
  display_message "Dotfiles symlinked successfully"
else
  display_message "WARNING: tuckr not found in PATH after brew install"
  exit 1
fi

# 9. Install Mise
display_message "Step 9: Installing Mise"
if ! command_exists mise; then
  curl https://mise.run | sh
  check_exit_status "Mise installation"
  
  # Activate mise for current shell session
  export PATH="$HOME/.local/bin:$PATH"
  eval "$(mise activate bash)"
fi
display_message "Mise ready: $(mise --version)"

# 10. Install all mise tools
display_message "Step 10: Installing Mise tools (languages, dev tools, etc.)"
mise up
check_exit_status "Mise tools installation"

# 11. Install Rosetta (for Intel binaries on Apple Silicon)
display_message "Step 11: Checking Rosetta"
if [[ "$(uname -m)" == "arm64" ]]; then
  if ! /usr/bin/pgrep -q "oahd"; then
    display_message "Installing Rosetta 2..."
    /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    check_exit_status "Rosetta installation"
  else
    display_message "Rosetta 2 already installed"
  fi
else
  display_message "Intel Mac detected, Rosetta not needed"
fi

# 12. Apply macOS defaults
display_message "Step 12: Applying macOS system defaults"
"$DOTFILES_DIR/Other/scripts/macos-defaults.sh" "$SCRIPT_COMPUTER_NAME"
check_exit_status "macOS defaults"

# 13. Setup complete message
display_message "Bootstrap Complete!"
echo ""
echo "Next steps:"
echo "  1. Restart your terminal (or run: exec $FISH_PATH)"
echo "  2. Run 'mise doctor' to verify setup"
echo "  3. Some macOS changes require a system restart"
echo ""
echo "Your system is now configured as: $SCRIPT_COMPUTER_NAME"
echo ""
