# v5.2.21.86-status-dedicated review

## v5.2.21.86 notes

- The real long-lived Chrome profile reproduced a black Mainsail shell at the
  correct `/k2-status/` URL, while a clean headless profile rendered the page.
  This proved the remaining fault was same-origin service-worker interception,
  not the status HTML or JSON generator.
- Moved the status page to dedicated port 4410 and made live HTTP/no-store/JSON
  verification part of the transactional nginx installation.
- Kept Fluidd 4408 and Mainsail 4409 untouched for their normal roles. Removed
  only helper-owned legacy links and managed v85 cache blocks.
- Added parser coverage for idempotence, removal, old-rule migration, missing
  frontend ports and protection of a foreign listener on 4410.

## v5.2.21.85 notes

- Reproduced the compact page and JSON as HTTP 200 in Chrome Beta without
  console errors; the server response nevertheless lacked cache-control for
  the `/k2-status/` directory URL.
- Added managed no-store nginx locations for ports 4408 and 4409, a visible
  startup/JavaScript fallback and last-completed consumption display.
- Added idempotence, foreign-location protection, exact-port checks and parser
  regression tests for the nginx patch.
- The live patch must back up nginx and the changed helper files, pass all
  local tests, pass `nginx -t`, reload cleanly and then be checked in desktop
  and mobile Chrome viewports.

## v5.2.21.84 notes

- The successful eSUN ePLA-HS+ Gray run emitted the authoritative mapping
  `T0(T1A)=>T1B`, material ID `90001`, colour `9ea7ae`, PA `0.056` and Flow
  `96`. After unload, the live `box.filament` pointer returned to T1A; that
  pointer is current selection state and not calibration attribution.
- The helper now preserves the job mapping, verifies it against live T1B
  (`090001`, `09ea7ae`) and emits the calculated profile flow ratio `0.9408`
  from the G-code base ratio `0.98`.
- The same run recorded successful nozzle-camera image groups,
  `subCameraAbnormal: 0`, valid PA/Flow results, and then Creality's explicit
  power-off. The following error 19 / `No such device` lines are therefore
  classified as expected shutdown noise, while uncorrelated loss remains an
  attention state.
- No printer profile, CFS database, camera power policy, firmware, heater,
  movement or motor command is modified by this release.

## v5.2.21.83 notes

- A controlled CFS T1A Mini Whistle print completed normally and produced a
  valid timelapse. This rules out a persistent nozzle blockage and confirms
  the stock CFS load/print/unload path.
- Creality reports one result per PA image task. The observed failed run emitted
  five `-1.000000` task values and then repeated `0.040` as best/effective.
  The parser now marks that sequence as fallback and never persistable.
- The exact CFS WebSocket start is `multiColorPrint` with
  `enableSelfTest=1`. The tested `opGcodeFile` request selects the external
  rack and was correctly rejected while CFS filament was loaded.
- Five cold/idle power-only nozzle-camera cycles became online in 1.46-1.85 s,
  but the print log captured a rare publication race at the manufacturer's
  roughly two-second existence check. The exact stock nonblocking power script
  remains unchanged.
- No printer profile, filament database, heater, movement, CFS motor command,
  firmware or manufacturer service is modified by this release.

## v5.2.21.82 notes

- A full live firmware 1.1.6.7 run completed its print but skipped both Auto PA
  and Flow Ratio after `IsNozzleCameraExist nozzle_camera_is_exist=0`.
- The same camera then enumerated as USB `32e6:9221`, created video2/video3 and
  reached `camera_sub online=1` within about one second during a controlled
  power-only probe. Hardware, cable, GPIO and the stock hotplug mapper work.
- The failed run exposed a parser bug: `flow_pa best_flow_pressure_advance`
  contained the copied profile value 0.040 even though no PA capture started.
  Such candidates now require a real start and zero errors before confirmation.
- `start flow_em detect fail` no longer counts as a successful start, and the
  observed `Print Finish` marker now closes the lifecycle.
- No filament database, profile, Flow Ratio, Pressure Advance, AI preference,
  firmware, CFS command, heater or motion setting is changed.

## v5.2.21.81 notes

- A live Creality calibration start exposed two parser defects: a stale
  Fluidd/Mainsail source marker could be reused, and the file path preceding
  `with self test = 1` was not retained.
- The parser now associates the local-Web start, file path and self-test within
  a bounded sequence, resets pending source state, and records duplicate start
  requests.
- `NOZZLE_CLEAR canceled by user` and `user stop print finish` now classify the
  attempt as `cancelled`. Such a job can never produce a persistable result
  unless a genuine measured marker was already present.
- The regression fixture reproduces the exact observed lifecycle. The feature
  remains read-only and sends no printer, heater, motion, CFS or profile command.

## v5.2.21.80 notes

- The installed Creality Print device bundle was traced to its exact WebSocket
  request. A normal start sends `enableSelfTest=0`; enabling the visible
  `Print calibration` control sends `enableSelfTest=1`.
- Both retained Mini Whistle starts came from Fluidd with
  `with self test = 0`. They ran only the selected CFS waste-camera check and
  produced no Auto PA or Auto Flow measurement.
- Added a bounded read-only parser for current and optional rotated
  `master-server` logs. Confirmed PA requires a real result and is discarded
  if the firmware reports its printer.cfg fallback. Confirmed Flow requires
  `flow_em best_flow_percentage`; a lone M221/default does not qualify.
- Live output associates the result with G-code filament metadata, current CFS
  slot, CFS firmware and Spoolman ID while labelling all database/runtime
  values as non-measurements.
- Eight isolated calibration-state regressions pass. A first full live scan
  exposed that decompressing all vendor archives is too slow on the OpenWrt
  host, so normal status now tails only the current log and history is opt-in.
- Live verification on T1A reported CFS 1.5.0, Hyper PLA metadata, runtime
  PA 0.038 and Flow 100 as defaults only, with no confirmed calibration result.
- No print, movement, heater, camera power, CFS command, profile write,
  preference write or service restart was introduced.

## v5.2.21.79 notes

- Live binaries, hotplug scripts, UBus state and retained successful print
  evidence confirm two separate camera roles. Main camera CCX2F4013 performs
  monitoring/print AI; nozzle camera STD-8062V0 is an on-demand capture device
  for Auto PA, Flow Ratio and selected CFS waste checks.
- Corrected earlier helper wording that incorrectly associated first-layer
  detection with the nozzle camera.
- Added read-only preference/lifecycle reporting and a status-page KI section.
  The report keeps global readiness separate from the per-job
  `Print Calibration` trigger.
- Replaced persistent power recovery with a cold/idle-only temporary probe.
  Cleanup is registered before the camera is powered, and every success,
  failure or interruption returns it to standby/off.
- Manual standby is now also cold/idle-only, preventing accidental interruption
  of a Creality-owned capture.
