# Disable fish greeting
set fish_greeting ""

# Tmux auto-launch (commented out for raw terminal usage)
# if status is-interactive
#     if not set -q TMUX
#         if test $TERM_PROGRAM != "vscode"
#             exec /opt/homebrew/bin/tmux new-session -As main
#         end
#     end
# end
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

# macchina
