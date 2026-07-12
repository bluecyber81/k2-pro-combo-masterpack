# Creality Helper Script - K2 Pro Combo v5.2.21.62-cfs-safe-tools build

## What changed in v5.2.21.62

- Makes the CFS material DB guard update-aware: official Creality profiles are fingerprinted and never replaced by the bundled custom patch.
- Preserves locally edited custom profiles and aborts without writes on custom ID/identity collisions or unknown JSON schemas.
- Creates a minimal custom-only `material_option.json` when that file is missing instead of restoring an old full vendor snapshot.
- Adds CFS Safe Tools: passive live CFS/Spoolman/RS485 status, compact event history, print-session tool-change statistics and stored G-code change-potential reports.
- Adds a lightweight boot service, helper menu/CLI, installed overview, dependency audit and health integration for CFS Safe Tools.
- Adds six isolated guard migration tests covering newer official databases, local edits, collisions, missing options, schema drift and fingerprint changes.
- No G-code, CFS/BOX command, serial write, cutter, heater, motor or filament movement path is included.

## What changed in v5.2.21.61

- Synchronizes the package version with the verified live v60 baseline and updates the Spoolman worker build label.
- Fixes the uninstalled-module audit so an active local Git Backup is reported as installed instead of available.
- Keeps generated Klipper `printer-YYYYMMDD_HHMMSS.cfg` and `printer.cfg.bak-*` files out of local Git snapshots while preserving the active `printer.cfg`.
- Keeps the Creality Moonraker/Klipper core pinned; no unsafe vanilla or beta core update is added.
- Validated for K2 Pro Combo firmware 1.1.6.3, CFS 1.4.2, Mainsail 2.18.2, Fluidd 1.37.2 and go2rtc 1.9.14.

## What changed in v5.2.21.57

- Full live audit against `192.168.178.74`: CFS/Box, Spoolman, Fluidd, Mainsail, go2rtc, Moonraker, helper syntax and material DB checks stayed healthy.
- Compresses repeated daemon log lines in the Spoolman CFS sync: state changes and warnings are still logged immediately; unchanged OK state is only repeated as a heartbeat.
- Promotes the known-good live Spoolman map to explicit `enabled=true` instead of relying on legacy "complete positive IDs" behavior.
- Leaves the CFS material database unchanged because the live IDs match; the only ambiguous ID is the intentional Generic/Sovol shared PLA-Silk-style ID and does not need repair.
- Keeps the same normal package boundary: no raw CFS expert-control commands, no direct Moonraker G-code sender, no one-shot full-stack installer.

## What changed in v5.2.21.56

- Live-checked against `192.168.178.74` via Moonraker API: printer ready, Klippy ready, CFS/Box connected, Spoolman connected, Fluidd/Mainsail/go2rtc reachable.
- Fixes the Spoolman CFS map logic so real Spoolman IDs `1-4` are no longer blocked as demo placeholders.
- Keeps existing legacy CFS maps active when all T1A/T1B/T1C/T1D IDs are positive, even if the older map has no `enabled` field.
- Starts helper Python workers with `python3 -B` / `PYTHONDONTWRITEBYTECODE=1` and removes the `nohup` dependency from the Spoolman service, matching the live OpenWrt toolset.
- Corrects the Spoolman CFS sync User-Agent/version marker from the imported v54 value to this build.
- Keeps the normal package shape: no raw CFS expert-control commands, no direct Moonraker G-code sender, no one-shot full-stack installer.

## What changed in v5.2.21.55

- Builds from the last normal printer package and pulls in the useful v5.2.21.54 improvements without the raw G-code / CFS expert-control paths.
- Adds Spoolman CFS service management and slot-map workflow:
  - `helper.sh --spoolman-cfs-status`
  - `helper.sh --spoolman-cfs-install`
  - `helper.sh --spoolman-cfs-map-wizard`
  - `helper.sh --spoolman-cfs-sync-once`
- Removes the shipped active `spoolman_cfs_map.json`; the package now ships only `spoolman_cfs_map.example.json` and creates a real active map through the wizard.
- Upgrades M600 handling: on K2 Pro Combo/CFS it installs a pause/park bridge instead of direct CFS load/unload/extrude commands.
- Adds explicit Nozzle-AI recover/standby commands while keeping boot behavior status-only.
- Updates health, status, preflight, dependency audit and CFS safety scan logic from the newer package.
- Does not include `cfs_expert_control.sh`, raw Moonraker G-code sending, `--full-stack` or `--experimental-stack`.

## What changed in v5.2.21.50

- Added a read-only Nozzle AI camera USB/UVC diagnostic path based on the K2 Pro stock camera behavior learned from live tests and community reports.
- New CLI: `helper.sh --nozzle-camera-diagnose` prints Creality camera status, `/dev/video*` mapping, `/etc/hotplug.d/usb/60-v4l`, `udevadm`/sysfs identity data and recent UVC/BIND/nozzle-camera log evidence.
- The new status/preflight/health output keeps the stock Creality on-demand behavior: an idle/offline nozzle AI camera is not treated as a hard failure unless AI/flow/first-layer calibration actually fails.
- The menu audit now calls out that Creality Print app camera problems after firmware updates can be app/firmware compatibility when Fluidd/Mainsail/go2rtc still work.

## What changed in v5.2.21.49

