#!/bin/zsh
# =============================================================================
# personal-bootstrap-macos.zsh -- macOS personal layer bootstrap
#
# Runs AFTER foundation-macos.zsh has completed successfully. Sources the
# shared library (lib/common.zsh) and reads the state file that foundation
# already populated with all resolved feature flags. Every step is gated by
# its corresponding RESOLVED_* flag — there is NO interactive target
# selection in this script.
#
# Usage:
#   ./personal-bootstrap-macos.zsh
#   ./personal-bootstrap-macos.zsh --dry-run
#   MODE=personal ./personal-bootstrap-macos.zsh
#
# Prerequisites:
#   - foundation-macos.zsh has been run at least once (state file exists)
#   - Homebrew is installed and on PATH
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.zsh"

MODE="${MODE:-personal}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/benjaminwestern/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
BOOTSTRAP_ROOT="${BOOTSTRAP_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

personal_usage() {
  cat <<'EOF'
Usage:
  personal-bootstrap-macos.zsh [options]

Options:
  --dotfiles-repo <url>    Override dotfiles repository URL
  --dotfiles-dir <path>    Override the local dotfiles checkout path
  --dry-run                Show what would happen without making changes
  --non-interactive        Disable gum-styled prompts and panels
  -h, --help               Show this help text

Notes:
  This script consumes resolved state written by the foundation layer.
  Feature-flag overrides are normally set through install.sh, environment
  variables, or ~/.config/dotfiles/state.env before this script runs.
EOF
}

