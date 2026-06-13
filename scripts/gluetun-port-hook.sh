#!/bin/sh
# Runs INSIDE the gluetun container. Triggered by gluetun's
# VPN_PORT_FORWARDING_UP_COMMAND on every port-forward "up" event.
# See README.md, docs/deployment-checklist.md, and docs/legacy/SETUP.md.
#
# qBittorrent shares gluetun's network namespace, so it's reachable at
# localhost:8080 from in here. Uses busybox wget + sed (no curl/jq/bash).

set -eu

NEW_PORT="${1:-}"
QBIT_URL="http://localhost:8080"

log() { printf '[gluetun-port-hook] %s\n' "$*"; }

case "${NEW_PORT}" in
  ''|*[!0-9]*)
    log "ERROR: invalid port '${NEW_PORT}'"; exit 1 ;;
esac

if [ -z "${QBIT_USER:-}" ] || [ -z "${QBIT_PASS:-}" ]; then
  log "ERROR: QBIT_USER/QBIT_PASS not set in gluetun container env"; exit 1
fi

# Login. Capture response headers (busybox wget -S writes them to stderr).
# Cookie name is QBT_SID_<port> (e.g. QBT_SID_8080) — match flexibly.
LOGIN_HEADERS=$(
  wget -q -S \
    --header="Referer: ${QBIT_URL}" \
    --post-data="username=${QBIT_USER}&password=${QBIT_PASS}" \
    -O /dev/null \
    "${QBIT_URL}/api/v2/auth/login" 2>&1 || true
)

SID_COOKIE=$(echo "${LOGIN_HEADERS}" | sed -n 's/.*[Ss]et-[Cc]ookie:[[:space:]]*\(QBT_SID_[0-9]*=[^;]*\).*/\1/p' | head -1)

if [ -z "${SID_COOKIE}" ]; then
  log "ERROR: qBit login failed (no session cookie in response)"; exit 1
fi

# Read current listen_port. busybox sed has limited regex; this works:
CURRENT_PORT=$(
  wget -q --header="Cookie: ${SID_COOKIE}" \
    -O - "${QBIT_URL}/api/v2/app/preferences" \
  | sed -n 's/.*"listen_port"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p'
)

if [ "${CURRENT_PORT}" = "${NEW_PORT}" ]; then
  log "OK: qBit listen_port already ${NEW_PORT}, no change needed"
  exit 0
fi

log "Port mismatch: qBit=${CURRENT_PORT}, gluetun=${NEW_PORT}. Updating..."

wget -q \
  --header="Cookie: ${SID_COOKIE}" \
  --header="Referer: ${QBIT_URL}" \
  --post-data="json={\"listen_port\": ${NEW_PORT}}" \
  -O /dev/null \
  "${QBIT_URL}/api/v2/app/setPreferences"

log "OK: qBit listen_port updated to ${NEW_PORT}"