- Fixed Creality Timelapse Recover when a new `main_output.h264` is paired with stale display-log metadata from an older print.
- The recover daemon now rejects stale print IDs that do not match the raw file timestamp, uses a valid fallback timestamp ID, and avoids marking new captures as already processed just because an older ID exists.

## What changed in v5.2.21.48

- Restores the Spoolman CFS sync worker and slot-map files into the reviewed package so an installed service cannot be left without its executable.
- Dependency and health audits now catch missing Spoolman worker/map files and report Moonraker Spoolman connectivity plus the active spool.

## What changed in v5.2.21.47

- Replaced the three remaining advanced placeholders with K2-Pro-appropriate behavior:
  - `Git Backup lokal` now creates local Git snapshots of `/mnt/UDISK/printer_data/config` and can optionally use a manually configured remote later.
  - `OctoEverywhere` now shows status and can start the official OctoEverywhere installer only after explicit interactive confirmation.
  - `Mobileraker` now shows the correct app/Moonraker URLs and explains that Mobileraker Companion belongs on a Raspberry Pi/Debian host rather than being silently installed on the printer firmware.
- Updated status, dependency audit, menu audit and uninstalled-module audit so these entries no longer appear as unfinished placeholders.
- Added CLI helpers: `--git-backup`, `--git-backup-status`, `--octoeverywhere-status` and `--mobileraker-status`.
- No firmware flash, print start, movement, heating, CFS load/unload/extrude/refresh command or blind cloud login behavior was added.


## What changed in v5.2.21.46

- Local clean review package: removed shipped runtime state files (`.installed`, `.creality_timelapse_recover_state.json`), sanitized the CFS patch metadata path, fixed the expert prompt newline, and narrowed camera stop handling to helper-owned processes.
- Added `helper.sh --version` for quick package identification without starting the interactive menu.
- Made Entware `ensure` safe: it now refuses to patch `rc.local`, PATH or SFTP symlinks when Entware/opkg is not installed yet.
- Routed direct CFS DB install/repair CLI calls and the maintenance-menu CFS DB repair through the same K2 Pro compatibility guard used by normal installs.
- Prevented broken SFTP symlinks by linking Entware's `sftp-server` only when the target binary exists.
- Extended normal backups with the CFS material database snapshot and the helper `.installed` marker, so Combo/CFS recovery information is preserved.
- Added an automatic pre-restore backup of the current config before an interactive restore overwrites anything, stored separately so it cannot be picked accidentally as a normal full restore backup.
- Tightened backup/restore exit codes and copy checks so failed backup, corrupt restore or failed config copy are reported as command failures.
- Made the compact CFS protocol report return a partial/unavailable status when Moonraker live CFS data cannot be read, avoiding false OK summaries.
- Fixed the deep file audit's broken-symlink counter so symlink failures affect the final FAIL count and exit status.
- Made the dependency audit return a non-zero exit code when required dependencies are missing.
- Switched helper/menu warning output from `echo -e` to portable `printf`, so colors/status lines do not show stray `-e` on shells that do not support that echo option.

## What changed in v5.2.21.45

- Repacked the ZIP with Unix executable permissions for `helper.sh`, all helper scripts, Python entry points and the bundled `go2rtc` binary.
- Added the missing shebang and a clearer `python3` prerequisite error to `scripts/cfs_protocol_report.sh`.
- Fixed the CFS protocol report so empty/unused CFS slots are not counted as missing material-database IDs.
- Fixed the CFS material DB health probe to ignore empty `-1` live slot IDs.
- Updated the deep file/script audit so Python syntax checks compile in memory and no longer create `.pyc`/`__pycache__` artifacts.
- Fixed the deep audit exit status so FAIL results are reflected in the command return code while still writing the report.
- Updated the Moonraker webcam compatibility check to compile patched Python in memory instead of leaving bytecode cache files behind.
- Extended helper/dependency/deep audits to include the bundled `S98nozzle_camera_recover` init helper.
- Cleaned the README install section and clarified that this reviewed ZIP contains the `go2rtc` runtime binary.

## What changed in v5.2.21.44

- Cleans up the interactive menu for K2 Pro Combo use: first-run checks, status, install/repair, maintenance, restore/remove and advanced tests are separated more clearly.
- Makes backup restore visible in the restore/remove menu instead of leaving it as a hidden handler.
- Removes the confusing duplicate `Spoolman/CFS Sync` install entry that pointed to the Moonraker extension installer. Spoolman/CFS state remains visible in the installed-status overview.
- Adds Dependency Audit and Deep File/Script Audit directly to the first-run and status menus, so the thorough checks are easy to run.
- Adds visible status entries for Creality Timelapse Recover and Entware.
- Lets `helper.sh --help` print usage without requiring root or an interactive terminal.
- Keeps the K2 Pro safety policy unchanged: M600 only without CFS/Box, HelixScreen test-only, Z-Offset locked behind Expert-Unlock, CFS diagnostics read-only.

## What changed in v5.2.21.43

- Refines the deep file audit after live testing: Creality GUI event streams and inactive init-script backups are informational, not active failures.
- Keeps the audit read-only and report-backed.

## What changed in v5.2.21.42

- Adds `scripts/deep_file_audit_k2pro.sh` and `helper.sh --deep-file-audit` for a broad read-only audit of helper scripts, init scripts, Python files, JSON/config data, Klipper includes, executable bits, symlinks, Nginx syntax and recent severe logs.
- Classifies Creality encrypted/user-private files, GUI event-stream files and inactive init-script backups correctly instead of reporting them as active failures.
- Writes timestamped reports to `/mnt/UDISK/helper-script/reports/`.

