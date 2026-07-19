#!/bin/bash
set -euo pipefail

# defaults-macos.sh
# Configures macOS system defaults for a fresh machine setup.
# Sets canonical machine names, Dock behaviour, menu-bar items and clock,
# Finder preferences, mouse settings, power/sleep options, and screenshots.
#
# Usage: ./defaults-macos.sh [mac-mini|macbook-air|macbook-pro]
#   The hardware profile is detected from System Information when omitted.

detect_machine_profile() {
  local model_name
  model_name="$(system_profiler SPHardwareDataType 2>/dev/null \
    | awk -F': ' '/Model Name:/ { print $2; exit }')"
  case "$model_name" in
    'Mac mini')    printf '%s\n' 'mac-mini' ;;
    'MacBook Air') printf '%s\n' 'macbook-air' ;;
    'MacBook Pro') printf '%s\n' 'macbook-pro' ;;
    *)
      printf 'Unsupported Mac model: %s (%s)\n' "$model_name" "$(sysctl -n hw.model)" >&2
      return 1
      ;;
  esac
}

SCRIPT_MACHINE_PROFILE="${1:-$(detect_machine_profile)}"
case "$SCRIPT_MACHINE_PROFILE" in
  mac-mini|macbook-air|macbook-pro) ;;
  *)
    printf 'Invalid machine profile: %s\n' "$SCRIPT_MACHINE_PROFILE" >&2
    exit 2
    ;;
esac

component_enabled() {
  local variable_name="$1"
  local value="${!variable_name-true}"
  [[ "$value" == "true" ]]
}

