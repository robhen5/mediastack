#!/usr/bin/env bash
# Read-only SMART health check for the media server disks.
#
# Intended for root/systemd because smartctl usually needs raw disk access.
# Configure SMART_DEVICES in .env for stable by-id paths, for example:
#   SMART_DEVICES="/dev/disk/by-id/ata-ST28000NM001C_XXXX"
#
# If SMART_DEVICES is empty, the script tries a conservative by-id discovery
# for whole ata/scsi/nvme devices and skips partition symlinks.

set -euo pipefail

MEDIASTACK_DIR="${MEDIASTACK_DIR:-${MEDIASTACK_ROOT:-/opt/mediastack}}"
SMART_DEVICES="${SMART_DEVICES:-}"
SMARTCTL_OPTIONS="${SMARTCTL_OPTIONS:-}"
SMART_TEMP_WARN_C="${SMART_TEMP_WARN_C:-50}"
SMART_NTFY_URL="${SMART_NTFY_URL:-}"
SMART_NTFY_TOPIC="${SMART_NTFY_TOPIC:-${NTFY_TOPIC:-mediastack-alerts}}"
DRY_RUN="${DRY_RUN:-0}"

is_dry_run() {
  case "${DRY_RUN}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

notify() {
  local title="$1"
  local message="$2"

  if [[ -z "${SMART_NTFY_URL}" ]]; then
    echo "NOTICE: SMART_NTFY_URL is not set; notification skipped."
    return 0
  fi

  if is_dry_run; then
    printf 'DRY-RUN: curl -fsS -H %q -d %q %q\n' \
      "Title: ${title}" "${message}" "${SMART_NTFY_URL}/${SMART_NTFY_TOPIC}"
    return 0
  fi

  curl -fsS \
    -H "Title: ${title}" \
    -H "Priority: high" \
    -H "Tags: warning,hard_disk" \
    -d "${message}" \
    "${SMART_NTFY_URL}/${SMART_NTFY_TOPIC}" >/dev/null
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

extract_attr_raw() {
  local output="$1"
  local attr="$2"
  awk -v attr="${attr}" '$2 == attr { print $10; found=1 } END { if (!found) print "" }' <<<"${output}"
}

extract_temperature() {
  local output="$1"
  local temp=""

  temp="$(awk '/Temperature_Celsius|Airflow_Temperature_Cel|Temperature_Internal/ { print $10; found=1 } END { if (!found) print "" }' <<<"${output}" | head -n1)"
  if [[ -n "${temp}" && "${temp}" =~ ^[0-9]+$ ]]; then
    echo "${temp}"
    return 0
  fi

  temp="$(awk -F: '/Current Drive Temperature/ { gsub(/[^0-9]/, "", $2); print $2; found=1 } END { if (!found) print "" }' <<<"${output}" | head -n1)"
  if [[ -n "${temp}" && "${temp}" =~ ^[0-9]+$ ]]; then
    echo "${temp}"
    return 0
  fi

  echo ""
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

failures=()
echo "==> checking SMART health for ${#device_names[@]} device(s)"

for device in "${device_names[@]}"; do
  echo
  echo "-- ${device}"

  if [[ ! -e "${device}" ]]; then
    failures+=("${device}: missing device path")
    echo "FAIL: missing device path"
    continue
  fi

  output=""
  status=0
  # Intentionally read-only: health, attributes, error log, and self-test log.
  set +e
  output="$(smartctl ${SMARTCTL_OPTIONS} -H -A -l error -l selftest "${device}" 2>&1)"
  status=$?
  set -e

  model="$(awk -F: '/Device Model|Product|Model Number/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' <<<"${output}")"
  serial="$(awk -F: '/Serial Number/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' <<<"${output}")"
  health="$(awk -F: '/SMART overall-health self-assessment test result|SMART Health Status/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' <<<"${output}")"
  temp="$(extract_temperature "${output}")"

  [[ -n "${model}" ]] && echo "model: ${model}"
  [[ -n "${serial}" ]] && echo "serial: ${serial}"
  [[ -n "${health}" ]] && echo "health: ${health}"
  [[ -n "${temp}" ]] && echo "temperature: ${temp} C"

  if (( status != 0 )); then
    failures+=("${device}: smartctl exited ${status}")
  fi

  if [[ -z "${health}" ]]; then
    failures+=("${device}: SMART health result unavailable")
  elif [[ "${health}" != PASSED* && "${health}" != OK* ]]; then
    failures+=("${device}: health=${health}")
  fi

  if [[ -n "${temp}" && "${temp}" =~ ^[0-9]+$ && "${temp}" -ge "${SMART_TEMP_WARN_C}" ]]; then
    failures+=("${device}: temperature ${temp} C >= ${SMART_TEMP_WARN_C} C")
  fi

  for attr in Reallocated_Sector_Ct Current_Pending_Sector Offline_Uncorrectable; do
    raw="$(extract_attr_raw "${output}" "${attr}")"
    if [[ -n "${raw}" && "${raw}" =~ ^[0-9]+$ && "${raw}" -gt 0 ]]; then
      failures+=("${device}: ${attr}=${raw}")
      echo "warning: ${attr}=${raw}"
    fi
  done
done

if (( ${#failures[@]} )); then
  message="$(printf '%s\n' "${failures[@]}")"
  echo
  echo "SMART CHECK FAILED:"
  echo "${message}"
  notify "Mediastack SMART warning" "${message}"
  exit 2
fi

echo
echo "SMART check passed."