## What changed in v5.2.21.41

- Makes `helper.sh --restart-camera` restore the executable bit on `go2rtc` before restarting the service, protecting against ZIP/copy/restore permission loss.
- Adds an explicit health check for the `go2rtc` executable bit so camera permission drift is reported directly.

## What changed in v5.2.21.40

- Adds a compatibility fix for Mainsail 2.18+ on Creality's bundled Moonraker webcam API: the `K2 Camera` entry now reports `enabled=true`, `mdiWebcam`, idle FPS, aspect ratio and extra data defaults.
- Makes the camera health check fail if the Mainsail-required webcam enable flag disappears again.
- Keeps the fix small and reversible: the original Moonraker `webcam.py` is backed up before patching.

## What changed in v5.2.21.39

- Confirms and documents that Mainsail `v2.18.2` is current for this printer install.
- Extends camera health with real Mainsail camera checks: direct go2rtc frame, Fluidd proxy frame, Mainsail proxy frame, and the Mainsail WebRTC stream page.
- Verifies the Moonraker webcam entry for `K2 Camera`: `webrtc-go2rtc`, `k2camera` stream/snapshot URLs, and target FPS.
- Keeps Mainsail on the official Moonraker webcam API path and removes the old brittle Mainsail Vue-store index injection from future camera repairs.
- Improves `mainsail.sh status` so it reads `.version` / `release_info.json`, matching current Mainsail release packages.
- Adds a Mainsail dashboard database check that the webcam and Spoolman panels are visible for K2 Pro Combo use.

## What changed in v5.2.21.38

- Adds `scripts/cfs_protocol_report.sh`, a read-only CFS protocol/slot/database report based on the live K2 Pro RS485/CFS model.
- Adds menu and CLI entry `helper.sh --cfs-protocol-report` / `helper.sh --cfs-protocol`.
- The report maps live `T1A..T1D` slot IDs to database profiles, shows blank live labels that are still backed by a valid DB profile, and documents the safe/unsafe CFS command policy.
- Health and Preflight now include a compact CFS protocol summary, without sending `BOX_INFO_REFRESH`, `BOX_SEND_DATA`, load, unload, cut, extrude or refresh commands.
- Adds `docs/CFS_COMMUNICATION_READONLY_2026-07-06.md` so the CFS communication findings survive a later restore or firmware reset.

## What changed in v5.2.21.37

- Adds `scripts/cfs_db_guard.py` and `scripts/cfs_db_guard.sh` to keep the two local CFS custom material profiles durable after a full power-cycle.
- The guard is deliberately narrow and read-only with respect to the CFS bus: it never sends BOX/CFS load, unload, extrude, refresh or movement commands. It only validates JSON, backs up the current database, and merges the helper's known custom profiles if Creality prunes them during boot.
- Adds menu/CLI entries: `helper.sh --cfs-db-guard`, `helper.sh --cfs-db-repair`, and `helper.sh --cfs-db-guard-status`.
- Healthcheck now verifies that the CFS material DB guard service, script and patch snapshot exist when the feature is installed.
- Keeps Creality's official database entries instead of replacing the whole database blindly, so future official material database changes are less likely to be overwritten.

## What changed in v5.2.21.36

- Adds a read-only CFS material database integrity check to `scripts/health.sh`.
- The health report now validates the core CFS JSON files, catches a missing `material_option.json`, and warns if a live CFS slot uses a material ID that is no longer present in `material_database.json`.
- Documents the observed K2 Pro Combo case where Creality kept live `T1D` as Sovol `PLA Steel Blue` / `090002`, but pruned the matching user material profile from the selectable material database after a restart.
- Treats HelixScreen's optional `server.helix.status` / HelixPrint plugin probe as harmless Moonraker log noise when the HelixPrint plugin is not installed.
- Records the live finding that `BOX_INFO_REFRESH` can call `BOX_SET_PRE_LOADING` without required parameters on this K2 Pro firmware and trigger `key60`; helper diagnostics must keep CFS refresh/status checks read-only through Moonraker objects instead.

## What changed in v5.2.21.35

- Fixes the dependency audit Python syntax check so it compiles helper Python files in memory instead of creating `.pyc` files.
- The reviewed ZIP now includes the `go2rtc` runtime binary and preserves/restores its executable bit. The camera module still repairs the executable bit if a copy/extract step loses it.
- Removes generated `.pyc` files left by the earlier dependency-audit run on the printer.

## What changed in v5.2.21.34

- Clarifies the current KAMP policy: an already detected/tested KAMP-K2 setup is handled as repair/reinstall with backup, while a fresh KAMP install remains an Expert test.
- Updates the direct `kamp.sh` guard text so it no longer sounds like the tested repair path is forbidden.
- Keeps the M600 policy from v5.2.21.33 unchanged: M600 is only for printers without CFS/Box.

## What changed in v5.2.21.33

- Keeps the updated M600 policy: M600 is only for printers without CFS/Box.
- Removes confusing old force-bypass wording from the current reviewed notes. On K2 Pro Combo with CFS, use Creality/CFS, the display filament workflow and slicer tool changes instead of M600.
- Removes generated `__pycache__`/`.pyc` files from the cleaned reviewed package.

