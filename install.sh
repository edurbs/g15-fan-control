#!/usr/bin/env bash
# install.sh — install + start the boost-based G15 fan controller.
# Run from the repo root:  sudo bash install.sh
set -euo pipefail
STAGE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

by_name(){ for d in /sys/class/hwmon/hwmon*; do [ "$(cat "$d/name" 2>/dev/null)" = "$1" ] && { echo "$d"; return 0; }; done; return 1; }

echo ">> installing files (from $STAGE)"
install -m 0755 -o root -g root "$STAGE/g15-fan-control"        /usr/local/sbin/g15-fan-control
install -m 0644 -o root -g root "$STAGE/g15-fan-control.conf"   /etc/g15-fan-control.conf
install -m 0644 -o root -g root "$STAGE/g15-fan-control.service" /etc/systemd/system/g15-fan-control.service

aw=$(by_name alienware_wmi) || { echo "!! alienware_wmi hwmon not found — this laptop may be unsupported"; exit 1; }
smm=$(by_name dell_smm) || smm=""

echo ">> ensuring balanced profile (the daemon layers boost on top of it)"
powerprofilesctl set balanced >/dev/null 2>&1 || true

echo ">> enabling + starting service"
systemctl daemon-reload
systemctl enable --now g15-fan-control.service

sleep 5
echo ">> service status"
systemctl --no-pager --full status g15-fan-control.service | sed -n '1,10p' || true

echo ">> live read (daemon should now be setting boost from temperature)"
ct=$(by_name coretemp) || ct=""
mx=0; if [ -n "$ct" ]; then for t in "$ct"/temp*_input; do v=$(($(cat "$t" 2>/dev/null)/1000)); [ "$v" -gt "$mx" ] && mx=$v; done; fi
printf "   cpu max   : %sC\n" "$mx"
printf "   fan1_boost= %s   fan2_boost= %s\n" "$(cat "$aw/fan1_boost")" "$(cat "$aw/fan2_boost")"
if [ -n "$smm" ]; then printf "   fan rpm    : cpu=%s  video=%s\n" "$(cat "$smm/fan1_input")" "$(cat "$smm/fan2_input")"; fi

echo ""
echo ">> DONE.  Tune: sudoedit /etc/g15-fan-control.conf  then  sudo systemctl restart g15-fan-control"
