#!/bin/bash
set -euo pipefail

# macos-defaults.sh
# Configures macOS system defaults for a fresh machine setup.
# Sets hostname, Dock behaviour, battery menu bar, Finder preferences,
# mouse settings, power/sleep options, and screenshot format.
#
# Usage: ./macos-defaults.sh [computer-name]
#   computer-name  defaults to "macbook-pro" if omitted.

# Assign input parameters to variables or use default values
SCRIPT_COMPUTER_NAME="${1:-macbook-pro}"

###############################################################################
# Hostname                                                                    #
###############################################################################

sudo scutil --set HostName "$SCRIPT_COMPUTER_NAME"
sudo scutil --set ComputerName "$SCRIPT_COMPUTER_NAME"
sudo scutil --set LocalHostName "$SCRIPT_COMPUTER_NAME"

###############################################################################
# Dock                                                                        #
###############################################################################

# Move Dock to the left
defaults write com.apple.dock orientation left

# Enable Dock auto-hide
defaults write com.apple.dock autohide -bool true

# Disable Dock auto-hide delay and animation
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -int 0

# Purge all (default) app icons from the Dock
defaults delete com.apple.dock persistent-apps

# Purge all non-persistent app icons from the Dock
defaults delete com.apple.dock persistent-others

# Remove Recents from the Dock
defaults write com.apple.dock show-recents -bool false

# Restart Dock to apply all changes
killall Dock

###############################################################################
# Battery                                                                     #
###############################################################################

# Show battery percentage on the menu bar
defaults write com.apple.menuextra.battery ShowPercent YES

###############################################################################
# Mouse                                                                       #
###############################################################################

# Disable mouse acceleration
defaults write .GlobalPreferences com.apple.mouse.scaling -1

###############################################################################
# Power / Sleep                                                               #
###############################################################################

# Sleep options (display, disk, and system) in minutes
sudo pmset -a displaysleep 10
sudo pmset -a disksleep 10
sudo pmset -a sleep 20

###############################################################################
# Finder                                                                      #
###############################################################################

# Show Finder path bar
defaults write com.apple.finder ShowPathbar -bool true

# Show Finder status bar
defaults write com.apple.finder ShowStatusBar -bool true

# Show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show the ~/Library folder
chflags nohidden ~/Library

# Show the /Volumes folder
sudo chflags nohidden /Volumes

# Disable the warning when changing a file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Disable the warning before emptying the Trash
defaults write com.apple.finder WarnOnEmptyTrash -bool false

###############################################################################
# Screenshots                                                                 #
###############################################################################

# Take screenshots as png (available: png, jpg, tiff, bmp, gif, pdf, none)
defaults write com.apple.screencapture type png