This is a guarded K2 Pro Combo adaptation of the K2 Plus helper script.

## What changed in v5.2.21.17

- Refines the CFS health summary while a print is active: high `Serial_485 #unknown` / raw-frame noise is now reported as OK when no severe CFS errors and no excessive timeout count are paired with it. This avoids a false warning during normal Creality CFS polling while printing.

## What changed in v5.2.21.16

- Reduces Creality timelapse recover log noise: idle `no raw Creality timelapse file found` is logged once per idle state, not every 30 seconds.
- Treats a missing local copy of the current firmware image on UDISK as informational when the installed runtime firmware is current.
- No security, firewall, SSH, router or internet-exposure changes are included.

## What changed in v5.2.21.15

- Reverts the v5.2.21.14 go2rtc API/RTSP localhost binding because this build should not apply security hardening.
- Keeps the functional camera improvement: idle-safe watchdog checks no longer open hanging `frame.jpeg` snapshot consumers on the Creality WebRTC source.
- Keeps the WebRTC printer LAN-IP candidate and shorter read-only health retries.

## What changed in v5.2.21.14

- Makes the direct Creality go2rtc camera path idle-safe: the watchdog no longer opens hanging `frame.jpeg` snapshot consumers on the WebRTC source.
- Previously bound go2rtc API and RTSP to `127.0.0.1`; v5.2.21.15 intentionally reverts that security hardening.
- Uses the printer LAN IP as the WebRTC candidate so browser playback is not advertised as `127.0.0.1`.
- Shortens slow health retries so a read-only helper health check no longer blocks for about a minute on transient CFS reconnect states.

## What changed in v5.2.21.13

- Treats nozzle AI camera standby as informational health output instead of a warning.
- This keeps the expected Creality on-demand camera behavior visible without making the overall health summary look degraded.
- Root-level old helper packages can be archived separately without deleting rollback material.

## What changed in v5.2.21.12

- Keeps the K2 Pro nozzle AI camera recovery helper, but no longer forces the nozzle camera on at boot.
- `S98nozzle_camera_recover boot` is now status/log only so Creality can keep the nozzle camera under on-demand control.
- Adds `standby`/`off` support to park the nozzle AI camera with Creality's stock `/usr/bin/nozzle_cam_power.sh off`.
- Health treats an offline nozzle AI camera as a standby/on-demand warning instead of a hard failure; use recovery only if AI/flow/first-layer calibration fails to wake it.

## What changed in v5.2.21.11

- Adds a K2 Pro nozzle AI camera recovery helper using Creality's stock `/usr/bin/nozzle_cam_power.sh`.
- Health now checks the stock Creality nozzle AI camera path: `camera_sub online=1`, `/dev/v4l/by-id/sub-video2` and `/dev/video2`.
- Live recovery restored the nozzle camera from `camera_sub online=0` to `camera_sub online=1`, with `sub-video2 -> /dev/video2` and `cam_sub_app` running.

## What changed in v5.2.21.10

- Camera watchdog now validates direct go2rtc mode by probing real `frame.jpeg` output instead of relying on optional `bytes_recv` counters that are absent in the Creality direct WebRTC producer response.
- This prevents repeated false `Stream stale - reconnecting...` loops after reboot while keeping reconnect behavior for missing producers or failed JPEG probes.
- Live reboot verification on the K2 Pro Combo passed with `go2rtc=1`, `k2rtc=0`, `watchdog=1`, working Fluidd/Mainsail frames and full helper health `OK:49 WARN:0 FAIL:0`.

## What changed in v5.2.21.9

- Timelapse Recover now suppresses repeated `already listed` log/write cycles for the same raw Creality H264 source after it has recorded the matching state once.
- The Health check now waits through the short Creality CFS/RS485 reconnect window before declaring BOX/CFS disconnected.
- Keeps the existing stock Creality `delay_image` recovery behavior, MP4/cover generation, and no-movement/no-CFS-macro safety model.

## What changed in v5.2.21.8

- Camera support now uses go2rtc's native Creality WebRTC format directly:
  `webrtc:http://127.0.0.1:8000/call/webrtc_local#format=creality`.
- The runtime camera service no longer starts the intermediate `k2rtc.py` bridge.
- The camera healthcheck accepts this direct mode and expects `go2rtc=1`, `k2rtc=0`, `watchdog=1`.
- This matches the live-tested K2 Pro firmware `1.1.6.3` setup and reduces one Python process from the camera path.

## What changed in v5

The uploaded firmware image `CR0CN200400C10_R_202605061516_ota_img_V1.1.5.5.img` was inspected.
Important firmware mapping from `/etc/init.d/hostname`:

- `F008` = K2Plus
- `F012` = K2Pro
- `F021` = K2
- `F025` = M300
- `GS-04` = GS04
- `Z2` = Z2

For K2 Pro Combo this script expects:

- model: `F012`
- board: `CR0CN200400C10`
- printer size: `300*300*300`

The script now warns if the printer reports a different model/board or if 300x300x300 is not detected.

## Safe order

1. Run `K2 Pro Preflight report`
2. Run `Backup Klipper config + important system files`
3. Test only one module at a time
4. Restart Klipper and inspect logs after every change

## Risk and test modules remain visible but guarded

These modules remain in the package but are guarded:

- Save Z-Offset Macros
- HelixScreen
- KAMP Adaptive Meshing: fresh install is Expert-only; if KAMP is already detected on this printer, the helper offers repair/reinstall after backup.

Fresh risky installs require the Expert Unlock file and the exact phrase:

```text
ICH VERSTEHE K2 PRO RISIKO
```

Unlock:

```sh
touch /mnt/UDISK/helper-script/.expert_unlock_k2pro
```

Lock again:

```sh
rm -f /mnt/UDISK/helper-script/.expert_unlock_k2pro
```

In this package, the direct module scripts also guard risky installs. The helper menu passes the internal override only after the unlock file, an existing backup, and the exact risk phrase are present, except for the tested KAMP repair/reinstall path where KAMP is already detected and a backup exists. Remove actions remain available without the override.

v5.2 additionally patches Moonraker through `/etc/init.d/moonraker` when present. The firmware image shows `/etc/rc.d/S56moonraker` is a symlink, so patching the real init script avoids replacing the symlink during `sed -i`.

## Install

Copy this folder to:

```sh
/mnt/UDISK/helper-script
```

Then run:

```sh
chmod +x /mnt/UDISK/helper-script/helper.sh /mnt/UDISK/helper-script/go2rtc
chmod +x /mnt/UDISK/helper-script/scripts/*.sh /mnt/UDISK/helper-script/scripts/S98nozzle_camera_recover
chmod +x /mnt/UDISK/helper-script/*.py /mnt/UDISK/helper-script/scripts/*.py 2>/dev/null || true
sh /mnt/UDISK/helper-script/helper.sh
```

## Strong warning

Do not use K2 Plus / F008 configs or 350x350x350 movement macros on K2 Pro/F012. K2 Pro is 300x300x300.


## v5.2.3 review-fix

This reviewed build keeps the v5.2 behaviour, but adds extra safety before the Camera Support module changes nginx/Fluidd/Mainsail files:

- backs up `/etc/nginx/nginx.conf` through the helper backup function
- backs up `/etc/rc.local`
- backs up `/usr/share/fluidd/index.html`
- backs up `/usr/share/mainsail/index.html` when present
- rewrites the camera reboot confirmation with an explicit `if` block
- fixes the v5.2.1 backup order so `/etc/rc.local` is backed up before it is modified
- fixes broken Entware Python snippets that edited `/etc/rc.local`
- writes Entware PATH entries as `"$PATH"` correctly, without escaping the dollar sign
- downloads the Entware installer to a file before running it instead of piping `wget` into `sh`
- blocks install menu entries unless K2 Pro model/board/300x300x300 compatibility and a helper backup are present

No extra risky modules were unlocked. Z-Offset, KAMP and HelixScreen remain Expert-Unlock only.

## v5.2.4 camera and update-manager fix

- repairs the Camera Support module so it starts `/etc/rc.d/S99camera restart` immediately after install instead of requiring a reboot
- restores or downloads the missing `go2rtc` binary before starting the camera bridge
- changes the boot entry to `S99camera boot`, which keeps the 60 second boot delay but avoids delaying manual restarts
- makes the nginx go2rtc patch idempotent: existing broken `/go2rtc` blocks are removed and recreated on ports 4408 and 4409, then validated with `nginx -t`
- uses the nginx helper for removal too, instead of broad regex deletion
- makes the Fluidd keepalive iframe use the same-origin `/go2rtc/` proxy
- registers the camera as `mjpegstreamer-adaptive` with direct go2rtc `:1984` `frame.jpeg` URLs, which avoids the stock Creality web server on port 80 and is more reliable in Fluidd and Mainsail than forcing WebRTC in the dashboard
- adds the actual Moonraker `[update_manager]` section that was missing in v5.2.3
- disables Moonraker system package updates by default for this firmware
- creates the missing `/usr/share/scripts` compatibility stubs required by this firmware's bundled Moonraker update_manager

## v5.2.5 full hardening pass

- removes `eval` from backup restore selection and rejects unsafe tar paths before extracting backups
- makes feature tracking and printer.cfg include removal use exact line matching instead of broad regexes
- improves Moonraker section removal with a line-based parser and better remove behavior if the wrapper config is already missing
- makes Klipper, Moonraker and nginx restart helpers return non-zero on failed restarts
- validates Fluidd and Mainsail nginx edits with `nginx -t`
- hardens Fluidd, Mainsail, KAMP, Timelapse, Entware and HelixScreen download/install paths
- prevents KAMP from creating a duplicate `[file_manager]` section in `moonraker.conf`
- makes M600 pause through `PAUSE_BASE` only when that command exists, otherwise falls back to `PAUSE`
- removes the `less` dependency from log viewing in the helper menu

## v5.2.6 live-audit hardening

- adds `scripts/health.sh` with non-destructive checks for helper files, shell syntax, Python helper compile, camera, Moonraker, CFS/BOX, logs and disk space
- adds helper menu entries:
  - `28) Camera health check`
  - `29) CFS/BOX diagnosis`
  - `30) Full helper health check`
  - `31) Restart helper camera bridge`
