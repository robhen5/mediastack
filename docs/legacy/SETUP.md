# Media Automation Stack — Setup Specification

A spec for Claude Code to provision a self-hosted media stack on **Ubuntu Server Linux**.
Pair this document with the `docker-compose.yml` in the same directory.

---

## 1. Project goal

Build a self-hosted, automated media stack that downloads, organizes, and
serves movies, TV, anime, and books — with a Japanese-study workflow layered
on top, and a privacy-conscious networking posture.

**Three things this system does:**

1. **Media automation** — request a title, the stack finds it, downloads it
   through a VPN, organizes it, and makes it streamable via Jellyfin.
2. **Japanese study** — the operator studies Japanese and watches anime for
   immersion. Subtitles (Japanese + English) are fetched automatically, and
   a browser-based mining workflow (asbplayer + Yomitan + Anki) turns watched
   episodes into study material.
3. **Privacy** — all torrent traffic is forced through a VPN with a kill
   switch; general system DNS is encrypted so the ISP cannot log lookups.

**Operator context for Claude Code:** the operator is an experienced developer
but **new to Docker and self-hosting**. Work methodically. Explain what each
step does. **Verify each phase before moving to the next.** Do not bulk-deploy
all 16 containers at once.

---

## 2. What's in the stack

| Function | Containers |
|---|---|
| VPN gateway | gluetun |
| Download client | qBittorrent (routed through gluetun) |
| Indexers | Prowlarr, FlareSolverr |
| Video automation | Sonarr (TV), Radarr (movies) |
| Subtitles | Bazarr |
| Front-end / server | Jellyseerr, Jellyfin |
| Self-maintenance | Recyclarr, autobrr, cross-seed, qbitmanage, Unpackerr |
| Books (incl. light novels) | LazyLibrarian, Calibre-Web Automated, Audiobookshelf |
| Manga (Phase 6 — planned add-on) | Suwayomi-Server, Kavita |
| Household URL layer (Phase 7) | Caddy, Homepage |
| Observability / self-healing (Phase 8) | Cleanuparr, ntfy, Uptime-Kuma, Jellystat (+Postgres), Diun |

---

## 3. Division of responsibility

### Claude Code handles
- Verifying/installing Docker + Docker Compose
- Creating the folder structure
- Scaffolding the `.env` file (placeholders) and `.gitignore`
- Placing and validating `docker-compose.yml`
- Generating config files where they can be templated
  (recyclarr.yml, cross-seed config, qbit_manage config.yml)
- Writing the forwarded-port automation script (see §7.6)
- Configuring system encrypted DNS (§7.1)
- Bringing containers up phase by phase
- Reading logs and troubleshooting errors
- Running the verification/acceptance tests

### The operator (human) handles — DO NOT attempt these
- ProtonVPN subscription + generating the WireGuard config (private key/address)
- Creating indexer/tracker accounts and obtaining API keys
- All web-UI configuration that requires a login
- Pasting real secrets into `.env`
- Decisions about which trackers to use and quality preferences

---

## 4. Prerequisites (operator provides before Phase 1)

- A working Ubuntu Server install with Docker + Docker Compose available
- A **ProtonVPN paid plan**, with a WireGuard configuration generated in the
  Proton account dashboard — yields a private key and an interface address
- The `.env` file populated (Claude Code scaffolds it; operator fills secrets)

---

## 5. Host preparation — Phase 0

1. **Verify Docker:** confirm `docker` and `docker compose` work and the
   daemon is running and enabled.

2. **Create the folder structure** (all under one filesystem — required for
   hardlinks):

   ```
   /opt/mediastack/
   |-- config/
   `-- data/
       |-- torrents/{anime,tv,movies,books}
       |-- media/{anime,tv,movies}
       |-- books/{ingest,library}
       `-- audiobooks/
   ```

3. **Identify IDs:** run `id -u` and `id -g` for PUID/PGID; run
   `getent group render` and `getent group video` for Jellyfin's `group_add`
   GIDs. Substitute the real values into `docker-compose.yml`.

4. **Secrets hygiene:** create `/opt/mediastack/.env` for secrets and a
   `.gitignore` that excludes `.env` and `config/`. The compose file must
   reference the WireGuard key via `${WIREGUARD_PRIVATE_KEY}` from `.env` —
   the key must never sit in a file that could be committed to git.

5. **System encrypted DNS:** configure DNS-over-TLS (see §7.1).

---

## 6. Phased deployment

