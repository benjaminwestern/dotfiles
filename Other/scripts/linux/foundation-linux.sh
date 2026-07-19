#!/usr/bin/env bash
# Cross-distribution Linux bootstrap for apt and pacman families.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

MODE=''
CLI_PROFILE="${DEVICE_PROFILE:-}"
CLI_SHELL="${PREFERRED_SHELL:-}"
CLI_DEVICE_NAME="${DEVICE_NAME:-}"
CLI_DOWNLOADS_TARGET="${DOWNLOADS_TARGET:-}"
CLI_GIT_USER_NAME="${GIT_USER_NAME:-}"
CLI_GIT_USER_EMAIL="${GIT_USER_EMAIL:-}"

usage() {
  cat <<'EOF'
Usage: foundation-linux.sh [setup|ensure|update|personal] [options]

Options:
  --profile <work|home|minimal>
  --shell <bash|zsh|fish>
  --device-name <hostname>
  --downloads-target <absolute-path>
  --git-name <name>
  --git-email <address>
  --enable-<flag> / --disable-<flag>
  --non-interactive
  --dry-run

Flags:
  packages, applications, mise-tools, dotfiles, code-directory,
  downloads-link, git-identity, linux-defaults, remote-access,
  shell-default, zscaler, linux-hostname, linux-default-apps
EOF
}

set_cli_flag() {
  local name="$1" value="$2"
  name="${name//-/_}"; name="${name^^}"
  if [[ "$name" == LINUX_* && "$name" != LINUX_DEFAULTS ]]; then
    printf -v "CLI_${name}" '%s' "$value"
  else
    printf -v "CLI_ENABLE_${name}" '%s' "$value"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      setup|ensure|update|personal) [[ -z "$MODE" ]] || fail "Mode already set"; MODE="$1"; shift ;;
      --profile) [[ $# -ge 2 ]] || fail "--profile requires a value"; CLI_PROFILE="$2"; shift 2 ;;
      --shell) [[ $# -ge 2 ]] || fail "--shell requires a value"; CLI_SHELL="$2"; shift 2 ;;
      --device-name) [[ $# -ge 2 ]] || fail "--device-name requires a value"; CLI_DEVICE_NAME="$2"; shift 2 ;;
      --downloads-target) [[ $# -ge 2 ]] || fail "--downloads-target requires a value"; CLI_DOWNLOADS_TARGET="$2"; set_cli_flag downloads-link true; shift 2 ;;
      --git-name) [[ $# -ge 2 ]] || fail "--git-name requires a value"; CLI_GIT_USER_NAME="$2"; set_cli_flag git-identity true; shift 2 ;;
      --git-email) [[ $# -ge 2 ]] || fail "--git-email requires a value"; CLI_GIT_USER_EMAIL="$2"; set_cli_flag git-identity true; shift 2 ;;
      --enable-*) set_cli_flag "${1#--enable-}" true; shift ;;
      --disable-*) set_cli_flag "${1#--disable-}" false; shift ;;
      --non-interactive) NON_INTERACTIVE=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help|help) usage; exit 0 ;;
      *) fail "Unknown Linux bootstrap argument: $1" ;;
    esac
  done
  MODE="${MODE:-setup}"
  case "$MODE" in setup|ensure|update|personal) ;; *) fail "Unsupported mode: $MODE" ;; esac
}

ensure_baseline() {
  local specs=() missing=() spec package
  while IFS= read -r spec; do [[ -n "$spec" ]] && specs+=("$spec"); done < <(linux_baseline_package_specs)
  if ! command_exists mise; then
    if dry_run_active; then
      dry_run_log "mise bootstrap packages apply --yes --update ${specs[*]}"
      status_fix "Linux baseline packages" "would run after mise installation"
      return 0
    fi
    fail "mise is required before Linux system packages can be reconciled"
  fi
  for spec in "${specs[@]}"; do
    package="${spec#*:}"
    package_installed "$package" || missing+=("$spec")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    status_pass "Linux baseline packages" "all ${#specs[@]} package(s) installed"
    return 0
  fi
  note "mise will reconcile the minimal $PACKAGE_MANAGER packages; an administrator password may be requested."
  wait_for_package_manager
  if dry_run_active; then
    bootstrap_mise bootstrap packages apply --dry-run --update "${missing[@]}"
    status_fix "Linux baseline packages" "mise would install ${#missing[@]} missing package(s)"
  else
    bootstrap_mise bootstrap packages apply --yes --update "${specs[@]}"
    status_pass "Linux baseline packages" "mise reconciled ${#specs[@]} package(s)"
  fi
  export PATH="$HOME/.local/bin:$PATH"
}

ensure_mise() {
  if command_exists mise; then
    status_pass "Mise" "$(mise --version 2>/dev/null | head -1)"
    return 0
  fi
  if dry_run_active; then
    dry_run_log "curl -fsSL https://mise.run | sh (or wget -qO- https://mise.run | sh)"
    status_fix "Mise" "would install standalone binary"
    return 0
  fi
  if command_exists curl; then
    curl -fsSL https://mise.run | sh
  elif command_exists wget; then
    wget -qO- https://mise.run | sh
  else
    fail "mise installation requires curl or wget; neither is available"
  fi
  export PATH="$HOME/.local/bin:$PATH"
  command_exists mise || fail "mise installation completed but mise is unavailable"
  status_fix "Mise" "installed standalone"
}

ensure_gum() {
  command_exists mise || { status_skip "Gum" "mise unavailable"; return 0; }
  local gum_path=''
  if command_exists gum; then
    status_pass "Gum" "$(command -v gum)"
    return 0
  fi
  if dry_run_active; then
    dry_run_log "mise -C $HOME install gum@latest"
    status_fix "Gum" "would install through mise"
    return 0
  fi
  mise -C "$HOME" install gum@latest >/dev/null
  gum_path="$(mise -C "$HOME" exec gum@latest -- which gum)"
  [[ -x "$gum_path" ]] || fail "mise installed Gum but did not return an executable"
  export PATH="$(dirname "$gum_path"):$PATH"
  status_fix "Gum" "installed through mise"
}

