# K2 Pro GC, Estimator and CFS retry integration

## Klipper Garbage Collection

The helper installs the upstream `garbage_collection.py` module only when its
SHA256 is exactly:

`6d339dcd08752fb95322ca5fb71a7624fec07cdaf639cb47803653346db232ff`

It is activated through the isolated file
`k2pro_garbage_collection.cfg`. The optimization runs a full collection when
Klipper becomes ready and freezes long-lived startup objects. It is a small
runtime/memory-management improvement; it does not change motion, heaters,
CFS commands or print calibration.

Useful commands:

```sh
sh helper.sh --klipper-gc-status
sh helper.sh --health
```

Install and removal create timestamped backups below
`/mnt/UDISK/printer_data/backups/k2pro_helper`.

## K2 Pro Combo restart rule

An isolated Klipper service restart was reproduced to fail in Creality's
`motor_control_wrapper.Motor_Control.set_motor_pin` ready callback. Therefore
the helper detects the active `box.cfg` plus `motor_control.cfg` stack and uses
a full Linux reboot for Klipper configuration changes. A printing or paused
printer blocks that reboot. Other printer models retain the normal Klipper
service restart behavior.

For maintenance sessions a reboot can be deferred explicitly:

```sh
K2PRO_DEFER_REBOOT=1 sh scripts/klipper_gc.sh install
```

The configuration is then inactive until one full reboot is performed.

## CFS Safe Tools boot retry

The passive CFS worker no longer exits when it starts before Moonraker or the
Creality CFS objects are available. It waits and retries both during initial
boot and after transient API failures. The monitor remains read-only: it does
not send load, unload, extrusion, motor or RS485 control commands.

On this K2 Pro firmware, custom helper services are launched explicitly from
`/etc/rc.local`; copying the service to `/etc/rc.d` alone does not start it.
The installer therefore maintains one exact `S97cfs_safe_monitor` boot line,
backs up `rc.local`, validates shell syntax and removes only its own line.

## Creality Print hybrid time estimator

The Windows package is bundled under
`extras/windows/klipper-estimator`. It recognizes Creality Print and Creality
Cloud Slicer generated G-code and uses a local Moonraker cache if the printer
is temporarily unreachable while slicing. Its K2 Pro arc setting is
`mm_per_arc_segment=0.9`.

The wrapper keeps a temporary original until both processing stages succeed.
For G-code without a real `Tn` transition, Klipper Estimator supplies the
motion-aware `M73` timeline. For CFS G-code, the wrapper restores Creality's
CFS motion timeline and adds the share of total CFS transition time still
ahead at every `M73` point. This keeps purge, retract and tool-change time in
the displayed remaining time even when Creality's raw `M73 R` values omit it.
Both paths receive the robust 110-second median residual measured from nine
completed single-color K2 Pro prints. The correction decays with remaining
progress and reaches zero at `P100`.

The model targets Moonraker `print_duration`. Heating, AI/flow preparation,
nozzle cleaning, pauses and network delay remain variable runtime overhead.
The calibration evidence is stored in
`extras/windows/klipper-estimator/K2Pro-Time-Calibration.json`.

The Cloud Slicer path has a separate source unit test. Before the live
migration, all 17 existing printer-side G-code files were compared line by
line. Only existing `M73` values, one estimated-time comment per file and the
estimator/hybrid markers changed; motion, heaters, CFS and other machine
commands remained byte-identical.

Moonraker's metadata parser originally recognized only
`Creality_Print` headers. The helper's guarded `moonraker.sh metadata` repair
extends that existing expression to `Creality_Cloud_Slicer`, after an exact
source-pattern check and timestamped backup. This only changes file metadata
parsing; it does not touch Klipper motion, CFS or printer services. The live
Cloud test file is recognized as Creality 7.1.0.0 with an estimated time of
191 seconds.

The estimator is a slicer post-processing tool. Nothing from this package is
started as a daemon on the printer.

The passive `scripts/gcode_time_audit.py` scanner checks uploaded files for a
skipped post-processor, missing time metadata, legacy CFS marker v1 and a large
gap between the total estimate and the `M73` timeline. It reads files only and
has no Moonraker, serial, G-code or printer-control path.

## F012 factory samples after reboot

Creality's `/etc/init.d/klipper` runs this on every boot:

```sh
rsync -a /usr/share/klipper/gcodes/F012/* /mnt/UDISK/printer_data/gcodes/
```

That restores `3DBench_PLA_21m.gcode`, `4color-3DBench_PLA_31m.gcode` and
`spatula_PLA_35m2s.gcode` unless the writable F012 source has the same hybrid
versions. `scripts/gcode_time_hybrid.sh` updates only those three source/user
pairs after validating package checksums, model F012, board and printer
standby. It backs up both sides and provides status/removal commands. The
read-only `/rom` factory image is never modified.
