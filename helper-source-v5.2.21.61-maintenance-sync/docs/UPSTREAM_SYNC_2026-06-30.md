# Upstream sync notes - 2026-06-30

Reviewed sources:

- sw3defy/Creality-Helper-Script-K2-Plus, commit `f5623bef413c1507817e78af8b72e18c3544e210`
- MasterLufier/Creality-K2-Plus-Custom-Macros, commit `8da3ef063b9a743e761428bcdca05ffecd97a7a0`

## Safe change ported

The sw3defy K2 Plus changelog documents a Moonraker metadata race: stock
`/usr/share/moonraker/moonraker.conf` can set `queue_gcode_uploads: False`.
Fluidd and Mainsail may then ask for metadata before extraction has finished,
which can lead to missing G-code preview, missing thumbnails, or unknown file
metadata.

This K2 Pro Combo uses `/mnt/UDISK/printer_data/config/moonraker.conf`, which
includes `/usr/share/moonraker/moonraker.conf`, so the stock value still matters.
The helper now has a backed-up fix path that changes the stock value to:

```ini
queue_gcode_uploads: True
```

The fix is idempotent and backs up the original file under:

```text
/mnt/UDISK/printer_data/backups/k2pro_helper/moonraker_queue/
```

## Deliberately not ported

The MasterLufier macro package states that it is only for K2 Plus and that K2
and K2 Pro require changes and tests. Its `tool.cfg` replaces sensitive
tool-change, CFS and autorefill behavior. This K2 Pro Combo has already shown
that direct `BOX_LOAD_MATERIAL` / `BOX_EXTRUDE_MATERIAL` paths can trigger
Klipper shutdowns, so those macros are not imported.

The sw3defy K2 Plus helper also patches K2 Plus mesh and macro naming details.
On this K2 Pro firmware, `box.cfg` and `gcode_macro.cfg` already expose the
needed public macro names, so the broad underscore-renaming patch is not needed.
The K2 Plus `mesh_min: 20,20` change is also not applied because it changes
probing behavior and would require K2 Pro-specific mesh validation.
