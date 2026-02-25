# Scripts Directory

This directory contains bootstrap and configuration scripts for setting up new machines.

## Available Scripts

### `bootstrap.sh` (Universal Entry Point)
**Location:** Repository root (`~/.dotfiles/bootstrap.sh`)

Universal bootstrap script that detects the operating system and delegates to the appropriate OS-specific script.

**Features:**
- Auto-detects OS (macOS/Linux)
- Calls `macos-bootstrap.sh` or `linux-bootstrap.sh`
- Passes computer name parameter

**Usage:**
```bash
# From anywhere
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/.dotfiles/main/bootstrap.sh | bash

# With custom computer name
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/.dotfiles/main/bootstrap.sh | bash -s -- "work-macbook"

# Or if already cloned
~/.dotfiles/bootstrap.sh [computer-name]
```

---

### `macos-bootstrap.sh` (macOS Setup)
**Location:** `Other/scripts/macos-bootstrap.sh`

Complete macOS environment setup from fresh install to fully functional development machine.

**What it does (in order):**
1. **Xcode Command Line Tools** - Installs if missing (required for git)
2. **Homebrew** - Package manager installation
3. **Clone Dotfiles** - Clones repo from GitHub, converts HTTPS to SSH
4. **Brew Bundle** - Installs all Brewfile packages (Fish, tuckr, CLI tools, apps)
5. **Fish Shell** - Adds to `/etc/shells`, sets as default
6. **Pre-create Directories** - Creates `~/.ssh/` (700) and `~/.config/` to prevent tuckr from symlinking entire directories
7. **Tuckr Symlink** - Symlinks all dotfiles via `tuckr add \*`
8. **Mise Installation** - Installs mise runtime manager
9. **Mise Tools** - Installs all languages and dev tools via `mise up`
10. **Rosetta 2** - Installs on Apple Silicon Macs for Intel compatibility
11. **macOS Defaults** - Applies system preferences (Dock, Finder, etc.)

**Total time:** ~10-15 minutes

**Requirements:** macOS 10.15+ (Catalina or later)

**Usage:**
```bash
# Called automatically by bootstrap.sh
# Or run directly:
~/.dotfiles/Other/scripts/macos-bootstrap.sh "my-macbook"
```

---

### `macos-defaults.sh` (System Preferences)
**Location:** `Other/scripts/macos-defaults.sh`

Applies macOS system defaults and preferences. Called by `macos-bootstrap.sh` but can be run independently.

**What it configures:**
- Hostname (ComputerName, HostName, LocalHostName)
- Dock (left side, auto-hide, no delay, remove default apps)
- Menu bar (show battery percentage)
- Finder (show path bar, status bar, all extensions, no warnings)
- Power management (display/disk sleep times)
- Screenshots (PNG format)
- Mouse (disable acceleration)

**Does NOT configure:**
- Git user.name/user.email (now in `Configs/git/.gitconfig`)

**Usage:**
```bash
~/.dotfiles/Other/scripts/macos-defaults.sh "computer-name"
```

**Note:** Some changes require logging out or restarting to take full effect.

---

### `linux-bootstrap.sh` (Linux Setup - TODO)
**Location:** `Other/scripts/linux-bootstrap.sh` (planned)

Future Linux bootstrap script. Currently shows manual instructions when called.

**Planned features:**
- APT/DNF/Pacman package installation
- Fish, Mise, Tuckr setup
- Equivalent dev tool installation

**Current behavior:** Displays manual setup instructions

---

## Manual Recovery Steps

If the bootstrap script fails or you need to manually get things working:

### 1. Get Basic Shell Working
```bash
# If stuck without tools, manually install:
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
brew install git fish
```

### 2. Get Dotfiles
```bash
git clone https://github.com/benjaminwestern/dotfiles ~/.dotfiles
cd ~/.dotfiles
git remote set-url origin git@github.com:benjaminwestern/dotfiles.git
```

### 3. Install Core Tools
```bash
brew bundle --file=~/.dotfiles/Configs/brew/Brewfile
```

### 4. Setup Shell
```bash
# Add fish to shells
sudo sh -c 'echo /opt/homebrew/bin/fish >> /etc/shells'
chsh -s /opt/homebrew/bin/fish

# Pre-create directories
mkdir -p ~/.ssh && chmod 700 ~/.ssh
mkdir -p ~/.config

# Symlink dotfiles
tuckr add \*
```

### 5. Get Mise Working
```bash
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash)"  # or zsh/fish
mise up
```

### 6. Activate Everything
```bash
# Restart terminal or
exec /opt/homebrew/bin/fish

# Verify
mise doctor
tuckr status
```

---

## Core Tool Stack

### Present Tools (All Implemented)

| Tool | Purpose | Install Method | Config Location |
|------|---------|----------------|-----------------|
| **Fish** | Shell | Homebrew | `Configs/fish/.config/fish/` |
| **Tuckr** | Dotfile manager | Homebrew | This repo |
| **Mise** | Dev environment | curl installer | `Configs/mise/.config/mise/` |
| **Homebrew** | Package manager | curl installer | `Configs/brew/Brewfile` |
| **Tmux** | Terminal multiplexer | Homebrew | `Configs/tmux/.config/tmux/` |
| **Neovim** | Editor | Homebrew | `Configs/nvim/.config/nvim/` |
| **Zoxide** | Smart cd | Homebrew | Activated in all shells |
| **FZF** | Fuzzy finder | Homebrew | Activated in all shells |

### Deprecated/Replaced

| Old Tool | Replacement | Reason |
|----------|-------------|---------|
| **Stow** | Tuckr | Better conflict detection, Rust-based |
| **setup-osx.sh** | bootstrap.sh | Unified cross-platform entry |

---

## Quick Reference

### One-liners by OS

**macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/.dotfiles/main/bootstrap.sh | bash
```

**Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/.dotfiles/main/bootstrap.sh | bash
```

**With wget:**
```bash
wget -qO- https://raw.githubusercontent.com/benjaminwestern/.dotfiles/main/bootstrap.sh | bash
```

### Post-Install Verification

```bash
# Check all symlinks
tuckr status

# Check mise installation
mise doctor

# Check shell is fish
echo $SHELL  # Should be /opt/homebrew/bin/fish

# Check zoxide works
zoxide --version

# Check mise tools
mise list
```

---

## Links

- [Tuckr Documentation](https://github.com/RaphGL/Tuckr)
- [Mise Documentation](https://mise.jdx.dev/)
- [Homebrew Bundle](https://github.com/Homebrew/homebrew-bundle)
- [Fish Shell](https://fishshell.com/)
