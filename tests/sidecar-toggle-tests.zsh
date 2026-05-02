#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SCRIPT="${ROOT_DIR}/sidecar-toggle.sh"

fail() {
  print -u2 -- "FAIL: $*"
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"

  /usr/bin/grep -Fq -- "$expected" "$file" || {
    print -u2 -- "Expected to find: $expected"
    print -u2 -- "Actual contents:"
    /bin/cat "$file" >&2
    exit 1
  }
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"

  [[ -f "$file" ]] || return 0

  if /usr/bin/grep -Fq -- "$unexpected" "$file"; then
    print -u2 -- "Did not expect to find: $unexpected"
    print -u2 -- "Actual contents:"
    /bin/cat "$file" >&2
    exit 1
  fi
}

make_fixture() {
  local dir="$1"
  local external="$2"

  /bin/mkdir -p "$dir/bin" "$dir/home/.local/bin" "$dir/home/Library/Logs"

  /bin/cat > "$dir/bin/system_profiler" <<'EOF'
#!/bin/zsh
if [[ "${FAKE_EXTERNAL_DISPLAY:-0}" == "system_profiler_gpu_only" || "${FAKE_EXTERNAL_DISPLAY:-0}" == "powered_off_external" ]]; then
  print -- "Graphics/Displays:"
  print -- ""
  print -- "    Apple M4:"
  print -- ""
  print -- "      Chipset Model: Apple M4"
elif [[ "${FAKE_EXTERNAL_DISPLAY:-0}" == "stale_system_profiler_powered_off" ]]; then
  print -- "Graphics/Displays:"
  print -- ""
  print -- "    Apple M4:"
  print -- ""
  print -- "      Chipset Model: Apple M4"
  print -- "      Type: GPU"
  print -- "      Bus: Built-In"
  print -- "      Displays:"
  print -- "        MAG 272U X24:"
  print -- "          Resolution: 1600 x 1200 (UXGA - Ultra eXtended Graphics Array)"
  print -- "          UI Looks like: 800 x 600 @ 240.00Hz"
  print -- "          Mirror: On"
  print -- "          Mirror Status: Hardware Mirror"
  print -- "          Online: Yes"
  print -- "          Rotation: Supported"
  print -- "        Sidecar Display:"
  print -- "          Resolution: 2732 x 2048"
  print -- "          UI Looks like: 1366 x 1024 @ 60.00Hz"
  print -- "          Framebuffer Depth: 24-Bit Color (ARGB8888)"
  print -- "          Main Display: Yes"
  print -- "          Mirror: On"
  print -- "          Mirror Status: Master Mirror"
  print -- "          Connection Type: AirPlay"
  print -- "          Virtual Device: Yes"
elif [[ "${FAKE_EXTERNAL_DISPLAY:-0}" == "nested_displays" ]]; then
  print -- "Graphics/Displays:"
  print -- ""
  print -- "    Apple M4:"
  print -- ""
  print -- "      Chipset Model: Apple M4"
  print -- "      Type: GPU"
  print -- "      Bus: Built-In"
  print -- "      Displays:"
  print -- "        MAG 272U X24:"
  print -- "          Resolution: 3840 x 2160 (2160p/4K UHD 1 - Ultra High Definition)"
  print -- "          UI Looks like: 1920 x 1080 @ 240.00Hz"
  print -- "          Main Display: Yes"
  print -- "          Mirror: On"
  print -- "          Mirror Status: Master Mirror"
  print -- "          Online: Yes"
  print -- "          Rotation: Supported"
  print -- "        虚拟 16:12:"
  print -- "          Resolution: 3840 x 2880"
  print -- "          UI Looks like: 1920 x 1440 @ 60.00Hz"
  print -- "          Mirror: Off"
  print -- "          Online: Yes"
  print -- "          Rotation: Supported"
  print -- "        Sidecar Display:"
  print -- "          Resolution: 3840 x 2160 (2160p/4K UHD 1 - Ultra High Definition)"
  print -- "          UI Looks like: 1920 x 1080 @ 60.00Hz"
  print -- "          Framebuffer Depth: 24-Bit Color (ARGB8888)"
  print -- "          Mirror: On"
  print -- "          Mirror Status: Hardware Mirror"
  print -- "          Connection Type: AirPlay"
  print -- "          Virtual Device: Yes"
elif [[ "${FAKE_EXTERNAL_DISPLAY:-0}" == "sidecar_only" ]]; then
  print -- "Graphics/Displays:"
  print -- ""
  print -- "    Apple M4:"
  print -- ""
  print -- "      Chipset Model: Apple M4"
  print -- "      Type: GPU"
  print -- "      Displays:"
  print -- "        虚拟 16:12:"
  print -- "          Resolution: 3840 x 2880"
  print -- "          UI Looks like: 1920 x 1440 @ 60.00Hz"
  print -- "          Mirror: Off"
  print -- "          Online: Yes"
  print -- "          Rotation: Supported"
  print -- "        Sidecar Display:"
  print -- "          Resolution: 3840 x 2160 (2160p/4K UHD 1 - Ultra High Definition)"
  print -- "          UI Looks like: 1920 x 1080 @ 60.00Hz"
  print -- "          Framebuffer Depth: 24-Bit Color (ARGB8888)"
  print -- "          Mirror: On"
  print -- "          Mirror Status: Hardware Mirror"
  print -- "          Connection Type: AirPlay"
  print -- "          Virtual Device: Yes"
elif [[ "${FAKE_EXTERNAL_DISPLAY:-0}" == "1" ]]; then
  print -- "Displays:"
  print -- "    Built-in Display:"
  print -- "      Display Type: Built-in"
  print -- "    DELL U2720Q:"
  print -- "      Display Type: External"
elif [[ "${FAKE_EXTERNAL_DISPLAY:-0}" == "virtual" ]]; then
  print -- "Displays:"
  print -- "    Built-in Display:"
  print -- "      Display Type: Built-in"
  print -- "    BetterDisplay Virtual:"
  print -- "      Display Type: External"
  print -- "      Virtual Device: Yes"
else
  print -- "Displays:"
  print -- "    Built-in Display:"
  print -- "      Display Type: Built-in"
fi
EOF

  /bin/cat > "$dir/bin/ioreg" <<'EOF'
#!/bin/zsh
if [[ "${FAKE_EXTERNAL_DISPLAY:-0}" == "system_profiler_gpu_only" ]]; then
  print -- '+-o IOMobileFramebufferShim  <class IOMobileFramebufferShim>'
  print -- '  | {'
  print -- '  |   "IONameMatched" = "dispext0,t8132"'
  print -- '  |   "DisplayAttributes" = {"ProductAttributes"={"ManufacturerID"="MSI","ProductName"="MAG 272U X24","ProductID"=23767}}'
  print -- '  |   "Transport" = {"Upstream"="DP","Downstream"="DP"}'
  print -- '  |   "DisplayClock" = 346612512'
  print -- '  |   "PixelClock" = 300000000'
  print -- '  |   "external" = Yes'
  print -- '  | }'
elif [[ "${FAKE_EXTERNAL_DISPLAY:-0}" == "powered_off_external" ]]; then
  print -- '+-o IOMobileFramebufferShim  <class IOMobileFramebufferShim>'
  print -- '  | {'
  print -- '  |   "IONameMatched" = "dispext0,t8132"'
  print -- '  |   "DisplayAttributes" = {"ProductAttributes"={"ManufacturerID"="MSI","ProductName"="MAG 272U X24","ProductID"=23767}}'
  print -- '  |   "Transport" = {"Upstream"="DP","Downstream"="DP"}'
  print -- '  |   "DisplayClock" = 0'
  print -- '  |   "PixelClock" = 0'
  print -- '  |   "external" = Yes'
  print -- '  | }'
elif [[ "${FAKE_EXTERNAL_DISPLAY:-0}" == "stale_system_profiler_powered_off" ]]; then
  print -- '+-o IOMobileFramebufferShim  <class IOMobileFramebufferShim>'
  print -- '  | {'
  print -- '  |   "IONameMatched" = "dispext0,t8132"'
  print -- '  |   "DisplayAttributes" = {"ProductAttributes"={"ManufacturerID"="MSI","ProductName"="MAG 272U X24","ProductID"=23767}}'
  print -- '  |   "Transport" = {"Upstream"="DP","Downstream"="DP"}'
  print -- '  |   "DisplayClock" = 0'
  print -- '  |   "PixelClock" = 0'
  print -- '  |   "external" = Yes'
  print -- '  | }'
elif [[ "${FAKE_EXTERNAL_DISPLAY:-0}" == "betterdisplay_physical_on_ioreg_inactive" ]]; then
  print -- '+-o IOMobileFramebufferShim  <class IOMobileFramebufferShim>'
  print -- '  | {'
  print -- '  |   "IONameMatched" = "dispext0,t8132"'
  print -- '  |   "DisplayAttributes" = {"ProductAttributes"={"ManufacturerID"="MSI","ProductName"="MAG 272U X24","ProductID"=23767}}'
  print -- '  |   "Transport" = {"Upstream"="DP","Downstream"="DP"}'
  print -- '  |   "DisplayClock" = 0'
  print -- '  |   "PixelClock" = 0'
  print -- '  |   "external" = Yes'
  print -- '  | }'
fi
EOF

  /bin/cat > "$dir/bin/BetterDisplay" <<'EOF'
#!/bin/zsh
print -r -- "$*" >> "${FAKE_BETTERDISPLAY_LOG}"

if [[ "$1" == "get" && "$2" == "--identifiers" && "${FAKE_EXTERNAL_DISPLAY:-0}" == "betterdisplay_physical_on_ioreg_inactive" ]]; then
  print -- '{'
  print -- '  "deviceType" : "Display",'
  print -- '  "name" : "MAG 272U X24",'
  print -- '  "registryLocation" : "IOService:/AppleARMPE/arm-io@10F00000/AppleH16GFamilyIO/dispext0@84000000/IOMobileFramebufferShim",'
  print -- '  "tagID" : "3"'
  print -- '},{'
  print -- '  "deviceType" : "VirtualScreen",'
  print -- '  "name" : "虚拟 16:12",'
  print -- '  "tagID" : "15",'
  print -- '  "tagID (Display)" : "16"'
  print -- '}'
elif [[ "$1" == "get" && "$2" == "--tagID=3" && "$3" == "--ddcCapabilitiesString" && "${FAKE_EXTERNAL_DISPLAY:-0}" == "betterdisplay_physical_on_ioreg_inactive" ]]; then
  print -- '(prot(monitor)type(lcd)model(FALCON)vcp(10))'
fi
EOF

  /bin/cat > "$dir/home/.local/bin/SidecarLauncher" <<'EOF'
#!/bin/zsh
print -r -- "$*" >> "${FAKE_LAUNCHER_LOG}"

if [[ "$1" == "devices" && "$2" == "list" ]]; then
  print -- "Example iPad"
  print -- "Backup iPad"
  print -- "Primary iPad"
fi
EOF

  /bin/chmod 755 "$dir/bin/system_profiler" "$dir/bin/ioreg" "$dir/bin/BetterDisplay" "$dir/home/.local/bin/SidecarLauncher"
  print -r -- "$external" > "$dir/external"
}

