# Installation, migration and recovery

This repository is derived from a **working** Canon LBP2900 setup on Synology
DSM/Xpenology 7.3.2. The refactored multi-stage build and Supervisor-based
startup have **not yet been tested on the actual NAS**. Test in a separate
project directory first; do not replace the production container blindly.

## 1. Files and safety

Tracked: `Dockerfile`, `compose.yaml`, `start.sh`, `supervisor.conf`,
`cups-config/cupsd.conf`, `avahi/*.in`, `restore-avahi.sh`, Windows script,
docs, `.env.example`, and a pinned vendor driver ZIP. Not tracked:
`cups-persistent/` (includes private CUPS TLS keys), `data/` (print jobs),
`.env`, diagnostic logs and legacy `cups/`.

The repository is **not a backup** of live CUPS queues. Back up
`cups-persistent/` separately and protect its contents.

## 2. Configure

```sh
cp .env.example .env
# Edit NAS_IP, IPP_PORT, LPR_PORT, TZ, USB_LP_DEVICE
ls -l /dev/usb/lp0
ls -l /dev/bus/usb/
docker compose config
```

The example assumes `NAS_IP=192.168.23.10`, `IPP_PORT=8631`,
`LPR_PORT=1515`, `USB_LP_DEVICE=/dev/usb/lp0`. Keep this IP static on the LAN.
The container maps the entire USB bus and permits major 189 devices; this is
broader access than ideal. Restrict network access to trusted LAN clients.

## 3. Build and start (new installation)

```sh
docker compose build
docker compose up -d
docker compose ps
docker compose logs --tail=100
```

The Docker build verifies SHA-256 of the bundled `vendor/captdriver-master.zip`,
then builds `rastertocapt` and the Canon PPD in Debian Bookworm. A new empty
`cups-persistent/` is initialized from the Debian CUPS defaults and
`cups-config/cupsd.conf`. Existing `/etc/cups/cupsd.conf` is not overwritten.

Verify the USB backend inside the container:

```sh
docker exec canon-lbp2900 /usr/lib/cups/backend/usb
```

For the original printer, the USB URI was:
`usb://Canon/LBP2900?serial=0000A386UFWf`. Use the URI actually returned
by your USB backend, not necessarily this serial.

Create the queue **once**:

```sh
docker exec canon-lbp2900 lpadmin \
  -p Canon_LBP2900 -E \
  -v 'usb://Canon/LBP2900?serial=0000A386UFWf' \
  -P /opt/canon/CanonLBP-2900-3000.ppd
docker exec canon-lbp2900 lpadmin -p Canon_LBP2900 -o printer-is-shared=true
docker exec canon-lbp2900 lpadmin -d Canon_LBP2900
docker exec canon-lbp2900 lpstat -t
```

A CUPS 2.4 warning about deprecated PPD drivers is expected.
Do not create the queue again when restoring a saved `cups-persistent/`.

Test physical printing (job acceptance alone is insufficient):

```sh
docker exec canon-lbp2900 sh -c \
  'printf "Canon LBP2900 test\n" | lp -d Canon_LBP2900'
```

## 4. Avahi / Android discovery

The NAS (not the container) runs Avahi and advertises
`Canon LBP2900 (Docker CUPS)` via `_ipp._tcp`. The generated XML contains the
IPP port, queue path and NAS IP. The duplicate DSM advertisement
`usbprinter1 @ microwave` is disabled by renaming its service file; this does
**not** delete the physical printer or DSM queue.

As root on the NAS:

```sh
./restore-avahi.sh
avahi-browse -rt _ipp._tcp
```

The script reads `.env` and writes `/etc/avahi/services/canon-lbp2900.service`,
disables `/etc/avahi/services/bonjour-usbprinter1.service` if present, then
`touch`es the Canon XML. Run it from DSM Task Scheduler at system boot as
**root**, using an absolute project path, for example:

```sh
sleep 60
/volume1/docker/canon-lbp2900/restore-avahi.sh
```

