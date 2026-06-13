#!/usr/bin/env bash
# Mediastack configuration backup. Targets the data-loss controls in
# docs/SAFETY.md "Backup plan."
#
# Captures the irreplaceable bits — .env, app config databases, *arr
# SQLite, Jellyfin metadata, qBittorrent state, compose + scripts — into a
# single tarball under BACKUP_ROOT. Skips container-owned regenerable
# state that either bloats the archive or can't be tarred safely (live
# Postgres data dir, Caddy TLS state, ntfy attachment cache, diun cache).
#
# Media payload (DATA_ROOT) is deliberately NOT backed up — it's hundreds of
# GB to dozens of TB and recoverable by re-grabbing through the *arrs.
#
# Usage:
#   ./scripts/backup-config.sh           # write a new tarball
#   DRY_RUN=1 ./scripts/backup-config.sh # print what would be archived
#   KEEP=6 ./scripts/backup-config.sh    # rotate, keep N most recent (default 6)
#
# Recommended cadence: weekly via cron/systemd, plus an ad-hoc run before
# any compose change or app upgrade. Copy the tarball OFF the host
# afterwards (USB drive, another LAN host, encrypted cloud).

set -euo pipefail

MEDIASTACK_DIR="${MEDIASTACK_DIR:-${MEDIASTACK_ROOT:-/opt/mediastack}}"
BACKUP_ROOT="${BACKUP_ROOT:-${MEDIASTACK_DIR}/backups}"
KEEP="${KEEP:-6}"
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

timestamp="$(date +%Y%m%d-%H%M%S)"
archive="${BACKUP_ROOT}/mediastack-config-${timestamp}.tar.gz"

if [[ ! -d "${MEDIASTACK_DIR}" ]]; then
  echo "ERROR: MEDIASTACK_DIR not found: ${MEDIASTACK_DIR}" >&2
  exit 1
fi

if [[ ! -d "${MEDIASTACK_DIR}/config" ]]; then
  echo "ERROR: ${MEDIASTACK_DIR}/config not found — nothing to back up" >&2
  exit 1
fi

run mkdir -p "${BACKUP_ROOT}"

echo "==> creating ${archive}"

# Exclusions:
#  - caddy/data/caddy + caddy/config/caddy: TLS/runtime, rebuilt on restart.
#  - jellystat-db: live Postgres data dir — file-copying a running DB
#    can corrupt the snapshot. Use Jellystat's UI backup for stats history.
#  - diun: only tracks seen image versions; rebuilds itself.
#  - ntfy/attachments + ntfy/cache.db: ephemeral cached push messages.
#  - jellyfin/cache + jellyfin/log: regenerable cache and rotated logs.
#  - jellyfin/transcodes: huge transient transcoding scratch.
# Jellyfin metadata + watch state (jellyfin/data, jellyfin/metadata,
# jellyfin/root) IS captured — it's what users care about.
run tar -czf "${archive}" \
  --warning=no-file-changed \
  --warning=no-file-removed \
  --exclude='config/caddy/data/caddy' \
  --exclude='config/caddy/config/caddy' \
  --exclude='config/jellystat-db' \
  --exclude='config/diun' \
  --exclude='config/ntfy/attachments' \
  --exclude='config/ntfy/cache.db' \
  --exclude='config/jellyfin/cache' \
  --exclude='config/jellyfin/log' \
  --exclude='config/jellyfin/transcodes' \
  -C "${MEDIASTACK_DIR}" \
  config .env docker-compose.yml scripts \
  2>&1 | grep -v 'socket ignored' || true

if ! is_dry_run; then
  if [[ ! -s "${archive}" ]]; then
    echo "ERROR: archive empty or missing: ${archive}" >&2
    exit 1
  fi
  size="$(du -h "${archive}" | cut -f1)"
  echo "==> wrote ${archive} (${size})"
fi

# Smoke-test the archive: confirm tar can read it back.
echo "==> verifying archive integrity"
run tar -tzf "${archive}" > /dev/null

# Rotation: keep the KEEP most recent archives.
echo "==> rotating, keeping ${KEEP} most recent"
if ! is_dry_run; then
  mapfile -t archives < <(ls -1t "${BACKUP_ROOT}"/mediastack-config-*.tar.gz 2>/dev/null || true)
  if (( ${#archives[@]} > KEEP )); then
    for old in "${archives[@]:KEEP}"; do
      echo "    removing ${old}"
      rm -f "${old}"
    done
  fi
fi

echo
echo "==> done"
echo "Next: copy ${archive} OFF this host (USB, LAN, or encrypted cloud)."
echo "See docs/SAFETY.md for the restore rehearsal checklist."
