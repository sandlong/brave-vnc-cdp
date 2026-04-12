#!/usr/bin/env bash
set -Eeuo pipefail

DISPLAY="${DISPLAY:-:99}"
WIDTH="${VNC_WIDTH:-1440}"
HEIGHT="${VNC_HEIGHT:-900}"
DEPTH="${VNC_DEPTH:-24}"
VNC_PORT="${VNC_PORT:-5900}"
WEB_PORT="${WEB_PORT:-8080}"
CDP_PORT="${CDP_PORT:-9222}"
BRAVE_INTERNAL_CDP_PORT="${BRAVE_INTERNAL_CDP_PORT:-9223}"
VNC_PASS="${VNC_PASS:-change-me}"
VNC_TITLE="${VNC_TITLE:-Brave CDP}"
START_URL="${START_URL:-about:blank}"
USER_DATA_DIR="${USER_DATA_DIR:-/data/profile}"
TZ="${TZ:-UTC}"
SHARED="${VNC_SHARED:-false}"
BRAVE_ARGS_RAW="${BRAVE_ARGS:-}"
LOG_DIR="/var/log/brave-vnc-cdp"
mkdir -p "$USER_DATA_DIR" "$LOG_DIR"
export DISPLAY TZ

cleanup() {
  local code=$?
  trap - EXIT INT TERM
  for pid in "${BRAVE_PID:-}" "${SOCAT_PID:-}" "${NOVNC_PID:-}" "${X11VNC_PID:-}" "${OPENBOX_PID:-}" "${XVFB_PID:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  wait || true
  exit "$code"
}
trap cleanup EXIT INT TERM

x11vnc -storepasswd "$VNC_PASS" /tmp/x11vnc.pass >/dev/null

Xvfb "$DISPLAY" -screen 0 "${WIDTH}x${HEIGHT}x${DEPTH}" -ac +extension RANDR >"$LOG_DIR/xvfb.log" 2>&1 &
XVFB_PID=$!
sleep 1

openbox-session >"$LOG_DIR/openbox.log" 2>&1 &
OPENBOX_PID=$!

X11VNC_ARGS=(
  -display "$DISPLAY"
  -rfbport "$VNC_PORT"
  -forever
  -passwdfile /tmp/x11vnc.pass
  -noxrecord
  -noxfixes
  -noxdamage
)
if [[ "$SHARED" == "true" ]]; then
  X11VNC_ARGS+=( -shared )
else
  X11VNC_ARGS+=( -nevershared )
fi
x11vnc "${X11VNC_ARGS[@]}" >"$LOG_DIR/x11vnc.log" 2>&1 &
X11VNC_PID=$!

websockify --web=/usr/share/novnc/ "$WEB_PORT" "127.0.0.1:${VNC_PORT}" >"$LOG_DIR/novnc.log" 2>&1 &
NOVNC_PID=$!

socat TCP-LISTEN:"$CDP_PORT",bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:"$BRAVE_INTERNAL_CDP_PORT" >"$LOG_DIR/socat.log" 2>&1 &
SOCAT_PID=$!

read -r -a EXTRA_BRAVE_ARGS <<< "$BRAVE_ARGS_RAW"
BRAVE_CMD=(
  brave-browser
  --no-first-run
  --no-default-browser-check
  --disable-dev-shm-usage
  --disable-features=Translate
  --user-data-dir="$USER_DATA_DIR"
  --remote-debugging-address=127.0.0.1
  --remote-debugging-port="$BRAVE_INTERNAL_CDP_PORT"
  --window-size="${WIDTH},${HEIGHT}"
  --start-maximized
  --test-type
  --enable-logging=stderr
  --v=1
  --password-store=basic
)
if [[ "${BRAVE_NO_SANDBOX:-true}" == "true" ]]; then
  BRAVE_CMD+=( --no-sandbox )
fi
BRAVE_CMD+=( "${EXTRA_BRAVE_ARGS[@]}" "$START_URL" )

printf 'Starting Brave VNC CDP container\n'
printf '  noVNC: http://127.0.0.1:%s/vnc.html\n' "$WEB_PORT"
printf '  VNC:   127.0.0.1:%s\n' "$VNC_PORT"
printf '  CDP:   http://127.0.0.1:%s/json/version\n' "$CDP_PORT"
printf '  Title: %s\n' "$VNC_TITLE"
printf '  TZ:    %s\n' "$TZ"

"${BRAVE_CMD[@]}" >"$LOG_DIR/brave.log" 2>&1 &
BRAVE_PID=$!

wait "$BRAVE_PID"
