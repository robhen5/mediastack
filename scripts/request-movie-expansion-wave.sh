#!/usr/bin/env bash
set -euo pipefail

cd "${MEDIASTACK_ROOT:-/opt/mediastack}"

URL="${JELLYSEERR_URL:-http://localhost:5055}"
APPLY="${APPLY:-0}"
LIMIT="${LIMIT:-}"
WAVE="${WAVE:-all}"

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

run_list() {
  local list="$1"
  if [[ ! -f "$list" ]]; then
    echo
    echo "SKIP: $list does not exist yet. Generate it first if you want this wave."
    return 0
  fi

  echo
  echo "==> $list"
  python3 scripts/request-jellyseerr-list.py "${args[@]}" --list "$list"
}

run_genres() {
  run_list "docs/lists/noir-essentials.csv"
  run_list "docs/lists/western-essentials.csv"
  run_list "docs/lists/sci-fi-essentials.csv"
  run_list "docs/lists/horror-classics.csv"
  run_list "docs/lists/seventies-new-hollywood.csv"
  run_list "docs/lists/nineties-crime-thriller.csv"
}

run_awards() {
  run_list "docs/lists/afi-100-years-100-movies.csv"
  run_list "docs/lists/best-picture-nominees.csv"
  run_list "docs/lists/best-actor-nominated-films.csv"
}

run_directors() {
  run_list "docs/lists/stanley-kubrick-filmography.csv"
  run_list "docs/lists/martin-scorsese-filmography.csv"
  run_list "docs/lists/steven-spielberg-filmography.csv"
  run_list "docs/lists/akira-kurosawa-filmography.csv"
  run_list "docs/lists/david-fincher-filmography.csv"
  run_list "docs/lists/francis-ford-coppola-filmography.csv"
  run_list "docs/lists/coen-brothers-filmography.csv"
  run_list "docs/lists/billy-wilder-filmography.csv"
  run_list "docs/lists/sidney-lumet-filmography.csv"
  run_list "docs/lists/john-carpenter-filmography.csv"
  run_list "docs/lists/sergio-leone-filmography.csv"
  run_list "docs/lists/brian-de-palma-filmography.csv"
  run_list "docs/lists/michael-mann-filmography.csv"
  run_list "docs/lists/ridley-scott-filmography.csv"
}

run_actors() {
  run_list "docs/lists/nicolas-cage-filmography.csv"
  run_list "docs/lists/john-wayne-filmography.csv"
}

run_deep_essentials() {
  run_list "docs/lists/boutique-restoration-essentials.csv"
  run_list "docs/lists/world-cinema-essentials.csv"
  run_list "docs/lists/cult-midnight-essentials.csv"
  run_list "docs/lists/documentary-essentials.csv"
  run_list "docs/lists/animation-essentials.csv"
}

run_disney() {
  run_list "docs/lists/disney-animation-canon.csv"
  run_list "docs/lists/pixar-features.csv"
  run_list "docs/lists/disney-family-classics.csv"
  run_list "docs/lists/disney-vault-classics.csv"
}

case "$WAVE" in
  genres)
    run_genres
    ;;
  awards)
    run_awards
    ;;
  directors)
    run_directors
    ;;
  actors)
    run_actors
    ;;
  essentials)
    run_deep_essentials
    ;;
  disney)
    run_disney
    ;;
  all)
    run_genres
    run_deep_essentials
    run_disney
    run_awards
    run_directors
    run_actors
    ;;
  *)
    echo "ERROR: WAVE must be one of: all, genres, essentials, disney, awards, directors, actors" >&2
    exit 2
    ;;
esac
