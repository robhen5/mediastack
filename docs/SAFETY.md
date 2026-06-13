# Mediastack Data-Loss Safety Plan

This is the operator's reference for keeping the 28TB Exos drive and the
app config databases safe from automation-driven deletion or accidental
duplication. Read it once before first deploy, again before enabling any
cleanup automation, and again before any disk replacement or migration.

The single most expensive failure mode here is **silent data loss**:
qbitmanage removes a torrent whose only library hardlink also disappears
(because Sonarr is told to delete on upgrade); Cleanuparr's Download
Cleaner removes a private-tracker torrent inside its required seedtime;
Sonarr's "Delete files" toggle removes the only seeding hardlink. Any of
those land the operator on a re-download path for content they thought
they owned.

The second most expensive failure mode is **silent duplication**:
torrents/ and media/ end up on different filesystems (or different
sub-mounts of the same nominal pool), Sonarr/Radarr fall back to
full-copy imports, and the 28TB Exos fills at 2× the expected rate.

This document is the project's authoritative answer to both.

---

## 1. Inventory of destructive and semi-destructive workflows

Everything in the stack that can move, rename, delete, or duplicate
media or config, ranked by blast radius.

| Service | What it can do | Default state | Where configured |
|---|---|---|---|
| **qbit_manage** | Delete torrents + on-disk files based on ratio / seedtime / orphan rules. Runs every 30 min. | Behind `cleanup` profile **AND** `QBT_DRY_RUN=true` (report-only). | `docker-compose.yml` qbitmanage block + `config/qbitmanage/config.yml` |
| **Cleanuparr (Queue Cleaner)** | Remove stalled/dead in-progress downloads and tell *arrs to grab alternatives. | Behind `cleanup` profile; must enable per-module in UI. | `docker-compose.yml` cleanuparr block + UI |
| **Cleanuparr (Download Cleaner)** | Remove already-seeding torrents by ratio/seedtime. Overlaps qbitmanage. | Behind `cleanup` profile; intentionally **leave OFF**. | UI only |
| **Cleanuparr (Seeker)** | Mass missing-item / cutoff-unmet search against the *arrs. Can pound public indexers. | Behind `cleanup` profile. | UI only |
| **Sonarr/Radarr "Delete files"** | Permanently removes the library hardlink (and the seeding copy if it was the last link). | Manual checkbox per delete; operator decision. | Per-app UI |
| **Sonarr/Radarr upgrade-replace** | When a better release is grabbed, the old file is deleted from media/ (and the hardlink count drops). | Default on; safe in isolation if hardlinks are working. | Per-app Media Management settings |
| **Sonarr/Radarr "Delete empty folders"** | Removes empty series/movie dirs after deletion. | Off by default; toggle in Media Management. | Per-app Media Management settings |
| **Unpackerr** | Extracts archives into the torrent folder. Can delete originals and extracted files on a delay. | `DELETE_ORIG=false`; `DELETE_DELAY=9999h` (effectively never). | `docker-compose.yml` unpackerr env + `.env` `UNPACKERR_DELETE_DELAY` |
| **cross-seed** | Creates hardlinks/symlinks into a parallel tree to seed the same payload across multiple trackers. Misconfig can cause *arrs to import duplicates. | Behind `optional`/`automation` profile; recommend `action: "save"` for the first week. | `config/cross-seed/config.js` |
| **autobrr** | Auto-grabs from private-tracker announce channels. Not destructive itself, but feeds qBit and indirectly the *arrs. | Behind `optional`/`automation`. | UI |
| **Recyclarr** | Writes TRaSH quality profiles into Sonarr/Radarr. Not destructive of files, but a bad profile can drive aggressive upgrade-replace cycles. | Cron at noon; behind `optional`/`automation`. | `config/recyclarr/recyclarr.yml` |
| **update.sh** | `docker compose pull` + `up -d` + `docker image prune -f`. Touches images, not media. Supports `DRY_RUN=1`. | Manual invocation. | `scripts/update.sh` |
| **qBit + Gluetun namespace stale state** | If qBit's namespace handle goes stale, an operator might delete-and-readd torrents trying to fix it — wiping the hardlinked library copies. | Mitigated by `update.sh` and the port-sync hook. | `scripts/update.sh` |
| **Legacy `rm -rf` examples** | `docs/legacy/MAINTENANCE.md` shows `rm -rf data/manga/<Series>/` as the manga delete pattern. Easy to mistype the path. | Legacy reference; not invoked by anything. | `docs/legacy/MAINTENANCE.md` |
| **Maintainerr / Janitorr** | Auto-delete media by watch status/age. | **Not deployed.** Do not add without a separate safety review. | n/a |

