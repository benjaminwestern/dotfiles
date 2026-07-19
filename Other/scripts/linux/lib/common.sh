#!/usr/bin/env bash
# Shared Linux bootstrap primitives.  Bash 4+ is available on every supported
# distribution (Debian/Ubuntu/Mint and Arch/CachyOS).

if [[ "${_LINUX_COMMON_LOADED:-0}" == 1 ]]; then
  return 0
fi
_LINUX_COMMON_LOADED=1

set -euo pipefail

STATE_FILE_PATH="${STATE_FILE_PATH:-$HOME/.config/dotfiles/state.env}"
DRY_RUN="${DRY_RUN:-0}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
BOOTSTRAP_ROOT="${BOOTSTRAP_ROOT:-$DOTFILES_DIR}"
LINK_SOURCE_ROOT="${LINK_SOURCE_ROOT:-$BOOTSTRAP_ROOT}"
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

PROFILE_BEGIN='# >>> foundation-bootstrap >>>'
PROFILE_END='# <<< foundation-bootstrap <<<'
MISE_BEGIN='# >>> foundation-seed >>>'
MISE_END='# <<< foundation-seed <<<'
ZSCALER_ENV_BEGIN='# >>> zscaler-bootstrap >>>'
ZSCALER_ENV_END='# <<< zscaler-bootstrap <<<'

if [[ -t 1 ]]; then
  _BOLD=$'\033[1m' _GREEN=$'\033[32m' _YELLOW=$'\033[33m'
  _BLUE=$'\033[34m' _RED=$'\033[31m' _CYAN=$'\033[36m' _RESET=$'\033[0m'
else
  _BOLD='' _GREEN='' _YELLOW='' _BLUE='' _RED='' _CYAN='' _RESET=''
fi

PASS_COUNT=0 FIX_COUNT=0 SKIP_COUNT=0 FAIL_COUNT=0

command_exists() { command -v "$1" >/dev/null 2>&1; }
dry_run_active() { [[ "$DRY_RUN" == 1 ]]; }

status_pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '%s✓%s %s%-34s%s %s\n' "$_GREEN" "$_RESET" "$_BOLD" "$1" "$_RESET" "${2:-}"; }
status_fix() { FIX_COUNT=$((FIX_COUNT + 1)); printf '%s↻%s %s%-34s%s %s\n' "$_YELLOW" "$_RESET" "$_BOLD" "$1" "$_RESET" "${2:-}"; }
status_skip() { SKIP_COUNT=$((SKIP_COUNT + 1)); printf '%s○%s %s%-34s%s %s\n' "$_CYAN" "$_RESET" "$_BOLD" "$1" "$_RESET" "${2:-}"; }
status_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf '%s✗%s %s%-34s%s %s\n' "$_RED" "$_RESET" "$_BOLD" "$1" "$_RESET" "${2:-}" >&2; }
status_summary() { printf '\n%s%s:%s %d pass, %d fix, %d skip, %d fail\n' "$_BOLD" "${1:-Bootstrap}" "$_RESET" "$PASS_COUNT" "$FIX_COUNT" "$SKIP_COUNT" "$FAIL_COUNT"; }
note() { printf '%s→%s %s\n' "$_BLUE" "$_RESET" "$1"; }
fail() { printf '%sERROR:%s %s\n' "$_RED" "$_RESET" "$1" >&2; exit 1; }

dry_run_log() { printf '  %s[dry-run]%s would run: %s\n' "$_CYAN" "$_RESET" "$1"; }
run_or_dry() {
  if dry_run_active; then dry_run_log "$(printf '%q ' "$@")"; return 0; fi
  "$@"
}

bootstrap_git() { GIT_CONFIG_GLOBAL=/dev/null command git "$@"; }
bootstrap_mise() { command mise -C "$HOME" "$@"; }
bootstrap_repo_mise() {
  MISE_GLOBAL_CONFIG_FILE="$BOOTSTRAP_ROOT/mise/config.toml" \
  MISE_GLOBAL_CONFIG_ROOT="$HOME" \
  MISE_AUTO_ENV=true \
    command mise -C "$HOME" "$@"
}

elevate() {
  if [[ "$(id -u)" == 0 ]]; then "$@"; return; fi
  command_exists sudo || fail "Administrator access is required, but sudo is unavailable"
  sudo "$@"
}

