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
  --dry-run                Inspect drift and print only required repairs; do not apply them
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
local env_preferred_shell="${PREFERRED_SHELL:-}"
local env_device_profile="${DEVICE_PROFILE:-}"
local env_enable_dotfiles="${ENABLE_DOTFILES:-}"
local env_enable_packages="${ENABLE_PACKAGES:-}"
local env_enable_applications="${ENABLE_APPLICATIONS:-}"
local env_enable_macos_defaults="${ENABLE_MACOS_DEFAULTS:-}"
local env_enable_remote_access="${ENABLE_REMOTE_ACCESS:-}"
local env_enable_rosetta="${ENABLE_ROSETTA:-}"
local env_enable_shell_default="${ENABLE_SHELL_DEFAULT:-}"
local env_enable_code_directory="${ENABLE_CODE_DIRECTORY:-}"
local env_enable_downloads_link="${ENABLE_DOWNLOADS_LINK:-}"
local env_enable_git_identity="${ENABLE_GIT_IDENTITY:-}"
local env_device_name="${DEVICE_NAME:-}"
local env_git_user_name="${GIT_USER_NAME:-}"
local env_git_user_email="${GIT_USER_EMAIL:-}"
local env_macos_hostname="${MACOS_HOSTNAME:-}"
local env_macos_dock="${MACOS_DOCK:-}"
local env_macos_desktop="${MACOS_DESKTOP:-}"
local env_macos_default_apps="${MACOS_DEFAULT_APPS:-}"
local env_macos_menu_bar="${MACOS_MENU_BAR:-}"
local env_macos_mouse="${MACOS_MOUSE:-}"
local env_macos_power="${MACOS_POWER:-}"
local env_macos_finder="${MACOS_FINDER:-}"
local env_macos_screenshots="${MACOS_SCREENSHOTS:-}"
local env_macos_touch_id="${MACOS_TOUCH_ID:-}"
state_read

# The state file stores ENABLE_* keys, but this script consumes RESOLVED_*.
# Foundation resolves them; when personal runs alone, mirror the dotfiles flag.
# Env overrides state to match the public loader's resolution precedence.
RESOLVED_SHELL="${RESOLVED_SHELL:-${env_preferred_shell:-${PREFERRED_SHELL:-fish}}}"
RESOLVED_PROFILE="${RESOLVED_PROFILE:-${env_device_profile:-${DEVICE_PROFILE:-home}}}"
RESOLVED_DOTFILES="${RESOLVED_DOTFILES:-${env_enable_dotfiles:-${ENABLE_DOTFILES:-true}}}"
RESOLVED_PACKAGES="${RESOLVED_PACKAGES:-${env_enable_packages:-${ENABLE_PACKAGES:-true}}}"
RESOLVED_APPLICATIONS="${RESOLVED_APPLICATIONS:-${env_enable_applications:-${ENABLE_APPLICATIONS:-true}}}"
RESOLVED_MACOS_DEFAULTS="${RESOLVED_MACOS_DEFAULTS:-${env_enable_macos_defaults:-${ENABLE_MACOS_DEFAULTS:-true}}}"
RESOLVED_REMOTE_ACCESS="${RESOLVED_REMOTE_ACCESS:-${env_enable_remote_access:-${ENABLE_REMOTE_ACCESS:-true}}}"
RESOLVED_ROSETTA="${RESOLVED_ROSETTA:-${env_enable_rosetta:-${ENABLE_ROSETTA:-true}}}"
RESOLVED_SHELL_DEFAULT="${RESOLVED_SHELL_DEFAULT:-${env_enable_shell_default:-${ENABLE_SHELL_DEFAULT:-true}}}"
RESOLVED_CODE_DIRECTORY="${RESOLVED_CODE_DIRECTORY:-${env_enable_code_directory:-${ENABLE_CODE_DIRECTORY:-false}}}"
RESOLVED_DOWNLOADS_LINK="${RESOLVED_DOWNLOADS_LINK:-${env_enable_downloads_link:-${ENABLE_DOWNLOADS_LINK:-false}}}"
RESOLVED_GIT_IDENTITY="${RESOLVED_GIT_IDENTITY:-${env_enable_git_identity:-${ENABLE_GIT_IDENTITY:-false}}}"
RESOLVED_DEVICE_NAME="${RESOLVED_DEVICE_NAME:-${env_device_name:-${DEVICE_NAME:-$(default_device_name)}}}"
RESOLVED_GIT_USER_NAME="${RESOLVED_GIT_USER_NAME:-${env_git_user_name:-${GIT_USER_NAME:-}}}"
RESOLVED_GIT_USER_EMAIL="${RESOLVED_GIT_USER_EMAIL:-${env_git_user_email:-${GIT_USER_EMAIL:-}}}"
RESOLVED_MACOS_HOSTNAME="${RESOLVED_MACOS_HOSTNAME:-${env_macos_hostname:-${MACOS_HOSTNAME:-true}}}"
RESOLVED_MACOS_DOCK="${RESOLVED_MACOS_DOCK:-${env_macos_dock:-${MACOS_DOCK:-true}}}"
RESOLVED_MACOS_DESKTOP="${RESOLVED_MACOS_DESKTOP:-${env_macos_desktop:-${MACOS_DESKTOP:-true}}}"
RESOLVED_MACOS_DEFAULT_APPS="${RESOLVED_MACOS_DEFAULT_APPS:-${env_macos_default_apps:-${MACOS_DEFAULT_APPS:-true}}}"
RESOLVED_MACOS_MENU_BAR="${RESOLVED_MACOS_MENU_BAR:-${env_macos_menu_bar:-${MACOS_MENU_BAR:-true}}}"
RESOLVED_MACOS_MOUSE="${RESOLVED_MACOS_MOUSE:-${env_macos_mouse:-${MACOS_MOUSE:-true}}}"
RESOLVED_MACOS_POWER="${RESOLVED_MACOS_POWER:-${env_macos_power:-${MACOS_POWER:-true}}}"
RESOLVED_MACOS_FINDER="${RESOLVED_MACOS_FINDER:-${env_macos_finder:-${MACOS_FINDER:-true}}}"
RESOLVED_MACOS_SCREENSHOTS="${RESOLVED_MACOS_SCREENSHOTS:-${env_macos_screenshots:-${MACOS_SCREENSHOTS:-true}}}"
RESOLVED_MACOS_TOUCH_ID="${RESOLVED_MACOS_TOUCH_ID:-${env_macos_touch_id:-${MACOS_TOUCH_ID:-true}}}"


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
    if dry_run_active; then
      local worktree_status="" upstream="" divergence=""
      worktree_status="$(bootstrap_git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null || true)"
      if [[ -n "$worktree_status" ]]; then
        status_skip "Dotfiles repo" "local work present; dry-run would preserve it"
        return 0
      fi
      upstream="$(bootstrap_git -C "$DOTFILES_DIR" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
      if [[ -n "$upstream" ]]; then
        divergence="$(bootstrap_git -C "$DOTFILES_DIR" rev-list --left-right --count "HEAD...$upstream" 2>/dev/null || true)"
      fi
      if [[ "$divergence" == $'0\t0' || "$divergence" == '0 0' ]]; then
        status_pass "Dotfiles repo" "HEAD matches cached $upstream; network not contacted"
      else
        dry_run_log "GIT_CONFIG_GLOBAL=/dev/null git -C $DOTFILES_DIR fetch --all --prune"
        dry_run_log "GIT_CONFIG_GLOBAL=/dev/null git -C $DOTFILES_DIR pull --ff-only"
        status_fix "Dotfiles repo" "would check remote and fast-forward if behind (${divergence:-upstream unknown})"
      fi
      return 0
    fi

    if ! bootstrap_git -C "$DOTFILES_DIR" fetch --all --prune >/dev/null 2>&1; then
      status_fail "Dotfiles repo" "fetch failed"
      return 0
    fi

    local before after
    before="$(bootstrap_git -C "$DOTFILES_DIR" rev-parse HEAD)"
    if ! bootstrap_git -C "$DOTFILES_DIR" pull --ff-only >/dev/null 2>&1; then
      status_fail "Dotfiles repo" "pull --ff-only failed; local work was preserved"
      return 0
    fi
    after="$(bootstrap_git -C "$DOTFILES_DIR" rev-parse HEAD)"

    if [[ "$before" == "$after" ]]; then
      status_pass "Dotfiles repo" "up to date"
    else
      status_fix "Dotfiles repo" "pulled new changes"
    fi
    return 0
  fi

  run_or_dry bootstrap_git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  if dry_run_active; then
    status_fix "Dotfiles repo" "would clone from $DOTFILES_REPO"
  else
    status_fix "Dotfiles repo" "cloned from $DOTFILES_REPO"
  fi
}


