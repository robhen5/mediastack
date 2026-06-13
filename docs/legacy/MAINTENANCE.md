# Mediastack — Maintenance Runbook

Day-to-day operational reference. For the original build process, see
[SETUP.md](SETUP.md).

---

## Quick reference: ports and URLs

All services bind to `0.0.0.0` so they're reachable from any device on
your LAN at `http://<host-LAN-IP>:<port>`. Find your host IP with
`hostname -I`.

| Service | Port | What for | Phase |
|---|---|---|---|
| Jellyfin | 8096 | Watch media (you + household) | 1 |
| Jellyseerr | 5055 | Request content (you + household) | 1 |
| qBittorrent | 8081 | Torrent client admin | 1 |
| Sonarr | 8989 | TV / anime automation | 1 |
| Radarr | 7878 | Movie automation | 1 |
| Prowlarr | 9696 | Indexer manager | 1 |
| Bazarr | 6767 | Subtitle automation | 1 |
| FlareSolverr | 8191 | Cloudflare challenge solver (background) | 1 |
| Gluetun | — | VPN gateway (no UI) | 1 |
| Recyclarr | — | TRaSH-guide profile sync (cron, no UI) | 4 |
| autobrr | 7474 | Private-tracker instant grabs (idle until private trackers join) | 4 |
| cross-seed | 2468 | Multi-tracker seeding | 4 |
| qbitmanage | — | qBit cleanup / ratio enforcement (cron, no UI) | 4 |
| unpackerr | — | Auto-extract archived releases (no UI) | 4 |
| LazyLibrarian | 5299 | Book acquisition (impaired — manual ingest workflow) | 5 |
| Calibre-Web Automated | 8083 | Ebook reader / library | 5 |
| Audiobookshelf | 13378 | Audiobook server | 5 |
| Suwayomi-Server | 4567 | Manga scraping (Tachiyomi extensions) | 6 |
| Kavita | 5000 | Manga reader / library / OPDS | 6 |
| **Caddy** | **80** | Reverse proxy — root URL family uses (`http://<host-LAN-IP>/`) | 7 |
| Homepage | 3000 | Status dashboard (also served via Caddy at `/`) | 7 |
| ntfy | 2586 | Push-notification bus (subscribe in the ntfy phone app) | 8 |
| Cleanuparr | 11011 | Removes stalled / dead downloads, re-triggers *arr search | 8 |
| Jellystat | 3010 | Jellyfin viewing statistics (host 3010 → container 3000) | 8 |
| jellystat-db | — | Postgres backing Jellystat (no UI) | 8 |
| Uptime-Kuma | 3001 | Service health dashboard + alerting (pages ntfy) | 8 |
| Diun | — | "Image update available" notifier (cron, no UI, pings ntfy) | 8 |

