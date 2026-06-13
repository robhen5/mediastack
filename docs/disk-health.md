# Disk Health Monitoring

This stack depends on one large HDD today and a future USB DAS later. SMART
monitoring should run on the host, not inside Docker, because the host has the
real block device paths and USB/SATA passthrough behavior.

## What This Adds

- Daily read-only SMART health checks via `scripts/check-disk-health.sh`
- ntfy alerts when SMART health is not OK, temperature is high, or key failure
  counters are nonzero
- Monthly SMART long self-tests via `scripts/start-disk-long-test.sh`
- systemd service/timer units for both workflows

The scripts do not move, rename, delete, format, or mount anything.

## Configure Devices

Install smartmontools:

```bash
sudo apt update
sudo apt install smartmontools
```

Find stable disk names:

```bash
ls -l /dev/disk/by-id/
```

Use by-id paths in `.env`, not `/dev/sdX`:

```env
SMART_DEVICES="/dev/disk/by-id/ata-ST28000NM001C_replace_with_real_serial"
SMARTCTL_OPTIONS=
SMART_TEMP_WARN_C=50
SMART_NTFY_URL=http://localhost:2586
SMART_NTFY_TOPIC=mediastack-alerts
```

For the future TerraMaster D9-320, add each exposed disk by stable by-id path
after confirming `smartctl -a` works. Some USB bridges require extra options,
commonly `SMARTCTL_OPTIONS="-d sat"`. Test that manually before putting it in
the timer.

## Manual Test

Run this before installing timers:

```bash
sudo /opt/mediastack/scripts/check-disk-health.sh
```

Start one long self-test manually:

```bash
sudo /opt/mediastack/scripts/start-disk-long-test.sh
```

Check progress or results:

```bash
sudo smartctl -a /dev/disk/by-id/ata-ST28000NM001C_replace_with_real_serial
```

Large HDD long tests can take many hours. This is normal.

## Install Timers

```bash
sudo install -m644 /opt/mediastack/scripts/check-disk-health.service /etc/systemd/system/
sudo install -m644 /opt/mediastack/scripts/check-disk-health.timer /etc/systemd/system/
sudo install -m644 /opt/mediastack/scripts/start-disk-long-test.service /etc/systemd/system/
sudo install -m644 /opt/mediastack/scripts/start-disk-long-test.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now check-disk-health.timer start-disk-long-test.timer
systemctl list-timers check-disk-health.timer start-disk-long-test.timer --no-pager
```

Force a health check now:

```bash
sudo systemctl start check-disk-health.service
journalctl -u check-disk-health.service -n 80 --no-pager
```

## Alert Behavior

The check alerts through ntfy when `SMART_NTFY_URL` is set. With the current
stack, use:

```env
SMART_NTFY_URL=http://localhost:2586
SMART_NTFY_TOPIC=mediastack-alerts
```

If ntfy is down, the check still fails in systemd/journal so the problem is
visible locally.

## TerraMaster D9-320 Notes

- Label each physical disk and record its by-id path.
- Do not rely on `/dev/sdX` order. USB disk order can change after reboot.
- Confirm SMART passthrough for each bay before trusting alerts.
- Keep the DAS on stable power and avoid loose USB cabling.
- If a disk disappears, treat it as a storage incident before starting the
  media stack or cleanup tools.