run_script() {
  local dir="$1"
  shift

  FAKE_EXTERNAL_DISPLAY="$(<"$dir/external")" \
  FAKE_BETTERDISPLAY_LOG="$dir/betterdisplay.log" \
  FAKE_LAUNCHER_LOG="$dir/launcher.log" \
  HOME="$dir/home" \
  SIDECAR_TOGGLE_SYSTEM_PROFILER="$dir/bin/system_profiler" \
  SIDECAR_TOGGLE_IOREG="$dir/bin/ioreg" \
  SIDECAR_TOGGLE_BETTERDISPLAY="$dir/bin/BetterDisplay" \
  SIDECAR_TOGGLE_VIRTUAL_TAG_ID="16" \
  SIDECAR_TOGGLE_STATE_FILE="$dir/state" \
  SIDECAR_TOGGLE_DEVICES_FILE="$dir/devices.txt" \
  SIDECAR_TOGGLE_TRIGGER_FILE="$dir/trigger" \
  SIDECAR_TOGGLE_LOCK_DIR="$dir/lock" \
  SIDECAR_TOGGLE_VIRTUAL_DISPLAY_SETTLE_SECONDS="0" \
  "$SCRIPT" "$@"
}

test_toggle_connects_virtual_display_before_sidecar_when_no_external_display() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" 0

  run_script "$dir" toggle

  assert_contains "$dir/betterdisplay.log" "set --tagID=16 --connected=on"
  assert_contains "$dir/launcher.log" "connect Example iPad"
}

