#!/usr/bin/env bats
# Unit tests for root/usr/local/bin/start-cdp-chromium.sh
#
# Strategy: mock external commands (socat, wrapped-chromium) so tests run
# without the full container environment. Let real mkdir handle directories.

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
SCRIPT_UNDER_TEST="${SCRIPT_DIR}/root/usr/local/bin/start-cdp-chromium.sh"

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

# Source only the is_true function from the script without executing the rest.
load_is_true() {
  eval "$(sed -n '/^is_true()/,/^}/p' "$SCRIPT_UNDER_TEST")"
}

# Run the full script with mocked externals.
# Mock wrapped-chromium prints its args to stdout (captured by bats' `run`).
# Mock socat writes its args to $TEST_TMPDIR/socat-args.
run_script() {
  export TEST_TMPDIR
  TEST_TMPDIR="$(mktemp -d)"

  # Mock: wrapped-chromium prints its args to stdout
  cat > "${TEST_TMPDIR}/wrapped-chromium" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@"
MOCK
  chmod +x "${TEST_TMPDIR}/wrapped-chromium"

  # Mock: socat records its args to a file
  cat > "${TEST_TMPDIR}/socat" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${TEST_TMPDIR}/socat-args"
MOCK
  chmod +x "${TEST_TMPDIR}/socat"

  # Replace 'exec' with 'command' so the script doesn't replace the process
  local modified_script="${TEST_TMPDIR}/script.sh"
  sed 's/^exec /command /' "$SCRIPT_UNDER_TEST" > "$modified_script"
  chmod +x "$modified_script"

  # Put mocks first on PATH; use temp dirs for CDP paths
  export PATH="${TEST_TMPDIR}:${PATH}"
  export CDP_LOG_DIR="${CDP_LOG_DIR:-${TEST_TMPDIR}/log}"
  export CDP_PROFILE_DIR="${CDP_PROFILE_DIR:-${TEST_TMPDIR}/cdp-profile}"

  run bash "$modified_script" "$@"
}

setup() {
  unset ENABLE_CDP CHROME_CLI CDP_PORT CDP_INTERNAL_PORT CDP_PROFILE_DIR CDP_LOG_DIR
}

teardown() {
  if [[ -n "${TEST_TMPDIR:-}" && -d "${TEST_TMPDIR:-}" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# ==========================================================================
# is_true() function tests
# ==========================================================================

@test "is_true: '1' returns true" {
  load_is_true
  is_true "1"
}

@test "is_true: 'true' returns true" {
  load_is_true
  is_true "true"
}

@test "is_true: 'TRUE' returns true (case-insensitive)" {
  load_is_true
  is_true "TRUE"
}

@test "is_true: 'True' returns true (mixed case)" {
  load_is_true
  is_true "True"
}

@test "is_true: 'yes' returns true" {
  load_is_true
  is_true "yes"
}

@test "is_true: 'YES' returns true (case-insensitive)" {
  load_is_true
  is_true "YES"
}

@test "is_true: 'on' returns true" {
  load_is_true
  is_true "on"
}

@test "is_true: 'ON' returns true (case-insensitive)" {
  load_is_true
  is_true "ON"
}

@test "is_true: '0' returns false" {
  load_is_true
  ! is_true "0"
}

@test "is_true: 'false' returns false" {
  load_is_true
  ! is_true "false"
}

@test "is_true: 'no' returns false" {
  load_is_true
  ! is_true "no"
}

@test "is_true: empty string returns false" {
  load_is_true
  ! is_true ""
}

@test "is_true: random string returns false" {
  load_is_true
  ! is_true "banana"
}

@test "is_true: 'off' returns false" {
  load_is_true
  ! is_true "off"
}

# ==========================================================================
# Default environment variable tests
# ==========================================================================

@test "defaults: ENABLE_CDP defaults to false (no CDP started)" {
  run_script
  [ "$status" -eq 0 ]
  [ ! -f "${TEST_TMPDIR}/socat-args" ]
}

@test "defaults: CDP_PORT defaults to 9222" {
  export ENABLE_CDP=true
  run_script
  [ "$status" -eq 0 ]
  grep -q "TCP-LISTEN:9222" "${TEST_TMPDIR}/socat-args"
}

@test "defaults: CDP_INTERNAL_PORT defaults to 9223" {
  export ENABLE_CDP=true
  run_script
  [ "$status" -eq 0 ]
  grep -q "TCP:127.0.0.1:9223" "${TEST_TMPDIR}/socat-args"
}

@test "defaults: CDP_PROFILE_DIR defaults to /config/cdp-profile" {
  export ENABLE_CDP=true
  # Explicitly unset so the script uses its built-in default
  unset CDP_PROFILE_DIR
  # We need a writable log dir but let profile dir be the default
  export CDP_LOG_DIR
  TEST_TMPDIR="$(mktemp -d)"
  CDP_LOG_DIR="${TEST_TMPDIR}/log"

  cat > "${TEST_TMPDIR}/wrapped-chromium" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@"
MOCK
  chmod +x "${TEST_TMPDIR}/wrapped-chromium"

  cat > "${TEST_TMPDIR}/socat" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${TEST_TMPDIR}/socat-args"
MOCK
  chmod +x "${TEST_TMPDIR}/socat"

  local modified_script="${TEST_TMPDIR}/script.sh"
  sed 's/^exec /command /' "$SCRIPT_UNDER_TEST" > "$modified_script"
  # Also override mkdir to be a no-op (since /config may not exist)
  cat > "${TEST_TMPDIR}/mkdir" <<'MOCK'
#!/usr/bin/env bash
true
MOCK
  chmod +x "${TEST_TMPDIR}/mkdir"
  chmod +x "$modified_script"
  export PATH="${TEST_TMPDIR}:${PATH}"

  run bash "$modified_script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--user-data-dir=/config/cdp-profile"* ]]
}

@test "defaults: CDP_INTERNAL_PORT default used in --remote-debugging-port" {
  export ENABLE_CDP=true
  run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"--remote-debugging-port=9223"* ]]
}

