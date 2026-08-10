#!/usr/bin/env bash
set -euo pipefail

cd "${MEDIASTACK_ROOT:-/opt/mediastack}"

SLEEP_SECONDS="${SLEEP_SECONDS:-75}"
START_AT="${START_AT:-}"
STOP_AFTER="${STOP_AFTER:-}"

directors=(
  "kubrick"
  "scorsese"
  "spielberg"
  "kurosawa"
  "fincher"
  "coppola"
  "coen-brothers"
  "billy-wilder"
  "sidney-lumet"
  "john-carpenter"
  "sergio-leone"
  "brian-de-palma"
  "michael-mann"
  "ridley-scott"
)

started=0
for slug in "${directors[@]}"; do
  if [[ -n "$START_AT" && "$started" == "0" && "$slug" != "$START_AT" ]]; then
    echo "SKIP: $slug before START_AT=$START_AT"
    continue
  fi

  started=1
  echo
  echo "==> generating director list: $slug"
  python3 scripts/generate-jellyseerr-curated-lists.py --list "$slug"

  if [[ -n "$STOP_AFTER" && "$slug" == "$STOP_AFTER" ]]; then
    echo "STOP: reached STOP_AFTER=$STOP_AFTER"
    break
  fi

  echo "Sleeping ${SLEEP_SECONDS}s to be kind to Wikidata."
  sleep "$SLEEP_SECONDS"
done
