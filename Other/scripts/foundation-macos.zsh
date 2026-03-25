#!/bin/zsh
# =============================================================================
# foundation-macos.zsh -- macOS foundation bootstrap
#
# Installs and configures the core tooling layer that every macOS machine needs
# regardless of personal preferences: Homebrew, CLI utilities, shell profile
# integration, mise language runtime seeding, and optional Zscaler TLS trust.
#
# Can be invoked in two ways:
#   1. Via bootstrap.sh (env vars pre-populated from CLI parsing)
#   2. Directly: ./foundation-macos.zsh setup --shell fish --profile work
#
# Architecture:
#   Sources lib/common.zsh for all shared utilities (status output, state file,
#   flag resolution, managed block writer, gum UI helpers).
#
# Design principles:
#   - Absolute idempotency: check before act, never destructive
#   - Feature-flag gating: every function respects RESOLVED_* flags
#   - Status output: every ensure/check emits status_pass/fix/skip/fail
#   - Shell-aware: writes correct profile block for RESOLVED_SHELL
# =============================================================================

set -euo pipefail


# =============================================================================
# SECTION 1: HEADER & CONSTANTS
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.zsh"

# -- Foundation Homebrew packages ---------------------------------------------
# The minimum set of CLI tools installed on every macOS machine. gum is included
# here so there is no separate ensure_gum step -- it arrives with the rest of
# the foundation packages.
#
# NOTE: mise is NOT in this list. It can be installed via Homebrew OR via the
# shell installer (curl https://mise.run | sh). The ensure_mise() function
# handles both paths and detects which method was used for updates.
FOUNDATION_BREW_PACKAGES=(git gh jq yq fzf fd ripgrep zoxide lazygit openssl gum)

# -- Mise paths ---------------------------------------------------------------
MISE_CONFIG_DIR="$HOME/.config/mise"
MISE_CONFIG_PATH="$MISE_CONFIG_DIR/config.toml"
MISE_ENV_PATH="$MISE_CONFIG_DIR/.env"

# -- Certificate / Zscaler paths ---------------------------------------------
CERTS_DIR="$HOME/certs"
ZSCALER_CHAIN_PATH="$CERTS_DIR/zscaler_chain.pem"
GOLDEN_BUNDLE_PATH="$CERTS_DIR/golden_pem.pem"

# -- Bootstrap root -----------------------------------------------------------
# When called directly (not via bootstrap.sh), BOOTSTRAP_ROOT defaults to the
# dotfiles repository root (two levels above this script).
BOOTSTRAP_ROOT="${BOOTSTRAP_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# -- MODE env var -------------------------------------------------------------
# May be pre-set by bootstrap.sh or the caller's environment.
MODE="${MODE:-}"


# =============================================================================
# SECTION 2: ARGUMENT PARSING
# =============================================================================

# parse_foundation_args -- Parse CLI arguments for direct invocation
#
# What: Accepts the same flags as bootstrap.sh so the foundation script can be
#       run standalone without the entrypoint wrapper.
# Why:  Enables direct execution for testing, CI, or users who prefer to skip
#       the entrypoint.
# Checks: Validates mode is not set twice; required values have arguments.
# Gates: None (always runs).
# Side effects: Populates CLI_* global variables used by resolve_all_flags.
# Idempotency: Overwrites CLI_* vars with the same values each time.
#
# Stores results in:
#   CLI_SHELL, CLI_PROFILE, CLI_ENABLE_ZSCALER, CLI_ENABLE_WORK_APPS,
#   CLI_ENABLE_HOME_APPS, CLI_ENABLE_GUI, CLI_ENABLE_TUCKR,
#   CLI_ENABLE_MACOS_DEFAULTS, CLI_ENABLE_ROSETTA, CLI_ENABLE_MISE_TOOLS,
#   CLI_ENABLE_SHELL_DEFAULT, NON_INTERACTIVE, ENABLE_PERSONAL
typeset -g CLI_SHELL=""
typeset -g CLI_PROFILE=""
typeset -g CLI_ENABLE_ZSCALER=""
typeset -g CLI_ENABLE_WORK_APPS=""
typeset -g CLI_ENABLE_HOME_APPS=""
typeset -g CLI_ENABLE_GUI=""
typeset -g CLI_ENABLE_TUCKR=""
typeset -g CLI_ENABLE_MACOS_DEFAULTS=""
typeset -g CLI_ENABLE_ROSETTA=""
typeset -g CLI_ENABLE_MISE_TOOLS=""
typeset -g CLI_ENABLE_SHELL_DEFAULT=""

