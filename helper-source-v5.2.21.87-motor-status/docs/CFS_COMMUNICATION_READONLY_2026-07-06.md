# CFS communication read-only notes

These notes document the K2 Pro Combo CFS model used by the helper diagnostics.

## Live model

- The CFS is connected through the Creality RS485 stack on `/dev/ttyS5` at 230400 baud.
- Klipper loads Creality extras in this chain: `serial_485`, `auto_addr`, `box`, `filament_rack`.
- The public Python files mostly load closed Creality wrapper modules, so helper code must treat movement/raw-bus commands as unsafe unless proven on the live printer.
- The active material box appears as `T1`, with slots `T1A` to `T1D`.

## Packet model observed in Creality files

- Frame header: `0xF7`
- Shape: header, address, length, status, function, data, CRC8
- CRC: polynomial `0x07`
- Material box addresses are modelled as `0x01` to `0x04`.
- Broadcast addresses exist for material box, closed-loop motor and belt tension motor, but the current active table only uses material box devices.

## Safe diagnostics

- Moonraker object reads: `box`, `filament_rack`, `filament_switch_sensor filament_sensor`.
- JSON validation of `/mnt/UDISK/creality/userdata/box/*.json`.
- Config, G-code and log scanning.
- `helper.sh --cfs-safety-scan`.
- `helper.sh --cfs-protocol-report`.

## Commands that must stay guarded

- `BOX_SEND_DATA`
- `BOX_INFO_REFRESH`
- `BOX_SET_PRE_LOADING`
- `BOX_LOAD_MATERIAL`
- `BOX_EXTRUDE_MATERIAL`
- `BOX_RETRUDE_MATERIAL`
- `BOX_EXTRUDER_EXTRUDE`
- direct `_CFS_LOAD` / `_CFS_UNLOAD` style macros from K2 Plus experiments

These can send RS485 commands or move, heat, cut, feed or retract material.

## Official Creality path

The stock `box.cfg` contains the official `M8200` chain:

- `M8200 P` prepare
- `M8200 C` cut
- `M8200 R` retract
- `M8200 L I0..I3` load slot (`I0=T1A`, `I1=T1B`, `I2=T1C`, `I3=T1D`)
- `M8200 W` waste/purge check
- `M8200 F` flush
- `M8200 O` finish

The helper must keep stock `START_PRINT`, `END_PRINT`, `BOX_START_PRINT`,
`BOX_END` and `BOX_END_PRINT` intact.

