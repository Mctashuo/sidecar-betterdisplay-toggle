#!/bin/zsh

set -euo pipefail

SOURCE_DIR="${0:A:h}"
SCRIPT_SOURCE="${SOURCE_DIR}/sidecar-toggle.sh"
INSTALL_DIR="${HOME}/.local/bin"
SCRIPT_TARGET="${INSTALL_DIR}/sidecar-toggle.sh"
TRIGGER_FILE="${HOME}/.sidecar-toggle-trigger"
CONFIG_DIR="${HOME}/.config/sidecar-toggle"
DEVICES_FILE="${CONFIG_DIR}/devices.txt"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_TARGET="${PLIST_DIR}/local.sidecar-toggle.plist"
SYNC_PLIST_TARGET="${PLIST_DIR}/local.sidecar-display-sync.plist"
LABEL="local.sidecar-toggle"
SYNC_LABEL="local.sidecar-display-sync"
DOMAIN="gui/$(/usr/bin/id -u)"
SYNC_INTERVAL_SECONDS="10"
LAUNCHER="${SIDECAR_TOGGLE_LAUNCHER:-${HOME}/.local/bin/SidecarLauncher}"
LAUNCHCTL="${SIDECAR_TOGGLE_LAUNCHCTL:-/bin/launchctl}"

if [[ ! -f "$SCRIPT_SOURCE" ]]; then
  print -u2 "Missing ${SCRIPT_SOURCE}"
  exit 1
fi

if [[ ! -x "$LAUNCHER" ]]; then
  print -u2 "Missing executable SidecarLauncher: ${LAUNCHER}"
  exit 1
fi

device_output="$("$LAUNCHER" devices list)"
devices=("${(@f)device_output}")
devices=("${(@)devices:#}")

if (( ${#devices[@]} == 0 )); then
  print -u2 "No connectable Sidecar devices found. Make sure your iPad is visible, then run the installer again."
  exit 1
fi

print "Available Sidecar devices:"
for i in {1..${#devices[@]}}; do
  print "  ${i}) ${devices[$i]}"
done

print ""
print -n "Enter device numbers in connection priority order (for example: 2 1): "
read -r selection

selected_devices=()
for number in ${(z)selection}; do
  if [[ ! "$number" == <-> ]] || (( number < 1 || number > ${#devices[@]} )); then
    print -u2 "Invalid device number: ${number}"
    exit 1
  fi
  selected_devices+=("${devices[$number]}")
done

if (( ${#selected_devices[@]} == 0 )); then
  print -u2 "No devices selected."
  exit 1
fi

/bin/mkdir -p "$INSTALL_DIR" "$PLIST_DIR" "$CONFIG_DIR" "${HOME}/Library/Logs"
/bin/cp "$SCRIPT_SOURCE" "$SCRIPT_TARGET"
/bin/chmod 755 "$SCRIPT_TARGET"
[[ -e "$TRIGGER_FILE" ]] || : > "$TRIGGER_FILE"
: > "$DEVICES_FILE"
for device in "${selected_devices[@]}"; do
  print -r -- "$device" >> "$DEVICES_FILE"
done
/bin/chmod 600 "$DEVICES_FILE"

/bin/cat > "$PLIST_TARGET" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${SCRIPT_TARGET}</string>
    <string>toggle</string>
  </array>

  <key>WatchPaths</key>
  <array>
    <string>${TRIGGER_FILE}</string>
  </array>

  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/sidecar-toggle.launchd.out.log</string>

  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/sidecar-toggle.launchd.err.log</string>
</dict>
</plist>
PLIST

/bin/cat > "$SYNC_PLIST_TARGET" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${SYNC_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${SCRIPT_TARGET}</string>
    <string>sync</string>
  </array>

  <key>StartInterval</key>
  <integer>${SYNC_INTERVAL_SECONDS}</integer>

  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/sidecar-display-sync.launchd.out.log</string>

  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/sidecar-display-sync.launchd.err.log</string>
</dict>
</plist>
PLIST

"$LAUNCHCTL" bootout "${DOMAIN}" "$PLIST_TARGET" >/dev/null 2>&1 || true
"$LAUNCHCTL" bootout "${DOMAIN}" "$SYNC_PLIST_TARGET" >/dev/null 2>&1 || true
: > "${HOME}/Library/Logs/sidecar-toggle.launchd.out.log" 2>/dev/null || true
: > "${HOME}/Library/Logs/sidecar-toggle.launchd.err.log" 2>/dev/null || true
: > "${HOME}/Library/Logs/sidecar-display-sync.launchd.out.log" 2>/dev/null || true
: > "${HOME}/Library/Logs/sidecar-display-sync.launchd.err.log" 2>/dev/null || true
"$LAUNCHCTL" bootstrap "${DOMAIN}" "$PLIST_TARGET"
"$LAUNCHCTL" bootstrap "${DOMAIN}" "$SYNC_PLIST_TARGET"
"$LAUNCHCTL" enable "${DOMAIN}/${LABEL}"
"$LAUNCHCTL" enable "${DOMAIN}/${SYNC_LABEL}"

print "Installed ${SCRIPT_TARGET}"
print "Installed ${PLIST_TARGET}"
print "Installed ${SYNC_PLIST_TARGET}"
print "Configured device priority in ${DEVICES_FILE}"
print "Trigger with:"
print -r "  printf '%s\n' '<iPad device name>' > ${TRIGGER_FILE}"
print ""
print "Useful logs:"
print "  ${HOME}/Library/Logs/sidecar-toggle.log"
print "  ${HOME}/Library/Logs/sidecar-toggle.launchd.err.log"
print "  ${HOME}/Library/Logs/sidecar-display-sync.launchd.err.log"
