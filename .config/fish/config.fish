if status is-interactive
    # Commands to run in interactive sessions can go here
end

# export DOCKER_HOST=ssh://mac-mini

# Paths
set -gx PATH /opt/homebrew/opt/ruby/bin $PATH
set -gx PATH $PATH /usr/local/bin
set -gx PATH $PATH /opt/homebrew/bin

# Load zoxide
zoxide init --cmd cd fish | source

# Load nvim as default editor
export EDITOR='nvim'

# OS Aliases
alias cls="clear"
alias buu="brew update && brew upgrade && brew cleanup && brew autoremove"
alias vim="nvim"
alias vi="nvim"
alias v="nvim"
alias python=python3
alias vc="open $1 -a \"Visual Studio Code\""
alias cu="open $1 -a \"Cursor\""

# Git Aliases
alias banish_ds_store="find . -name .DS_Store -print0 | xargs -0 git rm -f --ignore-unmatch && echo .DS_Store >> .gitignore && git add .gitignore && git commit -m ':fire: .DS_Store banished!' && git push"
alias egg="git add . && git commit --allow-empty -m ':sparkles: :rocket:' && git push"

# Terraform Aliases
alias ta="terraform fmt -recursive && terraform init && terraform validate && terraform apply"
alias taa="terraform fmt -recursive && terraform init && terraform validate && terraform apply --auto-approve"
alias tp="terraform fmt -recursive && terraform init && terraform validate && terraform plan"
alias tpt="terraform plan --target"
alias taat="terraform apply --target"
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

# Mise Aliases
alias gsp="mise run set-gcp-project"
alias git-pull="mise run pull-all-repos"
alias git-check="mise run check-all-repos"

macchina
