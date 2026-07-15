#!/usr/bin/env bash
set -Eeuo pipefail

# CDP-aware Chromium launcher for linuxserver/chromium (Selkies).
#
# Upstream /usr/bin/wrapped-chromium hardcodes a bare `--user-data-dir` with no
# value. Chromium treats the next argv as that switch's value, so flags we append
# (including --user-data-dir=/path and --remote-debugging-*) can be eaten or
# dropped after relaunch. When ENABLE_CDP=true we therefore launch chromium
# directly with an explicit valued --user-data-dir and CDP flags.

ENABLE_CDP="${ENABLE_CDP:-false}"
CHROME_CLI_RAW="${CHROME_CLI:-}"
CDP_PORT="${CDP_PORT:-9222}"
CDP_INTERNAL_PORT="${CDP_INTERNAL_PORT:-9223}"
CDP_PROFILE_DIR="${CDP_PROFILE_DIR:-/config/cdp-profile}"
CDP_LOG_DIR="${CDP_LOG_DIR:-/config/log}"
CHROMIUM_BIN="${CHROMIUM_BIN:-/usr/bin/chromium}"

read -r -a USER_CHROME_ARGS <<< "${CHROME_CLI_RAW}"
EXTRA_ARGS=("$@")

is_true() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

if ! is_true "$ENABLE_CDP"; then
  # Non-CDP path: preserve upstream behavior.
  exec wrapped-chromium "${EXTRA_ARGS[@]}" "${USER_CHROME_ARGS[@]}"
fi

mkdir -p "$CDP_PROFILE_DIR" "$CDP_LOG_DIR"

if ! touch "${CDP_PROFILE_DIR}/.cdp-write-test" 2>/dev/null; then
  echo "start-cdp-chromium: cannot write to CDP_PROFILE_DIR=${CDP_PROFILE_DIR}" >&2
  echo "start-cdp-chromium: uid=$(id -u) gid=$(id -g) path=$(ls -ld "$CDP_PROFILE_DIR" 2>&1 || true)" >&2
  exit 1
fi
rm -f "${CDP_PROFILE_DIR}/.cdp-write-test"

# Drop stale singleton locks only when no chromium is running.
if ! pgrep -x chromium >/dev/null 2>&1 && ! pgrep -f '/usr/lib/chromium/chromium' >/dev/null 2>&1; then
  rm -f "${CDP_PROFILE_DIR}/Singleton"* 2>/dev/null || true
fi

# Replace any previous forwarder on CDP_PORT (container restart / watchdog).
if command -v fuser >/dev/null 2>&1; then
  fuser -k "${CDP_PORT}/tcp" >/dev/null 2>&1 || true
else
  pkill -f "socat TCP-LISTEN:${CDP_PORT}," >/dev/null 2>&1 || true
fi

socat TCP-LISTEN:"$CDP_PORT",bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:"$CDP_INTERNAL_PORT" \
  >"$CDP_LOG_DIR/cdp-socat.log" 2>&1 &

# Launch chromium directly. Do NOT call wrapped-chromium here: its bare
# --user-data-dir consumes the next argument and breaks CDP.
#
# Keep the useful upstream defaults, then force a dedicated profile + loopback CDP.
exec "$CHROMIUM_BIN" \
  --no-sandbox \
  --password-store=basic \
  --simulate-outdated-no-au='Tue, 31 Dec 2099 23:59:59 GMT' \
  --start-maximized \
  --test-type \
  --no-default-browser-check \
  --disable-pings \
  --user-data-dir="$CDP_PROFILE_DIR" \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port="$CDP_INTERNAL_PORT" \
  "${EXTRA_ARGS[@]}" \
  "${USER_CHROME_ARGS[@]}"