parse_personal_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dotfiles-repo)
        [[ $# -ge 2 ]] || fail "--dotfiles-repo requires a value"
        DOTFILES_REPO="$2"
        shift 2
        ;;
      --dotfiles-dir)
        [[ $# -ge 2 ]] || fail "--dotfiles-dir requires a value"
        DOTFILES_DIR="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      -h|--help)
        personal_usage
        exit 0
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done
}

parse_personal_args "$@"

# -----------------------------------------------------------------------------
# Read the state file to populate all RESOLVED_* variables.
# Foundation has already resolved every flag; we just consume them here.
# If the state file is missing (e.g. user runs personal before foundation),
# the RESOLVED_* variables will be empty and each step falls back to its
# hard default from the flag catalog.
# -----------------------------------------------------------------------------
local env_enable_dotfiles="${ENABLE_DOTFILES:-}"
state_read

# The state file stores ENABLE_* keys, but this script consumes RESOLVED_*.
# Foundation resolves them; when personal runs alone, mirror the dotfiles flag.
# Env overrides state to match the public loader's resolution precedence.
RESOLVED_DOTFILES="${RESOLVED_DOTFILES:-${env_enable_dotfiles:-${ENABLE_DOTFILES:-true}}}"


# =============================================================================
# SECTION 2: DOTFILES REPO
# =============================================================================

# ensure_repo -- Clone the dotfiles repo if absent, or pull latest changes
#
# Checks: Whether $DOTFILES_DIR/.git exists.
# Gates: None — always runs because the repo is needed for everything else.
# Side effects: Clones or fetches+pulls the dotfiles repository.
# Idempotency: Safe. Uses --ff-only so it will never force-merge.
#
# Status:
#   pass  -- repo exists and is up to date
#   fix   -- repo was cloned or updated via pull
#   fail  -- git operations failed unexpectedly
ensure_repo() {
  if [[ -d "$DOTFILES_DIR/.git" ]]; then
    git -C "$DOTFILES_DIR" fetch --all --prune >/dev/null 2>&1

    local before after
    before="$(git -C "$DOTFILES_DIR" rev-parse HEAD)"
    git -C "$DOTFILES_DIR" pull --ff-only >/dev/null 2>&1 || true
    after="$(git -C "$DOTFILES_DIR" rev-parse HEAD)"

    if [[ "$before" == "$after" ]]; then
      status_pass "Dotfiles repo" "up to date"
    else
      status_fix "Dotfiles repo" "pulled new changes"
    fi
    return 0
  fi

  run_or_dry git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  if dry_run_active; then
    status_fix "Dotfiles repo" "would clone from $DOTFILES_REPO"
  else
    status_fix "Dotfiles repo" "cloned from $DOTFILES_REPO"
  fi
}


# =============================================================================
# SECTION 3: BREW BUNDLE (CASKS / TAPS / MAS / TAPPED FORMULAE)
# =============================================================================

# apply_brew_bundle -- Install Homebrew casks, taps, Mac App Store apps, and
#                     tapped formulae that cannot be managed by mise.
#
# Checks: Whether brew and the Brewfile are available.
# Gates: None — always runs.
# Side effects: Installs/upgrades Homebrew casks/taps/formulae.
# Idempotency: brew bundle is idempotent — already-installed packages are
#              skipped.
#
# NOTE: Core Homebrew formulae are now managed by mise [bootstrap.packages] in
#       ~/.config/mise/config.toml. Do NOT run `brew bundle cleanup` manually,
#       because it will try to remove those mise-managed formulae. Use
#       `mise run bundle-update` (or `mise bootstrap packages install` +
#       `mise upgrade`) and `brew autoremove` instead.
#
# Status:
#   pass -- bundle completed with package count
#   fail -- brew or Brewfile not found
apply_brew_bundle() {
  local brewfile="$DOTFILES_DIR/brew/Brewfile"

  if ! command_exists brew; then
    status_fail "Brew bundle" "brew not found on PATH"
    return 0
  fi

  if [[ ! -f "$brewfile" ]]; then
    status_fail "Brew bundle" "Brewfile not found at $brewfile"
    return 0
  fi

  if dry_run_active; then
    local pkg_count
    pkg_count="$(brew bundle list --file="$brewfile" 2>/dev/null | wc -l | tr -d ' ')"
    dry_run_log "brew bundle --file=$brewfile ($pkg_count packages)"
    status_fix "Brew bundle" "would install/update $pkg_count packages"
    return 0
  fi

  local output
  output="$(brew bundle --file="$brewfile" 2>&1)" || true

  # Count installed packages for the status line
  local pkg_count
  pkg_count="$(brew bundle list --file="$brewfile" 2>/dev/null | wc -l | tr -d ' ')"

  status_pass "Brew bundle" "$pkg_count packages"
}


# =============================================================================
# SECTION 4: DOTFILES (mise)
# =============================================================================

# apply_dotfiles -- Converge mise [dotfiles] symlinks
#
# What: Runs `mise dotfiles apply` so mise owns the dotfile layer.
# Why:  Dotfile mappings are declared in ~/.config/mise/config.toml under
#       [dotfiles]. This replaces the previous Tuckr-based symlink setup.
# Checks: Whether mise is installed.
# Gates: RESOLVED_DOTFILES — controls whether mise dotfiles are applied.
#        (Older state files may contain ENABLE_TUCKR; it is honoured as a
#        fallback during state migration.)
# Side effects: Creates/converges symlinks declared in [dotfiles]. Pre-creates
#               ~/.ssh and sets mode 700 because [dotfiles] does not guarantee
#               directory permissions.
# Idempotency: mise dotfiles apply is convergent — it skips targets already
#              matching the desired state.
#
# Status:
#   pass -- dotfiles applied
#   skip -- RESOLVED_DOTFILES is false
#   fail -- mise not found on PATH
apply_dotfiles() {
  local enabled="${RESOLVED_DOTFILES:-true}"

  if [[ "$enabled" != "true" ]]; then
    status_skip "Mise dotfiles" "disabled by flag"
    return 0
  fi

  if ! command_exists mise; then
    status_fail "Mise dotfiles" "mise not found on PATH"
    return 0
  fi

  if dry_run_active; then
    dry_run_log "mkdir -p ~/.ssh && chmod 700 ~/.ssh && mise dotfiles apply"
    status_fix "Mise dotfiles" "would apply"
    return 0
  fi

  mkdir -p "$HOME/.ssh" "$HOME/.config" \
           "$HOME/.config/borders" "$HOME/.config/gh" \
           "$HOME/.config/ghostty" "$HOME/.config/git" \
           "$HOME/.config/hypr" "$HOME/.config/opencode" \
           "$HOME/.config/pitchfork" "$HOME/.config/worktrunk" \
           "$HOME/.pi"
  chmod 700 "$HOME/.ssh"

  mise dotfiles apply >/dev/null 2>&1

  status_pass "Mise dotfiles" "applied"
}


# =============================================================================
# SECTION 5: SHELL DEFAULT
# =============================================================================

# apply_shell_default -- Set the preferred shell as the user's login shell
#
# Checks: RESOLVED_SHELL for which shell binary to use. Verifies the binary
#         exists, is listed in /etc/shells, and is the current $SHELL.
# Gates: RESOLVED_SHELL_DEFAULT — skips when "false" or empty (default: true).
# Side effects: May append to /etc/shells (requires sudo). May run chsh.
# Idempotency: Checks current $SHELL before acting; no-ops if already set.
#
# Logic:
#   1. Determine shell binary path from RESOLVED_SHELL:
#      - fish: /opt/homebrew/bin/fish or /usr/local/bin/fish
#      - zsh:  /opt/homebrew/bin/zsh or /bin/zsh (system fallback)
#   2. If the binary doesn't exist, status_fail
#   3. If not in /etc/shells, add it (needs sudo)
#   4. If $SHELL != binary, run chsh -s
#
# Status:
#   pass -- shell already set as default
#   fix  -- shell was changed or added to /etc/shells
#   skip -- disabled by flag
#   fail -- shell binary not found
apply_shell_default() {
  local enabled="${RESOLVED_SHELL_DEFAULT:-true}"

  if [[ "$enabled" != "true" ]]; then
    status_skip "Default shell" "disabled by flag"
    return 0
  fi

  local preferred="${RESOLVED_SHELL:-fish}"
  local shell_bin=""

  # Determine the shell binary path based on the preferred shell
  case "$preferred" in
    fish)
      if [[ -x /opt/homebrew/bin/fish ]]; then
        shell_bin="/opt/homebrew/bin/fish"
      elif [[ -x /usr/local/bin/fish ]]; then
        shell_bin="/usr/local/bin/fish"
      fi
      ;;
    zsh)
      if [[ -x /opt/homebrew/bin/zsh ]]; then
        shell_bin="/opt/homebrew/bin/zsh"
      elif [[ -x /bin/zsh ]]; then
        shell_bin="/bin/zsh"
      fi
      ;;
    *)
      status_fail "Default shell" "unknown shell: $preferred"
      return 0
      ;;
  esac

  if [[ -z "$shell_bin" ]]; then
    status_fail "Default shell" "$preferred not found on this system"
    return 0
  fi

  local changed=false

  # Ensure the shell binary is registered in /etc/shells
  if ! grep -qx "$shell_bin" /etc/shells 2>/dev/null; then
    run_or_dry sudo sh -c "echo '$shell_bin' >> /etc/shells"
    changed=true
  fi

  # Change the login shell if it doesn't already match
  if [[ "$SHELL" != "$shell_bin" ]]; then
    run_or_dry chsh -s "$shell_bin"
    changed=true
  fi

  if dry_run_active && [[ "$changed" == "true" ]]; then
    status_fix "Default shell" "would set to $shell_bin"
  elif [[ "$changed" == "true" ]]; then
    status_fix "Default shell" "set to $shell_bin"
  else
    status_pass "Default shell" "$shell_bin"
  fi
}


