#!/usr/bin/env bash
# tools/boost-sweep.sh — measure the boost -> fan-speed relationship on your unit.
# Sweeps fan1_boost / fan2_boost 0..100 and prints RPM. Useful for tuning the
# curve in /etc/g15-fan-control.conf. Reversible: restores boost=0 at the end
# AND on any interrupt (trap).
#
# Run: sudo bash tools/boost-sweep.sh
set -u
shopt -s nullglob
by_name(){ for d in /sys/class/hwmon/hwmon*; do [ "$(cat "$d/name" 2>/dev/null)" = "$1" ] && { echo "$d"; return; }; done; }
aw=$(by_name alienware_wmi) || { echo "alienware_wmi hwmon not found"; exit 1; }
smm=$(by_name dell_smm)   # optional: used only to show RPM

# always hand fans back to the BIOS on exit / Ctrl-C
restore(){ for f in "$aw"/fan*_boost; do echo 0 > "$f" 2>/dev/null; done; }
trap restore EXIT INT TERM

echo "aw=$aw  smm=${smm:-<none>}"
echo "set profile to balanced for a clean baseline..."
powerprofilesctl set balanced >/dev/null
sleep 4

sweep(){
  local val=$1
  echo "$val" > "$aw/fan1_boost" 2>/dev/null
  echo "$val" > "$aw/fan2_boost" 2>/dev/null
  sleep 5
  local rb1 rb2
  rb1=$(cat "$aw/fan1_boost"); rb2=$(cat "$aw/fan2_boost")
  if [ -n "$smm" ]; then
    printf "  boost=%-4s readback=%s/%s   cpu_fan=%-5srpm  video_fan=%-5srpm\n" \
      "$val" "$rb1" "$rb2" "$(cat "$smm/fan1_input")" "$(cat "$smm/fan2_input")"
  else
    printf "  boost=%-4s readback=%s/%s   (no dell_smm RPM source)\n" "$val" "$rb1" "$rb2"
  fi
}

echo "sweeping fan1_boost / fan2_boost (0,30,60,100):"
for v in 0 30 60 100; do sweep "$v"; done

echo "restoring boost=0..."
restore
echo "done"