ensure_persistent_repo() {
  local target="${DOTFILES_DIR:-$HOME/.dotfiles}"
  if [[ "$BOOTSTRAP_ROOT" == "$target" || -d "$target/.git" ]]; then
    if [[ -d "$target/.git" ]]; then BOOTSTRAP_ROOT="$target"; DOTFILES_DIR="$target"; fi
    return 0
  fi
  if dry_run_active; then
    dry_run_log "GIT_CONFIG_GLOBAL=/dev/null git clone $DOTFILES_REPO $target"
    status_fix "Persistent dotfiles checkout" "would clone after Git becomes available"
    # Model the post-clone paths so every later dry-run line describes the
    # durable checkout rather than the temporary downloaded archive.
    LINK_SOURCE_ROOT="$target" DOTFILES_DIR="$target"
    export LINK_SOURCE_ROOT DOTFILES_DIR
    return 0
  fi
  command_exists git || fail "Git is unavailable after the mise-managed baseline package stage"
  [[ ! -e "$target" ]] || fail "$target exists but is not a Git checkout"
  bootstrap_git clone "$DOTFILES_REPO" "$target"
  BOOTSTRAP_ROOT="$target" LINK_SOURCE_ROOT="$target" DOTFILES_DIR="$target"
  export BOOTSTRAP_ROOT LINK_SOURCE_ROOT DOTFILES_DIR
  status_fix "Persistent dotfiles checkout" "$target"
}

selection_has() { printf '%s\n' "$1" | grep -Fxq "$2"; }

interactive_plan() {
  [[ "$NON_INTERACTIVE" != 1 && -t 0 ]] || return 0
  command_exists gum || { note "Gum is not available yet; continuing with CLI/state/profile defaults."; return 0; }

  if [[ -z "$CLI_PROFILE" ]]; then
    CLI_PROFILE="$(gum choose --header 'Choose the Linux bootstrap profile' \
      "home — Ben's full personal Linux setup" \
      "work — Ben's setup plus Zscaler" \
      'minimal — neutral baseline for another adopter')"
    CLI_PROFILE="${CLI_PROFILE%% *}"
  fi

  local defaults=() stages
  if [[ "$CLI_PROFILE" != minimal ]]; then
    defaults=(packages applications mise-tools dotfiles code-directory git-identity linux-defaults remote-access shell-default)
  else
    defaults=(code-directory git-identity linux-defaults)
  fi
  [[ "$CLI_PROFILE" == work ]] && defaults+=(zscaler)
  stages="$(gum choose --no-limit --header 'Edit the profile stages (Space toggles; Return confirms)' \
    --selected "$(IFS=,; printf '%s' "${defaults[*]}")" \
    packages applications mise-tools dotfiles code-directory downloads-link git-identity linux-defaults remote-access shell-default zscaler)"
  local stage
  for stage in packages applications mise-tools dotfiles code-directory downloads-link git-identity linux-defaults remote-access shell-default zscaler; do
    if selection_has "$stages" "$stage"; then set_cli_flag "$stage" true; else set_cli_flag "$stage" false; fi
  done
  [[ "$CLI_PROFILE" == work && "${CLI_ENABLE_ZSCALER:-}" == true ]] && CLI_ENABLE_ZSCALER=auto

  CLI_SHELL="$(gum choose --header 'Preferred login shell' fish zsh bash)"
  if [[ "${CLI_ENABLE_LINUX_DEFAULTS:-false}" == true ]]; then
    CLI_DEVICE_NAME="$(gum input --header 'Device hostname' --value "${CLI_DEVICE_NAME:-$(hostname -s 2>/dev/null || printf linux)}")"
  fi
  if [[ "${CLI_ENABLE_DOWNLOADS_LINK:-false}" == true ]]; then
    CLI_DOWNLOADS_TARGET="$(gum input --header 'Absolute directory that ~/Downloads should point to' --value "${CLI_DOWNLOADS_TARGET:-}")"
  fi
  if [[ "${CLI_ENABLE_GIT_IDENTITY:-false}" == true ]]; then
    CLI_GIT_USER_NAME="$(gum input --header 'Git author name' --value "${CLI_GIT_USER_NAME:-$(git config --global --includes --get user.name 2>/dev/null || true)}")"
    CLI_GIT_USER_EMAIL="$(gum input --header 'Git author email' --value "${CLI_GIT_USER_EMAIL:-$(git config --global --includes --get user.email 2>/dev/null || true)}")"
  fi
}

show_plan() {
  cat <<EOF

Linux bootstrap plan
  Distribution:       $DISTRO_NAME ($PACKAGE_MANAGER)
  Account:            $(id -un) (detected; never renamed)
  Action/profile:     $MODE / $RESOLVED_PROFILE
  Hostname:           $RESOLVED_DEVICE_NAME (apply=$RESOLVED_LINUX_HOSTNAME)
  Shell:              $RESOLVED_SHELL (set-default=$RESOLVED_SHELL_DEFAULT)
  Ben's CLI packages: $RESOLVED_PACKAGES
  Native apps:        $RESOLVED_APPLICATIONS
  Ben's mise tools:   $RESOLVED_MISE_TOOLS
  Ben's dotfiles:     $RESOLVED_DOTFILES
  Create ~/code:      $RESOLVED_CODE_DIRECTORY
  Link Downloads:     $RESOLVED_DOWNLOADS_LINK${RESOLVED_DOWNLOADS_TARGET:+ -> $RESOLVED_DOWNLOADS_TARGET}
  Git identity:       $RESOLVED_GIT_IDENTITY${RESOLVED_GIT_USER_EMAIL:+ ($RESOLVED_GIT_USER_NAME <$RESOLVED_GIT_USER_EMAIL>)}
  Linux defaults:     $RESOLVED_LINUX_DEFAULTS
  Default apps:       $RESOLVED_LINUX_DEFAULT_APPS
  Remote SSH:         $RESOLVED_REMOTE_ACCESS
  Zscaler:            $RESOLVED_ZSCALER
EOF
  if dry_run_active; then printf '  Mode safety:        DRY RUN — no changes will be made\n'; fi
  echo
  if use_gum && ! dry_run_active; then
    gum confirm --default=true "Apply this Linux plan?" || exit 0
  fi
}

