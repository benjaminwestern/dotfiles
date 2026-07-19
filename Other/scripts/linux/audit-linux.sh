#!/usr/bin/env bash
# Read-only Linux inventory and bootstrap drift audit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

AUDIT_CONTEXT=general
AUDIT_PROFILE=''
AUDIT_SECTION=all
JSON=0
DRIFT=()
PACKAGE_ROWS=()
DOTFILE_ROWS=()

usage() {
  cat <<'EOF'
Usage: audit-linux.sh [--general | --profile <work|home|minimal> | --expect-state]
                      [--section <all|system|tools|packages|config|services>]
                      [--json]

  --general       Report the current machine without declaring profile drift
  --profile NAME  Compare current state with a clean profile preset
  --expect-state  Compare with the exact saved bootstrap plan
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --general) AUDIT_CONTEXT=general; AUDIT_PROFILE=''; shift ;;
      --profile) [[ $# -ge 2 ]] || fail "--profile requires a value"; AUDIT_CONTEXT=profile; AUDIT_PROFILE="$2"; shift 2 ;;
      --expect-state) AUDIT_CONTEXT=saved-plan; shift ;;
      --section) [[ $# -ge 2 ]] || fail "--section requires a value"; AUDIT_SECTION="$2"; shift 2 ;;
      --json) JSON=1; shift ;;
      -h|--help|help) usage; exit 0 ;;
      *) fail "Unknown audit argument: $1" ;;
    esac
  done
  case "$AUDIT_SECTION" in all|system|tools|packages|config|services) ;; *) fail "Unknown audit section: $AUDIT_SECTION" ;; esac
  [[ -z "$AUDIT_PROFILE" ]] || case "$AUDIT_PROFILE" in work|home|minimal) ;; *) fail "Profile must be work, home, or minimal" ;; esac
}

want_section() { [[ "$AUDIT_SECTION" == all || "$AUDIT_SECTION" == "$1" ]]; }

add_drift() { DRIFT+=("$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"); }

tool_version() {
  local tool="$1"
  command_exists "$tool" || { printf 'not installed'; return; }
  case "$tool" in
    git) git --version 2>/dev/null | head -1 ;;
    mise) mise --version 2>/dev/null | head -1 ;;
    gum) gum --version 2>/dev/null | head -1 ;;
    fish|zsh|bash|nvim|tmux|rg|fd|fdfind|gh) "$tool" --version 2>/dev/null | head -1 || printf installed ;;
    *) printf installed ;;
  esac
}

