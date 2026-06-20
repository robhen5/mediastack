#!/usr/bin/env bash
# Apply the known-good UFW allowlist for the mediastack Ubuntu host.
#
# Default is dry-run. Run with APPLY=1 only after checking the printed rules.
# This script intentionally does not delete existing UFW rules. Review with:
#   sudo ufw status numbered

set -euo pipefail

DRY_RUN="${DRY_RUN:-1}"
APPLY="${APPLY:-0}"
LAN_SUBNET="${LAN_SUBNET:-}"
TAILSCALE_SUBNET="${TAILSCALE_SUBNET:-100.64.0.0/10}"
FIREWALL_PORTS="${FIREWALL_PORTS:-22 80 3000 3001 5055 6767 7878 8053 8081 8096 8989 9696 2586 11011}"
FIREWALL_LAN_DNS_PORTS="${FIREWALL_LAN_DNS_PORTS:-53}"

is_apply() {
  case "${APPLY}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

run() {
  if is_apply; then
    "$@"
  else
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  fi
}

if [[ -z "${LAN_SUBNET}" ]]; then
  echo "ERROR: LAN_SUBNET is required, for example 192.168.0.0/24." >&2
  echo "Set it in .env or run: LAN_SUBNET=192.168.0.0/24 $0" >&2
  exit 1
fi

if [[ "${LAN_SUBNET}" == "0.0.0.0/0" || "${TAILSCALE_SUBNET}" == "0.0.0.0/0" ]]; then
  echo "ERROR: refusing to allow from 0.0.0.0/0." >&2
  exit 1
fi

echo "==> UFW allowlist"
echo "LAN_SUBNET=${LAN_SUBNET}"
echo "TAILSCALE_SUBNET=${TAILSCALE_SUBNET}"
echo "FIREWALL_PORTS=${FIREWALL_PORTS}"
echo "FIREWALL_LAN_DNS_PORTS=${FIREWALL_LAN_DNS_PORTS}"
echo

run ufw default deny incoming
run ufw default allow outgoing
run ufw logging low

for port in ${FIREWALL_PORTS}; do
  run ufw allow from "${LAN_SUBNET}" to any port "${port}" proto tcp
  run ufw allow from "${TAILSCALE_SUBNET}" to any port "${port}" proto tcp
done

# Pi-hole DNS is intentionally LAN-only. Do not expose port 53 through the
# Tailscale allowlist until Tailscale split-DNS is configured deliberately.
for port in ${FIREWALL_LAN_DNS_PORTS}; do
  run ufw allow from "${LAN_SUBNET}" to any port "${port}" proto tcp
  run ufw allow from "${LAN_SUBNET}" to any port "${port}" proto udp
done

run ufw enable
run ufw status verbose

if ! is_apply; then
  echo
  echo "Dry run only. Re-run with APPLY=1 after reviewing the commands."
fi
