if status is-interactive
    if not set -q TMUX
        if test $TERM_PROGRAM != "vscode"
            exec /opt/homebrew/bin/tmux new-session -As main
        end
    end
end

# Paths
# set -gx PATH $PATH /opt/homebrew/bin
# set -gx PATH $PATH /opt/homebrew/sbin

# Initialise mise
~/.local/bin/mise activate fish | source

# Load zoxide
zoxide init --cmd cd fish | source

# Load nvim as default editor
export EDITOR='nvim'

# OS Aliases
alias cls="clear"
alias vim="nvim"
alias vi="nvim"
alias v="nvim"
alias python=python3
alias vc="open $1 -a \"Visual Studio Code\""
alias cu="open $1 -a \"Cursor\""

# Terraform Aliases
alias tf="terraform"

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
alias buu="mise run bundle-update"
alias gsp="mise run set-gcp-project"

alias git-pull="mise run pull-all-repos"
alias git-check="mise run check-all-repos"
alias banish="mise run banish-ds-store"
alias git-empty="mise run empty-commit"

alias ti="mise run terraform-init"
alias tc="mise run terraform-console"
alias taa="mise run terraform-auto-apply"
alias ta="mise run terraform-apply"
alias tp="mise run terraform-plan"

macchina
