#!/bin/zsh

set -u

LAUNCHER="${SIDECAR_TOGGLE_LAUNCHER:-${HOME}/.local/bin/SidecarLauncher}"
BETTERDISPLAY="${SIDECAR_TOGGLE_BETTERDISPLAY:-/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay}"
BETTERDISPLAY_VIRTUAL_TAG_ID="${SIDECAR_TOGGLE_VIRTUAL_TAG_ID:-16}"
SYSTEM_PROFILER="${SIDECAR_TOGGLE_SYSTEM_PROFILER:-/usr/sbin/system_profiler}"
IOREG="${SIDECAR_TOGGLE_IOREG:-/usr/sbin/ioreg}"
LOG_FILE="${SIDECAR_TOGGLE_LOG_FILE:-${HOME}/Library/Logs/sidecar-toggle.log}"
STATE_FILE="${SIDECAR_TOGGLE_STATE_FILE:-${HOME}/.sidecar-toggle-state}"
LOCK_DIR="${SIDECAR_TOGGLE_LOCK_DIR:-/tmp/sidecar-toggle.${UID}.lock}"
VIRTUAL_DISPLAY_SETTLE_SECONDS="${SIDECAR_TOGGLE_VIRTUAL_DISPLAY_SETTLE_SECONDS:-2}"
PREFERRED_DEVICES=(
  "Example iPad"
  "Example Tablet"
)

