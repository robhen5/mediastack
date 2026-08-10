# Jellyseerr Bulk Requests

Use `scripts/request-jellyseerr-list.py` to request curated movie lists through
Jellyseerr without clicking each movie manually.

The script is safe by default:

- Dry-run unless `--apply` is passed.
- Matches exact title and release year where possible.
- Skips ambiguous matches unless `--allow-ambiguous` is passed.
- Processes in batches with `--limit`.
- Checks Jellyseerr/Seerr status and skips rows that are already available or
  already tracked unless `--request-existing` is passed.

## API Key

Create or copy a Jellyseerr API key from the Jellyseerr admin settings, then
export it only in your shell session:

```bash
export JELLYSEERR_API_KEY="paste_key_here"
```

Do not commit API keys to `.env`, config templates, or docs.

## AFI 100 Years...100 Movies

The AFI list CSV is stored at:

```text
docs/lists/afi-100-years-100-movies.csv
```

Dry-run the first 10:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://100.115.252.112:5055 \
  --list docs/lists/afi-100-years-100-movies.csv \
  --limit 10
```

Apply the first 10 only after reviewing the dry-run output:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://100.115.252.112:5055 \
  --list docs/lists/afi-100-years-100-movies.csv \
  --limit 10 \
  --apply
```

Continue in batches:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://100.115.252.112:5055 \
  --list docs/lists/afi-100-years-100-movies.csv \
  --start-rank 11 \
  --limit 10
```

If a row is ambiguous, add its TMDB ID to the CSV `tmdb_id` column and rerun.

## Popular American Films From StartingList Top 500

The extracted source list is stored at:

```text
docs/lists/popular-american-top500.csv
```

The Jellyseerr-ready request list is stored at:

```text
docs/lists/popular-american-top500-jellyseerr.csv
```

Dry-run this list in chunks because it has more ambiguous titles and overlaps
with the AFI list:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/popular-american-top500-jellyseerr.csv \
  --limit 25
```

Apply a reviewed chunk:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/popular-american-top500-jellyseerr.csv \
  --limit 25 \
  --apply
```

Continue with `--start-rank` using the `rank` values shown in the output.

## Nicolas Cage Filmography

The Nicolas Cage list contains 120 unique film appearances, including voice
roles, cameos, documentaries in which he appears or narrates, and announced
future films. Producer-only credits without a Cage appearance are excluded.
Every row includes a TMDB ID to avoid ambiguous title/year matching.

```text
docs/lists/nicolas-cage-filmography.csv
```

Dry-run the full list:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/nicolas-cage-filmography.csv
```

Apply only after reviewing the dry-run:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/nicolas-cage-filmography.csv \
  --apply
```

Jellyseerr/Radarr will monitor dated and undated upcoming films until releases
become available. Already available or previously requested films are safe to
rerun through the request endpoint.

## John Wayne Filmography

The John Wayne request list contains 171 TMDB-resolvable film appearances,
including credited and uncredited roles, shorts, documentaries, and the stock
audio appearance listed in his filmography. Three television episodes are
excluded. Two additional film appearances with no TMDB entry are preserved in
`john-wayne-unavailable-in-tmdb.csv` because Jellyseerr cannot request them.

```text
docs/lists/john-wayne-filmography.csv
docs/lists/john-wayne-unavailable-in-tmdb.csv
```

Dry-run the full requestable list:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/john-wayne-filmography.csv
```

Apply after reviewing the dry-run:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/john-wayne-filmography.csv \
  --apply
```

## Academy Award Best Picture Nominees

The Best Picture nominee list contains all 621 films listed in the Academy
Award for Best Picture table, winners included, through the 98th ceremony. Every
row includes a TMDB ID to avoid ambiguous title/year matching.

```text
docs/lists/best-picture-nominees.csv
```

Dry-run the full requestable list:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/best-picture-nominees.csv
```

Apply after reviewing the dry-run:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/best-picture-nominees.csv \
  --apply
```

For a large queue, prefer batches with `--limit` and `--start-rank` so the HDD
does not get flooded with searches/imports all at once.

## Genre Pillars

The genre pillar lists are curated starter expansions for broad movie-library
coverage:

```text
docs/lists/noir-essentials.csv
docs/lists/western-essentials.csv
docs/lists/sci-fi-essentials.csv
docs/lists/horror-classics.csv
docs/lists/seventies-new-hollywood.csv
docs/lists/nineties-crime-thriller.csv
```

Preview all six lists in one pass:

```bash
./scripts/request-genre-pillars.sh
```

Preview a smaller sample from every list:

```bash
LIMIT=10 ./scripts/request-genre-pillars.sh
```

Apply all six lists only after reviewing the dry-run output:

```bash
APPLY=1 ./scripts/request-genre-pillars.sh
```

The wrapper uses `JELLYSEERR_URL` when set, otherwise it defaults to
`http://localhost:5055`. It still relies on `JELLYSEERR_API_KEY` from your shell
session and still uses the duplicate/available-media checks in
`request-jellyseerr-list.py`.

## Big Movie Expansion Waves

Use the wave wrapper when you want to sweep multiple curated lists without
remembering every generated filename. It defaults to dry-run and skips generated
director/award files that do not exist yet.

Preview every known wave:

```bash
./scripts/request-movie-expansion-wave.sh
```

Preview one wave:

```bash
WAVE=directors ./scripts/request-movie-expansion-wave.sh
WAVE=essentials ./scripts/request-movie-expansion-wave.sh
WAVE=disney ./scripts/request-movie-expansion-wave.sh
WAVE=awards ./scripts/request-movie-expansion-wave.sh
WAVE=genres ./scripts/request-movie-expansion-wave.sh
WAVE=actors ./scripts/request-movie-expansion-wave.sh
```