# ==========================================================================
# Custom environment variable tests
# ==========================================================================

@test "custom: CDP_PORT is respected" {
  export ENABLE_CDP=true
  export CDP_PORT=5555
  run_script
  [ "$status" -eq 0 ]
  grep -q "TCP-LISTEN:5555" "${TEST_TMPDIR}/socat-args"
}

@test "custom: CDP_INTERNAL_PORT is respected" {
  export ENABLE_CDP=true
  export CDP_INTERNAL_PORT=7777
  run_script
  [ "$status" -eq 0 ]
  grep -q "TCP:127.0.0.1:7777" "${TEST_TMPDIR}/socat-args"
}

@test "custom: CDP_INTERNAL_PORT reflected in chromium flag" {
  export ENABLE_CDP=true
  export CDP_INTERNAL_PORT=8888
  run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"--remote-debugging-port=8888"* ]]
}

@test "custom: CDP_PROFILE_DIR is passed to chromium" {
  export ENABLE_CDP=true
  local custom_dir
  custom_dir="$(mktemp -d)/my-custom-profile"
  export CDP_PROFILE_DIR="$custom_dir"
  run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"--user-data-dir=${custom_dir}"* ]]
  rm -rf "$(dirname "$custom_dir")"
}

# ==========================================================================
# CDP-enabled behavior tests
# ==========================================================================

@test "cdp-enabled: socat listens on 0.0.0.0" {
  export ENABLE_CDP=true
  run_script
  [ "$status" -eq 0 ]
  grep -q "bind=0.0.0.0" "${TEST_TMPDIR}/socat-args"
}

@test "cdp-enabled: socat uses reuseaddr and fork" {
  export ENABLE_CDP=true
  run_script
  [ "$status" -eq 0 ]
  grep -q "reuseaddr" "${TEST_TMPDIR}/socat-args"
  grep -q "fork" "${TEST_TMPDIR}/socat-args"
}

@test "cdp-enabled: chromium gets --remote-debugging-address=127.0.0.1" {
  export ENABLE_CDP=true
  run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"--remote-debugging-address=127.0.0.1"* ]]
}

@test "cdp-enabled: chromium gets --user-data-dir" {
  export ENABLE_CDP=true
  run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"--user-data-dir="* ]]
}

@test "cdp-enabled: log directory is created" {
  export ENABLE_CDP=true
  run_script
  [ "$status" -eq 0 ]
  [ -d "${TEST_TMPDIR}/log" ]
}

@test "cdp-enabled: profile directory is created" {
  export ENABLE_CDP=true
  run_script
  [ "$status" -eq 0 ]
  [ -d "${TEST_TMPDIR}/cdp-profile" ]
}

# ==========================================================================
# CDP-disabled behavior tests
# ==========================================================================

@test "cdp-disabled: ENABLE_CDP=false starts no socat" {
  export ENABLE_CDP=false
  run_script
  [ "$status" -eq 0 ]
  [ ! -f "${TEST_TMPDIR}/socat-args" ]
}

