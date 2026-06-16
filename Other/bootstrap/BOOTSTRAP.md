# Unified Bootstrap Guide

This is the single source of truth for taking a fresh machine to a working shell, runtime manager, and personal config. It covers both macOS and Arch Linux, plus every ordering gotcha and manual workaround we hit while bringing this repo online.

## The SSH chicken-and-egg problem

`git/.gitconfig` contains:

```ini
[url "git@github.com:"]
    insteadOf = https://github.com
```

Once this file is symlinked into `~/.gitconfig`, **every** `git clone https://github.com/...` is rewritten to use SSH. On a fresh machine with no SSH key registered at GitHub, those operations fail with permission denied. This affects:

- The initial dotfiles clone
- `cargo install --git https://github.com/...`
- `pipx`/`uv` installing from git URLs
- The TPM clone inside `mise run bootstrap`
- Any other tool that shells out to `git` for a GitHub HTTPS URL

### Workaround

Use `GIT_CONFIG_GLOBAL=/dev/null` to bypass `~/.gitconfig` for the specific command:

```bash
GIT_CONFIG_GLOBAL=/dev/null git clone https://github.com/benjaminwestern/dotfiles ~/.dotfiles
GIT_CONFIG_GLOBAL=/dev/null cargo install --git https://github.com/owner/repo
GIT_CONFIG_GLOBAL=/dev/null pipx install git+https://github.com/owner/repo
```

The bootstrap task generates an SSH key, but you must still register the public key at GitHub manually before normal git operations work.

## macOS bootstrap

Use the public loader on a fresh machine:

```bash
# Install mise standalone first (do NOT use Homebrew for mise itself)
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"

curl -fsSL https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh \
  | bash -s -- setup --shell fish --profile work --personal
```

Or clone first and run locally:

```bash
# Install mise standalone first (do NOT use Homebrew for mise itself)
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"

git clone https://github.com/benjaminwestern/dotfiles ~/.dotfiles
~/.dotfiles/install.sh setup --shell fish --profile work --personal
```

Routine maintenance:

```bash
~/.dotfiles/install.sh ensure --personal
~/.dotfiles/install.sh update
mise doctor
mise up
mise dotfiles status
```

## Arch Linux bootstrap

The Arch `mise` package in pacman is too old for `mise bootstrap` and `[dotfiles]`, so install the standalone binary first.

```bash
# 1. Install mise standalone (do NOT use pacman for mise itself)
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"

# 2. Clone dotfiles with HTTPS (SSH key doesn't exist yet)
GIT_CONFIG_GLOBAL=/dev/null git clone https://github.com/benjaminwestern/dotfiles ~/.dotfiles

# 3. Bootstrap system packages, dotfile symlinks, and default shell
mise bootstrap

# 4. Install language runtimes and tools
mise install

# 5. Install TPM
mise run bootstrap

# 6. Register a new SSH key at GitHub manually, then restart the shell
exec fish
```

### Platform-specific mise config

`~/.config/mise` is a directory symlink to `~/.dotfiles/mise`. It contains:

- `config.toml` — shared config (tools, env, aliases, tasks, dotfiles)
- `config.linux.toml` — pacman packages and Linux login shell
- `config.macos.toml` — brew packages and macOS login shell
- `miserc.toml` — enables `auto_env = true` so mise loads the right platform file

`auto_env` is required because mise does not auto-load `mise.{linux,macos}.toml`
by default. The `miserc.toml` turns it on early, before config discovery finishes.

Routine maintenance:

```bash
mise doctor
mise up
mise dotfiles status
mise run bundle-update
```

## What `mise bootstrap` does

1. Reads `[bootstrap.packages]` and installs system packages:
   - macOS: `brew:*` formulae
   - Arch: `pacman:*` packages
2. Reads `[bootstrap.user]` and sets the login shell (Arch only; macOS uses `install.sh`)
3. Reads `[dotfiles]` and symlinks config from `~/.dotfiles/` into `~/$HOME`

Then `mise install` installs everything in `[tools]`.

## The unified config layout

A single file, `~/.dotfiles/mise/config.toml`, is shared by both platforms:

- macOS gets it via mise `[dotfiles]`
- Arch gets it via a symlink: `~/.config/mise` → `~/.dotfiles/mise`

Because `~/.config/mise` is a **directory** symlink, both `config.toml` and the task scripts in `scripts/` resolve through the same link. Machine-local secrets live in `~/.config/mise/.env`, which is gitignored.

## Gotchas we hit bringing this device online

### 1. Mise must be the standalone binary

