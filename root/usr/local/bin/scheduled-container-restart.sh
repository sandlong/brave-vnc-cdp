#!/usr/bin/with-contenv bash
# shellcheck shell=bash

set -Eeuo pipefail

log_dir="${CDP_LOG_DIR:-/config/log}"
mkdir -p "$log_dir" 2>/dev/null || true

{
  printf '[scheduled-container-restart] %s requested by CONTAINER_RESTART_CRON\n' "$(date -Is 2>/dev/null || date)"
} >>"$log_dir/container-restart.log" 2>/dev/null || true

# s6-overlay owns PID 1 in linuxserver images. Requesting a graceful halt lets
# it stop supervised services cleanly; Docker's restart policy is responsible
# for creating the next container run.
exec /run/s6/basedir/bin/halt
