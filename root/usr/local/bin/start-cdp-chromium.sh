#!/usr/bin/env bash
set -Eeuo pipefail

ENABLE_CDP="${ENABLE_CDP:-false}"
CHROME_CLI_RAW="${CHROME_CLI:-}"
CDP_PORT="${CDP_PORT:-9222}"
CDP_INTERNAL_PORT="${CDP_INTERNAL_PORT:-9223}"
CDP_PROFILE_DIR="${CDP_PROFILE_DIR:-/config/cdp-profile}"
CDP_LOG_DIR="${CDP_LOG_DIR:-/config/log}"

read -r -a USER_CHROME_ARGS <<< "${CHROME_CLI_RAW}"
EXTRA_ARGS=("$@")

is_true() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

if is_true "$ENABLE_CDP"; then
  mkdir -p "$CDP_PROFILE_DIR" "$CDP_LOG_DIR"
  socat TCP-LISTEN:"$CDP_PORT",bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:"$CDP_INTERNAL_PORT" \
    >"$CDP_LOG_DIR/cdp-socat.log" 2>&1 &
  EXTRA_ARGS+=(
    "--user-data-dir=$CDP_PROFILE_DIR"
    "--remote-debugging-address=127.0.0.1"
    "--remote-debugging-port=$CDP_INTERNAL_PORT"
  )
fi

exec wrapped-chromium "${EXTRA_ARGS[@]}" "${USER_CHROME_ARGS[@]}"
