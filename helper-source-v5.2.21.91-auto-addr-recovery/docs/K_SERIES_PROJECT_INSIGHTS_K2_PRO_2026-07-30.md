# K-series project insights for the K2 Pro Combo

Date: 2026-07-30

Target: Creality K2 Pro Combo, model F012, board CR0CN200400C10, 300 x 300 x
300 mm. This review is deliberately exact-model aware. Findings from F008 K2
Plus and F021 K2 are architecture evidence, not drop-in configuration.

## Result

The production-safe direction is to keep Creality's stock control plane for
PRTouch, Z alignment, CFS motion, cutter, AI cameras and firmware. Community
projects are most valuable as documentation and as passive observers. The
helper therefore adopts diagnostics and guards, not foreign motor/probe
control.

Two new passive tools are included:

- `sh helper.sh --bed-mesh-insights` reads an existing Moonraker mesh and fits
  a plane. It reports raw range, X/Y tilt and residual shape separately.
- `sh helper.sh --k2-lan-insights` sends only fixed `get` requests to the local
  Creality WebSocket and reports print/CFS state plus real used-material
  length. There is no generic request or command input.

## How the important paths work

### Print start and KAMP

1. The slicer uploads G-code through Moonraker or the Creality host.
2. Creality `master-server` can request G29 before the sliced `START_PRINT`.
3. KAMP intercepts the early trigger, returns Creality's required timing
   handshake, waits for object boundaries and performs the adaptive mesh at
   the correct point.
4. PRTouch homing, thermal settling, nozzle cleaning and purge remain stock
   operations. A generic G-code macro cannot safely reproduce Creality's
   force-controlled bed/nozzle interaction.

The installed KAMP-K2 v1.1.0 is retained. Upstream installers are not rerun
because several repositories label the F021 260 mm geometry as "K2 Pro"; this
F012 uses a 300 mm bed.

### CFS and RS485

1. A slicer `Tn` request enters Creality's stock tool-change macros.
2. The stock box wrapper coordinates motion, cutter, nozzle and waste/purge.
3. The CFS transport uses `/dev/ttyS5` at 230400 baud. Documented frames begin
   with `F7`, followed by address, length, payload and CRC8 polynomial `0x07`.
4. CFS discovery uses broadcast addresses and assigns device addresses. This
   is not equivalent to a normal Klipper G-code device.
5. Creality's LAN/Moonraker `selected` material is a UI/material selection. It
   does not prove the internal steady-feed arm state.
6. CFS operation `mode=0` means the load/unload operation engine is idle. It
   does not mean filament feed is disabled.

The helper reads these states but never sends raw RS485, BOX, cutter, load or
unload commands. K2 Plus `tool.cfg` and T17 experiments remain blocked.

### Cameras

- The chamber camera stays on Creality's vendor service and is exposed through
  go2rtc using the native `#format=creality` input. This avoids the old
  `k2rtc.py` bridge.
- The nozzle camera is an on-demand AI/calibration device. Its absence while
  idle is not by itself a fault, and the helper does not keep it powered.
- Direct WebRTC viewers are useful fallbacks when port 8000 integration is
  broken, but they do not improve the sensor or justify replacing Moonraker.

### Firmware and host software

- Creality's K2 Klipper fork contains model-specific wrappers and older API
  contracts. Replacing only Klipper or Moonraker from generic upstream can
  break PRTouch, box, motor-control and display services.
- Firmware or MCU/CFS images must match F012 and CR0CN200400C10 exactly.
- Mainsail and Fluidd are independent web clients and can be updated with
  backup/health validation. They do not replace Moonraker.
- OrcaSlicer 2.4 integrated the K2/K2 Plus/K2 Pro and CFS host workflow.
  Existing stock profile inheritance should be preserved; only user overrides
  should be reviewed.

## Project decisions

