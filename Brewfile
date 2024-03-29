# Taps
tap "hashicorp/tap"
tap "homebrew/bundle"
tap "homebrew/cask-fonts"
tap "homebrew/services"
tap "warrensbox/tap"
tap "microsoft/mssql-release" 

# Tools
brew "warrensbox/tap/tfswitch"
brew "mssql-tools18"
brew "msodbcsql18"
brew "gh"
brew "git"
brew "gitleaks"
brew "htop"
brew "curl"
brew "tree"
brew "lazydocker"
brew "lazygit"
brew "neofetch"
brew "neovim"
brew "pngpaste" # Required for neovim clipboard
brew "ripgrep" # Required for fzf
brew "tmux"
brew "fish"
brew "fzf"
brew "fisher"
brew "jq"
brew "zoxide" 
brew "stow" # Required for dotfiles
brew "mas" # Mac App Store CLI
brew "deno" # Required for peek.nvim 

# Programming Languages
brew "go"
brew "node"
brew "python"

# Core Casks
cask "font-jetbrains-mono-nerd-font"
cask "alacritty"
cask "google-chrome"
cask "obsidian"

# Extra Casks
if ENV['HOMEBREW_EXTRA_CASKS']
	cask "google-drive" 
	cask "docker"
	cask "dbngin"
	cask "tableplus"
	cask "google-cloud-sdk"
	cask "rode-central"
	cask "rode-connect"
	cask "logi-options-plus"
end

# MAS Apps
if ENV['HOMEBREW_MAS_APPS']
	mas "Maccy", id: 1527619437
	mas "Magnet", id: 441258766
	mas "Wireguard", id: 1451685025
	mas "Microsoft Remote Desktop", id: 1295203466
	mas "DaisyDisk", id: 411643860
	mas "Cyberduck", id: 409222199
	mas "Final Cut Pro", id: 424389933
	mas "TripMode", id: 1513400665
end
