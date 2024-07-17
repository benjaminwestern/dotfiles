# Assign input parameters to variables or use default values
SCRIPT_COMPUTER_NAME="${1:-macbook-pro}"
SCRIPT_USER_NAME="${2:-Benjamin Western}"
SCRIPT_USER_EMAIL="${3:-code@benjaminwestern.io}"

# Update hostname:
sudo scutil --set HostName $SCRIPT_COMPUTER_NAME
sudo scutil --set ComputerName $SCRIPT_COMPUTER_NAME
sudo scutil --set LocalHostName $SCRIPT_COMPUTER_NAME

# Move Dock to the left:
defaults write com.apple.dock orientation left; killall Dock

# Enable Dock auto-hide:
defaults write com.apple.dock autohide -bool true; killall Dock

# Disable Dock slow auto-hide:
defaults write com.apple.dock autohide-delay -float 0; killall dock 
defaults write com.apple.dock autohide-time-modifier -int 0; killall Dock

# Purge all (default) app icons from the Dock:
defaults delete com.apple.dock persistent-apps; killall Dock

# Purge all non-persistent app icons from the Dock:
defaults delete com.apple.dock persistent-others; killall Dock

# Remove Recents from the Dock:
defaults write com.apple.dock show-recents -bool false; killall Dock

# Show Battery Percentage on Taskbar:
defaults write com.apple.menuextra.battery ShowPercent YES
https://github.com/pawelgrzybek/dotfiles/blob/master/setup-brew.sh

# Add persistent app icons to the Dock:
defaults write com.apple.dock persistent-apps -array-add '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>/Applications/Google Chrome.app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>'; killall Dock
defaults write com.apple.dock persistent-apps -array-add '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>/Applications/Alacritty.app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>'; killall Dock
defaults write com.apple.dock persistent-apps -array-add '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>/Applications/Obsidian.app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>'; killall Dock
defaults write com.apple.dock persistent-apps -array-add '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>/Applications/Safari.app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>'; killall Dock

# Disable mouse acceleration:
defaults write .GlobalPreferences com.apple.mouse.scaling -1

# Power Options:
# Sleep options (Display, Disk and System) in minutes
sudo pmset -a displaysleep 10
sudo pmset -a disksleep 10
sudo pmset -a sleep 20

# Show finder path bar:
defaults write com.apple.finder ShowPathbar -bool true

# Show finder status bar:
defaults write com.apple.finder ShowStatusBar -bool true

# Show all filename extensions:
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show the ~/Library folder:
chflags nohidden ~/Library

# Show the /Volumes folder:
sudo chflags nohidden /Volumes

# Disable the warning when changing a file extension:
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Disable the warning before emptying the Trash:
defaults write com.apple.finder WarnOnEmptyTrash -bool false

# Take screenshots as png:
# Available Types: png, jpg, tiff, bmp, gif, pdf, or none
defaults write com.apple.screencapture type png 

# Setup Git Config
git config --global user.name $SCRIPT_USER_NAME 
git config --global user.email $SCRIPT_USER_EMAIL 
git config --global init.defaultBranch main # Set default branch to main
git config --global color.ui auto # Enable color in terminal
git config --global push.autoSetupRemote true # Enable auto push with switched branches
git config --global pull.rebase false # Disable auto rebase on pull
