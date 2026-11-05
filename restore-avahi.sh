#!/bin/sh
set -eu

# Run on Synology NAS as root. Override PROJECT_DIR when cloned elsewhere.
PROJECT_DIR=${PROJECT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}
AVAHI_DIR=${AVAHI_DIR:-/etc/avahi/services}
ENV_FILE="$PROJECT_DIR/.env"
[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE; copy .env.example to .env" >&2; exit 1; }
# Read only the two expected values, without evaluating arbitrary .env content.
getenv() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1 | tr -d '\r'; }
NAS_IP=$(getenv NAS_IP)
IPP_PORT=$(getenv IPP_PORT)
[ -n "$NAS_IP" ] && [ -n "$IPP_PORT" ] || { echo "NAS_IP and IPP_PORT required in .env" >&2; exit 1; }
case "$NAS_IP" in *[!0-9.]*|'') echo "Invalid IPv4 NAS_IP" >&2; exit 1;; esac
case "$IPP_PORT" in *[!0-9]*|'') echo "Invalid IPP_PORT" >&2; exit 1;; esac
[ "$IPP_PORT" -ge 1 ] && [ "$IPP_PORT" -le 65535 ] || exit 1
SOURCE="$PROJECT_DIR/avahi/canon-lbp2900.service.in"
TARGET="$AVAHI_DIR/canon-lbp2900.service"
[ -f "$SOURCE" ] || { echo "Missing $SOURCE" >&2; exit 1; }
mkdir -p "$AVAHI_DIR"
TMP=$(mktemp "$AVAHI_DIR/.canon-lbp2900.XXXXXX")
trap 'rm -f "$TMP"' EXIT HUP INT TERM
sed -e "s/@NAS_IP@/$NAS_IP/g" -e "s/@IPP_PORT@/$IPP_PORT/g" "$SOURCE" > "$TMP"
chmod 644 "$TMP"
if [ ! -f "$TARGET" ] || ! cmp -s "$TMP" "$TARGET"; then
    mv -f "$TMP" "$TARGET"
    echo "Canon Avahi service installed"
else
    echo "Canon Avahi service unchanged"
fi
# DSM creates its own discovery entry for usbprinter1. Disable advertisement only.
DSM_PRINTER="$AVAHI_DIR/bonjour-usbprinter1.service"
if [ -f "$DSM_PRINTER" ]; then
    mv -f "$DSM_PRINTER" "$DSM_PRINTER.disabled"
    echo "DSM duplicate Avahi advertisement disabled"
fi
# In the observed DSM environment a touch resolved DNS-SD SRV/TXT timeout after reboot.
touch "$TARGET"
echo "Canon Avahi service refreshed"