test_toggle_disconnects_virtual_display_before_sidecar_when_external_display_exists() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" 1

  run_script "$dir" toggle

  assert_contains "$dir/betterdisplay.log" "set --tagID=16 --connected=off"
  assert_contains "$dir/launcher.log" "connect Example iPad"
}

test_toggle_uses_private_device_config_priority() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" 0
  /bin/cat > "$dir/devices.txt" <<'EOF'
Backup iPad
Primary iPad
EOF

  run_script "$dir" toggle

  assert_contains "$dir/launcher.log" "connect Backup iPad"
  assert_not_contains "$dir/launcher.log" "connect Example iPad"
}

test_toggle_prioritizes_device_named_in_trigger_file() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" 0
  /bin/cat > "$dir/devices.txt" <<'EOF'
Backup iPad
Primary iPad
EOF
  print -r -- "Primary iPad" > "$dir/trigger"

  run_script "$dir" toggle

  assert_contains "$dir/launcher.log" "connect Primary iPad"
  assert_not_contains "$dir/launcher.log" "connect Backup iPad"
}

test_sync_disconnects_virtual_display_without_toggling_sidecar() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" 1

  run_script "$dir" sync

  assert_contains "$dir/betterdisplay.log" "set --tagID=16 --connected=off"
  assert_not_contains "$dir/launcher.log" "connect Example iPad"
  assert_not_contains "$dir/launcher.log" "disconnect Example iPad"
}