- Health treats the verified idle tuple GPIO 162=1, no sub node and no
  `cam_sub_app` as `[OK]` standby.
- No vendor AI model, threshold, G-code, calibration value, camera firmware,
  CFS command, movement or heater setting was changed.

## v5.2.21.78 notes

- The first real whistle test reproduced `key564` while the extruder was
  physically stable at 220 C. Log timestamps tied the event to a synchronous
  22-second wait in a previously modified nozzle-camera power script.
- `/usr/bin/nozzle_cam_power.sh` was backed up and restored byte-for-byte from
  the immutable F012 `/rom` source. A firmware restart returned Klipper to
  `ready`, and the exact repeat print completed without another reactor gap,
  heater error or camera failure.
- The package now carries the exact stock script and validates its fixed hash.
  Status is read-only. Restore is manual and requires root, exact F012/board,
  matching ROM/package hashes, an idle/finished print state and both heater
  targets at zero. It backs up before an atomic replacement.
- The first successful passive CFS measurement is 351.0 mm on T1A, with zero
  unattributed usage, resets and anomalies. Klipper's print counter was
  300.7 mm; the difference is the visible Creality start/purge/end overhead.
- No firmware, CFS/MCU flash, calibration, Flow Ratio or Pressure Advance
  change was made.

## v5.2.21.77 notes

- Extends the one existing passive CFS monitor with a deduplicated mesh history,
  explicit slot confidence and a GET-only consumption dry-run. No second
  Spoolman writer was added.
- Adds a full-file G-code preflight for duplicate START/mesh paths, M600 on
  CFS, T0-T3 bounds, raw BOX commands, preview/layer/object metadata and
  implausible Pressure Advance syntax. It reports only and never edits G-code.
- Adds an exact F012/CR0CN200400C10 post-update version/hash baseline. Drift is
  reported but never automatically restored.
- Adds a compact read-only status page under both Fluidd and Mainsail. The same
  URL is suitable for a browser on the HelixScreen/K2Dash Raspberry Pi.
- Flow Ratio and Pressure Advance calibration remain unchanged by explicit
  user decision.

## v5.2.21.76 notes

- Adds passive bed-mesh plane/residual analysis without movement or probing.
- Adds a fixed GET-only K2 LAN/CFS report without generic command input.
- Adds source-level safety, privacy and WebSocket framing regression tests.
- Documents the broader K-series project comparison and F012 compatibility
  decisions in `docs/K_SERIES_PROJECT_INSIGHTS_K2_PRO_2026-07-30.md`.

## v5.2.21.75 notes

- K2 OpenKlipper commit `c3d5c4dd1550fb164dc7cb970363f379428c33c4`
  was reviewed as a protocol reference, not as installable K2 Pro firmware.
- CFS `mode=0` is now reported as an idle load/unload operation engine. It does
  not prove that Creality's separate steady-feed path is disabled.
- Slot selection remains useful for Spoolman mapping, but the report now says
  explicitly that stock Moonraker does not expose the feed-arm flag or the
  RS485 buffer-arm state.
- `buf_len=0x0` and non-zero `buf_len` lines are counted separately. They are
  receive-buffer parser evidence, not automatic CFS faults.
- Config safety checks now follow only the include graph rooted at
  `printer.cfg`. This removes false alarms from stale automatic config backups
  without weakening checks on nested active files.
- The existing Creality START/END, M8200, arc implementation, CFS transaction
  path and F012 low-level configs remain unchanged.
- No OpenKlipper K2 Plus board mapping, probe bypass, raw motor command, custom
  load/unload transaction, firmware image or macro override was imported.

## v5.2.21.74 notes

- The official K2 Pro `1.1.6.7` image was matched to exact model `F012` and
  board `CR0CN200400C10`, checked with SHA-256, unpacked, compared with
  `1.1.6.3`, and accepted by Creality's `swupdate --check`.
- The K2 Pro MCU, nozzle MCU, motor and RFID payloads are byte-identical to
  `1.1.6.3`; the changed low-level bundle is CFS `1.5.0`, plus CFS-Pro/CFS-2
  host support.
- The active host wrapper is based on Creality's `1.1.6.7` source and keeps
  only the previously reviewed 10-second idle polling interval.
- The guard treats connected CFS `1.4.2` plus bundled `1.5.0` as an available
  separate update, not a mismatched image.
- A newer connected live state supersedes a stale boot-time monitor failure,
  preventing a false blocking health result after startup.
- Firmware metadata checks now compare the display-side JSON to the runtime
  OTA version and search the firmware subdirectory used by the installer.
- No automatic CFS, MCU, camera or firmware flashing was added.

## v5.2.21.73 notes

- A live July 27 audit found that Creality rewrote the material database at
  19:02 the previous evening and removed custom profile `90002`; the old guard
  only checked once after boot.
- The guard now watches the three relevant database files at five-minute
  intervals and only acts after their signature changes.
- Automatic repair requires a reachable Moonraker status, a cold bed and
  extruder, and a print state of `standby`, `complete` or `cancelled`.
- Printing, pausing, heating, unknown schema, unavailable Moonraker and profile
  collisions all defer or abort without a database write.
- The generated service has start, stop, restart and PID-backed status control.
  Full health warns if an installed watcher is not running.
- Eleven CFS DB tests cover preservation, collisions, schema drift, official
  fingerprinting and the new cold-idle safety gate.
- Static type-check findings were corrected without altering runtime behavior.
- No CFS/RS485 command, motion, heating, print start, calibration or flash was
  introduced.

## v5.2.21.72 notes

- WSL validation exposed two hard-coded service-directory arguments in the
  otherwise isolated CFS Safe Tools boot-hook integration test.
- Service directories now follow `CFS_SAFE_SERVICE_INIT` and
  `CFS_SAFE_SERVICE_RC`, and a failed directory creation aborts before copying.
- The local validator now executes the shell integration test on every release.
- Runtime behavior on the K2 Pro is unchanged because the production defaults
  still resolve to `/etc/init.d` and `/etc/rc.d`.

## v5.2.21.71 notes

- Added a strictly read-only combined guard for exact F012/CR0CN200400C10 firmware identity, MCU/CFS/camera bundles, low-level config drift, recovery inventory, update-aware CFS database preservation and passive CFS state.
- Active `box.cfg` and `motor_control.cfg` must match the exact installed F012 factory files. `factory_printer.cfg` is validated structurally because Creality's active runtime variant intentionally differs from the older packaged reference.
- The OTA file gate requires the exact board token, blocks known foreign K2 Plus/camera tokens and downgrades, and requires a caller-supplied trusted SHA-256. It does not invoke any update or flash path.
- The source selftest permits only the read-only `get_sn_mac`, OTA-version and `fw_printenv` subprocesses. Regression fixtures cover exact F012 success, foreign board, low-level drift, cold-extrusion bypass, camera mismatch, database-base change and OTA hash/board handling.
- Integrated the compact result into preflight and full health, plus dedicated status menu and CLI commands.
- No firmware, MCU, CFS, camera, motion, heater, cutter, serial or restart command was added.

