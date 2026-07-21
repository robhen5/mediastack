#!/usr/bin/env python3
"""Generate Jellyseerr-ready curated movie CSVs from Wikidata.

This script writes reviewable CSV lists only. It does not create Jellyseerr
requests; use scripts/request-jellyseerr-list.py after reviewing the output.
"""

from __future__ import annotations

import argparse
import csv
import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


SPARQL_ENDPOINT = "https://query.wikidata.org/sparql"
USER_AGENT = "mediastack-curated-list-generator/1.0 (local personal media list)"

DEFAULT_OUTPUT_DIR = Path("docs/lists")

HITCHCOCK_CSV = "alfred-hitchcock-filmography.csv"
HITCHCOCK_UNAVAILABLE_CSV = "alfred-hitchcock-unavailable-in-tmdb.csv"
BEST_ACTOR_CSV = "best-actor-nominated-films.csv"
BEST_ACTOR_UNAVAILABLE_CSV = "best-actor-nominated-films-unavailable-in-tmdb.csv"


HITCHCOCK_QUERY = """
SELECT ?film ?filmLabel ?tmdb (MIN(?date) AS ?firstDate) WHERE {
  ?film wdt:P31/wdt:P279* wd:Q11424;
        wdt:P57 wd:Q7374;
        rdfs:label ?filmLabel.
  FILTER(LANG(?filmLabel) = "en")
  OPTIONAL { ?film wdt:P4947 ?tmdb. }
  OPTIONAL { ?film wdt:P577 ?date. }
}
GROUP BY ?film ?filmLabel ?tmdb
ORDER BY ?firstDate ?filmLabel
"""


BEST_ACTOR_QUERY = """
SELECT ?film ?filmLabel ?tmdb (MIN(?date) AS ?firstDate)
       (GROUP_CONCAT(DISTINCT ?actorLabel; separator=", ") AS ?actors) WHERE {
  ?actor p:P1411 ?nomStmt;
         rdfs:label ?actorLabel.
  ?nomStmt ps:P1411 wd:Q103916;
           pq:P1686 ?film.
  ?film rdfs:label ?filmLabel.
  FILTER(LANG(?actorLabel) = "en")
  FILTER(LANG(?filmLabel) = "en")
  OPTIONAL { ?film wdt:P4947 ?tmdb. }
  OPTIONAL { ?film wdt:P577 ?date. }
}
GROUP BY ?film ?filmLabel ?tmdb
ORDER BY ?firstDate ?filmLabel
"""


@dataclass(frozen=True)
class CsvRow:
    rank: int
    title: str
    year: str
    tmdb_id: str
    notes: str


def sparql(query: str, timeout: float, retries: int) -> list[dict[str, dict[str, str]]]:
    url = SPARQL_ENDPOINT + "?" + urlencode({"query": query, "format": "json"})
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/sparql-results+json"})
    for attempt in range(1, retries + 1):
        try:
            with urlopen(request, timeout=timeout) as response:
                payload = json.loads(response.read().decode("utf-8"))
            return payload["results"]["bindings"]
        except HTTPError as exc:
            if exc.code != 429 or attempt == retries:
                raise
            retry_after = exc.headers.get("Retry-After")
            delay = int(retry_after) if retry_after and retry_after.isdigit() else 65
            print(
                f"Wikidata rate-limited the query; waiting {delay}s before retry {attempt + 1}/{retries}.",
                flush=True,
            )
            time.sleep(delay)
    raise RuntimeError("unreachable SPARQL retry state")


def value(binding: dict[str, dict[str, str]], key: str) -> str:
    return binding.get(key, {}).get("value", "").strip()


def year_from_date(date_value: str) -> str:
    return date_value[:4] if date_value else ""


def write_rows(path: Path, rows: list[CsvRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["rank", "title", "year", "tmdb_id", "notes"])
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    "rank": row.rank,
                    "title": row.title,
                    "year": row.year,
                    "tmdb_id": row.tmdb_id,
                    "notes": row.notes,
                }
            )