# =============================================================================
# SECTION 3: HOME DIRECTORY LAYOUT
# =============================================================================

# apply_home_layout -- Create the local code root and link Downloads to iCloud
#
# Checks: ~/code directory state, iCloud Downloads availability, and the
#         existing ~/Downloads file type/target.
# Gates: RESOLVED_CODE_DIRECTORY and RESOLVED_DOWNLOADS_LINK independently.
# Side effects: Creates ~/code. Replaces ~/Downloads only when it is absent or
#               contains only fresh Finder metadata, then creates the symlink.
# Idempotency: Existing correct directories and links are left unchanged.
# Safety: Downloads directories containing user files and unexpected symlinks
#         are never removed or overwritten. Fresh Finder metadata is ignored,
#         and the stock deny-delete ACL is cleared only after that check.
apply_home_layout() {
  local code_dir="$HOME/code"
  if [[ "${RESOLVED_CODE_DIRECTORY:-false}" != "true" ]]; then
    status_skip "Code directory" "disabled by plan"
  elif [[ -d "$code_dir" ]]; then
    status_pass "Code directory" "$code_dir"
  elif [[ -e "$code_dir" || -L "$code_dir" ]]; then
    status_fail "Code directory" "$code_dir exists but is not a directory"
  elif dry_run_active; then
    dry_run_log "mkdir -p $code_dir"
    status_fix "Code directory" "would create $code_dir"
  else
    mkdir -p "$code_dir"
    status_fix "Code directory" "created $code_dir"
  fi

  local mise_env="$HOME/.config/mise/.env"
  if [[ "${RESOLVED_DOTFILES:-false}" != "true" \
    && "${RESOLVED_MISE_TOOLS:-false}" != "true" \
    && "${RESOLVED_ZSCALER:-false}" == "false" ]]; then
    status_skip "Mise secrets" "Ben's config and Zscaler stages disabled"
  elif [[ ! -f "$mise_env" ]]; then
    status_skip "Mise secrets" "private .env has not been imported"
  else
    local mise_env_mode=""
    mise_env_mode="$(stat -f '%Lp' "$mise_env" 2>/dev/null || true)"
    if [[ "$mise_env_mode" == "600" ]]; then
      status_pass "Mise secrets" "private .env mode is 0600"
    elif dry_run_active; then
      dry_run_log "chmod 600 $mise_env"
      status_fix "Mise secrets" "would restrict mode ${mise_env_mode:-unknown} to 0600"
    else
      chmod 600 "$mise_env"
      status_fix "Mise secrets" "restricted mode ${mise_env_mode:-unknown} to 0600"
    fi
  fi

  local downloads_path="$HOME/Downloads"
  local icloud_downloads="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Downloads"

  if [[ "${RESOLVED_DOWNLOADS_LINK:-false}" != "true" ]]; then
    status_skip "Downloads" "iCloud link disabled by plan"
    return 0
  fi

  if [[ -L "$downloads_path" ]]; then
    local current_target=""
    current_target="$(/usr/bin/readlink "$downloads_path" 2>/dev/null || true)"
    if [[ "$current_target" == "$icloud_downloads" ]]; then
      status_pass "Downloads" "linked to iCloud Drive"
    else
      status_skip "Downloads" "preserved unexpected symlink to ${current_target:-unknown}"
    fi
    return 0
  fi

  if [[ ! -d "$icloud_downloads" ]]; then
    status_skip "Downloads" "iCloud Drive Downloads is not available yet"
    return 0
  fi

  if [[ -e "$downloads_path" ]]; then
    if [[ ! -d "$downloads_path" ]]; then
      status_skip "Downloads" "preserved non-directory path at $downloads_path"
      return 0
    fi
    # Fresh macOS folders may contain only harmless Finder metadata. Treat
    # those markers as empty, but preserve every other entry.
    if [[ -n "$(find "$downloads_path" -mindepth 1 -maxdepth 1 \
      ! \( -type f \( -name .localized -o -name .DS_Store \) \) \
      -print -quit 2>/dev/null)" ]]; then
      status_skip "Downloads" "preserved non-empty local directory for manual reconciliation"
      return 0
    fi
  fi

  if dry_run_active; then
    [[ -f "$downloads_path/.localized" ]] && dry_run_log "rm -f $downloads_path/.localized"
    [[ -f "$downloads_path/.DS_Store" ]] && dry_run_log "rm -f $downloads_path/.DS_Store"
    [[ -d "$downloads_path" ]] && dry_run_log "chmod -N $downloads_path"
    [[ -d "$downloads_path" ]] && dry_run_log "rmdir $downloads_path"
    dry_run_log "ln -s $icloud_downloads $downloads_path"
    status_fix "Downloads" "would link to iCloud Drive"
    return 0
  fi

  if [[ -d "$downloads_path" ]]; then
    [[ -f "$downloads_path/.localized" ]] && rm -f "$downloads_path/.localized"
    [[ -f "$downloads_path/.DS_Store" ]] && rm -f "$downloads_path/.DS_Store"
    # macOS creates ~/Downloads with an `everyone deny delete` ACL. The owner
    # can clear it without elevation once the safety check above proves the
    # folder contains no user data.
    chmod -N "$downloads_path"
    rmdir "$downloads_path"
  fi
  ln -s "$icloud_downloads" "$downloads_path"
  status_fix "Downloads" "linked to iCloud Drive"
}