# v5.2.21.70-new-tools-audit review

## v5.2.21.70 notes

- A live source/install hash comparison found that `/etc/init.d/S98nozzle_camera_recover` still used the older July 1 behavior while the packaged source contained the safer July 14 status-only restart behavior.
- The installer now validates all packaged shell, Python and JSON files plus the regression suite before copying anything.
- Existing helper-managed S97/S98 files are updated atomically with a backup and no service restart; full health now detects future drift.
- Package version labels are consistent. The previous v5.2.21.69 helper header and Fluidd code were newer than its v5.2.21.68 installer, preflight and Spoolman labels.
- ShellCheck 0.11.0, shfmt 3.13.1, Ruff 0.16.0, Python compile checks and the printer's native BusyBox ash/Python 3.9 tests are required before release.
- No firmware, MCU, CFS, motion, heater, calibration or print behavior is changed.

# v5.2.21.68-stable-health-count review

## v5.2.21.68 notes

- The Moonraker log health section now emits exactly one healthy HelixPrint optional-probe result whether the recent count is zero or nonzero.
- This removes a misleading `82` versus `83` OK-total drift without hiding real Moonraker errors.
- Shell syntax, Python compilation, the regression suite and the live full health check are required before release.

## v5.2.21.67 notes

- A real cold boot logged `Spoolman CFS sync started` with the K2's initial 2020 clock, then jumped to 2026 after time synchronization. Because readiness used `time.time()`, the jump made the 180-second startup wait expire immediately and the first sync reached Moonraker before its Spoolman endpoint existed, producing a transient `HTTP Error 404`.
- Startup waits, metadata intervals, heartbeat intervals and repeated-warning intervals now use `time.monotonic()`. Log timestamps deliberately remain wall-clock based.
- The regression test forces the wall clock to jump and verifies readiness continues until Moonraker/Spoolman report ready.

## v5.2.21.66 notes

- A live `/server/webcams/test` call reproduced empty URLs and four Moonraker tracebacks. The bundled webcam parser expects the local address in field four of `ss -ltn`, while the previous BusyBox shim exposed field four as `Send-Q`.
- The new compatibility wrapper emits only the listener format Moonraker needs, converts IPv6 wildcard listeners to parser-safe IPv4 wildcard entries for port discovery, and passes other invocations through to BusyBox `netstat`.
- Installation saves the pre-helper wrapper once, updates atomically through a validated candidate, and can restore the prior wrapper. A camera health run now tests both format compatibility and Moonraker's own webcam-test endpoint.

## v5.2.21.65 notes

- The first real cold boot proved that this Creality image does not automatically execute the copied `S97cfs_safe_monitor` service from `/etc/rc.d`. Existing helper services are started explicitly by `/etc/rc.local`.
- CFS Safe Tools now adds exactly one validated `/etc/rc.local` boot hook with a timestamped, PID-suffixed backup and removes only its own marker and command during uninstall.
- The monitor remains passive. This persistence fix adds no G-code, CFS/BOX, serial, motor, heater, cutter or filament command.

## v5.2.21.64 notes

- Compared the current Creality and Klipper estimates with 11 latest completed Moonraker history records: nine single-color and two real CFS jobs.
- A fixed 110-second median residual was the best conservative model in leave-one-out testing. It avoids fitting a fragile duration curve to only nine samples.
- The wrapper detects real `Tn` transitions. Single-color files retain Klipper Estimator `M73`; CFS files restore Creality's change-aware `M73`; both receive the calibrated residual that decays with remaining progress.
- The original G-code is held until both stages succeed. Any estimator or hybrid failure restores it, and already hybridized files are left unchanged.
- The model targets Moonraker `print_duration`. Variable AI, nozzle cleaning, heating and user pauses remain runtime-only overhead and are not hidden inside the static estimate.
- A real cold boot showed that Creality's stock Klipper init script always runs `rsync -a /usr/share/klipper/gcodes/F012/*` into the user directory. The helper now has an F012-only, SHA256-guarded install/status/remove path for the three affected factory samples, with source and user backups and no change to `/rom`.

## v5.2.21.63 notes

- Added the exact upstream Klipper Garbage Collection module (`SHA256 6d339dcd08752fb95322ca5fb71a7624fec07cdaf639cb47803653346db232ff`) with a separate include, status, health, dependency, backup and rollback coverage.
- A live isolated Klipper restart exposed Creality's `motor_control_wrapper.Motor_Control.set_motor_pin` ready-callback failure. The helper now detects the K2 Pro Combo/CFS config, blocks restart while printing/paused and schedules a full Linux reboot instead.
- Fixed CFS Safe Tools so an early Moonraker/CFS startup race no longer terminates its monitor. A simulated unavailable endpoint confirmed that the worker stays alive and retries.
- Included the tested Creality Print and Creality Cloud Slicer Klipper Estimator package and its offline Moonraker cache fallback. The estimator remains a Windows slicer post-process tool, not a printer daemon. Both header formats have unit tests; 17 existing G-code files passed a metadata-only diff before atomic migration. Moonraker's Creality parser receives a guarded, backed-up regex extension so Cloud Slicer files expose their estimated time in Fluidd/Mainsail.

# v5.2.21.62-cfs-safe-tools update-aware CFS follow-up

## v5.2.21.62 notes

- The database guard now separates official and local custom profiles. It fingerprints the official base and only restores the two known local profiles when they are absent.
- A future Creality DB with more official profiles is retained in full. Existing local custom values are retained. ID/identity collisions and unknown schema changes abort before writes.
- CFS Safe Tools permanently integrates the previously live-tested passive prototype as an init service with state heartbeat, compact JSONL events, helper status/events/G-code reports and health checks.
- Isolated migration tests verify 60 official plus 2 local profiles, local edit preservation, collision no-write behavior, minimal options repair, schema no-write behavior and official fingerprint tracking.
- A real CFS tool-change print is still required before event counters can be considered field-validated; installation does not start a print or move filament.

# v5.2.21.61-maintenance-sync live maintenance follow-up

## v5.2.21.61 notes

- Unified helper and Spoolman worker version markers on the current live package.
- Corrected Git Backup detection in the uninstalled-module audit.
- Added narrow Git ignore rules for generated Klipper backup copies, leaving the active configuration tracked.
- Preserved the validated Creality core, CFS/AI workflow, camera bridge and stock timelapse recovery path.

# v5.2.21.57-live-audited-improved full live audit follow-up

## v5.2.21.57 notes

