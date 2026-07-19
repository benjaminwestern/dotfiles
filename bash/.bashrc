# Homebrew PATH (for Apple Silicon)
export PATH=$PATH:/opt/homebrew/bin
export PATH=$PATH:/opt/homebrew/sbin

# Add ~/.local/bin to PATH
if [ -d "$HOME/.local/bin" ]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

# WSL launched from Windows inherits the native Windows working directory.
# Start an ordinary login in Linux home so mise does not mistake the native
# Windows ~/.config/mise tree for a project configuration.
if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  case "$PWD" in
    /mnt/?/Users/"${USER:-$(basename "$HOME")}") cd "$HOME" || true ;;
  esac
fi

# Initialize mise
if command -v mise >/dev/null 2>&1; then
  eval "$(mise -C "$HOME" activate bash)"
fi

if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init bash)"; fi

# Initialize zoxide
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init --cmd cd bash)"
fi