- hardens `S99camera` with PID files under `/tmp/k2camera`
- makes camera stop/restart remove stale `go2rtc`, `k2rtc.py` and `camera_watchdog.py` processes before starting new ones
- adds `S99camera health` for local stream and frame checks
- changes `system.sh restart_camera` to restart the helper camera bridge (`S99camera`) when it is installed
- updates the packaged `camera_watchdog.py` template to match the generated stale-stream detection logic
- removes the confusing static LAN IP from the packaged `go2rtc.yaml` template; `camera.sh` still writes the real printer IP during install
- expands the preflight report with helper version, installed features, live CFS/BOX state and camera service status
- adds an explicit menu warning not to update Creality Klipper/Moonraker core from the Fluidd/Mainsail update manager

The update-manager endpoint may still show Git validation warnings on Creality firmware.
That is expected for the vendor zip tree and should not be treated as a request
to update core Klipper/Moonraker through Fluidd or Mainsail.

## v5.2.7 CFS live-test safety update

- keeps CFS/BOX diagnosis read-only and explicitly states that it does not load, unload, extrude or move filament
- warns that the official `BOX_LOAD_MATERIAL` path calls `BOX_EXTRUDE_MATERIAL`
- records the live finding that direct `BOX_LOAD_MATERIAL TNN=T1A` caused `key60` / `Internal error on command:BOX_EXTRUDE_MATERIAL` and Klipper shutdown on this K2 Pro Combo
- detects recent `key60`, `BOX_EXTRUDE_MATERIAL` and `BOX_LOAD_MATERIAL_EXTRUDE_MATERIAL` evidence in `klippy.log`
- adds the same CFS direct-load safety note to the preflight report

## v5.2.8 non-interactive safety update

- adds real CLI entrypoints: `--health`, `--health-camera`, `--health-cfs`, `--preflight`, `--backup`, `--show-installed`, `--restart-camera`
- blocks the interactive menu when stdin is not a TTY, so SSH/batch calls cannot fall into menu prompts
- fixes the unsafe `helper.sh --health` behavior where an unsupported argument could leave a menu process waiting in a non-interactive SSH session

## v5.2.9 health-check polish

- makes the health-check process counter robust when a short-lived `/proc/.../cmdline` disappears during scanning
- updates the preflight report header to the current helper version

## v5.2.10 CFS auto_addr safety update

- detects the Creality CFS state where only `auto_addr` is pending and warns not to run `SAVE_CONFIG` just for that state
- documents the observed Creality `motor_control_wrapper` ready-callback bug after saving only `auto_addr`
- counts all `buf_len = 0x...` log noise, not only `buf_len = 0x0`

## v5.2.11-reviewed notes

- Reviewed `v5.2.10-fixed` package.
- Shell syntax check passed for all `.sh` files and Python helper files compile successfully.
- Added a safer `/etc/rc.local` handling path in the camera module: it now creates a minimal `rc.local` if missing and removes camera startup entries without failing if the file is absent.
- Made nginx backup handling quieter/safer when `/etc/nginx/nginx.conf` is missing.
- Camera health check now warns instead of failing when Camera Support was never installed; it still fails if `camera_support` is marked installed but `S99camera` is missing.
- Risk modules remain present but Expert-Unlock only: Z-Offset, KAMP, HelixScreen.

## v5.2.12-fixed notes

- Fixed stale package labels from v5.2.10/v5.2.11-reviewed to the current build name.
- Removed Python `__pycache__`/`.pyc` release artifacts from the final package.
- Made Camera Support skip Fluidd index injection/removal cleanly if `/usr/share/fluidd/index.html` is missing, matching the optional Mainsail handling.
- Extended the preflight report with `SAVE_CONFIG` pending state, `auto_addr`-only warning, `motor_control_wrapper` ready-callback detection and generic `buf_len = 0x...` log-noise counts.

## v5.2.13-fixed menu and printer-fit update

- Adds a read-only `K2 Pro menu suitability audit` menu item and `--menu-audit` CLI entrypoint.
- Reviews all menu entries against K2 Pro Combo expectations: local-safe, caution, placeholder, or blocked expert-only.
- Adds missing remove-menu entries for OctoEverywhere, Mobileraker and Git Backup placeholders.
- Clarifies that OctoEverywhere, Mobileraker and Git Backup are placeholders/not implemented for K2 Series in this helper.
- Adds explicit router/Fritzbox/WAN non-goal text; local Fluidd/Mainsail/nginx services remain local printer services.
- Makes helper-added `SAVE_CONFIG` macros block saving when CFS `auto_addr` is pending.
- Makes M600/FILAMENT_LOAD/FILAMENT_UNLOAD non-CFS-only: installation is blocked when CFS/Box config is detected; runtime macros also block if `printer.box` exists. No force bypass is kept for CFS/Box.

## v5.2.14-fixed health-check cleanup

- Changes the helper health Python syntax check to compile in memory instead of running `python3 -m py_compile`, so health checks no longer create `.pyc` files on the printer.


## v5.2.15-reviewed changes

This reviewed build keeps the v5.2.14 safety model and adds small robustness fixes:

- Camera install now detects the printer IP with fallback logic (`ip route get 1`, then `hostname -I`, then `127.0.0.1`) instead of assuming the default-route command always succeeds.
- Fluidd camera HTML injection no longer aborts if the IP route command is unavailable, because that injected script does not need the IP value.
- Camera removal can clean up `S99camera` even if `.installed` lost the `camera_support` marker.
- Moonraker startup log wording was made generic for `/etc/init.d/moonraker` and `/etc/rc.d/S56moonraker`.

## v5.2.16-fixed cleanup