run_elevated_or_dry() {
  if dry_run_active; then dry_run_log "sudo $(printf '%q ' "$@")"; return 0; fi
  elevate "$@"
}

# Distribution detection deliberately keys off the package manager after
# validating /etc/os-release. Arch derivatives are not Debian-family.
detect_linux_platform() {
  local release_file="${BOOTSTRAP_OS_RELEASE_FILE:-/etc/os-release}"
  DISTRO_ID=unknown DISTRO_LIKE='' DISTRO_NAME=Linux PACKAGE_MANAGER=''
  if [[ -r "$release_file" ]]; then
    local detected_id detected_like detected_name
    detected_id="$(awk -F= '$1=="ID" {gsub(/^"|"$/, "", $2); print tolower($2)}' "$release_file")"
    detected_like="$(awk -F= '$1=="ID_LIKE" {gsub(/^"|"$/, "", $2); print tolower($2)}' "$release_file")"
    detected_name="$(awk -F= '$1=="PRETTY_NAME" {sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print}' "$release_file")"
    [[ -z "$detected_id" ]] || DISTRO_ID="$detected_id"
    [[ -z "$detected_like" ]] || DISTRO_LIKE="$detected_like"
    [[ -z "$detected_name" ]] || DISTRO_NAME="$detected_name"
  fi

  if [[ -n "${BOOTSTRAP_PACKAGE_MANAGER:-}" ]]; then
    PACKAGE_MANAGER="$BOOTSTRAP_PACKAGE_MANAGER"
  elif command_exists apt-get && { [[ "$DISTRO_ID" =~ ^(debian|ubuntu|linuxmint|pop|elementary|raspbian)$ ]] || [[ "$DISTRO_LIKE" == *debian* ]] || [[ "$DISTRO_LIKE" == *ubuntu* ]]; }; then
    PACKAGE_MANAGER=apt
  elif command_exists pacman && { [[ "$DISTRO_ID" =~ ^(arch|cachyos|manjaro|endeavouros|garuda)$ ]] || [[ "$DISTRO_LIKE" == *arch* ]]; }; then
    PACKAGE_MANAGER=pacman
  elif command_exists apt-get; then
    PACKAGE_MANAGER=apt
  elif command_exists pacman; then
    PACKAGE_MANAGER=pacman
  else
    fail "Supported Linux package manager not found (expected apt-get or pacman)"
  fi
  export DISTRO_ID DISTRO_LIKE DISTRO_NAME PACKAGE_MANAGER
}

package_installed() {
  case "$PACKAGE_MANAGER" in
    apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
    pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

package_available() {
  case "$PACKAGE_MANAGER" in
    apt) apt-cache show "$1" >/dev/null 2>&1 ;;
    pacman) pacman -Si "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# Flatpak desktop entries live outside the traditional XDG search path. A
# graphical login normally imports /etc/profile.d/flatpak.sh, but bootstrap and
# audit commands are commonly run over SSH where that profile hook is absent.
# Build the same search path here so xdg-mime sees the applications mise has
# installed system-wide.
refresh_flatpak_data_dirs() {
  command_exists flatpak || return 0
  local data_dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" installation share
  while IFS= read -r installation; do
    [[ -n "$installation" ]] || continue
    share="${installation%/}/exports/share"
    case ":$data_dirs:" in
      *":$share:"*|*":$share/:"*) ;;
      *) data_dirs="$share:$data_dirs" ;;
    esac
  done < <(flatpak --installations 2>/dev/null || true)
  export XDG_DATA_DIRS="$data_dirs"
}

stock_skeleton_file() {
  local target="$1" relative skeleton
  [[ -f "$target" && ! -L "$target" && "$target" == "$HOME/"* ]] || return 1
  relative="${target#"$HOME"/}"
  skeleton="/etc/skel/$relative"
  [[ -f "$skeleton" ]] && cmp -s "$target" "$skeleton"
}