Tools NOT in this stack but commonly bolted onto media servers — and
explicitly **rejected** for now: Maintainerr, Janitorr, Tdarr (re-encode
in place is destructive of bytes if the original is removed),
Watchtower (auto-image-pulls bypass `update.sh`).

---

## 2. Safe default behavior shipped in this repo

This pass makes the default `docker compose --profile first-deploy up -d`
incapable of automatically deleting media. Specifically:

1. **`first-deploy` profile excludes all cleanup tools.** qbitmanage,
   Cleanuparr, autobrr, cross-seed, Recyclarr, and Unpackerr are NOT
   started. Verified by `tests/test_repo_static.ps1`.
2. **`cleanup` profile is opt-in.** Even `--profile optional` doesn't
   enable it — the operator has to pass `--profile cleanup` explicitly.
3. **qbitmanage starts in dry-run.** `QBT_DRY_RUN=${QBT_DRY_RUN:-true}`
   ships in the compose env block; `.env.example` documents and defaults
   the variable to `true`. The container will log what it WOULD remove
   instead of removing it, until the operator flips the flag.
4. **Cleanuparr ships with no auto-enabled modules.** Its profile gate
   stops it from running; its compose block instructs the operator to
   tick "Dry Run" / "Test Mode" on every module in the UI before saving.
5. **Unpackerr never deletes originals; never deletes extracted files
   for the first 30 days.** `UN_*_DELETE_ORIG=false` and
   `UN_*_DELETE_DELAY=${UNPACKERR_DELETE_DELAY:-9999h}`.
6. **cross-seed is opt-in via `automation`/`optional` profile.** The
   compose comment directs the operator to start with `action: "save"`
   in `config.js`, which only writes `.torrent` files — it does not
   inject anything into qBit.
7. **`scripts/update.sh` already supports `DRY_RUN=1`** and gates
   `docker image prune -f` behind the dry-run wrapper.

---

## 3. The "first 30 days" safe operating mode

Goal: nothing in the stack can delete media automatically while the
operator is still learning where automation will and won't surprise
them. Tracker rules, hardlink integrity, and backups are all verified
under no-deletion pressure.

### Profiles to run during the 30 days

```bash
docker compose --profile first-deploy up -d
```

Optionally add monitoring once core is stable:

```bash
docker compose --profile first-deploy --profile monitoring up -d
```

Use `--profile observability` only when you intentionally want the full
observability bundle, including Jellystat, Jellystat Postgres, and Diun.

**Do not** enable `cleanup` during the 30 days. Do not enable
`automation` for the first week (`cross-seed`, `autobrr`, `unpackerr`,
`recyclarr`) — add them one at a time after the core stack is verified.

### What the operator does during the 30 days

| Action | Why |
|---|---|
| Delete unwanted media **manually** via Sonarr/Radarr UI, checked "Delete files from disk." | Learn the two-step delete: *arr UI → qBittorrent right-click → Delete files. See `docs/legacy/MAINTENANCE.md` §"Delete content." |
| Run `scripts/backup-config.sh` weekly. | Build a backup history. The newest backup is what the next disk replacement restores from. |
| Run `scripts/restore-config-test.sh` once after the first weekly backup. | Confirm the archive actually contains the irreplaceable files. |
| Run `scripts/test-hardlinks.sh` after first deploy AND any storage layout change. | Catch silent fallback-to-copy before the library doubles. |
| Watch the *arrs' Activity → History → Imported tab for "Hardlink" vs "Copy." | Independent confirmation that imports are not duplicating bytes. |
| Watch `df -h $DATA_ROOT` weekly. | A sudden jump in usage that doesn't match grabs = silent copy fallback. |
| In Sonarr/Radarr → Settings → Media Management, **leave "Delete Empty Folders" OFF**. | Easier to recover from an accidental delete if the folder skeleton is still there. |
| In Bazarr, don't enable the "Auto delete subtitles" features. | Subtitle files are tiny but irrecoverable if Bazarr's matching breaks. |