Bring services up in groups. After each phase, run that phase's acceptance
test and confirm success before continuing.

### Phase 1 — Core media pipeline
Services: gluetun, qbittorrent, prowlarr, flaresolverr, sonarr, radarr,
bazarr, jellyseerr, jellyfin.

Acceptance test: request one TV episode through Jellyseerr; confirm it
downloads via qBittorrent, is hardlinked into `data/media/`, and plays in
Jellyfin. Confirm the hardlink (see §8) — the file must consume disk space
only once across `torrents/` and `media/`.

### Phase 1.5 — LAN multi-user, casting, optional external access
No new containers required for the core path. Make the stack usable by
other people in the household (request, watch, cast to TV) and decide
how locked-down the admin surface should be.

**1. LAN reachability — already works.** Every published container port
in `docker-compose.yml` binds to `0.0.0.0`, so any device on the LAN can
already reach the relevant services at the host's LAN IP. Find that IP
with `hostname -I` (first address). From a phone/laptop on the same WiFi:
- Jellyfin: `http://<host-LAN-IP>:8096`
- Jellyseerr: `http://<host-LAN-IP>:5055`

If Ubuntu Server has firewalld enabled, allow those two ports on the LAN zone.

**2. Create Jellyfin users for each household member.**
Jellyfin → Dashboard → Users → + (per user): pick a username, set a password,
configure per-user library access if some libraries should be hidden from
some users (e.g., kids). Each user gets their own watch progress.

**3. Wire those users into Jellyseerr.**
Jellyseerr → Settings → Users → Import Jellyfin Users → select all → Save.
Per-user permissions:
- Default: requests must be approved by admin (you). Sensible for housemates.
- For trusted family: enable "Auto-Approve" on their permission set.
- Request quotas (X per week) available if anyone is over-requesting.

**4. Casting & native apps.** Jellyfin has casting built in — no server-side
config needed:
- **Chromecast / Google TV**: any Chromecast button in Jellyfin's web/mobile
  player.
- **AirPlay / Apple TV**: Swiftfin (App Store) is the recommended native
  client. AirPlay also works from the iOS Jellyfin Mobile app.
- **Android TV / Fire TV / Roku / Samsung TVs**: search "Jellyfin" in the
  TV's app store; native apps exist for all of these and log in with the
  user's Jellyfin credentials.
- **Findroid** (Android) is the unofficial native client preferred by many
  power users over the official mobile app.

**5. Lock down the admin surface — choose one approach.**
By default, anyone on the LAN can also hit `http://<host>:8989` (Sonarr),
`:7878` (Radarr), `:9696` (Prowlarr), `:8081` (qBittorrent), etc. Each app
has its own login (we configured that in Phase 1), so passwords protect
them — but the attack surface is exposed.

Two paths, pick one:

- **(a) Trust-the-LAN (do nothing).** Acceptable if everyone on the LAN is
  trusted. Each app's password is the only barrier. Currently your default.

- **(b) Bind admin UIs to localhost only.** In `docker-compose.yml`, change
  each admin container's port from `8989:8989` to `127.0.0.1:8989:8989`
  (and similar for radarr, prowlarr, bazarr, flaresolverr, gluetun's qbit
  port). This makes those WebUIs reachable ONLY from the host itself —
  family on the LAN can still use Jellyfin/Jellyseerr but cannot reach
  the admin tools. You administer from the host's browser or via Tailscale
  (see step 7). `docker compose up -d` after editing applies the change.

Either is acceptable for a home setup; (b) is the better long-term choice.

**6. Optional polish: pretty URLs via reverse proxy.**
Telling housemates "go to `http://192.168.1.42:5055`" is ugly. Add Caddy
(easiest reverse proxy) in front of the stack to map clean LAN hostnames:
- `jellyfin.lan` → `:8096`
- `requests.lan` → `:5055`
Set up local DNS to point `*.lan` at the host's LAN IP (router DNS or
headscale's split DNS), then Caddy handles the rest in ~30 lines of
Caddyfile. Out of scope for first deployment; tackle later if motivated.

**7. External access via Tailscale (you already have headscale).**
Because this host runs headscale, any device you add to your Tailscale
network gets a stable `100.x.y.z` address that reaches the host from
anywhere — no port forwarding, no dynamic DNS, no Cloudflare Tunnel,
no public HTTPS certs. Family members install Tailscale on their phones,
authenticate via your headscale, and `http://<host-tailscale-IP>:8096`
works from anywhere with internet. This is the cleanest "watch from
outside the house" path and you're already 95% of the way there.

