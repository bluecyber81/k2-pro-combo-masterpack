#!/bin/sh
# dependency_audit_k2pro.sh - read-only dependency and feature dependency audit
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

ok=0
warn=0
fail=0

row() {
    state="$1"
    name="$2"
    note="$3"
    case "$state" in
        OK) ok=$((ok + 1)) ;;
        WARN|INFO) warn=$((warn + 1)) ;;
        FAIL) fail=$((fail + 1)) ;;
    esac
    printf "%-5s %-30s %s\n" "$state" "$name" "$note"
}

cmd_path() {
    command -v "$1" 2>/dev/null
}

need_cmd() {
    p="$(cmd_path "$1")"
    if [ -n "$p" ]; then
        row OK "$1" "$p"
    else
        row FAIL "$1" "missing"
    fi
}

optional_cmd() {
    p="$(cmd_path "$1")"
    if [ -n "$p" ]; then
        row OK "$1" "$p"
    else
        row INFO "$1" "optional/missing"
    fi
}

file_row() {
    if [ -e "$2" ]; then
        row OK "$1" "$2"
    else
        row FAIL "$1" "missing: $2"
    fi
}

optional_file_row() {
    if [ -e "$2" ]; then
        row OK "$1" "$2"
    else
        row INFO "$1" "not installed: $2"
    fi
}

feature_file_row() {
    feature="$1"
    label="$2"
    path="$3"
    if is_installed "$feature"; then
        if [ -e "$path" ]; then
            row OK "$label" "$path"
        else
            row FAIL "$label" "marked installed but missing: $path"
        fi
    elif [ -e "$path" ]; then
        row INFO "$label" "detected but not marked: $path"
    else
        row INFO "$label" "not installed: $path"
    fi
}

feature_exec_row() {
    feature="$1"
    label="$2"
    path="$3"
    if is_installed "$feature"; then
        if [ -x "$path" ]; then
            row OK "$label" "$path"
        elif [ -e "$path" ]; then
            row FAIL "$label" "marked installed but not executable: $path"
        else
            row FAIL "$label" "marked installed but missing: $path"
        fi
    elif [ -x "$path" ]; then
        row INFO "$label" "detected/executable but not marked: $path"
    elif [ -e "$path" ]; then
        row WARN "$label" "detected but not executable: $path"
    else
        row INFO "$label" "not installed: $path"
    fi
}

feature_exec_any() {
    feature="$1"
    label="$2"
    shift 2
    found=""
    existing=""
    for path in "$@"; do
        [ -e "$path" ] && existing="$existing $path"
        [ -z "$found" ] && [ -x "$path" ] && found="$path"
    done
    if is_installed "$feature"; then
        if [ -n "$found" ]; then
            row OK "$label" "$found"
        elif [ -n "$existing" ]; then
            row FAIL "$label" "marked installed but not executable:$existing"
        else
            row FAIL "$label" "marked installed but missing: $*"
        fi
    elif [ -n "$found" ]; then
        row INFO "$label" "detected/executable but not marked: $found"
    elif [ -n "$existing" ]; then
        row WARN "$label" "detected but not executable:$existing"
    else
        row INFO "$label" "not installed: $*"
    fi
}

port_row() {
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | grep -q ":$2 " && { row OK "$1" "listening on $2"; return; }
    elif command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | grep -q ":$2 " && { row OK "$1" "listening on $2"; return; }
    else
        row INFO "$1" "port check skipped: ss/netstat missing"
        return
    fi
    row "$3" "$1" "not listening on $2"
}

version_line() {
    name="$1"
    shift
    printf "%-18s " "$name"
    "$@" 2>&1 | head -1 || true
}

compile_python_files() {
    py_list=/tmp/dependency_audit_py_files.$$
    find -L "$SCRIPT_DIR" -maxdepth 3 -type f -name '*.py' 2>/dev/null > "$py_list"
    if [ ! -s "$py_list" ]; then
        row INFO "python compile" "no helper Python files found"
        rm -f "$py_list"
        return 0
    fi
    if python3 - "$py_list" >/tmp/dependency_audit_py.out 2>/tmp/dependency_audit_py.err <<'PYEOF'
import pathlib
import sys

bad = []
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    files = [line.strip() for line in handle if line.strip()]
for name in files:
    path = pathlib.Path(name)
    try:
        compile(path.read_text(), str(path), "exec")
    except Exception as exc:
        bad.append(f"{path}: {exc}")
if bad:
    print("\n".join(bad))
    raise SystemExit(1)
PYEOF
    then
        row OK "python compile" "helper Python files passed"
    else
        row FAIL "python compile" "$(cat /tmp/dependency_audit_py.err /tmp/dependency_audit_py.out 2>/dev/null | tail -5 | tr '\n' ' ')"
    fi
    rm -f "$py_list" /tmp/dependency_audit_py.err /tmp/dependency_audit_py.out
}

