# Canon LBP2900 — Docker CUPS print server for Synology DSM

USB Canon LBP2900 (Canon L11121E) shared over LAN with CUPS and the open-source
CAPT filter. **Ubuntu uses IPP**, **Windows 10 uses LPR**, and **Android uses
DNS-SD/IPP** advertised by the NAS's Avahi daemon.

```text
Ubuntu  -- IPP TCP 8631 -----------+
Android -- mDNS + IPP TCP 8631 ----+--> Synology NAS --> Docker CUPS --> CAPT --> USB --> Canon LBP2900
Windows -- LPR TCP 1515 ----------+
```

## Verified on the original NAS

- DSM/Xpenology 7.3.2, x86_64, LAN IP `192.168.23.10`.
- Printer CUPS queue `Canon_LBP2900`; USB URI from the original device:
  `usb://Canon/LBP2900?serial=0000A386UFWf`.
- Ubuntu IPP printing; Windows 10 via `Microsoft PS Class Driver` and LPR;
  Android built-in printing after Avahi announcement.
- After NAS reboot the CUPS queue was reachable, but mDNS DNS-SD resolution
  timed out until `touch` was run on the Avahi service file. The provided
  boot script refreshes it; **fully automatic reboot recovery remains to be
  confirmed**. Mopria was not working reliably; Android's built-in service was.

## Quick start

1. Clone the repository into a **new directory** (do not overwrite the working
   installation). `cp .env.example .env`, then set NAS IP, ports, timezone.
2. Confirm printer device `/dev/usb/lp0` and Docker Compose availability.
3. `docker compose build && docker compose up -d`.
4. Create the queue once using `lpadmin` (see [INSTALL.md](INSTALL.md)).
5. On the NAS as root run `./restore-avahi.sh` and add it as a DSM boot task.
6. Windows: run `install-canon-lbp2900.ps1` in elevated Windows PowerShell.

The driver snapshot is vendored in `vendor/captdriver-master.zip` and built
in a separate Docker build stage. The archive has a fixed SHA-256; its precise
upstream commit is unknown (see [license notes](LICENSE-THIRD-PARTY.md)).

**Security:** CUPS exposes printing on the local network without authentication
at `/printers/...`; do not forward ports 8631 or 1515 to the Internet. The
working CUPS configuration, private TLS keys and print jobs must not be
committed to Git.

See **[INSTALL.md](INSTALL.md)** for migration, troubleshooting, backups and
client instructions.
