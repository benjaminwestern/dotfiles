function gwt-clone --description "Clone repo as bare with main worktree"
    set repo_url $argv[1]
    
    if test -z "$repo_url"
        echo "Usage: gwt-clone <ssh-url>"
        echo "Example: gwt-clone git@github.com:user/repo.git"
        return 1
    end
    
    # Extract repo name from URL
    set repo_name (basename $repo_url .git)
    set bare_dir "$repo_name.git"
    
    echo "Cloning $repo_url into worktree structure..."
    
    # Clone as bare
    git clone --bare $repo_url $bare_dir
    cd $bare_dir
    
    # Get default branch name
    set default_branch (git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
    
    # Create main worktree
    git worktree add main $default_branch
    
    echo "Created:"
    echo "  $bare_dir/        # Bare repo"
    echo "  $bare_dir/main/   # Main worktree"
    echo ""
    echo "cd $bare_dir/main"
    
    cd main
end