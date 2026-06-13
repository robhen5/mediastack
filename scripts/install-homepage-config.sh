#!/usr/bin/env bash
# Install the repo-owned Homepage dashboard templates into CONFIG_ROOT.
#
# Safe defaults:
#   - Creates the target directory when missing.
#   - Refuses to overwrite existing files unless FORCE=1 is set.
#   - Backs up overwritten files to *.bak-<timestamp>.
#   - DRY_RUN=1 prints every filesystem change without writing.

set -euo pipefail

MEDIASTACK_DIR="${MEDIASTACK_DIR:-${MEDIASTACK_ROOT:-/opt/mediastack}}"
CONFIG_ROOT="${CONFIG_ROOT:-${MEDIASTACK_DIR}/config}"
SOURCE_DIR="${MEDIASTACK_DIR}/config-templates/homepage"
TARGET_DIR="${CONFIG_ROOT}/homepage"
DRY_RUN="${DRY_RUN:-0}"
FORCE="${FORCE:-0}"

is_dry_run() {
  case "${DRY_RUN}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

is_force() {
  case "${FORCE}" in
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

if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "ERROR: Homepage template directory not found: ${SOURCE_DIR}" >&2
  exit 1
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
run mkdir -p "${TARGET_DIR}"

for source in "${SOURCE_DIR}"/*.yaml; do
  name="$(basename "${source}")"
  target="${TARGET_DIR}/${name}"

  if [[ -e "${target}" ]]; then
    if ! is_force; then
      echo "SKIP: ${target} already exists. Re-run with FORCE=1 to back up and replace it."
      continue
    fi

    backup="${target}.bak-${timestamp}"
    echo "BACKUP: ${target} -> ${backup}"
    run cp -p "${target}" "${backup}"
  fi

  echo "INSTALL: ${source} -> ${target}"
  run cp "${source}" "${target}"
done

echo
echo "Done. Start the dashboard with:"
echo "  docker compose --profile dashboard --profile monitoring up -d homepage ntfy uptime-kuma"
