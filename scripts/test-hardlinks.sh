#!/usr/bin/env bash
# Verify that DATA_ROOT supports hardlinks across the torrents/ and media/
# trees. If this fails, Sonarr/Radarr imports fall back to slow full copies
# AND the seeding hardlink/import-copy dedup breaks — so a 30GB library
# becomes 60GB of duplicated bytes on the 28TB Exos.
#
# This is the test docs/SAFETY.md and docs/deployment-checklist.md require
# before enabling any *arr imports. Re-run any time DATA_ROOT changes
# (filesystem swap, pool reshape, new DAS attached).
#
# Usage:
#   ./scripts/test-hardlinks.sh
#   DATA_ROOT=/some/other/root ./scripts/test-hardlinks.sh

set -euo pipefail

DATA_ROOT="${DATA_ROOT:-/media/storage/data}"
TORRENTS_DIR="${DATA_ROOT}/torrents"
MEDIA_DIR="${DATA_ROOT}/media"
TORRENT_TEST="${TORRENTS_DIR}/.hardlink-test"
MEDIA_TEST="${MEDIA_DIR}/.hardlink-test"

cleanup() {
  rm -f "${TORRENT_TEST}" "${MEDIA_TEST}" 2>/dev/null || true
}
trap cleanup EXIT

if [[ ! -d "${DATA_ROOT}" ]]; then
  echo "FAIL: DATA_ROOT not found: ${DATA_ROOT}" >&2
  exit 1
fi

mkdir -p "${TORRENTS_DIR}" "${MEDIA_DIR}"

echo "==> writing sentinel file under ${TORRENTS_DIR}"
echo "mediastack-hardlink-test-$(date +%s)" > "${TORRENT_TEST}"

echo "==> attempting hardlink into ${MEDIA_DIR}"
if ! ln "${TORRENT_TEST}" "${MEDIA_TEST}" 2>/dev/null; then
  echo
  echo "FAIL: ln across torrents/ and media/ refused by the filesystem." >&2
  echo "      torrents/ and media/ are most likely on different filesystems," >&2
  echo "      mount points, or pool branches. Sonarr/Radarr imports will COPY," >&2
  echo "      doubling disk usage." >&2
  echo >&2
  echo "      Check:   findmnt -T ${TORRENTS_DIR}  and  findmnt -T ${MEDIA_DIR}" >&2
  echo "      Fix by placing both under one filesystem before importing." >&2
  exit 1
fi

# Compare inode numbers and link counts.
torrent_inode="$(stat -c '%i' "${TORRENT_TEST}")"
media_inode="$(stat -c '%i' "${MEDIA_TEST}")"
torrent_links="$(stat -c '%h' "${TORRENT_TEST}")"
media_links="$(stat -c '%h' "${MEDIA_TEST}")"
torrent_dev="$(stat -c '%d' "${TORRENT_TEST}")"
media_dev="$(stat -c '%d' "${MEDIA_TEST}")"

echo
echo "    torrents/: inode=${torrent_inode} links=${torrent_links} device=${torrent_dev}"
echo "    media/   : inode=${media_inode} links=${media_links} device=${media_dev}"

if [[ "${torrent_inode}" != "${media_inode}" ]]; then
  echo "FAIL: hardlink succeeded but inodes differ — fs is faking it (overlayfs?)." >&2
  exit 1
fi

if [[ "${torrent_dev}" != "${media_dev}" ]]; then
  echo "FAIL: hardlink succeeded but devices differ — split filesystem." >&2
  exit 1
fi

if (( torrent_links < 2 )); then
  echo "FAIL: hardlink succeeded but link count < 2." >&2
  exit 1
fi

# Now confirm the *arrs' actual import path: the typical layout is
# torrents/<category>/<release> hardlinked to media/<library>/<file>. Re-run
# the test one level deeper to catch nested-mountpoint surprises.
mkdir -p "${TORRENTS_DIR}/.hardlink-test-dir" "${MEDIA_DIR}/.hardlink-test-dir"
nested_torrent="${TORRENTS_DIR}/.hardlink-test-dir/file"
nested_media="${MEDIA_DIR}/.hardlink-test-dir/file"
echo "nested-test-$(date +%s)" > "${nested_torrent}"
if ! ln "${nested_torrent}" "${nested_media}" 2>/dev/null; then
  echo "FAIL: hardlink across nested subdirs refused — sub-mountpoint detected." >&2
  rm -r "${TORRENTS_DIR}/.hardlink-test-dir" "${MEDIA_DIR}/.hardlink-test-dir" 2>/dev/null || true
  exit 1
fi
rm -r "${TORRENTS_DIR}/.hardlink-test-dir" "${MEDIA_DIR}/.hardlink-test-dir" 2>/dev/null || true

# Disk-usage sanity: a hardlinked pair must NOT double-count.
size_each="$(du -b "${TORRENT_TEST}" | cut -f1)"
size_pair="$(du -bc "${TORRENT_TEST}" "${MEDIA_TEST}" | tail -1 | cut -f1)"
if [[ "${size_each}" != "${size_pair}" ]]; then
  echo "FAIL: du reports the hardlinked pair as ${size_pair} bytes, expected ${size_each}." >&2
  echo "      The fs is treating the link as a copy — imports will duplicate bytes." >&2
  exit 1
fi

echo
echo "PASS: hardlinks across torrents/ and media/ work, single inode, no byte duplication."
echo "      *arr imports will hardlink instead of copy. Safe to proceed with imports."