parse_foundation_args() {
  # If bootstrap.sh already parsed, these env vars will be set. Use them as
  # starting values so CLI flags here can override.
  CLI_SHELL="${PREFERRED_SHELL:-}"
  CLI_PROFILE="${DEVICE_PROFILE:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      setup|ensure|update|personal)
        if [[ -n "$MODE" ]]; then
          fail "Mode already set to '$MODE'; cannot set again to '$1'"
        fi
        MODE="$1"
        shift
        ;;
      --shell)
        [[ $# -ge 2 ]] || fail "--shell requires a value"
        CLI_SHELL="$2"
        shift 2
        ;;
      --profile)
        [[ $# -ge 2 ]] || fail "--profile requires a value"
        CLI_PROFILE="$2"
        shift 2
        ;;
      --enable-zscaler)     CLI_ENABLE_ZSCALER="true";  shift ;;
      --disable-zscaler)    CLI_ENABLE_ZSCALER="false"; shift ;;
      --enable-work-apps)   CLI_ENABLE_WORK_APPS="true";  shift ;;
      --disable-work-apps)  CLI_ENABLE_WORK_APPS="false"; shift ;;
      --enable-home-apps)   CLI_ENABLE_HOME_APPS="true";  shift ;;
      --disable-home-apps)  CLI_ENABLE_HOME_APPS="false"; shift ;;
      --enable-gui)         CLI_ENABLE_GUI="true";  shift ;;
      --disable-gui)        CLI_ENABLE_GUI="false"; shift ;;
      --enable-tuckr)       CLI_ENABLE_TUCKR="true";  shift ;;
      --disable-tuckr)      CLI_ENABLE_TUCKR="false"; shift ;;
      --enable-macos-defaults)  CLI_ENABLE_MACOS_DEFAULTS="true";  shift ;;
      --disable-macos-defaults) CLI_ENABLE_MACOS_DEFAULTS="false"; shift ;;
      --enable-rosetta)     CLI_ENABLE_ROSETTA="true";  shift ;;
      --disable-rosetta)    CLI_ENABLE_ROSETTA="false"; shift ;;
      --enable-mise-tools)  CLI_ENABLE_MISE_TOOLS="true";  shift ;;
      --disable-mise-tools) CLI_ENABLE_MISE_TOOLS="false"; shift ;;
      --enable-shell-default)  CLI_ENABLE_SHELL_DEFAULT="true";  shift ;;
      --disable-shell-default) CLI_ENABLE_SHELL_DEFAULT="false"; shift ;;
      --personal)
        ENABLE_PERSONAL=1
        shift
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --dotfiles-repo)
        [[ $# -ge 2 ]] || fail "--dotfiles-repo requires a value"
        DOTFILES_REPO="$2"
        shift 2
        ;;
      --personal-script)
        [[ $# -ge 2 ]] || fail "--personal-script requires a value"
        PERSONAL_SCRIPT="$2"
        shift 2
        ;;
      -h|--help)
        printf 'Usage: foundation-macos.zsh <setup|ensure|update|personal> [options]\n'
        printf 'Options: --shell, --profile, --enable-*/--disable-*, --personal, --non-interactive, --dry-run\n'
        exit 0
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done
}


# =============================================================================
# SECTION 3: HOMEBREW
# =============================================================================

# ensure_homebrew -- Install Homebrew if it is not already present
#
# What: Checks for brew on PATH. If missing, verifies Xcode CLT are installed
#       (required by the Homebrew installer), then runs the official install
#       script in non-interactive mode.
# Why:  Homebrew is the package manager for everything else in the foundation.
# Checks: command_exists brew, xcode-select -p
# Gates: None (always runs).
# Side effects: May install Xcode CLT (triggers Apple UI), may install Homebrew.
# Idempotency: No-op if brew is already on PATH.
#
# Status:
#   pass  -- Homebrew already installed
#   fix   -- Homebrew was just installed
#   fail  -- Xcode CLT needed (user must complete install and re-run)
ensure_homebrew() {
  # Use pre-flight data if available to avoid redundant checks
  if [[ "${PREFLIGHT_HOMEBREW:-}" == "installed" ]] || command_exists brew; then
    status_pass "Homebrew" "${PREFLIGHT_HOMEBREW_VERSION:-already installed}"
    return 0
  fi

  # Xcode CLT are required before Homebrew can be installed
  if ! xcode-select -p >/dev/null 2>&1; then
    if dry_run_active; then
      dry_run_log "xcode-select --install"
      status_fix "Homebrew" "would trigger Xcode CLT install"
      return 0
    fi
    xcode-select --install || true
    status_fail "Homebrew" "Xcode CLT install triggered -- complete it and re-run"
  fi

  if dry_run_active; then
    dry_run_log "install Homebrew via official installer"
    status_fix "Homebrew" "would install"
    return 0
  fi

  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  status_fix "Homebrew" "installed"
}

# brew_shellenv -- Eval brew shellenv for the running zsh session
#
# What: Detects the Homebrew prefix (/opt/homebrew on ARM, /usr/local on Intel)
#       and evals brew shellenv to put brew and its packages on PATH.
# Why:  Needed immediately after installing Homebrew so subsequent commands
#       (brew install, mise, etc.) can be found.
# Checks: Tests for brew binary at both prefix locations.
# Gates: None.
# Side effects: Modifies PATH, HOMEBREW_PREFIX, etc. in the current shell.
# Idempotency: Safe to call repeatedly; shellenv is additive.
brew_shellenv() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

# ensure_foundation_packages -- Install missing packages from FOUNDATION_BREW_PACKAGES
#
# What: Iterates the package list, checks each with `brew list`, installs any
#       that are missing. Reports counts.
# Why:  Ensures every machine has the baseline CLI toolset.
# Checks: brew list per package.
# Gates: None (always runs).
# Side effects: Installs Homebrew formulae.
# Idempotency: Skips packages that are already installed.
#
# Status:
#   pass -- "N/N present" if all packages already installed
#   fix  -- "installed M missing" if some were installed this run
ensure_foundation_packages() {
  local pkg
  local present=0
  local missing=0
  local total=${#FOUNDATION_BREW_PACKAGES[@]}

  for pkg in "${FOUNDATION_BREW_PACKAGES[@]}"; do
    if brew list "$pkg" >/dev/null 2>&1; then
      (( present++ )) || true
    else
      run_or_dry brew install "$pkg"
      (( missing++ )) || true
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    status_pass "Foundation packages" "${present}/${total} present"
  elif dry_run_active; then
    status_fix "Foundation packages" "would install ${missing} missing"
  else
    status_fix "Foundation packages" "installed ${missing} missing"
  fi
}

# ensure_mise -- Install mise if not present (Homebrew OR shell installer)
#
# What: Checks whether mise is already available on PATH. If not, attempts
#       to install it via Homebrew first (preferred — integrates with brew
#       upgrade). Falls back to the shell installer (curl https://mise.run)
#       if Homebrew installation fails or is unavailable.
# Why:  mise is the development runtime version manager. It must be available
#       before any mise-managed tools can be installed. Unlike other foundation
#       packages, mise has a first-party shell installer that works without a
#       package manager, making it suitable for minimal or non-Homebrew setups.
# Checks: command -v mise on PATH.
# Gates: None — always runs. mise is required for language runtimes.
# Side effects: Installs mise binary (via brew install or curl | sh).
#               May modify PATH (shell installer places mise in ~/.local/bin).
# Idempotency: No-op if mise is already on PATH.
#
# Install priority:
#   1. Already installed (any method) → pass
#   2. Homebrew available → brew install mise
#   3. Homebrew unavailable or fails → curl https://mise.run | sh
#
# Status:
#   pass -- mise already installed (with version and install method)
#   fix  -- mise was just installed (via brew or shell installer)
ensure_mise() {
  if command_exists mise; then
    local ver
    ver="$(mise --version 2>/dev/null || echo "unknown")"
    local method="unknown"
    if brew list mise >/dev/null 2>&1; then
      method="homebrew"
    elif [[ -x "$HOME/.local/bin/mise" ]]; then
      method="shell installer"
    fi
    status_pass "Mise" "$ver ($method)"
    return 0
  fi

  # Try Homebrew first
  if command_exists brew; then
    run_or_dry brew install mise
    if dry_run_active; then
      status_fix "Mise" "would install via Homebrew"
      return 0
    fi

    if command_exists mise; then
      status_fix "Mise" "installed via Homebrew"
      return 0
    fi
  fi

  # Fallback: shell installer
  if dry_run_active; then
    dry_run_log "curl https://mise.run | sh"
    status_fix "Mise" "would install via shell installer"
    return 0
  fi

  curl -fsSL https://mise.run | sh
  export PATH="$HOME/.local/bin:$PATH"

  if command_exists mise; then
    status_fix "Mise" "installed via shell installer (~/.local/bin/mise)"
  else
    status_fail "Mise" "installation failed — neither brew nor shell installer succeeded"
  fi
}

# update_brew_packages -- Update, upgrade, and clean Homebrew
#
# What: Runs brew update, upgrade, cleanup, and autoremove in sequence.
# Why:  Keeps all Homebrew-managed software current and disk usage lean.
# Checks: None (brew handles its own state).
# Gates: MODE=update only (caller is responsible for gating).
# Side effects: Updates Homebrew index, upgrades all formulae/casks, removes
#               stale downloads and orphaned dependencies.
# Idempotency: Safe to run repeatedly; no-op if everything is current.
#
# Status:
#   pass -- "update + upgrade + cleanup complete"
update_brew_packages() {
  run_or_dry brew update
  run_or_dry brew upgrade
  run_or_dry brew cleanup
  run_or_dry brew autoremove
  if dry_run_active; then
    status_fix "Homebrew update" "would run update + upgrade + cleanup"
  else
    status_pass "Homebrew update" "update + upgrade + cleanup complete"
  fi
}


# =============================================================================
# SECTION 4: SHELL PROFILE
# =============================================================================

# profile_block_zsh -- Generate the zsh managed block content
#
# What: Produces the shell initialization lines for zsh, wrapped in managed
#       block markers. Each tool activation is guarded by command_exists so
#       the profile is safe even if a tool is not yet installed.
# Why:  Ensures brew, mise, and zoxide are activated in every new zsh session.
# Checks: None (pure string generation).
# Gates: None.
# Side effects: None.
# Idempotency: Always returns the same string.
profile_block_zsh() {
  cat <<'EOF'
# >>> foundation-bootstrap >>>
if command -v brew >/dev/null 2>&1; then eval "$(brew shellenv)"; fi
if command -v mise >/dev/null 2>&1; then eval "$(mise activate zsh)"; fi
if command -v zoxide >/dev/null 2>&1; then eval "$(zoxide init zsh)"; fi
# <<< foundation-bootstrap <<<
EOF
}

# profile_block_fish -- Generate the fish managed block content
#
# What: Produces the shell initialization lines for fish, wrapped in managed
#       block markers. Written to a conf.d file so fish sources it automatically.
#       Each tool activation is guarded by `type -q`.
# Why:  Ensures brew, mise, and zoxide are activated in every new fish session.
# Checks: None (pure string generation).
# Gates: None.
# Side effects: None.
# Idempotency: Always returns the same string.
profile_block_fish() {
  cat <<'EOF'
# >>> foundation-bootstrap >>>
if type -q brew; eval (brew shellenv); end
if type -q mise; mise activate fish | source; end
if type -q zoxide; zoxide init fish | source; end
# <<< foundation-bootstrap <<<
EOF
}

# ensure_profile_block -- Write the managed profile block for the resolved shell
#
# What: Determines the correct profile file and block content based on
#       RESOLVED_SHELL, then uses write_managed_block to idempotently write it.
# Why:  The user's preferred shell must have brew/mise/zoxide activation.
# Checks: Compares existing block content against desired content.
# Gates: None (always runs).
# Side effects: Creates or updates the shell profile file.
# Idempotency: No-op if the block is already present and correct.
#
# Status:
#   pass -- block already present and correct
#   fix  -- block written or updated
ensure_profile_block() {
  local target_file=""
  local block_content=""

  if [[ "$RESOLVED_SHELL" == "fish" ]]; then
    target_file="$HOME/.config/fish/conf.d/00-foundation.fish"
    block_content="$(profile_block_fish)"
  else
    target_file="$HOME/.zshrc"
    block_content="$(profile_block_zsh)"
  fi

  # Check if block already exists and matches
  if [[ -f "$target_file" ]] && grep -qF "$PROFILE_BEGIN" "$target_file"; then
    # Extract current block and compare
    local current_block=""
    current_block="$(awk "/$PROFILE_BEGIN/,/$PROFILE_END/" "$target_file")"
    if [[ "$current_block" == "$block_content" ]]; then
      status_pass "Shell profile block" "$RESOLVED_SHELL profile up to date"
      return 0
    fi
  fi

  write_managed_block "$target_file" "$PROFILE_BEGIN" "$PROFILE_END" "$block_content"
  if dry_run_active; then
    status_fix "Shell profile block" "would write $RESOLVED_SHELL profile to $target_file"
  else
    status_fix "Shell profile block" "wrote $RESOLVED_SHELL profile to $target_file"
  fi
}

# activate_shell -- Activate brew, mise, and zoxide in the RUNNING zsh session
#
# What: Evals brew shellenv, mise activate zsh, and zoxide init zsh for the
#       current process. Only activates mise/zoxide if they exist on PATH.
# Why:  The foundation script itself always runs in zsh (regardless of
#       RESOLVED_SHELL), so we need these tools active for subsequent steps
#       like `mise install`.
# Checks: command_exists for mise and zoxide before eval.
# Gates: None.
# Side effects: Modifies PATH and shell state for the current process.
# Idempotency: Safe to call repeatedly; each eval is additive/overwriting.
activate_shell() {
  eval "$(brew shellenv)"

  if command_exists mise; then
    eval "$(mise activate zsh)"
  fi

  if command_exists zoxide; then
    eval "$(zoxide init zsh)"
  fi
}


# =============================================================================
# SECTION 5: MISE
# =============================================================================

# seed_mise_block -- Generate the seed mise config.toml content
#
# What: Produces a config.toml snippet with experimental settings, env file
#       reference, and a curated set of language runtimes and tools. Wrapped
#       in managed block markers.
# Why:  Gives every machine a consistent baseline of language runtimes without
#       requiring manual configuration.
# Checks: None (pure string generation).
# Gates: None.
# Side effects: None.
# Idempotency: Always returns the same string.
seed_mise_block() {
  cat <<'EOF'
# >>> foundation-seed >>>
[settings]
experimental = true

[env]
_.file = "~/.config/mise/.env"

[tools]
go = "latest"
node = "latest"
bun = "latest"
python = "latest"
uv = "latest"
terraform = "latest"
gcloud = "latest"
usage = "latest"
# <<< foundation-seed <<<
EOF
}

# ensure_seed_mise_config -- Create or update the mise seed configuration
#
# What: If no mise config exists, creates it with the seed block. If one exists
#       with our managed markers, updates the managed section. If one exists
#       without markers, leaves it alone (user-managed config).
# Why:  Ensures mise knows which runtimes to install, but never overwrites
#       user customizations outside the managed block.
# Checks: File existence, presence of managed markers.
# Gates: None (always runs).
# Side effects: May create or modify ~/.config/mise/config.toml.
# Idempotency: No-op if config is already in the desired state.
#
# Status:
#   pass -- config exists with correct seed block
#   fix  -- config created or seed block updated
#   skip -- user config detected (no markers), left unchanged
ensure_seed_mise_config() {
  mkdir -p "$MISE_CONFIG_DIR"

  if [[ ! -f "$MISE_CONFIG_PATH" ]]; then
    seed_mise_block > "$MISE_CONFIG_PATH"
    status_fix "Mise seed config" "created $MISE_CONFIG_PATH"
    return 0
  fi

  if grep -qF "$MISE_BEGIN" "$MISE_CONFIG_PATH"; then
    # Check if existing block matches
    local current_block=""
    current_block="$(awk "/$MISE_BEGIN/,/$MISE_END/" "$MISE_CONFIG_PATH")"
    local desired_block=""
    desired_block="$(seed_mise_block)"

    if [[ "$current_block" == "$desired_block" ]]; then
      status_pass "Mise seed config" "already up to date"
    else
      write_managed_block "$MISE_CONFIG_PATH" "$MISE_BEGIN" "$MISE_END" "$desired_block"
      status_fix "Mise seed config" "updated managed block"
    fi
    return 0
  fi

  # Config exists but has no managed markers -- user owns it
  status_skip "Mise seed config" "user config detected at $MISE_CONFIG_PATH"
}

# ensure_mise_tools -- Install all tools defined in mise config
#
# What: Runs `mise install` to ensure every tool in config.toml is present at
#       the specified version.
# Why:  Language runtimes are needed for development and for Zscaler cert
#       bundle building (Python certifi).
# Checks: None (mise install is inherently idempotent).
# Gates: RESOLVED_MISE_TOOLS (skipped if "false").
# Side effects: Downloads and installs language runtimes.
# Idempotency: mise install skips tools that are already at the correct version.
#
# Status:
#   pass -- mise install succeeded
#   skip -- disabled by RESOLVED_MISE_TOOLS=false
ensure_mise_tools() {
  if [[ "${RESOLVED_MISE_TOOLS:-true}" != "true" ]]; then
    status_skip "Mise tools install" "disabled by flag"
    return 0
  fi

  run_or_dry mise install
  if dry_run_active; then
    status_fix "Mise tools install" "would run mise install"
  else
    status_pass "Mise tools install" "complete"
  fi
}

# update_mise -- Upgrade mise binary and all managed tools
#
# What: Upgrades the mise binary (via brew or self-update), then runs
#       `mise upgrade` and `mise install` to bring all tools to latest.
# Why:  Keeps runtimes current during update mode.
# Checks: Whether mise was installed via brew (to choose upgrade path).
# Gates: MODE=update and RESOLVED_MISE_TOOLS=true (caller gates MODE; this
#        function gates RESOLVED_MISE_TOOLS).
# Side effects: Upgrades binaries and runtimes.
# Idempotency: No-op if everything is already at latest.
#
# Status:
#   pass -- upgrade complete
#   skip -- disabled by RESOLVED_MISE_TOOLS=false
update_mise() {
  if [[ "${RESOLVED_MISE_TOOLS:-true}" != "true" ]]; then
    status_skip "Mise update" "disabled by flag"
    return 0
  fi

  if brew list mise >/dev/null 2>&1; then
    run_or_dry brew upgrade mise || true
  else
    run_or_dry mise self-update || true
  fi

  run_or_dry mise upgrade || true
  run_or_dry mise install
  if dry_run_active; then
    status_fix "Mise update" "would upgrade binary + tools"
  else
    status_pass "Mise update" "binary + tools upgraded"
  fi
}


# =============================================================================
# SECTION 6: ZSCALER
# =============================================================================

# detect_zscaler -- Probe TLS to detect Zscaler MITM proxy
#
# What: Connects to registry.npmjs.org via openssl s_client and inspects the
#       certificate issuer field for "Zscaler".
# Why:  When behind a Zscaler proxy, all TLS connections use Zscaler's CA.
#       Tools like npm, pip, and git will fail unless we inject the Zscaler
#       chain into their trust stores.
# Checks: TLS handshake to registry.npmjs.org:443.
# Gates: None.
# Side effects: None (read-only network probe).
# Idempotency: Pure detection -- safe to call repeatedly.
#
# Returns: 0 if Zscaler detected, 1 otherwise.
detect_zscaler() {
  local issuer
  issuer=$(openssl s_client -connect registry.npmjs.org:443 \
    -servername registry.npmjs.org < /dev/null 2>/dev/null |
    openssl x509 -noout -issuer 2>/dev/null || true)
  [[ "$issuer" == *Zscaler* ]]
}

# python_certifi_path -- Get the path to Python's certifi CA bundle
#
# What: Asks Python's bundled certifi package for its certificate bundle path.
# Why:  The golden bundle is built by concatenating certifi's bundle with the
#       Zscaler chain, giving tools a complete trust store.
# Checks: Requires python3 with pip's vendored certifi.
# Gates: None.
# Side effects: None.
# Idempotency: Pure query.
#
# Prints: The absolute path to cacert.pem, or empty string on failure.
python_certifi_path() {
  python3 -c 'import pip._vendor.certifi as c; print(c.where())' 2>/dev/null || true
}

# fetch_zscaler_chain -- Download the Zscaler certificate chain
#
# What: Uses openssl s_client with -showcerts to capture the full certificate
#       chain presented by Zscaler's proxy, extracts PEM blocks, and writes
#       them to ZSCALER_CHAIN_PATH.
# Why:  The chain file is needed to build the golden CA bundle.
# Checks: None (overwrites existing chain file).
# Gates: None.
# Side effects: Creates/overwrites ZSCALER_CHAIN_PATH.
# Idempotency: Produces the same output given the same network conditions.
fetch_zscaler_chain() {
  if dry_run_active; then
    dry_run_log "fetch Zscaler cert chain from registry.npmjs.org → $ZSCALER_CHAIN_PATH"
    return 0
  fi
  mkdir -p "$CERTS_DIR"
  openssl s_client -showcerts -connect registry.npmjs.org:443 \
    -servername registry.npmjs.org < /dev/null 2>/dev/null |
    awk '/-----BEGIN CERTIFICATE-----/{p=1}; p; /-----END CERTIFICATE-----/{p=0}' \
    > "$ZSCALER_CHAIN_PATH"
}

# validate_zscaler_chain -- Verify the fetched chain contains Zscaler certs
#
# What: Checks that the chain file exists, is non-empty, and that its first
#       certificate's issuer contains "Zscaler".
# Why:  Guards against corrupted or empty downloads before building the bundle.
# Checks: File existence, size, and issuer field.
# Gates: None.
# Side effects: None.
# Idempotency: Pure validation.
#
# Returns: 0 if valid, 1 otherwise.
validate_zscaler_chain() {
  [[ -s "$ZSCALER_CHAIN_PATH" ]] || return 1
  openssl x509 -in "$ZSCALER_CHAIN_PATH" -noout -issuer 2>/dev/null | grep -q "Zscaler"
}

# build_golden_bundle -- Concatenate certifi + Zscaler chain into golden bundle
#
# What: Finds the Python certifi CA bundle, concatenates it with the Zscaler
#       chain, and writes the result to GOLDEN_BUNDLE_PATH.
# Why:  The golden bundle is a complete trust store that includes both public
#       CAs and the corporate Zscaler CA, allowing all tools to verify TLS.
# Checks: python_certifi_path must return a valid path.
# Gates: None.
# Side effects: Creates/overwrites GOLDEN_BUNDLE_PATH.
# Idempotency: Produces the same output given the same inputs.
build_golden_bundle() {
  if dry_run_active; then
    dry_run_log "build golden CA bundle → $GOLDEN_BUNDLE_PATH"
    return 0
  fi
  local certifi_path
  certifi_path="$(python_certifi_path)"
  [[ -n "$certifi_path" ]] || fail "Unable to locate a Python certifi bundle via python3."
  cat "$certifi_path" "$ZSCALER_CHAIN_PATH" > "$GOLDEN_BUNDLE_PATH"
}

# zscaler_env_block -- Generate the env var block for Zscaler TLS trust
#
# What: Produces a block of environment variable assignments that point every
#       major tool's CA config at the golden bundle. Written to mise's .env
#       file so the vars are active in every shell session.
# Why:  Each tool has its own env var for custom CA bundles. Setting all of
#       them ensures no tool is left untrusted behind Zscaler.
# Checks: None (pure string generation).
# Gates: None.
# Side effects: None.
# Idempotency: Always returns the same string (for the same GOLDEN_BUNDLE_PATH).
zscaler_env_block() {
  cat <<EOF
# >>> zscaler-bootstrap >>>
SSL_CERT_FILE="$GOLDEN_BUNDLE_PATH"
SSL_CERT_DIR="$CERTS_DIR"
CERT_PATH="$GOLDEN_BUNDLE_PATH"
CERT_DIR="$CERTS_DIR"
REQUESTS_CA_BUNDLE="$GOLDEN_BUNDLE_PATH"
CURL_CA_BUNDLE="$GOLDEN_BUNDLE_PATH"
NODE_EXTRA_CA_CERTS="$GOLDEN_BUNDLE_PATH"
GRPC_DEFAULT_SSL_ROOTS_FILE_PATH="$GOLDEN_BUNDLE_PATH"
GIT_SSL_CAINFO="$GOLDEN_BUNDLE_PATH"
CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE="$GOLDEN_BUNDLE_PATH"
PIP_CERT="$GOLDEN_BUNDLE_PATH"
NPM_CONFIG_CAFILE="$GOLDEN_BUNDLE_PATH"
npm_config_cafile="$GOLDEN_BUNDLE_PATH"
AWS_CA_BUNDLE="$GOLDEN_BUNDLE_PATH"
# <<< zscaler-bootstrap <<<
EOF
}

# ensure_zscaler_env -- Write the Zscaler env block to mise's .env file
#
# What: Uses write_managed_block to idempotently write the TLS env vars into
#       the mise .env file so they are sourced on every shell activation.
# Why:  Mise's _.file directive reads this .env, making the vars available to
#       all tools activated by mise.
# Checks: Existing block content via write_managed_block.
# Gates: None.
# Side effects: Creates or modifies MISE_ENV_PATH.
# Idempotency: No-op if block is already present and correct.
ensure_zscaler_env() {
  write_managed_block "$MISE_ENV_PATH" "$ZSCALER_ENV_BEGIN" "$ZSCALER_ENV_END" "$(zscaler_env_block)"
}

# configure_tls_clients -- Set CA paths in git, pip, and gcloud configs
#
# What: Configures git's global http.sslcainfo, pip's global cert, and gcloud's
#       custom CA cert file to point at the golden bundle.
# Why:  Some tools read config files in addition to (or instead of) env vars.
# Checks: command_exists for python3 and gcloud before configuring them.
# Gates: None.
# Side effects: Modifies git global config, pip config, gcloud config.
# Idempotency: Overwrites the same settings with the same values.
configure_tls_clients() {
  run_or_dry git config --global http.sslcainfo "$GOLDEN_BUNDLE_PATH"

  if command_exists python3; then
    run_or_dry python3 -m pip config set global.cert "$GOLDEN_BUNDLE_PATH" >/dev/null 2>&1 || true
  fi

  if command_exists gcloud; then
    run_or_dry gcloud config set core/custom_ca_certs_file "$GOLDEN_BUNDLE_PATH" >/dev/null 2>&1 || true
  fi
}

# validate_zscaler_runtime -- Post-check: verify Zscaler trust is functional
#
# What: Verifies that the golden bundle exists, git config is correct, and
#       npm ping works (if node/npm are available).
# Why:  Catches configuration drift or incomplete Zscaler setup.
# Checks: File existence, git config value, npm connectivity.
# Gates: None (called only when Zscaler is active).
# Side effects: None (read-only checks).
# Idempotency: Pure validation.
#
# Status:
#   pass/fail per individual check
validate_zscaler_runtime() {
  if [[ -f "$GOLDEN_BUNDLE_PATH" ]]; then
    status_pass "Zscaler: golden bundle exists"
  else
    status_fail "Zscaler: golden bundle exists" "file missing at $GOLDEN_BUNDLE_PATH"
  fi

  if [[ -f "$MISE_ENV_PATH" ]]; then
    status_pass "Zscaler: mise .env exists"
  else
    status_fail "Zscaler: mise .env exists" "file missing at $MISE_ENV_PATH"
  fi

  local git_ca
  git_ca="$(git config --global --get http.sslcainfo || true)"
  if [[ "$git_ca" == "$GOLDEN_BUNDLE_PATH" ]]; then
    status_pass "Zscaler: git sslcainfo"
  else
    status_fail "Zscaler: git sslcainfo" "expected $GOLDEN_BUNDLE_PATH, got $git_ca"
  fi

  if command_exists node && command_exists npm; then
    if npm ping >/dev/null 2>&1; then
      status_pass "Zscaler: npm ping"
    else
      status_fail "Zscaler: npm ping" "npm registry unreachable"
    fi
  fi

  if command_exists python3; then
    if python3 -m pip --version >/dev/null 2>&1; then
      status_pass "Zscaler: pip functional"
    else
      status_fail "Zscaler: pip functional" "pip command failed"
    fi
  fi
}

# handle_zscaler -- Orchestrator for all Zscaler TLS trust configuration
#
# What: Evaluates RESOLVED_ZSCALER to decide whether to configure Zscaler trust.
#       When proceeding: fetches chain, validates it, builds golden bundle,
#       writes env vars, activates shell, and configures TLS clients.
# Why:  Centralizes the Zscaler decision logic and execution sequence.
# Checks: RESOLVED_ZSCALER value, detect_zscaler() for auto mode.
# Gates: RESOLVED_ZSCALER (false=skip, auto=detect, true=force).
# Side effects: May create cert files, modify configs, write state.
# Idempotency: Re-running produces the same state if network conditions match.
#
# Status:
#   skip -- disabled by flag or auto-detect found no Zscaler
#   fix  -- Zscaler trust configured
#   pass -- Zscaler trust already configured (all validation checks pass)
handle_zscaler() {
  # Gate: disabled
  if [[ "${RESOLVED_ZSCALER:-false}" == "false" ]]; then
    status_skip "Zscaler trust" "disabled by flag"
    return 0
  fi

  # Gate: auto-detect
  if [[ "${RESOLVED_ZSCALER:-false}" == "auto" ]]; then
    if detect_zscaler; then
      note "Zscaler detected on this network. Configuring TLS trust."
      state_set "ENABLE_ZSCALER" "true"
    else
      status_skip "Zscaler trust" "not detected on this network"
      state_set "ENABLE_ZSCALER" "false"
      return 0
    fi
  fi

  # Proceed: RESOLVED_ZSCALER=true or auto-detected
  # Check if already fully configured
  if [[ -f "$GOLDEN_BUNDLE_PATH" ]] && [[ -f "$MISE_ENV_PATH" ]] \
    && [[ "$(git config --global --get http.sslcainfo 2>/dev/null || true)" == "$GOLDEN_BUNDLE_PATH" ]]; then
    status_pass "Zscaler trust" "already configured"
    return 0
  fi

  fetch_zscaler_chain
  validate_zscaler_chain || fail "Detected active Zscaler, but failed to validate the fetched certificate chain."
  build_golden_bundle
  ensure_zscaler_env
  activate_shell
  configure_tls_clients
  status_fix "Zscaler trust" "configured"
}


# =============================================================================
# SECTION 7: VALIDATION
# =============================================================================

# validate_foundation -- Run individual checks and emit status per check
#
# What: Verifies that every critical tool is installed and functional. Checks
#       are conditional on feature flags where appropriate.
# Why:  Provides a clear pass/fail report at the end of the bootstrap run so
#       the user knows exactly what is working and what is not.
# Checks: command_exists and --version for each tool.
# Gates: RESOLVED_MISE_TOOLS for runtime checks, Zscaler state for TLS checks.
# Side effects: None (read-only validation).
# Idempotency: Pure validation -- safe to call any number of times.
#
# Status: emits pass/fail/skip per individual check.
validate_foundation() {
  # Core tools (always checked)
  if command_exists brew; then
    status_pass "Validate: brew"
  else
    status_fail "Validate: brew" "not found"
  fi

  if command_exists mise; then
    status_pass "Validate: mise"
  else
    status_fail "Validate: mise" "not found"
  fi

  if command_exists zoxide; then
    status_pass "Validate: zoxide"
  else
    status_fail "Validate: zoxide" "not found"
  fi

  if command_exists git; then
    status_pass "Validate: git"
  else
    status_fail "Validate: git" "not found"
  fi

  if command_exists openssl; then
    status_pass "Validate: openssl"
  else
    status_fail "Validate: openssl" "not found"
  fi

  # Runtime checks (conditional on RESOLVED_MISE_TOOLS)
  if [[ "${RESOLVED_MISE_TOOLS:-true}" == "true" ]]; then
    if command_exists node && node --version >/dev/null 2>&1; then
      status_pass "Validate: node" "$(node --version 2>/dev/null)"
    else
      status_fail "Validate: node" "not found or not working"
    fi

    if command_exists python && python --version >/dev/null 2>&1; then
      status_pass "Validate: python" "$(python --version 2>/dev/null)"
    else
      status_fail "Validate: python" "not found or not working"
    fi
  else
    status_skip "Validate: node" "mise-tools disabled"
    status_skip "Validate: python" "mise-tools disabled"
  fi

  # Zscaler checks (conditional on active Zscaler)
  local zscaler_active
  zscaler_active="$(state_get ENABLE_ZSCALER 2>/dev/null || true)"
  if [[ "$zscaler_active" == "true" ]] || [[ "${RESOLVED_ZSCALER:-false}" == "true" ]]; then
    validate_zscaler_runtime
  fi
}


# =============================================================================
# SECTION 8: PERSONAL HANDOFF
# =============================================================================

# personal_script_path -- Resolve the path to the personal bootstrap script
#
# What: Returns the absolute path to the personal-bootstrap-macos.zsh script.
#       Honors the PERSONAL_SCRIPT env var if set (supports both absolute and
#       relative paths). Falls back to the default location in the dotfiles repo.
# Why:  Allows overriding the personal script for testing or alternative configs.
# Checks: None.
# Gates: None.
# Side effects: None.
# Idempotency: Pure path resolution.
personal_script_path() {
  if [[ -n "${PERSONAL_SCRIPT:-}" ]]; then
    if [[ "$PERSONAL_SCRIPT" == /* ]]; then
      printf '%s\n' "$PERSONAL_SCRIPT"
    else
      printf '%s\n' "$BOOTSTRAP_ROOT/$PERSONAL_SCRIPT"
    fi
    return 0
  fi

  printf '%s\n' "$BOOTSTRAP_ROOT/Other/scripts/personal-bootstrap-macos.zsh"
}

# run_personal_layer -- Execute the personal bootstrap script
#
# What: Resolves the personal script path and execs it, passing all relevant
#       env vars (MODE, DOTFILES_REPO, BOOTSTRAP_ROOT, all RESOLVED_* flags).
# Why:  The personal layer applies user-specific configuration on top of the
#       foundation.
# Checks: Verifies the script file exists.
# Gates: ENABLE_PERSONAL=1 (caller is responsible for checking).
# Side effects: Spawns a child zsh process running the personal script.
# Idempotency: Depends on the personal script's own idempotency.
#
# Status:
#   skip -- ENABLE_PERSONAL not set
run_personal_layer() {
  if [[ "${ENABLE_PERSONAL:-0}" != "1" ]]; then
    status_skip "Personal layer" "not enabled (pass --personal to enable)"
    return 0
  fi

  local script_path
  script_path="$(personal_script_path)"

  if [[ ! -f "$script_path" ]]; then
    status_fail "Personal layer" "script not found at $script_path"
  fi

  note "Handing off to personal bootstrap: $script_path"
  DOTFILES_REPO="${DOTFILES_REPO:-}" \
    BOOTSTRAP_ROOT="$BOOTSTRAP_ROOT" \
    MODE="$MODE" \
    RESOLVED_SHELL="$RESOLVED_SHELL" \
    RESOLVED_PROFILE="$RESOLVED_PROFILE" \
    NON_INTERACTIVE="$NON_INTERACTIVE" \
    /bin/zsh "$script_path" "$MODE"
  status_pass "Personal layer" "completed"
}


# =============================================================================
# SECTION 9: MODE ORCHESTRATORS
# =============================================================================

# ensure_foundation -- Run all foundation steps in setup/ensure mode
#
# What: Sequential orchestrator for the full foundation provisioning flow.
# Why:  Provides a single entrypoint for the setup/ensure modes.
# Checks: Delegates to individual functions.
# Gates: Delegates to individual functions.
# Side effects: Installs software, writes configs, modifies shell state.
# Idempotency: Every step is individually idempotent.
ensure_foundation() {
  ensure_homebrew
  brew_shellenv
  ensure_foundation_packages
  ensure_mise
  ensure_profile_block
  activate_shell
  ensure_seed_mise_config
  handle_zscaler
  ensure_mise_tools
  validate_foundation
  run_personal_layer
}

# update_foundation -- Run all foundation steps in update mode
#
# What: Sequential orchestrator for the update flow. Same as ensure but also
#       runs brew update/upgrade and mise upgrade.
# Why:  Provides a single entrypoint for the update mode.
# Checks: Delegates to individual functions.
# Gates: Delegates to individual functions.
# Side effects: Upgrades software, writes configs, modifies shell state.
# Idempotency: Every step is individually idempotent.
update_foundation() {
  ensure_homebrew
  brew_shellenv
  update_brew_packages
  ensure_foundation_packages
  ensure_mise
  ensure_profile_block
  activate_shell
  ensure_seed_mise_config
  handle_zscaler
  update_mise
  validate_foundation
  run_personal_layer
}


# =============================================================================
# SECTION 10: MODE SELECTION
# =============================================================================

# select_mode -- Prompt the user to choose a mode if MODE is not set
#
# What: If MODE is empty and gum is available, presents an interactive chooser.
#       If MODE is empty and non-interactive, fails with an error.
# Why:  Supports both interactive first-run and CI/scripted invocations.
# Checks: MODE emptiness, use_gum() availability.
# Gates: NON_INTERACTIVE (fails if mode is empty and non-interactive).
# Side effects: Sets MODE global variable.
# Idempotency: No-op if MODE is already set.
select_mode() {
  if [[ -n "$MODE" ]]; then
    return 0
  fi

  if use_gum; then
    MODE=$(gum choose --header "Choose a macOS foundation mode" setup ensure update personal)
    return 0
  fi

  # Non-interactive and no MODE -- cannot proceed
  fail "MODE is not set and running non-interactively. Pass a mode: setup, ensure, update, or personal."
}


# =============================================================================
# SECTION 11: MAIN
# =============================================================================

main() {
  # Phase 1: Bootstrap minimum deps (need brew + gum for UI)
  # Homebrew must be available before we can install gum, and gum must be
  # available before we can show interactive prompts or themed output.
  ensure_homebrew
  brew_shellenv

  # Phase 2: Parse args and set up UI
  # This handles direct invocation (args on command line) and delegated
  # invocation (env vars from bootstrap.sh).
  parse_foundation_args "$@"
  setup_gum_theme

  # Phase 3: Pre-flight inventory
  # Snapshot everything that's already installed BEFORE making any changes.
  # Populates PREFLIGHT_* globals that ensure_* functions can reference.
  preflight_inventory

  # Phase 4: Read state and resolve all flags
  # The resolution engine walks CLI -> env -> state -> profile -> prompt -> default
  # for every configurable setting.
  state_read
  select_mode
  resolve_all_flags \
    "$CLI_SHELL" \
    "$CLI_PROFILE" \
    "$CLI_ENABLE_ZSCALER" \
    "$CLI_ENABLE_WORK_APPS" \
    "$CLI_ENABLE_HOME_APPS" \
    "$CLI_ENABLE_GUI" \
    "$CLI_ENABLE_TUCKR" \
    "$CLI_ENABLE_MACOS_DEFAULTS" \
    "$CLI_ENABLE_ROSETTA" \
    "$CLI_ENABLE_MISE_TOOLS" \
    "$CLI_ENABLE_SHELL_DEFAULT"

  # Phase 5: Display config panel
  local dry_label=""
  if dry_run_active; then
    dry_label="\n*** DRY RUN — no changes will be made ***"
  fi
  panel "macOS foundation bootstrap\nMode: $MODE\nShell: $RESOLVED_SHELL\nProfile: $RESOLVED_PROFILE${dry_label}"

  # Phase 6: Dispatch
  case "$MODE" in
    setup|ensure)
      ensure_foundation
      ;;
    update)
      update_foundation
      ;;
    personal)
      validate_foundation
      run_personal_layer
      ;;
    *)
      fail "Unsupported mode: $MODE"
      ;;
  esac

  # Phase 7: Summary
  status_summary "Foundation"
  success "Done."
}

main "$@"
