if status is-interactive
    # Commands to run in interactive sessions can go here
end

# export DOCKER_HOST=ssh://mac-mini

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

# Git Aliases
alias banish_ds_store="find . -name .DS_Store -print0 | xargs -0 git rm -f --ignore-unmatch && echo .DS_Store >> .gitignore && git add .gitignore && git commit -m ':fire: .DS_Store banished!' && git push"
alias egg="git add . && git commit --allow-empty -m ':sparkles: :rocket:' && git push"

# Terraform Aliases
alias taa="terraform apply --auto-approve"
alias tp="terraform fmt -recursive && terraform init && terraform plan"
alias taap="terraform apply --target"

# Google Aliases
alias gadc="gcloud auth application-default login"
alias gauth="gcloud auth login"
alias gsqp="gcloud auth application-default set-quota-project "
alias gssa="gcloud auth activate-service-account"
alias gsgp="gcloud config set project "
alias unsetgsgp="gcloud config unset project"
alias gsai="gcloud config set auth/impersonate_service_account " 
alias unsetgsai="gcloud config unset auth/impersonate_service_account"

source ~/.config/fish/functions/env_loader.fish
source ~/.config/fish/functions/new_markdown.fish
source ~/.config/fish/functions/replace_icon.fish
