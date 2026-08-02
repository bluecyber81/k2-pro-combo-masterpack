# Start here - K2 Pro Combo Helper v5.2.21.91-auto-addr-recovery

This is the normal improved K2 Pro Combo build with live API checks against `192.168.178.74`. It takes the useful parts from the expert-full package, adds the full-audit Spoolman/CFS fixes, and does not expose raw Moonraker G-code sending or one-shot full-stack installs.

## First run

```sh
cd /mnt/UDISK/helper-script
sh helper.sh --preflight
sh helper.sh --backup
sh helper.sh --health
sh helper.sh --protection-status
sh helper.sh --moonraker-webcam-status
sh helper.sh --nozzle-power-status
sh helper.sh --filament-calibration-status
sh helper.sh --motor-controller-status
sh helper.sh --auto-addr-status
sh helper.sh --health-cfs
sh helper.sh --klipper-gc-status
sh helper.sh --gcode-time-status
sh helper.sh --bed-mesh-insights
sh helper.sh --k2-lan-insights
sh helper.sh --bed-mesh-history
sh helper.sh --cfs-consumption
sh helper.sh --gcode-preflight
sh helper.sh --post-update-status
sh helper.sh --status-hub-status
```

`--bed-mesh-insights` analyzes only the already stored Moonraker mesh. It
separates fitted X/Y tilt from residual plate shape and never homes, heats,
probes, moves or sends G-code.

`--k2-lan-insights` uses a fixed GET-only request table on Creality's local
WebSocket. It reports print/CFS status and real used-material length without
exposing RFID, print IDs or any generic command interface. The selected CFS
slot remains a UI/material selection, not proof of the hidden feed-arm state.

After the printer is verified healthy, capture the local comparison baseline:

```sh
sh helper.sh --post-update-capture
```

Later `--post-update-status` compares exact F012/board, firmware, CFS/camera,
database, active config, core, frontend and Helper hashes. It never restores a
file automatically.

Install the common compact status page once:

```sh
sh helper.sh --status-hub-install
```

It is then available on the dedicated URL `http://PRINTER-IP:4410/`. Keeping
the page on its own origin prevents Fluidd or Mainsail service workers from
replacing it with an empty frontend shell. The same URL can be opened in a
browser on the HelixScreen/K2Dash Raspberry Pi.

When installed, the CFS database guard watches for later Creality-side database
rewrites every five minutes. It repairs only while Moonraker reports a cold,
idle printer and keeps a pre-repair archive. `--cfs-db-guard-status` shows the
watcher and database state.

`--nozzle-power-status` compares the live nozzle-AI power script with the exact
nonblocking F012 firmware source. Use `--nozzle-power-restore` only when status
detects drift: the command requires the exact K2 Pro model/board, a completed
or idle printer, both heater targets at zero and an existing helper backup. It
then backs up the live script and replaces it atomically without restarting a
printer service.

## K2 Pro protection guard

```sh
sh helper.sh --protection-status
sh helper.sh --firmware-compat
sh helper.sh --config-drift
sh helper.sh --recovery-inventory
sh helper.sh --database-protection
```

All five commands are read-only. To inspect a downloaded OTA file without
flashing it, provide its full path and a trusted SHA-256:

```sh
sh helper.sh --check-ota-image /path/to/F012-image.img EXPECTED_SHA256
```

The gate blocks foreign board/model names, downgrades and hash mismatches. A
successful result is still a preflight result, not a flash command.

If a firmware update restores the three F012 factory sample files, run
`sh helper.sh --gcode-time-install` while the printer is in standby. The
matching remove command restores both the factory source and user copies from
the helper-created backup.

## Spoolman CFS

```sh
sh helper.sh --spoolman-cfs-install
sh helper.sh --spoolman-cfs-map-wizard
sh helper.sh --spoolman-cfs-sync-once
sh helper.sh --spoolman-cfs-status
```

The ZIP does not ship an active `spoolman_cfs_map.json`. Use the wizard to create one with real T1A/T1B/T1C/T1D Spoolman spool IDs. IDs `1`, `2`, `3`, `4` are allowed when they are real Spoolman spools; the live printer used exactly that pattern.

## CFS Safe Tools

```sh
sh helper.sh --cfs-safe-install
sh helper.sh --cfs-safe-status
sh helper.sh --cfs-safe-events
sh helper.sh --cfs-safe-gcode
sh helper.sh --bed-mesh-history
sh helper.sh --cfs-consumption
```

The monitor is passive. It reads Moonraker, Creality material JSON, logs and
the fixed GET-only LAN status, keeps a compact event/mesh history and estimates
real-print consumption. It never sends G-code or CFS/BOX/serial commands and
never writes Spoolman inventory.

`--cfs-safe-status` and `--cfs-protocol-report` also explain Creality's CFS
operation mode. `mode=0` means that the load/unload operation engine is idle;
it does not prove that steady filament feed is disabled. Stock Moonraker does
not expose that separate feed-arm state.

## M600

```sh
sh helper.sh --m600-install
```

On K2 Pro Combo/CFS this installs an M600 pause/park bridge. It does not send direct `BOX_LOAD_MATERIAL`, `BOX_EXTRUDE_MATERIAL`, `_CFS_LOAD` or `_CFS_UNLOAD` commands.

## Nozzle-AI Camera

```sh
sh helper.sh --nozzle-ai-status
sh helper.sh --nozzle-camera-diagnose
sh helper.sh --nozzle-camera-recover
sh helper.sh --nozzle-camera-standby
```

The status and diagnosis paths are read-only. The legacy `recover` command now
performs a protected temporary power probe only while the printer is cold and
idle, then always returns the camera to standby/off. Manual standby is also
blocked during a print or while either heater has a non-zero target.
Boot/startup remains status-only so Creality retains on-demand control.

## Filament Auto PA / Flow

```sh
sh helper.sh --filament-calibration-status
sh helper.sh --filament-calibration-history 2
```

The fast status reads only the recent current Creality log. History can scan
up to six rotated gzip logs and is intentionally slower on the printer.
Neither command starts a print or changes a profile. A result is considered
measured only when the same `enableSelfTest=1` job contains Creality's real
PA/Flow result markers. Runtime PA, M221, `flow_rate.json` and CFS database
defaults are shown separately and are never promoted to measurements.

To create a new measurement, start a small matching PLA job in Creality Print
with the visible `Print calibration` option enabled. Normal Fluidd, Mainsail
and K2Dash starts use `enableSelfTest=0` and therefore do not request this
calibration.
