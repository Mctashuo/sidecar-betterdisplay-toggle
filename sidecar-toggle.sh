#!/bin/zsh

set -u

LAUNCHER="${SIDECAR_TOGGLE_LAUNCHER:-${HOME}/.local/bin/SidecarLauncher}"
BETTERDISPLAY="${SIDECAR_TOGGLE_BETTERDISPLAY:-/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay}"
BETTERDISPLAY_VIRTUAL_TAG_ID="${SIDECAR_TOGGLE_VIRTUAL_TAG_ID:-16}"
SYSTEM_PROFILER="${SIDECAR_TOGGLE_SYSTEM_PROFILER:-/usr/sbin/system_profiler}"
IOREG="${SIDECAR_TOGGLE_IOREG:-/usr/sbin/ioreg}"
LOG_FILE="${SIDECAR_TOGGLE_LOG_FILE:-${HOME}/Library/Logs/sidecar-toggle.log}"
STATE_FILE="${SIDECAR_TOGGLE_STATE_FILE:-${HOME}/.sidecar-toggle-state}"
DEVICES_FILE="${SIDECAR_TOGGLE_DEVICES_FILE:-${HOME}/.config/sidecar-toggle/devices.txt}"
TRIGGER_FILE="${SIDECAR_TOGGLE_TRIGGER_FILE:-${HOME}/.sidecar-toggle-trigger}"
LOCK_DIR="${SIDECAR_TOGGLE_LOCK_DIR:-/tmp/sidecar-toggle.${UID}.lock}"
VIRTUAL_DISPLAY_SETTLE_SECONDS="${SIDECAR_TOGGLE_VIRTUAL_DISPLAY_SETTLE_SECONDS:-2}"
LOCK_WAIT_SECONDS="${SIDECAR_TOGGLE_LOCK_WAIT_SECONDS:-8}"
PREFERRED_DEVICES=(
  "Example iPad"
  "Example Tablet"
)