### Day 30+ — graduating from safe mode

Only after all of these are true:

- [ ] Three or more `backup-config.sh` archives exist; the most recent
      was copied off-host.
- [ ] `restore-config-test.sh` passed against the latest archive.
- [ ] `test-hardlinks.sh` passed at least twice.
- [ ] No imported file in the last 30 days shows up as "Copy" in the
      *arr History view.
- [ ] `df -h $DATA_ROOT` growth matches grabbed-content size.
- [ ] qBittorrent has at least one private-tracker config (if relevant)
      with per-tracker seedtime rules written into `config/qbitmanage/config.yml`.

Then graduate one tool at a time:

1. **Unpackerr first.** Lower `UNPACKERR_DELETE_DELAY` to `1h` once the
   operator trusts that imports landed cleanly. Restart the container.
2. **Cross-seed second.** Switch `action: "save"` → `action: "inject"`
   in `config.js`. Watch Sonarr/Radarr History for unwanted duplicate
   imports for at least three days.
3. **qbitmanage third.** Set `QBT_DRY_RUN=false` in `.env`, recreate the
   qbitmanage container. Watch its logs for what it actually removes —
   the dry-run output should match the live output for at least the
   first 48 hours.
4. **Cleanuparr last.** Enable Queue Cleaner first (conservative
   strikes), then Seeker if you want it. **Never enable the Download
   Cleaner module** — that's qbit_manage's job and overlap risks
   double-deletes inside private-tracker seedtime windows.

---

## 4. Warnings before enabling deletion automation

These warnings exist in the compose comments too. They're collected here
so the operator can read them once before flipping any flag.

> **qbit_manage will permanently delete torrents and their on-disk
> files.** Files seeded inside a hardlink with no other library link
> become disk-free immediately. Tracker bans for early-deletion happen
> within hours of misconfigured seedtime rules. Do not flip
> `QBT_DRY_RUN=false` without first reading a full week of dry-run logs.

> **Cleanuparr's Queue Cleaner can re-trigger the *arr search loop**
> indefinitely if its strike threshold is too low. A slow but alive
> swarm gets killed, the *arr searches for another, that one is also
> slow, and you burn indexer quotas in a death spiral. Start with
> strikes ≥ 3 and a stall threshold ≥ 30 minutes.

> **Cleanuparr's Download Cleaner overlaps qbit_manage.** Running both
> double-manages seeding torrents and creates a race where one tool
> removes a torrent before the other's seedtime check completes. Leave
> Download Cleaner OFF; qbit_manage is the single source of truth for
> ratio/seedtime.

> **Sonarr/Radarr "Delete files from disk" removes the library
> hardlink.** If the torrent was the only other link, qBit will report
> the file as missing on its next recheck and pause the torrent (which
> may register as a non-seeding hit-and-run on private trackers). Use
> the two-step delete documented in `docs/legacy/MAINTENANCE.md`
> §"Delete content."

> **cross-seed's `linkType: "symlink"` will silently break Jellyfin
> playback** if `DATA_ROOT` is bind-mounted at different paths across
> containers. Stick with `linkType: "hardlink"` and the same
> `/data` mount everywhere — also a requirement for the *arrs' hardlink
> imports to work.

> **Recyclarr's TRaSH custom-format negatives can mark your whole
> library as "below cutoff,"** triggering a wave of upgrade-replace
> activity (each upgrade deletes the old file). Pin Recyclarr's
> templates by name in `recyclarr.yml` and review the diff before
> running it the first time.

> **Unpackerr's `DELETE_DELAY`, once shortened, deletes the extracted
> file the *arr imported from.** With hardlinks that's a no-op on disk,
> but on a split-filesystem deployment (which the hardlink test should
> have caught) it can leave the *arr pointing at nothing.

---

## 5. Backup plan

What's in scope and where it lives:

| What | Location | Risk if lost | Backup mechanism |
|---|---|---|---|
| `.env` | `${MEDIASTACK_ROOT}/.env` | All secrets: WireGuard key, qBit creds, app API keys, ntfy topic. | `scripts/backup-config.sh` |
| `docker-compose.yml` | `${MEDIASTACK_ROOT}/docker-compose.yml` | The deployment recipe. | Git + `backup-config.sh` |
| `scripts/` | `${MEDIASTACK_ROOT}/scripts/` | Port-sync hook, update, backup, hardlink test scripts. | Git + `backup-config.sh` |
| `config/qbittorrent/` | `${CONFIG_ROOT}/qbittorrent` | qBit session, fastresume files, categories, WebUI config. Without this, every active torrent has to be re-added (and the *arrs lose download-client tracking). | `backup-config.sh` |
| `config/sonarr/`, `config/radarr/` | `${CONFIG_ROOT}/sonarr`, `${CONFIG_ROOT}/radarr` | Series/movie database, watch history, indexer + download-client wiring, custom formats, API key, queue. | `backup-config.sh` |
| `config/prowlarr/` | `${CONFIG_ROOT}/prowlarr` | Indexer configs (Cloudflare cookies, login state), sync to *arrs, API key. | `backup-config.sh` |
| `config/bazarr/` | `${CONFIG_ROOT}/bazarr` | Language profiles, subtitle history. | `backup-config.sh` |
| `config/jellyfin/data/` and `config/jellyfin/metadata/` | `${CONFIG_ROOT}/jellyfin` | User accounts, watch progress, library DB, downloaded metadata, image cache (excluded), trickplay images. | `backup-config.sh` (cache + log + transcodes excluded) |
| `config/jellyseerr/` | `${CONFIG_ROOT}/jellyseerr` | User wiring to Jellyfin, request history. | `backup-config.sh` |
| `config/gluetun/` | `${CONFIG_ROOT}/gluetun` | Forwarded-port state. Regenerates from ProtonVPN; included for completeness. | `backup-config.sh` |
| `config/jellystat/` | `${CONFIG_ROOT}/jellystat` | App config only — stats are re-synced from Jellyfin. Postgres data dir (jellystat-db) is deliberately excluded. | `backup-config.sh` |
| Media payload | `${DATA_ROOT}/{torrents,media,books,audiobooks,manga}` | Hundreds of GB to multi-TB. Re-downloadable via the *arrs / trackers. | **NOT backed up.** Use the *arrs' history and the source trackers for recovery. Consider parity (SnapRAID, ZFS, Unraid) for the multi-drive future. |

Cadence and rotation:

- **Weekly automated backup.** Add a systemd timer (or cron) that runs
  `scripts/backup-config.sh`. The script keeps the last `KEEP=6`
  archives by default and verifies each archive's integrity via
  `tar -tzf` after writing it.
- **Ad-hoc before any change.** Before `update.sh`, before a compose
  edit, before any *arr major upgrade, before any cleanup-tool flag
  change.
- **3-2-1 if possible.** On-host copy + a second LAN host + an off-site
  encrypted copy (gpg-encrypted before upload — `.env` contains the
  WireGuard private key, treat the tarball as a secret).
- **Test the restore at least once a quarter.** Run
  `scripts/restore-config-test.sh` against the latest archive. A backup
  is fiction until it has been restored at least once.

What deliberately is NOT backed up by the script, and why:

- `config/caddy/data/caddy` and `config/caddy/config/caddy` — root-owned
  TLS/runtime state, regenerated from the Caddyfile on restart.
- `config/jellystat-db` — live Postgres data dir, file-copy of a
  running DB risks producing an inconsistent dump. Use Jellystat's UI
  backup feature instead.
- `config/diun` — image-version cache, rebuilds itself.
- `config/ntfy/attachments` + `config/ntfy/cache.db` — ephemeral
  push-message cache.
- `config/jellyfin/cache`, `config/jellyfin/log`,
  `config/jellyfin/transcodes` — regenerable cache, rotated logs,
  transient transcoding scratch (can be tens of GB).

---

## 6. Restore rehearsal checklist

Run this once after the first weekly backup, then at least quarterly.
The goal is to prove the archive could rebuild the stack from scratch
on a fresh Ubuntu install with `DATA_ROOT` empty.

### Quick rehearsal (does not touch live config)

```bash
./scripts/restore-config-test.sh
```

Pass criteria: script prints `PASS:` and shows all expected paths
present. No `[MISS]` lines.

