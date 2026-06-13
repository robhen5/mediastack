#!/usr/bin/env bash
# Start a non-destructive SMART long self-test on configured disks.
# The test runs in drive firmware and can take many hours on large HDDs.
# Check progress/results with:
#   sudo smartctl -a /dev/disk/by-id/<device>

set -euo pipefail

MEDIASTACK_DIR="${MEDIASTACK_DIR:-${MEDIASTACK_ROOT:-/opt/mediastack}}"
SMART_DEVICES="${SMART_DEVICES:-}"
SMARTCTL_OPTIONS="${SMARTCTL_OPTIONS:-}"
DRY_RUN="${DRY_RUN:-0}"

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

discover_devices() {
  local candidate
  shopt -s nullglob
  for candidate in /dev/disk/by-id/ata-* /dev/disk/by-id/scsi-* /dev/disk/by-id/nvme-*; do
    [[ "${candidate}" == *-part* ]] && continue
    printf '%s\n' "${candidate}"
  done
  shopt -u nullglob
}

device_names=()
if [[ -n "${SMART_DEVICES}" ]]; then
  # shellcheck disable=SC2206
  device_names=(${SMART_DEVICES})
else
  mapfile -t device_names < <(discover_devices)
fi

if (( ${#device_names[@]} == 0 )); then
  echo "ERROR: no SMART devices configured or discovered." >&2
  echo "Set SMART_DEVICES in ${MEDIASTACK_DIR}/.env using stable /dev/disk/by-id paths." >&2
  exit 1
fi

for device in "${device_names[@]}"; do
  if [[ ! -e "${device}" ]]; then
    echo "ERROR: missing device path: ${device}" >&2
    exit 1
  fi

  echo "==> starting SMART long test on ${device}"
  # Non-destructive: asks disk firmware to run an extended self-test.
  run smartctl ${SMARTCTL_OPTIONS} -t long "${device}"
done