# =============================================================================
# SECTION 4: BREW BUNDLE (CASKS / TAPS / MAS / TAPPED FORMULAE)
# =============================================================================

# apply_brew_bundle -- Install Homebrew casks, taps, Mac App Store apps, and
#                     tapped formulae that cannot be managed by mise.
#
# Checks: Whether brew and the Brewfile are available.
# Gates: RESOLVED_APPLICATIONS.
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
validate_chrome_cask() {
  local brewfile="${1:?validate_chrome_cask requires a Brewfile path}"
  local chrome_app="/Applications/Google Chrome.app"

  grep -Eq '^[[:space:]]*cask "google-chrome"' "$brewfile" || return 0

  [[ -d "$chrome_app" ]] \
    || status_fail "Google Chrome" "declared by Brewfile but application is absent"

  if ! /usr/bin/codesign --verify --deep --strict "$chrome_app" >/dev/null 2>&1; then
    status_fail "Google Chrome" "code signature validation failed"
  fi

  local signing_details=""
  signing_details="$(/usr/bin/codesign -dv --verbose=4 "$chrome_app" 2>&1 || true)"
  if ! printf '%s\n' "$signing_details" | grep -qx 'Identifier=com.google.Chrome' \
    || ! printf '%s\n' "$signing_details" | grep -qx 'TeamIdentifier=EQHXZ8M8AV'; then
    status_fail "Google Chrome" "unexpected signing identity"
  fi

  local quarantine_count="0"
  quarantine_count="$(/usr/bin/xattr -lr "$chrome_app" 2>/dev/null \
    | grep -c 'com.apple.quarantine:' || true)"
  if [[ "$quarantine_count" -gt 0 ]]; then
    local assessment=""
    if ! assessment="$(/usr/sbin/spctl --assess --type execute --verbose=4 \
      "$chrome_app" 2>&1)"; then
      local reason=""
      reason="$(printf '%s\n' "$assessment" | sed '/^$/d' | tail -1)"
      status_fail "Google Chrome" "Gatekeeper rejected assessment: ${reason:-unknown error}"
    fi
    status_pass "Google Chrome" "Google signature valid; Gatekeeper accepted"
  else
    status_pass "Google Chrome" "Google signature valid; quarantine already cleared"
  fi
}

