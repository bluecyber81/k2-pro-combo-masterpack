# K2 Pro Combo live policy - 2026-07-07

Live baseline:

- Printer: K2 Pro Combo, model F012, board CR0CN200400C10.
- Build volume: 300x300x300.
- Firmware: 1.1.6.3.
- CFS/T1 firmware: 1.4.2.
- Spoolman: connected through Moonraker, active spool 1.
- Spoolman CFS map: enabled, T1A=1, T1B=2, T1C=3, T1D=4.

Allowed normal helper work:

- Read Moonraker objects, Spoolman state, CFS material DB JSON and logs.
- Update helper scripts, status checks, dashboards, camera proxy helpers and local reports after backup.
- Use `helper.sh --spoolman-cfs-status`, `--spoolman-cfs-sync-once`, `--health-cfs`, `--cfs-protocol-report` and `--cfs-db-guard-status`.
- Keep the CFS DB guard installed; it only repairs the known custom material records and does not send BOX/CFS motion commands.

Do not update blindly:

- Do not use Moonraker update-manager to update Creality-bundled Klipper or Moonraker from the web UI. The vendor tree is detected as zip/git metadata and can report misleading upstream state.
- Do not flash printer, MCU, nozzle MCU or CFS firmware from this helper package.
- Do not add direct `BOX_LOAD_MATERIAL`, `BOX_EXTRUDE_MATERIAL`, `BOX_RETRUDE_MATERIAL`, `_CFS_LOAD`, `_CFS_UNLOAD`, `BOX_INFO_REFRESH` or raw RS485 tests to normal workflows.
- Do not run `SAVE_CONFIG` only for the CFS `auto_addr` pending item.

Current Spoolman/CFS decision:

- IDs 1-4 are real local Spoolman spool IDs on this printer, not demo IDs.
- The live CFS material IDs are present in the Creality material database.
- T1C material ID `000002` is shared/ambiguous between generic and custom PLA-Silk-like profiles, but the CFS report has no missing DB ID and does not require repair.
- The v5.2.21.57 Spoolman sync daemon compresses repeated unchanged OK log lines; state changes and warnings remain visible immediately.