BOOTSTRAP_DEVICE_NAME="${BOOTSTRAP_DEVICE_NAME:-$SCRIPT_MACHINE_PROFILE}"
if [[ ! "$BOOTSTRAP_DEVICE_NAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; then
  printf 'Invalid device name: %s\n' "$BOOTSTRAP_DEVICE_NAME" >&2
  exit 2
fi

###############################################################################
# Hostname                                                                    #
###############################################################################

if component_enabled MACOS_HOSTNAME; then
  sudo scutil --set ComputerName "$BOOTSTRAP_DEVICE_NAME"
  sudo scutil --set LocalHostName "$BOOTSTRAP_DEVICE_NAME"
  sudo scutil --set HostName "$BOOTSTRAP_DEVICE_NAME"
fi

###############################################################################
# Dock                                                                        #
###############################################################################

if component_enabled MACOS_DOCK; then
  # Move Dock to the left
  defaults write com.apple.dock orientation left

# Enable Dock auto-hide
defaults write com.apple.dock autohide -bool true

# Disable Dock auto-hide delay and animation
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -int 0

# Replace the factory Dock applications with the two validated persistent pins.
defaults write com.apple.dock persistent-apps -array
  if [[ -d /Applications/Ghostty.app ]]; then
    defaults write com.apple.dock persistent-apps -array-add \
      '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>/Applications/Ghostty.app/</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>'
  fi
  if [[ -d "/Applications/Google Chrome.app" ]]; then
    defaults write com.apple.dock persistent-apps -array-add \
      '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>/Applications/Google Chrome.app/</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>'
  fi

# Purge all non-persistent app icons from the Dock
defaults delete com.apple.dock persistent-others 2>/dev/null || true

# Remove Recents from the Dock
defaults write com.apple.dock show-recents -bool false

  killall Dock 2>/dev/null || true
fi

###############################################################################
# Desktop                                                                     #
###############################################################################

# Hide widgets on the desktop and in Stage Manager
if component_enabled MACOS_DESKTOP; then
  defaults write com.apple.WindowManager StandardHideWidgets -bool true
  defaults write com.apple.WindowManager StageManagerHideWidgets -bool true
  defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
  killall Dock 2>/dev/null || true
fi

###############################################################################
# Default applications                                                        #
###############################################################################

# Tahoe restricts the legacy LaunchServices setter APIs when invoked from a
# generic command-line process. Update only the explicit handler records while
# preserving the rest of the user's LaunchServices preferences. This uses only
# macOS-native tools plus jq, which the personal layer ensures when this group
# is selected.
if component_enabled MACOS_DEFAULT_APPS; then
CHROME_APP="/Applications/Google Chrome.app"
CHROME_BUNDLE_ID="com.google.Chrome"
LAUNCHSERVICES_DOMAIN="com.apple.LaunchServices/com.apple.launchservices.secure"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$CHROME_APP" ]]; then
  printf 'Google Chrome is required before default handlers can be configured\n' >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required to preserve LaunchServices handler records\n' >&2
  exit 1
fi

"$LSREGISTER" -f "$CHROME_APP"

launchservices_temp="$(mktemp)"
if ! defaults export "$LAUNCHSERVICES_DOMAIN" "$launchservices_temp" >/dev/null 2>&1; then
  plutil -create xml1 "$launchservices_temp"
fi
if ! plutil -extract LSHandlers raw "$launchservices_temp" >/dev/null 2>&1; then
  plutil -insert LSHandlers -array "$launchservices_temp"
fi

# Remove only records this bootstrap owns. Descending indices keep removals
# stable while every unrelated URL scheme and document handler is preserved.
handler_indices="$(
  plutil -convert json -o - "$launchservices_temp" |
    jq -r '
      .LSHandlers
      | to_entries[]
      | select(
          (.value.LSHandlerURLScheme == "http") or
          (.value.LSHandlerURLScheme == "https") or
          (.value.LSHandlerContentType == "public.html") or
          (.value.LSHandlerContentType == "public.xhtml") or
          (.value.LSHandlerContentType == "com.adobe.pdf")
        )
      | .key
    ' |
    sort -rn
)"
if [[ -n "$handler_indices" ]]; then
  while IFS= read -r handler_index; do
    plutil -remove "LSHandlers.$handler_index" "$launchservices_temp"
  done <<< "$handler_indices"
fi

for url_scheme in http https; do
  plutil -insert LSHandlers -json \
    "{\"LSHandlerURLScheme\":\"$url_scheme\",\"LSHandlerRoleAll\":\"$CHROME_BUNDLE_ID\"}" \
    -append "$launchservices_temp"
done
for content_type in public.html public.xhtml; do
  plutil -insert LSHandlers -json \
    "{\"LSHandlerContentType\":\"$content_type\",\"LSHandlerRoleAll\":\"$CHROME_BUNDLE_ID\"}" \
    -append "$launchservices_temp"
done
plutil -insert LSHandlers -json \
  "{\"LSHandlerContentType\":\"com.adobe.pdf\",\"LSHandlerRoleAll\":\"$CHROME_BUNDLE_ID\",\"LSHandlerRoleViewer\":\"$CHROME_BUNDLE_ID\"}" \
  -append "$launchservices_temp"

plutil -lint "$launchservices_temp" >/dev/null
defaults import "$LAUNCHSERVICES_DOMAIN" "$launchservices_temp" >/dev/null
rm -f "$launchservices_temp"
killall -u "$USER" lsd 2>/dev/null || true
fi

###############################################################################
# Menu bar and clock                                                          #
###############################################################################

if component_enabled MACOS_MENU_BAR; then
# Prevent an open settings pane from writing its cached values back over these
# preferences while ControlCenter is being restarted.
killall "System Settings" 2>/dev/null || true

# Keep connectivity and audio controls visible in the menu bar. Tahoe stores
# the authoritative mode per host; 18 means always visible.
for menu_item in WiFi Bluetooth Sound; do
  defaults -currentHost write com.apple.controlcenter "$menu_item" -int 18
done

# Hide the Spotlight magnifying-glass item. Spotlight search remains available
# through its keyboard shortcut and Finder; this changes only menu-bar presence.
defaults -currentHost write com.apple.Spotlight MenuItemHidden -int 1

# Show Battery and its percentage only on hardware that has a battery.
if [[ "$SCRIPT_MACHINE_PROFILE" == macbook-* ]]; then
  defaults -currentHost write com.apple.controlcenter Battery -int 18
  defaults -currentHost write com.apple.controlcenter BatteryShowPercentage -bool true
  defaults write com.apple.menuextra.battery ShowPercent -bool true
fi

# DDD DD MMM and HH:MM:SS, using Unicode/ICU date-field notation.
defaults delete NSGlobalDomain AppleICUForce12HourTime 2>/dev/null || true
defaults write NSGlobalDomain AppleICUForce24HourTime -bool true
defaults write com.apple.menuextra.clock IsAnalog -bool false
defaults write com.apple.menuextra.clock Show24Hour -bool true
defaults write com.apple.menuextra.clock ShowAMPM -bool false
defaults write com.apple.menuextra.clock ShowSeconds -bool true
defaults write com.apple.menuextra.clock ShowDayOfWeek -bool true
defaults write com.apple.menuextra.clock ShowDate -int 1
defaults write com.apple.menuextra.clock DateFormat -string "EEE dd MMM HH:mm:ss"

# ControlCenter owns these menu-bar items on current macOS releases.
killall ControlCenter 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true
fi

###############################################################################
# Mouse                                                                       #
###############################################################################

if component_enabled MACOS_MOUSE; then
  # Disable mouse acceleration
  defaults write .GlobalPreferences com.apple.mouse.scaling -1
fi

###############################################################################
# Power / Sleep                                                               #
###############################################################################

# Sleep options (display, disk, and system) in minutes. MacBooks share the
# laptop policy; the Mac mini preserves system sleep disabled.
if component_enabled MACOS_POWER; then
if [[ "$SCRIPT_MACHINE_PROFILE" == "mac-mini" ]]; then
  # A headless Mac mini must restart after power restoration, remain awake, and
  # keep network wake/keepalive available for Tahoe's pre-boot SSH unlock.
  # These pmset values do not unlock FileVault. Planned one-restart bypasses
  # require an explicit operator-run `fdesetup authrestart`; unexpected boots
  # still require password authentication locally or over Tahoe's pre-boot SSH.
  sudo pmset -a \
    displaysleep 10 \
    disksleep 10 \
    sleep 0 \
    autorestart 1 \
    womp 1 \
    tcpkeepalive 1
else
  sudo pmset -a displaysleep 10 disksleep 10 sleep 20
fi
fi

###############################################################################
# Finder                                                                      #
###############################################################################

if component_enabled MACOS_FINDER; then
  # Show Finder path bar
  defaults write com.apple.finder ShowPathbar -bool true

# Show Finder status bar
defaults write com.apple.finder ShowStatusBar -bool true

# Show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show the ~/Library folder
chflags nohidden ~/Library

# Disable the warning when changing a file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Preserve the warning before emptying the Trash.

# Restart Finder to apply all changes
killall Finder 2>/dev/null || true
fi

###############################################################################
# Screenshots                                                                 #
###############################################################################

if component_enabled MACOS_SCREENSHOTS; then
  # Take screenshots as png (available: png, jpg, tiff, bmp, gif, pdf, none)
  defaults write com.apple.screencapture type png
fi

###############################################################################
# Touch ID for sudo                                                           #
###############################################################################

# Enable Touch ID authentication for sudo, including inside tmux. Keep Apple's
# update-owned /etc/pam.d/sudo unchanged and use its sudo_local include.
if component_enabled MACOS_TOUCH_ID; then
PAM_REATTACH_MODULE="$(brew --prefix)/lib/pam/pam_reattach.so"
SUDO_LOCAL_PATH="/etc/pam.d/sudo_local"

if [[ ! -f "$PAM_REATTACH_MODULE" ]]; then
  printf 'Required PAM module is missing: %s\n' "$PAM_REATTACH_MODULE" >&2
  exit 1
fi

if [[ ! -f "$SUDO_LOCAL_PATH" ]]; then
  pam_temp="$(mktemp)"
  trap 'rm -f "$pam_temp"' EXIT
  printf '%s\n' \
    '# sudo_local: local configuration which survives system updates' \
    "auth       optional       $PAM_REATTACH_MODULE ignore_ssh" \
    'auth       sufficient     pam_tid.so' \
    > "$pam_temp"
  sudo install -o root -g wheel -m 0444 "$pam_temp" "$SUDO_LOCAL_PATH"
  rm -f "$pam_temp"
  trap - EXIT
fi

if ! grep -Fq "$PAM_REATTACH_MODULE ignore_ssh" "$SUDO_LOCAL_PATH" \
  || ! grep -Eq '^auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so$' "$SUDO_LOCAL_PATH"; then
  printf 'Existing %s does not match the validated Touch ID configuration\n' "$SUDO_LOCAL_PATH" >&2
  exit 1
fi
fi
