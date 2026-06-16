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