Apply one reviewed wave:

```bash
WAVE=directors APPLY=1 ./scripts/request-movie-expansion-wave.sh
```

Use `LIMIT=25` when you want readable chunks:

```bash
WAVE=awards LIMIT=25 ./scripts/request-movie-expansion-wave.sh
```

Generate director CSVs before running the director wave:

```bash
./scripts/generate-director-deep-dive.sh
```

If Wikidata rate-limits a run, resume from a later director:

```bash
START_AT=coppola ./scripts/generate-director-deep-dive.sh
```

## Deep Essential Waves

These lists are meant for the next layer after obvious canon, AFI, Best
Picture, and major director lists are already mostly covered:

```text
docs/lists/boutique-restoration-essentials.csv
docs/lists/world-cinema-essentials.csv
docs/lists/cult-midnight-essentials.csv
docs/lists/documentary-essentials.csv
docs/lists/animation-essentials.csv
```

Preview the deep essential wave:

```bash
WAVE=essentials ./scripts/request-movie-expansion-wave.sh
```

Apply after reviewing the dry-run:

```bash
WAVE=essentials APPLY=1 ./scripts/request-movie-expansion-wave.sh
```

## Disney and Pixar Classics

The Disney wave includes Disney Animation theatrical features, Pixar feature
films, and a broad Disney family/live-action classics list. It intentionally
does not try to include every Disney Channel movie, acquired studio release, or
Disney-owned label title.

```text
docs/lists/disney-animation-canon.csv
docs/lists/pixar-features.csv
docs/lists/disney-family-classics.csv
```

Preview Disney/Pixar/classics:

```bash
WAVE=disney ./scripts/request-movie-expansion-wave.sh
```

Apply after reviewing the dry-run:

```bash
WAVE=disney APPLY=1 ./scripts/request-movie-expansion-wave.sh
```

## Marvel MCU Projects

The Marvel MCU project list contains requestable MCU films, Marvel Studios
specials, Marvel One-Shots, Marvel Studios/Marvel Television series,
`Agents of S.H.I.E.L.D.`, and the Netflix/Defenders shows. The list supports
both movies and TV through the `media_type` column.

```text
docs/lists/marvel-mcu-projects.csv
docs/lists/marvel-mcu-unavailable-in-tmdb.csv
```

The unavailable CSV preserves announced projects that do not yet have stable
TMDB entries, so the main list can be dry-run and applied without known dead
rows.

Dry-run the full requestable list:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/marvel-mcu-projects.csv
```

Apply after reviewing the dry-run:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/marvel-mcu-projects.csv \
  --apply
```

TV rows request all regular seasons by default. Add `--include-specials` only
if you also want Jellyseerr to request TV season 0 specials.

## Alfred Hitchcock and Best Actor Nomination Lists

These lists are generated from Wikidata into Jellyseerr-ready CSV files. The
generator only writes CSV files; it does not create Jellyseerr requests.

```text
scripts/generate-jellyseerr-curated-lists.py
docs/lists/alfred-hitchcock-filmography.csv
docs/lists/alfred-hitchcock-unavailable-in-tmdb.csv
docs/lists/best-actor-nominated-films.csv
docs/lists/best-actor-nominated-films-unavailable-in-tmdb.csv
```

Generate both lists:

```bash
python3 scripts/generate-jellyseerr-curated-lists.py
```

If Wikidata is rate-limiting, generate one list at a time:

```bash
python3 scripts/generate-jellyseerr-curated-lists.py --list hitchcock
```

```bash
python3 scripts/generate-jellyseerr-curated-lists.py --list best-actor
```

Dry-run Hitchcock:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/alfred-hitchcock-filmography.csv
```

Apply Hitchcock after reviewing the dry-run:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/alfred-hitchcock-filmography.csv \
  --apply
```

Dry-run the Best Actor nomination film list:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/best-actor-nominated-films.csv
```

Apply in batches after reviewing the dry-run:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/best-actor-nominated-films.csv \
  --limit 25 \
  --apply
```

Continue with `--start-rank` using the rank values shown in the output. The
Best Actor list overlaps heavily with the Best Picture list, so already
available or previously requested films are expected and safe to rerun through
the request endpoint.

## Director Filmographies

The curated list generator can also create director filmographies. The starter
set is intentionally sharp and storage-efficient:

- Stanley Kubrick
- Martin Scorsese
- Steven Spielberg
- Akira Kurosawa
- David Fincher

Generate the starter director lists:

```bash
python3 scripts/generate-jellyseerr-curated-lists.py --list director-starters
```

Generate a single director list:

```bash
python3 scripts/generate-jellyseerr-curated-lists.py --list kubrick
```

Available director choices:

```text
kubrick
scorsese
spielberg
kurosawa
fincher
coppola
coen-brothers
billy-wilder
sidney-lumet
john-carpenter
sergio-leone
brian-de-palma
michael-mann
ridley-scott
```

Dry-run a director list:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/stanley-kubrick-filmography.csv
```

Apply after reviewing the dry-run:

```bash
python3 scripts/request-jellyseerr-list.py \
  --url http://localhost:5055 \
  --list docs/lists/stanley-kubrick-filmography.csv \
  --apply
```

The requester now status-checks TMDB-ID rows before posting requests. If a
movie is already available or already tracked in Jellyseerr/Seerr, it is skipped
by default. Use `--request-existing` only if you intentionally want to resend
requests for rows that Seerr already knows about.
