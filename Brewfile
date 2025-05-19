# CLI Tools
brew "stow" # Required for dotfiles, creates symlinks to important config
brew "tree" # Print folder layout
brew "tmux" # Terminal multiplexer
brew "tpm" # Tmux plugin manager
brew "fish" # Fish Shell
brew "fisher" # Plugin manager for the Fish shell
brew "neovim" # Neovim text editor
brew "macchina" # System Information like neofetch

# Neovim Setup
brew "luarocks" # Required for rest.nvim
brew "wget" # Required for neovim mason.nvim
brew "pngpaste" # Required for neovim clipboard

# Standard Apps
cask "ghostty"
cask "google-chrome"
cask "docker"
cask "maccy"
cask "rectangle"
cask "dbngin"
cask "bruno"

if ENV['HOMEBREW_WORK_APPS'] == "true"
  cask "microsoft-edge"
  cask "microsoft-teams"
  cask "visual-studio-code"
end

if ENV['HOMEBREW_HOME_APPS'] == "true"
  # Taps
  tap "microsoft/mssql-release"

  # Database Drivers
  brew "mssql-tools18"
  brew "msodbcsql18"

  cask "tableplus"
  cask "google-drive"
  brew "mas" # Mac store manager

  # Mac App Store Apps
  mas "Maccy", id: 1527619437
  mas "DaisyDisk", id: 411643860
  mas "Final Cut Pro", id: 424389933
end
