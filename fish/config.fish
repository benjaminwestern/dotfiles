# Disable fish greeting
set fish_greeting ""

# Add ~/.local/bin to PATH
if test -d "$HOME/.local/bin"
    fish_add_path "$HOME/.local/bin"
end

# Initialise mise
if command -v mise >/dev/null 2>&1
  mise activate fish | source
end

# Tmux auto-launch (macOS always; Linux only if DOTFILES_TMUX_AUTO=1)
if status is-interactive
    if not set -q TMUX
        if test "$TERM_PROGRAM" != "vscode"
            if test (uname) = Darwin -o "$DOTFILES_TMUX_AUTO" = "1"
                set -l tmux_bin (command -v tmux || echo /usr/bin/tmux)
                exec $tmux_bin new-session -As main
            end
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

