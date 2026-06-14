# Deployment Checklist

Use this on the Ubuntu Server or Unraid target host before putting real media at
risk. Windows is staging/testing only.

Read `docs/SAFETY.md` first. This checklist is the procedural sibling of
the data-loss safety plan documented there.

## Phase 0: Hardware And OS

- [ ] Decide whether this deployment is Ubuntu Server now or Unraid later.
- [ ] If using Ubuntu, install Ubuntu Server LTS on the Lenovo.
- [ ] Create a dedicated user, normally `mediastack`.
- [ ] Keep the 512GB SSD for OS, Docker, app config, metadata, logs, and backup
      staging.
- [ ] Prepare the 28TB Exos HDD for `DATA_ROOT`.
- [ ] Confirm the host timezone should be `America/New_York`.

## Phase 1: Storage

- [ ] Format the 28TB Exos as ext4 or XFS on Ubuntu, or assign it through the
      chosen Unraid share/pool layout.
- [ ] Mount the Exos by UUID or stable label, not by incidental device name.
- [ ] Create the SSD-backed roots:

```bash
sudo mkdir -p /opt/mediastack/{config,backups}
```

- [ ] Create the HDD-backed data root:

```bash
sudo mkdir -p /media/storage/data/{torrents,media/{movies,tv},books,audiobooks,manga}
```

- [ ] Confirm Docker will not start before the storage mount is available.
- [ ] Confirm the `mediastack` user can write to `CONFIG_ROOT`, `BACKUP_ROOT`,
      and `DATA_ROOT`.

## Phase 2: Environment

- [ ] Copy `.env.example` to `.env`.
- [ ] Set real values for:
  - `MEDIASTACK_ROOT`
  - `CONFIG_ROOT`
  - `BACKUP_ROOT`
  - `DATA_ROOT`
  - `PUID`
  - `PGID`
  - `RENDER_GID`
  - `VIDEO_GID`
  - `DOCKER_GID` if using Homepage/Diun Docker socket features
  - `LAN_IP`
  - `LAN_SUBNET`
  - VPN and app secrets
- [ ] Keep `.env` out of git.

Find IDs:

```bash
id mediastack
getent group render
getent group video
getent group docker
ls -l /dev/dri
```

## Phase 3: Static Validation

Run on the target host:

```bash
docker compose config
shellcheck scripts/*.sh
bash -n scripts/*.sh
```

If any command fails, fix that before starting containers.

## Phase 4: First Deploy

Start only the conservative profile:

```bash
docker compose --profile first-deploy up -d
```

This starts only:

- Gluetun
- qBittorrent
- Prowlarr
- Sonarr
- Radarr
- Bazarr
- Jellyfin
- Jellyseerr

Do not enable qbitmanage, Cleanuparr, or other cleanup tools during first
deploy.

## Phase 5: Target-Host Tests

Directory and permission checks:

```bash
findmnt /media/storage
df -h /opt/mediastack /media/storage
touch "$CONFIG_ROOT/.write-test" "$DATA_ROOT/.write-test"
rm "$CONFIG_ROOT/.write-test" "$DATA_ROOT/.write-test"
```

VPN leak test:

```bash
docker exec gluetun wget -qO- https://ipinfo.io/ip
curl -4 -s https://ipinfo.io/ip
```

The two IPs should differ.

Gluetun kill-switch test:

```bash
docker stop gluetun
# Confirm qBittorrent loses network connectivity.
docker start gluetun
```

Hardlink test:

```bash
mkdir -p "$DATA_ROOT/torrents" "$DATA_ROOT/media"
echo test > "$DATA_ROOT/torrents/hardlink-test"
ln "$DATA_ROOT/torrents/hardlink-test" "$DATA_ROOT/media/hardlink-test"
stat "$DATA_ROOT/torrents/hardlink-test" "$DATA_ROOT/media/hardlink-test"
rm "$DATA_ROOT/torrents/hardlink-test" "$DATA_ROOT/media/hardlink-test"
```

Both `stat` outputs should show the same inode and link count greater than 1.

Jellyfin transcode test:

