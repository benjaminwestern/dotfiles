# Taps
tap "hashicorp/tap"
tap "homebrew/bundle"
tap "homebrew/services"
tap "warrensbox/tap"
tap "tfverch/tfvc"
tap "microsoft/mssql-release" 
tap "julien-cpsn/atac"

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
brew "tfverch/tfvc/tfvc" # Terraform Version checker for Modules, providers and resources
brew "tokei" # Information about your git repo
brew "zoxide" # Smarter Change Directory (cd)
brew "gh" # Github CLI
brew "git" # Git CLI

# TUI Tools
brew "lazygit"
brew "atac" # Postman like TUI
brew "htop"
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

# Documentation Management
brew "vale" # Linting for Markdown
brew "pandoc" # Document Converter
cask "basictex" # Required for pandoc to export PDF

# Programming Languages
brew "go"
brew "node"
brew "deno" # Required for peek.nvim 
brew "python"
brew "terraform", link: false
cask "flutter"

# Version Management
brew "nvm"
brew "warrensbox/tap/tfswitch"
cask "anaconda"

# Standard Apps
cask "ghostty"
cask "google-cloud-sdk"
cask "google-chrome"
cask "visual-studio-code"
cask "docker"
cask "maccy"
cask "rectangle"
cask "slack"
cask "microsoft-teams"

if ENV['HOMEBREW_HOME_APPS'] == "true"
  brew "mas" # Mac store manager

  # Home Apps
  cask "tableplus"
  cask "discord"
  cask "dbngin"

  # Mac App Store Apps
  mas "Maccy", id: 1527619437
  mas "DaisyDisk", id: 411643860
  mas "Final Cut Pro", id: 424389933
end