**In-container references** (for one service to talk to another inside
Docker's network — used when wiring apps together):
`http://<container-name>:<container-internal-port>`. Examples:
`http://sonarr:8989`, `http://radarr:7878`, `http://gluetun:8080` (qbit
WebUI from sibling containers — §8 gotcha). **Never use `localhost` for
inter-container links.**

Torrent peer port: **6881 TCP + UDP** through gluetun. Forwarded port
(rotates) is synced automatically — see §"Forwarded-port sync" below.

---

## Update images

Run periodically (every 4–8 weeks is plenty):

```bash
/opt/mediastack/scripts/update.sh
```

What it does:
1. `docker compose pull` — downloads newer image versions
2. `docker compose up -d` — recreates containers whose image changed
3. Detects if gluetun was recreated; if so, runs
   `docker compose up -d --force-recreate qbittorrent` (otherwise qbit's
   network namespace stays stale and it has no internet)
4. `docker image prune -f` — frees disk from old versions
5. Prints final container status

**Before running**, glance at release notes for any container you care
about. Most updates are uneventful. Watch for:
- **gluetun** — sometimes renames env vars; check the changelog if Proton
  stops connecting after an update.
- **linuxserver/* images** — generally safe; their `latest` tag is rolling.

Watch the output for any container stuck in `Restarting` — that's the
signal to look at `docker logs <container>`.

---

## Delete content

Removing a series or movie cleanly is a two-step process because the
file exists in two places (the seeding copy in `torrents/`, the library
copy in `media/`) via a hardlink.

### Series (Sonarr) or movie (Radarr)
1. Sonarr → Series → click the show → ☰ → **Delete Series**
   (or Radarr → Movies → click the movie → ☰ → **Delete**)
2. In the dialog, check:
   - ☑ **Delete files from disk** — removes `/data/media/.../...mkv`
   - ☑ **Add List Exclusion** — prevents Jellyseerr from re-adding it
     if someone requests it again
3. Bazarr drops subtitle tracking on its next Sonarr/Radarr sync (~hour).
   Jellyfin removes the entry on its next library scan.
4. Disk space is **not yet freed** — qBittorrent still has a hardlink in
   `/data/torrents/`. The file's inode now has `links=1` instead of `2`.

### qBittorrent (frees the actual disk)
1. qBittorrent (`localhost:8081`) → find the torrent → right-click →
   **Delete** → ☑ **Delete files**
2. Now disk space is freed.

When/how to do step 2:
- **Immediately** — if you don't care about seeding back.
- **After hitting a ratio target** — community-friendly default.
- **Automated** — Phase 4's `qbitmanage` watches ratio/seed-time and
  auto-deletes torrents that hit your configured threshold. Once that's
  set up, you only do step 1.

**Do not** delete on the qBittorrent side first while leaving Sonarr's
copy intact — Sonarr will get confused on its next scan and may try to
re-grab.

---

## Backups

Your `/opt/mediastack/config/` directory holds every app's SQLite database,
all API keys, your indexer logins, your Bazarr profile, qBit's password
hash, etc. Lose it and you redo the day-long config dance. Backups are
the difference between "machine died" being annoying vs catastrophic.

### What to back up (and what NOT to back up)

| Backed up where | What | Why |
|---|---|---|
| **Git** | `docker-compose.yml`, `SETUP.md`, `MAINTENANCE.md`, `.gitignore`, `scripts/` | The *recipe* — small, text, versioned, easy to clone |
| **Tar (offline)** | `config/`, `.env` | The *instance* — secrets + runtime state, NEVER in git |
| **Not backed up** | `data/` | Too large (media/torrents). Media is recoverable via the *arrs; torrents are recoverable from the trackers |

### Periodic config backup

Run every 1–2 weeks (or after a big config change):

```bash
mkdir -p ~/backups
tar -czf ~/backups/mediastack-config-$(date +%Y%m%d).tar.gz \
  --exclude='config/caddy/data/caddy' \
  --exclude='config/caddy/config/caddy' \
  --exclude='config/jellystat-db' \
  --exclude='config/diun' \
  --exclude='config/ntfy/attachments' \
  --exclude='config/ntfy/cache.db' \
  -C /opt/mediastack config .env
```

The `--exclude` lines skip container-owned, **regenerable** state — all
root/system-owned (so they'd force a `sudo`) and none of it is recipe:
- **Caddy** `data/caddy` + `config/caddy` — TLS/runtime state, rebuilt
  from the Caddyfile on restart.
- **jellystat-db** — the Postgres *data dir*. Two reasons to skip: it's
  only viewing stats (Jellystat re-syncs from Jellyfin), and raw-copying a
  *live* Postgres directory can produce an inconsistent/corrupt dump
  anyway. If you ever want real stats backups, use Jellystat's own
  Settings → Backup feature instead of file-copying this dir.
- **diun** — just tracks which image versions it has seen; rebuilds itself
  (worst case: one extra "new image" notification after a restore).
- **ntfy** `attachments` + `cache.db` — ephemeral cached messages.

`tar: ... ipc-socket: socket ignored` is a harmless warning (you can't
archive a live socket), not the cause of any failure — the failure was
purely the permission-denied lines above, which these excludes resolve.

Then **copy that tarball off the machine**. Options:
- USB drive plugged in occasionally
- Another machine on your LAN (`scp`, `rsync`)
- Cloud (encrypted: `gpg -c` first, then upload — config holds your
  WireGuard private key)
- Headscale-connected device

Rotate: keep the last ~6 tarballs, delete older. A monthly cron entry
keeps backups current automatically.

### Restore on a new machine

1. Install Docker + docker-compose (`pacman -S docker docker-compose docker-buildx`)
2. `sudo systemctl enable --now docker.service`
3. `sudo usermod -aG docker $USER` then re-login
4. Clone the git repo: `git clone <your-remote> /opt/mediastack`
5. Untar the config + .env on top of it:
   `tar -xzf mediastack-config-YYYYMMDD.tar.gz -C /opt/mediastack`
6. Reconstruct the `/data` directory tree (empty is fine; downloads
   refill it):
   `mkdir -p /opt/mediastack/data/{torrents/{tv-sonarr,radarr,incomplete},media/{tv,anime,movies,anime-movies}}`
7. `cd /opt/mediastack && docker compose up -d`

Within ~minute the stack is back online at the same state. Sonarr will
re-detect existing library files and resume monitoring; qBittorrent will
resume seeding torrents that still have their `data/torrents/` files.

---

## Git setup

The project is git-initialized. The `.gitignore` excludes:
- `.env` (secrets — WireGuard key, qBit creds)
- `config/` (runtime state, app databases, API keys)
- `data/` (media payload — far too large)

Tracked files:
- `docker-compose.yml`
- `SETUP.md`, `MAINTENANCE.md`
- `.gitignore`
- `scripts/` (update.sh, sync-qbit-port.sh, gluetun-port-hook.sh, systemd units)

Commit when you change any of the above. Typical cadence:
- After editing `docker-compose.yml` (new service, env var change, etc.)
- After tweaking a script
- After updating documentation

```bash
cd /opt/mediastack
git add -A
git status                    # confirm no .env, config/, or data/ snuck in
git commit -m "describe the change"
```

### Pushing to a remote (optional but recommended)

For real off-machine recovery you want the git repo on a forge:

- **GitHub private repo** (free, 2FA required)
- **Codeberg / GitLab / self-hosted Gitea** — alternatives

```bash
# Once you have a remote URL:
git remote add origin <your-remote-url>
git branch -M main
git push -u origin main
```

After that, `git push` after each commit gets a copy off your disk.
Combined with the periodic tar backup of `config/`, full disaster
recovery is covered.

---

## Health checks

Quick monthly glance:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -v ' Up '
```

Anything that prints (other than the header) is in a bad state. For each
problem container:

```bash
docker logs <name> 2>&1 | tail -50
```

Disk space:

```bash
du -sh /opt/mediastack/data/{torrents,media,books,audiobooks} 2>/dev/null
df -h /home
```

Once `/home` is above ~80% full, time to delete shows or expand storage.

VPN sanity (occasional, especially after gluetun updates):

```bash
docker exec gluetun wget -qO- https://ipinfo.io/ip                  # should be NL
curl -4 -s https://ipinfo.io/ip                                     # your real IP
docker exec gluetun cat /tmp/gluetun/forwarded_port                 # current forwarded port
```

---

## Forwarded-port sync

qBittorrent's listening port has to match the port ProtonVPN forwards
via NAT-PMP, which rotates whenever gluetun reconnects. Two mechanisms
keep them in sync:

1. **Hook (instant)** — `scripts/gluetun-port-hook.sh` runs inside
   gluetun the moment NAT-PMP returns a new port. Configured via
   `VPN_PORT_FORWARDING_UP_COMMAND` env in `docker-compose.yml`. Updates
   qBit's listen_port via the WebUI API. Covers the common case.

2. **Polling (safety net)** — `scripts/sync-qbit-port.sh` runs on a
   systemd timer every 5 minutes, doing the same check from outside.
   Catches the rare case where the hook missed (e.g., gluetun container
   restart leaves qBit's namespace handle stale; the hook runs but qBit
   isn't reachable until you `docker compose up -d --force-recreate
   qbittorrent`).

Check the timer:

```bash
systemctl list-timers sync-qbit-port.timer --no-pager
journalctl -u sync-qbit-port.service -n 20 --no-pager
```

If the timer is missing entirely (e.g., new machine after a restore),
reinstall:

```bash
sudo install -m644 /opt/mediastack/scripts/sync-qbit-port.service /etc/systemd/system/
sudo install -m644 /opt/mediastack/scripts/sync-qbit-port.timer   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now sync-qbit-port.timer
```

---

## Manual book / audiobook ingest

LazyLibrarian's auto-grab path for ebooks is currently impaired (Anna's
Archive moved to a paid Member Key for their fast-download API; LibGen
mirrors are unstable and LL's scraper doesn't match current page
formats). The library *management* automation still works — only the
acquisition step is manual.

### Ebook workflow
1. Find the title on https://annas-archive.li (or the current live Anna
   mirror — see [Anna's Archive Wikipedia page](https://en.wikipedia.org/wiki/Anna%27s_Archive)
   for the latest list).
2. Filter to your language + preferred format (**EPUB** > MOBI > PDF).
3. Use Anna's free "Slow Partner Server" path — captcha + ~30 sec wait,
   then download.
4. Drop the file into:
   ```
   /opt/mediastack/data/books/ingest/
   ```
5. CWA picks it up automatically within ~30 seconds:
   - Reads EPUB/MOBI internal tags for title, author, ISBN, cover
   - Renames + moves to `/opt/mediastack/data/books/library/<Author>/<Title>/`
   - Adds to its database; fetches missing cover art from Google Books
6. Appears in CWA's web UI (`http://localhost:8083`) and in any OPDS-
   subscribed e-reader.

### Audiobook workflow
Audiobookshelf is stricter about layout — it does NOT auto-organize like
CWA, so you create the folder structure yourself before dropping the file.

1. Find the audiobook on Anna's Archive (same site, different filter).
   Format: **M4B** (single-file with chapter markers) preferred, or
   **MP3** set as fallback.
2. Manually create the destination directory:
   ```
   mkdir -p /opt/mediastack/data/audiobooks/<Author Name>/<Book Title>/
   ```
3. Drop the audio file(s) inside that folder.
4. Audiobookshelf (`http://localhost:13378`) scans on its watch timer and
   detects new content within a few minutes. Metadata comes from Audible.

Note: some Anna audiobook downloads are zip archives with the folder
structure already correct. Just unzip directly into
`/opt/mediastack/data/audiobooks/` and the layout is right out of the box.

### Cheat sheet

| You have | Drop into | Picked up by |
|---|---|---|
| `.epub` / `.mobi` / `.pdf` (flat file ok) | `data/books/ingest/` | CWA |
| `.m4b` or `.mp3` set | `data/audiobooks/<Author>/<Title>/` | Audiobookshelf |

### Re-trying auto-grab later
If Anna's free auto-API ever comes back, or if you decide to spring for
their $5/mo Member Key, the LazyLibrarian config is already wired —
nothing to redo. The Member Key field in LL → Settings → Providers →
Anna is the one place to paste the key when you have it.

---

## Subtitle drift handling

Bazarr-fetched subtitles sometimes don't sync to the video properly.
The two failure modes:

1. **Constant offset** — subtitle is consistently N seconds early/late
   across the whole runtime. Usually a release-mismatch (the sub was
   timed for a different cut than the video).
2. **Linear drift / scaling** — sub is fine at the start but drifts
   progressively over the runtime. Almost always a **framerate
   mismatch** — common scenario is a PAL-sourced subtitle (25 fps)
   matched to a Blu-ray (23.976 fps). The PAL video is sped up ~4% so
   PAL-timed subs run progressively ahead.

Bazarr's filename convention (`.en.hi.srt`, `Bluray-1080p` etc.) is a
trap — those names come from the *video file* the sub was matched to,
not the source the sub was originally timed against. A sub renamed
`...Bluray-1080p.en.hi.srt` could have been lifted off a 25-fps DVD
five seconds ago.

### Built-in auto-sync (recommended one-time setup)

Bazarr ships with the `ffsubsync` algorithm built in. It analyzes the
video's audio waveform, detects where speech happens, and rescales the
subtitle to match — handling both constant offset and linear drift
automatically. Disabled by default; turn it on once and it runs on
every subtitle download:

**Bazarr → Settings → Subtitles → Sub-Sync section:**

| Setting | Value | Why |
|---|---|---|
| **Always use Sub-Sync** | **ON** | Runs ffsubsync on every newly-downloaded subtitle |
| Or: **Use Sub-Sync threshold** | ON, threshold 90 (episodes) / 70 (movies) | Only runs sync when match confidence is below the threshold — saves CPU on high-confidence matches that probably don't need it |

Pick one (not both). Blanket "Always" is the safer choice — a few seconds
of CPU per download is invisible cost; never debugging a drifting sub
again is real value.

### Manual per-subtitle sync (when auto-sync misses one)

If a subtitle still drifts after auto-sync (rare but happens with low-
audio scenes), you can re-run subsync from Bazarr's UI per-file:

1. Bazarr → Series (or Movies) → click into the title → click the episode/
   movie row → click into the subtitle entry
2. Click the **"Sync subtitles"** button (translation-icon, looks like a
   pair of bidirectional arrows)
3. Choose alignment options if prompted (default settings work for almost
   everything)
4. Wait — Bazarr re-runs ffsubsync and overwrites the file

### Manual fix from CLI (last resort)

If Bazarr's built-in sync can't handle a specific file (edge case),
ffsubsync is also available on the host:

```bash
# Install once if not present
pip install ffsubsync   # requires ffmpeg in PATH (already installed via mediastack)

# Run against the actual video
ffsubsync "/path/to/Movie (Year) Bluray-1080p.mp4" \
  -i "/path/to/Movie (Year) Bluray-1080p.en.srt" \
  -o "/path/to/Movie (Year) Bluray-1080p.synced.srt"
```

Then rename the `.synced.srt` over the original. ffsubsync handles
both linear drift and offset automatically; for clean linear cases it
usually nails it on the first run.

Alternative tools that solve the same problem with the same usage
pattern: [`alass`](https://github.com/kaegi/alass) or
[Subtitle Edit](https://www.nikse.dk/SubtitleEdit) (GUI, lets you do
visual sync by anchoring first/last spoken line).

---

## Manga: Suwayomi extensions + Kavita library

Suwayomi (port 4567) downloads chapters into `/data/manga/<Series>/<Chapter N>.cbz`.
Kavita (port 5000) reads from the same folder and serves a web reader.

### Currently-configured extension repositories

Add these in **Suwayomi → Browse → Extension Repositories**:

| Repo | URL |
|---|---|
| keiyoushi (primary) | `https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json` |
| yuzono (mirror + restored DMCA'd sources) | `https://raw.githubusercontent.com/yuzono/manga-repo/repo/index.min.json` |
| komizoku (broadest catalog) | `https://raw.githubusercontent.com/komizoku/manga-repo/repo/index.min.json` |

### Currently-installed sources

| Type | Source | Notes |
|---|---|---|
| English aggregator | MangaDex | Largest catalog, best metadata |
| English aggregator | ComicK Fanmade | Community rebuild of ComicK (DMCA'd 2025) |
| English aggregator | Weeb Central | MangaSee successor |
| English aggregator | Asura Scans | Strong for current scanlations |
| English alt-host | Bbato | Bato.to community rebuild |
| English legal-purchase | BookWalker Global | Official; for legally bought titles |
| JP official publisher | Comic FUZ | Hakusensha/Akita |
| JP official publisher | Magazine Pocket | Kodansha |
| JP official publisher | Shonen Jump+ | Shueisha |
| JP scraper aggregator | Rawkuma | Broad backlog catalog |
| JP scraper aggregator | Sen Manga | Stable backup aggregator |

### Adding new sources later

If you ever want more (e.g. additional language scrapers):

1. Suwayomi → **Settings → Browse → Languages** → enable the language you want
   (extensions are language-filtered by default — that's why Japanese sources
   are hidden unless `日本語` is enabled).
2. Browse → Extensions tab → scroll to find new options after the language toggle
3. Install → it appears under Browse → Sources

### When a source breaks

Extensions break periodically (sites move, change HTML, get DMCA'd). The pattern:

- **First**: Browse → Extensions tab → check if there's a newer version of the
  failing extension. Update if so.
- **Bato.to specifically**: domain rot — open the extension's gear icon, change
  the default domain to `bato.si` (or whichever is current). The default rotates.
- **If a source disappears from a repo**: try yuzono or komizoku repos — they
  often carry DMCA-restored versions named slightly differently
  (`Comick Fanmade` vs `Comick`, `Bbato` vs `Bato.to`).
- **If a publisher app stops working**: usually a sign Shueisha/Kodansha pushed
  an API change. Wait a few days; the keiyoushi maintainers typically patch within
  a week. Or sub to https://github.com/keiyoushi/extensions for release notifs.

### Manga deletion (when you're done with a series)

Different from video — no *arr layer here. Just delete from disk:

> ⚠️ **`rm -rf` is irreversible.** Double-check the trailing series
> name before pressing Enter — a missing `<Series Title>` segment
> deletes the whole manga library. Prefer Kavita's per-series delete
> button (`Manga library → ⋯ → Delete`) and only fall back to `rm`
> when you've confirmed the exact path with `ls`. See `docs/SAFETY.md`
> §8 risk #1.

```
rm -rf /opt/mediastack/data/manga/<Series Title>/
```

Suwayomi's library tracker still shows the series (it tracks separately).
Remove from Suwayomi: Library → click series → bookmark icon to unbookmark.

Kavita: Manga library → click ⋯ menu next to the series → Delete (DB-only;
doesn't touch files, but if files are already gone via rm it'll show empty).

---

## Household URL layer (Caddy + Homepage)

Family bookmarks **one URL**: `http://<host-LAN-IP>/` → loads the Homepage
dashboard, which has cards linking to every household-facing service.

### What's exposed and how

| Service | URL family uses |
|---|---|
| Homepage (the dashboard) | `http://<LAN-IP>/` |
| Jellyfin | `http://<LAN-IP>/jellyfin/web/` (Caddy path) — Jellyfin's Base URL must be set to `/jellyfin` in Dashboard → Networking |
| Jellyseerr | `http://<LAN-IP>:5055` (direct — Caddy does NOT subpath-proxy this; Jellyseerr's redirect handling breaks under subpaths) |
| Kavita | `http://<LAN-IP>:5000` (direct, linked from Homepage card) |
| Audiobookshelf | `http://<LAN-IP>:13378` (direct, linked from Homepage card) |
| Calibre-Web | `http://<LAN-IP>:8083` (direct, linked from Homepage card) |

Admin tools (Sonarr, Radarr, Prowlarr, Bazarr, qBittorrent, LazyLibrarian,
Suwayomi, autobrr) are intentionally **NOT linked from the Homepage** for
non-admins to discover, and intentionally NOT reverse-proxied. They stay
on their raw ports for the operator to access from the host machine.

### TV apps + casting (Jellyfin on the big screen)

The web player's "Cast" button only lists active Jellyfin sessions +
detected Chromecasts — it is NOT a general cast-to-anything button. To put
Jellyfin on a TV:

1. **Install the native Jellyfin app on the TV** (best): Google Play
   (Android/Google TV, Shield), Amazon Appstore (Fire TV), **Swiftfin**
   (Apple TV), or the Roku channel. Samsung/LG built-in apps are weak — use
   a ~$30–40 Fire Stick / Chromecast w/ Google TV instead.
2. **Sign in** with the household member's Jellyfin account and this server
   URL — **the base path is required**:

   ```
   http://<LAN-IP>:8096/jellyfin
   ```

   ⚠️ **Every Jellyfin client needs the `/jellyfin` suffix** (TV app, phone
   app, Jellystat, Homepage widget). Because Jellyfin's Base URL is
   `/jellyfin`, pointing a client at the bare `:8096` makes it fetch the
   web page (HTML) instead of API JSON → errors like *"can't fetch proper
   json"* / *"not a Jellyfin server."* Add `/jellyfin` and it connects.
3. Once the TV app is signed in, the **phone's** Jellyfin Cast button will
   see it — browse on the phone, play on the TV.

Requires UFW to allow 8096 from the LAN (already set — see below). The TV
must be on the same `192.168.1.0/24` wifi.

### Jellyfin auto-refresh on import (no manual rescan)

Jellyfin's own library scan is on a timer and its filesystem-watching is
unreliable through Docker bind mounts — so new content used to need a
manual refresh. Fixed by having **Sonarr + Radarr trigger a targeted
Jellyfin scan on import**: Settings → Connect → **Emby / Jellyfin**
connection named "Jellyfin", with:
- Host `jellyfin`, Port `8096`, Use SSL off, **URL Base `/jellyfin`**
  (the base-path rule again — without it the connection test fails)
- API Key = `JELLYFIN_APIKEY`
- **Update Library ON**, Notify off
- Triggers: On Import, On Upgrade, On Rename, On Rename, file-delete
  events (so Jellyfin stays accurate on removals too)

New episodes/movies then appear within seconds for everyone, hands-off.
This lives in the (gitignored) Sonarr/Radarr config, so it's captured by
the tar backup and restored with it; if rebuilding from scratch, recreate
both connections as above (or re-POST via each app's
`/api/v3/notification`). Covers video only — Kavita (manga) scans on its
own schedule and Calibre-Web Automated auto-imports its ingest folder.

### LAN-only enforcement (UFW)

For Homepage / Caddy + the individual service ports to be reachable by
household devices, UFW must allow them from the LAN subnet only:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 80 proto tcp   # Caddy → Homepage + /jellyfin
sudo ufw allow from 192.168.1.0/24 to any port 5055 proto tcp # Jellyseerr (direct)
sudo ufw allow from 192.168.1.0/24 to any port 8096 proto tcp # Jellyfin (direct, for the native mobile app)
sudo ufw allow from 192.168.1.0/24 to any port 5000 proto tcp # Kavita
sudo ufw allow from 192.168.1.0/24 to any port 13378 proto tcp # Audiobookshelf
sudo ufw allow from 192.168.1.0/24 to any port 8083 proto tcp # Calibre-Web
```

The `from 192.168.1.0/24` clause restricts each rule to your LAN
subnet — outside-the-house traffic (if it ever reached the host
via misconfigured port forwarding) still gets bounced.

External access from outside the LAN: route via Tailscale/headscale,
not by exposing ports to the internet.

**ntfy is the one Phase 8 service that needs a UFW rule** — the phone app
subscribes over the LAN, so it must reach port 2586:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 2586 proto tcp # ntfy (phone app subscribe)
```

The other Phase 8 services (Cleanuparr, Huntarr, Jellystat, Uptime-Kuma)
are operator-only; you reach them from the host itself (`localhost`), so
they need no UFW rule unless you administer from a *second* LAN machine.

---

## Observability layer (Phase 8)

Six services that make the stack self-healing + observable. All admin-only
(not proxied through Caddy). One-time setup for each below.

### ntfy — the alert bus

Everything that wants to page you POSTs to `http://ntfy:2586/<topic>`
(in-container) and you read it on your phone. Topic name is `NTFY_TOPIC`
in `.env` (default `mediastack-alerts`).

1. Install the **ntfy** app (iOS/Android/desktop) or open `http://<LAN-IP>:2586`.
2. Add subscription → **use a self-hosted server** → server
   `http://<LAN-IP>:2586`, topic = your `NTFY_TOPIC`.
3. Test from the host: `curl -d "hello from mediastack" http://localhost:2586/mediastack-alerts`
   → should buzz the phone within a second.

No auth (LAN-only). Anyone on the LAN who knows the topic can read/post —
treat the topic name like a low-value password.

### Cleanuparr — auto-remove stalled / dead downloads

Complements qbitmanage (which handles torrents that downloaded *fine*).
Cleanuparr kills the ones that **never make progress** and tells the *arr
to grab an alternative — this is what fixes the "stalled old movie" case.

Setup at `http://<LAN-IP>:11011`. Add the connections under **Media Apps**:
- **Download Clients** → qBittorrent → host `http://gluetun:8080`, your
  QBIT_USER/QBIT_PASS (the §8 namespace rule — NOT host `qbittorrent`).
  URL Base + External URL blank. Hit **Test** then **Save**.
- **Sonarr** (`http://sonarr:8989` + SONARR_APIKEY, API v4) and **Radarr**
  (`http://radarr:7878` + RADARR_APIKEY, API v3).

Then enable modules deliberately — they are independent, and which ones
you turn on matters because Cleanuparr's scope overlaps qbitmanage's:

| Module | Turn on? | Why |
|---|---|---|
| **Queue Cleaner** | **YES** | The whole point — removes stalled/dead/stuck *in-progress* downloads and triggers a replacement search. qbitmanage does NOT do this. |
| **Seeker** | YES | Missing-item + cutoff-unmet search. This is the built-in **Huntarr replacement** (see below). |
| **Download Cleaner** | **NO** | Ratio / seed-time removal is **qbitmanage's job**. Running both double-manages seeding and — once on AnimeBytes — risks deleting a torrent still inside its required seedtime. Leave OFF; qbitmanage's share-limits are the single source of truth. |
| **Malware Blocker** | optional | Blocks known-malicious torrent hashes. Harmless to enable. |

Queue Cleaner: start with **conservative strikes** (a strike per stalled
check, remove after ~3 strikes) so a slow-but-alive swarm gets grace.

Seeker (the Huntarr replacement): on *public* indexers, aggressive
searching risks rate-limits/bans — heed the in-UI red warning. Keep the
search interval ≥30 min, Round Robin on, "Use Cutoff" OFF (don't chase
upgrades on public trackers). Raise the interval if Prowlarr shows
rate-limit warnings.

(Optional) point Cleanuparr's **Notifications** at ntfy
(`http://ntfy:2586`, your topic) for a ping each time it removes a dead
download.

### Huntarr — SUPERSEDED by Cleanuparr's Seeker (not deployed)

We never needed it. Cleanuparr (v2.9+) ships a built-in **Seeker** module
that does exactly what Huntarr did — missing-item + cutoff-unmet upgrade
searches. Enable Seeker in Cleanuparr instead. (Standalone Huntarr was
also a bad idea: its upstream, plexguide/Huntarr.io, was archived after
the maintainer went "scorched earth" over disclosed security
vulnerabilities and the image was pulled.) Its service block is left
commented in `docker-compose.yml` purely as a historical marker.

### Jellystat — viewing statistics

Needs `JELLYFIN_APIKEY` in `.env` (create in Jellyfin → Dashboard → API
Keys → +). At `http://<LAN-IP>:3010`:
1. First run → create a Jellystat admin login (its own, separate account).
2. Settings → add Jellyfin server: URL `http://jellyfin:8096`, the API key.
3. Run an initial sync. Stats backfill from Jellyfin's activity log.

The same `JELLYFIN_APIKEY` also lights up the Homepage Jellyfin widget.

### Uptime-Kuma — health dashboard + central alerting

At `http://<LAN-IP>:3001`: create an admin login (its own account), then:

1. **Settings → Notifications → Setup Notification → type "ntfy"**:
   - ntfy URL `http://ntfy:2586`, topic = your `NTFY_TOPIC`
   - tick **"Default enabled"** + **"Apply on all existing monitors"** so
     you don't have to attach it per-monitor
   - **Test** → phone should buzz.
2. Add one **monitor per service**. Uptime-Kuma runs on the compose
   network, so use **container-internal** URLs (it resolves container
   names; qBit + LazyLibrarian go via `gluetun`). Monitor type **HTTP(s)**,
   and under Advanced set **Accepted Status Codes = `200-399`** plus add
   **`401`** for the *arrs (their root may demand auth):

   | Monitor | URL |
   |---|---|
   | Jellyfin | `http://jellyfin:8096/jellyfin/health` |
   | Jellyseerr | `http://jellyseerr:5055` |
   | Sonarr | `http://sonarr:8989` |
   | Radarr | `http://radarr:7878` |
   | Prowlarr | `http://prowlarr:9696` |
   | Bazarr | `http://bazarr:6767` |
   | **qBittorrent (VPN canary)** | `http://gluetun:8080` |
   | LazyLibrarian | `http://gluetun:5299` |
   | Caddy | `http://caddy:80` |
   | Homepage | `http://homepage:3000` |
   | Kavita | `http://kavita:5000` |
   | Suwayomi | `http://suwayomi:4567` |
   | Audiobookshelf | `http://audiobookshelf:80` |
   | Calibre-Web | `http://calibre-web-automated:8083` |
   | Cleanuparr | `http://cleanuparr:11011` |
   | Jellystat | `http://jellystat:3000` |
   | ntfy | `http://ntfy:2586` |

   The **qBittorrent (`gluetun:8080`) monitor is the most valuable** — it's
   your VPN-namespace canary. If gluetun drops or qBit's namespace goes
   stale (the §8 gotcha), this monitor goes red and pages you.

   **Exceptions to the HTTP pattern:**
   - **cross-seed** (`:2468`) has no root route — an HTTP monitor gets a
     404 (false DOWN). Use a **TCP Port** monitor (host `cross-seed`, port
     `2468`) instead, or add `404` to its accepted codes. 404 here just
     means "daemon up, no route at /".
   - autobrr (`:7474`), Caddy (`:80`), Homepage (`:3000`), the *arrs,
     readers, ntfy, Cleanuparr, Jellystat, FlareSolverr all serve a
     200/302/401 at root — the standard accepted codes cover them.
3. Default check interval (60s) is fine. Keep retries at 1-2 so a single
   blip doesn't page you.

This is the central "something broke" alarm — prefer adding monitors here
over wiring per-service notification hooks. If a TCP-only check is easier
for a given service, the "TCP Port" monitor type just checks the port is
open (no status-code fuss).

### Diun — image-update notifications (notify only)

No UI. On its 6-hourly schedule it checks every running container's image
and pings ntfy when a newer one is published. It **does not auto-update** —
that's deliberate, so it never bypasses `update.sh`'s gluetun-aware
recreate of qBit/LazyLibrarian. When Diun pings, run `update.sh` yourself.

---

## Common gotchas (quick reference)

- **qBit shows "Up" but has no internet** → gluetun was restarted; qBit's
  namespace handle is stale. Fix: `docker compose up -d --force-recreate
  qbittorrent`. The update.sh script handles this automatically.

- **qBit WebUI returns bare "Unauthorized"** with no login form → qBit
  host-header validation is rejecting. Should be permanently fixed by
  `WebUI\HostHeaderValidation=false` in
  `config/qbittorrent/qBittorrent/qBittorrent.conf`. If it comes back,
  stop qbit, re-add that line, start qbit.

- **qBit asks for a new password on every restart** → no permanent
  password has been saved. Set one in Tools → Options → WebUI →
  Authentication, and **click the Save button at the bottom of the
  Options dialog** (not just close the tab).

- **Subtitles not downloading for new content** → either the series has
  no language profile assigned (Bazarr → Series → bulk edit → set
  profile), or Bazarr's "Search for Missing Subtitles" task hasn't run
  yet (System → Tasks → run it manually).

- **Movies / Series folders linger after deletion** → enable
  Sonarr/Radarr → Settings → Media Management → Folders → "Delete Empty
  Folders".

- **Caddy `/jellyfin` returns 404** → Jellyfin's Base URL isn't set or
  Jellyfin hasn't been restarted after setting it. Fix: Jellyfin →
  Dashboard → Networking → Base URL = `/jellyfin` → Save →
  `docker restart jellyfin`. The new path takes effect on restart.

- **Jellyseerr "Sign in with Jellyfin" silently fails after setting
  Jellyfin Base URL** → Jellyseerr's saved Jellyfin server entry has
  `urlBase: ""` and can't reach Jellyfin's API at its new prefix. Fix:
  stop Jellyseerr, edit `config/jellyseerr/settings.json`, set
  `jellyfin.urlBase` to `/jellyfin`, restart Jellyseerr.

- **Jellyseerr at `/requests` path redirects to `/login` and 404s** →
  Jellyseerr doesn't support subpath reverse-proxying cleanly (its
  redirect handling strips the prefix). Don't try to route it through
  Caddy at a subpath; link to it directly at port 5055 from Homepage.

- **Homepage shows "API Error" indicator** - docker socket is not reachable. The Homepage container needs `user: "${PUID}:${PGID}"` + `group_add: ["${DOCKER_GID}"]` in compose so the Next.js process has the target host docker group in its supplementary groups.

- **Jellyfin admin password lost (no other admin to reset it from)** →
  `docker stop jellyfin`, `sqlite3
  config/jellyfin/data/data/jellyfin.db "UPDATE Users SET Password=NULL,
  InvalidLoginAttemptCount=0 WHERE Username='<your-user>';"`,
  `docker start jellyfin`. Log in with empty password, set new one
  via Profile → Password immediately.

- **Tar backup fails with `Cannot open: Permission denied` on
  `config/caddy/data/caddy`** → Caddy's container creates that dir as
  root. Either back up with `sudo tar` or add `--exclude` lines for
  `config/caddy/data/caddy` and `config/caddy/config/caddy` to the tar
  command (the docs section "Periodic config backup" shows the
  exclude-flag pattern). Caddy regenerates this state on restart, so
  excluding it is safe.

- **A container's ntfy notification test spins forever / never sends**
  (Uptime-Kuma, Cleanuparr, Diun, etc.) → you used the host LAN IP
  (`http://${LAN_IP:-192.168.1.10}:2586`) as the server URL. Container traffic to the
  host LAN IP arrives from the Docker bridge subnet (172.x), which the UFW
  rule (`from 192.168.1.0/24`) drops → silent timeout. **Containers must
  use the internal URL `http://ntfy:2586`** (Docker network, no UFW). The
  LAN IP is only for the phone app, which is genuinely on the LAN subnet.

- **ntfy phone app won't connect** → it defaults to the public `ntfy.sh`.
  In the app, add the subscription under a **self-hosted server** =
  `http://<LAN-IP>:2586` (plain HTTP, not HTTPS), and confirm UFW allows
  2586 from the LAN subnet. Test with `curl -d test
  http://localhost:2586/<topic>` on the host first.

- **Jellystat syncs all FAIL / no libraries show** → same family as the
  Jellyseerr urlBase gotcha. Because Jellyfin's Base URL is `/jellyfin`,
  its API lives at `http://jellyfin:8096/jellyfin/...`. Jellystat must be
  given the URL **`http://jellyfin:8096/jellyfin`** (with the base path),
  not `http://jellyfin:8096`. Symptom in `docker logs jellystat`:
  `[JELLYFIN-API] : getUsers - <!doctype html>...` (Jellyfin returning its
  web page instead of JSON). Fix the URL in Jellystat → Settings, re-run
  Full Sync. ("Playback Reporting Plugin Sync" failing is separate +
  harmless unless that optional Jellyfin plugin is installed.)

- **`jellystat-db` won't start / Jellystat shows DB errors** → the
  Postgres data dir (`config/jellystat-db`) is created/owned by the
  postgres container; don't `chown` it to 1000. If it was ever started
  with a different password, the volume keeps the *old* one — to reset,
  stop both, `rm -rf config/jellystat-db`, restart (you only lose stats
  history, not media).

- **Cleanuparr deleting torrents that were just slow** → its stall
  threshold is too aggressive. Raise it (Queue Cleaner → max strikes /
  stall time) so a slow-but-alive swarm gets more grace. Note Cleanuparr
  and qbitmanage do NOT conflict: Cleanuparr acts on items still
  *downloading*, qbitmanage on items already *seeding*. Once AB is added,
  make sure Cleanuparr's seed-time/ratio cleaning never removes a torrent
  still inside the tracker's required seedtime (qbitmanage's `private`
  share-limits group is the source of truth for that).

- **Diun pinging about an update for a container you can't update** →
  some images (e.g. a pinned `postgres:16-alpine`) intentionally track a
  major tag; Diun still notes minor bumps. Run `update.sh` to pull, or
  add a `diun.enable=false` label to that service to silence it.