- Full live audit on `192.168.178.74` found the installed v56 helper healthy: CFS/Box connected, Spoolman connected, camera/frontends reachable, syntax/JSON checks clean, no helper FAIL results.
- Spoolman/CFS slot map is valid and maps real local Spoolman spools `1-4` to `T1A-T1D`; v57 keeps that map but makes `enabled=true` explicit.
- The live CFS material database already contains the required custom profiles for eSUN Gray and Sovol Steel Blue; no DB rewrite is needed.
- The sync daemon now suppresses repeated unchanged OK lines and keeps immediate logging for changes/warnings plus a periodic heartbeat.
- Moonraker update-manager still shows Creality zip/vendor-tree metadata; do not update core Klipper/Moonraker from this helper package.

# v5.2.21.56-live-tested-improved live follow-up

## v5.2.21.56 notes

- Live Moonraker API check on `192.168.178.74`: `K2Pro-Chris`, Klippy `ready`, print state `standby`, Spoolman connected, Fluidd/Mainsail/go2rtc reachable.
- Fixed Spoolman CFS map logic: IDs `1`, `2`, `3`, `4` can be real local Spoolman spool IDs and are no longer blocked as demo placeholders.
- Preserved the live legacy map behavior: `/mnt/UDISK/helper-script/spoolman_cfs_map.json` had complete T1A-T1D IDs but no `enabled` field, so v56 treats that as active instead of disabling the existing setup.
- Cleaned worker launches so Spoolman, camera, timelapse and CFS-DB Python helpers use `python3 -B`; removed the Spoolman service dependency on missing `nohup`.
- Updated the Spoolman CFS sync User-Agent and generated map marker to this build.
- SSH was reachable on port 22, but password/key login was not available in this session, so live shell execution is still gated by SSH credentials.

# v5.2.21.55-normal-improved selected v54 improvements

## v5.2.21.55 notes

- Kept the normal K2 Pro Combo helper posture and selected only the useful v5.2.21.54 pieces.
- Added Spoolman CFS service control, status, list, wizard, enable/disable and sync-once paths.
- Removed the active demo `spoolman_cfs_map.json` from the package so a real printer map is not overwritten.
- Added M600 CFS bridge mode: slicer M600 can pause/park, while material movement remains in the Creality/CFS/display/slicer workflow.
- Added explicit Nozzle-AI recover and standby commands; boot remains status-only.
- Updated health/preflight/dependency/deep audit logic for the added modules.
- Deliberately did not include raw G-code/CFS Expert Control or full-stack one-shot installers in this normal build.

# v5.2.21.50-reviewed Nozzle AI camera USB/UVC diagnostics

## v5.2.21.50 notes

- Added `helper.sh --nozzle-camera-diagnose` and a matching menu entry for read-only K2 Pro nozzle AI camera diagnostics.
- The diagnostic reports Creality `ubus` camera status, GPIO/node state, `/dev/video*` and `/dev/v4l` mapping, `/etc/hotplug.d/usb/60-v4l`, optional `udevadm` identity data and recent USB/UVC/BIND/nozzle log evidence.
- Health and preflight now include a compact nozzle-camera USB line without treating idle/offline standby as a failure. The helper still leaves Creality's stock on-demand Auto PA/Flow/CFS-waste camera power control intact.
- Community/forum evidence was folded in conservatively: camera visibility issues in Creality Print after firmware updates are not assumed to be a printer-camera fault when Fluidd/Mainsail/go2rtc remain healthy, and USB hub/path changes should be diagnosed before recovery.

# v5.2.21.49-reviewed Creality Timelapse recovery stale-ID fix

## v5.2.21.49 notes

- Fixed `creality_timelapse_recover.py` for the observed live K2 Pro case where today's `/mnt/UDISK/timelapse/main_output.h264` was treated as already processed because the newest display-server log metadata still pointed to an older print ID.
- The recover logic now rejects stale display metadata when its ID timestamp is too far from the raw H264 mtime, uses a valid epoch-second fallback ID, and only suppresses a duplicate source when the recorded output video still exists.
- This keeps Creality stock timelapse recovery compatible with firmware 1.1.6.3 while preserving the existing backup-first `delay_image_info.json` update path.

# v5.2.21.48-reviewed Spoolman worker restore / menu completion

## v5.2.21.48 notes

- Restored `spoolman_cfs_sync.py` and `spoolman_cfs_map.json` to the reviewed package after live audit found the init service present but the worker missing.
- Tightened `--status`, `--dependency-audit`, and `--health` so Spoolman CFS Sync is only considered complete when the service, worker, and slot map are all present.
- Added a dedicated health section for Moonraker Spoolman connectivity and active spool reporting.

## v5.2.21.47 notes

- Completed the three previously visible placeholder entries in a K2 Pro Combo-safe way.
- `Git Backup lokal` now initializes local Git history in `/mnt/UDISK/printer_data/config`, creates snapshots without a cloud remote by default, and supports optional manual `remote <git-url>` and `push` commands later.
- `OctoEverywhere` now has status/remove helpers and a guarded official installer launcher. It does not run the cloud installer silently; the user must type `INSTALL OCTOEVERYWHERE`.
- `Mobileraker` now provides practical app connection data for local Mainsail/Fluidd/Moonraker access and recommends running Mobileraker Companion on a Raspberry Pi/Debian host instead of installing a Python companion stack into Creality firmware.
- Menu labels, installed overview, dependency audit, menu audit and uninstalled-module audit now distinguish local helpers, external/cloud helpers and companion-device workflows.
- No firmware flash, print start, movement, heating, CFS load/unload/extrude/refresh command or blind cloud credential behavior was added.

# v5.2.21.46-reviewed safety polish / backup / CLI cleanup

## v5.2.21.46 notes

- Local clean review package removes accidental runtime state from the ZIP (`.installed` and `.creality_timelapse_recover_state.json`), replaces the local Windows `patch_dir` with `files/cfs_db_patch`, fixes the expert prompt newline, and avoids a broad `killall go2rtc` during camera stop.
- Added `helper.sh --version` for quick package verification.
- Hardened Entware `ensure` so it only runs when `/opt/bin/opkg` exists and no longer creates rc.local/PATH/SFTP changes on a non-Entware system.
- Routed direct CFS DB install/repair CLI calls and the maintenance-menu CFS DB repair through K2 Pro compatibility checks instead of bypassing the normal guard.
- SFTP symlink creation now checks that Entware's `sftp-server` binary exists before linking.
- Backup now also archives the CFS material database snapshot and helper `.installed` marker.
- Restore now creates a pre-restore backup of the current config before overwriting files, stores it in a separate `pre_restore/` folder and lists only full helper backups in the restore chooser.
- Backup/restore now returns failure codes for failed backup creation, corrupt restore archives, missing `printer_data/config` content or failed config copy.
- Compact CFS protocol reporting now signals partial/unavailable live data instead of returning a false all-OK result when Moonraker cannot be queried.
- Deep file audit broken-symlink failures now increment the final FAIL counter correctly.
- Dependency audit now exits non-zero when required dependencies are missing.
- Replaced `echo -e` status/menu output with portable `printf` in helper shell scripts to avoid ugly stray `-e` prefixes on stricter `/bin/sh` implementations.
- No firmware flash, print start, motion, heating, CFS load/unload/extrude/refresh command or network/security-hardening behavior was added.

