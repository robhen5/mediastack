# Hardware Plan

## Current Hardware

- Host: Lenovo desktop
- CPU: Intel i5-10400
- RAM: 12GB
- SSD: 512GB internal SSD
- OS today: Windows 11 Pro
- Media disk: Seagate Exos ST28000NM001C 28TB SATA HDD
- Planned expansion: TerraMaster D9-320 9-bay USB 3.2 Gen 2 DAS

## Goal

Build a scalable local movie and TV server. Jellyfin is implemented in the
current compose file. Plex can be added later if household clients need Plex's
app ecosystem.

The server should support:

- Large local libraries, potentially tens of thousands of files
- One 28TB disk now
- Multiple large drives later
- A migration path to Ubuntu Server or Unraid
- Safe operations around deletes, renames, and cleanup automation

## Recommended Role For Each Device

### Lenovo SSD

Use for:

- Operating system
- Docker engine
- Compose repo
- Application config
- SQLite/Postgres databases
- Jellyfin metadata
- Logs
- Backup staging

Reason: app databases and metadata perform much better on SSD than on a large
spinning media disk or USB DAS.

### 28TB Exos HDD

Use for:

- Movies
- TV
- Downloads and seeding data

Downloads and imported media should live on one filesystem if Sonarr/Radarr
hardlinks are expected to work.

### TerraMaster D9-320

Use later for:

- Additional media disks
- Expansion beyond the initial 28TB drive
- Possible Unraid array disks
- Possible mergerfs/SnapRAID or Linux pool disks

Risks and requirements to plan around:

- USB disconnects can interrupt Docker bind mounts.
- Drive order can change after reboot unless mounted by UUID or label.
- SMART passthrough may vary by USB enclosure and OS.
- Multi-drive pooling choices should be made before enabling automation that
  moves, renames, or deletes files.
- Label every disk or mount by UUID. Do not depend on `/dev/sdX` order.
- Use stable mount paths that survive reboot, for example `/media/storage` or
  Unraid shares with stable container paths.
- Test how the host behaves if the DAS is disconnected and reconnected.
- Add SMART monitoring after confirming the enclosure exposes disk health data.
- This repo includes host-side SMART scripts and systemd timers in `scripts/`;
  see `docs/disk-health.md`.
- Keep `torrents/` and `media/` under one filesystem or pool when hardlinking.
  If downloads and media land on different shares/filesystems, Sonarr/Radarr
  will copy instead of hardlinking.

## Operating System Recommendation

### Best Production Choice Now: Ubuntu Server LTS

Ubuntu Server is the cleanest path for this repo because the existing stack is
already Linux and Docker oriented. It supports:

- `/dev/net/tun` for Gluetun
- `/dev/dri` for Intel Quick Sync
- systemd timers
- stable mount units
- Docker Engine and Compose plugin

Recommended layout:

```text
/opt/mediastack/compose        # repository files
/opt/mediastack/config         # app state on SSD
/opt/mediastack/backups        # config backup staging
/media/storage/data            # media/downloads on Exos
```

### Windows 11 Pro

Windows can be used for an interim media server with native Jellyfin or Plex,
but this repository is not ready for a full native Windows deployment.

Avoid running the full automation stack against the 28TB media drive through
Docker Desktop until path mapping, VPN behavior, permissions, and drive
disconnect behavior are tested. Windows drive letters and Docker Desktop volume
semantics are a poor fit for the current Linux compose file.

Treat Windows as staging/testing only for this repo. Production should be
Ubuntu Server or Unraid.

### Unraid

Unraid is a strong future option after more drives are added. Main cautions:

- Keep downloads and media under a layout that preserves hardlinks.
- Prefer appdata/config on SSD/cache.
- Test Sonarr/Radarr hardlinks before importing a large library.
- Convert compose services carefully or use Docker Compose Manager.
- Start cleanup tools disabled until paths and permissions are verified.

## Filesystem And Pooling Notes

For one disk on Ubuntu:

- Use ext4 or XFS.
- Mount by UUID.
- Add a systemd mount dependency so Docker starts after storage is mounted.

For multiple disks later:

- Unraid: easiest mixed-drive expansion and parity model.
- mergerfs + SnapRAID: flexible Linux option for media libraries.
- ZFS: excellent integrity features, but less flexible for random single-disk
  expansion and wants more RAM/planning.

Whichever path is chosen, test hardlinks:

```bash
ln /media/storage/data/torrents/test-file /media/storage/data/media/test-file
stat /media/storage/data/torrents/test-file /media/storage/data/media/test-file
```

Both files should show the same inode and link count greater than 1.

## Transcoding Plan

The Intel i5-10400 includes Intel UHD Graphics 630, which can be used for Intel
Quick Sync transcoding on Linux.

Deployment implications:

- Keep Jellyfin's `/dev/dri:/dev/dri` mapping.
- Use Intel-specific comments and target-host group IDs.
- On the target Linux host, check the real render/video groups:

```bash
getent group render
getent group video
ls -l /dev/dri
```

For a home LAN, prefer direct play whenever possible. Transcoding should be a
fallback for incompatible clients or remote access, not the normal path.

## Capacity Plan

28TB raw is large but not infinite. Practical headroom is lower after
filesystem overhead and safety margin.

Operational thresholds:

- Below 70 percent full: normal operation
- 70 to 80 percent full: start planning expansion or cleanup
- 80 to 90 percent full: stop bulk imports and review large folders
- Above 90 percent full: high risk for failed downloads, database writes, and
  bad operator decisions under pressure

Do not wait until the drive is nearly full before deciding between another
single disk, DAS expansion, or Unraid.