| Project or group | Useful finding | F012 decision |
| --- | --- | --- |
| CrealityOfficial K2_Series_Klipper | Authoritative K2 wrappers, protocols and API compatibility | Reference and preserve |
| sw3defy Helper | Direct go2rtc Creality format, helper patterns | Camera approach already adopted |
| grant0013 KAMP-K2 | Correct Creality G29 handshake and adaptive mesh timing | Installed version retained |
| K2 OpenKlipper | PRTouch signal path, CFS frame/state research, rollback architecture | Research only; alpha is K2 Plus |
| k2-reverse-engineering | RS485 addressing and command evidence | Read-only documentation only |
| K2 Screws Tilt projects | Creality callback compatibility and candidate geometry | No install; coordinates/model claims conflict |
| bed_plane_calibrator | Least-squares plane fitting concept | Reimplemented as passive mesh analysis |
| Erinell K2 WebSocket | Local GET status, CFS and materials interfaces | Fixed GET-only diagnostic adopted |
| IPS-SpoolmanSync | `usedMaterialLength` includes real extrusion/purge | Read-only metric adopted; no second booking engine |
| CFSspoolsync | Last-confirmed-slot stabilization | Useful UI hint, not feed-arm proof |
| Hurricane Filament-Sync | Shows Creality DB layout | Rejected: periodic stale rsync can overwrite updates |
| SpoolID | MIFARE Classic 1K and spool length encoding | External tag workflow only |
| geckotdf camera viewer | Token-aware direct WebRTC fallback | Optional reference; no automatic install |
| skilly00/mpaw camera fixes | Older iframe/nozzle-camera experiments | Superseded or wrong firmware/model |
| k2dash | Fast dashboard and direct camera path | Raspberry Pi UI only, not printer core |
| K2 Backup | Basic config/calibration backup inventory | Existing checksummed restore package is broader |
| K2 analytics/metrics/HA dashboards | Passive telemetry and maintenance concepts | External host only when actually needed |
| FutureHax presets | Missing macOS/0.2 mm presets | Not relevant to Windows 0.4 mm setup |
| Barconero/MasterLufier/minimal3dp macros | Purge, fan, tool and calibration experiments | Rejected: broad stock macro replacement |
| purge-volume fix | Reduced purge and wipe time | Rejected without contamination testing |
| k2-unleashed | Model detection and broad diagnostics | No install; tests can move/heat/probe |
| old camera workaround | Restores a full Moonraker tree | Rejected: destructive and outdated |

## Already correct on this printer

- Exact F012/board protection and firmware image gate.
- KAMP adaptive mesh without foreign screws-tilt/probe modules.
- Direct go2rtc chamber-camera path and on-demand nozzle AI behavior.
- Update-aware CFS database guard that merges only custom IDs into the newest
  official base and writes atomically with backups.
- Passive CFS Safe Tools with mode/selection semantics and RS485 log counters.
- One Spoolman active-slot mapper. A second material-consumption booking engine
  is intentionally not enabled to avoid double deduction.
- Hybrid Creality/Klipper G-code time estimation and Klipper garbage
  collection with rollback.
- Full checksummed helper and restore archives.

## Live read-only verification

The new readers were verified against the live F012 on 2026-07-30 while the
printer was in standby and the heater targets were zero:

- LAN status identified F012 and display/runtime version 1.1.6.7.
- CFS reported connected, one external path and four T1 slots.
- The fragmented material response was reassembled and contained 52 profiles.
- The stored default bed mesh contained 81 samples over 5..295 mm.
- Its raw range was 0.4370 mm. Fitted tilt accounted for only +0.0622 mm
  across X and +0.1146 mm across Y.
- Plane-removed residual shape was 0.3896 mm peak-to-peak, 0.0835 mm RMS and
  0.2613 mm maximum absolute deviation. The center was about 0.1795 mm higher
  than the perimeter after plane removal.

This is an old stored mesh, not a new probe. It justifies a later controlled
same-temperature repeat comparison, not an automatic screws-tilt, calibration
or mechanical adjustment.

## Permanent safety rules

1. Never copy a complete community `gcode.py`, Moonraker tree, Klipper tree,
   `tool.cfg`, `box.cfg` or START/END macro set over the F012 vendor files.
2. Patch the smallest compatible surface and verify active includes, not stale
   `printer-*.cfg` backups.
3. Treat M600 as an optional pause bridge. Do not mix it with raw CFS unload or
   a replaced RESUME macro.
4. Do not infer screw turns from a bed mesh alone. Tilt, plate curvature,
   thermal state and PRTouch/nozzle condition must be separated first.
5. Do not run background CFS polling through synchronous motor-bus transfers.
6. Do not install a second Spoolman consumption writer.
7. Never flash by product name alone. Model, board, package identity and
   trusted checksum must all match.

## Reproducible project inventory

The following local heads were inspected. `Preserve` means the installed idea
or stock component stays. `Passive` means only read-only concepts were used.
`External` means Raspberry Pi/PC only. `Reject` means no F012 deployment.

