# Security review — g15-fan-control

## Summary

**Low risk.** The daemon is a root systemd service with **no network access and no
external/untrusted input**. All inputs are kernel sysfs files and a root-owned config.
An independent review was performed and its findings addressed (see *Review history*).

## Scope

- `g15-fan-control` — the daemon (runs as root via systemd)
- `g15-fan-control.conf` — config (sourced by the daemon)
- `g15-fan-control.service` — systemd unit
- `install.sh`, `tools/boost-sweep.sh` — setup/diagnostic scripts (run with sudo)

## Findings

### Attack surface / inputs
- **No network.** No sockets, no HTTP, no outbound calls of any kind.
- **No untrusted input.** The only parsed values are temperatures read from sysfs
  (`coretemp`, `alienware-wmi`), the output of a fixed `nvidia-smi` query, and the curve
  in the config. Sysfs temperature reads are regex-validated as integers before any
  arithmetic (`max_coretemp`).
- **Config is sourced as shell** (`. /etc/g15-fan-control.conf`). Standard pattern
  (cf. `/etc/default/*`) and safe here: the file is owned by `root:root` (mode `0644`),
  only root can modify it, and the daemon already runs as root ⇒ **no privilege
  escalation**. Do not loosen those permissions.

### Config validation (the important hardening)
- On startup `validate_config()` checks that `INTERVAL`, `EMERGENCY_TEMP`, `MAX_BOOST`,
  `SMOOTH_STEP`, `GPU_REFRESH_EVERY` are non-negative integers, and that `CURVE` has ≥ 2
  points of the form `temp:boost` with **strictly ascending temperatures and
  non-decreasing boosts**. This prevents a mis-written curve from spinning fans *slower*
  as the chip heats.
- On any validation failure the daemon **falls back to the built-in defaults** and logs a
  warning — it does not crash-loop or run with a dangerous curve.
- `shopt -s nullglob` is set, so a zero-match hwmon glob is safe (no arithmetic on a
  literal path).

### Outputs / side effects
- Writes a **bounded integer 0–100** to `…/fan*_boost`, clamped (`clamp_boost`) and
  snapped to `SMOOTH_STEP`. Worst case is "fans at max" — loud, never harmful.
- Logs via `logger -t g15-fan-control -- "$*"` — the `--` prevents option injection, and
  the message is daemon-authored.
- **No temp files** in world-writable locations; **no `eval`**; no command built from
  external data. `nvidia-smi` is invoked with fixed arguments only.

### Failure safety (the important part for a fan controller)
- Every loop iteration re-resolves the hwmon **by name** and re-writes the boost — a
  transient read failure skips that tick; it never crashes the loop.
- `release()` resets **every** `fan*_boost` (globbed, so a 3rd fan is covered too) to 0 on
  `EXIT`/`INT`/`TERM`. systemd's `ExecStopPost=… --release` does the same even on `SIGKILL`
  (where the trap can't run). `Restart=always` restarts within 2 s.
- Because `boost=0` hands control to the firmware, a stopped/dead daemon leaves the fans
  no worse than the BIOS's active profile.

### Thermal-profile assumption (be aware)
- `boost=0` "returning to BIOS control" is **empirical on the `balanced` profile** (measured:
  boost 0 → ~1830 rpm, not 0) — the AWCC `Thermal_Control` op 0x02 has no documented
  "0 = release" semantic; it layers on the active thermal profile. The installer sets
  `balanced`; if you switch to `quiet`, the baseline drops. The **BIOS hard
  critical-temperature trip is the hardware backstop regardless**, so genuine
  CPU-damaging overheating is prevented even if the daemon misbehaves.

### Deployment / permissions
- Installed root-owned: script `0755`, config/unit `0644`. Not world-writable.

## Optional hardening (not required; verify before relying on it)

```ini
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
```

## Review history

Independently reviewed by an automated security pass. Findings addressed in this version:
CURVE/numeric validation with safe default-fallback, glob-based fan reset in `release()`,
`nullglob`, `install.sh`/`tools` error-path robustness, and the thermal-profile caveat
documented above. The injection / privilege-escalation surface was found clean.

## Conclusion

No exploitable issues. The design is intentionally simple: *read temperatures, write a
bounded boost, validate the curve, hand back to the BIOS on exit.* Safe to run as root and
to publish.
