# Pi-hole

Pi-hole is an opt-in LAN DNS service behind the Compose `dns` profile. It
stores configuration on the SSD under `CONFIG_ROOT/pihole` and does not touch
the media drive. Starting Pi-hole does not change router or client DNS.

## Network Design

- DNS: `${LAN_IP}:53/tcp` and `${LAN_IP}:53/udp`, bound only to the LAN IP
- Admin UI: host port `8053`, available through the existing LAN/Tailscale
  firewall allowlists
- DHCP: remains on the home router; Pi-hole DHCP is not enabled
- Caddy: remains on host port `80`; Pi-hole uses `8053` to avoid collision
- Container DNS: the media containers are not switched to Pi-hole initially

This follows Pi-hole's Docker bridge guidance by setting
`FTLCONF_dns_listeningMode=ALL`. Only `/etc/pihole` is persisted for a new
Pi-hole v6 deployment.

## Preflight

Give the Lenovo a DHCP reservation/static lease for its current LAN address
before using it as DNS. On the current host that address is `192.168.0.172`.

Check that the address is present and inspect port 53 listeners:

```bash
ip -4 addr show
sudo ss -lntup | grep -E '(:53\\s)|(:53$)' || true
```

Ubuntu commonly has `systemd-resolved` on `127.0.0.53`; that loopback listener
normally does not conflict with Compose binding Pi-hole specifically to
`LAN_IP`. A listener on `0.0.0.0:53` or `${LAN_IP}:53` must be resolved before
starting Pi-hole.

Generate a unique admin password and put it in `.env` without printing it into
shell history:

```bash
read -rsp "Pi-hole password: " PIHOLE_PASSWORD; echo
printf 'PIHOLE_WEBPASSWORD=%s\n' "$PIHOLE_PASSWORD" >> .env
unset PIHOLE_PASSWORD
```

If `.env` already has `PIHOLE_WEBPASSWORD`, edit that line instead of adding a
duplicate.

## Start And Validate

Preview startup:

```bash
DRY_RUN=1 ./scripts/start-pihole.sh
```

Start Pi-hole:

```bash
APPLY=1 ./scripts/start-pihole.sh
docker compose --profile dns ps pihole
docker logs --since=5m pihole
```

Apply the updated firewall rules only after reviewing the dry-run:

```bash
LAN_SUBNET=192.168.0.0/24 DRY_RUN=1 ./scripts/apply-firewall-rules.sh
LAN_SUBNET=192.168.0.0/24 APPLY=1 ./scripts/apply-firewall-rules.sh
```

Test Pi-hole directly before changing router DNS:

```bash
sudo apt install -y dnsutils
dig @192.168.0.172 pi-hole.net
dig @192.168.0.172 doubleclick.net
curl -I http://192.168.0.172:8053/admin/
```

Open `http://192.168.0.172:8053/admin/` on the LAN. The admin UI is also
reachable remotely through Tailscale at
`http://100.115.252.112:8053/admin/`; DNS itself remains LAN-only.

## Router Cutover

After direct queries pass, set the router's LAN/DHCP DNS server to
`192.168.0.172`. Do not set a public resolver as a secondary DNS server:
clients may bypass Pi-hole unpredictably. Renew a test client's DHCP lease or
reconnect it to Wi-Fi, then confirm the client uses Pi-hole and appears in the
query log.

Change only DNS settings. Do not disable router DHCP.

## Rollback

If clients lose DNS, restore the router's previous DNS setting first. Then:

```bash
docker compose --profile dns stop pihole
```

Stopping or removing the container does not delete `CONFIG_ROOT/pihole`.

## Updates And Backups

Pi-hole's configuration is included in the existing `CONFIG_ROOT` backup. DIUN
may notify about new images; update deliberately with the stack's normal
update process. Pi-hole refreshes its ad lists automatically.
