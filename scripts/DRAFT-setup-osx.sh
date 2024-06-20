#!/bin/bash

# Function for user-friendly messages 
function display_message() {
  echo -e "\n*** $1 ***\n"
}

# Function to check exit codes and handle errors gracefully
function check_exit_status() {
  if [ $? -ne 0 ]; then
    display_message "Error: $1 failed. Please check the logs for details."
    exit 1
  fi
}

# === Device Setup ===
display_message "Beginning device setup"

# 0. Get device variables
SCRIPT_COMPUTER_NAME="${1:-macbook-pro}"
SCRIPT_USER_NAME="${2:-Benjamin Western}"
SCRIPT_USER_EMAIL="${3:-code@benjaminwestern.io}"

# 1. Install Xcode Command Line Tools
display_message "Checking if Xcode Command Line Tools are installed"
if ! xcode-select -p &> /dev/null; then
  display_message "Xcode Command Line Tools are not installed. Installing..." 
  xcode-select --install
  check_exit_status "Xcode Command Line Tools installation"
fi

# 2. Install Homebrew
# Check if Homebrew is installed
# If not, install it
if ! command -v brew &> /dev/null; then
  display_message "Homebrew is not installed. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
  check_exit_status "Homebrew installation"
fi

# 3. Clone this repository (Add your actual repository URL)
display_message "Checking if dotfiles repository is already cloned"
if [ -d ~/dotfiles ]; then
  display_message "Dotfiles repository already exists. Skipping cloning."
  cd ~/dotfiles
else
  display_message "Cloning dotfiles repository"
  cd ~ && git clone https://github.com/benjaminwestern/dotfiles && cd ~/dotfiles
  check_exit_status "Cloning repository"
fi

# 4. Install Brew Bundle
display_message "Installing/Updating Brew Bundles"
brew bundle
check_exit_status "Brew Bundle installation"

# 5. Stow the dotfiles to the home directory
display_message "Stowing/Re-Stowing Files"
stow .
check_exit_status "Stowing files"

# 6. Set up fish to be the default shell
display_message "Checking if fish shell is the default shell"
if [ $SHELL != $(which fish) ]; then
  display_message "Fish shell is not the default shell. Setting as default shell..."
  sudo sh -c 'echo $(which fish) >> /etc/shells'
  chsh -s $(which fish)
  check_exit_status "Setting up fish shell"
else
  display_message "Fish shell is already the default shell. Skipping setup."
fi

# 7. Set up macOS defaults
display_message "Setting up macOS defaults"
~/dotfiles/scripts/macos-defaults.sh $SCRIPT_COMPUTER_NAME $SCRIPT_USER_NAME $SCRIPT_USER_EMAIL 
check_exit_status "macOS defaults setup"

# 8. Enable rosseta
display_message "Checking if Rosetta is installed"
if ! /usr/sbin/softwareupdate --list | grep -q "Rosetta"; then
  display_message "Rosetta is not installed. Installing..."
  /usr/sbin/softwareupdate --install-rosetta --agree-to-license
  check_exit_status "Rosetta installation"
else
  display_message "Rosetta is already installed. Skipping installation."
fi

# Done
display_message "Device setup complete! You may need to restart your computer for all changes to take effect."
