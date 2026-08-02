# K2 OpenKlipper insights applied to K2 Pro diagnostics

Date: 2026-07-30

Reference:

- Repository: https://github.com/grant0013/K2-OpenKlipper
- Reviewed commit: `c3d5c4dd1550fb164dc7cb970363f379428c33c4`
- Relevant sources: `OPEN-STACK.md`, `docs/CFS-PROTOCOL.md`,
  `docs/PROJECT-STATUS.md`, `docs/PRTOUCH.md` and
  `klippy/extras/k2_cfs.py`

## What can be used safely

### CFS operation mode

The CFS `mode` field describes the load/unload operation engine:

| Code | Meaning |
| --- | --- |
| 0 | idle |
| 1 | preloading |
| 2 | printing transition |
| 3 | wrapping/rewind |
| 4 | error |
| 5 | service/test |

After steady feed is armed, a mode read normally returns `0`. Therefore
`mode=0` is not evidence that feed is disabled. The stock Creality Moonraker
object does not expose the separate steady-feed arm state.

### Slot and buffer semantics

The slot reported by the stock object is suitable for material selection,
Spoolman mapping and transition statistics. It is not proof of the hidden
steady-feed state. The CFS buffer arm has separate slack, middle and tensioned
states on RS485, but the stock Moonraker object does not expose them.

### RS485 log interpretation

`buf_len=0x...` lines describe receive-buffer parser activity. Zero and
non-zero values are useful context, but neither is an error by itself.
Timeouts, unknown frames and known severe exception signatures remain the
health signals used by the helper.

### Active Klipper configuration

Klipper behavior is determined by the include tree rooted at `printer.cfg`.
Automatic `printer-YYYY...cfg` backups that are not included are historical
files, not active configuration. Safety checks must follow active includes,
including nested and wildcard includes, while retaining exact factory hash
checks for `box.cfg` and `motor_control.cfg`.

## Already correct on the K2 Pro

- Creality's START sequence performs rough homing, nozzle cleaning and thermal
  settling before final Z homing and adaptive mesh generation.
- The stock M8200/CR_BOX transaction and START/END CFS calls are intact.
- The installed F012 arc implementation is vendor-specific and currently has
  no timer errors.
- Cancel and end macros preserve Creality's CFS cleanup ordering.

## Deliberately not imported

- K2 Plus board pins, probe configuration or hardware identities
- raw CFS/RS485 motor, cutter, load, unload or tension commands
- OpenKlipper START_PRINT, END_PRINT or CANCEL_PRINT macro replacements
- OpenKlipper arc settings
- probe bypasses or screws-tilt assumptions
- firmware, MCU, CFS or camera images

These paths are hardware- and stack-specific. Copying them into the F012 K2
Pro could move material unexpectedly, break Creality AI/calibration flows or
make recovery harder. This helper uses OpenKlipper only as a protocol reference
for passive diagnostics.