# v5.2.21.45-reviewed polish / packaging / audit cleanup

## v5.2.21.45 notes

- Repacked with Unix executable bits for shell scripts, Python helpers, init helper and bundled `go2rtc`.
- Added the missing shebang to `scripts/cfs_protocol_report.sh` and made missing `python3` report cleanly.
- Corrected CFS slot/DB reporting so empty `-1` slots are not treated as missing live material profiles.
- Updated deep file audit and the Moonraker webcam patch verification to compile Python in memory, preventing new `.pyc`/`__pycache__` artifacts.
- Fixed deep file audit return code handling while keeping timestamped report output.
- Extended helper/dependency/deep audits to include `scripts/S98nozzle_camera_recover`.
- Cleaned README install instructions and corrected the `go2rtc` packaging note.
- No firmware flash, print start, movement, heating, CFS load/unload/extrude/refresh command or network/security-hardening behavior was added.

# v5.2.21.44-reviewed menu cleanup / restore visibility

## v5.2.21.44 notes

- Reworked the interactive menu into clearer K2 Pro Combo groups without changing the safety policy.
- Made backup restore visible in the restore/remove menu instead of leaving it only as an internal handler.
- Removed the duplicate Spoolman/CFS Sync install entry that actually invoked Moonraker Extensions; Spoolman/CFS state remains visible in the installed overview.
- Added Dependency Audit, Deep File/Script Audit, Timelapse Recover status and Entware status to easier-to-find menus.
- Allowed `helper.sh --help` to print usage before the root/TTY checks.
- Kept M600 non-CFS-only, HelixScreen test-only, Z-Offset expert-locked, CFS diagnostics read-only, and no firmware flash/print/movement/security changes.

# v5.2.21.43-reviewed Mainsail camera/K2 Pro Combo fit

## v5.2.21.43 notes

- Live-tested the deep file audit and removed false positives for Creality GUI event streams and inactive service backup files.
- Final deep-audit output should now reserve FAIL for active breakage only.

# v5.2.21.42-reviewed Mainsail camera/K2 Pro Combo fit

## v5.2.21.42 notes

- Added a read-only deep file/script audit so broad "check every program/file/script" runs are reproducible.
- The audit avoids false positives on Creality encrypted files (`user_info.json`, `tb_info.json`, `user_data_not_deleted.json`), GUI event-stream files (`pipe-*`, `statistic-*`, `print_list-*`) and inactive init-script backups.
- The report includes shell/Python syntax, JSON/config classification, Klipper includes, executable permissions, symlinks, Nginx syntax and recent severe logs.

# v5.2.21.41-reviewed Mainsail camera/K2 Pro Combo fit

## v5.2.21.41 notes

- Live audit found `go2rtc` copied without executable permissions, causing Mainsail/Fluidd camera proxy 502 despite a correct Moonraker webcam entry.
- `helper.sh --restart-camera` now restores `chmod +x` on `go2rtc` before starting S99camera.
- Camera health now checks the executable bit directly to make this failure obvious.

# v5.2.21.40-reviewed Mainsail camera/K2 Pro Combo fit

## v5.2.21.40 notes

- Mainsail 2.18+ filters webcams by `enabled`. Creality's bundled Moonraker webcam component did not expose that field, so a working go2rtc stream could still be hidden in Mainsail.
- Camera install/repair now patches Moonraker's webcam API output with a backup-first compatibility shim: `enabled=true`, `icon=mdiWebcam`, `target_fps_idle`, `aspect_ratio=16:9` and `extra_data={}`.
- Camera health now validates the Mainsail-required `enabled` field in addition to the K2 camera service, URLs and FPS.

# v5.2.21.39-reviewed Mainsail camera/K2 Pro Combo fit

Live follow-up for Mainsail and camera adaptation on the K2 Pro Combo.

- Verified Mainsail `v2.18.2` against the GitHub latest release and kept it installed.
- Added health checks for the Mainsail go2rtc proxy frame and stream page.
- Added Moonraker webcam-entry validation for the K2 Camera service, stream URL, snapshot URL and FPS.
- Stopped future camera repairs from injecting old Mainsail Vue-store JavaScript; current Mainsail uses Moonraker's webcam API.
- Improved `mainsail.sh status` to read `.version` and `release_info.json`.
- Added a Mainsail dashboard DB check for visible webcam and Spoolman panels.

# v5.2.21.38-reviewed CFS protocol report

Live follow-up after learning the K2 Pro CFS communication model.

- Added a read-only `cfs_protocol_report.sh` that documents the local RS485 stack, slot-to-database mapping, M8200/CR_BOX path and risky command policy.
- Added helper menu and CLI wiring via `helper.sh --cfs-protocol-report` / `--cfs-protocol`.
- Added compact report output to Health and Preflight so firmware-reset checks show CFS slot/DB drift without using BOX refresh or raw bus commands.
- Added documentation in `docs/CFS_COMMUNICATION_READONLY_2026-07-06.md`.

# v5.2.21.35-reviewed install preservation / dependency audit cleanup

Live follow-up after installing v5.2.21.34-reviewed on the printer.

- Fixed `scripts/dependency_audit_k2pro.sh` so it compiles helper Python files in memory instead of using `python3 -m py_compile`, avoiding `.pyc` files in `/mnt/UDISK/helper-script`.
- Preserved/restored the runtime `go2rtc` binary from the previous helper directory during the live install, because the reviewed source ZIP does not bundle that downloaded binary.
- Removed generated `.pyc` files found after the dependency audit run.
- No firmware flash, print start, movement, heating, CFS load/unload or security-hardening behavior was added.

# v5.2.21.34-reviewed KAMP/M600 clarity

Checked against the cleaned v5.2.21.33-reviewed staging tree and the live printer helper baseline.

- Updated labels to v5.2.21.34-reviewed.
- Clarified KAMP wording: already detected/tested KAMP-K2 is repair/reinstall with backup, while a fresh KAMP install remains an Expert test.
- Kept the M600/CFS policy unchanged: M600/FILAMENT_LOAD/FILAMENT_UNLOAD are non-CFS-only and block on CFS/Box.
- No firmware flash, print start, movement, heating, CFS load/unload or security-hardening behavior was added.

# v5.2.21.33-reviewed M600 non-CFS cleanup

Checked against the user-modified v5.2.21.32-reviewed ZIP.