apply_brew_bundle() {
  local brewfile="$DOTFILES_DIR/brew/Brewfile"

  if [[ "${RESOLVED_APPLICATIONS:-true}" != "true" ]]; then
    status_skip "Brew bundle" "applications disabled in the selected plan"
    return 0
  fi

  if ! command_exists brew; then
    status_fail "Brew bundle" "brew not found on PATH"
    return 0
  fi

  # jq is a bootstrap implementation dependency for narrowly inspecting
  # Homebrew trust metadata; it does not imply Ben's CLI catalogue.
  if ! command_exists jq; then
    run_or_dry brew install jq
  fi

  if [[ ! -f "$brewfile" ]]; then
    status_fail "Brew bundle" "Brewfile not found at $brewfile"
    return 0
  fi

  if dry_run_active; then
    local bundle_check="" unsatisfied="" unsatisfied_count=0 total_count=0
    if bundle_check="$(HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1 \
      brew bundle check --verbose --file="$brewfile" 2>&1)"; then
      total_count="$(brew bundle list --all --file="$brewfile" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
      validate_chrome_cask "$brewfile"
      status_pass "Brew bundle" "$total_count declared entries satisfied"
      return 0
    fi
    unsatisfied="$(printf '%s\n' "$bundle_check" | sed -n 's/^→ /INSTALL /p')"
    unsatisfied_count="$(printf '%s\n' "$unsatisfied" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ -z "$unsatisfied" ]]; then
      printf '%s\n' "$bundle_check"
      status_fail "Brew bundle" "could not derive an installation plan"
      return 0
    fi
    while IFS= read -r bundle_action; do
      [[ -n "$bundle_action" ]] && dry_run_log "$bundle_action"
    done <<< "$unsatisfied"
    status_fix "Brew bundle" "would satisfy $unsatisfied_count missing or outdated entry(s)"
    return 0
  fi

  # Microsoft publishes the two SQL formulae from a third-party tap without
  # mise-compatible API metadata. Homebrew requires an explicit trust decision.
  if ! brew tap | grep -qx 'microsoft/mssql-release'; then
    note "Adding the Microsoft SQL Server Homebrew tap required by the Brewfile."
    brew tap microsoft/mssql-release
  fi

  local trust_json=""
  trust_json="$(brew trust --json=v1 2>/dev/null || printf '{}')"
  if ! printf '%s\n' "$trust_json" | jq -e '
      (.taps // [] | index("microsoft/mssql-release")) != null or
      (((.formulae // []) | index("microsoft/mssql-release/msodbcsql18")) != null and
       ((.formulae // []) | index("microsoft/mssql-release/mssql-tools18")) != null)
    ' >/dev/null; then
    panel "Third-party formula trust\n\nThe Brewfile needs only Microsoft's msodbcsql18 and mssql-tools18 formulae.\nHomebrew will refuse to load them until you explicitly trust those two formulae."
    if ! use_gum; then
      status_fail "Microsoft SQL trust" "interactive consent required; rerun in a terminal"
      return 0
    fi
    if ! gum confirm --default \
      --affirmative="Trust formulae" --negative="Stop" \
      "Trust the two declared Microsoft SQL formulae?"; then
      status_fail "Microsoft SQL trust" "operator declined formula trust"
      return 0
    fi
    brew trust --formula \
      microsoft/mssql-release/msodbcsql18 \
      microsoft/mssql-release/mssql-tools18
  fi

  warn "Homebrew will ask whether to proceed, then each Microsoft SQL formula will ask you to type YES for its licence. The bootstrap never accepts those licences on your behalf."
  warn "Some casks request an administrator password. MacTeX can remain quiet for several minutes while its privileged installer runs."

  if ! brew list --cask mactex >/dev/null 2>&1; then
    note "MacTeX is a multi-gigabyte privileged installer. It may request a password and remain quiet for several minutes; do not interrupt it."
  fi

  # Vendor-self-updating casks (notably Chrome) remain declared and therefore
  # uninstallable through Homebrew, but their privileged updaters own version
  # changes. This avoids Homebrew racing a root-owned, already-updated app.
  if ! HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1 brew bundle --file="$brewfile"; then
    status_fail "Brew bundle" "installation failed"
    return 0
  fi

  validate_chrome_cask "$brewfile"

  if grep -Eq '^[[:space:]]*cask "mactex"' "$brewfile" \
    && [[ ! -x /Library/TeX/texbin/latex ]]; then
    status_fail "Brew bundle" "MacTeX metadata is present but /Library/TeX/texbin/latex is not ready"
    return 0
  fi

  # Count installed packages for the status line
  local pkg_count
  pkg_count="$(brew bundle list --all --file="$brewfile" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"

  status_pass "Brew bundle" "$pkg_count packages"
}


# =============================================================================
# SECTION 5: DOTFILES (mise)
# =============================================================================

# apply_dotfiles -- Converge mise [dotfiles] symlinks
#
# What: Runs `mise dotfiles apply` for every declared target except the gated
#       global Git config, so mise owns the dotfile layer.
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

  if ! command_exists jq; then
    run_or_dry brew install jq
  fi

  local dotfiles_json="" ssh_mode="absent"
  dotfiles_json="$(bootstrap_mise dotfiles status --json 2>/dev/null || true)"
  if [[ -z "$dotfiles_json" ]]; then
    status_fail "Mise dotfiles" "could not read declarative dotfile status"
    return 0
  fi

  local -a dotfile_targets
  dotfile_targets=()
  local discovered_target
  while IFS= read -r discovered_target; do
    [[ -n "$discovered_target" ]] && dotfile_targets+=("$discovered_target")
  done <<< "$(printf '%s\n' "$dotfiles_json" | jq -r '
    [.files[], .edits[]?]
    | .[]
    | select(.target != "~/.gitconfig" and .state != "applied")
    | .target
  ')"
  [[ -d "$HOME/.ssh" ]] && ssh_mode="$(stat -f '%Lp' "$HOME/.ssh" 2>/dev/null || printf unknown)"

  local safe_total
  safe_total="$(printf '%s\n' "$dotfiles_json" | jq -r '
    [.files[], .edits[]?] | map(select(.target != "~/.gitconfig")) | length
  ')"

  if [[ "$safe_total" -eq 0 ]]; then
    status_fail "Mise dotfiles" "no safe targets discovered"
    return 0
  fi

  if dry_run_active; then
    local change_count=${#dotfile_targets[@]}
    if [[ "$ssh_mode" != "700" ]]; then
      dry_run_log "CHANGE ~/.ssh permissions: $ssh_mode -> 700"
      change_count=$((change_count + 1))
    fi
    local dotfile_target
    for dotfile_target in "${dotfile_targets[@]}"; do
      dry_run_log "APPLY $dotfile_target"
    done
    if [[ "$change_count" -eq 0 ]]; then
      status_pass "Mise dotfiles" "$safe_total safe targets applied; ~/.ssh mode 0700; Git config handled separately"
    else
      status_fix "Mise dotfiles" "would correct $change_count target or permission change(s)"
    fi
    return 0
  fi

  if [[ ${#dotfile_targets[@]} -eq 0 && "$ssh_mode" == "700" ]]; then
    status_pass "Mise dotfiles" "$safe_total safe targets already applied; Git config handled separately"
    return 0
  fi

  mkdir -p "$HOME/.ssh" "$HOME/.config" \
           "$HOME/.config/borders" "$HOME/.config/gh" \
           "$HOME/.config/ghostty" "$HOME/.config/git" \
           "$HOME/.config/hypr" "$HOME/.config/opencode" \
           "$HOME/.config/pitchfork" "$HOME/.config/worktrunk" \
           "$HOME/.pi"
  chmod 700 "$HOME/.ssh"

  if [[ ${#dotfile_targets[@]} -gt 0 ]]; then
    note "Mise will show only drifted dotfile links with Yes highlighted; press Return to apply them."
    if ! bootstrap_mise dotfiles apply "${dotfile_targets[@]}"; then
      status_fail "Mise dotfiles" "selective apply failed"
      return 0
    fi
  fi

  status_pass "Mise dotfiles" "applied; Git config deferred"
}


# Git configuration ownership -------------------------------------------------
#
# New adopters receive a generated, user-owned ~/.gitconfig. Existing configs
# are never replaced without interactive consent; preserving one writes a small
# identity include and adds that include to the existing file. Ben's historical
# symlink remains supported through git/.gitconfig, which is now only a wrapper
# around the same tracked shared configuration used by generated files.
typeset -gr GIT_CONFIG_MANAGED_MARKER="# Generated by benjaminwestern/dotfiles bootstrap"

git_config_has_include() {
  local config_file="${1:?git_config_has_include requires a config file}"
  local include_path="${2:?git_config_has_include requires an include path}"
  [[ -f "$config_file" ]] || return 1
  command git config --file "$config_file" --get-all include.path 2>/dev/null \
    | grep -Fxq "$include_path"
}

git_config_is_generated() {
  local config_file="${1:?git_config_is_generated requires a config file}"
  [[ -f "$config_file" ]] \
    && grep -Fqx "$GIT_CONFIG_MANAGED_MARKER" "$config_file" 2>/dev/null
}

github_ssh_is_ready() {
  local ssh_result=""
  ssh_result="$(ssh -o BatchMode=yes -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=yes -T git@github.com 2>&1 || true)"
  [[ "$ssh_result" == *"successfully authenticated"* ]]
}

write_generated_git_config() {
  local target="${1:?write_generated_git_config requires a target}"
  local include_shared="${2:-false}"
  local include_github_ssh="${3:-false}"
  local shared_config="$DOTFILES_DIR/git/config.shared"
  local github_ssh_config="$DOTFILES_DIR/git/github-ssh.inc"
  local temp_file=""

  [[ "$include_shared" != "true" || -f "$shared_config" ]] || return 1
  [[ "$include_github_ssh" != "true" || -f "$github_ssh_config" ]] || return 1

  temp_file="$(mktemp "${TMPDIR:-/tmp}/dotfiles-gitconfig.XXXXXX")"
  if ! {
    printf '%s\n' "$GIT_CONFIG_MANAGED_MARKER" > "$temp_file"
    if [[ "${RESOLVED_GIT_IDENTITY:-false}" == "true" ]]; then
      command git config --file "$temp_file" user.name "$RESOLVED_GIT_USER_NAME"
      command git config --file "$temp_file" user.email "$RESOLVED_GIT_USER_EMAIL"
    fi
    if [[ "$include_shared" == "true" ]]; then
      command git config --file "$temp_file" --add include.path "$shared_config"
    fi
    if [[ "$include_github_ssh" == "true" ]]; then
      command git config --file "$temp_file" --add include.path "$github_ssh_config"
    fi
    chmod 600 "$temp_file"
  }; then
    rm -f "$temp_file"
    return 1
  fi

  mv -f "$temp_file" "$target"
}

write_git_identity_include() {
  local identity_file="${1:?write_git_identity_include requires a target}"
  local temp_file=""
  mkdir -p "$(dirname "$identity_file")"
  chmod 700 "$(dirname "$identity_file")"
  temp_file="$(mktemp "${TMPDIR:-/tmp}/dotfiles-git-identity.XXXXXX")"
  if ! {
    command git config --file "$temp_file" user.name "$RESOLVED_GIT_USER_NAME"
    command git config --file "$temp_file" user.email "$RESOLVED_GIT_USER_EMAIL"
    chmod 600 "$temp_file"
  }; then
    rm -f "$temp_file"
    return 1
  fi
  mv -f "$temp_file" "$identity_file"
}

# apply_git_configuration_at -- Resolve ownership modes for explicit paths
apply_git_configuration_at() {
  local target="${1:?apply_git_configuration_at requires a config target}"
  local identity_file="${2:?apply_git_configuration_at requires an identity target}"
  local identity_enabled="${RESOLVED_GIT_IDENTITY:-false}"
  local dotfiles_enabled="${RESOLVED_DOTFILES:-false}"
  if [[ "$identity_enabled" != "true" && "$dotfiles_enabled" != "true" ]]; then
    status_skip "Git configuration" "Git identity and dotfiles are disabled by plan"
    return 0
  fi

  if [[ "$identity_enabled" == "true" ]] \
    && { [[ -z "${RESOLVED_GIT_USER_NAME:-}" ]] || [[ -z "${RESOLVED_GIT_USER_EMAIL:-}" ]]; }; then
    status_fail "Git configuration" "author name and email are required"
    return 0
  fi

  local identity_include="$identity_file"
  [[ "$identity_file" == "$HOME/.config/git/bootstrap-user.inc" ]] \
    && identity_include="~/.config/git/bootstrap-user.inc"
  local shared_config="$DOTFILES_DIR/git/config.shared"
  local github_ssh_config="$DOTFILES_DIR/git/github-ssh.inc"
  local ssh_ready=false

  [[ "$dotfiles_enabled" != "true" || -f "$shared_config" ]] \
    || { status_fail "Git configuration" "shared config missing at $shared_config"; return 0; }

  # No config: create the user-owned file directly. Shared settings are included
  # when dotfiles are selected; the HTTPS-to-SSH rewrite waits for proven SSH.
  if [[ ! -e "$target" && ! -L "$target" ]]; then
    [[ "$dotfiles_enabled" == "true" ]] && github_ssh_is_ready && ssh_ready=true
    if dry_run_active; then
      dry_run_log "CREATE $target as a user-owned Git config"
      [[ "$ssh_ready" == "true" ]] \
        || dry_run_log "DEFER GitHub HTTPS-to-SSH rewrite until GitHub SSH succeeds"
      status_fix "Git configuration" "would create generated ~/.gitconfig"
      return 0
    fi
    if ! write_generated_git_config "$target" "$dotfiles_enabled" "$ssh_ready"; then
      status_fail "Git configuration" "failed to create generated ~/.gitconfig"
      return 0
    fi
    status_fix "Git configuration" "created generated ~/.gitconfig"
    return 0
  fi

  if [[ -d "$target" && ! -L "$target" ]]; then
    status_fail "Git configuration" "$target is a directory"
    return 0
  fi
  if [[ -L "$target" && ! -e "$target" ]]; then
    status_fail "Git configuration" "$target is a broken symlink"
    return 0
  fi
  if [[ ! -f "$target" ]]; then
    status_fail "Git configuration" "$target is not a regular file or valid symlink"
    return 0
  fi

  # A generated file remains bootstrap-owned and is safely regenerated only
  # when its requested identity, shared include, permissions, or SSH include
  # has drifted.
  if git_config_is_generated "$target"; then
    local current_name="" current_email="" current_mode="" generated_changes=0
    local include_shared="$dotfiles_enabled"
    local include_github_ssh="$ssh_ready"
    current_name="$(command git config --file "$target" --get user.name 2>/dev/null || true)"
    current_email="$(command git config --file "$target" --get user.email 2>/dev/null || true)"
    current_mode="$(stat -f '%Lp' "$target" 2>/dev/null || printf unknown)"
    git_config_has_include "$target" "$shared_config" && include_shared=true
    git_config_has_include "$target" "$github_ssh_config" && include_github_ssh=true
    if [[ "$dotfiles_enabled" == "true" && "$include_github_ssh" != "true" ]] \
      && github_ssh_is_ready; then
      ssh_ready=true
      include_github_ssh=true
    fi
    if [[ "$dotfiles_enabled" == "true" ]] \
      && ! git_config_has_include "$target" "$shared_config"; then
      generated_changes=$((generated_changes + 1))
    fi
    [[ "$current_mode" == "600" ]] || generated_changes=$((generated_changes + 1))
    if [[ "$identity_enabled" == "true" ]]; then
      [[ "$current_name" == "$RESOLVED_GIT_USER_NAME" ]] || generated_changes=$((generated_changes + 1))
      [[ "$current_email" == "$RESOLVED_GIT_USER_EMAIL" ]] || generated_changes=$((generated_changes + 1))
    fi
    if [[ "$ssh_ready" == "true" ]] \
      && ! git_config_has_include "$target" "$github_ssh_config"; then
      generated_changes=$((generated_changes + 1))
    fi
    if [[ "$generated_changes" -eq 0 ]]; then
      status_pass "Git configuration" "generated ~/.gitconfig is current"
      return 0
    fi
    if dry_run_active; then
      dry_run_log "REGENERATE $target with $generated_changes correction(s)"
      status_fix "Git configuration" "would update generated ~/.gitconfig"
      return 0
    fi
    if ! write_generated_git_config "$target" "$include_shared" "$include_github_ssh"; then
      status_fail "Git configuration" "failed to update generated ~/.gitconfig"
      return 0
    fi
    status_fix "Git configuration" "updated generated ~/.gitconfig"
    return 0
  fi

  # A prior decision to preserve the existing config is represented by the
  # identity include. Converge it without prompting again.
  if [[ -f "$identity_file" ]]; then
    local include_name="" include_email="" include_mode="" include_changes=0
    include_name="$(command git config --file "$identity_file" --get user.name 2>/dev/null || true)"
    include_email="$(command git config --file "$identity_file" --get user.email 2>/dev/null || true)"
    include_mode="$(stat -f '%Lp' "$identity_file" 2>/dev/null || printf unknown)"
    if [[ "$identity_enabled" == "true" ]]; then
      [[ "$include_name" == "$RESOLVED_GIT_USER_NAME" ]] || include_changes=$((include_changes + 1))
      [[ "$include_email" == "$RESOLVED_GIT_USER_EMAIL" ]] || include_changes=$((include_changes + 1))
    fi
    [[ "$include_mode" == "600" ]] || include_changes=$((include_changes + 1))
    git_config_has_include "$target" "$identity_include" || include_changes=$((include_changes + 1))
    if [[ "$include_changes" -eq 0 ]]; then
      status_pass "Git configuration" "existing ~/.gitconfig plus identity include"
      return 0
    fi
    if dry_run_active; then
      dry_run_log "UPDATE $identity_file and its include in $target"
      status_fix "Git configuration" "would correct preserved-config identity include"
      return 0
    fi
    if [[ "$identity_enabled" == "true" ]] \
      && ! write_git_identity_include "$identity_file"; then
      status_fail "Git configuration" "failed to update identity include"
      return 0
    fi
    chmod 600 "$identity_file"
    if ! git_config_has_include "$target" "$identity_include"; then
      if ! command git config --file "$target" --add include.path "$identity_include"; then
        status_fail "Git configuration" "could not add identity include to existing config"
        return 0
      fi
    fi
    status_fix "Git configuration" "corrected preserved-config identity include"
    return 0
  fi

  # First encounter with an existing config: explicitly offer replacement.
  # Non-interactive mode takes the safe preserve path.
  if [[ "$identity_enabled" != "true" ]]; then
    status_pass "Git configuration" "existing ~/.gitconfig preserved; identity disabled"
    return 0
  fi

  local replace_existing=false
  if use_gum; then
    panel "Existing Git configuration\n\n$target already exists. Replace it with a generated config containing the selected identity and tracked shared settings, or preserve it and add only a machine-local identity include."
    if gum confirm \
      --affirmative="Replace config" --negative="Preserve + include" \
      "Replace the existing ~/.gitconfig?"; then
      replace_existing=true
    fi
  fi

  if [[ "$replace_existing" == "true" ]]; then
    [[ "$dotfiles_enabled" == "true" ]] && github_ssh_is_ready && ssh_ready=true
    if dry_run_active; then
      dry_run_log "REPLACE $target with a generated user-owned Git config"
      status_fix "Git configuration" "would replace existing ~/.gitconfig by consent"
      return 0
    fi
    if ! write_generated_git_config "$target" "$dotfiles_enabled" "$ssh_ready"; then
      status_fail "Git configuration" "failed to replace existing ~/.gitconfig"
      return 0
    fi
    status_fix "Git configuration" "replaced existing ~/.gitconfig by consent"
    return 0
  fi

  if dry_run_active; then
    dry_run_log "PRESERVE $target"
    dry_run_log "CREATE $identity_file and include it from $target"
    status_fix "Git configuration" "would preserve existing config and add identity include"
    return 0
  fi
  if ! write_git_identity_include "$identity_file"; then
    status_fail "Git configuration" "failed to create identity include"
    return 0
  fi
  if ! git_config_has_include "$target" "$identity_include"; then
    if ! command git config --file "$target" --add include.path "$identity_include"; then
      status_fail "Git configuration" "could not add identity include to existing config"
      return 0
    fi
  fi
  status_fix "Git configuration" "preserved existing config and added identity include"
}

# apply_git_configuration -- Use the standard per-user Git paths
apply_git_configuration() {
  apply_git_configuration_at \
    "$HOME/.gitconfig" \
    "$HOME/.config/git/bootstrap-user.inc"
}


# =============================================================================
# SECTION 6: SHELL DEFAULT
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
      elif command_exists brew; then
        run_or_dry brew install fish
        [[ -x /opt/homebrew/bin/fish ]] && shell_bin="/opt/homebrew/bin/fish"
        [[ -x /usr/local/bin/fish ]] && shell_bin="/usr/local/bin/fish"
        dry_run_active && shell_bin="$(brew --prefix)/bin/fish"
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

  note "Changing the login shell can request your macOS password once to register the shell and again for chsh."

  # Ensure the shell binary is registered in /etc/shells
  if ! grep -qx "$shell_bin" /etc/shells 2>/dev/null; then
    run_or_dry sudo sh -c "echo '$shell_bin' >> /etc/shells"
    changed=true
  fi

  # Query Directory Services because $SHELL remains stale until a new login.
  local current_shell
  current_shell="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"

  # Change the login shell if Directory Services does not already match.
  if [[ "$current_shell" != "$shell_bin" ]]; then
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
# SECTION 7: MACOS DEFAULTS
# =============================================================================

# apply_macos_defaults -- Run the defaults-macos.sh preferences script
#
# Checks: Whether the defaults script exists at the expected path.
# Gates: RESOLVED_MACOS_DEFAULTS — skips when "false" or empty (default: true).
# Side effects: Writes macOS system and application preferences via `defaults`,
#               `scutil`, and `pmset`. The defaults script detects the hardware
#               profile and uses it as the canonical machine name.
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

  if [[ "$RESOLVED_MACOS_DEFAULT_APPS" == "true" ]]; then
    if [[ ! -d "/Applications/Google Chrome.app" ]]; then
      status_fail "macOS default apps" "Google Chrome is not installed; select the Brewfile applications stage or install Chrome first"
      return 0
    fi
    if ! command_exists jq; then
      run_or_dry brew install jq
    fi
  fi

  if [[ "$RESOLVED_MACOS_TOUCH_ID" == "true" \
    && ! -f "$(brew --prefix)/lib/pam/pam_reattach.so" ]]; then
    local pam_planned_by_packages=false
    if dry_run_active && [[ "${RESOLVED_PACKAGES:-false}" == "true" ]] \
      && bootstrap_package_missing_lines 2>/dev/null | cut -f1 | grep -Fxq 'brew:pam-reattach'; then
      pam_planned_by_packages=true
    fi
    if [[ "$pam_planned_by_packages" != "true" ]]; then
      run_or_dry brew install pam-reattach
    fi
  fi

  if dry_run_active; then
    local defaults_drift="" drift_count=0 group label current expected
    defaults_drift="$(macos_defaults_drift_lines)"
    if [[ -z "$defaults_drift" ]]; then
      status_pass "macOS defaults" "all enabled preference groups match the resolved plan"
      return 0
    fi
    while IFS=$'\t' read -r group label current expected; do
      [[ -n "$group" ]] || continue
      dry_run_log "CHANGE $group/$label: $current -> $expected"
      drift_count=$((drift_count + 1))
    done <<< "$defaults_drift"
    status_fix "macOS defaults" "would correct $drift_count setting(s)"
    return 0
  fi

  note "Selected hostname, power, and Touch ID groups may request administrator authentication."
  BOOTSTRAP_DEVICE_NAME="$RESOLVED_DEVICE_NAME" \
    MACOS_HOSTNAME="$RESOLVED_MACOS_HOSTNAME" \
    MACOS_DOCK="$RESOLVED_MACOS_DOCK" \
    MACOS_DESKTOP="$RESOLVED_MACOS_DESKTOP" \
    MACOS_DEFAULT_APPS="$RESOLVED_MACOS_DEFAULT_APPS" \
    MACOS_MENU_BAR="$RESOLVED_MACOS_MENU_BAR" \
    MACOS_MOUSE="$RESOLVED_MACOS_MOUSE" \
    MACOS_POWER="$RESOLVED_MACOS_POWER" \
    MACOS_FINDER="$RESOLVED_MACOS_FINDER" \
    MACOS_SCREENSHOTS="$RESOLVED_MACOS_SCREENSHOTS" \
    MACOS_TOUCH_ID="$RESOLVED_MACOS_TOUCH_ID" \
    /bin/bash "$defaults_script"
  status_pass "macOS defaults" "hardware profile and preferences applied"
}


# =============================================================================
# SECTION 8: REMOTE ACCESS
# =============================================================================

# apply_remote_access -- Enable native SSH and Screen Sharing services
#
# Checks: Remote Login state, launchd Screen Sharing state, and membership of
#         the bootstrap user in both macOS service access-control groups.
# Gates: RESOLVED_REMOTE_ACCESS — defaults to true.
# Side effects: May enable Remote Login, enable/bootstrap Screen Sharing, create
#               native access groups, and authorize the current user. Existing
#               members and nested groups are preserved.
# Idempotency: Enabled services and existing memberships are left unchanged.
#
# This intentionally does not enable Apple Remote Management, grant SSH Full
# Disk Access, or configure password-based access for third-party VNC clients.
apply_remote_access() {
  local enabled="${RESOLVED_REMOTE_ACCESS:-true}"
  local ssh_group="com.apple.access_ssh"
  local screen_group="com.apple.access_screensharing"
  local screen_label="system/com.apple.screensharing"
  local screen_plist="/System/Library/LaunchDaemons/com.apple.screensharing.plist"
  local changed=false

  if [[ "$enabled" != "true" ]]; then
    status_skip "Remote access" "disabled by flag"
    return 0
  fi

  if dry_run_active; then
    local access_drift="" drift_count=0 group label current expected
    access_drift="$(remote_access_drift_lines)"
    if [[ -z "$access_drift" ]]; then
      status_pass "Remote access" "Remote Login, Screen Sharing, and user access are enabled"
      return 0
    fi
    while IFS=$'\t' read -r group label current expected; do
      [[ -n "$group" ]] || continue
      dry_run_log "CHANGE $group/$label: $current -> $expected"
      drift_count=$((drift_count + 1))
    done <<< "$access_drift"
    status_fix "Remote access" "would correct $drift_count service or access item(s)"
    return 0
  fi

  note "Remote access requires administrator authentication; enter your password if prompted."
  sudo -v

  local remote_login_state
  if ! remote_login_state="$(sudo systemsetup -getremotelogin 2>&1)"; then
    status_fail "Remote Login" "$remote_login_state"
    return 0
  fi

  if [[ "$remote_login_state" != *"Remote Login: On"* ]]; then
    if ! sudo systemsetup -setremotelogin on; then
      status_fail "Remote Login" "could not enable; Terminal may require Full Disk Access"
      return 0
    fi
    changed=true
  fi

  local screen_overrides
  screen_overrides="$(sudo launchctl print-disabled system 2>/dev/null || true)"
  if printf '%s\n' "$screen_overrides" \
      | grep -Eq '"com\.apple\.screensharing"[[:space:]]*=>[[:space:]]*(disabled|true)'; then
    if ! sudo launchctl enable "$screen_label"; then
      status_fail "Screen Sharing" "could not enable launch service"
      return 0
    fi
    changed=true
  fi

  if ! sudo launchctl print "$screen_label" >/dev/null 2>&1; then
    if ! sudo launchctl bootstrap system "$screen_plist" \
      && ! sudo launchctl print "$screen_label" >/dev/null 2>&1; then
      status_fail "Screen Sharing" "could not bootstrap native launch service"
      return 0
    fi
    changed=true
  fi

  local access_group
  for access_group in "$ssh_group" "$screen_group"; do
    if ! sudo dseditgroup -o read "$access_group" >/dev/null 2>&1; then
      if ! sudo dseditgroup -o create "$access_group"; then
        status_fail "Remote access" "could not create $access_group"
        return 0
      fi
      changed=true
    fi

    if ! sudo dseditgroup -o checkmember -m "$USER" "$access_group" 2>/dev/null \
      | grep -q '^yes '; then
      if ! sudo dseditgroup -o edit -a "$USER" -t user "$access_group"; then
        status_fail "Remote access" "could not authorize $USER in $access_group"
        return 0
      fi
      changed=true
    fi
  done

  if [[ "$changed" == "true" ]]; then
    status_fix "Remote access" "Remote Login and Screen Sharing enabled for $USER"
  else
    status_pass "Remote access" "Remote Login and Screen Sharing enabled for $USER"
  fi
}


# =============================================================================
# SECTION 9: ROSETTA
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
# SECTION 10: MAIN
# =============================================================================

main() {
  setup_gum_theme

  # Pre-flight: snapshot what's already in place before making changes
  preflight_inventory

  local dry_label=""
  if dry_run_active; then
    dry_label="\n*** DRY RUN — no changes will be made ***"
  fi
  panel "macOS personal bootstrap\nMode: $MODE\nProfile: ${RESOLVED_PROFILE:-home}\nShell: ${RESOLVED_SHELL:-fish}\nRepo: $DOTFILES_REPO${dry_label}"

  # Step 1: Always ensure repo is up to date
  ensure_repo

  # Step 2: Converge the managed home directory layout
  apply_home_layout

  # Step 3: Full brew bundle with feature-flag env vars
  apply_brew_bundle

  # Step 4: mise dotfiles (gated)
  apply_dotfiles

  # Step 5: Resolve generated, existing, and identity-include Git config modes
  apply_git_configuration

  # Step 6: Set default shell (gated)
  apply_shell_default

  # Step 7: macOS defaults (gated)
  apply_macos_defaults

  # Step 8: Remote Login and Screen Sharing (gated)
  apply_remote_access

  # Step 9: Rosetta (gated)
  apply_rosetta

  # Summary
  status_summary "Personal"
  success "Personal bootstrap completed."
}

main