echo ""
echo "K2 Pro Combo dependency audit"
echo "Safety: read-only only. This does not install, flash, move, heat or restart."
echo ""

echo "Core commands"
echo "-------------"
for c in sh python3 awk sed grep find stat tar gzip; do
    need_cmd "$c"
done
for c in curl wget ss netstat ip jq sqlite3 unzip xz base64 timeout bash git rsync scp sftp-server ffmpeg file nano opkg tree udevadm v4l2-ctl; do
    optional_cmd "$c"
done

echo ""
echo "Command versions"
echo "----------------"
version_line "python3" python3 --version
version_line "curl" curl --version
version_line "wget" wget --version
version_line "ip" ip -V
version_line "sqlite3" sqlite3 --version
version_line "git" git --version
version_line "ffmpeg" ffmpeg -version
if command -v wget >/dev/null 2>&1; then
    row OK "wget usable" "present; version/help flags may be limited on embedded builds"
else
    row WARN "wget usable" "wget missing"
fi
if command -v ip >/dev/null 2>&1 && ip -json -det address >/dev/null 2>&1; then
    row OK "ip json" "Moonraker network parser compatible"
elif command -v ip >/dev/null 2>&1; then
    row WARN "ip json" "ip -json -det address failed"
else
    row INFO "ip json" "ip command missing"
fi
if [ -x "$SCRIPT_DIR/scripts/moonraker_webcam_test.sh" ]; then
    ss_check_out=/tmp/dependency_audit_ss_$$
    if sh "$SCRIPT_DIR/scripts/moonraker_webcam_test.sh" format >"$ss_check_out" 2>&1; then
        row OK "ss listener format" "Moonraker webcam parser compatible"
    else
        row FAIL "ss listener format" "$(tail -1 "$ss_check_out")"
    fi
    rm -f "$ss_check_out"
else
    row FAIL "ss listener format" "moonraker_webcam_test.sh missing"
fi

