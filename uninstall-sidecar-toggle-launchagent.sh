#!/bin/zsh

set -euo pipefail

LABEL="local.sidecar-toggle"
SYNC_LABEL="local.sidecar-display-sync"
DOMAIN="gui/$(/usr/bin/id -u)"
PLIST_TARGET="${HOME}/Library/LaunchAgents/${LABEL}.plist"
SYNC_PLIST_TARGET="${HOME}/Library/LaunchAgents/${SYNC_LABEL}.plist"

/bin/launchctl bootout "${DOMAIN}" "$PLIST_TARGET" >/dev/null 2>&1 || true
/bin/launchctl bootout "${DOMAIN}" "$SYNC_PLIST_TARGET" >/dev/null 2>&1 || true
/bin/rm -f "$PLIST_TARGET"
/bin/rm -f "$SYNC_PLIST_TARGET"

print "Uninstalled ${LABEL}"
print "Uninstalled ${SYNC_LABEL}"
