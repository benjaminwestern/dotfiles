function gwt-switch --description "Switch between worktrees with fzf"
    # Find bare repo root
    set current_dir (pwd)
    set bare_root ""
    
    while test "$current_dir" != "/"
        if test -d "$current_dir/.git" -a ! -f "$current_dir/.git"
            set bare_root $current_dir
            break
        end
        set current_dir (dirname $current_dir)
    end
    
    if test -z "$bare_root"
        echo "Error: Not in a worktree"
        return 1
    end
    
    # Get worktrees with full paths for uniqueness
    set worktree (git worktree list | fzf --prompt="Select worktree: " | awk '{print $1}')
    
    if test -n "$worktree"
        cd $worktree
        # Add to zoxide with full path (keeps them unique)
        zoxide add $worktree
    end
end