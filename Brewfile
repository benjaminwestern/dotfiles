#Taps
tap "hashicorp/tap"
tap "homebrew/bundle"
tap "homebrew/services"
tap "warrensbox/tap"
tap "tfverch/tfvc"
tap "microsoft/mssql-release" 

# Tools
brew "mssql-tools18"
brew "msodbcsql18"
brew "gh"
brew "git"
brew "gcc" # GNU compiler collection
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
brew "docker-compose"
brew "tfverch/tfvc/tfvc" # Terraform Version checker for Modules, providers and resources
brew "terragrunt"

# Programming Languages
brew "go"
brew "node"
brew "deno" # Required for peek.nvim 
brew "python"

# Version Management
brew "pyenv"
brew "nvm"
brew "warrensbox/tap/tfswitch"

# Core Casks
cask "font-jetbrains-mono-nerd-font"
cask "alacritty"
cask "anaconda"

# Standard Apps
cask "google-cloud-sdk"
cask "docker"
cask "postman"
cask "obsidian"
cask "dbngin"

# Other Apps
brew "youtube-dl"
brew "ffmpeg"
brew "cmake"
brew "telnet"
brew "sqlc"

if ENV['HOMEBREW_HOME_APPS'] == "true"
  # Home Apps
  cask "tableplus"
  cask "discord"
  cask "rode-central"
  cask "rode-connect"
  cask "logi-options-plus"
  cask "visual-studio-code"

  # Mac App Store CLI
  brew "mas" 

  # Mac App Store Apps
  mas "Maccy", id: 1527619437
  mas "DaisyDisk", id: 411643860
  mas "Final Cut Pro", id: 424389933
end

if ENV['HOMEBREW_WORK_APPS'] == "true"
  # Work Apps
  cask "maccy"
  cask "slack"
end
