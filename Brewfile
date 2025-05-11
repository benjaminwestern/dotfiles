# Taps
tap "hashicorp/tap"
tap "homebrew/bundle"
tap "homebrew/services"
tap "microsoft/mssql-release"

# Database Drivers
brew "mssql-tools18"
brew "msodbcsql18"

# CLI Tools
brew "stow" # Required for dotfiles, creates symlinks to important config
brew "jq" # CLI JSON Processor
brew "yq" # CLI YAML Processor
brew "tree" # Print folder layout
brew "curl" # Make HTTP requests from terminal
brew "gitleaks" # Scan Git Commits for Secrets
brew "tokei" # Information about your git repo
brew "zoxide" # Smarter Change Directory (cd)
brew "gh" # Github CLI
brew "git" # Git CLI
brew "pipx" # Python non-requirements.txt python packages
brew "tmux"

# TUI Tools
brew "lazygit"
brew "neovim"
brew "macchina" # System Information like neofetch

# Neovim Setup
brew "ripgrep" # Required for fzf
brew "fzf" # A command-line fuzzy finder
brew "luarocks" # Required for rest.nvim
brew "fd" # Required for telescope select_env
brew "pngpaste" # Required for neovim clipboard

# Fish terminal
brew "fish" # Fish Shell
brew "fisher" # Plugin manager for the Fish shell

# Standard Apps
cask "ghostty"
cask "google-cloud-sdk"
cask "google-chrome"
cask "docker"
cask "maccy"
cask "rectangle"
cask "dbngin"
cask "bruno"

if ENV['HOMEBREW_HOME_APPS'] == "true"
  # Home Apps
  cask "tableplus"
  brew "mas" # Mac store manager

  # Mac App Store Apps
  mas "Maccy", id: 1527619437
  mas "DaisyDisk", id: 411643860
  mas "Final Cut Pro", id: 424389933
end