Acceptance test: another device on the LAN (phone or laptop) can sign
into Jellyfin with a non-admin user, browse the library, and play a
file. From the same device, log into Jellyseerr with the same credentials
and submit a request — confirm it shows up in your admin pending-requests
queue (if auto-approve is off) or in Sonarr/Radarr's grab activity (if on).

### Phase 2 — Verification & hardening
No new containers. Run all of §7: kill switch test, leak test, qBittorrent
hardening. Do not proceed until the VPN is confirmed leak-free.

### Phase 3 — Study layer
Not containers — browser extensions and (optionally) desktop apps. The
core dependency: subtitle text has to be **DOM-rendered**, not canvas, for
Yomitan to hover-lookup. Jellyfin's libass renderer draws subs to canvas
(pixels, not text), so Yomitan can't see them. **asbplayer's job is to
provide a parallel DOM-text overlay** that Yomitan CAN hook into.

**Required browser extensions:**
- **Yomitan** with dictionaries (Jitendex, KANJIDIC, JMnedict, frequency
  list e.g. JPDBv2 is a solid baseline; add a pitch-accent dictionary
  like Kanjium for production immersion).
- **asbplayer** browser extension.

**Workflow** (verified working with this stack):
1. Play any anime episode in Jellyfin web (`http://localhost:8096`).
2. Turn OFF Jellyfin's native subtitle track (Jellyfin's own libass
   render is canvas-based and not Yomitan-hoverable).
3. Drag the `.ja.srt` Bazarr fetched (under `data/media/anime/<series>/
   Season NN/*.ja.srt`) directly onto the Jellyfin video player.
4. asbplayer's DOM-text subtitle overlay appears, time-synced with the
   video.
5. Yomitan hover works on asbplayer's overlay; click words for
   definitions, kanji breakdown, pitch accent, frequency.
6. Hot-swap to English by dragging the `.en.srt` instead.

**Acceptance test (reading workflow):** Step 5 returns a definition.

**Mining (optional, downstream of reading).** The spec originally assumed
Anki + AnkiConnect as the mining destination, with asbplayer's WebSocket
sidecar enriching cards with audio segments and screenshots:
```
asbplayer extension  →  WebSocket sidecar  →  AnkiConnect  →  Anki
                       (adds audio+image)
```
If the operator uses NativShark, Migaku, or another non-Anki SRS,
mining has three reasonable paths:

- **(a) Anki as storage backend only** — install Anki + AnkiConnect, mine
  there, never use Anki for study; export `.apkg` when the destination
  SRS supports import.
- **(b) Stub AnkiConnect** — small custom HTTP server that implements the
  minimal AnkiConnect contract (`version`, `addNote`, `findNotes`) and
  dumps mining payloads to files/SQLite for later batch import.
- **(c) Skip mining for now** — the immersion-reading workflow alone is
  fully functional; capture words when an SRS API actually exists.

Mining setup is intentionally deferred when (c) is chosen — the reading
workflow above is the spec's Phase 3 acceptance criterion in its modern
form. Revisit mining when the destination SRS's API ships or workflow
demands it.

### Phase 4 — Self-maintenance ("the cycle")
Services: recyclarr, autobrr, cross-seed, qbitmanage, unpackerr.
Recyclarr first (quality profiles); the rest need tracker info from the
operator. Build an anime quality profile that prefers softsubbed,
multi-subtitle-track releases.

### Phase 5 — Books (including light novels)
Services: lazylibrarian, calibre-web-automated, audiobookshelf.
Configure LazyLibrarian's download destination to `data/books/ingest` so
Calibre-Web Automated auto-imports. Prefer EPUB over PDF as the target format.

**Light novels** use this same stack — they're just EPUB/PDF text content.
LazyLibrarian's libgen + Anna's Archive sources carry essentially all
officially-released English LNs. The one gap is fan-translations of
currently-airing series that drop chapter-by-chapter on translator
websites and never get compiled into an EPUB; for those, the **WebToEpub**
browser extension is the standard manual workaround. No additional
containers required.

