#!/usr/bin/env bash
set -Eeuo pipefail

# CDP-aware Chromium launcher for linuxserver/chromium (Selkies).
#
# Upstream /usr/bin/wrapped-chromium hardcodes a bare `--user-data-dir` with no
# value. Chromium treats the next argv as that switch's value, so flags we append
# (including --user-data-dir=/path and --remote-debugging-*) can be eaten or
# dropped after relaunch. When ENABLE_CDP=true we therefore launch chromium
# directly with an explicit valued --user-data-dir and CDP flags.
#
# /usr/bin/wrapped-chromium in this image is a shim that always re-enters this
# script (so right-click menu / desktop entries also get CDP). The original
# upstream launcher is preserved as /usr/bin/wrapped-chromium.real.

ENABLE_CDP="${ENABLE_CDP:-false}"
CHROME_CLI_RAW="${CHROME_CLI:-}"
CDP_PORT="${CDP_PORT:-9222}"
CDP_INTERNAL_PORT="${CDP_INTERNAL_PORT:-9223}"
CDP_PROFILE_DIR="${CDP_PROFILE_DIR:-/config/cdp-profile}"
CDP_LOG_DIR="${CDP_LOG_DIR:-/config/log}"
# Debian package launcher script -> /usr/lib/chromium/chromium
CHROMIUM_BIN="${CHROMIUM_BIN:-/usr/bin/chromium}"
UPSTREAM_WRAPPER="${UPSTREAM_WRAPPER:-/usr/bin/wrapped-chromium.real}"

read -r -a USER_CHROME_ARGS <<< "${CHROME_CLI_RAW}"
EXTRA_ARGS=("$@")

is_true() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

chromium_running() {
  # Match real browser processes only (not this script / wrappers / pgrep itself).
  pgrep -f '/usr/lib/chromium/chromium' >/dev/null 2>&1
}

clear_stale_singletons() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  # Always safe when no live browser: leftover Singleton* after crash/black-screen
  # makes the next launch exit immediately.
  if ! chromium_running; then
    rm -f "${dir}/Singleton"* 2>/dev/null || true
  fi
}

if ! is_true "$ENABLE_CDP"; then
  if [[ -x "$UPSTREAM_WRAPPER" ]]; then
    exec "$UPSTREAM_WRAPPER" "${EXTRA_ARGS[@]}" "${USER_CHROME_ARGS[@]}"
  fi
  exec "$CHROMIUM_BIN" \
    --no-sandbox \
    --password-store=basic \
    --simulate-outdated-no-au='Tue, 31 Dec 2099 23:59:59 GMT' \
    --start-maximized \
    --test-type \
    "${EXTRA_ARGS[@]}" \
    "${USER_CHROME_ARGS[@]}"
fi

mkdir -p "$CDP_PROFILE_DIR" "$CDP_LOG_DIR"

if ! touch "${CDP_PROFILE_DIR}/.cdp-write-test" 2>/dev/null; then
  echo "start-cdp-chromium: cannot write to CDP_PROFILE_DIR=${CDP_PROFILE_DIR}" >&2
  echo "start-cdp-chromium: uid=$(id -u) gid=$(id -g) path=$(ls -ld "$CDP_PROFILE_DIR" 2>&1 || true)" >&2
  exit 1
fi
rm -f "${CDP_PROFILE_DIR}/.cdp-write-test"

clear_stale_singletons "$CDP_PROFILE_DIR"

# Replace any previous forwarder on CDP_PORT (container restart / watchdog / menu relaunch).
if command -v fuser >/dev/null 2>&1; then
  fuser -k "${CDP_PORT}/tcp" >/dev/null 2>&1 || true
else
  pkill -f "socat TCP-LISTEN:${CDP_PORT}," >/dev/null 2>&1 || true
fi
# brief settle so the port is free
sleep 0.2

socat TCP-LISTEN:"$CDP_PORT",bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:"$CDP_INTERNAL_PORT" \
  >"$CDP_LOG_DIR/cdp-socat.log" 2>&1 &

# Launch via Debian's /usr/bin/chromium (adds package flags) with a valued
# --user-data-dir and loopback CDP. Never call wrapped-chromium.real here.
exec "$CHROMIUM_BIN" \
  --no-sandbox \
  --password-store=basic \
  --simulate-outdated-no-au='Tue, 31 Dec 2099 23:59:59 GMT' \
  --start-maximized \
  --test-type \
  --user-data-dir="$CDP_PROFILE_DIR" \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port="$CDP_INTERNAL_PORT" \
  "${EXTRA_ARGS[@]}" \
  "${USER_CHROME_ARGS[@]}"