seed_mise_config() {
  cat <<'EOF'
# >>> foundation-seed >>>
[settings]
experimental = true

[env]
_.file = "~/.config/mise/.env"

[tools]
gum = "latest"
# <<< foundation-seed <<<
EOF
}

ensure_mise_config() {
  local config_dir="$HOME/.config/mise" config="$HOME/.config/mise/config.toml"
  if [[ "$RESOLVED_DOTFILES" == true && -d "$BOOTSTRAP_ROOT/mise" ]]; then
    if paths_same "$config_dir" "$LINK_SOURCE_ROOT/mise"; then
      status_pass "Mise config" "repository symlink correct"
    elif [[ ! -e "$config_dir" && ! -L "$config_dir" ]]; then
      if dry_run_active; then dry_run_log "ln -s $LINK_SOURCE_ROOT/mise $config_dir"
      else mkdir -p "$HOME/.config"; ln -s "$LINK_SOURCE_ROOT/mise" "$config_dir"; fi
      if dry_run_active; then status_fix "Mise config" "would link repository config"
      else status_fix "Mise config" "linked repository config"; fi
    else
      status_skip "Mise config" "existing user-owned path preserved: $config_dir"
    fi
    return 0
  fi

  local desired; desired="$(seed_mise_config)"
  if [[ -f "$config" ]] && ! grep -Fq "$MISE_BEGIN" "$config"; then
    status_skip "Mise seed config" "existing user config preserved"
  elif [[ -f "$config" ]] && [[ "$(awk "/$MISE_BEGIN/,/$MISE_END/" "$config")" == "$desired" ]]; then
    status_pass "Mise seed config" "Gum baseline present"
  else
    write_managed_block "$config" "$MISE_BEGIN" "$MISE_END" "$desired"
    if dry_run_active; then status_fix "Mise seed config" "would ensure Gum baseline"
    else status_fix "Mise seed config" "ensured Gum baseline"; fi
  fi
}

ensure_mise_env() {
  local path="$HOME/.config/mise/.env"
  if [[ -e "$path" ]]; then
    status_pass "Mise .env" "existing file preserved"
  elif dry_run_active; then
    dry_run_log "install -m 600 /dev/null $path"
    status_fix "Mise .env" "would create private placeholder"
  else
    mkdir -p "$(dirname "$path")"
    printf '# Private environment variables; never commit secrets.\nEDITOR=nvim\n' > "$path"
    chmod 600 "$path"
    status_fix "Mise .env" "created private placeholder"
  fi
}

