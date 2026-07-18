# Start here - K2 Pro Combo Helper v5.2.21.68-stable-health-count

This is the normal improved K2 Pro Combo build with live API checks against `192.168.178.74`. It takes the useful parts from the expert-full package, adds the full-audit Spoolman/CFS fixes, and does not expose raw Moonraker G-code sending or one-shot full-stack installs.

## First run

```sh
cd /mnt/UDISK/helper-script
sh helper.sh --preflight
sh helper.sh --backup
sh helper.sh --health
sh helper.sh --moonraker-webcam-status
sh helper.sh --health-cfs
sh helper.sh --klipper-gc-status
sh helper.sh --gcode-time-status
```

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
```

The monitor is passive. It reads Moonraker, Creality material JSON and logs, keeps a compact event history and counts observed slot changes during real prints. It never sends G-code or CFS/BOX/serial commands.

## M600

```sh
sh helper.sh --m600-install
```

On K2 Pro Combo/CFS this installs an M600 pause/park bridge. It does not send direct `BOX_LOAD_MATERIAL`, `BOX_EXTRUDE_MATERIAL`, `_CFS_LOAD` or `_CFS_UNLOAD` commands.

## Nozzle-AI Camera

```sh
sh helper.sh --nozzle-camera-diagnose
sh helper.sh --nozzle-camera-recover
sh helper.sh --nozzle-camera-standby
```

Recovery is explicit. Boot/startup stays status-only so Creality can keep the Nozzle-AI camera under on-demand control.
