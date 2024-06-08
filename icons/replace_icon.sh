# Source of icons: https://dribbble.com/shots/6361500-Alacritty-Terminal-Icon

cp ~/dotfiles/icons/alacritty.icns /Applications/Alacritty.app/Contents/Resources/alacritty.icns
touch /Applications/Alacritty.app  # Triggers the system to update
killall Dock  # Restarts the Dock 