ensure_catalogue() {
  if [[ "$RESOLVED_PACKAGES" != true ]]; then status_skip "Ben's CLI packages" "disabled by plan"; return 0; fi
  if ! command_exists mise && dry_run_active; then
    dry_run_log "mise bootstrap packages apply --manager $PACKAGE_MANAGER --yes --update"
    status_fix "Ben's native package catalogue" "would run after mise installation"
    return 0
  fi
  local missing=() package
  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    package_installed "$package" || missing+=("$package")
  done < <(linux_package_catalogue)
  if [[ ${#missing[@]} -eq 0 ]]; then
    status_pass "Ben's native package catalogue" "all declared $PACKAGE_MANAGER packages installed"
    return 0
  fi
  wait_for_package_manager
  local missing_specs=()
  for package in "${missing[@]}"; do missing_specs+=("$PACKAGE_MANAGER:$package"); done
  if dry_run_active; then
    bootstrap_repo_mise bootstrap packages apply --dry-run --update "${missing_specs[@]}"
    status_fix "Ben's native package catalogue" "mise would install ${#missing[@]} missing package(s)"
  else
    note "mise will show the native package plan before using sudo; confirmation is pre-authorised by this bootstrap plan."
    bootstrap_repo_mise bootstrap packages apply --yes --update "${missing_specs[@]}"
    status_pass "Ben's native package catalogue" "mise reconciled $PACKAGE_MANAGER declarations"
  fi
}

ensure_applications() {
  if [[ "$RESOLVED_APPLICATIONS" != true ]]; then status_skip "Linux applications" "disabled by plan"; return 0; fi
  local specs=() missing=() spec application
  while IFS= read -r spec; do [[ -n "$spec" ]] && specs+=("$spec"); done < <(linux_application_package_specs)

  if command_exists flatpak; then
    for spec in "${specs[@]}"; do
      application="${spec#flatpak:}"
      flatpak info --system "$application" >/dev/null 2>&1 || missing+=("$spec")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
      status_pass "Linux applications" "all ${#specs[@]} declared Flatpak app(s) installed"
      return 0
    fi
  else
    missing=("${specs[@]}")
  fi

  if dry_run_active && ! command_exists mise; then
    dry_run_log "mise bootstrap packages apply --yes $PACKAGE_MANAGER:flatpak"
    dry_run_log "flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
    dry_run_log "sudo mise -C $HOME bootstrap packages apply --yes ${missing[*]}"
    status_fix "Linux applications" "would install via mise's Flatpak manager"
    return 0
  fi

  if ! command_exists flatpak; then
    wait_for_package_manager
    if dry_run_active; then bootstrap_mise bootstrap packages apply --dry-run "$PACKAGE_MANAGER:flatpak"
    else bootstrap_mise bootstrap packages apply --yes "$PACKAGE_MANAGER:flatpak"; fi
  fi
  if dry_run_active; then
    dry_run_log "flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
    dry_run_log "sudo $(command -v mise) -C $HOME bootstrap packages apply --yes ${missing[*]}"
    status_fix "Linux applications" "mise would install ${#missing[@]} missing Flatpak app(s)"
  else
    elevate flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    # mise's Flatpak manager deliberately owns the system installation. Run
    # this narrow explicit-package invocation as root so polkit does not reject
    # the non-interactive system-helper request on Ubuntu desktops.
    elevate "$(command -v mise)" -C "$HOME" bootstrap packages apply --yes "${missing[@]}"
    status_pass "Linux applications" "mise installed ${#missing[@]} missing Flatpak app(s)"
  fi
}

ensure_mise_tools() {
  local uv_bin uv_dir python_bin missing_json supported_missing_count
  local -a missing_tools=()
  if [[ "$RESOLVED_MISE_TOOLS" != true ]]; then status_skip "Ben's mise tools" "disabled by plan"; return 0; fi
  if dry_run_active; then
    if command_exists mise; then
      local plan
      plan="$(bootstrap_repo_mise install --dry-run 2>&1 || true)"
      if [[ "${BOOTSTRAP_WSL_VERSION:-}" == 1 ]]; then
        missing_json="$(bootstrap_repo_mise ls --missing --json 2>/dev/null || printf '{}')"
        supported_missing_count="$(awk '
          /^  "pipx:(mitmproxy|sqlfluff)"/ { skip=1; next }
          skip && /^  ]/ { skip=0; next }
          !skip && /"version"/ { count++ }
          END { print count+0 }
        ' <<< "$missing_json")"
        status_skip "WSL 1 Python applications" "SQLFluff and mitmproxy require WSL 2"
      else
        supported_missing_count=''
      fi
      if [[ "$supported_missing_count" == 0 ]] || grep -Fq 'all tools are installed' <<< "$plan"; then
        status_pass "Ben's mise tools" "all declared tools installed"
      else
        printf '%s\n' "$plan"
        status_fix "Ben's mise tools" "would install missing declared tools"
      fi
    else
      dry_run_log "mise install (repository Linux toolset)"
      status_fix "Ben's mise tools" "would install declared tools after mise"
    fi
  else
    note "mise may ask for confirmation before installing the declared toolset."
    bootstrap_mise trust "$BOOTSTRAP_ROOT/mise/config.toml" 2>/dev/null || true
    if [[ -f "$BOOTSTRAP_ROOT/mise.toml" ]]; then
      # The repository-level task config is discovered whenever a shell enters
      # ~/.dotfiles. Trust it during bootstrap so mise activation does not
      # break tool resolution inside the checkout.
      bootstrap_mise trust "$BOOTSTRAP_ROOT/mise.toml" 2>/dev/null || true
    fi
    # gcloud's vfox post-install hook uses CLOUDSDK_PYTHON immediately. The
    # pipx backend also invokes uv while the parent mise install is active.
    # Preinstall those Mise-owned runtimes and put uv's real binary ahead of
    # the shims so neither backend recursively re-enters the parent process.
    bootstrap_repo_mise install python uv pipx
    uv_bin="$(bootstrap_repo_mise which uv)"
    [[ -x "$uv_bin" ]] || fail "mise installed uv but did not return an executable"
    uv_dir="$(dirname "$uv_bin")"
    if [[ "${BOOTSTRAP_WSL_VERSION:-}" == 1 ]]; then
      # WSL 1 repeatedly returns ENOMEM while uv copies SQLFluff/mitmproxy's
      # Python environments, even with free RAM and swap. Keep every portable
      # release/language tool under Mise and exclude only these two apps. WSL 2
      # and ordinary Linux continue to install the complete catalogue.
      python_bin="$(bootstrap_repo_mise which python)"
      missing_json="$(bootstrap_repo_mise ls --missing --json)"
      while IFS= read -r tool; do
        [[ -z "$tool" ]] || missing_tools+=("$tool")
      done < <("$python_bin" -c 'import json, sys
excluded = {"pipx:mitmproxy", "pipx:sqlfluff"}
for tool in json.load(sys.stdin):
    if tool not in excluded:
        print(tool)
' <<< "$missing_json")
      if [[ ${#missing_tools[@]} -gt 0 ]]; then
        PATH="$uv_dir:$PATH" bootstrap_repo_mise install "${missing_tools[@]}"
      fi
      status_skip "WSL 1 Python applications" "SQLFluff and mitmproxy require WSL 2"
    else
      PATH="$uv_dir:$PATH" bootstrap_repo_mise install
    fi
    status_pass "Ben's mise tools" "declarative toolset installed"
  fi
}

ensure_code_directory() {
  if [[ "$RESOLVED_CODE_DIRECTORY" != true ]]; then status_skip "Code directory" "disabled by plan"; return 0; fi
  if [[ -d "$HOME/code" ]]; then status_pass "Code directory" "$HOME/code"
  elif dry_run_active; then dry_run_log "mkdir -p $HOME/code"; status_fix "Code directory" "would create"
  else mkdir -p "$HOME/code"; status_fix "Code directory" "created"; fi
}

ensure_downloads_link() {
  if [[ "$RESOLVED_DOWNLOADS_LINK" != true ]]; then status_skip "Downloads link" "disabled by plan"; return 0; fi
  local target="$RESOLVED_DOWNLOADS_TARGET" link="$HOME/Downloads"
  if paths_same "$link" "$target"; then status_pass "Downloads link" "$link -> $target"; return 0; fi
  [[ -e "$target" ]] || { if dry_run_active; then dry_run_log "mkdir -p $target"; else mkdir -p "$target"; fi; }
  if [[ -e "$link" || -L "$link" ]]; then
    status_skip "Downloads link" "existing $link preserved; move its contents and rerun"
    return 0
  fi
  if dry_run_active; then dry_run_log "ln -s $target $link"; else ln -s "$target" "$link"; fi
  if dry_run_active; then status_fix "Downloads link" "would link to $target"
  else status_fix "Downloads link" "linked to $target"; fi
}

dotfile_pairs() {
  cat <<EOF
$LINK_SOURCE_ROOT/bash/.bashrc|$HOME/.bashrc
$LINK_SOURCE_ROOT/bash/.bash_profile|$HOME/.bash_profile
$LINK_SOURCE_ROOT/bash/.hushlogin|$HOME/.hushlogin
$LINK_SOURCE_ROOT/zsh/.zshrc|$HOME/.zshrc
$LINK_SOURCE_ROOT/zsh/.zprofile|$HOME/.zprofile
$LINK_SOURCE_ROOT/tmux/.tmux.conf|$HOME/.tmux.conf
$LINK_SOURCE_ROOT/git/ignore|$HOME/.config/git/ignore
$LINK_SOURCE_ROOT/ssh/config|$HOME/.ssh/config
$LINK_SOURCE_ROOT/gh/config.yml|$HOME/.config/gh/config.yml
$LINK_SOURCE_ROOT/gh/hosts.yml|$HOME/.config/gh/hosts.yml
$LINK_SOURCE_ROOT/worktrunk/config.toml|$HOME/.config/worktrunk/config.toml
$LINK_SOURCE_ROOT/fish|$HOME/.config/fish
$LINK_SOURCE_ROOT/nvim|$HOME/.config/nvim
$LINK_SOURCE_ROOT/opencode/opencode.json|$HOME/.config/opencode/opencode.json
$LINK_SOURCE_ROOT/opencode/plugins|$HOME/.config/opencode/plugins
$LINK_SOURCE_ROOT/pi/APPEND_SYSTEM.md|$HOME/.pi/agent/APPEND_SYSTEM.md
$LINK_SOURCE_ROOT/pi/extensions|$HOME/.pi/agent/extensions
$LINK_SOURCE_ROOT/pi/mcp.json|$HOME/.pi/agent/mcp.json
$LINK_SOURCE_ROOT/pi/model-system|$HOME/.pi/agent/model-system
$LINK_SOURCE_ROOT/pi/settings.json|$HOME/.pi/agent/settings.json
EOF
}

ensure_dotfiles() {
  if [[ "$RESOLVED_DOTFILES" != true ]]; then status_skip "Ben's dotfiles" "disabled by plan"; return 0; fi
  local source target changed=0 preserved=0 replaced_stock=0
  while IFS='|' read -r source target; do
    source_available "$source" || continue
    if paths_same "$target" "$source"; then continue; fi
    if [[ -e "$target" || -L "$target" ]]; then
      if stock_skeleton_file "$target"; then
        if dry_run_active; then
          dry_run_log "replace untouched /etc/skel file $target with symlink to $source"
        else
          rm -f "$target"
          mkdir -p "$(dirname "$target")"
          ln -s "$source" "$target"
        fi
        changed=$((changed + 1))
        replaced_stock=$((replaced_stock + 1))
        continue
      fi
      preserved=$((preserved + 1)); continue
    fi
    if dry_run_active; then dry_run_log "ln -s $source $target"
    else mkdir -p "$(dirname "$target")"; ln -s "$source" "$target"; fi
    changed=$((changed + 1))
  done < <(dotfile_pairs)
  if ! dry_run_active && [[ -d "$HOME/.ssh" ]]; then chmod 700 "$HOME/.ssh"; fi
  if [[ "$changed" -eq 0 ]]; then status_pass "Ben's dotfiles" "all selected links already correct"
  elif dry_run_active; then status_fix "Ben's dotfiles" "${changed} link(s) would be created"
  else status_fix "Ben's dotfiles" "created ${changed} link(s)"; fi
  [[ "$replaced_stock" -eq 0 ]] || status_pass "Stock shell files" "replaced ${replaced_stock} untouched /etc/skel file(s)"
  [[ "$preserved" -eq 0 ]] || status_skip "Existing dotfile targets" "preserved ${preserved}; replace explicitly if desired"
}

git_generated_content() {
  cat <<EOF
# Generated by the cross-platform dotfiles bootstrap.
[user]
    name = $RESOLVED_GIT_USER_NAME
    email = $RESOLVED_GIT_USER_EMAIL
EOF
  [[ "$RESOLVED_DOTFILES" == true && -f "$BOOTSTRAP_ROOT/git/config.shared" ]] && printf '[include]\n\tpath = %s\n' "$LINK_SOURCE_ROOT/git/config.shared"
  return 0
}

git_identity_include_content() {
  cat <<EOF
# Machine-local identity generated by the dotfiles bootstrap.
[user]
    name = $RESOLVED_GIT_USER_NAME
    email = $RESOLVED_GIT_USER_EMAIL
EOF
  [[ "$RESOLVED_DOTFILES" == true && -f "$BOOTSTRAP_ROOT/git/config.shared" ]] && printf '[include]\n\tpath = %s\n' "$LINK_SOURCE_ROOT/git/config.shared"
  return 0
}

write_private_file() {
  local path="$1" content="$2" parent tmp
  parent="$(dirname "$path")"
  if dry_run_active; then dry_run_log "write mode-600 $path"; return 0; fi
  mkdir -p "$parent"; tmp="$(mktemp "$parent/.bootstrap.XXXXXX")"; chmod 600 "$tmp"
  printf '%s\n' "$content" > "$tmp"; mv -f "$tmp" "$path"
}

ensure_git_identity() {
  if [[ "$RESOLVED_GIT_IDENTITY" != true ]]; then status_skip "Git identity" "disabled by plan"; return 0; fi
  local config="$HOME/.gitconfig" include="$HOME/.config/git/bootstrap-user.inc" content decision
  if [[ ! -e "$config" && ! -L "$config" ]]; then
    content="$(git_generated_content)"; write_private_file "$config" "$content"
    if dry_run_active; then status_fix "Git config" "would create user-owned ~/.gitconfig"
    else status_fix "Git config" "created user-owned ~/.gitconfig"; fi
    return 0
  fi
  if [[ -L "$config" && ! -e "$config" ]]; then status_fail "Git config" "broken symlink preserved"; return 0; fi
  if [[ -f "$config" ]] && grep -Fq 'Generated by the cross-platform dotfiles bootstrap.' "$config"; then
    content="$(git_generated_content)"
    if [[ "$(cat "$config")" == "$content" ]]; then status_pass "Git config" "bootstrap-generated file current"
    else write_private_file "$config" "$content"; status_fix "Git config" "would update bootstrap-generated file"; fi
    return 0
  fi
  if [[ -f "$include" ]] && git config --file "$config" --get-all include.path 2>/dev/null | grep -Fxq "$include"; then
    content="$(git_identity_include_content)"; write_private_file "$include" "$content"
    status_pass "Git config" "existing config preserved with identity include"
    return 0
  fi

  decision=preserve
  if use_gum; then
    decision="$(gum choose --header 'An existing ~/.gitconfig is present' 'Preserve + include' 'Replace config')"
    [[ "$decision" == 'Replace config' ]] && decision=replace || decision=preserve
  fi
  if [[ "$decision" == replace ]]; then
    write_private_file "$config" "$(git_generated_content)"
    status_fix "Git config" "would replace after consent"
  else
    write_private_file "$include" "$(git_identity_include_content)"
    if dry_run_active; then dry_run_log "git config --file $config --add include.path $include"
    else git config --file "$config" --add include.path "$include"; fi
    status_fix "Git config" "would preserve existing config and add identity include"
  fi
}

ensure_tpm() {
  [[ "$RESOLVED_DOTFILES" == true || "$RESOLVED_MISE_TOOLS" == true ]] || { status_skip "Tmux plugin manager" "personal config disabled"; return 0; }
  local path="$HOME/.tmux/plugins/tpm"
  if [[ -d "$path/.git" ]]; then status_pass "Tmux plugin manager" "Git checkout present"
  elif [[ -e "$path" ]]; then status_skip "Tmux plugin manager" "$path exists but is not a Git checkout"
  elif dry_run_active; then dry_run_log "git clone https://github.com/tmux-plugins/tpm $path"; status_fix "Tmux plugin manager" "would clone"
  else bootstrap_git clone https://github.com/tmux-plugins/tpm "$path"; status_fix "Tmux plugin manager" "cloned"; fi
}

ensure_fisher() {
  [[ "$RESOLVED_SHELL" == fish ]] || { status_skip "Fisher" "Fish is not the selected shell"; return 0; }
  command_exists fish || { status_skip "Fisher" "Fish is not installed"; return 0; }
  if fish -c 'type -q fisher' >/dev/null 2>&1; then
    status_pass "Fisher" "$(fish -c 'fisher --version' 2>/dev/null || printf installed)"
    return 0
  fi

  local version=4.4.8 base function_path completion_path
  base="https://raw.githubusercontent.com/jorgebucaran/fisher/$version"
  function_path="$HOME/.local/share/fish/vendor_functions.d/fisher.fish"
  completion_path="$HOME/.local/share/fish/vendor_completions.d/fisher.fish"
  if dry_run_active; then
    dry_run_log "install Fisher $version to user Fish vendor directories"
    status_fix "Fisher" "would install $version from the official tagged release"
    return 0
  fi
  mkdir -p "$(dirname "$function_path")" "$(dirname "$completion_path")"
  curl -fsSL "$base/functions/fisher.fish" -o "$function_path"
  curl -fsSL "$base/completions/fisher.fish" -o "$completion_path"
  chmod 644 "$function_path" "$completion_path"
  fish -c 'type -q fisher' || fail "Fisher installation did not become visible to Fish"
  status_fix "Fisher" "installed $(fish -c 'fisher --version' 2>/dev/null || printf '%s' "$version")"
}

ensure_hostname() {
  if [[ "$RESOLVED_LINUX_HOSTNAME" != true ]]; then status_skip "Linux hostname" "disabled by plan"; return 0; fi
  local current; current="$(hostname -s 2>/dev/null || true)"
  if [[ "$current" == "$RESOLVED_DEVICE_NAME" ]]; then status_pass "Linux hostname" "$current"; return 0; fi
  if command_exists hostnamectl && command_exists systemctl && systemctl is-system-running >/dev/null 2>&1; then
    run_elevated_or_dry hostnamectl set-hostname "$RESOLVED_DEVICE_NAME"
  else
    # WSL 1 and other non-systemd environments still support the traditional
    # hostname interface. Persist it and update the current namespace.
    run_elevated_or_dry sh -c "printf '%s\\n' '$RESOLVED_DEVICE_NAME' > /etc/hostname && hostname '$RESOLVED_DEVICE_NAME'"
  fi
  if dry_run_active; then status_fix "Linux hostname" "would change $current -> $RESOLVED_DEVICE_NAME"
  else status_fix "Linux hostname" "changed $current -> $RESOLVED_DEVICE_NAME"; fi
}

ensure_remote_access() {
  if [[ "$RESOLVED_REMOTE_ACCESS" != true ]]; then status_skip "Remote access" "disabled by plan"; return 0; fi
  local server_package service
  if [[ "$PACKAGE_MANAGER" == apt ]]; then server_package=openssh-server; service=ssh.service
  else server_package=openssh; service=sshd.service; fi
  if ! package_installed "$server_package"; then
    local server_spec="$PACKAGE_MANAGER:$server_package"
    if dry_run_active; then bootstrap_mise bootstrap packages apply --dry-run "$server_spec"
    else bootstrap_mise bootstrap packages apply --yes "$server_spec"; fi
  fi
  if ! command_exists systemctl; then status_skip "Remote access" "systemd unavailable; SSH server installed but not enabled"; return 0; fi
  if systemctl is-enabled "$service" >/dev/null 2>&1 && systemctl is-active "$service" >/dev/null 2>&1; then
    status_pass "Remote access" "$service enabled and active"
  else
    run_elevated_or_dry systemctl enable --now "$service"
    if dry_run_active; then status_fix "Remote access" "would enable and start $service"
    else status_fix "Remote access" "enabled and started $service"; fi
  fi
}

ensure_shell_profile() {
  if [[ "$RESOLVED_DOTFILES" == true ]]; then status_skip "Shell fallback block" "tracked shell config selected"; return 0; fi
  local path content
  case "$RESOLVED_SHELL" in
    fish)
      path="$HOME/.config/fish/conf.d/00-foundation.fish"
      content=$'# >>> foundation-bootstrap >>>\nif test -r /proc/sys/kernel/osrelease; and string match -qi "*microsoft*" (cat /proc/sys/kernel/osrelease); and string match -q "/mnt/*/Users/$USER" "$PWD"; cd "$HOME"; end\nif test -x "$HOME/.local/bin/mise"; $HOME/.local/bin/mise -C "$HOME" activate fish | source; end\nif type -q zoxide; zoxide init fish | source; end\n# <<< foundation-bootstrap <<<'
      ;;
    zsh)
      path="$HOME/.zshrc"
      content=$'# >>> foundation-bootstrap >>>\nif grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then case "$PWD" in /mnt/?/Users/"${USER:-${HOME:t}}") cd "$HOME" || true ;; esac; fi\nif [[ -x "$HOME/.local/bin/mise" ]]; then eval "$("$HOME/.local/bin/mise" -C "$HOME" activate zsh)"; fi\nif command -v zoxide >/dev/null 2>&1; then eval "$(zoxide init zsh)"; fi\n# <<< foundation-bootstrap <<<'
      ;;
    bash)
      path="$HOME/.bashrc"
      content=$'# >>> foundation-bootstrap >>>\nif grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then case "$PWD" in /mnt/?/Users/"${USER:-$(basename "$HOME")}") cd "$HOME" || true ;; esac; fi\nif [[ -x "$HOME/.local/bin/mise" ]]; then eval "$("$HOME/.local/bin/mise" -C "$HOME" activate bash)"; fi\nif command -v zoxide >/dev/null 2>&1; then eval "$(zoxide init bash)"; fi\n# <<< foundation-bootstrap <<<'
      ;;
  esac
  write_managed_block "$path" "$PROFILE_BEGIN" "$PROFILE_END" "$content"
  if dry_run_active; then status_fix "Shell fallback block" "would ensure $path"
  else status_fix "Shell fallback block" "ensured $path"; fi
}

ensure_default_shell() {
  if [[ "$RESOLVED_SHELL_DEFAULT" != true ]]; then status_skip "Default shell" "disabled by plan"; return 0; fi
  local shell_path current
  shell_path="$(command -v "$RESOLVED_SHELL" 2>/dev/null || true)"
  [[ -n "$shell_path" ]] || { status_skip "Default shell" "$RESOLVED_SHELL is not installed"; return 0; }
  current="$(getent passwd "$(id -un)" | cut -d: -f7)"
  if [[ "$current" == "$shell_path" ]]; then status_pass "Default shell" "$shell_path"; return 0; fi
  if [[ "$RESOLVED_SHELL" == fish && "$shell_path" == /usr/bin/fish ]]; then
    note "mise will register Fish and change the login shell; sudo/chsh may ask for your password."
    if dry_run_active && ! command_exists mise; then dry_run_log "mise bootstrap user apply --yes"
    elif dry_run_active; then bootstrap_repo_mise bootstrap user apply --dry-run
    else bootstrap_repo_mise bootstrap user apply --yes; fi
    if dry_run_active; then status_fix "Default shell" "mise would change $current -> $shell_path"
    else status_fix "Default shell" "mise changed $current -> $shell_path"; fi
    return 0
  fi
  if ! grep -Fxq "$shell_path" /etc/shells 2>/dev/null; then
    run_elevated_or_dry sh -c "printf '%s\\n' '$shell_path' >> /etc/shells"
  fi
  note "Changing the login shell may ask for the account password."
  run_or_dry chsh -s "$shell_path"
  if dry_run_active; then status_fix "Default shell" "would change $current -> $shell_path"
  else status_fix "Default shell" "changed $current -> $shell_path"; fi
}

desktop_id_for_command() {
  local command_name="$1" candidate
  case "$command_name" in
    google-chrome|google-chrome-stable) printf google-chrome.desktop ;;
    chromium|chromium-browser) printf chromium.desktop ;;
    code) printf code.desktop ;;
    *)
      candidate="$(find /usr/share/applications "$HOME/.local/share/applications" -maxdepth 1 -type f -iname "*${command_name}*.desktop" 2>/dev/null | head -1 || true)"
      [[ -n "$candidate" ]] && basename "$candidate"
      ;;
  esac
}