wait_for_package_manager() {
  [[ "$PACKAGE_MANAGER" == apt ]] || return 0
  local elapsed=0 timeout="${APT_LOCK_TIMEOUT_SECONDS:-900}"
  local busy=false
  while :; do
    busy=false
    if command_exists fuser && {
      fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
        || fuser /var/lib/dpkg/lock >/dev/null 2>&1 \
        || fuser /var/lib/apt/lists/lock >/dev/null 2>&1;
    }; then busy=true; fi
    [[ "$busy" == true ]] || break
    if dry_run_active; then
      status_fix "APT package-manager lock" "would wait for Ubuntu background updates"
      return 0
    fi
    if [[ "$elapsed" -eq 0 ]]; then
      note "Ubuntu background updates are using apt/dpkg; waiting safely for them to finish."
    elif (( elapsed % 30 == 0 )); then
      note "Still waiting for apt/dpkg (${elapsed}s elapsed)..."
    fi
    (( elapsed < timeout )) || fail "apt/dpkg remained busy for ${timeout}s; rerun after Ubuntu updates finish"
    sleep 5
    elapsed=$((elapsed + 5))
  done
  [[ "$elapsed" -eq 0 ]] || status_pass "APT package-manager lock" "became available after ${elapsed}s"
}

state_get() {
  local key="$1"
  [[ -f "$STATE_FILE_PATH" ]] || return 0
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$STATE_FILE_PATH"
}

state_value_safe() {
  [[ "$1" != *$'\n'* && "$1" != *$'\r'* ]]
}

state_write_all() {
  dry_run_active && { status_skip "Bootstrap state" "dry-run leaves saved plan unchanged"; return 0; }
  local state_dir tmp key value
  state_dir="$(dirname "$STATE_FILE_PATH")"
  mkdir -p "$state_dir"
  tmp="$(mktemp "$state_dir/state.env.XXXXXX")"
  chmod 600 "$tmp"
  {
    printf '# dotfiles state file -- auto-generated by Linux bootstrap\n'
    printf '# last written: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for key in PREFERRED_SHELL DEVICE_PROFILE ENABLE_ZSCALER ENABLE_DOTFILES ENABLE_PACKAGES ENABLE_APPLICATIONS ENABLE_MISE_TOOLS ENABLE_SHELL_DEFAULT ENABLE_CODE_DIRECTORY ENABLE_DOWNLOADS_LINK ENABLE_GIT_IDENTITY ENABLE_LINUX_DEFAULTS ENABLE_REMOTE_ACCESS DEVICE_NAME DOWNLOADS_TARGET GIT_USER_NAME GIT_USER_EMAIL LINUX_HOSTNAME LINUX_DEFAULT_APPS; do
      value="$(resolved_value "$key")"
      state_value_safe "$value" || { rm -f "$tmp"; fail "State value for $key contains a newline"; }
      printf '%s=%s\n' "$key" "$value"
    done
  } > "$tmp"
  mv -f "$tmp" "$STATE_FILE_PATH"
  status_pass "Bootstrap state" "$STATE_FILE_PATH"
}

resolved_value() {
  case "$1" in
    PREFERRED_SHELL) printf '%s' "${RESOLVED_SHELL:-}" ;;
    DEVICE_PROFILE) printf '%s' "${RESOLVED_PROFILE:-}" ;;
    DEVICE_NAME) printf '%s' "${RESOLVED_DEVICE_NAME:-}" ;;
    GIT_USER_NAME) printf '%s' "${RESOLVED_GIT_USER_NAME:-}" ;;
    GIT_USER_EMAIL) printf '%s' "${RESOLVED_GIT_USER_EMAIL:-}" ;;
    DOWNLOADS_TARGET) printf '%s' "${RESOLVED_DOWNLOADS_TARGET:-}" ;;
    ENABLE_ZSCALER) printf '%s' "${RESOLVED_ZSCALER:-}" ;;
    ENABLE_DOTFILES) printf '%s' "${RESOLVED_DOTFILES:-}" ;;
    ENABLE_PACKAGES) printf '%s' "${RESOLVED_PACKAGES:-}" ;;
    ENABLE_APPLICATIONS) printf '%s' "${RESOLVED_APPLICATIONS:-}" ;;
    ENABLE_MISE_TOOLS) printf '%s' "${RESOLVED_MISE_TOOLS:-}" ;;
    ENABLE_SHELL_DEFAULT) printf '%s' "${RESOLVED_SHELL_DEFAULT:-}" ;;
    ENABLE_CODE_DIRECTORY) printf '%s' "${RESOLVED_CODE_DIRECTORY:-}" ;;
    ENABLE_DOWNLOADS_LINK) printf '%s' "${RESOLVED_DOWNLOADS_LINK:-}" ;;
    ENABLE_GIT_IDENTITY) printf '%s' "${RESOLVED_GIT_IDENTITY:-}" ;;
    ENABLE_LINUX_DEFAULTS) printf '%s' "${RESOLVED_LINUX_DEFAULTS:-}" ;;
    ENABLE_REMOTE_ACCESS) printf '%s' "${RESOLVED_REMOTE_ACCESS:-}" ;;
    LINUX_HOSTNAME) printf '%s' "${RESOLVED_LINUX_HOSTNAME:-}" ;;
    LINUX_DEFAULT_APPS) printf '%s' "${RESOLVED_LINUX_DEFAULT_APPS:-}" ;;
  esac
}

