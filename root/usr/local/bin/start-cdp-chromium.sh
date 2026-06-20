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

log() { printf '[start-cdp-chromium] %s\n' "$*" >&2; }

is_true() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

is_valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

if is_true "$ENABLE_CDP"; then
  if ! is_valid_port "$CDP_PORT"; then
    log "ERROR: CDP_PORT='$CDP_PORT' is not a valid port (must be 1-65535)"
    exit 1
  fi
  if ! is_valid_port "$CDP_INTERNAL_PORT"; then
    log "ERROR: CDP_INTERNAL_PORT='$CDP_INTERNAL_PORT' is not a valid port (must be 1-65535)"
    exit 1
  fi
  if [[ "$CDP_PORT" == "$CDP_INTERNAL_PORT" ]]; then
    log "ERROR: CDP_PORT and CDP_INTERNAL_PORT must differ (both set to '$CDP_PORT')"
    exit 1
  fi

  if ! mkdir -p "$CDP_PROFILE_DIR" "$CDP_LOG_DIR"; then
    log "ERROR: Failed to create directories: $CDP_PROFILE_DIR, $CDP_LOG_DIR"
    exit 1
  fi

  socat TCP-LISTEN:"$CDP_PORT",bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:"$CDP_INTERNAL_PORT" \
    >>"$CDP_LOG_DIR/cdp-socat.log" 2>&1 &
  SOCAT_PID=$!

  # Give socat a moment to bind or fail (e.g. port already in use)
  sleep 0.3
  if ! kill -0 "$SOCAT_PID" 2>/dev/null; then
    log "ERROR: socat exited immediately (PID $SOCAT_PID). Check $CDP_LOG_DIR/cdp-socat.log for details."
    log "  Typical cause: CDP_PORT $CDP_PORT is already in use."
    exit 1
  fi

  log "CDP forwarding active: 0.0.0.0:$CDP_PORT -> 127.0.0.1:$CDP_INTERNAL_PORT (socat PID $SOCAT_PID)"

  EXTRA_ARGS+=(
    "--user-data-dir=$CDP_PROFILE_DIR"
    "--remote-debugging-address=127.0.0.1"
    "--remote-debugging-port=$CDP_INTERNAL_PORT"
  )
fi

exec wrapped-chromium "${EXTRA_ARGS[@]}" "${USER_CHROME_ARGS[@]}"
