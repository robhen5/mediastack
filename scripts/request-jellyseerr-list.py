#!/usr/bin/env python3
"""Request a CSV media list through Jellyseerr.

Dry-run is the default. Use --apply to create requests.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


DEFAULT_LIST = "docs/lists/afi-100-years-100-movies.csv"


@dataclass
class MovieRow:
    rank: str
    title: str
    year: str
    tmdb_id: str
    notes: str
    media_type: str = "movie"


def normalize_title(value: str) -> str:
    value = value.lower()
    value = value.replace("&", "and")
    value = re.sub(r"[^a-z0-9]+", " ", value)
    value = re.sub(r"\b(the|a|an)\b", " ", value)
    return " ".join(value.split())


def release_year(result: dict[str, Any]) -> str:
    date = result.get("releaseDate") or result.get("firstAirDate") or ""
    return str(date)[:4] if date else ""


def movie_title(result: dict[str, Any]) -> str:
    return str(result.get("title") or result.get("name") or "")


def media_status(result: dict[str, Any]) -> str:
    media_info = result.get("mediaInfo") or {}
    status = media_info.get("status")
    status_name = media_info.get("statusName")
    if status_name:
        return str(status_name)
    if status is None:
        return "not_requested"
    return str(status)


def tv_seasons(media_id: int, args: argparse.Namespace) -> list[int]:
    status, payload = request_json(
        "GET",
        jellyseerr_url(args.url, f"/api/v1/tv/{media_id}"),
        args.api_key,
        args.timeout,
    )
    if status != 200:
        raise RuntimeError(f"TV details HTTP {status}: {payload}")

    seasons = []
    for season in payload.get("seasons", []):
        season_number = season.get("seasonNumber")
        if season_number is None:
            continue
        if season_number == 0 and not args.include_specials:
            continue
        seasons.append(int(season_number))
    return sorted(set(seasons))


def request_json(
    method: str,
    url: str,
    api_key: str,
    timeout: float,
    body: dict[str, Any] | None = None,
) -> tuple[int, Any]:
    data = None
    headers = {
        "Accept": "application/json",
        "X-Api-Key": api_key,
    }
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=timeout) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            payload = raw
        return exc.code, payload


def load_rows(path: str) -> list[MovieRow]:
    with open(path, newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        required = {"rank", "title", "year", "tmdb_id", "notes"}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise SystemExit(f"CSV is missing required columns: {', '.join(sorted(missing))}")

        rows = []
        for item in reader:
            rows.append(
                MovieRow(
                    rank=(item.get("rank") or "").strip(),
                    title=(item.get("title") or "").strip(),
                    year=(item.get("year") or "").strip(),
                    tmdb_id=(item.get("tmdb_id") or "").strip(),
                    notes=(item.get("notes") or "").strip(),
                    media_type=(item.get("media_type") or "movie").strip().lower(),
                )
            )
        return rows


def jellyseerr_url(base_url: str, path: str, query: dict[str, str] | None = None) -> str:
    url = base_url.rstrip("/") + path
    if query:
        url += "?" + urlencode(query, quote_via=quote)
    return url


def search_movie(row: MovieRow, args: argparse.Namespace) -> tuple[str, dict[str, Any] | None, str]:
    if row.media_type not in {"movie", "tv"}:
        return "invalid_media_type", None, f"expected media_type movie or tv, got {row.media_type!r}"

    if row.tmdb_id:
        date_key = "releaseDate" if row.media_type == "movie" else "firstAirDate"
        return "tmdb_id", {"id": int(row.tmdb_id), "title": row.title, date_key: row.year}, ""

    status, payload = request_json(
        "GET",
        jellyseerr_url(args.url, "/api/v1/search", {"query": row.title}),
        args.api_key,
        args.timeout,
    )
    if status != 200:
        return "search_error", None, f"search HTTP {status}: {payload}"

    results = [r for r in payload.get("results", []) if r.get("mediaType") == row.media_type]
    wanted_title = normalize_title(row.title)

    exact = [
        r
        for r in results
        if normalize_title(movie_title(r)) == wanted_title and release_year(r) == row.year
    ]
    if len(exact) == 1:
        return "matched", exact[0], ""

    same_year = [r for r in results if release_year(r) == row.year]
    if len(same_year) == 1 and normalize_title(movie_title(same_year[0])) == wanted_title:
        return "matched", same_year[0], ""

    exact_title = [r for r in results if normalize_title(movie_title(r)) == wanted_title]
    if len(exact_title) == 1 and args.allow_year_mismatch:
        return "matched_year_mismatch", exact_title[0], ""

    if args.allow_ambiguous and results:
        return "matched_ambiguous", results[0], "selected first search result"

    preview = "; ".join(
        f"{movie_title(r)} ({release_year(r) or '????'}) tmdb={r.get('id')}"
        for r in results[:5]
    )
    return "ambiguous", None, preview or "no movie search results"


def request_movie(row: MovieRow, match: dict[str, Any], args: argparse.Namespace) -> tuple[str, str]:
    tmdb_id = int(match["id"])
    body = {"mediaType": row.media_type, "mediaId": tmdb_id}
    if row.media_type == "tv":
        seasons = tv_seasons(tmdb_id, args)
        if not seasons:
            return "skipped", "no requestable TV seasons found"
        body["seasons"] = seasons
    if args.server_id is not None:
        body["serverId"] = args.server_id
    if args.profile_id is not None:
        body["profileId"] = args.profile_id
    if args.root_folder is not None:
        body["rootFolder"] = args.root_folder

    if not args.apply:
        return "dry_run", "would request"

    status, payload = request_json(
        "POST",
        jellyseerr_url(args.url, "/api/v1/request"),
        args.api_key,
        args.timeout,
        body,
    )
    if status in (200, 201):
        return "requested", "created request"
    if status in (400, 409):
        return "skipped", f"already requested/available or rejected: {payload}"
    return "error", f"request HTTP {status}: {payload}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=os.environ.get("JELLYSEERR_URL", "http://localhost:5055"))
    parser.add_argument("--api-key", default=os.environ.get("JELLYSEERR_API_KEY"))
    parser.add_argument("--list", default=DEFAULT_LIST)
    parser.add_argument("--apply", action="store_true", help="Create Jellyseerr requests.")
    parser.add_argument("--limit", type=int, help="Process at most this many rows.")
    parser.add_argument("--start-rank", type=int, default=1)
    parser.add_argument("--sleep", type=float, default=0.25)
    parser.add_argument("--timeout", type=float, default=20)
    parser.add_argument("--allow-ambiguous", action="store_true")
    parser.add_argument("--allow-year-mismatch", action="store_true")
    parser.add_argument("--server-id", type=int)
    parser.add_argument("--profile-id", type=int)
    parser.add_argument("--root-folder")
    parser.add_argument(
        "--include-specials",
        action="store_true",
        help="Include TV season 0 specials when requesting TV rows.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.api_key:
        print("ERROR: pass --api-key or set JELLYSEERR_API_KEY.", file=sys.stderr)
        return 2

    rows = [r for r in load_rows(args.list) if int(r.rank or 0) >= args.start_rank]
    if args.limit is not None:
        rows = rows[: args.limit]

    print(f"Mode: {'APPLY' if args.apply else 'DRY-RUN'}")
    print(f"URL: {args.url}")
    print(f"List: {args.list}")
    print("")

    failures = 0
    requested = 0
    for row in rows:
        try:
            match_status, match, detail = search_movie(row, args)
            if not match:
                failures += 1
                print(f"[{row.rank}] SKIP {row.title} ({row.year}) - {match_status}: {detail}")
                continue

            name = movie_title(match) or row.title
            year = release_year(match) or row.year
            status = media_status(match)
            action, message = request_movie(row, match, args)
            if action in {"requested", "dry_run"}:
                requested += 1
            elif action == "error":
                failures += 1

            print(
                f"[{row.rank}] {action.upper()} {row.title} ({row.year}) [{row.media_type}] -> "
                f"{name} ({year}) tmdb={match['id']} status={status} - {message}"
            )
            if detail:
                print(f"      note: {detail}")
            time.sleep(args.sleep)
        except (RuntimeError, URLError, TimeoutError, ValueError) as exc:
            failures += 1
            print(f"[{row.rank}] ERROR {row.title} ({row.year}) - {exc}")

    print("")
    print(f"Done. candidate_requests={requested} failures={failures}")
    if failures and not args.allow_ambiguous:
        print("Review skipped/ambiguous rows before using --apply.")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