log() {
  mkdir -p "${LOG_FILE:h}"
  print -r -- "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

load_preferred_devices() {
  local line
  local configured_devices=()

  if [[ -f "$DEVICES_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -z "$line" || "$line" == \#* ]] && continue
      configured_devices+=("$line")
    done < "$DEVICES_FILE"
  fi

  if (( ${#configured_devices[@]} > 0 )); then
    PREFERRED_DEVICES=("${configured_devices[@]}")
  fi
}

prioritize_device() {
  local requested_device="$1"
  local device
  local reordered_devices=()

  [[ -z "$requested_device" ]] && return 0

  reordered_devices+=("$requested_device")
  for device in "${PREFERRED_DEVICES[@]}"; do
    [[ "$device" == "$requested_device" ]] && continue
    reordered_devices+=("$device")
  done

  PREFERRED_DEVICES=("${reordered_devices[@]}")
}

load_trigger_device_priority() {
  local line

  [[ -f "$TRIGGER_FILE" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    prioritize_device "$line"
    log "Prioritizing Sidecar device from trigger file: ${line}"
    return 0
  done < "$TRIGGER_FILE"
}

cleanup() {
  /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
}

acquire_lock() {
  local wait_seconds="$1"
  local waited=0

  while ! /bin/mkdir "$LOCK_DIR" 2>/dev/null; do
    if (( waited >= wait_seconds )); then
      log "Another sidecar-toggle instance is already running"
      return 1
    fi

    log "Another sidecar-toggle instance is already running; waiting for lock"
    /bin/sleep 1
    waited=$((waited + 1))
  done
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
  [[ "$(probe_external_display)" == "present" ]]
}

finish_external_display_probe() {
  local state="$1"
  local reason="$2"

  log "$reason"
  print -r -- "$state"
}

probe_external_display() {
  local probe_status

  ioreg_has_display_data
  probe_status=$?
  if (( probe_status == 2 )); then
    finish_external_display_probe "unknown" "External display probe unknown; ioreg probe failed"
    return 0
  fi

  if (( probe_status == 0 )); then
    has_external_display_from_ioreg
    probe_status=$?
    if (( probe_status == 0 )); then
      finish_external_display_probe "present" "External display detected from ioreg active timing"
      return 0
    fi
    if (( probe_status == 2 )); then
      finish_external_display_probe "unknown" "External display probe unknown; ioreg active timing probe failed"
      return 0
    fi

    has_external_display_from_betterdisplay
    probe_status=$?
    if (( probe_status == 0 )); then
      finish_external_display_probe "present" "External display detected from BetterDisplay DDC"
      return 0
    fi
    if (( probe_status == 2 )); then
      finish_external_display_probe "unknown" "External display probe unknown; BetterDisplay DDC probe failed"
      return 0
    fi

    finish_external_display_probe "absent" "No external display detected; ioreg stale and BetterDisplay DDC unavailable"
    return 0
  fi

  has_external_display_from_system_profiler
  probe_status=$?
  if (( probe_status == 0 )); then
    finish_external_display_probe "present" "External display detected from system_profiler"
  elif (( probe_status == 2 )); then
    finish_external_display_probe "unknown" "External display probe unknown; system_profiler probe failed"
  else
    finish_external_display_probe "absent" "No external display detected from system_profiler"
  fi
}

ioreg_has_display_data() {
  local output

  if ! output="$("$IOREG" -lw0 -r -c IOMobileFramebuffer 2>/dev/null)"; then
    return 2
  fi

  print -r -- "$output" | /usr/bin/awk '
    /^\+-o IOMobileFramebuffer/ { found = 1 }
    END { exit !found }
  '
}

has_external_display_from_system_profiler() {
  local output

  if ! output="$("$SYSTEM_PROFILER" SPDisplaysDataType 2>/dev/null)"; then
    return 2
  fi

  print -r -- "$output" | /usr/bin/awk '
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

has_external_display_from_betterdisplay() {
  local identifiers tag_id

  [[ -x "$BETTERDISPLAY" ]] || return 1

  if ! identifiers="$("$BETTERDISPLAY" get --identifiers 2>/dev/null)"; then
    return 2
  fi

  for tag_id in ${(f)"$(print -r -- "$identifiers" | /usr/bin/awk '
    BEGIN { RS = "\\n\\},\\{" }
    /"deviceType"[[:space:]]*:[[:space:]]*"Display"/ &&
    /"registryLocation"[[:space:]]*:[[:space:]]*".*dispext[0-9]/ {
      if (match($0, /"tagID"[[:space:]]*:[[:space:]]*"[0-9]+"/)) {
        tag = substr($0, RSTART, RLENGTH)
        gsub(/[^0-9]/, "", tag)
        print tag
      }
    }
  ')"}; do
    [[ -z "$tag_id" ]] && continue
    if "$BETTERDISPLAY" get --tagID="$tag_id" --ddcCapabilitiesString >/dev/null 2>&1; then
      return 0
    fi
  done

  return 1
}

has_external_display_from_ioreg() {
  local output

  if ! output="$("$IOREG" -lw0 -r -c IOMobileFramebuffer 2>/dev/null)"; then
    return 2
  fi

  print -r -- "$output" | /usr/bin/awk '
    function finish_display() {
      if (inside && external && display_attributes && physical_transport && active_timing) {
        found = 1
      }
      inside = 0
      external = 0
      display_attributes = 0
      physical_transport = 0
      active_timing = 0
    }

    /^\+-o IOMobileFramebuffer/ {
      finish_display()
      inside = 1
      next
    }

    inside && /"external" = Yes/ { external = 1 }
    inside && /"DisplayAttributes"/ { display_attributes = 1 }
    inside && /"Transport" = .*"(DP|HDMI|DVI|VGA|Thunderbolt)"/ { physical_transport = 1 }
    inside && /"(DisplayClock|PixelClock)" = [1-9][0-9]*/ { active_timing = 1 }

    END {
      finish_display()
      exit !found
    }
  '
}

is_idempotent_betterdisplay_set_failure() {
  local output="$1"

  [[ "$output" == *"Failed."* ]]
}

set_virtual_display_connection() {
  local state="$1"
  local output exit_status

  if [[ ! -x "$BETTERDISPLAY" ]]; then
    log "BetterDisplay is not executable: ${BETTERDISPLAY}"
    return 1
  fi

  log "Setting BetterDisplay virtual display tagID=${BETTERDISPLAY_VIRTUAL_TAG_ID} connected=${state}"
  output="$("$BETTERDISPLAY" set --tagID="$BETTERDISPLAY_VIRTUAL_TAG_ID" --connected="$state" 2>&1)"
  exit_status=$?

  [[ -n "$output" ]] && print -r -- "$output" >> "$LOG_FILE"

  if (( exit_status == 0 )); then
    return 0
  fi

  if is_idempotent_betterdisplay_set_failure "$output"; then
    log "BetterDisplay virtual display already connected=${state}; treating set failure as non-fatal"
    return 0
  fi

  return "$exit_status"
}

prepare_virtual_display_for_sidecar() {
  local external_display_state

  external_display_state="$(probe_external_display)"

  case "$external_display_state" in
    present)
      log "External display detected; disconnecting BetterDisplay virtual display before Sidecar connect"
      set_virtual_display_connection off
      return $?
      ;;
    absent)
      log "No external display detected; connecting BetterDisplay virtual display before Sidecar connect"
      set_virtual_display_connection on || return $?
      /bin/sleep "$VIRTUAL_DISPLAY_SETTLE_SECONDS"
      ;;
    unknown)
      log "External display probe unknown; leaving virtual display unchanged"
      ;;
  esac

  return 0
}

sync_virtual_display_for_external_monitor() {
  local external_display_state

  external_display_state="$(probe_external_display)"

  if [[ "$external_display_state" == "unknown" ]]; then
    log "External display probe unknown; leaving virtual display unchanged"
    return 0
  fi

  if [[ "$external_display_state" == "present" ]]; then
    if is_sidecar_connected; then
      write_state "external-sidecar"
      log "External display and Sidecar detected during sync; remembering Sidecar state"
    else
      if sidecar_was_active_with_external_display; then
        log "External display detected during sync; Sidecar probe missed, preserving remembered Sidecar state"
      else
        clear_state
        log "External display detected during sync; Sidecar is not connected"
      fi
    fi

    log "External display detected during sync; disconnecting BetterDisplay virtual display"
    set_virtual_display_connection off
    return $?
  fi

  log "No external display detected during sync; connecting BetterDisplay virtual display"
  set_virtual_display_connection on || return $?

  if sidecar_was_active_with_external_display; then
    log "External display disappeared after Sidecar was active; reconnecting virtual display and restarting Sidecar"
    /bin/sleep "$VIRTUAL_DISPLAY_SETTLE_SECONDS"

    if is_sidecar_connected; then
      disconnect_preferred_device || return $?
      /bin/sleep "$VIRTUAL_DISPLAY_SETTLE_SECONDS"
    fi

    connect_preferred_device || return $?
    write_state "recovered"
    return 0
  fi

  log "No external display detected during sync; Sidecar was not remembered active, leaving Sidecar unchanged"
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
  load_preferred_devices
  load_trigger_device_priority

  if ! acquire_lock "$LOCK_WAIT_SECONDS"; then
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

  case "$(probe_external_display)" in
    present)
      write_state "external-sidecar"
      ;;
    absent)
      write_state "recovered"
      ;;
    unknown)
      log "External display probe unknown; leaving Sidecar recovery state unchanged"
      ;;
  esac
}

sync_main() {
  load_preferred_devices

  if ! acquire_lock 0; then
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
