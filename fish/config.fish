# Disable fish greeting
set fish_greeting ""

# Initialise Homebrew for Apple Silicon and Intel prefixes.
if test -x /opt/homebrew/bin/brew
    eval (/opt/homebrew/bin/brew shellenv)
else if test -x /usr/local/bin/brew
    eval (/usr/local/bin/brew shellenv)
end

# Add ~/.local/bin to PATH
if test -d "$HOME/.local/bin"
    fish_add_path --global "$HOME/.local/bin"
end

# WSL launched from Windows inherits the native Windows working directory.
# Start an ordinary login in Linux home so mise does not mistake the native
# Windows ~/.config/mise tree for a project configuration.
if test -r /proc/sys/kernel/osrelease; and string match -qi '*microsoft*' (cat /proc/sys/kernel/osrelease)
    if string match -q "/mnt/*/Users/$USER" "$PWD"
        cd "$HOME"
    end
end

# Tmux auto-launch (macOS always; Linux opt-in via DOTFILES_TMUX_AUTO=1 in
# ~/.config/mise/.env). The .env is read directly because mise activates
# after this file loads, so its variables are not yet in the shell here.
set -l tmux_auto off
if test (uname) = Darwin
    set tmux_auto on
else if test -r "$HOME/.config/mise/.env"; and string match -rq '^[[:space:]]*DOTFILES_TMUX_AUTO[[:space:]]*=[[:space:]]*1' < "$HOME/.config/mise/.env"
    set tmux_auto on
end
if test "$tmux_auto" = on; and status is-interactive
    if not set -q TMUX
        if test "$TERM_PROGRAM" != "vscode"
            set -l tmux_bin (command -v tmux || echo /usr/bin/tmux)
            $tmux_bin new-session -As main
        end
    end
end

# Initialise worktrunk
if command -v wt >/dev/null 2>&1
  command wt config shell init fish | source
end

# Load zoxide
if command -v zoxide &> /dev/null
  zoxide init --cmd cd fish | source
end

# System info (skip non-interactive sessions, e.g. scp over SSH)
if status is-interactive
    fastfetch
end