If the repository lives elsewhere, change the absolute path. DSM may
regenerate the duplicate advertisement after the boot task; check after a
reboot. A successful boot-task recovery has not yet been confirmed.

On Ubuntu:

```sh
avahi-browse -rt _ipp._tcp
avahi-resolve-host-name microwave.local
```

Expect host `microwave.local`, IP `192.168.23.10`, port `8631`, and
`rp=printers/Canon_LBP2900`. On the original NAS, Avahi announced on both
`eth0` (`192.168.23.10`) and `eth1` (`169.254.169.182`); the LAN address
was correct. Avoid altering NAS network interfaces without investigation.

Android: enable the built-in print service and select
`Canon LBP2900 (Docker CUPS)`. Mopria Print Service previously reported
"printer not ready"; the built-in service printed successfully.

## 5. Ubuntu IPP

Use `ipp://192.168.23.10:8631/printers/Canon_LBP2900` (replace IP/port).
CLI test:

```sh
lpstat -h 192.168.23.10:8631 -e
printf 'Ubuntu print test\n' | lp -h 192.168.23.10:8631 -d Canon_LBP2900
```

## 6. Windows 10 LPR

Run `install-canon-lbp2900.ps1` from **elevated Windows PowerShell**.
The script enables the LPR port monitor, uses `Microsoft PS Class Driver`,
creates LPR queue `Canon_LBP2900`, and sets the port to NAS TCP `1515`
(the Windows port monitor defaults to 515). It may require rebooting Windows.

Edit `$serverIP` and `$serverPort` in the script if different from the example.
Do not substitute the original Canon CAPT Windows driver for the PostScript
class driver in this server-side rendering architecture.

## 7. Migration from an existing working NAS

**Do not run two containers with the same name and host ports.** The working
instance should remain untouched while validating the new image build in an
isolated project. Build without starting the new service:

```sh
docker compose build
```

To migrate, stop the old service in a maintenance window, back up
`cups-persistent/` and `data/`, copy them into the new project, check owner
and permissions, then start the new container. Keep the old project intact
for rollback. The new `start.sh` does not overwrite existing CUPS settings.

When testing with existing queue data, verify:

```sh
docker exec canon-lbp2900 lpstat -t
docker exec canon-lbp2900 /usr/lib/cups/backend/usb
docker compose ps
```

A saved `printers.conf` must be mounted as part of the whole `/etc/cups`
directory. Binding only `printers.conf` causes CUPS atomic-write errors
(`Device or resource busy`).

## 8. Troubleshooting

| Symptom | Check |
|---|---|
| IPP page unavailable | `curl -I http://NAS_IP:IPP_PORT/printers/Canon_LBP2900` and `docker compose ps` |
| Queue disabled | `docker exec canon-lbp2900 lpstat -t` |
| USB backend missing | `/dev/usb/lp0`, `/dev/bus/usb`, Docker cgroup rule |
| CUPS says `Failed to open PPD` | PPD existence and mode `644` in `cups-persistent/ppd/` |
| Job completed, no paper | `/var/log/cups/error_log` and physical printer |
| Avahi browse `+` but resolve times out | `touch /etc/avahi/services/canon-lbp2900.service` |
| Duplicate `usbprinter1` returns | Check DSM regenerated `bonjour-usbprinter1.service` |
| Windows can't connect | Check TCP 1515, LPR queue name, PS class driver, port monitor |

Useful commands:

```sh
docker compose logs --tail=100
docker exec canon-lbp2900 lpstat -t
docker exec canon-lbp2900 tail -100 /var/log/cups/error_log
avahi-browse -rt _ipp._tcp
```

## 9. GitHub publication

Only commit files included by `.gitignore`. Verify with:

```sh
git init
git add .
git status --short
git ls-files
```

Never commit `cups-persistent/ssl/*.key`, `data/`, raw print jobs or a ZIP of
the entire working NAS directory. The bundled driver archive includes GPLv3
source and license; read `LICENSE-THIRD-PARTY.md` before redistribution.