def dedupe_by_tmdb_or_title(rows: list[CsvRow]) -> list[CsvRow]:
    seen: set[str] = set()
    deduped: list[CsvRow] = []
    for row in rows:
        key = f"tmdb:{row.tmdb_id}" if row.tmdb_id else f"title:{row.title.lower()}:{row.year}"
        if key in seen:
            continue
        seen.add(key)
        deduped.append(row)
    return [CsvRow(i + 1, row.title, row.year, row.tmdb_id, row.notes) for i, row in enumerate(deduped)]


def split_requestable(rows: list[CsvRow]) -> tuple[list[CsvRow], list[CsvRow]]:
    requestable = [row for row in rows if row.tmdb_id]
    unavailable = [row for row in rows if not row.tmdb_id]
    return (
        [CsvRow(i + 1, row.title, row.year, row.tmdb_id, row.notes) for i, row in enumerate(requestable)],
        [CsvRow(i + 1, row.title, row.year, row.tmdb_id, row.notes) for i, row in enumerate(unavailable)],
    )


def hitchcock_rows(timeout: float, retries: int) -> list[CsvRow]:
    rows: list[CsvRow] = []
    for index, binding in enumerate(sparql(HITCHCOCK_QUERY, timeout, retries), start=1):
        title = value(binding, "filmLabel")
        if not title or title.startswith("Q"):
            continue
        rows.append(
            CsvRow(
                rank=index,
                title=title,
                year=year_from_date(value(binding, "firstDate")),
                tmdb_id=value(binding, "tmdb"),
                notes="Directed by Alfred Hitchcock; source: Wikidata Q7374 director film query",
            )
        )
    return dedupe_by_tmdb_or_title(rows)


def best_actor_rows(timeout: float, retries: int) -> list[CsvRow]:
    rows: list[CsvRow] = []
    for index, binding in enumerate(sparql(BEST_ACTOR_QUERY, timeout, retries), start=1):
        title = value(binding, "filmLabel")
        actors = value(binding, "actors")
        if not title or title.startswith("Q"):
            continue
        rows.append(
            CsvRow(
                rank=index,
                title=title,
                year=year_from_date(value(binding, "firstDate")),
                tmdb_id=value(binding, "tmdb"),
                notes=(
                    "Film associated with Academy Award for Best Actor nomination"
                    + (f"; nominated actor(s): {actors}" if actors else "")
                    + "; source: Wikidata P1411 Academy Award for Best Actor with P1686 film qualifier"
                ),
            )
        )
    return dedupe_by_tmdb_or_title(rows)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--retries", type=int, default=2)
    parser.add_argument(
        "--list",
        choices=["all", "hitchcock", "best-actor"],
        default="all",
        help="Which list to generate.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_dir = args.output_dir

    if args.list in {"all", "hitchcock"}:
        requestable, unavailable = split_requestable(hitchcock_rows(args.timeout, args.retries))
        write_rows(output_dir / HITCHCOCK_CSV, requestable)
        write_rows(output_dir / HITCHCOCK_UNAVAILABLE_CSV, unavailable)
        print(f"Wrote {len(requestable)} requestable Hitchcock rows to {output_dir / HITCHCOCK_CSV}")
        print(f"Wrote {len(unavailable)} Hitchcock rows without TMDB IDs to {output_dir / HITCHCOCK_UNAVAILABLE_CSV}")

    if args.list in {"all", "best-actor"}:
        requestable, unavailable = split_requestable(best_actor_rows(args.timeout, args.retries))
        write_rows(output_dir / BEST_ACTOR_CSV, requestable)
        write_rows(output_dir / BEST_ACTOR_UNAVAILABLE_CSV, unavailable)
        print(f"Wrote {len(requestable)} requestable Best Actor rows to {output_dir / BEST_ACTOR_CSV}")
        print(f"Wrote {len(unavailable)} Best Actor rows without TMDB IDs to {output_dir / BEST_ACTOR_UNAVAILABLE_CSV}")

    print("Review the generated CSVs, then request them with scripts/request-jellyseerr-list.py.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
