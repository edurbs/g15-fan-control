# g15-fan-control

Temperature-driven fan control for the **Dell G15 5530** (and other Dell G-series /
Alienware laptops that expose the `alienware-wmi` AWCC interface) — using the
kernel's native per-fan **boost**. No EC writes, no NoteBook FanControl.

## The problem

On Ubuntu, the `balanced` power profile keeps the fans slow (~1300 rpm), so the
keyboard/chassis gets uncomfortably hot. The `performance` profile spins both fans
to near-max (~2900 rpm) and is too loud. The firmware's three profiles
(`quiet` / `balanced` / `performance`) give no middle ground.

## What this does

A small systemd daemon reads your CPU (and GPU) temperature every few seconds and
sets each fan's **boost** (0–100) along a curve you define, through the
`alienware-wmi` kernel driver:

- `fan1_boost` → **CPU fan**, driven from the hottest core (`coretemp`)
- `fan2_boost` → **Video fan**, driven from the hotter of CPU/GPU (`nvidia-smi`, optional)

`boost=0` means "let the BIOS decide," so you're never quieter or slower than the
firmware's own balanced curve — the daemon only *adds* cooling. The BIOS
critical-temperature protection always applies.

Measured on a G15 5530 at ~66 °C:

| boost | CPU fan | Video fan |
|------:|--------:|----------:|
|   0   | ~1830   | ~2141     |
|  30   | ~2000   | ~2189     |
|  60   | ~2766   | ~2745     |
| 100   | ~3594   | ~3582     |

It's a closed loop: fans spin up → CPU cools → boost eases back → it settles at the
temperature your curve targets.

## Requirements

- A Dell G-series / Alienware laptop exposing the AWCC `alienware-wmi` hwmon
  (`fan*_boost`). Tested on the **G15 5530**; likely works on 5511/5515/5520/5525/5535.
- `coretemp` (Intel CPU temps) — present by default.
- `nvidia-smi` — **optional**; only feeds the GPU temperature into the Video fan.
  Without it, the Video fan follows the CPU temp.
- systemd.

## Install

```bash
git clone https://github.com/edurbs/g15-fan-control.git
cd g15-fan-control
sudo bash install.sh
```

`install.sh` installs the daemon + config + unit, sets you to `balanced`, then starts
and enables the service. Verify:

```bash
systemctl status g15-fan-control
# watch the daemon react to temperature:
watch -n2 'cat /sys/class/hwmon/hwmon*/fan1_boost /sys/class/hwmon/hwmon*/fan2_boost 2>/dev/null'
```

## Tune the curve

Edit `/etc/g15-fan-control.conf`:

```
CURVE="45:0 50:10 55:20 60:30 65:40 70:52 76:66 82:82 88:100"
```

Each pair is `temperature°C : boost (0–100)`, ramped linearly between points. Use the
table above to pick the RPM you want at a given temperature, then:

```bash
sudo systemctl restart g15-fan-control
```

- **Keyboard still too warm** → raise the boosts (e.g. `65:55`).
- **Too loud at light load** → ramp later/lower (e.g. `55:0 60:20 65:35 ...`).

Other knobs in the config: `INTERVAL`, `EMERGENCY_TEMP`, `CONTROL_GPU`, `SMOOTH_STEP`.
Re-measure the boost→speed relationship on your unit with `tools/boost-sweep.sh`.

## Safety

- **No EC writes, no nbfc** — purely the kernel `alienware-wmi` sysfs.
- **The curve is validated at startup**: temperatures strictly ascending and boosts
  non-decreasing (so cooling never falls as temperature rises), and every numeric
  setting is checked. A malformed config falls back to the built-in defaults (with a
  warning in the journal) rather than crash-looping or under-cooling.
- `boost=0` hands the fan to the firmware. Keep `power-profiles-daemon` on **balanced** —
  the daemon layers boost on top of the *active* profile, so on `quiet` the baseline is
  lower. Either way the BIOS's hard critical-temperature trip protects the hardware
  regardless of what boost is set.
- On stop/crash, **every** `fan*_boost` is reset to 0 (`ExecStopPost --release`);
  `Restart=always` brings the daemon back in 2 s.
- Past `EMERGENCY_TEMP` (88 °C) both fans go to max (100).
- Doesn't touch CPU power limits — `power-profiles-daemon` and `thermald` keep working.

See [SECURITY.md](SECURITY.md) for the review.

## Uninstall

```bash
sudo systemctl disable --now g15-fan-control
sudo rm /usr/local/sbin/g15-fan-control \
        /etc/g15-fan-control.conf \
        /etc/systemd/system/g15-fan-control.service
sudo systemctl daemon-reload
```

## Why not `dell_smm` / nbfc?

On the G15 5530 the `dell-smm-hwmon` `pwm*` files are **read-only mirrors of the EC** —
writes are silently ignored and the fans don't move (verified). Real custom curves need
either the AWCC WMI interface (what this uses) or raw EC writes (nbfc). The AWCC path is
kernel-mediated and far safer. See the [kernel alienware-wmi docs][kdoc].

## Tools

- `tools/boost-sweep.sh` — sweeps `fan*_boost` 0→100 and prints RPM, to (re)measure the
  boost→speed relationship on your unit.

## License

MIT — see [LICENSE](LICENSE). Built on the Linux kernel's `alienware-wmi` driver and the
community-documented AWCC WMI interface.

[kdoc]: https://docs.kernel.org/wmi/devices/alienware-wmi.html
