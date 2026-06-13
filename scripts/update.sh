#!/usr/bin/env bash
# Mediastack image-update workflow. Handles the gluetun→qbittorrent namespace
# gotcha automatically: if gluetun was recreated, qbittorrent must be too.
#
# Run periodically (every 1-2 months is fine). For current deployment guidance
# see README.md and docs/deployment-checklist.md.
#
# Dry run:
#   DRY_RUN=1 ./scripts/update.sh
# Prints the docker commands that would run, including the image prune step,
# without changing containers or deleting old image layers.
#
# Profiles:
#   UPDATE_PROFILES="first-deploy monitoring dashboard" ./scripts/update.sh
# Defaults to the safe core stack, monitoring, and the read-only dashboard.
# Add profiles explicitly when you intentionally run optional services.

set -euo pipefail

MEDIASTACK_DIR="${MEDIASTACK_DIR:-${MEDIASTACK_ROOT:-/opt/mediastack}}"
DRY_RUN="${DRY_RUN:-0}"
UPDATE_PROFILES="${UPDATE_PROFILES:-first-deploy monitoring dashboard}"
cd "${MEDIASTACK_DIR}"

is_dry_run() {
  case "${DRY_RUN}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

run() {
  if is_dry_run; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

inspect_gluetun_id() {
  if is_dry_run; then
    echo dry-run-gluetun-id
  else
    docker inspect --format '{{.Id}}' gluetun 2>/dev/null || echo none
  fi
}

compose() {
  local args=(compose)
  local profile
  for profile in ${UPDATE_PROFILES}; do
    args+=(--profile "${profile}")
  done
  args+=("$@")
  run docker "${args[@]}"
}

container_exists() {
  if is_dry_run; then
    [[ "$1" == "qbittorrent" ]]
  else
    docker inspect "$1" >/dev/null 2>&1
  fi
}

# Container IDs are stable as long as the container isn't recreated. Capture
# gluetun's ID before the update so we can detect whether it got replaced.
old_gluetun_id="$(inspect_gluetun_id)"

echo "==> pulling latest images"
compose pull

echo
echo "==> applying updates"
compose up -d

new_gluetun_id="$(inspect_gluetun_id)"

if [[ "${old_gluetun_id}" != "${new_gluetun_id}" ]]; then
  echo
  echo "==> gluetun was recreated; reattaching dependents to new network namespace"
  # Every container with `network_mode: service:gluetun` must be recreated
  # because its namespace handle points to the OLD gluetun container ID.
  # If you add more VPN-routed containers, add them here. Each service is only
  # recreated when its container already exists, so optional profiles stay off.
  dependents=()
  for service in qbittorrent lazylibrarian; do
    if container_exists "${service}"; then
      dependents+=("${service}")
    fi
  done
  if (( ${#dependents[@]} )); then
    compose up -d --force-recreate "${dependents[@]}"
  fi
fi

echo
echo "==> reclaiming disk from old image versions"
run docker image prune -f

echo
echo "==> final status"
run docker ps --format 'table {{.Names}}\t{{.Status}}'

echo
echo "==> done"
