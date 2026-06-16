![Configuration groups banner](../assets/readme/configs-hero.svg)

This directory contains all managed dotfile groups. Each subdirectory holds the
config files for one tool; the layout is flat so a single source path maps to
a single target path. mise `[dotfiles]` creates symlinks from `$HOME`
back into this repo, the Linux bootstrap symlinks a subset of the same groups,
and the Windows personal bootstrap copies specific groups.

Use [README.md](README.md) for the public bootstrap entrypoints and
[Other/scripts/README.md](Other/scripts/README.md) for the detailed
bootstrap and repair flow. Stay on this page when you need to know which config
a subdirectory owns, what platform it targets, or how to add a new managed
surface.

The repo root also contains a separate `mise.toml` for contributor tooling.
That file powers the README asset pipeline and is distinct from the unified
`mise` config that manages personal dotfiles.

![Config management banner](../assets/readme/configs-platform-model.svg)

### Both platforms — Mise `[dotfiles]`

mise `[dotfiles]` reads the mappings declared in
`mise/config.toml` and creates symlinks from `$HOME` back
into this repo. For example, `git/.gitconfig` is symlinked to
`~/.gitconfig`.

```bash
# Apply/converge all dotfiles
mise dotfiles apply

# Check current dotfile status
mise dotfiles status

# Show only missing or conflicting entries
mise dotfiles status --missing
```

mise symlinks **individual files and directories** as declared. The bootstrap
pre-creates `~/.ssh/` (mode 700) before applying dotfiles so SSH config lands
with the right parent permissions. Directories are symlinked as a whole —
make sure you don't store machine-local state inside a managed directory.

### Windows — Selective copy (legacy)

The Windows personal bootstrap
([`Other/scripts/windows/personal-bootstrap-windows.ps1`](../Other/scripts/windows/personal-bootstrap-windows.ps1))
copies specific config groups into `$HOME` using SHA256 hash comparison to
avoid unnecessary overwrites. Currently managed:

- `git/.gitconfig` → `$HOME\.gitconfig`
- `ssh/config` → `$HOME\.ssh\config`
- `mise/` → `$HOME\.config\mise\` (config.toml, .env, scripts/)
- `opencode/` → `$HOME\.config\opencode\` (opencode.json, plugins/)

Each copy target is gated by an `ENABLE_*` environment variable (default:
`true`) and supports dry-run via `-DryRun`.

![Config reference banner](../assets/readme/configs-group-reference.svg)

| Subdirectory | Target Path | Platform | Description |
|---|---|---|---|---|
| `aerospace` | `~/.aerospace.toml` | macOS | Aerospace tiling window manager configuration |
| `bash` | `~/.bashrc`, `~/.bash_profile`, `~/.hushlogin` | Both | Bash shell configuration with mise, zoxide, and worktrunk activation |
| `borders` | `~/.config/borders/bordersrc` | macOS | Window border styling for the borders utility |
| `brew` | Used by `brew bundle` | macOS | Brewfile with Homebrew taps, casks, Mac App Store apps, and tapped formulae. Core formulae are managed by mise `[bootstrap.packages]` |
| `fish` | `~/.config/fish/` | Both | Fish shell config, plugins (Fisher), and variables |
| `ghostty` | `~/.config/ghostty/config` | macOS | Ghostty terminal emulator configuration |
| `git` | `~/.gitconfig` | Both | Git configuration (default branch, colour, push, pull, user, URL rewriting) |
| `hypr` | `~/.config/hypr/hyprland.conf` | Linux | Hyprland Wayland compositor configuration |
| `mise` | `~/.config/mise/` | Both | Unified mise runtime config (`config.toml`), environment variables (`.env`), example env (`.example.env`), and task scripts (`scripts/`). Separate from the repo-root `mise.toml` used for local contributor tasks |
| `nvim` | `~/.config/nvim/` | Both | Neovim configuration based on Kickstart.nvim, including `init.lua`, plugin specs, keymaps, and [its own README](nvim/README.md) |
| `opencode` | `~/.config/opencode/` | Both | Opencode AI assistant configuration (`opencode.json`) and plugins (mise integration) |
| `pi` | `~/.pi/agent/` | Both | Pi coding agent settings, model registry, prompt appendix, and extensions. `auth.json` and `sessions/` remain machine-local |
| `pitchfork` | `~/.config/pitchfork/` | Both | Pitchfork configuration (Caddyfile and config.toml) |
| `ssh` | `~/.ssh/config` | Both | SSH client configuration for hosts, identity files, and tunnels. Keys are **not** included in this repo |
| `tmux` | `~/.tmux.conf` | Both | Tmux terminal multiplexer configuration |
| `worktrunk` | `~/.config/worktrunk/config.toml` | Both | Worktrunk (`wt`) worktree manager configuration including worktree path template and post-start hooks |
| `zsh` | `~/.zshrc`, `~/.zprofile` | Both | Zsh shell configuration with mise, zoxide, and worktrunk activation |

![Add config surface banner](../assets/readme/configs-add-group.svg)

1. Create a new directory at the repo root named after the tool (e.g., `starship/`)
2. Place the config file(s) inside it using a flat layout. For example, if the config lives at `~/.config/starship/starship.toml`, create `starship/starship.toml`
3. Add a `[dotfiles]` entry in `mise/config.toml` mapping the target path to the source path
4. On Windows, if the config should be copied by the personal bootstrap, add a new `Apply-*` function in [`Other/scripts/windows/personal-bootstrap-windows.ps1`](Other/scripts/windows/personal-bootstrap-windows.ps1) following the existing pattern (source path, destination path, SHA256 comparison, `Invoke-OrDry` gate)
5. Run `mise dotfiles apply` to symlink it into place
6. Commit and push

![Remove config surface banner](../assets/readme/configs-remove-group.svg)

```bash
# Remove a dotfile entry from mise/config.toml
# Then delete the directory if no longer needed
rm -rf <group-name>

# Re-converge
mise dotfiles apply
```

On Windows, remove the corresponding `Apply-*` function from
[`Other/scripts/windows/personal-bootstrap-windows.ps1`](Other/scripts/windows/personal-bootstrap-windows.ps1).
