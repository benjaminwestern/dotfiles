# Homebrew PATH (for Apple Silicon)
export PATH=$PATH:/opt/homebrew/bin
export PATH=$PATH:/opt/homebrew/sbin

# Initialize mise
if [ -f "$HOME/.local/bin/mise" ]; then
  eval "$($HOME/.local/bin/mise activate bash)"
fi

# Initialize zoxide
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init --cmd cd bash)"
fi

if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init bash)"; fi