# =============================================================================
# SECTION 6: MACOS DEFAULTS
# =============================================================================

# apply_macos_defaults -- Run the defaults-macos.sh preferences script
#
# Checks: Whether the defaults script exists at the expected path.
# Gates: RESOLVED_MACOS_DEFAULTS — skips when "false" or empty (default: true).
# Side effects: Writes macOS system and application preferences via `defaults`
#               commands. Passes the short hostname to the script.
# Idempotency: The defaults script itself is idempotent — it writes the same
#              values each time.
#
# Status:
#   pass -- defaults script ran successfully
#   skip -- disabled by flag
#   fail -- defaults script not found or returned non-zero
apply_macos_defaults() {
  local enabled="${RESOLVED_MACOS_DEFAULTS:-true}"

  if [[ "$enabled" != "true" ]]; then
    status_skip "macOS defaults" "disabled by flag"
    return 0
  fi

  local defaults_script="$DOTFILES_DIR/Other/scripts/macos/defaults-macos.sh"

  if [[ ! -f "$defaults_script" ]]; then
    status_fail "macOS defaults" "script not found at $defaults_script"
    return 0
  fi

  if dry_run_active; then
    dry_run_log "/bin/bash $defaults_script $(hostname -s)"
    status_fix "macOS defaults" "would apply for $(hostname -s)"
    return 0
  fi

  /bin/bash "$defaults_script" "$(hostname -s)"
  status_pass "macOS defaults" "applied for $(hostname -s)"
}


