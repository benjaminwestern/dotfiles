function ssh --description "SSH with direct remote tmux for mac-mini" --wraps=ssh
    # Avoid nested tmux for the default interactive Mac mini connection. Keep
    # the local session alive while detached, then restore it after SSH exits.
    if test (count $argv) -eq 1; and test "$argv[1]" = mac-mini
        if set -q TMUX
            command tmux detach-client -E \
                'ssh -t mac-mini "env TERM=xterm-256color tmux new-session -As main"; exec tmux new-session -As main'
        else
            command ssh -t mac-mini 'env TERM=xterm-256color tmux new-session -As main'
        end
        return $status
    end

    command ssh $argv
end
