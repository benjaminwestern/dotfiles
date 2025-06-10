# Device Setup
This repository contains the dotfiles and scripts to setup a new device. The dotfiles are managed using GNU Stow.
The neovim components of this repository are heavily taken from [Kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)

## Installation
1. Install Xcode
```bash
xcode-select --install
```

2. Install homebrew & Mise
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

curl https://mise.run | sh
```

3. Clone this repository
```bash
git clone https://github.com/benjaminwestern/dotfiles ~/.dotfiles
```

4. Install Brew bundle
```bash
cd ~/.dotfiles
# Add export HOMEBREW_HOME_APPS=true or export HOMEBREW_WORK_APPS=true to install those specified
export HOMEBREW_ACCEPT_EULA=Y  && /opt/homebrew/bin/brew bundle 
```

5. Set up fish as the default shell
```bash
sudo sh -c 'echo /opt/homebrew/bin/fish >> /etc/shells'
chsh -s /opt/homebrew/bin/fish
```

6. Install dotfiles
```bash
# Step might not be required as installed google-cloud-sdk sets up the .config directory.
if [ ! -d ~/.config ]; then
    mkdir ~/.config # Create the config directory if it doesn't exist otherwise stow will absorb the directory into the dotfiles
fi

if [ ! -d ~/.ssh ]; then
    mkdir ~/.ssh # Create the config directory if it doesn't exist otherwise stow will absorb the directory into the dotfiles
fi

# Install Mise Tools
cd ~/.dotfiles/Config/mise/.config/mise/
mise trust
mise install

cd ~/.dotfiles
tuckr add \*
```

7. Install rosetta for M1 Macs
```bash
# Need to type 'a' to install
softwareupdate --install-rosetta
```

## Things to be added in future
- [dadbod.nvim](https://github.com/tpope/vim-dadbod) - Databaes interaction tool in Neovim. 

## Installed Application
### Applications (Not available on the App Store or Homebrew)
- [Parallels Desktop](https://www.parallels.com/) - Virtual Machine

## Other Alternative Applications
- [Maccy](https://maccy.app/) - Clipboard Manager - `brew install maccy`
- [Visual Studio Code](https://code.visualstudio.com/) - Code Editor - `brew install visual-studio-code`

## Reference Links
- [GNU Stow](https://www.gnu.org/software/stow/) (Dotfile Manager)
- [Homebrew](https://brew.sh/) (Package Manager)
- [Fish Shell](https://fishshell.com/) (Shell)
- [Fisher](https://github.com/jorgebucaran/fisher) (Fish Plugin Manager)
- [Git](https://git-scm.com/) (Version Control)
- [Vim](https://www.vim.org/) (Text Editor)
- [Neovim](https://neovim.io/) (Text Editor)
