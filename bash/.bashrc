# Homebrew PATH (for Apple Silicon)
export PATH=$PATH:/opt/homebrew/bin
export PATH=$PATH:/opt/homebrew/sbin

# Add ~/.local/bin to PATH
if [ -d "$HOME/.local/bin" ]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

# Initialize mise
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate bash)"
fi

if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init bash)"; fi

# Initialize zoxide
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init --cmd cd bash)"
fi
