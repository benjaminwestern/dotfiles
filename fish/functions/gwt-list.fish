function gwt-list --description "List all worktrees for current repo"
    # Find bare repo root
    set current_dir (pwd)
    while test "$current_dir" != "/"
        if test -d "$current_dir/.git" -a ! -f "$current_dir/.git"
            cd $current_dir
            git worktree list
            return 0
        end
        set current_dir (dirname $current_dir)
    end
    
    echo "Error: Not in a worktree or bare repo"
    return 1
end