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
brew "tokei" # Information about your git repo
brew "lazydocker"
brew "lazygit"
brew "neofetch"
brew "neovim"
brew "pngpaste" # Required for neovim clipboard
brew "ripgrep" # Required for fzf
brew "tmux" # zellij
brew "fish"
brew "fzf"
brew "fisher"
brew "jq"
brew "yq"
brew "zoxide" 
brew "luarocks" # Required for rest.nvim
brew "fd" # Required for telescope select_env
brew "stow" # Required for dotfiles
brew "deno" # Required for peek.nvim 
brew "docker-compose"

# Programming Languages
brew "go"
brew "node"
brew "python"

# Core Casks
cask "font-jetbrains-mono-nerd-font"
cask "alacritty"
cask "google-chrome"

# Standard Apps
cask "google-drive" 
cask "google-cloud-sdk"
cask "docker"

# Other Apps
brew "youtube-dl"
cask "ngrok"
brew "ffmpeg"
brew "cmake"
brew "telnet"
brew "sqlc"

if ENV['HOMEBREW_HOME_APPS'] == "true"
  # Home Apps
  cask "discord"
  cask "dbngin"
  cask "tableplus"
  cask "rode-central"
  cask "rode-connect"
  cask "logi-options-plus"

  # Mac App Store CLI
  brew "mas" 

  # Mac App Store Apps
  mas "Maccy", id: 1527619437
  mas "Magnet", id: 441258766
  mas "Wireguard", id: 1451685025
  mas "Microsoft Remote Desktop", id: 1295203466
  mas "DaisyDisk", id: 411643860
  mas "Cyberduck", id: 409222199
  mas "Final Cut Pro", id: 424389933
  mas "TripMode", id: 1513400665
  mas "Exporter", id: 1099120373
end

if ENV['HOMEBREW_WORK_APPS'] == "true"
  # Work Apps
  cask "maccy"
  cask "rectangle"
  cask "slack"
end