audit_packages() {
  local package state package_json=''
  if [[ "${BOOTSTRAP_WSL_VERSION:-}" != 1 ]] && command_exists mise && command_exists jq; then
    package_json="$(bootstrap_repo_mise bootstrap packages status --json 2>/dev/null || true)"
    if [[ -n "$package_json" ]] && printf '%s' "$package_json" | jq -e --arg manager "$PACKAGE_MANAGER" '.[$manager].packages' >/dev/null 2>&1; then
      while IFS=$'\t' read -r package state; do
        PACKAGE_ROWS+=("cli"$'\t'"$package"$'\t'"$state")
      done < <(printf '%s' "$package_json" | jq -r --arg manager "$PACKAGE_MANAGER" '.[$manager].packages[] | [.package, .state] | @tsv')
    fi
  fi
  if [[ ${#PACKAGE_ROWS[@]} -eq 0 ]]; then
    while IFS= read -r package; do
      [[ -n "$package" ]] || continue
      if package_installed "$package"; then state=installed
      elif package_available "$package"; then state=missing
      else state=unavailable
      fi
      PACKAGE_ROWS+=("cli"$'\t'"$package"$'\t'"$state")
    done < <(linux_package_catalogue)
  fi
  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    if command_exists flatpak && flatpak info --system "$package" >/dev/null 2>&1; then state=installed
    else state=missing
    fi
    PACKAGE_ROWS+=("application"$'\t'"$package"$'\t'"$state")
  done < <(linux_application_catalogue)
}

dotfile_pairs_audit() {
  cat <<EOF
$BOOTSTRAP_ROOT/bash/.bashrc|$HOME/.bashrc
$BOOTSTRAP_ROOT/bash/.bash_profile|$HOME/.bash_profile
$BOOTSTRAP_ROOT/bash/.hushlogin|$HOME/.hushlogin
$BOOTSTRAP_ROOT/zsh/.zshrc|$HOME/.zshrc
$BOOTSTRAP_ROOT/zsh/.zprofile|$HOME/.zprofile
$BOOTSTRAP_ROOT/tmux/.tmux.conf|$HOME/.tmux.conf
$BOOTSTRAP_ROOT/git/ignore|$HOME/.config/git/ignore
$BOOTSTRAP_ROOT/ssh/config|$HOME/.ssh/config
$BOOTSTRAP_ROOT/gh/config.yml|$HOME/.config/gh/config.yml
$BOOTSTRAP_ROOT/gh/hosts.yml|$HOME/.config/gh/hosts.yml
$BOOTSTRAP_ROOT/worktrunk/config.toml|$HOME/.config/worktrunk/config.toml
$BOOTSTRAP_ROOT/fish|$HOME/.config/fish
$BOOTSTRAP_ROOT/nvim|$HOME/.config/nvim
$BOOTSTRAP_ROOT/opencode/opencode.json|$HOME/.config/opencode/opencode.json
$BOOTSTRAP_ROOT/opencode/plugins|$HOME/.config/opencode/plugins
$BOOTSTRAP_ROOT/pi/APPEND_SYSTEM.md|$HOME/.pi/agent/APPEND_SYSTEM.md
$BOOTSTRAP_ROOT/pi/extensions|$HOME/.pi/agent/extensions
$BOOTSTRAP_ROOT/pi/mcp.json|$HOME/.pi/agent/mcp.json
$BOOTSTRAP_ROOT/pi/model-system|$HOME/.pi/agent/model-system
$BOOTSTRAP_ROOT/pi/settings.json|$HOME/.pi/agent/settings.json
EOF
}

audit_dotfiles() {
  local source target state detail
  while IFS='|' read -r source target; do
    [[ -e "$source" ]] || continue
    if paths_same "$target" "$source"; then state=correct; detail="$source"
    elif [[ -L "$target" ]]; then state=wrong-symlink; detail="$(readlink "$target" 2>/dev/null || true)"
    elif [[ -e "$target" ]]; then state=user-owned; detail='preserved non-symlink'
    else state=missing; detail="$source"
    fi
    DOTFILE_ROWS+=("$target"$'\t'"$state"$'\t'"$detail")
  done < <(dotfile_pairs_audit)
}

git_config_mode() {
  local config="$HOME/.gitconfig" include="$HOME/.config/git/bootstrap-user.inc"
  if [[ -L "$config" && ! -e "$config" ]]; then printf broken-symlink
  elif [[ -L "$config" ]]; then printf valid-symlink
  elif [[ -f "$config" ]] && grep -Fq 'Generated by the cross-platform dotfiles bootstrap.' "$config"; then printf bootstrap-generated
  elif [[ -f "$config" ]] && [[ -f "$include" ]] && git config --file "$config" --get-all include.path 2>/dev/null | grep -Fxq "$include"; then printf user-file-with-include
  elif [[ -f "$config" ]]; then printf user-file
  else printf absent
  fi
}

login_shell() { getent passwd "$(id -un)" | cut -d: -f7; }

ssh_service_state() {
  command_exists systemctl || { printf unavailable; return; }
  local service
  [[ "$PACKAGE_MANAGER" == apt ]] && service=ssh.service || service=sshd.service
  if systemctl is-enabled "$service" >/dev/null 2>&1 && systemctl is-active "$service" >/dev/null 2>&1; then printf enabled-active
  elif systemctl is-enabled "$service" >/dev/null 2>&1; then printf enabled-inactive
  elif systemctl is-active "$service" >/dev/null 2>&1; then printf active-not-enabled
  else printf disabled
  fi
}

fisher_state() {
  command_exists fish || { printf 'not installed (Fish missing)'; return; }
  fish -c 'type -q fisher' >/dev/null 2>&1 || { printf 'not installed'; return; }
  fish -c 'fisher --version' 2>/dev/null || printf installed
}

configured_browser_desktop() {
  command_exists flatpak || return 0
  if flatpak info --system com.google.Chrome >/dev/null 2>&1; then printf com.google.Chrome.desktop
  elif flatpak info --system org.chromium.Chromium >/dev/null 2>&1; then printf org.chromium.Chromium.desktop
  fi
}

xdg_default_handler() {
  command_exists xdg-mime || { printf unavailable; return; }
  refresh_flatpak_data_dirs
  xdg-mime query default "$1" 2>/dev/null || true
}

expected_from_profile() {
  local profile="$1" key="$2"
  case "$key" in
    DEVICE_PROFILE) printf '%s' "$profile" ;;
    PREFERRED_SHELL) [[ "$profile" == minimal ]] && printf bash || printf fish ;;
    DEVICE_NAME) printf '%s' "$(hostname -s 2>/dev/null || printf linux)" ;;
    ENABLE_*|LINUX_*) profile_default "$profile" "$key" ;;
  esac
}