echo ""
echo "Package files and feature install state"
echo "---------------------------------------"
file_row "helper.sh" "$SCRIPT_DIR/helper.sh"
file_row "go2rtc binary" "$SCRIPT_DIR/go2rtc"
file_row "go2rtc.yaml" "$SCRIPT_DIR/go2rtc.yaml"
file_row "CFS DB guard script" "$SCRIPT_DIR/scripts/cfs_db_guard.py"
file_row "CFS DB patch snapshot" "$SCRIPT_DIR/files/cfs_db_patch/material_database.json"
file_row "CFS protocol report" "$SCRIPT_DIR/scripts/cfs_protocol_report.sh"
file_row "CFS Safe Tools worker" "$SCRIPT_DIR/scripts/cfs_safe_tools.py"
file_row "CFS Safe Tools service source" "$SCRIPT_DIR/scripts/S97cfs_safe_monitor"
file_row "K2 observability worker" "$SCRIPT_DIR/scripts/k2_observability.py"
file_row "Filament PA/Flow result worker" "$SCRIPT_DIR/scripts/filament_calibration.py"
file_row "Filament PA/Flow result wrapper" "$SCRIPT_DIR/scripts/filament_calibration.sh"
file_row "G-Code preflight worker" "$SCRIPT_DIR/scripts/gcode_preflight.py"
file_row "Post-update guard worker" "$SCRIPT_DIR/scripts/post_update_guard.py"
file_row "K2 compact status page" "$SCRIPT_DIR/web/k2-status/index.html"
file_row "Nozzle AI power-script guard" "$SCRIPT_DIR/scripts/nozzle_camera_power_guard.sh"
file_row "F012 stock nozzle power script" "$SCRIPT_DIR/files/nozzle_camera/nozzle_cam_power.sh"
file_row "Klipper GC installer" "$SCRIPT_DIR/scripts/klipper_gc.sh"
file_row "Klipper GC package module" "$SCRIPT_DIR/files/klipper_gc/garbage_collection.py"
file_row "Factory G-Code hybrid installer" "$SCRIPT_DIR/scripts/gcode_time_hybrid.sh"
file_row "Passive G-Code time audit" "$SCRIPT_DIR/scripts/gcode_time_audit.py"
file_row "Factory G-Code hybrid checksums" "$SCRIPT_DIR/files/gcode_time_hybrid/F012/SHA256SUMS.txt"
optional_file_row "installed marker" "$SCRIPT_DIR/.installed"
optional_file_row "nozzle camera init helper" "$SCRIPT_DIR/scripts/S98nozzle_camera_recover"
optional_file_row "nozzle camera recover script" "$SCRIPT_DIR/scripts/nozzle_camera_recover.sh"
optional_file_row "Moonraker webcam test compatibility" "$SCRIPT_DIR/scripts/moonraker_webcam_test.sh"
optional_file_row "Creality USB camera mapper" "/etc/hotplug.d/usb/60-v4l"
feature_file_row "moonraker_extensions" "moonraker.conf" "$CONFIG_DIR/moonraker.conf"
feature_exec_any "camera_support" "camera service" "/etc/rc.d/S99camera" "/etc/init.d/S99camera"
feature_exec_any "creality_timelapse_recover" "timelapse recover service" "/etc/rc.d/S99timelapse_recover" "/etc/init.d/S99timelapse_recover"
feature_exec_any "spoolman_cfs_sync" "spoolman sync service" "/etc/rc.d/S99spoolman_cfs_sync" "/etc/init.d/S99spoolman_cfs_sync"
feature_exec_any "cfs_db_guard" "CFS DB guard service" "/etc/rc.d/S98cfs_db_guard" "/etc/init.d/S98cfs_db_guard"
feature_exec_any "cfs_safe_tools" "CFS Safe Tools service" "/etc/rc.d/S97cfs_safe_monitor" "/etc/init.d/S97cfs_safe_monitor"
if is_installed "cfs_safe_tools"; then
    if grep -Fqx '/etc/rc.d/S97cfs_safe_monitor boot &' /etc/rc.local 2>/dev/null; then
        row OK "CFS Safe Tools boot hook" "/etc/rc.local"
    else
        row FAIL "CFS Safe Tools boot hook" "marked installed but missing from /etc/rc.local"
    fi
fi
feature_file_row "klipper_gc" "Klipper GC live module" "/usr/share/klipper/klippy/extras/garbage_collection.py"
feature_file_row "klipper_gc" "Klipper GC config" "$CONFIG_DIR/k2pro_garbage_collection.cfg"
feature_file_row "gcode_time_hybrid" "Factory G-Code boot source" "/usr/share/klipper/gcodes/F012/3DBench_PLA_21m.gcode"
feature_file_row "fluidd_updated" "fluidd webroot" "/usr/share/fluidd"
feature_file_row "mainsail" "mainsail webroot" "/usr/share/mainsail"
if is_installed "k2_status_hub"; then
    if sh "$SCRIPT_DIR/scripts/k2_status_hub.sh" status >/tmp/k2_status_dependency.log 2>&1; then
        row OK "K2 status endpoint" "dedicated port 4410; HTTP/no-store/JSON checks passed"
    else
        row FAIL "K2 status endpoint" "marked installed but dedicated endpoint check failed"
    fi
else
    row INFO "K2 status endpoint" "not installed; dedicated port 4410 is optional"