@test "cdp-disabled: ENABLE_CDP=0 starts no socat" {
  export ENABLE_CDP=0
  run_script
  [ "$status" -eq 0 ]
  [ ! -f "${TEST_TMPDIR}/socat-args" ]
}

@test "cdp-disabled: no remote-debugging flags passed" {
  export ENABLE_CDP=false
  run_script
  [ "$status" -eq 0 ]
  [[ "$output" != *"--remote-debugging"* ]]
}

@test "cdp-disabled: no --user-data-dir flag passed" {
  export ENABLE_CDP=false
  run_script
  [ "$status" -eq 0 ]
  [[ "$output" != *"--user-data-dir"* ]]
}

@test "cdp-disabled: directories not created when CDP off" {
  export ENABLE_CDP=false
  run_script
  [ "$status" -eq 0 ]
  [ ! -d "${TEST_TMPDIR}/cdp-profile" ]
}

# ==========================================================================
# CHROME_CLI pass-through tests
# ==========================================================================

@test "chrome_cli: extra flags from CHROME_CLI are passed to chromium" {
  export ENABLE_CDP=false
  export CHROME_CLI="--no-sandbox --disable-gpu"
  run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"--no-sandbox"* ]]
  [[ "$output" == *"--disable-gpu"* ]]
}

@test "chrome_cli: CHROME_CLI combined with CDP args" {
  export ENABLE_CDP=true
  export CHROME_CLI="--headless"
  run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"--headless"* ]]
  [[ "$output" == *"--remote-debugging-address=127.0.0.1"* ]]
}

@test "chrome_cli: empty CHROME_CLI is handled gracefully" {
  export ENABLE_CDP=false
  export CHROME_CLI=""
  run_script
  [ "$status" -eq 0 ]
}

@test "chrome_cli: unset CHROME_CLI is handled gracefully" {
  export ENABLE_CDP=false
  unset CHROME_CLI
  run_script
  [ "$status" -eq 0 ]
}

# ==========================================================================
# Positional argument (extra args) tests
# ==========================================================================

@test "extra-args: positional arguments are passed to chromium" {
  export ENABLE_CDP=false
  run_script --enable-features=UseOzonePlatform --ozone-platform=wayland
  [ "$status" -eq 0 ]
  [[ "$output" == *"--enable-features=UseOzonePlatform"* ]]
  [[ "$output" == *"--ozone-platform=wayland"* ]]
}

@test "extra-args: positional args combined with CDP args" {
  export ENABLE_CDP=true
  run_script --kiosk
  [ "$status" -eq 0 ]
  [[ "$output" == *"--kiosk"* ]]
  [[ "$output" == *"--remote-debugging-address=127.0.0.1"* ]]
}

@test "extra-args: positional args combined with CHROME_CLI" {
  export ENABLE_CDP=false
  export CHROME_CLI="--no-sandbox"
  run_script --kiosk
  [ "$status" -eq 0 ]
  [[ "$output" == *"--kiosk"* ]]
  [[ "$output" == *"--no-sandbox"* ]]
}

@test "extra-args: all three sources combined (CDP + CHROME_CLI + positional)" {
  export ENABLE_CDP=true
  export CHROME_CLI="--no-sandbox"
  run_script --kiosk
  [ "$status" -eq 0 ]
  [[ "$output" == *"--remote-debugging-address=127.0.0.1"* ]]
  [[ "$output" == *"--no-sandbox"* ]]
  [[ "$output" == *"--kiosk"* ]]
}

# ==========================================================================
# Argument ordering tests
# ==========================================================================

@test "ordering: positional args appear before CHROME_CLI args" {
  export ENABLE_CDP=false
  export CHROME_CLI="--chrome-cli-flag"
  run_script --positional-flag

  [ "$status" -eq 0 ]
  # positional args ($@) come first in EXTRA_ARGS, CHROME_CLI comes after
  local pos_line chrome_line
  pos_line=$(echo "$output" | grep -n "positional-flag" | cut -d: -f1)
  chrome_line=$(echo "$output" | grep -n "chrome-cli-flag" | cut -d: -f1)
  [ "$pos_line" -lt "$chrome_line" ]
}

@test "ordering: CDP args appear before CHROME_CLI when CDP enabled" {
  export ENABLE_CDP=true
  export CHROME_CLI="--chrome-cli-flag"
  run_script

  [ "$status" -eq 0 ]
  local cdp_line chrome_line
  cdp_line=$(echo "$output" | grep -n "remote-debugging-address" | cut -d: -f1)
  chrome_line=$(echo "$output" | grep -n "chrome-cli-flag" | cut -d: -f1)
  [ "$cdp_line" -lt "$chrome_line" ]
}
