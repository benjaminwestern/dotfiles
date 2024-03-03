# Device Setup
This repository contains the dotfiles and scripts to setup a new device. The dotfiles are managed using GNU Stow.
The neovim components of this repository are heavily taken from [Kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)

## Installation
1. Install Xcode
```bash
xcode-select --install
```

2. Install homebrew
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
```

3. Clone this repository
```bash
git clone
```

4. Install Brew bundle
```bash
brew bundle
```

5. Set up fish as the default shell
```bash
sudo sh -c 'echo $(which fish) >> /etc/shells'
chsh -s $(which fish)
```

6. Install dotfiles
```bash
cd ~/dotfiles
stow .
```

7. Install rosetta for M1 Macs
```bash
softwareupdate --install-rosetta
```

## Installed Application
### Applications (Not available on the App Store or Homebrew)
- [Duet Display](https://www.duetdisplay.com/) - Connect iPad as a second display
- [Parallels Desktop](https://www.parallels.com/) - Virtual Machine
- [Microsoft Office](https://www.microsoft.com/en-us/microsoft-365/) - Office Suite

## Other Alternative Applications
- [Maccy](https://maccy.app/) - Clipboard Manager - `brew install maccy`
- [Rectangle](https://rectangleapp.com/) - Window Manager - `brew install rectangle`
- [BeeKeeper Studio](https://www.beekeeperstudio.io/) - SQL Client - `brew install beekeeper-studio`
- [Visual Studio Code](https://code.visualstudio.com/) - Code Editor - `brew install visual-studio-code`
- [GitHub Desktop](https://desktop.github.com/) - Git Client - `brew install github`
- [Postman](https://www.postman.com/) - API Client - `brew install postman`

## Reference Links
- [GNU Stow](https://www.gnu.org/software/stow/) (Dotfile Manager)
- [Homebrew](https://brew.sh/) (Package Manager)
- [Fish Shell](https://fishshell.com/) (Shell)
- [Fisher](https://github.com/jorgebucaran/fisher) (Fish Plugin Manager)
- [Git](https://git-scm.com/) (Version Control)
- [Vim](https://www.vim.org/) (Text Editor)
- [Neovim](https://neovim.io/) (Text Editor)

## Stow Ignored Directories
- .git
- .gitignore
- scripts
- icons
- lock files for brew and lazy
- README.md
- LICENSE

To add more directories to ignore, add them to the `.stow-local-ignore` file.
