# Disable fish greeting
set fish_greeting ""

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
#

# Add ~/.local/bin to PATH
if test -d "$HOME/.local/bin"
    fish_add_path "$HOME/.local/bin"
end

# Initialise mise
if command -v mise >/dev/null 2>&1
  mise activate fish | source
end

# Initialise worktrunk
if command -v wt >/dev/null 2>&1
  command wt config shell init fish | source
end

# Load zoxide
if command -v zoxide &> /dev/null
  zoxide init --cmd cd fish | source
end

# System info (macchina on macOS, fastfetch on Linux)
if command -v macchina >/dev/null
    macchina
else if command -v fastfetch >/dev/null
    fastfetch
end

if test -d $HOME/.grok/bin
    fish_add_path $HOME/.grok/bin
end