expected_value() {
  local key="$1"
  case "$AUDIT_CONTEXT" in
    general) printf '' ;;
    profile) expected_from_profile "$AUDIT_PROFILE" "$key" ;;
    saved-plan) state_get "$key" ;;
  esac
}

build_drift() {
  [[ "$AUDIT_CONTEXT" != general ]] || return 0
  local expected current row kind package state target dotstate detail

  expected="$(expected_value DEVICE_NAME)"
  [[ -z "$expected" ]] || { current="$(hostname -s 2>/dev/null || true)"; [[ "$current" == "$expected" ]] || add_drift system hostname "$current" "$expected"; }

  expected="$(expected_value ENABLE_CODE_DIRECTORY)"
  if [[ "$expected" == true && ! -d "$HOME/code" ]]; then add_drift config "$HOME/code" missing present; fi

  expected="$(expected_value ENABLE_DOWNLOADS_LINK)"
  if [[ "$expected" == true ]]; then
    local downloads_target; downloads_target="$(expected_value DOWNLOADS_TARGET)"
    if [[ -z "$downloads_target" || ! -e "$HOME/Downloads" || ! -e "$downloads_target" || ! "$HOME/Downloads" -ef "$downloads_target" ]]; then
      add_drift config "$HOME/Downloads" "not linked" "${downloads_target:-saved target}"
    fi
  fi

  expected="$(expected_value ENABLE_GIT_IDENTITY)"
  if [[ "$expected" == true ]]; then
    current="$(git_config_mode)"
    [[ "$current" != absent && "$current" != broken-symlink ]] || add_drift config Git "$current" usable-config
    local expected_name expected_email current_name current_email
    expected_name="$(expected_value GIT_USER_NAME)"; expected_email="$(expected_value GIT_USER_EMAIL)"
    current_name="$(git config --global --includes --get user.name 2>/dev/null || true)"
    current_email="$(git config --global --includes --get user.email 2>/dev/null || true)"
    [[ -z "$expected_name" || "$current_name" == "$expected_name" ]] || add_drift config git-user-name "$current_name" "$expected_name"
    [[ -z "$expected_email" || "$current_email" == "$expected_email" ]] || add_drift config git-user-email "$current_email" "$expected_email"
  fi

  expected="$(expected_value ENABLE_DOTFILES)"
  if [[ "$expected" == true ]]; then
    for row in "${DOTFILE_ROWS[@]}"; do
      IFS=$'\t' read -r target dotstate detail <<< "$row"
      [[ "$dotstate" == correct ]] || add_drift config "$target" "$dotstate" correct-symlink
    done
  fi

  expected="$(expected_value ENABLE_PACKAGES)"
  if [[ "$expected" == true ]]; then
    for row in "${PACKAGE_ROWS[@]}"; do
      IFS=$'\t' read -r kind package state <<< "$row"
      [[ "$kind" != cli || "$state" == installed || "$state" == unavailable ]] || add_drift package "$package" "$state" installed
    done
  fi
  expected="$(expected_value ENABLE_APPLICATIONS)"
  if [[ "$expected" == true ]]; then
    for row in "${PACKAGE_ROWS[@]}"; do
      IFS=$'\t' read -r kind package state <<< "$row"
      [[ "$kind" != application || "$state" == installed || "$state" == unavailable ]] || add_drift application "$package" "$state" installed
    done
  fi

  expected="$(expected_value ENABLE_MISE_TOOLS)"
  if [[ "$expected" == true && -n "$(command -v mise 2>/dev/null || true)" ]]; then
    local missing_count
    if [[ "${BOOTSTRAP_WSL_VERSION:-}" == 1 ]]; then
      missing_count="$(bootstrap_repo_mise ls --missing --json 2>/dev/null | awk '
        /^  "pipx:(mitmproxy|sqlfluff)"/ { skip=1; next }
        skip && /^  ]/ { skip=0; next }
        !skip && /"version"/ { count++ }
        END { print count+0 }
      ' || printf 0)"
    else
      missing_count="$(bootstrap_repo_mise ls --missing --json 2>/dev/null | awk 'BEGIN{n=0} /"version"/{n++} END{print n}' || printf 0)"
    fi
    [[ "$missing_count" == 0 ]] || add_drift tool mise-tools "$missing_count missing" all-installed
  elif [[ "$expected" == true ]]; then add_drift tool mise missing installed; fi

  local expected_shell_name
  expected_shell_name="$(expected_value PREFERRED_SHELL)"
  if [[ "$expected_shell_name" == fish && "$(fisher_state)" == 'not installed' ]]; then
    add_drift tool Fisher missing installed
  fi

  expected="$(expected_value LINUX_DEFAULT_APPS)"
  if [[ "$expected" == true && "${BOOTSTRAP_WSL_VERSION:-}" != 1 ]]; then
    local desired_desktop current_http current_pdf
    desired_desktop="$(configured_browser_desktop)"
    current_http="$(xdg_default_handler x-scheme-handler/http)"
    current_pdf="$(xdg_default_handler application/pdf)"
    if [[ -z "$desired_desktop" ]]; then
      add_drift application browser missing Chrome-or-Chromium
    else
      [[ "$current_http" == "$desired_desktop" ]] || add_drift config HTTP-handler "${current_http:-unset}" "$desired_desktop"
      [[ "$current_pdf" == "$desired_desktop" ]] || add_drift config PDF-handler "${current_pdf:-unset}" "$desired_desktop"
    fi
  fi

  expected="$(expected_value ENABLE_SHELL_DEFAULT)"
  if [[ "$expected" == true ]]; then
    local expected_shell; expected_shell="$(expected_value PREFERRED_SHELL)"
    current="$(basename "$(login_shell)")"
    [[ "$current" == "$expected_shell" ]] || add_drift system login-shell "$current" "$expected_shell"
  fi

  expected="$(expected_value ENABLE_REMOTE_ACCESS)"
  if [[ "$expected" == true && "${BOOTSTRAP_WSL_VERSION:-}" != 1 ]]; then current="$(ssh_service_state)"; [[ "$current" == enabled-active ]] || add_drift service SSH "$current" enabled-active; fi
}