log() {
  mkdir -p "${LOG_FILE:h}"
  print -r -- "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

cleanup() {
  /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
}

write_state() {
  print -r -- "$1" > "$STATE_FILE"
}

clear_state() {
  /bin/rm -f "$STATE_FILE" 2>/dev/null || true
}

sidecar_was_active_with_external_display() {
  [[ -f "$STATE_FILE" ]] && [[ "$(<"$STATE_FILE")" == "external-sidecar" ]]
}

is_sidecar_connected() {
  "$SYSTEM_PROFILER" SPDisplaysDataType | /usr/bin/awk '
    /^        Sidecar Display:/ { inside = 1; next }
    /^        [^ ].*:/ { inside = 0 }
    inside && /Virtual Device: Yes/ { found = 1 }
    END { exit !found }
  '
}

has_external_display() {
  has_external_display_from_system_profiler || has_external_display_from_ioreg
}

has_external_display_from_system_profiler() {
  "$SYSTEM_PROFILER" SPDisplaysDataType | /usr/bin/awk '
    function finish_display() {
      if (inside && online && external && !virtual && !airplay && !betterdisplay_virtual && !internal) {
        found = 1
      }
      inside = 0
      online = 0
      external = 0
      virtual = 0
      airplay = 0
      betterdisplay_virtual = 0
      internal = 0
    }

    /^      Displays:$/ {
      in_displays = 1
      next
    }

    in_displays && /^        [^ ].*:$/ {
      finish_display()
      inside = 1
      external = 1
      online = 0
      name = $0
      sub(/^[[:space:]]*/, "", name)
      sub(/:$/, "", name)
      if (name ~ /^(虚拟|BetterDisplay|Sidecar Display)/) {
        betterdisplay_virtual = 1
      }
      if (name ~ /(Built-in|Built-In|内建)/) {
        internal = 1
      }
      next
    }

    in_displays && /^[[:space:]]{4}[^[:space:]].*:$/ {
      finish_display()
      in_displays = 0
    }

    /^[[:space:]]{4,}[^[:space:]].*:$/ && !in_displays {
      finish_display()
      inside = 1
      next
    }

    inside && /Online: Yes/ { online = 1 }
    inside && /Display Type: External/ { external = 1; online = 1 }
    inside && /Virtual Device: Yes/ { virtual = 1 }
    inside && /Connection Type: AirPlay/ { airplay = 1 }
    inside && /Connection Type: (Internal|Built-In|Built-in)/ { internal = 1 }

    END {
      finish_display()
      exit !found
    }
  '
}

has_external_display_from_ioreg() {
  "$IOREG" -lw0 -r -c IOMobileFramebuffer | /usr/bin/awk '
    function finish_display() {
      if (inside && external && display_attributes && physical_transport) {
        found = 1
      }
      inside = 0
      external = 0
      display_attributes = 0
      physical_transport = 0
    }

    /^\+-o IOMobileFramebuffer/ {
      finish_display()
      inside = 1
      next
    }

    inside && /"external" = Yes/ { external = 1 }
    inside && /"DisplayAttributes"/ { display_attributes = 1 }
    inside && /"Transport" = .*"(DP|HDMI|DVI|VGA|Thunderbolt)"/ { physical_transport = 1 }

    END {
      finish_display()
      exit !found
    }
  '
}

set_virtual_display_connection() {
  local state="$1"

  if [[ ! -x "$BETTERDISPLAY" ]]; then
    log "BetterDisplay is not executable: ${BETTERDISPLAY}"
    return 1
  fi

  log "Setting BetterDisplay virtual display tagID=${BETTERDISPLAY_VIRTUAL_TAG_ID} connected=${state}"
  "$BETTERDISPLAY" set --tagID="$BETTERDISPLAY_VIRTUAL_TAG_ID" --connected="$state" >> "$LOG_FILE" 2>&1
}

prepare_virtual_display_for_sidecar() {
  if has_external_display; then
    log "External display detected; disconnecting BetterDisplay virtual display before Sidecar connect"
    set_virtual_display_connection off
    return $?
  fi

  log "No external display detected; connecting BetterDisplay virtual display before Sidecar connect"
  set_virtual_display_connection on || return $?
  /bin/sleep "$VIRTUAL_DISPLAY_SETTLE_SECONDS"
}

sync_virtual_display_for_external_monitor() {
  if has_external_display; then
    if is_sidecar_connected; then
      write_state "external-sidecar"
      log "External display and Sidecar detected during sync; remembering Sidecar state"
    else
      clear_state
      log "External display detected during sync; Sidecar is not connected"
    fi

    log "External display detected during sync; disconnecting BetterDisplay virtual display"
    set_virtual_display_connection off
    return $?
  fi

  if sidecar_was_active_with_external_display; then
    log "External display disappeared after Sidecar was active; reconnecting virtual display and restarting Sidecar"
    set_virtual_display_connection on || return $?
    /bin/sleep "$VIRTUAL_DISPLAY_SETTLE_SECONDS"

    if is_sidecar_connected; then
      disconnect_preferred_device || return $?
      /bin/sleep "$VIRTUAL_DISPLAY_SETTLE_SECONDS"
    fi

    connect_preferred_device || return $?
    write_state "recovered"
    return 0
  fi

  log "No external display detected during sync; leaving BetterDisplay virtual display unchanged"
  return 0
}

disconnect_preferred_device() {
  local device

  for device in "${PREFERRED_DEVICES[@]}"; do
    log "Trying disconnect: ${device}"
    if "$LAUNCHER" disconnect "$device" >> "$LOG_FILE" 2>&1; then
      log "Disconnected: ${device}"
      return 0
    fi
  done

  log "Sidecar display is connected, but preferred-device disconnect failed"
  return 1
}

connect_preferred_device() {
  local reachable device

  if ! reachable="$("$LAUNCHER" devices list 2>&1)"; then
    log "Failed to list reachable Sidecar devices: ${reachable}"
    return 1
  fi

  for device in "${PREFERRED_DEVICES[@]}"; do
    if print -r -- "$reachable" | /usr/bin/grep -Fxq -- "$device"; then
      log "Trying connect: ${device}"
      if "$LAUNCHER" connect "$device" >> "$LOG_FILE" 2>&1; then
        log "Connected: ${device}"
        return 0
      fi

      log "Connect failed: ${device}"
      return 1
    fi
  done

  log "No preferred Sidecar device is reachable. Reachable devices: ${reachable}"
  return 2
}

main() {
  if ! /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
    log "Another sidecar-toggle instance is already running"
    return 0
  fi
  trap cleanup EXIT INT TERM

  if [[ ! -x "$LAUNCHER" ]]; then
    log "SidecarLauncher is not executable: ${LAUNCHER}"
    return 1
  fi

  log "Toggle requested"

  if is_sidecar_connected; then
    clear_state
    disconnect_preferred_device
    return $?
  fi

  prepare_virtual_display_for_sidecar || return $?
  connect_preferred_device || return $?

  if has_external_display; then
    write_state "external-sidecar"
  else
    write_state "recovered"
  fi
}

sync_main() {
  if ! /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
    log "Another sidecar-toggle instance is already running"
    return 0
  fi
  trap cleanup EXIT INT TERM

  log "Display sync requested"
  sync_virtual_display_for_external_monitor
}

case "${1:-toggle}" in
  toggle)
    main "$@"
    ;;
  sync)
    sync_main
    ;;
  *)
    log "Unknown command: ${1}"
    print -u2 -- "Usage: $0 [toggle|sync]"
    exit 64
    ;;
esac