**LazyLibrarian via VPN.** As called out in `docker-compose.yml`, libgen
direct downloads come from the lazylibrarian container itself, not via
gluetun. Operator preference: route libgen through the VPN. To do that:
give the lazylibrarian service `network_mode: "service:gluetun"`, drop
its own `ports:` block, and add `5299:5299` to gluetun's `ports:`. Then
any service that talks to LazyLibrarian must use `gluetun:5299`, not
`lazylibrarian:5299` (same gotcha as qBittorrent, §8). Also: gluetun
will need to be restarted in lockstep — `docker restart gluetun` should
be followed by `docker restart qbittorrent lazylibrarian` (network_mode
dependents don't auto-reattach when gluetun's namespace is recreated).

### Phase 6 — Manga
Services: suwayomi-server, kavita.
Manga is its own category because of how it's distributed: ongoing series
drop chapter-by-chapter on reader sites *before* anyone bundles them into
torrents, so torrent-based acquisition lags ongoing releases by weeks.

The split that works:

- **Suwayomi-Server** — self-hosted Tachiyomi/Mihon. Uses the Tachiyomi
  extension catalog (hundreds of source sites, including Japanese-language
  ones useful for the immersion workflow) to monitor series and auto-pull
  new chapters as CBZ files. This is the "Sonarr for manga" role.
- **Kavita** — the reader and library server. Better UX for sequential
  art than CWA: page-turn animations, reading direction (R-to-L for manga),
  double-page layouts. The "Jellyfin for manga" role.

Pipeline: Suwayomi drops CBZ chapters into a shared folder → Kavita indexes
and serves them. Backlog torrents from Nyaa's "Literature - English-translated"
or "Literature - Raw" sections can land in the same folder via a `manga`
qBittorrent category for backfill.

Folder layout to add under `data/`:

```
data/manga/             <- Kavita library (also Suwayomi's chapter destination)
data/torrents/manga/    <- qBittorrent destination for backlog grabs
```

Suwayomi runs on port 4567, Kavita on 5000 by default (move to 8084 if there's
a collision). Neither needs the VPN — they're scrapers, not torrent clients —
though if anything they grab goes through qBittorrent, that does.

### Phase 7 — Polish layer (optional)
Quality-of-life additions that layer on top of the core stack without
replacing anything. None are required; pick what's interesting.

- **Reverse proxy** — **DEPLOYED in this build.** Caddy on port 80
  serves the household-facing URL surface. Path-based routing under one
  host (no DNS dependency): `http://<LAN-IP>/` → Homepage dashboard;
  `http://<LAN-IP>/jellyfin/` → Jellyfin. Admin tools intentionally not
  proxied, kept on raw ports for the operator only. Critical config
  decisions captured:
  - **Jellyfin Base URL = `/jellyfin`** (Dashboard → Networking) so
    Jellyfin's internal links match the Caddy path. Restart Jellyfin
    after setting.
  - **Jellyseerr is NOT subpath-proxied** — its redirect handling
    strips prefixes (documented Jellyseerr limitation). Homepage card
    links to port 5055 directly.
  - **Jellyseerr's `settings.json` jellyfin.urlBase must be
    `/jellyfin`** after the Jellyfin Base URL change, or Jellyseerr's
    SSO calls go to the wrong Jellyfin API path and silently fail.
  See MAINTENANCE.md "Household URL layer" for the full Caddy + UFW
  + DNS picture and per-gotcha details.