| Repository | Inspected head | Last commit | Decision |
| --- | --- | --- | --- |
| CrealityOfficial/K2_Series_Klipper | bc0a52078ace | 2025-10-22 | Preserve/reference |
| sw3defy/Creality-Helper-Script-K2-Plus | f5623bef413c | 2026-06-23 | Preserve selected patterns |
| grant0013/KAMP-K2 | ef8fd5d87580 | 2026-07-21 | Preserve installed v1.1.0 |
| grant0013/K2-OpenKlipper | c3d5c4dd1550 | 2026-07-29 | Passive research, alpha |
| grant0013/k2-reverse-engineering | 4c429a7f6b0f | 2026-05-01 | Passive protocol research |
| grant0013/k2-firmware | 0ddcb2c73790 | 2026-07-21 | Reference only |
| grant0013/k2-adaptive-bedmesh | bb693852ba2b | 2026-05-01 | Superseded by KAMP |
| grant0013/K2-Screws-Tilt | 6d22b93c1457 | 2026-06-17 | Reject F021 coordinates |
| grant0013/K2-Backup | d88f8eebfb53 | 2026-06-12 | Existing restore is broader |
| jglerner/k2-pro-klipper | 3773d343eef1 | 2026-07-22 | Research only |
| jglerner/creality-k2-pro-klipper-screws-tilt | 6bff4c63d7f5 | 2026-07-23 | Reject unverified geometry |
| DashRulez/bed_plane_calibrator | d610b33607f3 | 2026-04-26 | Passive math concept |
| Erinell/Creality-K2-websocket | c1bf222017c8 | 2025-03-03 | Fixed GET subset adopted |
| badfrog18/IPS-SpoolmanSync | 6dbc67fcdfed | 2026-07-22 | Passive metric only |
| mschoettli/CFSspoolsync | cab3a7721b08 | 2026-05-21 | Selection semantics only |
| HurricanePrint/Filament-Sync | de13d46d6dc5 | 2026-07-19 | Reject periodic full sync |
| HurricanePrint/Filament-Sync-Service | a6d354eabee6 | 2026-07-21 | Reject 15-second stale rsync |
| SpoolId/SpoolID | 1998b0b48e85 | 2026-07-06 | External RFID reference |
| renaudrenaud/creality_k2_cfs | 787b84a5c676 | 2025-08-25 | Protocol reference only |
| geckotdf/Creality-K2-Camera-Fix | 2f46c39d6237 | 2026-07-20 | Optional viewer reference |
| skilly00/K2-Camera-Fix | aa745a6b161c | 2026-02-24 | Reject old Moonraker patch |
| mpaw/k2plus-nozzle-cam | 170749311413 | 2024-12-29 | Evidence only |
| dherald007/Creality-K2-Camera-Workaround | 300027747bc4 | 2025-09-20 | Reject full tree replace |
| pdromnt/k2dash | 5e960411b8b3 | 2026-07-20 | External Pi UI |
| nickgtg/creality-k2-home-assistant-dashboard | 021edd2fbd10 | 2026-07-16 | External HA UI |
| MiguelAPerez/creality-k2-metrics-exporter | 10c9ca5ddc67 | 2026-05-12 | External optional metrics |
| GhostyAUS/k2-printer-analytics | 2fd98383df21 | 2026-06-01 | Reject until known bugs fixed |
| FutureHax/creality-k2-pro-presets | b7f794557935 | 2026-07-14 | Not applicable |
| Barconero/Creality-K2-Pro-addons | c31581933e86 | 2026-07-06 | Reject broad macro replace |
| MasterLufier/Creality-K2-Plus-Custom-Macros | 8da3ef063b9a | 2026-03-05 | Reject F008 raw BOX macros |
| minimal3dp/k2_powerups | 3718d7f982f9 | 2026-05-02 | Reject conflicting macros |
| camaro4life18/Creality-K2-Series-Purge-Volume-Fix | 7075be14a410 | 2026-01-27 | Reject without purge tests |
| simonsprofile/creality_k2_tweaks | 5bb95cbe6d7e | 2026-04-15 | Reject F021/240V assumptions |
| j-devops/k2-unleashed | d3be14c50b91 | 2026-01-31 | Reject active diagnostic suite |
| dherald007/Creality-K2-Bed-Leveling-Macro | 43d1e418e726 | 2025-11-22 | Reject active heat/motion |
| jamincollins/k2-improvements | d9fef1115195 | 2025-04-07 | Archived reference |
| Guilouz/Creality-Helper-Script | b46787a61b3c | 2025-05-21 | Discussion/reference only |
| rconescu/K2Rebuild | cc7d55ad3ccd | 2025-10-31 | Recovery research only |

## Primary sources

- https://github.com/CrealityOfficial/K2_Series_Klipper
- https://github.com/grant0013/K2-OpenKlipper
- https://github.com/grant0013/KAMP-K2
- https://github.com/Erinell/Creality-K2-websocket
- https://github.com/badfrog18/IPS-SpoolmanSync
- https://github.com/geckotdf/Creality-K2-Camera-Fix
- https://github.com/OrcaSlicer/OrcaSlicer/wiki/release_2_4_0_beta

The remaining reviewed repositories are kept in the dated local study checkout.
No installer from that checkout was executed on the printer.
