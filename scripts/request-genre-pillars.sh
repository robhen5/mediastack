#!/usr/bin/env bash
set -euo pipefail

cd "${MEDIASTACK_ROOT:-/opt/mediastack}"

URL="${JELLYSEERR_URL:-http://localhost:5055}"
APPLY="${APPLY:-0}"
LIMIT="${LIMIT:-}"

args=(--url "$URL")
if [[ -n "$LIMIT" ]]; then
  args+=(--limit "$LIMIT")
fi

if [[ "$APPLY" == "1" ]]; then
  args+=(--apply)
  echo "Mode: APPLY"
else
  echo "Mode: DRY-RUN"
  echo "Set APPLY=1 only after reviewing the dry-run output."
fi

lists=(
  "docs/lists/noir-essentials.csv"
  "docs/lists/western-essentials.csv"
  "docs/lists/sci-fi-essentials.csv"
  "docs/lists/horror-classics.csv"
  "docs/lists/seventies-new-hollywood.csv"
  "docs/lists/nineties-crime-thriller.csv"
)

for list in "${lists[@]}"; do
  echo
  echo "==> $list"
  python3 scripts/request-jellyseerr-list.py "${args[@]}" --list "$list"
done
