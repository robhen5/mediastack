# Server Operations Notes

These notes capture live-host habits for the Ubuntu server at `/opt/mediastack`.

## Pulling Updates

The live server may have local operational edits from setup or emergency
hotfixes. If `git pull` fails with a message like:

```text
error: Your local changes to the following files would be overwritten by merge:
        scripts/request-jellyseerr-list.py
```

do not blindly reset the repo. First inspect the exact local change:

```bash
cd /opt/mediastack
git status --short
git diff -- scripts/request-jellyseerr-list.py
git diff --cached -- scripts/request-jellyseerr-list.py
```

For a different blocked file, replace the path in both `git diff` commands.

If the diff is only a local hotfix that was just pushed upstream, or a
mode-only executable-bit change, it is safe to discard that file and pull:

```bash
git restore --staged scripts/request-jellyseerr-list.py
git restore scripts/request-jellyseerr-list.py
git pull
chmod +x scripts/*.sh scripts/*.py
```

On older Git versions:

```bash
git reset HEAD scripts/request-jellyseerr-list.py
git checkout -- scripts/request-jellyseerr-list.py
git pull
chmod +x scripts/*.sh scripts/*.py
```

## Common Benign Local Changes

- `scripts/*.sh` mode changes after `chmod +x scripts/*.sh`
- `docker-compose.yml` local host/IP edits that should live in `.env`
- `scripts/request-jellyseerr-list.py` hotfixes made manually before upstream
  catches up
- untracked backups such as `docker-compose.yml.bak-jellystat-db-name`

Untracked backup files do not block `git pull`; leave them unless the user asks
to clean them up.

## Safety Rule

Never suggest a broad reset such as `git reset --hard` for the live server.
Discard only the specific file that was inspected and confirmed safe.
