# AGENTS.md

Repo-specific instructions for future Codex tasks.

## Project Context

This repo is a home media server stack plan, not a generic software app. The
target hardware is:

- Lenovo desktop with Intel i5-10400, 12GB RAM, 512GB SSD
- Windows 11 Pro currently installed
- One Seagate Exos ST28000NM001C 28TB SATA HDD
- Planned TerraMaster D9-320 9-bay USB 3.2 Gen 2 DAS for expansion
- Future migration may be Ubuntu Server or Unraid
- Timezone is `America/New_York`
- Primary goal is local movies/TV via Jellyfin or Plex, with this repo
  currently implementing Jellyfin and automation services

Read these first:

1. `README.md`
2. `docs/SAFETY.md`
3. `docs/hardware-plan.md`
4. `docs/risk-register.md`
5. `docs/deployment-checklist.md`
6. `docs/disk-health.md`
7. `docs/firewall.md`
8. Existing legacy docs only after that: `docs/legacy/SETUP.md`,
   `docs/legacy/MAINTENANCE.md`

## Current State

- The compose and scripts are Linux-oriented.
- Windows is a staging/testing path only; production should be Ubuntu Server or
  Unraid.
- Compose paths, identity, timezone, LAN, and device group values are
  parameterized through `.env`.
- Use `docker compose --profile first-deploy up -d` for the first safe launch.
- Use the `dashboard` profile for Homepage without also enabling Caddy.
- qbitmanage and Cleanuparr are behind the `cleanup` profile and must not be
  enabled casually.

## Change Discipline

- Do not make large rewrites unless the user explicitly asks.
- Prefer documentation, parameterization, and narrowly scoped compose changes.
- Preserve the hardlink model: downloads and media must share one filesystem
  under one container-visible root such as `/data`.
- Treat any cleanup/delete automation as high risk.
- Do not enable aggressive qbitmanage, Cleanuparr, Maintainerr, Janitorr, or
  similar deletion behavior without explicit user approval.
- Preserve the safety defaults in `docker-compose.yml` and `.env.example`:
  `QBT_DRY_RUN=true` on qbitmanage, `UN_*_DELETE_ORIG=false` and
  `UN_*_DELETE_DELAY=${UNPACKERR_DELETE_DELAY:-9999h}` on unpackerr, and
  `cleanup`-profile gating on qbitmanage + cleanuparr. Any change here must
  be flagged explicitly in the response and reviewed against `docs/SAFETY.md`.
- Keep `.env`, `config/`, `data/`, media payloads, logs, and backups out of git.

## Validation Expectations

When Docker and bash are available on the target host, run:

```bash
docker compose config
shellcheck scripts/*.sh
bash -n scripts/*.sh
```

If those tools are unavailable, report the exact blocker and do not imply that
compose or scripts were validated.

For deployment work, verify:

- VPN IP from inside Gluetun
- qBittorrent loses connectivity when Gluetun stops
- One successful hardlink import from download folder to media folder
- Jellyfin playback and Intel Quick Sync behavior
- Config backup and restore rehearsal
- Weekly `backup-config.timer` is installed only after a manual backup succeeds
  and at least one backup tarball is copied off-host.
- Disk health work should use stable `/dev/disk/by-id` paths and host-side
  smartmontools. Do not use `/dev/sdX` in docs or scripts except as a warning.
- Firewall work should preserve LAN/Tailscale allowlists and must not open
  admin ports to `0.0.0.0/0`.

## Hardware Guidance

- Use the SSD for app config, databases, metadata, logs, and backup staging.
- Use the 28TB Exos for media and downloads under one `DATA_ROOT`.
- Use stable Linux mount paths, not drive letters.
- For the i5-10400, prefer Intel Quick Sync over CPU transcoding.
- The TerraMaster D9-320 is USB DAS expansion. Plan for disk labels, stable
  mounts, SMART visibility, disconnect recovery, and future pooling before
  adding automation.

## Preferred Implementation Direction

Near-term production target should be Ubuntu Server on the Lenovo unless the
user chooses to keep Windows and defer automation. Unraid is a valid future
target when multiple drives are added, but hardlink behavior and share layout
must be tested before enabling Sonarr/Radarr imports and cleanup tooling.