fi
optional_file_row "post-update baseline" "$SCRIPT_DIR/state/post_update_baseline.json"
optional_file_row "bed mesh history" "$SCRIPT_DIR/reports/bed_mesh_history.jsonl"
optional_file_row "CFS consumption dry-run history" "$SCRIPT_DIR/reports/cfs_consumption_dry_run.jsonl"
feature_file_row "kamp" "KAMP config" "$CONFIG_DIR/KAMP"
feature_file_row "kamp" "restore_bed_mesh.py" "/usr/share/klipper/klippy/extras/restore_bed_mesh.py"
feature_file_row "git_backup" "Git config history" "$CONFIG_DIR/.git"
feature_exec_any "octoeverywhere" "OctoEverywhere service" "/etc/init.d/octoeverywhere" "/etc/rc.d/S99octoeverywhere"
optional_file_row "spoolman sync worker" "$SCRIPT_DIR/spoolman_cfs_sync.py"
optional_file_row "spoolman active CFS slot map" "$SCRIPT_DIR/spoolman_cfs_map.json"
optional_file_row "spoolman example CFS slot map" "$SCRIPT_DIR/spoolman_cfs_map.example.json"
optional_file_row "handover baseline script" "$SCRIPT_DIR/scripts/handover_baseline_k2pro.sh"
optional_file_row "spoolman CFS status script" "$SCRIPT_DIR/scripts/spoolman_cfs_status.sh"
optional_file_row "K2 Pro safe policy document" "$SCRIPT_DIR/docs/K2_PRO_COMBO_SAFE_POLICY_2026-07-07.md"
optional_file_row "HelixScreen service" "/etc/init.d/S99helixscreen"

echo ""
echo "Listening ports"
echo "---------------"
port_row "Creality web" 80 WARN
port_row "Moonraker" 7125 WARN
port_row "Fluidd" 4408 INFO
port_row "Mainsail" 4409 INFO
port_row "K2 status" 4410 INFO
port_row "go2rtc" 1984 INFO
port_row "Creality WebRTC local" 8000 INFO

echo ""
echo "Helper syntax checks"
echo "--------------------"
if sh -n "$SCRIPT_DIR/helper.sh" 2>/tmp/dependency_audit_sh.err; then
    row OK "helper shell syntax" "helper.sh"
else
    row FAIL "helper shell syntax" "$(cat /tmp/dependency_audit_sh.err 2>/dev/null)"
fi
sh_fail=0
for f in "$SCRIPT_DIR"/scripts/*.sh "$SCRIPT_DIR/scripts/S98nozzle_camera_recover"; do
    [ -e "$f" ] || continue
    if ! sh -n "$f" 2>/tmp/dependency_audit_sh.err; then
        sh_fail=$((sh_fail + 1))
        row FAIL "script shell syntax" "$f: $(cat /tmp/dependency_audit_sh.err 2>/dev/null)"
    fi
done
[ "$sh_fail" -eq 0 ] && row OK "script shell syntax" "all shell scripts passed"
rm -f /tmp/dependency_audit_sh.err
compile_python_files

echo ""
echo "Feature dependency notes"
echo "------------------------"
row INFO "Moonraker core" "Creality bundled core; do not blindly update via web UI"
row INFO "Moonraker webcam test" "BusyBox netstat requires the helper ss-format wrapper; camera streaming itself is unchanged"
row INFO "Moonraker Timelapse" "keep off while Creality Timelapse Recover works"
row INFO "M600" "blocked on CFS/Box; only for non-CFS manual printers"
row INFO "Z-Offset macros" "blocked unless deliberately testing"
row INFO "HelixScreen" "test-only; stock display/CFS/AI must be retested after install"
row INFO "CFS DB Guard" "cold-idle DB rewrite watcher; no BOX/CFS load, unload, extrude or refresh command"
row INFO "Git Backup local" "safe local config snapshots; GitHub remote is optional/manual"
row INFO "OctoEverywhere" "cloud remote access; official installer only after backup and explicit confirmation"
row INFO "Mobileraker" "phone app can use Moonraker directly; Companion belongs on Raspberry Pi/Debian"
row INFO "Nozzle AI camera" "Creality on-demand camera; use helper.sh --nozzle-camera-diagnose for USB/UVC/BIND evidence before recovery"
row INFO "Nozzle AI power script" "must return immediately; use --nozzle-power-status to detect blocking legacy waits that can trigger false key564 shutdowns"
row INFO "Spoolman CFS Sync" "active slot map is not overwritten by the package; use --spoolman-cfs-status, copy/edit spoolman_cfs_map.example.json with real IDs, then enable"
row INFO "Klipper Garbage Collection" "small upstream runtime optimization; K2/CFS changes require a full Linux reboot, never an isolated Klipper restart"

echo ""
echo "Summary"
echo "-------"
echo "OK=$ok WARN_OR_INFO=$warn FAIL=$fail"
if [ "$fail" -eq 0 ]; then
    echo "Result: dependency baseline is complete for the current installed feature set."
    exit 0
else
    echo "Result: missing required dependencies found."
    exit 1
fi