use_gum() { [[ "$NON_INTERACTIVE" != 1 ]] && command_exists gum && [[ -t 0 ]]; }

confirm() {
  local prompt="$1" default="${2:-false}"
  if use_gum; then
    if [[ "$default" == true ]]; then gum confirm --default=true "$prompt"; else gum confirm "$prompt"; fi
    return
  fi
  [[ "$NON_INTERACTIVE" == 1 ]] && [[ "$default" == true ]]
}

choose() {
  local header="$1" default="$2"; shift 2
  if use_gum; then gum choose --header "$header" "$@"; else printf '%s' "$default"; fi
}

input_value() {
  local header="$1" value="${2:-}"
  if use_gum; then gum input --header "$header" --value "$value"; else printf '%s' "$value"; fi
}

profile_default() {
  local profile="$1" key="$2"
  case "$profile:$key" in
    work:ENABLE_ZSCALER) printf auto ;;
    home:ENABLE_ZSCALER|minimal:ENABLE_ZSCALER) printf false ;;
    work:ENABLE_DOWNLOADS_LINK|home:ENABLE_DOWNLOADS_LINK) printf false ;;
    work:ENABLE_*) printf true ;;
    home:ENABLE_*) printf true ;;
    minimal:ENABLE_CODE_DIRECTORY|minimal:ENABLE_GIT_IDENTITY|minimal:ENABLE_LINUX_DEFAULTS) printf true ;;
    minimal:ENABLE_*) printf false ;;
    work:LINUX_*|home:LINUX_*) printf true ;;
    minimal:LINUX_HOSTNAME) printf true ;;
    minimal:LINUX_*) printf false ;;
  esac
}

resolve_setting() {
  local key="$1" cli="$2" env_val="$3" state_val="$4" profile_val="$5" hard="$6"
  if [[ -n "$cli" ]]; then printf '%s' "$cli"
  elif [[ -n "$env_val" ]]; then printf '%s' "$env_val"
  elif [[ -n "$state_val" ]]; then printf '%s' "$state_val"
  elif [[ -n "$profile_val" ]]; then printf '%s' "$profile_val"
  else printf '%s' "$hard"
  fi
}

validate_boolish() {
  case "$2" in true|false) ;; *) fail "$1 must be true or false, got: $2" ;; esac
}