ensure_default_apps() {
  if [[ "$RESOLVED_LINUX_DEFAULT_APPS" != true ]]; then status_skip "Linux default apps" "disabled by plan"; return 0; fi
  command_exists xdg-mime || { status_skip "Linux default apps" "xdg-mime unavailable"; return 0; }
  refresh_flatpak_data_dirs
  local browser='' desktop=''
  if command_exists flatpak; then
    if flatpak info --system com.google.Chrome >/dev/null 2>&1; then desktop=com.google.Chrome.desktop
    elif flatpak info --system org.chromium.Chromium >/dev/null 2>&1; then desktop=org.chromium.Chromium.desktop
    fi
  fi
  if [[ -n "$desktop" ]]; then browser="${desktop%.desktop}"; fi
  for browser in google-chrome google-chrome-stable chromium chromium-browser; do command_exists "$browser" && break; browser=''; done
  [[ -n "$browser" || -n "$desktop" ]] || { status_skip "Linux default apps" "Google Chrome/Chromium not installed"; return 0; }
  [[ -n "$desktop" ]] || desktop="$(desktop_id_for_command "$browser")"
  [[ -n "$desktop" ]] || { status_skip "Linux default apps" "desktop entry not found for $browser"; return 0; }
  local mime current changed=0
  for mime in x-scheme-handler/http x-scheme-handler/https text/html application/pdf; do
    current="$(xdg-mime query default "$mime" 2>/dev/null || true)"
    [[ "$current" == "$desktop" ]] && continue
    run_or_dry xdg-mime default "$desktop" "$mime"; changed=$((changed + 1))
  done
  if [[ "$changed" -eq 0 ]]; then status_pass "Linux default apps" "$desktop owns browser + PDF"
  elif dry_run_active; then status_fix "Linux default apps" "would update ${changed} MIME handler(s) to $desktop"
  else status_fix "Linux default apps" "updated ${changed} MIME handler(s) to $desktop"; fi
}

