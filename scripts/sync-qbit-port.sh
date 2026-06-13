#!/usr/bin/env bash
# Sync qBittorrent's listening port with ProtonVPN's NAT-PMP forwarded port.
# See README.md, docs/deployment-checklist.md, and docs/legacy/SETUP.md.
#
# Why this is needed: gluetun negotiates a forwarded port via NAT-PMP and writes
# it to /tmp/gluetun/forwarded_port (inside the container). qBittorrent's
# Session\Port has to match for incoming peer connections to work. The port
# rotates whenever gluetun reconnects, so we poll periodically.
#
# Run by systemd timer every 5 minutes (see scripts/sync-qbit-port.timer).
# Exits 0 on success or when no change needed; non-zero on error.

set -euo pipefail

MEDIASTACK_DIR="${MEDIASTACK_DIR:-${MEDIASTACK_ROOT:-/opt/mediastack}}"
QBIT_URL="http://localhost:8081"

# Load QBIT_USER / QBIT_PASS from the project's .env (same place as the WG key).
# .env is gitignored so secrets stay out of source control.
if [[ -r "${MEDIASTACK_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; . "${MEDIASTACK_DIR}/.env"; set +a
fi

: "${QBIT_USER:?QBIT_USER not set in ${MEDIASTACK_DIR}/.env}"
: "${QBIT_PASS:?QBIT_PASS not set in ${MEDIASTACK_DIR}/.env}"

log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*"; }

# Best-effort push to the self-hosted ntfy bus (Phase 8). Never let a
# failed notification abort the script — hence the `|| true`. NTFY_TOPIC
# comes from .env (sourced above); falls back to the documented default.
NTFY_URL="http://localhost:2586"
NTFY_TOPIC="${NTFY_TOPIC:-mediastack-alerts}"
notify_fail() {
  curl -fsS --max-time 5 \
    -H "Title: qBit port-sync FAILED" \
    -H "Priority: high" \
    -H "Tags: warning" \
    -d "$1" \
    "${NTFY_URL}/${NTFY_TOPIC}" >/dev/null 2>&1 || true
}

# Step 1: read forwarded port from gluetun's runtime file (inside container).
forwarded_port="$(docker exec gluetun cat /tmp/gluetun/forwarded_port 2>/dev/null | tr -d '[:space:]')"
if ! [[ "${forwarded_port}" =~ ^[0-9]+$ ]] || (( forwarded_port < 1024 || forwarded_port > 65535 )); then
  log "ERROR: invalid forwarded_port from gluetun: '${forwarded_port}'"
  notify_fail "Could not read a valid forwarded port from gluetun (got '${forwarded_port}'). VPN port forwarding may be down."
  exit 1
fi

# Step 2: authenticate to qBittorrent WebUI, save cookie.
cookie_jar="$(mktemp)"
trap 'rm -f "${cookie_jar}"' EXIT

# qBittorrent 5.x responds 204 No Content with a session cookie on success;
# older versions returned "Ok." in the body. We just check the HTTP code and
# that the cookie jar received the QBT_SID cookie — works across versions.
login_http_code="$(curl -sS --max-time 10 \
  -o /dev/null \
  -w '%{http_code}' \
  -c "${cookie_jar}" \
  -H "Referer: ${QBIT_URL}" \
  --data-urlencode "username=${QBIT_USER}" \
  --data-urlencode "password=${QBIT_PASS}" \
  "${QBIT_URL}/api/v2/auth/login")"

case "${login_http_code}" in
  200|204) ;;  # success
  *)
    log "ERROR: qBittorrent login failed (HTTP ${login_http_code})"
    notify_fail "qBittorrent WebUI login failed (HTTP ${login_http_code}) — check QBIT creds or that qBit is up."
    exit 1
    ;;
esac

if ! grep -q 'QBT_SID' "${cookie_jar}"; then
  log "ERROR: qBittorrent login returned ${login_http_code} but no session cookie was set"
  notify_fail "qBittorrent login returned ${login_http_code} but set no session cookie — qBit may be mid-restart."
  exit 1
fi

# Step 3: read qBit's currently-configured listen_port.
current_port="$(curl -fsS --max-time 10 \
  -b "${cookie_jar}" \
  "${QBIT_URL}/api/v2/app/preferences" | jq -r '.listen_port')"

if [[ "${current_port}" == "${forwarded_port}" ]]; then
  log "OK: qBit listen_port (${current_port}) already matches forwarded port — nothing to do"
  exit 0
fi

log "Port mismatch: qBit=${current_port}, gluetun forwarded=${forwarded_port}. Updating..."

# Step 4: write the new port via setPreferences.
curl -fsS --max-time 10 \
  -b "${cookie_jar}" \
  -H "Referer: ${QBIT_URL}" \
  --data-urlencode "json={\"listen_port\": ${forwarded_port}}" \
  "${QBIT_URL}/api/v2/app/setPreferences" > /dev/null

# Step 5: verify the change took.
new_port="$(curl -fsS --max-time 10 \
  -b "${cookie_jar}" \
  "${QBIT_URL}/api/v2/app/preferences" | jq -r '.listen_port')"

if [[ "${new_port}" != "${forwarded_port}" ]]; then
  log "ERROR: setPreferences accepted but verify shows ${new_port}, expected ${forwarded_port}"
  notify_fail "Tried to set qBit listen_port to ${forwarded_port} but it still reads ${new_port}. Incoming peers will be blocked."
  exit 1
fi

log "OK: qBit listen_port updated to ${forwarded_port}"
