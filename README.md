# Dotfiles

Personal macOS (and future Linux) development environment configuration managed with [Tuckr](https://github.com/RaphGL/Tuckr) and version controlled via Git.

## What This Repo Contains

This repository sets up a complete development environment from a fresh macOS installation to a fully functional workspace.

### Managed by Homebrew (Brewfile)
**Core infrastructure tools** that need to be available immediately:
- **Shell:** Fish (with Fisher plugin manager)
- **Terminal:** Ghostty, Tmux (with TPM)
- **Editors:** Neovim
- **CLI Tools:** git, lazygit, zoxide, fzf, fd, ripgrep, jq, yq, gh, gitleaks, tree, htop
- **System:** Aerospace (window manager), borders, mcp-toolbox
- **Dotfile Manager:** tuckr

### Managed by Mise (mise.toml)
**Development environments and language runtimes:**
- **Languages:** Go, Node.js, Deno, Bun, Python, Rust, Lua, Terraform
- **Go Tools:** cloud-sql-proxy, air, golangci-lint, gofumpt, swag, sqlc, d2, glow, freeze, vhs
- **Node Tools:** pnpm, dataform-cli, gemini-cli, opencode-ai, sourcegraph/amp
- **Python Tools:** uv, pipx, sqlfluff
- **Cargo Tools:** tuckr (self-managing)

### Configuration Files
- **Shell:** Fish, Zsh, Bash configs with mise and zoxide activation
- **Editors:** Neovim (based on Kickstart.nvim), Ghostty terminal
- **Tools:** Mise, Tmux, Yazi (file manager), Git, Opencode
- **System:** macOS defaults, Aerospace window manager

## Quick Start (New Machine)

### Automated Bootstrap (Recommended)

**⚠️ Security Note:** The one-liners below download and execute code from the internet. Only run these on trusted networks. If you prefer, [clone first and inspect the code](#clone-first-then-run).

**macOS (curl):**
```bash
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/.dotfiles/main/bootstrap.sh | bash
```

**Linux (curl):**
```bash
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/.dotfiles/main/bootstrap.sh | bash
```

**With custom computer name:**
```bash
curl -fsSL https://raw.githubusercontent.com/benjaminwestern/.dotfiles/main/bootstrap.sh | bash -s -- "my-macbook"
```

**Using wget (if curl unavailable):**
```bash
wget -qO- https://raw.githubusercontent.com/benjaminwestern/.dotfiles/main/bootstrap.sh | bash
```

**Clone first, then run (recommended for security):**
```bash
git clone https://github.com/benjaminwestern/dotfiles ~/.dotfiles
# Inspect the code: cat ~/.dotfiles/bootstrap.sh
~/.dotfiles/bootstrap.sh [computer-name]
```

The bootstrap script will:
1. ✅ Install Xcode Command Line Tools
2. ✅ Install Homebrew
3. ✅ Clone this repository and convert to SSH
4. ✅ Install all Brewfile packages (includes Fish, tuckr, core CLI tools)
5. ✅ Set Fish as default shell
6. ✅ Pre-create `~/.ssh/` and `~/.config/` (prevents directory absorption issues)
7. ✅ Symlink all dotfiles via `tuckr add \*`
8. ✅ Install Mise
9. ✅ Install all Mise-managed tools (`mise up`)
10. ✅ Install Rosetta 2 (Apple Silicon only)
11. ✅ Apply macOS system defaults

**Total time:** ~10-15 minutes depending on internet connection.

### Manual Setup (If You Prefer)

If you want to understand/verify each step:

```bash
# 1. Install Xcode Command Line Tools
xcode-select --install

# 2. Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"

# 3. Clone dotfiles
git clone https://github.com/benjaminwestern/dotfiles ~/.dotfiles
cd ~/.dotfiles

# 4. Convert git remote to SSH (for pushing updates)
git remote set-url origin git@github.com:benjaminwestern/dotfiles.git

# 5. Install all Homebrew packages
brew bundle

# 6. Set Fish as default shell
sudo sh -c 'echo /opt/homebrew/bin/fish >> /etc/shells'
chsh -s /opt/homebrew/bin/fish

# 7. Pre-create directories (prevents tuckr from symlinking entire directories)
mkdir -p ~/.ssh && chmod 700 ~/.ssh
mkdir -p ~/.config

# 8. Symlink dotfiles
tuckr add \*

# 9. Install Mise
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash)"

# 10. Install all Mise tools
mise up

# 11. Apply macOS defaults
~/.dotfiles/Other/scripts/macos-defaults.sh "my-macbook"

# 12. Install Rosetta (Apple Silicon only)
/usr/sbin/softwareupdate --install-rosetta --agree-to-license
```

## What Gets Installed

### Immediate (Homebrew - ~5 mins)
- Fish shell with all completions
- Git, lazygit
- Modern CLI replacements: zoxide (cd), fzf (find), fd (find), ripgrep (grep)
- Data processing: jq (JSON), yq (YAML)
- Terminal: tmux, ghostty, yazi
- Security: gitleaks
- Development: neovim

### Development Tools (Mise - ~10 mins)
- All programming languages and their package managers
- Language-specific CLI tools (linters, formatters, etc.)
- Cloud tools (gcloud via mise plugin)

## Repository Structure

```
.dotfiles/
├── bootstrap.sh              # Universal entry point (OS detection)
├── Configs/
│   ├── brew/Brewfile         # Homebrew packages
│   ├── mise/.config/mise/    # Mise configuration & tools
│   ├── fish/.config/fish/    # Fish shell config
│   ├── zsh/                  # Zsh config (.zshrc, .zprofile)
│   ├── bash/                 # Bash config (.bashrc, .bash_profile)
│   ├── nvim/.config/nvim/    # Neovim configuration
│   ├── git/.gitconfig        # Git configuration
│   ├── ssh/.ssh/config       # SSH config (keys not included)
│   ├── tmux/.config/tmux/    # Tmux configuration
│   ├── yazi/.config/yazi/    # Yazi file manager
│   ├── opencode/.config/opencode/  # Opencode configuration
│   └── ...                   # Other tool configs
├── Other/
│   └── scripts/
│       ├── bootstrap.sh      # Main bootstrap (calls OS-specific)
│       ├── macos-bootstrap.sh # macOS-specific setup
│       └── macos-defaults.sh  # macOS system preferences
└── Secrets/                  # Encrypted sensitive files (not committed)
```

## Daily Usage

### After Bootstrap

1. **Restart terminal** or run `exec fish` to activate Fish shell
2. Run `mise doctor` to verify everything is working
3. Some macOS changes require a system restart

### Managing Dotfiles

```bash
# Check symlink status
cd ~/.dotfiles && tuckr status

# Add new config group
tuckr add <group-name>

# Remove config group
tuckr rm <group-name>

# Push changes
git add -A
git commit -m "update: description"
git push
```

### Updating Tools

```bash
# Update Homebrew packages
brew update && brew upgrade

# Update Mise tools
mise up

# Update both (run via mise task)
mise run bundle-update
```

## Customization

### Environment-Specific Brewfile Apps

The Brewfile supports conditional installs:

```bash
# For work machine (installs Edge, Teams)
export HOMEBREW_WORK_APPS=true
brew bundle

# For home machine (installs databases, Mac App Store apps)
export HOMEBREW_HOME_APPS=true
brew bundle
```

### Computer Name

Pass a custom name to the bootstrap script:
```bash
~/.dotfiles/bootstrap.sh "work-macbook-pro"
```

This sets the hostname and appears in your shell prompt.

## Key Design Decisions

1. **Brew vs Mise Split:** Core shell tools (zoxide, fzf) are in Brewfile so they're available before mise runs. Development tools (languages, compilers) are in mise for version management.

2. **Tuckr Instead of Stow:** Tuckr is a Rust-based stow replacement with better conflict detection and symlink tracking. It symlinks individual files when directories exist, preventing "directory absorption" issues.

3. **Pre-Created Directories:** The bootstrap creates `~/.ssh/` and `~/.config/` before running tuckr, ensuring only config files are symlinked (not entire directories that might contain other files).

4. **Fish as Default:** While zsh and bash configs are included, Fish is the primary shell with full mise and zoxide integration.

## Troubleshooting

### Mise not found after install
```bash
export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate fish)"  # or zsh/bash
```

### Tuckr symlink issues
```bash
# Check status
tuckr status

# If conflicts, you can see what's not symlinked (shown in red)
# Then manually handle conflicts or use tuckr rm/add
```

### Bootstrap fails mid-way
The bootstrap script is idempotent - you can safely re-run it. It checks for existing installations and skips completed steps.

## Manual Recovery (Getting Things Online)

If the automated bootstrap fails or you need to manually set up a machine, follow these steps in order:

### Step 1: Get Basic Tools
```bash
# Install Xcode Command Line Tools
xcode-select --install

# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"

# Install minimal requirements
brew install git fish
```

### Step 2: Get Dotfiles
```bash
# Clone repository
git clone https://github.com/benjaminwestern/dotfiles ~/.dotfiles
cd ~/.dotfiles

# Convert to SSH (for pushing updates later)
git remote set-url origin git@github.com:benjaminwestern/dotfiles.git
```

### Step 3: Install Core Stack
```bash
# Install all Brewfile packages (takes ~5 mins)
brew bundle --file=~/.dotfiles/Configs/brew/Brewfile

# Install Mise
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash)"
```

### Step 4: Setup Shell & Symlinks
```bash
# Add fish to allowed shells
sudo sh -c 'echo /opt/homebrew/bin/fish >> /etc/shells'
chsh -s /opt/homebrew/bin/fish

# Pre-create directories (prevents tuckr absorption issues)
mkdir -p ~/.ssh && chmod 700 ~/.ssh
mkdir -p ~/.config

# Symlink all dotfiles
cd ~/.dotfiles && tuckr add \*
```

### Step 5: Install Dev Tools
```bash
# Install all mise-managed tools (takes ~10 mins)
mise up

# Verify installation
mise doctor
tuckr status
```

### Step 6: Finalize
```bash
# Apply macOS defaults
~/.dotfiles/Other/scripts/macos-defaults.sh "$(hostname -s)"

# Install Rosetta (Apple Silicon only)
/usr/sbin/softwareupdate --install-rosetta --agree-to-license

# Restart terminal
exec /opt/homebrew/bin/fish
```

### Verification Checklist
After manual setup, verify everything:
```bash
# Check shell
echo $SHELL  # Should be /opt/homebrew/bin/fish

# Check dotfiles
tuckr status

# Check tools
which zoxide fzf mise
mise list | head -10

# Check configs
ls -la ~/.zshrc ~/.bashrc ~/.gitconfig
```

## References

- [Tuckr](https://github.com/RaphGL/Tuckr) - Dotfile symlink manager
- [Mise](https://mise.jdx.dev/) - Development environment manager
- [Homebrew](https://brew.sh/) - macOS package manager
- [Fish Shell](https://fishshell.com/) - User-friendly shell
- [Neovim](https://neovim.io/) - Modern Vim editor
- [Kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) - Neovim configuration base

## License

Personal dotfiles - use at your own risk. Some configurations based on Kickstart.nvim (MIT).