### Full rehearsal (use a throwaway VM or second host)

- [ ] Fresh Ubuntu Server LTS, Docker + compose installed.
- [ ] Clone the git repo to `/opt/mediastack`.
- [ ] Copy the latest `mediastack-config-YYYYMMDD-HHMMSS.tar.gz` onto
      the box.
- [ ] Extract: `tar -xzf mediastack-config-*.tar.gz -C /opt/mediastack`
- [ ] Reconstruct the (empty) data root:
      `mkdir -p $DATA_ROOT/{torrents,media/{movies,tv},books,audiobooks,manga}`
- [ ] Confirm `.env` came back with all secrets intact.
- [ ] `docker compose --profile first-deploy up -d`
- [ ] Confirm every core service comes back without prompting for a
      first-time setup. Specifically:
  - [ ] qBittorrent WebUI accepts the saved password (no fresh
        password prompt = config restored cleanly).
  - [ ] Sonarr/Radarr show their library lists, even though `data/` is
        empty (they will mark every file as "missing" until you point
        them at restored media).
  - [ ] Jellyfin shows the user accounts.
  - [ ] Bazarr remembers the language profile.
  - [ ] Prowlarr's indexers are present.
- [ ] Run `./scripts/test-hardlinks.sh` on the restored host to confirm
      the new storage layout supports hardlinks before importing any
      media.
- [ ] Re-install the systemd timer for `sync-qbit-port`:

```bash
sudo install -m644 /opt/mediastack/scripts/sync-qbit-port.service /etc/systemd/system/
sudo install -m644 /opt/mediastack/scripts/sync-qbit-port.timer   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now sync-qbit-port.timer
```

- [ ] If the rehearsal box will not become the new prod, tear it down
      and document any surprises.

### What to do if the rehearsal fails

- A missing path in `restore-config-test.sh`'s `[ok]` list = add it to
  `scripts/backup-config.sh`'s include list, run a new backup, re-test.
- A container that won't start = read its logs, check the
  `--exclude` list in `backup-config.sh` did not accidentally drop a
  required state file, fix and re-archive.
- Permission errors after restore = the running container's PUID/PGID
  doesn't match what created the original files. Match `.env`'s PUID
  to the restored host's `id mediastack`.

---

## 7. Hardlink test plan

Hardlinks are the single mechanism preventing the 28TB Exos from
filling at 2× the expected rate. They are also the mechanism that lets
qBit keep seeding while Sonarr/Radarr "own" the library copy.

### Smoke test (run before any imports)

```bash
./scripts/test-hardlinks.sh
```

Pass criteria: script prints `PASS:`, the two test files share an
inode, link count is 2, devices match, and `du` reports the pair as a
single file's worth of bytes.

### Per-import sanity check

In Sonarr or Radarr → Activity → History → click an imported entry.
The "Imported" event will show either:

- "Hard Linked" — good
- "Copied" — BAD, stop and re-run `test-hardlinks.sh` and fix the
  filesystem layout before more grabs accumulate

### Per-week sanity check

```bash
df -h "${DATA_ROOT:-/media/storage/data}"
```

If usage grew much faster than the grabs the *arrs report this week,
hardlinks are silently broken even though the test script passes. The
most common cause is one specific category folder ending up on a
different filesystem (`torrents/manga/` on a separate share, etc.) —
re-run `test-hardlinks.sh` with `DATA_ROOT` pointed at each sub-tree.

### Failure modes to watch for

| Symptom | Likely cause |
|---|---|
| `test-hardlinks.sh` refuses on `ln` | torrents/ and media/ are on different filesystems. Re-pool. |
| Test passes, *arr History shows "Copied" | The *arr's path mapping doesn't have `torrents` and `media` under one container mount. Both must be subdirs of `/data` inside the container. |
| Test passes; disk usage doubles | A nested submount inside `media/` (common with Unraid shares) breaks hardlinks for one specific library. Re-run the test with `DATA_ROOT` pointed at the suspect subtree. |
| Files disappear after `qbitmanage` ran | Hardlinks were working; qbitmanage removed the torrent AND the library copy was the same inode. Restore `QBT_DRY_RUN=true` and re-read its logs. |
| qBittorrent reports "Missing files" after the *arr imports | The *arr is moving, not hardlinking. Sonarr/Radarr → Settings → Media Management → "Use Hardlinks instead of Copy" must be ON. |