- Kept the new M600 policy: M600 is only for printers without CFS/Box.
- Removed the remaining confusing force-bypass wording from the reviewed notes. On K2 Pro Combo with CFS/Box, M600/FILAMENT_LOAD/FILAMENT_UNLOAD should block instead of offering a force path.
- Removed generated `__pycache__`/`.pyc` artifacts from the cleaned package.
- No firmware flash, print start, movement, heating, CFS load/unload or security-hardening behavior was added.

# v5.2.21.32-reviewed clarity/safety cleanup

Checked against v5.2.21.30-hotfix. Shell syntax and Python compile checks pass.

Changes made:

- Fixed stale preflight version text.
- Made placeholder modules visibly **not implemented** instead of normal-looking install items.
- Removed unnecessary backup requirement just to view placeholder messages.
- Changed KAMP handling: repair/reinstall is available when KAMP is detected, but a fresh KAMP install goes through Expert-Unlock.
- Removed generated `__pycache__` artifacts from the output package.

# K2 Pro Combo Helper v5.2.21.17 Review Notes

Checked locally against the uploaded `Creality-Helper-Script-K2-Pro-Combo-firmware-aware-v5.2.zip`.

## Result

The package is usable as a guarded K2 Pro helper build.

## v5.2.21.17 live follow-up

- Improved the compact CFS health result for active prints. If the log tail shows `print_stats: printing`, high raw-frame/noise counts no longer become a warning by themselves when severe CFS errors are zero and timeout counts remain below the existing threshold.
- Reason: live K2 Pro Combo check on 2026-07-03 showed a running CFS print with healthy BOX state and `0` severe CFS hits, but a misleading high raw-frame/noise warning caused by normal polling.

## v5.2.21.16 live follow-up

- Full health was functionally clean but had one misleading warning for a missing local firmware image despite installed firmware `1.1.6.3` being current; this is now informational.
- Timelapse recover daemon log was writing the normal idle state every 30 seconds; it now logs repeated idle/no-raw states only once until the state changes.
- This build intentionally keeps the v5.2.21.15 no-security-hardening behavior.

## v5.2.21.15 live follow-up

- User requested no security improvements. The active go2rtc API/RTSP localhost binding from v5.2.21.14 was reverted.
- Functional camera behavior remains: the watchdog and health checks avoid `frame.jpeg` snapshot probes that can hang on the direct Creality WebRTC source.
- Helper version was bumped so installed printer files and the local package clearly show the no-security-hardening revision.

## v5.2.21.14 live follow-up

- Live camera check found many hanging go2rtc `keyframe` consumers caused by `frame.jpeg` probes against the direct Creality WebRTC source.
- go2rtc API/RTSP localhost binding was tested here but reverted in v5.2.21.15 because no security improvements should be applied.
- Camera watchdog and helper health now use stream configuration checks instead of snapshot probes, so idle camera state no longer causes reconnect loops or leaked consumers.
- Full live helper health passed after the change with `OK:45 WARN:1 FAIL:0`; the only warning was the missing local firmware image on UDISK, not a runtime fault.

## v5.2.21.13 live follow-up

- Health output now treats nozzle AI camera standby as `[INFO]`, not `[WARN]`.
- This matches the confirmed Creality on-demand power behavior and keeps real warnings visible.
- Old root-level helper archives on UDISK may be moved into an archive folder; do not delete firmware rollback images automatically.

## v5.2.21.12 live follow-up

- Creality binaries reference `nozzle_cam_power.sh on/off`; later live tracing confirmed on-demand control for Auto PA, Flow Ratio and selected CFS waste checks. First-layer detection belongs to the main camera path.
- Changed the boot hook from auto-recover to status/log only; it no longer forces the nozzle AI camera to stay on after every reboot.
- Added `standby`/`off` mode for the recovery helper so the camera can be parked with Creality's stock power script when the printer is idle.
- Health now reports an offline nozzle AI camera as standby/on-demand warning rather than a hard helper failure.

## v5.2.21.11 live follow-up

- The K2 Pro nozzle AI camera was offline after reboot because GPIO162 was left in the off state.
- Creality's stock `/usr/bin/nozzle_cam_power.sh off/on` recovered the device: USB `32e6:9221`, `/dev/v4l/by-id/sub-video2 -> /dev/video2`, `camera_sub online=1`, and `cam_sub_app` running.
- Added a helper recovery script and health checks so this failure is visible and recoverable after future boots.

## v5.2.21.10 live follow-up

- Reboot verification confirmed the direct camera path persists: `go2rtc=1`, `k2rtc=0`, `watchdog=1`.
- Replaced the watchdog's stale-stream heuristic with a real JPEG frame probe because go2rtc direct Creality producers do not expose `bytes_recv` in `/api/streams`.
- Full helper health after reboot passed with `OK:49 WARN:0 FAIL:0`.

## v5.2.21.9 live follow-up

- Patched `creality_timelapse_recover.py` so an already-listed raw H264 source is recorded in state once and then treated as already processed.
- This avoids repeated `timelapse id ... is already listed` daemon log/write cycles while preserving the existing Creality `delay_image` recovery behavior.
- Patched `scripts/health.sh` so the CFS/BOX check retries through the short Creality RS485 reconnect window before failing.

## v5.2.21.8 live follow-up

- Firmware `1.1.6.3` was installed on the live K2 Pro via Creality's local OTA updater.
- Camera support was switched from `k2rtc.py -> go2rtc` to direct go2rtc Creality WebRTC mode.
- Live verification passed with `go2rtc=1`, `k2rtc=0`, `watchdog=1`, and working Fluidd/Mainsail frame URLs.
- Helper health logic now detects direct `#format=creality` mode so the installed direct camera setup does not report a false `k2rtc.py` failure.

## Verified

- All shell scripts pass `sh -n` syntax checks.
- Risk modules remain visible but locked:
  - `z_offset.sh`
  - `kamp.sh`
  - `helixscreen.sh`
- Those three scripts also contain direct install guards, so they do not run just because someone executes the script file manually.
- No active hard-coded K2 Plus 350/370/380 movement coordinates were found in the code.
- Firmware-aware model guard is present: K2 Pro should be `F012`, board `CR0CN200400C10`.
- Moonraker patching now prefers `/etc/init.d/moonraker`, which is safer when `/etc/rc.d/S56moonraker` is a symlink.

## Remaining caution

Camera Support, Entware, Fluidd/Mainsail update and Moonraker Extensions still touch system files. The helper menu now blocks install entries until Preflight compatibility is confirmed and a helper backup exists.

## v5.2.3 changes made here

- Added backups before Camera Support modifies nginx/Fluidd/Mainsail/rc.local files.
- Made camera reboot confirmation explicit.
- Corrected the backup order so `/etc/rc.local` is copied before the camera startup entry is inserted.
- Fixed Entware's embedded Python syntax errors in the `/etc/rc.local` edit paths.
- Fixed Entware PATH persistence so `$PATH` is written correctly.
- Replaced the Entware `wget ... | sh` pattern with download-to-file plus explicit `sh`.
- Added menu-level guards for K2 Pro compatibility and required backup before install options.