detect_zscaler() {
  command_exists openssl || return 1
  local issuer
  issuer="$(openssl s_client -connect registry.npmjs.org:443 -servername registry.npmjs.org </dev/null 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null || true)"
  [[ "$issuer" == *Zscaler* ]]
}

zscaler_env_block() {
  local bundle="$1" cert_dir
  cert_dir="$(dirname "$1")"
  cat <<EOF
$ZSCALER_ENV_BEGIN
ZSCALER_CERT_BUNDLE="$bundle"
ZSCALER_CERT_DIR="$cert_dir"
SSL_CERT_FILE="$bundle"
SSL_CERT_DIR="$cert_dir"
REQUESTS_CA_BUNDLE="$bundle"
CERT_PATH="$bundle"
CERT_DIR="$cert_dir"
CURL_CA_BUNDLE="$bundle"
GRPC_DEFAULT_SSL_ROOTS_FILE_PATH="$bundle"
NODE_EXTRA_CA_CERTS="$bundle"
GIT_SSL_CAINFO="$bundle"
CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE="$bundle"
PIP_CERT="$bundle"
NPM_CONFIG_CAFILE="$bundle"
npm_config_cafile="$bundle"
AWS_CA_BUNDLE="$bundle"
$ZSCALER_ENV_END
EOF
}

