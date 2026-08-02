# K2 Pro auto-address recovery guard

## Scope

This module is only for K2 Pro model `F012`, board `CR0CN200400C10`, and
firmware `1.1.6.7`. It does not flash printer, MCU, motor-controller, camera, or
CFS firmware.

## Corrected vendor behavior

The stock `auto_addr_wrapper.py` can dereference an empty acknowledgement for a
loader or unknown callback. Its address-table loop also stops after the first
table even when the reported device belongs to a later table. The reviewed
payload:

- returns cleanly when the callback has no matching acknowledgement decoder;
- keeps loader-to-app acknowledgements silent;
- scans until the matching device table is found;
- returns safely when no table matches;
- preserves the existing ten-second CFS polling adjustment.

## Guard rails

Installation requires the exact known stock SHA-256. The payload and the live
result are checksum-verified, Python-compiled, and regression-tested before the
operation succeeds. Unknown firmware or file hashes are never overwritten.
The original file is stored below
`/mnt/UDISK/printer_data/backups/k2pro_helper/auto_addr_recovery/` and can be
restored from the Helper menu.

After installation or restore, use the safe full K2/CFS reboot. Do not restart
Klipper alone because the Creality motor-controller ready callback depends on
the full vendor service startup order.
