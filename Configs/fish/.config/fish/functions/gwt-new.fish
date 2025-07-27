function gwt-new --description "Create new worktree from current bare repo"
    set branch_name $argv[1]
    
    if test -z "$branch_name"
        echo "Usage: gwt-new <branch-name>"
        return 1
    end
    
    # Find the bare repo root (look for .git that's not a file)
    set current_dir (pwd)
    while test "$current_dir" != "/"
        if test -d "$current_dir/.git" -a ! -f "$current_dir/.git"
            # Found bare repo
            cd $current_dir
            git worktree add $branch_name $branch_name
            echo "Created worktree: $current_dir/$branch_name"
            cd $branch_name
            return 0
        end
        set current_dir (dirname $current_dir)
    end
    
    echo "Error: Not in a worktree or bare repo"
    return 1
end