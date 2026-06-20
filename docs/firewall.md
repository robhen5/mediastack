# Firewall

The Ubuntu host should expose media/admin services only to the home LAN and
Tailscale. The current validated posture is:

- UFW active
- Default incoming: deny
- Default outgoing: allow
- Default routed: deny
- SSH and stack ports allowed from LAN and Tailscale only

## Validated Ports

| Port | Service |
|---|---|
| 22 | SSH |
| 80 | Caddy front door to Homepage |
| 3000 | Homepage dashboard |
| 3001 | Uptime Kuma |
| 5055 | Jellyseerr |
| 6767 | Bazarr |
| 7878 | Radarr |
| 8053 | Pi-hole admin UI |
| 8081 | qBittorrent WebUI through Gluetun |
| 8096 | Jellyfin |
| 8989 | Sonarr |
| 9696 | Prowlarr |
| 2586 | ntfy |
| 11011 | Cleanuparr |
| 53 TCP/UDP | Pi-hole DNS, LAN only |

Allowed source networks:

```text
LAN:       192.168.0.0/24
Tailscale: 100.64.0.0/10
```

Adjust `LAN_SUBNET` in `.env` if your home network changes.

## Apply Rules

Dry-run first:

```bash
LAN_SUBNET=192.168.0.0/24 DRY_RUN=1 ./scripts/apply-firewall-rules.sh
```

Apply:

```bash
LAN_SUBNET=192.168.0.0/24 APPLY=1 ./scripts/apply-firewall-rules.sh
```

The script does not delete existing UFW rules. Review rules manually:

```bash
sudo ufw status numbered
sudo ufw status verbose
```

## Manual Equivalent

```bash
sudo ufw allow from 192.168.0.0/24 to any port 22 proto tcp
sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp

for port in 80 3000 3001 5055 6767 7878 8053 8081 8096 8989 9696 2586 11011; do
  sudo ufw allow from 192.168.0.0/24 to any port "$port" proto tcp
  sudo ufw allow from 100.64.0.0/10 to any port "$port" proto tcp
done


# Pi-hole DNS is LAN-only. The admin UI above remains available over Tailscale.
sudo ufw allow from 192.168.0.0/24 to any port 53 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 53 proto udp

sudo ufw enable
sudo ufw status verbose
```

## Verified Checks

Expected UFW summary:

```text
Default: deny (incoming), allow (outgoing), deny (routed)
```

Expected local service checks:

```bash
curl -I http://192.168.0.172:8096
curl -I http://192.168.0.172:3000
curl -I http://192.168.0.172
```

Jellyfin may return `302 Found` to `web/`; Homepage and Caddy should return
`200 OK`.

## Safety Notes

- Always allow SSH from LAN and Tailscale before enabling UFW.
- Keep Tailscale SSH/access working before changing LAN rules.
- Do not allow these admin ports from `0.0.0.0/0`.
- The script intentionally avoids deleting rules because rule removal is the
  risky part. Remove old rules manually after reviewing `ufw status numbered`.
