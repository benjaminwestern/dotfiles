# Core Tools
- Fish - https://fishshell.com
- Fish Plugin Manager - https://github.com/jorgebucaran/fisher (currently done through homebrew)
- TMUX - https://github.com/tmux/tmux/wiki
- TMUX Plugin Manager - https://github.com/tmux-plugins/tpm (can be done through homebrew, needs to be in the right path)
- Mise - https://github.com/jdx/mise
- Stow - https://www.gnu.org/software/stow/ 
- Neovim - https://github.com/neovim/neovim

# To Investigate
- Tuckr - https://github.com/RaphGL/Tuckr (replacement to stow)

# MacOS Core Tools
- Homebrew - https://github.com/Homebrew/install

# Setup script for MacOS needs to do:
1. Run`xcode-select install` only if `xcode-select -p` doesn't return something, this allows me to use git
2. Run homebrew sh script
3. Git clone my dotfiles, make the directory and change into the directory
4. Run Brew Bundle (installs fish, fisher, tmux, neovim and stow as CORE requirements)
5. Create `.config` folder, `.ssh` and `code` folders in $HOME so `stow` doesn't absorb them entirely
6. From the `dotfiles` directory, run `stow .`
7. Run mise sh script
8. Run `mise install`
9. Run tmux-plugin git clone
10. Change default shell to `fsh`
11. Check if rosetta is installed if `/usr/sbin/softwareupdate --list | grep -q "Rosetta"` returns nothing, then install
12. Setup MacOS defaults using shell script
