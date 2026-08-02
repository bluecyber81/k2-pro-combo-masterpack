# K2 Pro Combo passive diagnostics - 2026-08-02

## Scope

This review was performed while the printer was idle and cold. It did not send
axis, extruder, CFS, heater, fan, probe, calibration, camera-power, print or
firmware commands. Live access was limited to state, files, versions and logs.

## Bed mesh interpretation

The stored history contains two different measurement classes:

- Full-plate meshes use a 9x9 grid over approximately 5..295 mm.
- KAMP/adaptive meshes use a local 3x3 grid around the printed object.

The full-plate residual peak-to-peak values were approximately 0.389..0.408 mm.
The small adaptive regions were approximately 0.020..0.058 mm. These values are
not evidence of temperature drift because they cover different areas and grid
densities. Compare meshes only when scope, grid and sampled area match. The
helper now emits a stable comparison key for this purpose.

## G-code remaining-time audit

Creality's total-time comment already included a substantial part of CFS
transition overhead in several real files, while the original `M73 R` timeline
could still represent mostly motion time. Three affected examples contained 15,
68 and 254 CFS transitions. Their old timelines ended near 39, 109 and 121
minutes while their total estimates were approximately 61, 246 and 486 minutes.

Marker v2 preserves Creality's existing motion timeline and adds only the share
of the estimated CFS transition gap that is still ahead at each progress point.
Existing v1 files are migrated without applying the calibrated offset twice.

Six real G-code files were validated before installation. A normalized
byte-for-byte comparison confirmed that every non-time line remained unchanged.
Only `M73`, the estimated-time comment and estimator marker lines differed.
The live read-only audit subsequently reported 21 files and zero warnings.

The audit command is:

```sh
sh /mnt/UDISK/creality/helper-script/scripts/gcode_time_hybrid.sh status
```

`gcode_time_audit.py` reads local files only. It has no Moonraker request,
G-code command, serial access, motor/heater path or file-write operation.

## Current passive baseline

- Printer firmware: 1.1.6.7 for the reviewed F012 / CR0CN200400C10 target.
- CFS firmware: 1.5.0.
- X, Y and extruder motor-controller images: 081 generation.
- CFS database guards and Spoolman mapping: healthy in the reviewed snapshot.
- No current critical Health, configuration-drift or restore-inventory finding.
- A historical full-bed residual shape remains measurable. It should be judged
  with a controlled, same-area calibration series, not from mixed KAMP history.

## Rollback evidence

The live time-metadata migration created this printer-side backup before any
replacement:

```text
/mnt/UDISK/printer_data/backups/k2pro_helper/gcode_time_v2_20260802_054848
```

No service restart was required for the G-code metadata migration. A later
active test print is still needed to validate the displayed remaining-time
curve under real CFS operation; that test is intentionally outside this passive
review.