# =============================================================================
# SECTION 7: ROSETTA
# =============================================================================

# apply_rosetta -- Install Rosetta 2 on Apple Silicon Macs
#
# Checks: CPU architecture via `uname -m`. Whether oahd (Rosetta daemon) is
#         already running.
# Gates: RESOLVED_ROSETTA — skips when "false" or empty (default: true).
# Side effects: Installs Rosetta 2 via softwareupdate on first run.
# Idempotency: Checks for the oahd process before attempting installation;
#              no-ops if Rosetta is already present.
#
# Status:
#   pass -- Rosetta already installed (oahd running)
#   fix  -- Rosetta was just installed
#   skip -- disabled by flag, or not Apple Silicon (Intel Mac)
apply_rosetta() {
  local enabled="${RESOLVED_ROSETTA:-true}"

  if [[ "$enabled" != "true" ]]; then
    status_skip "Rosetta 2" "disabled by flag"
    return 0
  fi

  # Only relevant on Apple Silicon
  if [[ "$(uname -m)" != "arm64" ]]; then
    status_skip "Rosetta 2" "not Apple Silicon"
    return 0
  fi

  # Check if Rosetta is already installed by looking for the oahd daemon
  if pgrep -q oahd 2>/dev/null; then
    status_pass "Rosetta 2" "already installed"
    return 0
  fi

  run_or_dry softwareupdate --install-rosetta --agree-to-license
  if dry_run_active; then
    status_fix "Rosetta 2" "would install"
  else
    status_fix "Rosetta 2" "installed"
  fi
}


# =============================================================================
# SECTION 8: MAIN
# =============================================================================

main() {
  setup_gum_theme

  # Pre-flight: snapshot what's already in place before making changes
  preflight_inventory

  local dry_label=""
  if dry_run_active; then
    dry_label="\n*** DRY RUN — no changes will be made ***"
  fi
  panel "macOS personal bootstrap\nMode: $MODE\nShell: ${RESOLVED_SHELL:-fish}\nRepo: $DOTFILES_REPO${dry_label}"

  # Step 1: Always ensure repo is up to date
  ensure_repo

  # Step 2: Full brew bundle with feature-flag env vars
  apply_brew_bundle

  # Step 3: mise dotfiles (gated)
  apply_dotfiles

  # Step 4: Set default shell (gated)
  apply_shell_default

  # Step 5: macOS defaults (gated)
  apply_macos_defaults

  # Step 6: Rosetta (gated)
  apply_rosetta

  # Summary
  status_summary "Personal"
  success "Personal bootstrap completed."
}

main