- [ ] Confirm direct play works on a local client.
- [ ] Force one transcode from a client profile or incompatible format.
- [ ] Confirm Jellyfin dashboard shows hardware acceleration rather than CPU-only
      transcode.

Backup/restore rehearsal (prefer the safety scripts):

```bash
./scripts/backup-config.sh
./scripts/restore-config-test.sh
```

The scripts include verified excludes, integrity checks, rotation, and a
sanity check on the irreplaceable files. Manual `tar` is documented in
`docs/SAFETY.md` §5 as a fallback.

Hardlink test (re-run after every storage layout change):

```bash
./scripts/test-hardlinks.sh
```

Disk health monitoring:

```bash
sudo apt install smartmontools
ls -l /dev/disk/by-id/
sudo smartctl -a /dev/disk/by-id/ata-ST28000NM001C_replace_with_real_serial
sudo /opt/mediastack/scripts/check-disk-health.sh
```

Then install the timers from `docs/disk-health.md`.

Firewall:

```bash
LAN_SUBNET=192.168.0.0/24 DRY_RUN=1 ./scripts/apply-firewall-rules.sh
LAN_SUBNET=192.168.0.0/24 APPLY=1 ./scripts/apply-firewall-rules.sh
sudo ufw status verbose
```

See `docs/firewall.md`.

Install weekly config backups after the first successful manual backup:

```bash
sudo install -m644 /opt/mediastack/scripts/backup-config.service /etc/systemd/system/
sudo install -m644 /opt/mediastack/scripts/backup-config.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now backup-config.timer
systemctl list-timers backup-config.timer --no-pager
sudo systemctl start backup-config.service
journalctl -u backup-config.service -n 30 --no-pager
```

Keep copying at least one recent backup tarball off the server. The timer
protects against app/config loss, not SSD failure or whole-machine loss.

## Phase 6: After Core Is Stable

Only after the first-deploy profile passes:

- [ ] Add monitoring with `--profile monitoring` for ntfy and Uptime Kuma.
- [ ] Add the dashboard with `scripts/install-homepage-config.sh`, then
      `docker compose --profile dashboard --profile monitoring up -d homepage ntfy uptime-kuma`.
- [ ] Add full observability with `--profile observability` only when you also
      want Jellystat and Diun.
- [ ] Add optional services by profile, one category at a time.
- [ ] Keep qbitmanage and Cleanuparr disabled until cleanup rules are reviewed.
- [ ] If enabling `cleanup`, start with report-only/dry-run behavior where the
      app supports it (qbitmanage already defaults to `QBT_DRY_RUN=true`).

## Phase 7: First 30 Days Safe Operating Mode

Spelled out in full in `docs/SAFETY.md` §3. Quick gates:

- [ ] Run only `--profile first-deploy` (optionally `+ observability`) for
      the first week.
- [ ] Weekly `scripts/backup-config.sh`; copy at least one tarball off-host.
- [ ] At least one `scripts/restore-config-test.sh` PASS during the 30 days.
- [ ] All imports confirmed as "Hard Linked" in *arr History; no "Copied"
      entries.
- [ ] `df -h $DATA_ROOT` weekly; growth matches grabs.
- [ ] Sonarr/Radarr → Settings → Media Management → "Delete Empty Folders" OFF.
- [ ] No qbitmanage / Cleanuparr / Maintainerr / Janitorr in any compose
      `up -d` command issued during the 30 days.

Graduating from safe mode is gated in `docs/SAFETY.md` §3 "Day 30+ —
graduating from safe mode."

## Go/No-Go Criteria

Go only when all are true:

- [ ] `docker compose config` passes on the target host.
- [ ] Directory permissions are verified.
- [ ] VPN leak test passes.
- [ ] Gluetun kill-switch test passes.
- [ ] Hardlink test passes (`scripts/test-hardlinks.sh`).
- [ ] Jellyfin direct play and transcode tests pass.
- [ ] Config backup and restore rehearsal succeeds.
- [ ] Cleanup tools remain disabled or conservative (qbit_manage in
      `QBT_DRY_RUN=true`; Cleanuparr modules in UI Test Mode).
