#!/usr/bin/env bash
# Restore rehearsal: extract a config backup into a throwaway directory,
# list its contents, and sanity-check the irreplaceable files. Does NOT
# touch the live /opt/mediastack/config or .env.
#
# Usage:
#   ./scripts/restore-config-test.sh                       # newest archive
#   ./scripts/restore-config-test.sh /path/to/backup.tar.gz
#
# This is what docs/SAFETY.md "Restore rehearsal checklist" runs.
# Re-run after every meaningful compose change and before any disk replacement.

set -euo pipefail

MEDIASTACK_DIR="${MEDIASTACK_DIR:-${MEDIASTACK_ROOT:-/opt/mediastack}}"
BACKUP_ROOT="${BACKUP_ROOT:-${MEDIASTACK_DIR}/backups}"

archive="${1:-}"
if [[ -z "${archive}" ]]; then
  archive="$(ls -1t "${BACKUP_ROOT}"/mediastack-config-*.tar.gz 2>/dev/null | head -1 || true)"
fi

if [[ -z "${archive}" || ! -f "${archive}" ]]; then
  echo "ERROR: no archive found (looked in ${BACKUP_ROOT})" >&2
  echo "Run scripts/backup-config.sh first." >&2
  exit 1
fi

restore_dir="$(mktemp -d -t mediastack-restore-test-XXXXXX)"
# mktemp -d creates the dir 0700 and owned by us, so `rm -r` is sufficient.
# We deliberately use the non-forcing variant so the repo-wide guard in
# tests/test_repo_static.ps1 (which forbids forced recursive deletes in
# scripts/*.sh) stays meaningful.
trap 'echo "==> cleaning up ${restore_dir}"; rm -r "${restore_dir}" 2>/dev/null || true' EXIT

echo "==> rehearsing restore of ${archive}"
echo "==> extracting to ${restore_dir}"
tar -xzf "${archive}" -C "${restore_dir}"

echo
echo "==> top-level layout:"
ls -1 "${restore_dir}"

echo
echo "==> sanity checks:"
fail=0
check() {
  local label="$1" path="$2"
  if [[ -e "${restore_dir}/${path}" ]]; then
    echo "  [ok]   ${label}: ${path}"
  else
    echo "  [MISS] ${label}: ${path}"
    fail=1
  fi
}

check ".env file"             ".env"
check "compose file"          "docker-compose.yml"
check "config root"           "config"
check "qBittorrent state"     "config/qbittorrent"
check "Sonarr DB"             "config/sonarr"
check "Radarr DB"             "config/radarr"
check "Prowlarr DB"           "config/prowlarr"
check "Bazarr DB"             "config/bazarr"
check "Jellyfin data"         "config/jellyfin/data"
check "Jellyseerr config"     "config/jellyseerr"
check "Gluetun state"         "config/gluetun"

# Confirm a few specific irreplaceable files exist in the extract.
if [[ -f "${restore_dir}/config/qbittorrent/qBittorrent/qBittorrent.conf" ]]; then
  echo "  [ok]   qBittorrent.conf present"
else
  echo "  [warn] qBittorrent.conf not found — may not have been configured yet"
fi

if compgen -G "${restore_dir}/config/sonarr/sonarr.db*" > /dev/null; then
  echo "  [ok]   Sonarr SQLite DB present"
else
  echo "  [warn] Sonarr SQLite DB not found — Sonarr may not have been started yet"
fi

if compgen -G "${restore_dir}/config/radarr/radarr.db*" > /dev/null; then
  echo "  [ok]   Radarr SQLite DB present"
else
  echo "  [warn] Radarr SQLite DB not found — Radarr may not have been started yet"
fi

echo
if (( fail )); then
  echo "==> FAIL: one or more required paths missing from the backup."
  echo "    Review scripts/backup-config.sh include list before trusting this archive."
  exit 1
fi

echo "==> PASS: archive extracts and contains the expected layout."
echo "==> NOTE: extract is in ${restore_dir} for inspection (deleted on exit)."
