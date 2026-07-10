# Start here - K2 Pro Combo Helper v5.2.21.61-maintenance-sync

This is the normal improved K2 Pro Combo build with live API checks against `192.168.178.74`. It takes the useful parts from the expert-full package, adds the full-audit Spoolman/CFS fixes, and does not expose raw Moonraker G-code sending or one-shot full-stack installs.

## First run

```sh
cd /mnt/UDISK/helper-script
sh helper.sh --preflight
sh helper.sh --backup
sh helper.sh --health
sh helper.sh --health-cfs
```

## Spoolman CFS

```sh
sh helper.sh --spoolman-cfs-install
sh helper.sh --spoolman-cfs-map-wizard
sh helper.sh --spoolman-cfs-sync-once
sh helper.sh --spoolman-cfs-status
```

The ZIP does not ship an active `spoolman_cfs_map.json`. Use the wizard to create one with real T1A/T1B/T1C/T1D Spoolman spool IDs. IDs `1`, `2`, `3`, `4` are allowed when they are real Spoolman spools; the live printer used exactly that pattern.

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