test_sync_detects_real_external_display_in_nested_system_profiler_output() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" nested_displays

  run_script "$dir" sync

  assert_contains "$dir/betterdisplay.log" "set --tagID=16 --connected=off"
  assert_not_contains "$dir/launcher.log" "connect Example iPad"
  assert_not_contains "$dir/launcher.log" "disconnect Example iPad"
}

test_sync_reopens_virtual_display_and_restarts_sidecar_after_external_disconnect_when_sidecar_was_open() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" nested_displays

  run_script "$dir" sync
  print -r -- "sidecar_only" > "$dir/external"
  run_script "$dir" sync

  assert_contains "$dir/betterdisplay.log" "set --tagID=16 --connected=off"
  assert_contains "$dir/betterdisplay.log" "set --tagID=16 --connected=on"
  assert_contains "$dir/launcher.log" "disconnect Example iPad"
  assert_contains "$dir/launcher.log" "connect Example iPad"
}

test_sync_connects_virtual_display_without_toggling_sidecar_when_no_external_display() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" 0

  run_script "$dir" sync

  assert_contains "$dir/betterdisplay.log" "set --tagID=16 --connected=on"
  assert_not_contains "$dir/launcher.log" "connect Example iPad"
}

test_sync_uses_ioreg_fallback_when_system_profiler_has_no_display_entries() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" system_profiler_gpu_only

  run_script "$dir" sync

  assert_contains "$dir/betterdisplay.log" "set --tagID=16 --connected=off"
  assert_not_contains "$dir/launcher.log" "connect Example iPad"
  assert_not_contains "$dir/launcher.log" "disconnect Example iPad"
}

test_sync_ignores_powered_off_external_display_left_in_ioreg() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" powered_off_external
  print -r -- "external-sidecar" > "$dir/state"

  run_script "$dir" sync

  assert_contains "$dir/betterdisplay.log" "set --tagID=16 --connected=on"
  assert_contains "$dir/launcher.log" "connect Example iPad"
  assert_contains "$dir/state" "recovered"
}

test_sync_ignores_stale_system_profiler_external_when_ioreg_is_powered_off() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" stale_system_profiler_powered_off
  print -r -- "external-sidecar" > "$dir/state"

  run_script "$dir" sync

  assert_contains "$dir/betterdisplay.log" "set --tagID=16 --connected=on"
  assert_contains "$dir/launcher.log" "connect Example iPad"
  assert_contains "$dir/state" "recovered"
}

test_sync_detects_betterdisplay_physical_display_when_ioreg_timing_is_inactive() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" betterdisplay_physical_on_ioreg_inactive
  print -r -- "external-sidecar" > "$dir/state"

  run_script "$dir" sync

  assert_contains "$dir/betterdisplay.log" "get --identifiers"
  assert_contains "$dir/betterdisplay.log" "get --tagID=3 --ddcCapabilitiesString"
  assert_contains "$dir/betterdisplay.log" "set --tagID=16 --connected=off"
  assert_not_contains "$dir/launcher.log" "connect Example iPad"
  assert_contains "$dir/state" "external-sidecar"
}

test_sync_preserves_external_sidecar_state_when_sidecar_probe_temporarily_misses() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" 1
  print -r -- "external-sidecar" > "$dir/state"

  run_script "$dir" sync

  assert_contains "$dir/state" "external-sidecar"
  assert_contains "$dir/betterdisplay.log" "set --tagID=16 --connected=off"
  assert_not_contains "$dir/launcher.log" "connect Example iPad"
}

test_sync_keeps_virtual_display_connected_when_only_virtual_display_exists() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_fixture "$dir" virtual

  run_script "$dir" sync

  assert_contains "$dir/betterdisplay.log" "set --tagID=16 --connected=on"
}

for test_name in ${(k)functions}; do
  if [[ "$test_name" == test_* ]]; then
    "$test_name"
    print -- "ok - $test_name"
  fi
done
