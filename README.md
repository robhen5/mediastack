# Mediastack

Docker Compose media stack for the Lenovo home server plan:

- Lenovo desktop with Intel i5-10400
- 12GB RAM now, possible 32GB later
- 512GB SSD for OS, app config, metadata, logs, and backup staging
- Seagate Exos ST28000NM001C 28TB SATA HDD for downloads and media
- Future TerraMaster D9-320 USB DAS expansion
- Windows 11 Pro currently installed, but production should be Ubuntu Server or
  Unraid
- Timezone: `America/New_York`

This repo is now parameterized for the actual hardware plan. It is still
conservative: first deployment brings up only the core movie/TV stack, while
cleanup, observability, books, manga, dashboard, and other optional services
require explicit Docker Compose profiles.

> **Read `docs/SAFETY.md` before first deploy.** Everything that can move,
> rename, or delete media is inventoried there, and the default behavior of
> this stack is configured to be report-only / non-destructive for the
> first 30 days. See "First 30 days safe mode" in that doc.

## Production Target

Use Windows only for staging, reading docs, or testing compose edits. Do not run
the production automation stack against the 28TB media drive through Docker
Desktop. The stack assumes Linux paths, `/dev/net/tun`, `/dev/dri`, Linux file
ownership, and stable mounted storage.

Recommended production path:

1. Install Ubuntu Server LTS on the Lenovo, or migrate to Unraid later.
2. Keep app state on the SSD.
3. Mount the 28TB Exos at a stable Linux path.
4. Keep downloads and media under one `DATA_ROOT` filesystem/pool so
   Sonarr/Radarr hardlinks work.

## Storage Layout

Default `.env.example` paths:

```text
MEDIASTACK_ROOT=/opt/mediastack
CONFIG_ROOT=/opt/mediastack/config
BACKUP_ROOT=/opt/mediastack/backups
DATA_ROOT=/media/storage/data
```

Recommended physical placement:

- SSD: `MEDIASTACK_ROOT`, `CONFIG_ROOT`, `BACKUP_ROOT`
- Exos HDD: `DATA_ROOT`
- Future D9-320: expand `DATA_ROOT` through Unraid or a Linux pool after
  validating hardlinks and mount stability

Keep both torrents and imported media under `DATA_ROOT`:

```text
/media/storage/data/
  torrents/
  media/
    movies/
    tv/
  books/
  audiobooks/
  manga/
```

## First Deploy

Copy `.env.example` to `.env`, fill in real values, then validate on the Ubuntu
target host:

```bash
docker compose config
docker compose --profile first-deploy up -d
```

The `first-deploy` profile starts only:

- Gluetun
- qBittorrent
- Prowlarr
- Sonarr
- Radarr
- Bazarr
- Jellyfin
- Jellyseerr

It intentionally does not start qbitmanage, Cleanuparr, or other cleanup
services.

## Compose Profiles

| Profile | Purpose |
|---|---|
| `first-deploy` | Core safe first deployment only |
| `core` | Same core movie/TV stack |
| `optional` | Broad opt-in for non-core services |
| `indexers` | FlareSolverr |
| `automation` | Recyclarr, autobrr, cross-seed, Unpackerr |
| `cleanup` | qbitmanage and Cleanuparr; disabled by default |
| `books` | LazyLibrarian, Calibre-Web Automated, Audiobookshelf |
| `manga` | Suwayomi and Kavita |
| `polish` | Caddy and Homepage |
| `monitoring` | ntfy and Uptime Kuma only |
| `observability` | Full observability bundle: ntfy, Uptime-Kuma, Jellystat, Diun |

Do not enable the `cleanup` profile until backups, hardlink behavior, tracker
seed-time rules, and dry-run/report-only settings are verified. The compose
file ships qbit_manage with `QBT_DRY_RUN=true` so that even when the
`cleanup` profile is enabled, the tool starts in report-only mode. See
`docs/SAFETY.md` §4 "Warnings before enabling deletion automation."

## Intel Quick Sync

The i5-10400 includes Intel UHD Graphics 630. Jellyfin is configured to expose
`/dev/dri` for Intel Quick Sync on Linux:

```yaml
devices:
  - /dev/dri:/dev/dri
```

On the target host, verify group IDs and set them in `.env`:

```bash
id mediastack
getent group render
getent group video
ls -l /dev/dri
```

Then test playback with direct play and with one forced transcode.

## Target-Host Validation

Run these on Ubuntu Server or Unraid, not this Windows staging folder:

```bash
docker compose config
shellcheck scripts/*.sh
bash -n scripts/*.sh
```

Storage and permissions:

```bash
id mediastack
findmnt /media/storage
df -h /opt/mediastack /media/storage
touch /media/storage/data/.write-test && rm /media/storage/data/.write-test
```

Hardlink test:

```bash
mkdir -p /media/storage/data/{torrents,media}
echo test > /media/storage/data/torrents/hardlink-test
ln /media/storage/data/torrents/hardlink-test /media/storage/data/media/hardlink-test
stat /media/storage/data/torrents/hardlink-test /media/storage/data/media/hardlink-test
rm /media/storage/data/torrents/hardlink-test /media/storage/data/media/hardlink-test
```

VPN checks:

```bash
docker exec gluetun wget -qO- https://ipinfo.io/ip
curl -4 -s https://ipinfo.io/ip
docker stop gluetun
# Confirm qBittorrent loses connectivity.
docker start gluetun
```

Backup/restore rehearsal:

```bash
tar -czf "$BACKUP_ROOT/config-test-$(date +%Y%m%d).tar.gz" -C "$MEDIASTACK_ROOT" config .env
mkdir -p /tmp/mediastack-restore-test
tar -xzf "$BACKUP_ROOT/config-test-$(date +%Y%m%d).tar.gz" -C /tmp/mediastack-restore-test
```

## Scripts

- `scripts/update.sh` supports `DRY_RUN=1`, defaults to
  `first-deploy monitoring`, and wraps `docker image prune -f` behind that
  dry-run runner.
- `scripts/sync-qbit-port.sh` updates qBittorrent's listen port to match the
  Gluetun/ProtonVPN forwarded port. It does not move, rename, or delete files.
- `scripts/backup-config.sh` archives `.env`, `config/`, `docker-compose.yml`,
  and `scripts/` into `BACKUP_ROOT` with a verified tarball, rotation
  (default keep last 6), and `DRY_RUN=1` support. Run weekly.
- `scripts/restore-config-test.sh` extracts the newest backup to a temp dir
  and confirms it contains the expected layout. Run quarterly.
- `scripts/test-hardlinks.sh` proves that `torrents/` and `media/` share one
  filesystem and that hardlinks do not duplicate bytes. Run after any storage
  layout change.

## Documentation

- `docs/SAFETY.md`: destructive-workflow inventory, 30-day safe mode, backup
  plan, restore rehearsal, hardlink test plan, and remaining risks (**read
  before first deploy**)
- `docs/hardware-plan.md`: Lenovo, Exos, TerraMaster, Ubuntu, and Unraid plan
- `docs/deployment-checklist.md`: target-host validation and deployment steps
- `docs/risk-register.md`: data-loss and scaling risks
- `docs/legacy/`: older detailed setup/maintenance notes retained for reference
