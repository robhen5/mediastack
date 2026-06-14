# Risk Register

This register focuses on data loss, scaling, performance, and deployment risks
for the Lenovo plus 28TB Exos media server plan.

| Priority | Risk | Evidence in repo | Impact | Mitigation |
|---|---|---|---|---|
| P0 | Wrong host paths | Compose uses `.env` path variables; the target host must set them correctly | Containers fail or write data to the wrong place | Verify `MEDIASTACK_ROOT`, `CONFIG_ROOT`, `BACKUP_ROOT`, and `DATA_ROOT` before deployment |
| P0 | Cleanup deletes wanted files | qbitmanage, Cleanuparr, Sonarr/Radarr delete workflows, legacy manual `rm -rf` docs | Irrecoverable media loss | qbitmanage ships `QBT_DRY_RUN=true`; cleanuparr docs require UI Test Mode; cleanup profile gated. See `docs/SAFETY.md` §3-§4. |
| P0 | No config restore test | Backups are documented, but no automated restore verification exists | App databases and secrets could be lost | `scripts/backup-config.sh` + `scripts/restore-config-test.sh`. Quarterly rehearsal in `docs/SAFETY.md` §6. |
| P0 | Storage mount missing at container start | Linux bind mounts can create empty host folders if the real disk is not mounted | Apps may scan empty libraries or write to SSD by accident | Use stable mounts and make Docker depend on mounted storage |
| P0 | Unpackerr post-extract deletion | Unpackerr can delete extracted files (and optionally originals) after *arr import | Imports point at nothing on a misconfigured (split-filesystem) deployment | Default `UN_*_DELETE_ORIG=false`, `UN_*_DELETE_DELAY=${UNPACKERR_DELETE_DELAY:-9999h}`; shorten only after 30-day safe mode (`docs/SAFETY.md` §3) |
| P1 | Hardlinks broken by split filesystems | Stack depends on one `/data` filesystem | Imports become slow full copies and seeding/library dedupe fails — fills 28TB at 2× rate | `scripts/test-hardlinks.sh`, per-import History review, weekly `df -h`. See `docs/SAFETY.md` §7. |
| P1 | cross-seed misconfig duplicates imports | `linkType` or `dataDirs` errors cause *arrs to import a cross-seeded copy as a separate release | Library has phantom duplicates; disk fills | Compose comment directs starting with `action: "save"` for one week; recommend `linkType: "hardlink"` |
| P1 | Windows deployment mismatch | Repo assumes Linux paths, devices, bash, systemd, Docker CLI | Production deployment fails or behaves differently | Use Ubuntu Server or Unraid for production; treat Windows as interim only |
| P1 | Host-specific UID/GID values | Values are parameterized but still must match the target host | Permission failures, broken GPU access, Docker socket access issues | Set `PUID`, `PGID`, `RENDER_GID`, `VIDEO_GID`, and `DOCKER_GID` from target-host commands |
| P1 | Hardware acceleration not verified | Compose exposes `/dev/dri` for Intel Quick Sync | Jellyfin transcoding may fail or use CPU | Test one forced transcode on the i5-10400 |
| P1 | WebUIs exposed on all interfaces | Most ports use `host:container` without localhost binding | LAN users can reach admin apps | Bind admin ports to localhost or management network |
| P1 | Firewall rules not reproducible | UFW was configured manually on the Ubuntu host | Rebuilds or migrations may accidentally expose admin ports | Capture LAN/Tailscale allowlist in `docs/firewall.md` and `scripts/apply-firewall-rules.sh` |
| P1 | Rolling `latest` image tags | Many services use `latest` | Unexpected breaking upgrades | Pin major versions or use scheduled/manual update process |
| P1 | Docker socket exposure | Homepage and Diun mount `/var/run/docker.sock:ro` | Container compromise can reveal host/container metadata | Keep read-only, restrict access, or remove if not needed |
| P1 | qBittorrent namespace staleness | Docs and `update.sh` account for Gluetun recreation | qBit appears up but loses internet | Keep forced recreation logic and monitor `gluetun:8080` |
| P1 | Proton forwarded port drift | Scripts exist to sync qBit listen port | Poor torrent connectivity | Validate hook and timer on target Linux host |
| P2 | Large Jellyfin metadata growth | Jellyfin config is SSD-backed but thumbnails/trickplay can grow | SSD fills or scans slow down | Monitor config size; enable expensive metadata features gradually |
| P2 | Library scan I/O saturation | Tens of thousands of files on HDD/USB DAS | Slow playback/imports during scans | Schedule scans, avoid full refreshes, keep metadata on SSD |
| P2 | Bazarr scan cost | Bazarr can scan large TV libraries | CPU/I/O spikes and slow subtitle queue | Tune schedules and language profiles |
| P2 | qBittorrent memory growth | Many torrents and WebUI/API calls | 12GB RAM may become tight | Limit active torrents, monitor memory, consider RAM upgrade |
| P2 | USB DAS disconnects | TerraMaster D9-320 planned over USB | Missing/stale mounts, interrupted writes | Use stable cabling, UPS, mount checks, SMART monitoring (`docs/disk-health.md`), and cautious automation |
| P2 | No health checks in compose | Restart policies exist but health checks mostly absent | Failures are less visible to Docker | Add health checks or Uptime-Kuma monitors |
| P2 | Logs grow unchecked | No central log rotation config in repo | Disk pressure over time | Add Docker logging options or host logrotate guidance |
| P3 | Plex not implemented | Repo is Jellyfin-centric | Plex clients unavailable | Add Plex later as a separate service sharing media read-only |
| P3 | Unraid path conversion | No Unraid templates | Migration friction | Add Unraid-specific docs/templates after hardware expansion |

## Data-Loss Controls To Add First

The authoritative version of this list — with cadence, scripts, and
graduation criteria — lives in `docs/SAFETY.md`. Summary:

1. Back up `.env` and `config/` via `scripts/backup-config.sh` (weekly cron).
2. Restore the latest backup via `scripts/restore-config-test.sh` (quarterly).
3. Confirm media disk mount before Docker starts.
4. Keep qbitmanage and Cleanuparr disabled until the `cleanup` profile is
   deliberately enabled. Even then, qbitmanage starts in `QBT_DRY_RUN=true`.
5. Avoid auto-delete tools that delete watched media until seed-time and
   retention rules are fully understood. No Maintainerr/Janitorr.
6. Keep media deletion a manual operator action until the library is stable.
7. Run `scripts/test-hardlinks.sh` after first deploy and after every storage
   layout change.
8. Operate in `docs/SAFETY.md` "first 30 days safe mode" before flipping any
   destructive defaults.

## Scaling Controls To Add First

1. Put application config and metadata on SSD.
2. Keep downloads and media hardlink-compatible.
3. Monitor disk fullness at 70, 80, and 90 percent thresholds.
4. Add Uptime-Kuma and ntfy early.
5. Add SMART/disk monitoring for the Exos and future DAS disks via
   `docs/disk-health.md`.
6. Add RAM if qBittorrent plus Jellyfin plus indexers push the host into swap.