---

## 8. Remaining risks after this safety pass

This pass dropped the most explosive defaults but does not — and
cannot — eliminate every risk. What remains:

1. **Operator-driven deletes are still possible at any time.** Sonarr
   and Radarr's "Delete files" checkboxes, qBittorrent's right-click
   "Delete files," and `rm -rf` examples in `docs/legacy/MAINTENANCE.md`
   are all still live. No automation guards against an operator who
   types the wrong path under time pressure.
2. **`first-deploy` does not back itself up.** The first backup only
   happens once the operator runs `scripts/backup-config.sh` for the
   first time. A disk failure between the first deploy and the first
   backup loses the operator's hand-configured app state. Mitigation:
   run the backup script the same day as first-deploy, before grabbing
   any content.
3. **The backup script keeps archives on the same host by default.** A
   bit-rot event on the SSD or a fire/theft loses both `.env` and every
   backup. Off-host copying is documented as a manual step but not
   automated.
4. **qbit_manage's dry-run flag is honored by the upstream image**, but
   if a future image release rewires the flag name (e.g., to
   `QBT_CMD_DRY_RUN`), the compose env will silently no-op and the
   tool will become destructive on the next pull. Mitigation: Diun
   already pings on image updates; the operator should review
   qbit_manage release notes before running `update.sh`.
5. **Cleanuparr's per-module dry-run is UI-only.** This repo cannot
   enforce it. An operator who unticks Test Mode in the Cleanuparr UI
   bypasses every safety gate this document provides. Mitigation: the
   compose comment block + this document + the dry-run-run-week
   discipline in §3.
6. **cross-seed config lives in `config/cross-seed/config.js`**, which
   is gitignored. A misconfigured `linkType` or `dataDirs` won't show
   up in any test in this repo. Mitigation: §4 warning + the
   "automation profile only after week 1" discipline.
7. **Hardlinks can be silently broken by future storage changes.**
   Adding the TerraMaster D9-320 DAS, migrating to Unraid, expanding
   into mergerfs or ZFS — each one is a chance for `torrents/` and a
   specific `media/<library>/` subtree to end up on different
   filesystems. Mitigation: re-run `test-hardlinks.sh` after any
   storage change, plus the `df -h` weekly sanity check.
8. **No automated detection of the "qBit-namespace stale → manual
   re-add" pattern.** If gluetun's IP rotates and qBit appears to lose
   its torrents, an operator who re-adds the torrents fresh (instead of
   running `update.sh` with the forced recreate) can end up with two
   qBit entries pointing at the same on-disk data, with conflicting
   seed states. Mitigation: `update.sh`'s recreate logic + the gotcha
   block in `docs/legacy/MAINTENANCE.md`.
9. **Recyclarr can be invoked manually** even when its profile is off
   (volume-mounted config persists). A misconfigured profile run at
   midnight before a library scan is still possible. Mitigation: pin
   templates by name and review diffs before invoking.
10. **The 28TB Exos is a single point of failure.** No RAID, no parity,
    no snapshots. A drive death loses all content, not just the
    delta since the last (config-only) backup. Mitigation: the
    DATA_ROOT contents are recoverable from the *arrs and trackers; the
    one-time pain after a drive death is hours/days of re-grabbing, not
    permanent loss. Real parity (Unraid array, SnapRAID, ZFS mirror)
    only becomes available after the planned TerraMaster D9-320
    expansion.

If any of these remaining risks change shape — new tools added, storage
layout changes, household members get write access — update §1 first,
then propagate the warnings into §4 and the test gates into §7.

---

## 9. See also

- `README.md` — quickstart and compose-profile cheatsheet.
- `docs/deployment-checklist.md` — phased deploy gates.
- `docs/risk-register.md` — full priority-ranked risk list.
- `docs/hardware-plan.md` — disk layout reasoning.
- `docs/legacy/MAINTENANCE.md` — operational runbook including the
  two-step deletion procedure.
- `scripts/backup-config.sh`, `scripts/restore-config-test.sh`,
  `scripts/test-hardlinks.sh` — the executable backing of this plan.