resolve_linux_plan() {
  local cli_profile="${CLI_PROFILE:-${DEVICE_PROFILE:-}}" profile_state
  profile_state="$(state_get DEVICE_PROFILE)"
  RESOLVED_PROFILE="${cli_profile:-${profile_state:-minimal}}"
  case "$RESOLVED_PROFILE" in work|home|minimal) ;; *) fail "Profile must be work, home, or minimal" ;; esac

  RESOLVED_SHELL="${CLI_SHELL:-${PREFERRED_SHELL:-$(state_get PREFERRED_SHELL)}}"
  RESOLVED_SHELL="${RESOLVED_SHELL:-$(if [[ "$RESOLVED_PROFILE" == minimal ]]; then printf bash; else printf fish; fi)}"
  case "$RESOLVED_SHELL" in bash|zsh|fish) ;; *) fail "Linux shell must be bash, zsh, or fish" ;; esac

  local suffix resolved cli env_value state_value default_value
  for suffix in ZSCALER DOTFILES PACKAGES APPLICATIONS MISE_TOOLS SHELL_DEFAULT CODE_DIRECTORY DOWNLOADS_LINK GIT_IDENTITY LINUX_DEFAULTS REMOTE_ACCESS; do
    cli="CLI_ENABLE_${suffix}"; env_value="ENABLE_${suffix}"; resolved="RESOLVED_${suffix}"
    # An explicitly selected profile means "start from this preset". Saved
    # per-feature choices are only inherited when no profile was supplied.
    if [[ -n "$cli_profile" ]]; then state_value=''; else state_value="$(state_get "ENABLE_${suffix}")"; fi
    default_value="$(profile_default "$RESOLVED_PROFILE" "ENABLE_${suffix}")"
    printf -v "$resolved" '%s' "$(resolve_setting "ENABLE_${suffix}" "${!cli:-}" "${!env_value:-}" "$state_value" "$default_value" false)"
    if [[ "$suffix" == ZSCALER ]]; then
      case "${!resolved}" in true|false|auto) ;; *) fail "ENABLE_ZSCALER must be true, false, or auto" ;; esac
    else
      validate_boolish "ENABLE_${suffix}" "${!resolved}"
    fi
  done

  for suffix in HOSTNAME DEFAULT_APPS; do
    cli="CLI_LINUX_${suffix}"; env_value="LINUX_${suffix}"; resolved="RESOLVED_LINUX_${suffix}"
    if [[ "$RESOLVED_LINUX_DEFAULTS" != true ]]; then printf -v "$resolved" false; continue; fi
    printf -v "$resolved" '%s' "$(resolve_setting "LINUX_${suffix}" "${!cli:-}" "${!env_value:-}" "$(state_get "LINUX_${suffix}")" "$(profile_default "$RESOLVED_PROFILE" "LINUX_${suffix}")" false)"
    validate_boolish "LINUX_${suffix}" "${!resolved}"
  done

  RESOLVED_DEVICE_NAME="${CLI_DEVICE_NAME:-${DEVICE_NAME:-$(state_get DEVICE_NAME)}}"
  RESOLVED_DEVICE_NAME="${RESOLVED_DEVICE_NAME:-$(hostname -s 2>/dev/null || printf linux)}"
  [[ "$RESOLVED_DEVICE_NAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || fail "Device name must be a valid hostname"

  RESOLVED_DOWNLOADS_TARGET="${CLI_DOWNLOADS_TARGET:-${DOWNLOADS_TARGET:-$(state_get DOWNLOADS_TARGET)}}"
  if [[ "$RESOLVED_DOWNLOADS_LINK" == true ]]; then
    [[ "$RESOLVED_DOWNLOADS_TARGET" == /* ]] || fail "Downloads target must be an absolute path when Downloads linking is selected"
  else
    RESOLVED_DOWNLOADS_TARGET=''
  fi

  RESOLVED_GIT_USER_NAME="${CLI_GIT_USER_NAME:-${GIT_USER_NAME:-$(state_get GIT_USER_NAME)}}"
  RESOLVED_GIT_USER_EMAIL="${CLI_GIT_USER_EMAIL:-${GIT_USER_EMAIL:-$(state_get GIT_USER_EMAIL)}}"
  if [[ "$RESOLVED_GIT_IDENTITY" == true ]]; then
    [[ -n "$RESOLVED_GIT_USER_NAME" ]] || RESOLVED_GIT_USER_NAME="$(git config --global --includes --get user.name 2>/dev/null || true)"
    [[ -n "$RESOLVED_GIT_USER_EMAIL" ]] || RESOLVED_GIT_USER_EMAIL="$(git config --global --includes --get user.email 2>/dev/null || true)"
    [[ -n "$RESOLVED_GIT_USER_NAME" ]] || fail "Git author name is required when Git identity is selected"
    [[ "$RESOLVED_GIT_USER_EMAIL" == *@*.* ]] || fail "A valid Git author email is required when Git identity is selected"
  else
    RESOLVED_GIT_USER_NAME='' RESOLVED_GIT_USER_EMAIL=''
  fi
  export RESOLVED_PROFILE RESOLVED_SHELL RESOLVED_ZSCALER RESOLVED_DOTFILES RESOLVED_PACKAGES RESOLVED_APPLICATIONS RESOLVED_MISE_TOOLS RESOLVED_SHELL_DEFAULT RESOLVED_CODE_DIRECTORY RESOLVED_DOWNLOADS_LINK RESOLVED_DOWNLOADS_TARGET RESOLVED_GIT_IDENTITY RESOLVED_LINUX_DEFAULTS RESOLVED_REMOTE_ACCESS RESOLVED_LINUX_HOSTNAME RESOLVED_LINUX_DEFAULT_APPS RESOLVED_DEVICE_NAME RESOLVED_GIT_USER_NAME RESOLVED_GIT_USER_EMAIL
}

write_managed_block() {
  local path="$1" begin="$2" end="$3" content="$4" parent tmp
  parent="$(dirname "$path")"
  if dry_run_active; then dry_run_log "write managed block to $path"; return 0; fi
  mkdir -p "$parent"
  tmp="$(mktemp "$parent/.bootstrap.XXXXXX")"
  if [[ -f "$path" ]] && grep -Fq "$begin" "$path"; then
    awk -v begin="$begin" -v end="$end" -v replacement="$content" '
      $0 == begin { print replacement; skipping=1; next }
      skipping && $0 == end { skipping=0; next }
      !skipping { print }
    ' "$path" > "$tmp"
  else
    [[ -f "$path" ]] && cat "$path" > "$tmp"
    [[ ! -s "$tmp" ]] || printf '\n' >> "$tmp"
    printf '%s\n' "$content" >> "$tmp"
  fi
  mv -f "$tmp" "$path"
}

paths_same() { [[ -e "$1" && -e "$2" && "$1" -ef "$2" ]]; }

source_available() {
  local source="$1" relative
  [[ -e "$source" ]] && return 0
  if dry_run_active && [[ "$LINK_SOURCE_ROOT" != "$BOOTSTRAP_ROOT" && "$source" == "$LINK_SOURCE_ROOT"/* ]]; then
    relative="${source#"$LINK_SOURCE_ROOT"/}"
    [[ -e "$BOOTSTRAP_ROOT/$relative" ]]
    return
  fi
  return 1
}

linux_package_catalogue() {
  local config="$BOOTSTRAP_ROOT/mise/config.linux.toml"
  [[ -f "$config" ]] || return 0
  awk -v manager="$PACKAGE_MANAGER" '
    index($0, "\"" manager ":") == 1 {
      line = $0
      sub("^\"" manager ":", "", line)
      sub("\".*$", "", line)
      print line
    }
  ' "$config" | {
    if [[ "${BOOTSTRAP_WSL_VERSION:-}" == 1 ]]; then
      # WSL 1 has no systemd or device-service support. Keep the portable CLI
      # catalogue, but do not ask dpkg to configure packages whose maintainer
      # scripts require those facilities. WSL 2 and ordinary Linux hosts retain
      # the complete package set.
      grep -Ev '^(flatpak|yubikey-manager)$' || true
    else
      cat
    fi
  }
}

linux_baseline_package_specs() {
  case "$PACKAGE_MANAGER" in
    apt) printf '%s\n' apt:ca-certificates apt:curl apt:git apt:openssh-client apt:bash apt:tar ;;
    pacman) printf '%s\n' pacman:ca-certificates pacman:curl pacman:git pacman:openssh pacman:bash pacman:tar ;;
  esac
}

linux_application_catalogue() {
  [[ "${BOOTSTRAP_WSL_VERSION:-}" != 1 ]] || return 0
  printf '%s\n' com.visualstudio.code
  case "$(uname -m)" in
    x86_64|amd64) printf '%s\n' com.google.Chrome ;;
    aarch64|arm64) printf '%s\n' org.chromium.Chromium ;;
  esac
}

linux_application_package_specs() {
  local package
  while IFS= read -r package; do printf 'flatpak:%s\n' "$package"; done < <(linux_application_catalogue)
}

json_escape() {
  local value="$1"
  value=${value//\\/\\\\}; value=${value//\"/\\\"}; value=${value//$'\n'/\\n}; value=${value//$'\r'/\\r}; value=${value//$'\t'/\\t}
  printf '%s' "$value"
}