- **Dashboard page** — **DEPLOYED.** Homepage at port 3000, also reachable
  through Caddy at root. Service cards for every household-facing app,
  live widget data from Sonarr/Radarr/Prowlarr/qBittorrent (API keys
  read from `.env` via `HOMEPAGE_VAR_*` env vars). Docker-status dots
  require `user: "${PUID}:${PGID}"` + `group_add: ["${DOCKER_GID}"]` on the homepage container so its `node` user has the target host's docker group GID.
  Alternatives if you ever want to swap: [Homarr](https://homarr.dev),
  [Glance](https://glance.zone) — same role, different aesthetic.
- **Monitoring** — disk/CPU/network graphs. Lightweight: [Netdata](https://www.netdata.cloud)
  (one container, instant dashboards). Heavyweight: Grafana + Prometheus
  + node-exporter. Worth it once you're on a dedicated server and want
  to spot disk-fill or container-restart issues before they bite.
- **Container management UI** — [Portainer](https://www.portainer.io)
  or [Dockge](https://github.com/louislam/dockge) for browser-based
  inspection of containers/logs without dropping to CLI.
- **Off-site backup automation** — [Restic](https://restic.net) to
  Backblaze B2 or AWS S3, scheduled by systemd timer or cron. Encrypts
  + dedupes + versions. Replaces (or augments) the manual tar workflow
  in MAINTENANCE.md.
- **SSO across the stack** — [Authelia](https://www.authelia.com) or
  [Authentik](https://goauthentik.io) lets one login (with optional 2FA)
  grant access to every app via reverse-proxy auth. Heavy lift to set
  up; nice when you have ~10+ services and household users.
- **Notification aggregator** — [Notifiarr](https://notifiarr.com) or
  [Apprise-API](https://github.com/caronc/apprise-api) fan out the
  *arrs' / qbitmanage / cross-seed notifications to Discord, email,
  push, etc. through a single config.

### Phase 8 — Observability & self-healing layer (DEPLOYED)
Six services that make the stack notice and fix problems on its own, and
let the operator see what's happening at a glance. All admin-only — none
are proxied through Caddy; family never touches them. Full one-time setup
per service is in MAINTENANCE.md "Observability layer (Phase 8)".

- **Cleanuparr** (port 11011) — **DEPLOYED.** Removes stalled / dead /
  metadata-stuck downloads from the qBit queue and tells Sonarr/Radarr to
  grab an alternative. This is the automated answer to the "old movie
  stalls forever with no seeders" case. Complements qbitmanage rather than
  overlapping: Cleanuparr acts on items still *downloading*; qbitmanage on
  items already *seeding*. Connects to qBit via `gluetun:8080` (the §8
  namespace rule) and to the *arrs via API key.
- **Huntarr** — **SUPERSEDED (not deployed).** Its job (missing-item +
  cutoff-unmet upgrade search) is built into **Cleanuparr's Seeker**
  module, so it was never needed. Standalone Huntarr was also unsafe — its
  upstream (plexguide/Huntarr.io) was archived after the maintainer went
  "scorched earth" over disclosed security vulnerabilities and the image
  was pulled. Use Cleanuparr → Seeker instead. (Block left commented in
  `docker-compose.yml` as a historical marker.)
- **ntfy** (port 2586) — **DEPLOYED.** Self-hosted push-notification bus.
  Everything that needs to page the operator POSTs to it; you subscribe
  from the ntfy phone app. No auth (LAN-only, matches the no-SSO trust
  model). Already wired: `scripts/sync-qbit-port.sh` pings it if the VPN
  forwarded-port sync ever fails, and Diun + Uptime-Kuma publish here.
  This is the one Phase 8 service that needs a UFW LAN rule (the phone
  subscribes over the network).
- **Uptime-Kuma** (port 3001) — **DEPLOYED.** Health dashboard that pings
  every service and pages ntfy when one goes down. Homepage shows *links*;
  Uptime-Kuma shows *health + history + alerts*. Preferred place to add
  monitoring (central) over wiring per-service notification hooks.
- **Jellystat** (port 3010, + its own Postgres) — **DEPLOYED.** Tautulli-
  for-Jellyfin: who watched what, when, how much. Needs a Jellyfin API key
  (`JELLYFIN_APIKEY` in `.env`) — the same key also lights up the Homepage
  Jellyfin widget. (This fulfils the watch-analytics bullet that was
  previously parked in the old Phase 10.)
- **Diun** (no UI) — **DEPLOYED.** Checks every container's image on a
  6-hourly schedule and pings ntfy when a newer one is published.
  Notify-**only** by design: it never auto-updates, so it can't bypass
  `update.sh`'s gluetun-ID-aware recreate of qBit/LazyLibrarian. When Diun
  pings, the operator runs `update.sh` deliberately. (Replaces the
  Watchtower idea, which would have been unsafe here.)

This phase delivered the "Monitoring" and "Notification aggregator"
bullets that were sketched as optional under Phase 7, plus the watch-
analytics piece from the old Phase 10. Still deliberately **not** done:
SSO (the per-app-account model is intentional — see §3 / old Phase 10),
and heavyweight Grafana/Prometheus (Uptime-Kuma + ntfy cover the need at
this scale).

### Phase 9 — Dedicated server migration (when ready)
The current stack is fully portable. Migration to dedicated hardware is
a copy-paste: clone the git repo + untar config/ on the new box + mount
storage at `/data` + `docker compose up -d`.

Considerations when picking hardware:

- **Storage architecture** — the only constraint that doesn't move:
  **`data/` must stay on one filesystem** for hardlinks to work (§8).
  If you pool drives, use one of:
  - **ZFS** (snapshots, ARC cache, native checksums; demands RAM and
    a planned topology — recommended if comfortable with the learning
    curve)
  - **btrfs** (built-in to Linux; snapshot semantics; simpler than ZFS)
  - **mergerfs + SnapRAID** (union filesystem + parity files; the most
    drive-flexible option — add/remove disks easily — popular in the
    homelab/datahoarder space)
  Pattern most setups use: SSD pool for `config/` (fast SQLite writes),
  big spinning-disk pool for `data/`.
- **Transcoding GPU** - the Lenovo i5-10400's Intel UHD 630 should use Intel Quick Sync through `/dev/dri`. Verify `render` and `video` group IDs on the target host before enabling Jellyfin hardware acceleration.
- **Power profile** — full desktop ~150-300W idle vs N100 mini-PC + JBOD
  ~25W idle. Matters at 24/7 runtime.
- **Networking** — 2.5GbE or 10GbE between server and clients is cheap
  now and makes large file moves bearable. Static IP for the server.

Migration procedure:
1. Install Linux + Docker on the new box.
2. `git clone <your-remote>` to `/opt/mediastack`.
3. `tar -xzf <latest-config-backup>.tar.gz -C /opt/mediastack` to restore
   `config/` + `.env`.
4. Mount the storage at the same logical path (`/opt/mediastack/
   data` or wherever — keep it identical to the old machine to avoid
   path-rewrites).
5. `mkdir -p` any data subdirs that didn't survive the move.
6. `docker compose up -d`. Stack resumes exactly where it left off:
   same Sonarr/Radarr databases, same qBit torrents, same library,
   same Bazarr profiles, same Recyclarr state.
7. Re-install the systemd timer for the qBit port sync (see §7.6 /
   MAINTENANCE.md "Forwarded-port sync").

The whole migration is ~30 minutes once hardware is ready.

### Phase 10 — Additional content types (extensions)
A menu of whole new *domains* the stack could grow into. None are wanted
right now (operator decision, 2026-05) — documented here so they're ready
to build when/if the interest appears. Each is a small set of containers
that drops into the existing pattern (compose service + Homepage card +
optional Uptime-Kuma monitor + ntfy alerts already in place).

**Music (self-hosted Spotify).** Two pieces:
- **Lidarr** — "Sonarr for music," album acquisition. Plugs into Prowlarr
  the same way; route downloads through gluetun like the rest. Adds
  ~10GB/year for moderate listeners.
- **Navidrome** — the streaming/listening front-end (Subsonic-API, great
  mobile apps). Lidarr fills the library, Navidrome serves it. Family-
  facing, so it'd get a Caddy entry + Homepage card.

**Photos (Google Photos replacement).** The single most family-loved
addition out there:
- **Immich** — phone auto-backup, face/object/place search, shared albums,
  timeline. Heavier than the others (its own Postgres + Redis + a machine-
  learning container), so best added *after* the dedicated-hardware move
  (Phase 9) where storage + a small GPU/iGPU help the ML features. Family-
  facing; would sit behind Caddy with its own per-user accounts.

**Documents.** Different domain from media, mention-only:
- **Paperless-ngx** — scan / OCR / full-text-search / archive for mail,
  receipts, manuals. Own Postgres + Redis. Useful but unrelated to the
  media pipeline; only add if you actually want a paperless office.

**Storage optimization** (revisit at the Phase 9 hardware move, when disk
gets tight — needs a transcode-capable GPU/iGPU to be worthwhile):
- **Tdarr** — library-wide transcoding: re-encode bloated x264 to
  efficient HEVC/AV1 to reclaim disk, or standardize codecs/containers.
  Distributed-worker model. Big disk savings, but CPU/GPU-intensive.

**Email — NOT recommended.** Self-hosting a mail *server* (Mailcow,
docker-mailserver) is a notoriously painful, high-maintenance domain
(deliverability, blocklists, DNS records, security exposure) with nothing
to do with media. If "email" just means *notifications*, that's already
handled by the Phase 8 ntfy bus. Leave real email to a hosted provider.

**Other / advanced (situational):**
- **Plex alongside Jellyfin** — some households run both: Plex for
  non-technical family (historically smoother mobile UX), Jellyfin for the
  operator. Both serve from the same `data/media` simultaneously.
- **Overseerr** — Plex-focused request frontend (sister to Jellyseerr).
  Only if running Plex.
- **rclone-mounted cloud storage** — extends `data/media` with effectively
  unlimited cold storage (Google Drive, etc.) via an encrypted union
  mount. The most common "advanced datahoarder" move; out-of-scope for
  most home setups.
- **Auto-cleanup** — [Maintainerr](https://docs.maintainerr.info) /
  [Janitorr](https://github.com/Schaka/janitorr) auto-delete media by
  watch status/age. Careful: must never delete something still inside a
  private tracker's required seedtime (qbitmanage owns that — §Phase 8).

### Phase 11 — Identity, scaling (when household grows)
Once 3+ humans use the stack regularly:

- **SSO** via Authelia/Authentik (see Phase 7) becomes worth the
  setup cost. Still intentionally skipped for now — the per-app-account
  model (each user has their own login per app) is deliberate so family
  members can't accidentally break shared configuration (§3).
- **Watch analytics** — **already deployed** via Jellystat in Phase 8.
  Use it to detect bandwidth hogs / per-user viewing once the household
  grows.
- **Notifications routed to humans** — extend the Phase 8 ntfy bus so each
  household member gets their own topic for "your request is ready" /
  "your show has a new episode" alerts (per-user ntfy topics + Jellyseerr
  webhooks).
- **Family-tier permissions in Jellyseerr** — different request quotas
  per user (e.g., kids get 5 requests/month), auto-approve for trusted
  adults, admin-approve for the rest.

---

## 7. Security & hardening — detailed

### 7.1 Encrypted DNS — DoT vs DoH, and the recommendation

Both encrypt DNS lookups so the ISP cannot read them. The difference:

- **DoT (DNS over TLS)** — runs on dedicated port 853. Easy to deploy
  system-wide on Linux; cleanly integrated with `systemd-resolved`. Because
  it's on its own port, a network observer can tell it's DNS traffic (though
  not its contents).
- **DoH (DNS over HTTPS)** — runs on port 443, indistinguishable from normal
  HTTPS traffic, so it's marginally better at evading observation or blocking.
  Usually configured per-application rather than system-wide.

**Recommendation — do both, at the layers each suits best:**

- **System-wide: DoT via `systemd-resolved`.** Simplest robust whole-system
  option on Ubuntu Server. Configure `/etc/systemd/resolved.conf`:
  - `DNS=9.9.9.9#dns.quad9.net` (the `#hostname` is required for TLS cert
    validation; Quad9 or Cloudflare `1.1.1.1#cloudflare-dns.com` are both fine)
  - `DNSOverTLS=yes`
  - Restart `systemd-resolved`; confirm `/etc/resolv.conf` points at the stub
    resolver `127.0.0.53`; verify with `resolvectl status` showing
    `+DNSOverTLS`.
- **Browser: Firefox's built-in DoH.** Settings → Privacy & Security → enable
  DNS over HTTPS, "Increased/Max Protection". Defense in depth for browsing.

Note: this is for the **operator's general system traffic only**. The media
stack's DNS is already handled — gluetun routes container DNS through the VPN
with DoT enabled by default. The two are independent.

(If maximum control over system-wide DoH is wanted later, `dnscrypt-proxy`
is the tool — out of scope for initial setup.)

### 7.2 Kill switch verification

gluetun's firewall is the kill switch: it blocks all non-tunnel traffic, and
qBittorrent shares gluetun's network namespace so it physically cannot route
around the VPN. This is structural, not a setting — but **verify it**:

- `docker stop gluetun` → confirm qBittorrent immediately loses all network
  connectivity (its WebUI/traffic should stall).
- `docker start gluetun` → confirm connectivity returns.

### 7.3 Leak test

- Public IP: `docker exec gluetun wget -qO- https://ipinfo.io/ip` must
  return the VPN's IP, **not** the operator's home IP. (Note: the spec
  originally suggested `ifconfig.me` — that URL returns HTML to wget rather
  than a plain IP, so use ipinfo.io/ip for a clean comparison. Compare
  against `curl -4 -s https://ipinfo.io/ip` on the host to confirm the
  IPs differ.)
- DNS leak: from inside the gluetun namespace, confirm DNS resolves through
  the VPN, not the ISP's resolver.
- Optionally load a torrent-IP-check magnet to confirm the swarm sees only
  the VPN IP.

### 7.4 qBittorrent hardening

Apply in qBittorrent's settings once the WebUI is reachable:

- **Encryption** — Options → BitTorrent → set connection encryption to
  *Prefer* (broad compatibility) or *Require* (strictest; use if the operator
  only ever uses private trackers, as it can reduce the public peer pool).
  Naming note: current qBittorrent labels the *Prefer* mode as
  **"Allow encryption"** in the UI — same underlying setting, just renamed.
  The other two options are *Require encryption* and *Disable encryption*.
- **Anonymous mode** — a privacy toggle that strips identifying client info.
  Useful for public trackers. **Caution:** some private trackers' rules
  expect a normally identifiable client and may flag anonymous mode — check
  each private tracker's rules before enabling globally.
- **DHT / PeX / LSD** — these peer-discovery mechanisms are required on
  *public* trackers (it's how peers are found) but forbidden by *private*
  trackers. Important detail: torrents from private trackers carry a "private"
  flag, and qBittorrent automatically disables DHT/PeX/LSD for any flagged
  torrent regardless of the global setting. So:
  - Using both public and private trackers → leave DHT/PeX/LSD **on**
    globally; the private flag protects private torrents automatically.
  - Using private trackers exclusively → disabling them globally is fine and
    a reasonable belt-and-suspenders choice.

### 7.5 Secrets management

- WireGuard private key and any API keys live in `/opt/mediastack/.env`.
- `.gitignore` must exclude `.env` and `config/`.
- If the `mediastack` directory is ever placed under version control, confirm
  no secret is in tracked files.

### 7.6 Forwarded-port automation script

ProtonVPN's forwarded port can change when gluetun reconnects. qBittorrent's
listening port must match it. Write a small script that:

1. Reads the current forwarded port from gluetun (control-server API at
   `http://localhost:8000/v1/openvpn/portforwarded`, or the
   `config/gluetun/forwarded_port` file).
2. Sets qBittorrent's `listen_port` via its WebUI API
   (`/api/v2/app/setPreferences`).
3. Runs on a schedule (cron or a small loop) so a port change is picked up.

Until this is in place, the port can be set manually in qBittorrent after the
first VPN connection.

---

## 8. Known gotchas

- **The `gluetun` hostname rule.** qBittorrent has no network identity of its
  own — it lives inside gluetun's namespace. Every service that connects to
  qBittorrent (Sonarr, Radarr, autobrr, cross-seed, qbitmanage) must use
  **host `gluetun`, port `8080`** — never `qbittorrent`. Using `qbittorrent`
  fails silently.
- **Hardlinks need one filesystem.** All of `data/` must be on a single
  filesystem/mount. If `torrents/` and `media/` are on different filesystems,
  the *arrs silently fall back to slow full copies and lose the
  seed-while-in-library behavior.
- **Forwarded port drift.** See §7.6 — the port is not static.

---

## 9. Final acceptance tests

The build is complete when all of the following pass:

1. A Jellyseerr request flows end-to-end to a playable file in Jellyfin.
2. Hardlinks confirmed — a downloaded file occupies its disk space once.
3. Kill switch confirmed — stopping gluetun cuts qBittorrent's network.
4. No IP leak — the stack's public IP is the VPN's.
5. System DNS confirmed encrypted — `resolvectl status` shows `+DNSOverTLS`.
6. One Anki card successfully mined from a Jellyfin episode via asbplayer.
7. Recyclarr has synced quality profiles into Sonarr/Radarr.
8. A book acquired via LazyLibrarian appears in Calibre-Web Automated.

---

## 10. Port reference

| Service | Port | Service | Port |
|---|---|---|---|
| qBittorrent (via gluetun) | 8081 (host) → 8080 (container) | autobrr | 7474 |
| Prowlarr | 9696 | cross-seed | 2468 |
| FlareSolverr | 8191 | LazyLibrarian | 5299 |
| Sonarr | 8989 | Calibre-Web Automated | 8083 |
| Radarr | 7878 | Audiobookshelf | 13378 |
| Bazarr | 6767 | Jellyfin | 8096 |
| Jellyseerr | 5055 | Suwayomi-Server (Phase 6) | 4567 |
| Kavita (Phase 6) | 5000 (or 8084 if collision) | Caddy (Phase 7) | 80 |
| Homepage (Phase 7) | 3000 | ntfy (Phase 8) | 2586 |
| Cleanuparr (Phase 8) | 11011 | Uptime-Kuma (Phase 8) | 3001 |
| Jellystat (Phase 8) | 3010 (host) → 3000 (container) | Huntarr | DEFERRED (security) |

**qBittorrent port note.** The host port for qBittorrent's WebUI is **8081**,
not 8080, because the host already runs headscale on 8080. Inside the
container (and on the Docker network) qBittorrent still listens on 8080,
so the §8 "host = gluetun, port = 8080" rule for inter-container references
is unchanged.