**Never install mise via a package manager** (pacman, Homebrew, etc.). The system packages are often too old and do not support `mise bootstrap`, `[dotfiles]`, or platform-specific config (`auto_env`). Always use the official installer:

```bash
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"
```

Then verify with `mise version` and `mise doctor`.

### 2. Pacman mise is too old

### 2. Initial clone must bypass `~/.gitconfig`

Run `GIT_CONFIG_GLOBAL=/dev/null git clone ...` before the SSH key exists. Once `~/.gitconfig` is symlinked, every HTTPS GitHub URL becomes SSH.

### 3. `~/.config/mise` must be a directory symlink

Originally only `~/.config/mise/config.toml` was symlinked. After the `Configs/` → root restructure, `~/.config/mise` itself is symlinked to `~/.dotfiles/mise` so task scripts resolve correctly.

### 4. Old `Configs/` symlinks break after restructure

If upgrading from the old layout, symlinks still point to `~/.dotfiles/Configs/...`. Delete the stale directory and reapply:

```bash
rm -rf ~/.dotfiles/Configs
mise dotfiles apply
```

### 5. Real files can block dotfiles apply

If a target path exists as a real file or directory, mise refuses to overwrite it. We hit this with:

- `~/.config/ghostty/config`
- `~/.config/opencode/plugins`

Remove or back them up, then rerun `mise dotfiles apply`.

### 6. `~/.pi` was a stale directory symlink

In the old layout `~/.pi` symlinked to `~/.dotfiles/Configs/pi/.pi`. The new layout manages individual files under `~/.pi/agent/`. Remove the old symlink and recreate the parent directory:

```bash
rm ~/.pi
mkdir -p ~/.pi/agent
mise dotfiles apply
```

### 7. TPM clone fails without `GIT_CONFIG_GLOBAL=/dev/null`

The bootstrap task clones `tmux-plugins/tpm` over HTTPS. Because `~/.gitconfig` is already in place, the task uses `GIT_CONFIG_GLOBAL=/dev/null` to avoid the SSH rewrite.

### 8. `.env` is not created automatically

`mise/.example.env` is tracked; `mise/.env` is gitignored. Copy and edit it per machine:

```bash
cp ~/.dotfiles/mise/.example.env ~/.config/mise/.env
```

### 9. Some dotfiles are platform-only

`~/.aerospace.toml`, `~/.config/borders/bordersrc`, `~/.config/ghostty/config`, and `~/Brewfile` are declared for macOS. On Arch they show as `applied` symlinks even though the tools themselves may not be installed.

### 10. `mise doctor` PATH warning

`~/.local/share/omarchy/bin` may take precedence over mise shims in `PATH`. This is a warning, not an error, but be aware if tools resolve unexpectedly.

### 11. SSH key generation is manual

`mise run bootstrap` no longer creates an SSH key. Generate one yourself when you need git push/pull access:

```bash
ssh-keygen -t ed25519 -C "$USER@$(hostname)"
cat ~/.ssh/id_ed25519.pub
```

Then add the public key to GitHub at https://github.com/settings/keys.

### 12. Manual font installs

Some fonts are not packaged and must be installed from upstream releases. Example: `psudoFont Liga Mono` from <https://github.com/psudo-dev/psudofont-liga-mono>:

```bash
mkdir -p ~/.local/share/fonts/psudofont-liga-mono
cd /tmp
curl -sL -o psudofont.zip https://github.com/psudo-dev/psudofont-liga-mono/releases/download/v.2.2.0/psudoFont_Liga_Mono_V.2.2.0.zip
unzip -q psudofont.zip
cp psudoFont_Liga_Mono_V.2.2.0/*.ttf ~/.local/share/fonts/psudofont-liga-mono/
fc-cache -fv ~/.local/share/fonts/psudofont-liga-mono
```

## Validation checklist

After bootstrap, confirm:

```bash
# mise is the standalone version, not pacman
mise version

# config loads with no errors
mise doctor

# all dotfiles are symlinks to the flat repo layout
mise dotfiles status

# env vars are present
mise env | grep -E 'EDITOR|PITCHFORK|OPENCODE'

# login shell is fish
echo $SHELL

# SSH key exists
ls ~/.ssh/id_ed25519
```

## Recovering from a partial bootstrap

The bootstrap is idempotent. If something fails partway through, fix the blocker and rerun the same step:

```bash
mise bootstrap          # system packages + dotfiles + shell
mise install            # tools
mise run bootstrap      # SSH key + TPM
mise dotfiles apply     # re-converge symlinks
```

For any git operation that must use HTTPS before the SSH key is registered, prefix with `GIT_CONFIG_GLOBAL=/dev/null`.