ensure_zscaler() {
  [[ "$RESOLVED_ZSCALER" != false ]] || { status_skip "Zscaler trust" "disabled by plan"; return 0; }
  local detected=false
  detect_zscaler && detected=true
  if [[ "$RESOLVED_ZSCALER" == auto && "$detected" == false ]]; then status_skip "Zscaler trust" "not detected"; return 0; fi
  [[ "$detected" == true ]] || { status_fail "Zscaler trust" "enabled but no Zscaler TLS issuer detected"; return 0; }
  local cert_dir="$HOME/.config/dotfiles/certs" chain bundle system_bundle=''
  chain="$cert_dir/zscaler-chain.pem"
  bundle="$cert_dir/ca-bundle.pem"
  for system_bundle in /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem; do [[ -s "$system_bundle" ]] && break; system_bundle=''; done
  [[ -n "$system_bundle" ]] || { status_fail "Zscaler trust" "system CA bundle not found"; return 0; }
  if dry_run_active; then
    dry_run_log "capture Zscaler chain and build $bundle"
  else
    mkdir -p "$cert_dir"
    openssl s_client -showcerts -connect registry.npmjs.org:443 -servername registry.npmjs.org </dev/null 2>/dev/null \
      | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > "$chain"
    [[ -s "$chain" ]] || fail "Zscaler certificate capture produced an empty chain"
    cat "$system_bundle" "$chain" > "$bundle"; chmod 600 "$chain" "$bundle"
  fi
  write_managed_block "$HOME/.config/mise/.env" "$ZSCALER_ENV_BEGIN" "$ZSCALER_ENV_END" "$(zscaler_env_block "$bundle")"
  if dry_run_active; then status_fix "Zscaler trust" "would build CA bundle and mise environment block"
  else status_fix "Zscaler trust" "configured $bundle"; fi
}

