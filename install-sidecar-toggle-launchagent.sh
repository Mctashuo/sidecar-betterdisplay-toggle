#!/bin/zsh

set -euo pipefail

SOURCE_DIR="${0:A:h}"
SCRIPT_SOURCE="${SOURCE_DIR}/sidecar-toggle.sh"
INSTALL_DIR="${HOME}/.local/bin"
SCRIPT_TARGET="${INSTALL_DIR}/sidecar-toggle.sh"
TRIGGER_FILE="${HOME}/.sidecar-toggle-trigger"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_TARGET="${PLIST_DIR}/local.sidecar-toggle.plist"
SYNC_PLIST_TARGET="${PLIST_DIR}/local.sidecar-display-sync.plist"
LABEL="local.sidecar-toggle"
SYNC_LABEL="local.sidecar-display-sync"
DOMAIN="gui/$(/usr/bin/id -u)"
SYNC_INTERVAL_SECONDS="10"

if [[ ! -f "$SCRIPT_SOURCE" ]]; then
  print -u2 "Missing ${SCRIPT_SOURCE}"
  exit 1
fi

/bin/mkdir -p "$INSTALL_DIR" "$PLIST_DIR" "${HOME}/Library/Logs"
/bin/cp "$SCRIPT_SOURCE" "$SCRIPT_TARGET"
/bin/chmod 755 "$SCRIPT_TARGET"
[[ -e "$TRIGGER_FILE" ]] || : > "$TRIGGER_FILE"

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

/bin/launchctl bootout "${DOMAIN}" "$PLIST_TARGET" >/dev/null 2>&1 || true
/bin/launchctl bootout "${DOMAIN}" "$SYNC_PLIST_TARGET" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "${DOMAIN}" "$PLIST_TARGET"
/bin/launchctl bootstrap "${DOMAIN}" "$SYNC_PLIST_TARGET"
/bin/launchctl enable "${DOMAIN}/${LABEL}"
/bin/launchctl enable "${DOMAIN}/${SYNC_LABEL}"

print "Installed ${SCRIPT_TARGET}"
print "Installed ${PLIST_TARGET}"
print "Installed ${SYNC_PLIST_TARGET}"
print "Trigger with:"
print "  touch ${TRIGGER_FILE}"
print ""
print "Useful logs:"
print "  ${HOME}/Library/Logs/sidecar-toggle.log"
print "  ${HOME}/Library/Logs/sidecar-toggle.launchd.err.log"
print "  ${HOME}/Library/Logs/sidecar-display-sync.launchd.err.log"
