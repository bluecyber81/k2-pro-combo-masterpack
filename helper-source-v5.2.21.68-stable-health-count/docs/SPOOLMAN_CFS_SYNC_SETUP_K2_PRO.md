# Spoolman CFS Sync Setup - K2 Pro Combo

This package intentionally does **not** ship an active `spoolman_cfs_map.json`. That protects a real printer map from being overwritten. IDs `1`, `2`, `3`, `4` are allowed when they are real local Spoolman spools; the live K2 Pro Combo at `192.168.178.74` used this pattern.

Older maps without an `enabled` field stay active when T1A, T1B, T1C and T1D all contain positive Spoolman IDs. Running the wizard later rewrites the map with an explicit `enabled: true`.

## Safe status check

```sh
/mnt/UDISK/helper-script/helper.sh --spoolman-cfs-status
```

The command is read-only. It does not load, unload, extrude, refresh, or move CFS material.

## Enable sync deliberately

1. Copy the example map:

   ```sh
   cp /mnt/UDISK/helper-script/spoolman_cfs_map.example.json /mnt/UDISK/helper-script/spoolman_cfs_map.json
   ```

2. Edit `spoolman_cfs_map.json` and enter the real Spoolman spool IDs for all four slots:

   - `T1A`
   - `T1B`
   - `T1C`
   - `T1D`

3. Set `enabled` to `true` only after every slot points to the correct real spool.

4. Run the read-only status check again:

   ```sh
   /mnt/UDISK/helper-script/helper.sh --spoolman-cfs-status
   ```

The worker blocks missing, disabled, incomplete, and demo-ID maps. It only changes Moonraker's active Spoolman spool after the map is enabled and all four slot IDs are valid positive Spoolman IDs.

## Important CFS safety note

Do not test CFS with direct `BOX_LOAD_MATERIAL`, `BOX_EXTRUDE_MATERIAL`, `_CFS_LOAD`, or `_CFS_UNLOAD` commands. Use the printer display, slicer toolchange, or the official Creality/CFS workflow.