- Repacked the v5.2.15-reviewed improvements without release `__pycache__`/`.pyc` artifacts.
- Updated helper/preflight/package labels to the fixed build name.

## v5.2.20-fixed upstream sync and G-code preview fix

- Reviewed the current sw3defy K2 Plus helper and MasterLufier K2 Plus custom macro sources before porting more behavior to K2 Pro.
- Adds a backed-up Moonraker `queue_gcode_uploads: True` repair path. This matches the upstream fix for Fluidd/Mainsail metadata races and directly addresses missing G-code preview/metadata symptoms.
- Adds `helper.sh --fix-moonraker-queue` and menu item `35) Fix Moonraker G-code preview queue`; both restart Moonraker after a successful config change.
- Extends `health.sh` and the K2 Pro preflight report to show whether Moonraker uses the UDISK wrapper and whether the active stock config still disables queued G-code uploads.
- Fixes the `system.sh restart_* force` entrypoints so non-interactive helper actions can restart services without falling back to a prompt.
- Does not import MasterLufier `tool.cfg`, CFS autorefill, K2 Plus bed-mesh storage, or CFS load/unload rewrites. Those sources are K2 Plus/F008 firmware-targeted, and this K2 Pro already has live evidence that direct BOX load/extrude paths can trigger shutdowns.

See `docs/UPSTREAM_SYNC_2026-06-30.md` for the source comparison notes.

## v5.2.21-fixed CFS bus safety scan

- Adds `scripts/cfs_safety_scan.sh`, a read-only scanner for risky CFS commands in custom configs, uploaded G-code files and recent Klipper logs.
- Adds menu item `36) CFS command/log safety scan` and `helper.sh --cfs-safety-scan`.
- Extends `health.sh cfs` and the preflight report with a compact CFS safety summary.
- Treats stock `box.cfg` as known Creality logic, but warns about custom/raw commands such as `BOX_SEND_DATA`, direct `BOX_LOAD_MATERIAL`, direct `BOX_EXTRUDE_MATERIAL`, `_CFS_LOAD`, `_CFS_UNLOAD` and manual `M8200` sequences outside the official workflow.
- Keeps the K2 Pro policy unchanged: diagnose CFS read-only, move material through display/Creality Print, and avoid direct CFS raw-bus or load/unload automation.

## v5.2.21.1-hotfix

- Makes the CFS safety scan faster in compact/health mode by scanning the newest G-code files with a per-file read limit.
- Separates real CFS error/timeout log hits from normal RS485 raw-frame/noise lines such as `#unknown` and `buf_len = 0x...`.
- Keeps full detail available through `helper.sh --cfs-safety-scan`, while `health.sh cfs` stays quick enough for repeated checks.

## v5.2.21.2-hotfix

- Updates the K2 Pro menu suitability audit so it includes menu item `36) CFS command/log safety scan`.
- Updates the audit recommendation to explicitly mention scanning CFS-related G-code before printing.

## v5.2.21.3-hotfix

- Makes `scripts/cfs_safety_scan.sh` quieter by default: timeout/noise sections now show a short sample and counts, with full output available through `--verbose`.
- Makes `--compact` output only the machine-readable `CFS_SCAN_SUMMARY`, which keeps preflight and health reports cleaner.

## v5.2.21.7-hotfix Creality timelapse recover

- Adds `creality_timelapse_recover.py` and `scripts/creality_timelapse_recover.sh`.
- Adds menu item `37) Creality Timelapse Recover`.
- Fixes the observed stock Creality time-lapse failure where `/mnt/UDISK/timelapse/main_output.h264` is recorded but no MP4, cover image or `delay_image_info.json` entry is created.
- Installs a small `S99timelapse_recover` watchdog that waits until the printer is idle, renders the raw H264 file to Creality's stock delay-image MP4 folder, creates a cover image and backs up `delay_image_info.json` before updating it.
- Extends `health.sh` with a `timelapse` mode and includes the recover service in full/helper health checks.


## v5.2.21.32-reviewed clarity/safety cleanup

- Fixes the stale preflight report label so it no longer reports v5.2.21.25.
- Renames placeholder entries in the advanced/remove menus to **nicht implementiert**, so they are not mistaken for working installers.
- Selecting OctoEverywhere, Mobileraker or Git Backup now shows the placeholder message directly instead of demanding a backup first.
- KAMP-K2 remains available, but a fresh install is treated as an Expert test. Only an already detected KAMP setup is offered as repair/reinstall from the normal install menu.
- No new movement, heating, CFS load/unload or security-hardening behavior was added.

## v5.2.21.30-hotfix Dependency audit polish

- Refines the dependency audit so embedded `wget` builds are not misclassified
  as warnings just because they do not support normal desktop `--help` or
  `--version` behavior.

## v5.2.21.29-hotfix Dependency audit

- Adds `helper.sh --dependency-audit` and an Advanced menu entry for a read-only dependency matrix.
- Checks required tools, optional maintenance tools, command versions, service files, ports, helper shell syntax and helper Python compilation without treating empty glob patterns as errors.
- Documents the current safe baseline: Creality Moonraker core is not blindly updated, Moonraker Timelapse/M600/Z-Offset remain off by default, and HelixScreen remains test-only.

## v5.2.21.28-hotfix HelixScreen audit