## v5.2.4 changes made here

- Fixed the Camera Support install path so missing `go2rtc`, missing `S99camera`, and stale nginx `/go2rtc` blocks are repaired.
- The camera service starts immediately after install and no longer asks for a reboot.
- The Moonraker webcam entry now uses `mjpegstreamer-adaptive` and direct go2rtc `:1984` `frame.jpeg` URLs so both Fluidd and Mainsail display the working snapshot stream without resolving `/go2rtc` against the stock port 80 web server.
- Added a `boot` mode for `S99camera` so boot still waits 60 seconds, while manual `restart` is immediate.
- Replaced the nginx go2rtc patcher with an idempotent parser that updates/removes the 4408 and 4409 server blocks and validates with `nginx -t`.
- Added the missing Moonraker `[update_manager]` section, with system package updates disabled for safety.
- Added firmware compatibility stubs for `/usr/share/scripts/moonraker-requirements.txt` and `/usr/share/scripts/install-moonraker.sh`, which this bundled Moonraker update_manager requires before it will load.

## v5.2.5 changes made here

- Removed `eval` from backup restore selection and added tar path safety checks.
- Reworked installed-feature and printer.cfg include removal to exact-match lines.
- Replaced Moonraker section removal with a line-based parser.
- Made restart helpers return failure when Klipper, Moonraker or nginx do not come back.
- Added nginx validation to Fluidd and Mainsail nginx edits.
- Hardened download/extract paths for Fluidd, Mainsail, KAMP, Timelapse, Entware and HelixScreen.
- Prevented duplicate `[file_manager]` sections during KAMP object-processing setup.
- Made M600 compatible with printers that provide `PAUSE` but not `PAUSE_BASE`.
- Removed the `less` dependency from log viewing.

## v5.2.6 changes made here

- Added `scripts/health.sh` for repeatable helper, camera, Moonraker, CFS/BOX, log and disk checks.
- Added menu options `28`, `29`, `30` and `31` for camera health, CFS/BOX diagnosis, full helper health and camera bridge restart.
- Hardened the generated `S99camera` service with PID files and stale-process cleanup so duplicate watchdogs are not left running after restarts.
- Added `S99camera health` for local go2rtc stream/frame checks.
- Fixed `system.sh restart_camera` to restart `S99camera` when the helper camera bridge is installed.
- Brought the packaged `camera_watchdog.py` template in line with the generated stale-stream watchdog.
- Replaced the static example IP in packaged `go2rtc.yaml` with `127.0.0.1` plus a note that install rewrites it.
- Expanded preflight output with helper version, installed marker, live CFS/BOX summary and camera status.
- Added a visible warning that Creality Klipper/Moonraker core should not be updated from Fluidd/Mainsail update manager on this vendor firmware.

## v5.2.7 changes made here

- Marked CFS/BOX diagnosis as read-only and non-moving.
- Added a safety warning for the official `BOX_LOAD_MATERIAL` path because it calls `BOX_EXTRUDE_MATERIAL`.
- Documented the live failure: direct `BOX_LOAD_MATERIAL TNN=T1A` produced `key60` / `Internal error on command:BOX_EXTRUDE_MATERIAL` and put Klipper into shutdown.
- Added recent-log detection for `key60`, `BOX_EXTRUDE_MATERIAL` and `BOX_LOAD_MATERIAL_EXTRUDE_MATERIAL`.
- Added the same CFS direct-load safety note to the preflight report.

## v5.2.8 changes made here

- Added real non-interactive CLI entrypoints for health, preflight, backup, installed-feature listing and camera restart.
- Blocked the interactive menu when stdin is not a TTY, preventing SSH/batch calls from hanging inside menu prompts.
- Fixed the discovered unsafe `helper.sh --health` behavior: unsupported arguments no longer fall through to the interactive menu.

## v5.2.9 changes made here

- Fixed a harmless but noisy health-check race where a short-lived process could disappear while `/proc/.../cmdline` was being read.
- Updated the preflight report header to the current helper version.

## v5.2.10 changes made here

- Added a CFS safety warning for the real live finding that saving only `auto_addr` can trigger Creality's binary `motor_control_wrapper` ready-callback bug.
- Added recent-log detection for `motor_control_wrapper.Motor_Control.set_motor_pin`, `No active exception to reraise` and `Internal error during ready callback`.
- Changed `buf_len` detection to count every `buf_len = 0x...` line, because the live printer produced `buf_len = 0x9` as well as earlier `0x0` noise.

## Recommended first run order

1. `K2 Pro Preflight report`
2. `Backup Klipper config + important system files`
3. Optional: one module at a time, for example `Camera Support`, `Mobileraker`, `Git Backup`, `Entware`
4. Do not use `Z-Offset`, `KAMP` or `HelixScreen` unless using Expert-Unlock deliberately.
5. Use `Full helper health check` from the interactive menu, or `./helper.sh --health` over SSH.
6. Use the printer display/official Creality workflow for CFS loading; do not trigger direct `BOX_LOAD_MATERIAL` or `BOX_EXTRUDE_MATERIAL` tests from Moonraker/helper.

## v5.2.11-reviewed notes

- Reviewed `v5.2.10-fixed` package.
- Shell syntax check passed for all `.sh` files and Python helper files compile successfully.
- Added a safer `/etc/rc.local` handling path in the camera module: it now creates a minimal `rc.local` if missing and removes camera startup entries without failing if the file is absent.
- Made nginx backup handling quieter/safer when `/etc/nginx/nginx.conf` is missing.
- Camera health check now warns instead of failing when Camera Support was never installed; it still fails if `camera_support` is marked installed but `S99camera` is missing.
- Risk modules remain present but Expert-Unlock only: Z-Offset, KAMP, HelixScreen.

## v5.2.12-fixed changes made here

- Updated stale package labels so the helper header, preflight report and documents agree on the current build.
- Removed accidental `__pycache__`/`.pyc` artifacts from the release package.
- Made Fluidd camera index edits optional-safe: install and remove now skip cleanly when `/usr/share/fluidd/index.html` is missing instead of aborting the camera module.
- Extended the preflight report with CFS `SAVE_CONFIG` pending state, the `auto_addr`-only warning, Creality `motor_control_wrapper` ready-callback evidence and `buf_len = 0x...` noise counts.

## v5.2.13-fixed changes made here