print_header() {
  printf '%s\nLinux Machine Audit\n%s\nRead-only — no changes will be made\n' '---' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf 'Context: %s%s\n---\n' "$AUDIT_CONTEXT" "${AUDIT_PROFILE:+ ($AUDIT_PROFILE)}"
}

print_human() {
  local row kind package state target dotstate detail installed=0 missing=0 unavailable=0
  print_header
  if want_section system; then
    printf '\n── System ──\n\n'
    printf '  %-28s %s\n' Distribution "$DISTRO_NAME" Package-manager "$PACKAGE_MANAGER" Architecture "$(uname -m)" Account "$(id -un)" Hostname "$(hostname -s 2>/dev/null || true)" Login-shell "$(login_shell)"
  fi
  if want_section tools; then
    printf '\n── Core tools ──\n\n'
    for package in git curl mise gum bash zsh fish nvim tmux rg fd gh; do printf '  %-28s %s\n' "$package" "$(tool_version "$package")"; done
    printf '  %-28s %s\n' Fisher "$(fisher_state)"
  fi
  if want_section packages; then
    printf '\n── Declarative native packages ──\n\n'
    for row in "${PACKAGE_ROWS[@]}"; do IFS=$'\t' read -r kind package state <<< "$row"; printf '  %-12s %-28s %s\n' "$kind" "$package" "$state"; case "$state" in installed) installed=$((installed+1));; missing) missing=$((missing+1));; unavailable) unavailable=$((unavailable+1));; esac; done
    printf '\n  Summary: %d installed, %d missing, %d unavailable in configured repositories\n' "$installed" "$missing" "$unavailable"
  fi
  if want_section config; then
    printf '\n── Configuration ──\n\n'
    printf '  %-28s %s\n' 'Dotfiles checkout' "$BOOTSTRAP_ROOT" 'Mise config' "$(if paths_same "$HOME/.config/mise" "$BOOTSTRAP_ROOT/mise"; then printf 'correct repository symlink'; elif [[ -e "$HOME/.config/mise/config.toml" ]]; then printf 'user/seed config'; else printf missing; fi)" 'Mise .env' "$(if [[ -f "$HOME/.config/mise/.env" ]]; then stat -c '%a %n' "$HOME/.config/mise/.env" 2>/dev/null || printf present; else printf missing; fi)" 'Git config' "$(git_config_mode)" 'Git author' "$(git config --global --includes --get user.name 2>/dev/null || printf unset) <$(git config --global --includes --get user.email 2>/dev/null || printf unset)>" 'Code directory' "$(if [[ -d "$HOME/code" ]]; then printf present; else printf missing; fi)" 'Downloads path' "$(if [[ -L "$HOME/Downloads" ]]; then printf 'symlink -> %s' "$(readlink "$HOME/Downloads")"; elif [[ -e "$HOME/Downloads" ]]; then printf directory; else printf missing; fi)"
    printf '\n  Dotfile targets:\n'
    for row in "${DOTFILE_ROWS[@]}"; do IFS=$'\t' read -r target dotstate detail <<< "$row"; printf '    %-46s %-14s %s\n' "${target/#$HOME/~}" "$dotstate" "$detail"; done
  fi
  if want_section services; then
    printf '\n── Services and desktop defaults ──\n\n'
    printf '  %-28s %s\n' 'SSH service' "$(ssh_service_state)" 'HTTP handler' "$(xdg_default_handler x-scheme-handler/http)" 'PDF handler' "$(xdg_default_handler application/pdf)" 'Zscaler block' "$(grep -Fq "$ZSCALER_ENV_BEGIN" "$HOME/.config/mise/.env" 2>/dev/null && printf present || printf absent)"
  fi
  if [[ "$AUDIT_CONTEXT" != general ]]; then
    printf '\n── Bootstrap drift ──\n\n'
    if [[ ${#DRIFT[@]} -eq 0 ]]; then printf '  No drift found for this comparison.\n'
    else for row in "${DRIFT[@]}"; do IFS=$'\t' read -r kind package state detail <<< "$row"; printf '  %-12s %-34s current=%s expected=%s\n' "$kind" "$package" "$state" "$detail"; done; fi
  fi
  printf '\nAudit complete.\n'
}

json_rows() {
  local array_name="$1" fields="$2" row first=1 i value
  local -n rows_ref="$array_name"
  printf '['
  for row in "${rows_ref[@]}"; do
    [[ "$first" == 1 ]] || printf ','; first=0
    IFS=$'\t' read -ra values <<< "$row"
    printf '{'; i=0
    while IFS= read -r field; do
      [[ "$i" == 0 ]] || printf ','
      value="${values[$i]:-}"; printf '"%s":"%s"' "$field" "$(json_escape "$value")"; i=$((i+1))
    done <<< "$fields"
    printf '}'
  done
  printf ']'
}

print_json() {
  printf '{'
  printf '"audit_context":"%s",' "$(json_escape "$AUDIT_CONTEXT")"
  printf '"profile":%s,' "$(if [[ -n "$AUDIT_PROFILE" ]]; then printf '"%s"' "$(json_escape "$AUDIT_PROFILE")"; else printf null; fi)"
  printf '"system":{"distribution":"%s","id":"%s","package_manager":"%s","architecture":"%s","account":"%s","hostname":"%s","login_shell":"%s"},' "$(json_escape "$DISTRO_NAME")" "$(json_escape "$DISTRO_ID")" "$PACKAGE_MANAGER" "$(json_escape "$(uname -m)")" "$(json_escape "$(id -un)")" "$(json_escape "$(hostname -s 2>/dev/null || true)")" "$(json_escape "$(login_shell)")"
  printf '"git":{"mode":"%s","name":"%s","email":"%s"},' "$(git_config_mode)" "$(json_escape "$(git config --global --includes --get user.name 2>/dev/null || true)")" "$(json_escape "$(git config --global --includes --get user.email 2>/dev/null || true)")"
  printf '"packages":'; json_rows PACKAGE_ROWS $'kind\npackage\nstate'; printf ','
  printf '"dotfiles":'; json_rows DOTFILE_ROWS $'target\nstate\ndetail'; printf ','
  printf '"drift":'; json_rows DRIFT $'kind\nitem\ncurrent\nexpected'
  printf '}\n'
}

main() {
  parse_args "$@"
  detect_linux_platform
  [[ "$AUDIT_CONTEXT" != saved-plan || -f "$STATE_FILE_PATH" ]] || fail "Saved-plan audit requested but $STATE_FILE_PATH is absent"
  audit_packages
  audit_dotfiles
  build_drift
  if [[ "$JSON" == 1 ]]; then print_json; else print_human; fi
}

main "$@"
