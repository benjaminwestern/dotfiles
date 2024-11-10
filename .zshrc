export PATH=$PATH:/opt/homebrew/anaconda3/bin
export PATH=$PATH:/opt/homebrew/bin
export PATH=$PATH:/Users/benjaminwestern/.deno/bin
export PATH=$PATH:/Users/benjaminwestern/Go/bin
export PATH=$PATH:/opt/homebrew/opt/go/libexec/bin
export PATH=$PATH:/Users/benjaminwestern/bin
export PATH=$PATH:/Users/benjaminwestern/.cache/lm-studio/bin

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
if [[ -f "/opt/homebrew/anaconda3/bin/conda" ]]; then
    eval "$(/opt/homebrew/anaconda3/bin/conda "shell.zsh" "hook" $argv)"
else
    if [[ -f "/opt/homebrew/anaconda3/etc/profile.d/conda.sh" ]]; then
        . "/opt/homebrew/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="/opt/homebrew/anaconda3/bin:$PATH"
    fi
fi
# <<< conda initialize <<<