- Audited the full helper menu for this live K2 Pro Combo shape: model F012, board CR0CN200400C10, 300 mm class bed, CFS/Box present, local Fluidd/Mainsail/Camera helper already installed.
- Added `scripts/menu_audit_k2pro.sh`, menu item 32 and `helper.sh --menu-audit` for repeatable read-only menu-fit reporting on the printer.
- Fixed the remove menu so placeholder modules from the install menu also have matching remove entries: OctoEverywhere, Mobileraker and Git Backup.
- Relabeled not-implemented placeholder modules and network/system package modules so they are not presented as normal green safe installs.
- Added CFS `auto_addr` protection around helper-added `SAVE_CONFIG` calls in Useful Macros, Improved Shapers and the expert-only Z-Offset module.
- Added CFS-connected guards to M600/FILAMENT_LOAD/FILAMENT_UNLOAD so direct manual extrusion is blocked when CFS/Box is present; no force bypass is kept for CFS/Box.

## v5.2.14-fixed changes made here

- Fixed a follow-up issue discovered during live verification: `scripts/health.sh` used `python3 -m py_compile`, which created `.pyc` files in `/mnt/UDISK/helper-script`.
- The health check now compiles Python helper files in memory and leaves the helper directory cache-free after checks.


## v5.2.15-reviewed notes

Review result for `Creality-Helper-Script-K2-Pro-Combo-firmware-aware-v5.2.14-fixed.zip`:

- Shell syntax check passed for all `.sh` files.
- Python helper files compile successfully.
- Expert-locked modules remain protected: Z-Offset, KAMP and HelixScreen.
- No active K2 Plus 350/370/380 movement coordinates were found.
- Menu item 32 (`menu_audit_k2pro.sh`) is read-only and useful before installing optional modules.
- OctoEverywhere, Mobileraker and Git Backup are still placeholders in this package; selecting them does not install a working integration.
- v5.2.15 only applies small robustness fixes to camera IP detection/removal and Moonraker log wording.

## v5.2.16-fixed changes made here

- Removed accidental `__pycache__`/`.pyc` files from the reviewed release package.
- Kept the v5.2.15 camera IP fallback, camera removal cleanup and generic Moonraker startup wording.
- Updated helper, preflight and documentation labels to `v5.2.16-fixed`.

## v5.2.20-fixed changes made here

- Compared the package with sw3defy's current K2 Plus helper and MasterLufier's K2 Plus custom macros.
- Ported only the safe Moonraker `queue_gcode_uploads` metadata-race fix, with a timestamped backup under `printer_data/backups/k2pro_helper/moonraker_queue`.
- Added health/preflight reporting for the active Moonraker startup config and stock `queue_gcode_uploads` value.
- Added `helper.sh --fix-moonraker-queue` and menu item 35.
- Fixed `system.sh` service-restart dispatch so `restart_moonraker force`, `restart_klipper force` and `restart_nginx force` actually pass the force argument to the restart function.
- Left K2 Plus `tool.cfg`, autorefill, mesh store and CFS load/unload rewrites out of the K2 Pro helper until they can be tested on F012 firmware and this exact CFS path.

## v5.2.21-fixed changes made here

- Added a dedicated read-only CFS command/log safety scan based on the live CFS bus analysis: RS485 `/dev/ttyS5`, `serial_485`, `box_wrapper`, `auto_addr`, `motor_control` and the stock `M8200`/`CR_BOX_*` path.
- Added `scripts/cfs_safety_scan.sh`, menu item 36 and `helper.sh --cfs-safety-scan`.
- The scanner warns about custom configs or G-code files that contain raw/direct CFS commands such as `BOX_SEND_DATA`, direct `BOX_LOAD_MATERIAL`, direct `BOX_EXTRUDE_MATERIAL`, `_CFS_LOAD`, `_CFS_UNLOAD` or manual `M8200` sequences.
- Integrated the compact scanner summary into `health.sh cfs` and `preflight_k2pro.sh`.
- No printer CFS config was changed and no material movement command is introduced.

## v5.2.21.1-hotfix changes made here

- Tightened the first CFS scanner implementation after live testing on the printer.
- Compact/health mode now scans newest G-code files with limits so repeated `--health-cfs` checks do not hang on large uploads.
- Split recent Klipper log findings into real CFS error/timeout hits and lower-severity RS485 raw-frame/noise hits.
- Adjusted `health.sh cfs` so normal `#unknown`/`buf_len` bus chatter is not treated like a direct CFS command failure.

## v5.2.21.2-hotfix changes made here

- Fixed the menu audit to include the new CFS command/log safety scan menu item 36.
- Updated helper/preflight labels to `v5.2.21.2-hotfix`.

## v5.2.21.3-hotfix changes made here

- Improved `scripts/cfs_safety_scan.sh` output after full live runs showed that normal RS485 timeout/noise evidence can flood the report.
- Default scan now shows compact samples for timeout/noise sections and points to `--verbose` for full detail.
- `--compact` now emits only `CFS_SCAN_SUMMARY`, so preflight reports avoid duplicate headings.

## v5.2.21.7-hotfix changes made here

- Diagnosed the live Creality time-lapse path: the stock setting was enabled and `main_output.h264` was recorded, but the firmware did not render/copy it into `/mnt/UDISK/creality/userdata/delay_image/video/` or update `delay_image_info.json`.
- Added `creality_timelapse_recover.py`, which converts the stock H264 recording to MP4, creates a cover PNG, backs up and updates `delay_image_info.json`, and avoids movement/CFS/G-code macro changes.
- Added `scripts/creality_timelapse_recover.sh`, menu item 37, CLI status/recover entrypoints, and a boot-started `S99timelapse_recover` service.
- Extended `health.sh` and `menu_audit_k2pro.sh` so the new recover service is checked and listed.
- Live verification on the printer created and listed `1782826663.mp4` for `rerailer straight.stl_PLA_59m38s.gcode`; `health.sh timelapse` reported `OK: 5`, `WARN: 0`, `FAIL: 0`.

## v5.2.21.18-hotfix changes made here

- Installed and verified Entware on the live K2 Pro Combo, then extended `scripts/entware.sh` so the helper can reproduce that maintenance environment.
- Added the recommended package set used during live diagnostics: `bash`, `bc`, `xz`, `file`, `sqlite3-cli`, `jq`, `tree`, `diffutils`, `coreutils-stat`, `coreutils-timeout`, `nano`, `htop`, `git`, `curl` and `openssh-sftp-server`.
- Added `helper.sh --entware-status` and `helper.sh --entware-ensure` for non-interactive SSH checks and repair after firmware resets.
- Added `/etc/profile` PATH persistence and safer cleanup of Entware-created `/usr/bin` links on remove.
- Live test confirmed Klipper/Moonraker remained ready, Spoolman connected and the fault list empty after the Entware maintenance pack.


## v5.2.21.32-reviewed

M600 policy tightened after review: M600 is now named and guarded as **non-CFS only**. The installer refuses to install on K2 Pro Combo/CFS when Box indicators are found, and the generated Klipper macros block at runtime if `printer.box` exists. This avoids suggesting M600 as a normal or forceable workflow on CFS printers.
