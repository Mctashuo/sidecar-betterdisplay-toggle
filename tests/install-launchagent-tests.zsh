#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
INSTALLER="${ROOT_DIR}/install-sidecar-toggle-launchagent.sh"

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

assert_not_exists() {
  local path="$1"

  [[ ! -e "$path" ]] || fail "Did not expect path to exist: $path"
}

make_install_fixture() {
  local dir="$1"
  local devices="$2"

  /bin/mkdir -p "$dir/home/.local/bin" "$dir/bin"

  /bin/cat > "$dir/home/.local/bin/SidecarLauncher" <<EOF
#!/bin/zsh
if [[ "\$1" == "devices" && "\$2" == "list" ]]; then
${devices}
fi
EOF

  /bin/cat > "$dir/bin/launchctl" <<'EOF'
#!/bin/zsh
print -r -- "$*" >> "${FAKE_LAUNCHCTL_LOG}"
EOF

  /bin/chmod 755 "$dir/home/.local/bin/SidecarLauncher" "$dir/bin/launchctl"
}

run_installer() {
  local dir="$1"
  local input="$2"

  FAKE_LAUNCHCTL_LOG="$dir/launchctl.log" \
  HOME="$dir/home" \
  SIDECAR_TOGGLE_LAUNCHCTL="$dir/bin/launchctl" \
  SIDECAR_TOGGLE_LAUNCHER="$dir/home/.local/bin/SidecarLauncher" \
  "$INSTALLER" <<< "$input"
}

test_install_writes_selected_device_priority() {
  local dir config
  dir="$(/usr/bin/mktemp -d)"
  config="$dir/home/.config/sidecar-toggle/devices.txt"
  make_install_fixture "$dir" $'print -- "Living Room iPad"\nprint -- "Desk iPad"\nprint -- "Travel iPad"'

  run_installer "$dir" "2 1"

  assert_contains "$config" "Desk iPad"
  assert_contains "$config" "Living Room iPad"
  [[ "$(/usr/bin/head -n 1 "$config")" == "Desk iPad" ]] || fail "Expected Desk iPad to be first priority"
  assert_contains "$dir/launchctl.log" "bootstrap"
}

test_install_aborts_when_no_devices_are_visible() {
  local dir
  dir="$(/usr/bin/mktemp -d)"
  make_install_fixture "$dir" ""

  if run_installer "$dir" ""; then
    fail "Installer should fail when no Sidecar devices are visible"
  fi

  assert_not_exists "$dir/home/.config/sidecar-toggle/devices.txt"
}

for test_name in ${(k)functions}; do
  if [[ "$test_name" == test_* ]]; then
    "$test_name"
    print -- "ok - $test_name"
  fi
done
