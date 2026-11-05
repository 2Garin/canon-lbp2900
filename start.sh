#!/bin/sh
set -eu

# A bind-mounted /etc/cups may initially be empty. Initialize only once.
if [ ! -f /etc/cups/cupsd.conf ]; then
    echo "Initializing CUPS configuration in /etc/cups"
    cp -a /opt/cups-defaults/. /etc/cups/
    cp /opt/canon/cupsd.conf /etc/cups/cupsd.conf
    chmod 644 /etc/cups/cupsd.conf
fi
mkdir -p /run/cups /var/spool/cups
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
