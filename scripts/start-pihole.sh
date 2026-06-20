#!/usr/bin/env bash
# Start the opt-in Pi-hole service only after validating required host values.
# Default is dry-run. Use APPLY=1 after reviewing the printed command.

set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
APPLY="${APPLY:-0}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: ${ENV_FILE} does not exist." >&2
  exit 1
fi

env_value() {
  local name="$1"
  local line
  line="$(grep -E "^${name}=" "${ENV_FILE}" | tail -n 1 || true)"
  printf '%s' "${line#*=}"
}

pihole_password="$(env_value PIHOLE_WEBPASSWORD)"
lan_ip="$(env_value LAN_IP)"
config_root="$(env_value CONFIG_ROOT)"
config_root="${config_root:-/opt/mediastack/config}"

case "${pihole_password}" in
  ""|replace_*|change_*|changeme|password)
    echo "ERROR: set a unique PIHOLE_WEBPASSWORD in ${ENV_FILE}." >&2
    exit 1
    ;;
esac

if [[ -z "${lan_ip}" ]]; then
  echo "ERROR: LAN_IP must be set in ${ENV_FILE}." >&2
  exit 1
fi

run() {
  if [[ "${APPLY}" == "1" ]]; then
    "$@"
  else
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  fi
}

echo "Pi-hole DNS address: ${lan_ip}"
echo "Pi-hole admin URL: http://${lan_ip}:8053/admin/"
echo "Config directory: ${config_root}/pihole"
echo

run mkdir -p "${config_root}/pihole"
run docker compose --profile dns up -d pihole

if [[ "${APPLY}" != "1" ]]; then
  echo
  echo "Dry run only. Check port 53 and then re-run with APPLY=1."
fi
