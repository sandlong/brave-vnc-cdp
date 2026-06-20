#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/usr/local/lib/cdp-lib.sh
source /usr/local/lib/cdp-lib.sh

load_cdp_defaults

CHROME_CLI_RAW="${CHROME_CLI:-}"
read -r -a USER_CHROME_ARGS <<< "${CHROME_CLI_RAW}"
EXTRA_ARGS=("$@")

if is_true "$ENABLE_CDP"; then
  start_cdp_forwarding
fi

exec wrapped-chromium "${EXTRA_ARGS[@]}" "${USER_CHROME_ARGS[@]}"
