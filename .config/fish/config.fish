if status is-interactive
    # Commands to run in interactive sessions can go here
end

# export DOCKER_HOST=ssh://mac-mini

# Paths
set -gx PATH $PATH /usr/local/bin
set -gx PATH $PATH /opt/homebrew/anaconda3/bin
set -gx PATH $PATH /opt/homebrew/bin
set -gx PATH $PATH /Users/benjaminwestern/.deno/bin
set -gx PATH $PATH /Users/benjaminwestern/Go/bin
set -gx PATH $PATH /opt/homebrew/opt/go/libexec/bin
set -gx PATH $PATH /Users/benjaminwestern/bin
set -gx PATH $PATH /Users/benjaminwestern/.cache/lm-studio/bin

# Load zoxide
zoxide init --cmd cd fish | source

# Load nvim as default editor
export EDITOR='nvim'

# OS Aliases
alias cls="clear"
alias buu="brew update && brew upgrade && brew cleanup && brew autoremove"
alias bb="cd ~ && brew bundle"
alias bbh="cd ~ && export HOMEBREW_HOME_APPS=true && brew bundle"
alias vim="nvim"
alias vi="nvim"
alias v="nvim"
alias python=python3
alias code="open -a Visual\ Studio\ Code.app"

# Git Aliases
alias banish_ds_store="find . -name .DS_Store -print0 | xargs -0 git rm -f --ignore-unmatch && echo .DS_Store >> .gitignore && git add .gitignore && git commit -m ':fire: .DS_Store banished!' && git push"
alias egg="git add . && git commit --allow-empty -m ':sparkles: :rocket:' && git push"

# Terraform Aliases
alias taa="terraform apply --auto-approve"
alias tp="terraform fmt -recursive && terraform init && terraform plan"
alias taap="terraform apply --target"
alias tf="terraform"
alias tfc="terraform console"

# Dataform Aliases
alias dfc="dataform compile"
alias dfr="dataform run"
alias dft="dataform test"
alias dff="dataform format"
alias dfi="dataform install"

# Google Aliases
alias gadc="gcloud auth application-default login"
alias gauth="gcloud auth login"
alias gsqp="gcloud auth application-default set-quota-project "
alias gsgp="gcloud config set project "
alias gssa="gcloud auth activate-service-account"
alias unsetgsgp="gcloud config unset project"
alias gsai="gcloud config set auth/impersonate_service_account " 
alias unsetgsai="gcloud config unset auth/impersonate_service_account"

source ~/.config/fish/functions/env_loader.fish
source ~/.config/fish/functions/new_markdown.fish
source ~/.config/fish/functions/replace_icon.fish
source ~/.config/fish/functions/gcloud.fish

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
if test -f /opt/homebrew/anaconda3/bin/conda
    eval /opt/homebrew/anaconda3/bin/conda "shell.fish" "hook" $argv | source
else
    if test -f "/opt/homebrew/anaconda3/etc/fish/conf.d/conda.fish"
        . "/opt/homebrew/anaconda3/etc/fish/conf.d/conda.fish"
    else
        set -x PATH "/opt/homebrew/anaconda3/bin" $PATH
    end
end
# <<< conda initialize <<<
