# K2 Pro Combo Health Process Detection Patch - 2026-07-08

This package keeps the v5.2.21.58 Spoolman live sync changes and adds one
live-tested health/status fix.

## Fixed

- `scripts/health.sh` now detects helper Python daemons by script path.
- `scripts/camera.sh` status/stop now handles `python3 -B ...` process forms.
- `scripts/creality_timelapse_recover.sh` stop fallback now handles
  `python3 -B ... --daemon`.

## Reason

On the live K2 Pro Combo, camera watchdog and Creality timelapse recover were
running correctly after reboot, but the health check reported false failures
because it matched only the exact `python3 script.py` command form.

## Live Validation

- Camera health: OK 12 / WARN 0 / FAIL 0
- Creality timelapse recover health: OK 5 / WARN 0 / FAIL 0
- Full helper health after patch: OK 69 / WARN 0 / FAIL 0
