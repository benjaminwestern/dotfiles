function ssh --description "SSH with direct remote tmux for managed hosts" --wraps=ssh
    # Avoid nested tmux for default interactive development-host connections.
    # Keep the local session alive while detached, then restore it after SSH exits.
    set -l tmux_host
    if test (count $argv) -eq 1
        switch "$argv[1]"
            case mac-mini cachy
                set tmux_host "$argv[1]"
        end
    end

    if test -n "$tmux_host"
        if set -q TMUX
            command tmux detach-client -E \
                "ssh -t $tmux_host 'env TERM=xterm-256color tmux new-session -As main'; exec tmux new-session -As main"
        else
            command ssh -t "$tmux_host" 'env TERM=xterm-256color tmux new-session -As main'
        end
        return $status
    end

    command ssh $argv
end
