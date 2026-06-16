function gwt-convert --description "Convert current repo to worktree structure"
    # Get current info
    set current_dir (pwd)
    set parent_dir (dirname $current_dir)
    set repo_name (basename $current_dir)
    set current_branch (git branch --show-current)
    
    if test -z "$current_branch"
        echo "Error: Not in a git repository"
        return 1
    end
    
    set bare_dir "$parent_dir/$repo_name.git"
    set main_worktree "$bare_dir/main"
    
    echo "Converting '$repo_name' to worktree structure..."
    
    # Create temporary backup
    set temp_dir "$parent_dir/.tmp-$repo_name"
    mv $current_dir $temp_dir
    
    # Clone current repo as bare
    cd $temp_dir
    git clone --bare . $bare_dir
    
    # Create main worktree
    cd $bare_dir
    git worktree add main $current_branch
    
    # Copy uncommitted changes
    cp -r $temp_dir/* main/ 2>/dev/null || true
    cp -r $temp_dir/.* main/ 2>/dev/null || true
    
    # Clean up
    rm -rf $temp_dir
    
    echo "Created:"
    echo "  $bare_dir/        # Bare repo" 
    echo "  $bare_dir/main/   # Main worktree"
    echo ""
    echo "cd $main_worktree"
    
    cd main
end