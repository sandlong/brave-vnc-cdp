#!/usr/bin/env bash
# cdp-lib.sh -- shared helpers for chromium-selkies-cdp scripts.
# Source this file; do not execute it directly.

# ---------------------------------------------------------------------------
# Boolean helper
# ---------------------------------------------------------------------------
is_true() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Environment defaults (all overridable via env vars)
# ---------------------------------------------------------------------------
load_cdp_defaults() {
  ENABLE_CDP="${ENABLE_CDP:-false}"
  CDP_PORT="${CDP_PORT:-9222}"
  CDP_INTERNAL_PORT="${CDP_INTERNAL_PORT:-9223}"
  CDP_PROFILE_DIR="${CDP_PROFILE_DIR:-/config/cdp-profile}"
  CDP_LOG_DIR="${CDP_LOG_DIR:-/config/log}"
}

# ---------------------------------------------------------------------------
# Start socat forwarding and append Chromium CDP flags to EXTRA_ARGS.
# Expects EXTRA_ARGS to be a pre-declared array in the caller.
# ---------------------------------------------------------------------------
start_cdp_forwarding() {
  mkdir -p "$CDP_PROFILE_DIR" "$CDP_LOG_DIR"
  socat TCP-LISTEN:"$CDP_PORT",bind=0.0.0.0,reuseaddr,fork \
        TCP:127.0.0.1:"$CDP_INTERNAL_PORT" \
    >"$CDP_LOG_DIR/cdp-socat.log" 2>&1 &
  EXTRA_ARGS+=(
    "--user-data-dir=$CDP_PROFILE_DIR"
    "--remote-debugging-address=127.0.0.1"
    "--remote-debugging-port=$CDP_INTERNAL_PORT"
  )
}