- Adds a read-only HelixScreen audit as `helper.sh --helixscreen-audit` and an Advanced menu check.
- Updates the HelixScreen helper to use the current upstream HTTPS installer source if expert install is deliberately started later.
- Reclassifies HelixScreen as test-only for this K2 Pro Combo: upstream K2 Pro support exists, but stock display, CFS, AI/nozzle-camera, camera and Creality time-lapse workflows must be retested after any install.
- Fixes the visible helper menu header version.

## v5.2.21.27-hotfix CLI CRLF guard

- Hardens non-interactive CLI argument parsing against Windows CRLF endings when commands are sent through tools such as PuTTY/plink.
- Keeps options like `--uninstalled-audit` working even when launched from PowerShell through `sh -s`.

## v5.2.21.26-hotfix uninstalled-module audit

- Adds `helper.sh --uninstalled-audit` and an advanced menu entry to check modules that are intentionally not installed.
- Documents why Moonraker Timelapse, M600, Z-Offset, HelixScreen and placeholder modules are not better as default installs on this K2 Pro Combo.
- Keeps the check read-only: no install, flash, heat, move or restart.

## v5.2.21.25-hotfix reviewed ZIP follow-up

- Incorporates the reviewed M600 detection logic so `helper.sh --status` only detects M600 when `m600.cfg` or its printer.cfg include is present.
- Updates the preflight report version label to the current helper generation.

## v5.2.21.24-hotfix audit/test cleanup

- Fixes `system.sh` so it only dispatches CLI commands when executed directly, not when sourced by scripts such as Entware or Timelapse status.
- Updates the K2 Pro menu audit for the current first-run menu, tested KAMP-K2 state and non-CFS-only M600 handling.
- Leaves placeholder modules visible only as advanced/not implemented entries.

## v5.2.21.23-hotfix first-run checklist

- Adds a dedicated first-run menu with the intended order: printer suitability check, backup, installed overview, full health, CFS/BOX, camera, Fluidd/Mainsail, firmware/system and menu audit.
- Moves M600 out of normal install flow because CFS/Box printers should use Creality/CFS and slicer filament-change workflows by default.
- Keeps M600 as a visible notice/install path, but the actual installer refuses to install when CFS/Box is detected. It is only for non-CFS manual single-filament printers.

## v5.2.21.22-hotfix menu cleanup

- Reworks the interactive helper into clearer submenus: Status & Gesundheit, Installieren/Reparieren, Wartung/Logs, Entfernen/Wiederherstellen and Erweitert/Tests.
- Moves the live-tested KAMP-K2 adaptive mesh option out of the locked risk section and into the install/repair menu.
- Keeps untested high-impact UI/offset features in the advanced section while reducing backup friction for already installed/marked modules.
- Adds KAMP-K2 as an explicit module row in `helper.sh --status`.

## v5.2.21.21-hotfix KAMP status classification

- Fixes `helper.sh --status` after KAMP tests so it reads only Moonraker's `save_config_pending_items`.
- Avoids a false `bed_mesh` warning when the normal loaded config contains `bed_mesh default` but the actual pending item is only Creality CFS `auto_addr`.

## v5.2.21.20-hotfix KAMP test follow-up

- Extends `helper.sh --status` with a SAVE_CONFIG pending check.
- Warns explicitly when KAMP/adaptive meshing leaves `bed_mesh default` pending so it is not saved accidentally.
- Treats Creality CFS `auto_addr` pending as informational, because it is normal on this firmware and should not be saved just because it appears.

## v5.2.21.19-hotfix menu/status cleanup

- Adds a richer installed-module overview through menu item `3` and CLI commands `helper.sh --status` / `helper.sh --installed-status`.
- The overview combines the helper `.installed` marker with visible file/service evidence for Moonraker, Fluidd, Mainsail, Camera Support, Fans, Useful Macros, Shapers, Timelapse Recover, Spoolman CFS Sync, Entware, Moonraker Timelapse and M600.
- Cleans up the main menu into clearer groups: status/safe first steps, install/repair after backup, diagnostics/service tools and risk modules locked by default.
- Keeps the raw installed marker list available inside the new overview and through `helper.sh --show-installed`.

## v5.2.21.18-hotfix Entware maintenance pack

- Extends Entware package handling with the live K2 Pro maintenance set: `bash`, `bc`, `xz`, `file`, `sqlite3-cli`, `jq`, `tree`, `diffutils`, `coreutils-stat`, `coreutils-timeout`, plus the base tools `nano`, `htop`, `git`, `curl` and `openssh-sftp-server`.
- Adds stable `/usr/bin` links for installed Entware tools where Creality scripts and SSH sessions commonly expect them.
- Persists Entware PATH in `/etc/profile` as well as `/etc/rc.local`.
- Adds non-interactive helper commands: `helper.sh --entware-status` and `helper.sh --entware-ensure`.
- Improves Entware removal so Entware-created `/usr/bin` links and the `/etc/profile` PATH entry are cleaned up.


## v5.2.21.32-reviewed M600 CFS policy cleanup

- Renames M600 in the menu as **only for printers without CFS/Box**.
- Blocks `m600.sh install` when `box.cfg`, `[include box.cfg]`, `[box]`, or BOX_* macros are detected.
- Removes the earlier force-bypass wording for CFS/Box. On K2 Pro Combo, use Creality/CFS, display filament workflow and slicer tool changes instead of M600.
- Runtime `M600`, `FILAMENT_LOAD` and `FILAMENT_UNLOAD` now also block when `printer.box` exists.
