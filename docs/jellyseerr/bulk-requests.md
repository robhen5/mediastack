# Jellyseerr Bulk Requests

Use `scripts/request-jellyseerr-list.py` to request curated movie lists through
Jellyseerr without clicking each movie manually.

The script is safe by default:

- Dry-run unless `--apply` is passed.
- Matches exact title and release year where possible.
- Skips ambiguous matches unless `--allow-ambiguous` is passed.
- Processes in batches with `--limit`.

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
