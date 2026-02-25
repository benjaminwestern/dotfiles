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

# Initialise mise
~/.local/bin/mise activate fish | source

# Load zoxide
zoxide init --cmd cd fish | source

# macchina
