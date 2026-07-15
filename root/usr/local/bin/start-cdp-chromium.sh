#!/usr/bin/env bash
set -Eeuo pipefail

# CDP-aware Chromium launcher for linuxserver/chromium (Selkies).
#
# Upstream /usr/bin/wrapped-chromium hardcodes a bare `--user-data-dir` with no
# value, so appended CDP flags can be swallowed. When ENABLE_CDP=true we launch
# chromium with an explicit valued --user-data-dir and loopback DevTools ports.
#
# /usr/bin/wrapped-chromium in this image is a shim into this script (right-click
# menu / desktop entries). Upstream original is preserved as wrapped-chromium.real.
#
# After a hard crash (commonly right after Sync "I am in"), Chromium leaves
# Singleton* under the profile and /tmp. The next launch then exits immediately.
# We clear those stale locks whenever no live browser process is present.

ENABLE_CDP="${ENABLE_CDP:-false}"
CHROME_CLI_RAW="${CHROME_CLI:-}"
CDP_PORT="${CDP_PORT:-9222}"
CDP_INTERNAL_PORT="${CDP_INTERNAL_PORT:-9223}"
CDP_PROFILE_DIR="${CDP_PROFILE_DIR:-/config/cdp-profile}"
CDP_LOG_DIR="${CDP_LOG_DIR:-/config/log}"
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

# True only if a real browser binary is running (not wrappers / shells).
chromium_running() {
  local pid comm
  for pid in /proc/[0-9]*; do
    [[ -r "$pid/comm" ]] || continue
    comm=$(cat "$pid/comm" 2>/dev/null || true)
    # Debian chromium main/children report comm as "chromium"
    if [[ "$comm" == "chromium" ]]; then
      # Exclude this shell / unrelated helpers by checking exe path when possible.
      if [[ -r "$pid/cmdline" ]]; then
        if tr '\0' '\n' < "$pid/cmdline" 2>/dev/null | grep -q '^/usr/lib/chromium/chromium$'; then
          return 0
        fi
      fi
    fi
  done
  return 1
}

clear_stale_singletons() {
  local dir="$1"
  if chromium_running; then
    return 0
  fi
  if [[ -d "$dir" ]]; then
    rm -f "${dir}/Singleton"* 2>/dev/null || true
  fi
  rm -rf /tmp/org.chromium.Chromium.* 2>/dev/null || true
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

if command -v fuser >/dev/null 2>&1; then
  fuser -k "${CDP_PORT}/tcp" >/dev/null 2>&1 || true
else
  pkill -f "socat TCP-LISTEN:${CDP_PORT}," >/dev/null 2>&1 || true
fi
sleep 0.2

socat TCP-LISTEN:"$CDP_PORT",bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:"$CDP_INTERNAL_PORT" \
  >"$CDP_LOG_DIR/cdp-socat.log" 2>&1 &

# Keep a short launch breadcrumb for post-crash forensics.
{
  date -Is 2>/dev/null || date
  echo "ENABLE_CDP=$ENABLE_CDP CDP_PROFILE_DIR=$CDP_PROFILE_DIR"
  echo "args: ${EXTRA_ARGS[*]} ${USER_CHROME_ARGS[*]}"
} >>"$CDP_LOG_DIR/cdp-launch.log" 2>/dev/null || true

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
