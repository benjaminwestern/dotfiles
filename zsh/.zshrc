# Keep zsh's path array unique when this file is sourced more than once.
typeset -U path PATH

# Initialise Homebrew for Apple Silicon and Intel prefixes.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Add ~/.local/bin to PATH
if [ -d "$HOME/.local/bin" ]; then
  path=("$HOME/.local/bin" $path)
fi

# WSL launched from Windows inherits the native Windows working directory.
# Start an ordinary login in Linux home so mise does not mistake the native
# Windows ~/.config/mise tree for a project configuration.
if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  case "$PWD" in
    /mnt/?/Users/"${USER:-${HOME:t}}") cd "$HOME" || true ;;
  esac
fi

# Initialize mise
if command -v mise >/dev/null 2>&1; then
  eval "$(mise -C "$HOME" activate zsh)"
fi

if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init zsh)"; fi

# Initialize zoxide
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init --cmd cd zsh)"
fi