validate_linux() {
  local tool
  for tool in git curl mise; do
    if command_exists "$tool"; then status_pass "Validate: $tool" "$(command -v "$tool")"
    elif dry_run_active; then status_fix "Validate: $tool" "would be available after apply"
    else status_fail "Validate: $tool" "missing"; fi
  done
  if [[ "$RESOLVED_DOTFILES" == true ]]; then
    local source target wrong=0
    while IFS='|' read -r source target; do
      source_available "$source" || continue
      paths_same "$target" "$source" || wrong=$((wrong + 1))
    done < <(dotfile_pairs)
    if [[ "$wrong" -eq 0 ]]; then status_pass "Validate: dotfile links" "all correct"
    else status_skip "Validate: dotfile links" "$wrong preserved/missing"; fi
  fi
}

main() {
  parse_args "$@"
  detect_linux_platform
  ensure_mise
  ensure_gum
  interactive_plan
  resolve_linux_plan
  show_plan
  state_write_all

  ensure_baseline
  ensure_persistent_repo
  ensure_mise_config
  ensure_mise_env
  if [[ "$MODE" == update && "$RESOLVED_PACKAGES" == true ]]; then
    wait_for_package_manager
    if dry_run_active; then bootstrap_repo_mise bootstrap packages upgrade --manager "$PACKAGE_MANAGER" --dry-run
    else bootstrap_repo_mise bootstrap packages upgrade --manager "$PACKAGE_MANAGER" --yes; fi
  fi
  ensure_catalogue
  ensure_applications
  ensure_code_directory
  ensure_downloads_link
  ensure_dotfiles
  ensure_git_identity
  ensure_tpm
  ensure_fisher
  ensure_shell_profile
  ensure_mise_tools
  ensure_zscaler
  ensure_hostname
  ensure_remote_access
  ensure_default_apps
  ensure_default_shell
  validate_linux
  status_summary "Linux bootstrap"
  [[ "$FAIL_COUNT" -eq 0 ]] || exit 1
}

main "$@"
