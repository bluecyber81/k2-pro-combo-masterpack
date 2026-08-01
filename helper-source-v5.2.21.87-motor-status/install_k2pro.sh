#!/bin/sh
# Install/update this extracted helper package without replacing local state.
set -eu

VERSION=v5.2.21.87-motor-status
TARGET=/mnt/UDISK/helper-script
BACKUP_ROOT=/mnt/UDISK/printer_data/backups/k2pro_helper
SOURCE="$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd)"

validate_package() {
    test -f "$SOURCE/helper.sh"
    test -f "$SOURCE/scripts/system.sh"
    test -f "$SOURCE/scripts/klipper_gc.sh"
    test -f "$SOURCE/scripts/k2pro_protection_guard.sh"
    test -f "$SOURCE/scripts/k2pro_protection_guard.py"
    test -f "$SOURCE/scripts/bed_mesh_insights.py"
    test -f "$SOURCE/scripts/k2_lan_insights.py"
    test -f "$SOURCE/scripts/k2_observability.py"
    test -f "$SOURCE/scripts/filament_calibration.py"
    test -f "$SOURCE/scripts/filament_calibration.sh"
    test -f "$SOURCE/scripts/motor_controller_report.py"
    test -f "$SOURCE/scripts/motor_controller_report.sh"
    test -f "$SOURCE/scripts/gcode_preflight.py"
    test -f "$SOURCE/scripts/post_update_guard.py"
    test -f "$SOURCE/scripts/k2_status_hub.sh"
    test -f "$SOURCE/scripts/nozzle_camera_power_guard.sh"
    test -f "$SOURCE/docs/K2_PRO_AI_NOZZLE_CAMERA_2026-07-31.md"
    test -f "$SOURCE/docs/K2_PRO_CFS_MOTOR_CONTROLLER_2026-08-01.md"
    test -f "$SOURCE/files/nozzle_camera/nozzle_cam_power.sh"
    test -f "$SOURCE/web/k2-status/index.html"
    test -f "$SOURCE/web/k2-status/status.json"

    if [ -f "$SOURCE/PACKAGE_SHA256SUMS.txt" ]; then
        (
            cd "$SOURCE"
            sha256sum -c PACKAGE_SHA256SUMS.txt
        )
    fi

    for file in \
        "$SOURCE/helper.sh" \
        "$SOURCE/install_k2pro.sh" \
        "$SOURCE"/scripts/*.sh \
        "$SOURCE"/scripts/S[0-9]* \
        "$SOURCE"/tests/*.sh; do
        [ -f "$file" ] || continue
        sh -n "$file"
    done

    python3 -B - "$SOURCE" <<'PYEOF'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for path in root.rglob("*.py"):
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
for path in root.rglob("*.json"):
    json.loads(path.read_text(encoding="utf-8"))
PYEOF

    python3 -B "$SOURCE/scripts/k2pro_protection_guard.py" --selftest
    python3 -B "$SOURCE/scripts/bed_mesh_insights.py" --selftest
    python3 -B "$SOURCE/scripts/k2_lan_insights.py" --selftest
    python3 -B "$SOURCE/scripts/k2_observability.py" --selftest
    python3 -B "$SOURCE/scripts/filament_calibration.py" --selftest
    python3 -B "$SOURCE/scripts/gcode_preflight.py" --selftest
    python3 -B "$SOURCE/scripts/post_update_guard.py" --selftest
    python3 -B "$SOURCE/scripts/motor_controller_report.py" --selftest
    K2_HELPER_DIR="$SOURCE" sh "$SOURCE/scripts/nozzle_camera_power_guard.sh" selftest

    if [ -d "$SOURCE/tests" ]; then
        (
            cd "$SOURCE"
            PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s tests -p 'test_*.py'
        )
        if [ -f "$SOURCE/tests/test_cfs_safe_boot_hook.sh" ]; then
            TMPDIR=/tmp sh "$SOURCE/tests/test_cfs_safe_boot_hook.sh"
        fi
    fi
}

refresh_managed_path() {
    managed_source="$1"
    managed_target="$2"
    managed_backup_name="$3"

    [ -e "$managed_target" ] || return 0
    [ -L "$managed_target" ] && return 0
    cmp -s "$managed_source" "$managed_target" && return 0

    mkdir -p "$SERVICE_BACKUP_DIR"
    cp -a "$managed_target" "$SERVICE_BACKUP_DIR/$managed_backup_name"
    managed_candidate="$managed_target.new.$$"
    cp "$managed_source" "$managed_candidate"
    chmod 0755 "$managed_candidate"
    sh -n "$managed_candidate"
    mv -f "$managed_candidate" "$managed_target"
    echo "Refreshed managed service: $managed_target"
}

sync_managed_service() {
    managed_source="$1"
    managed_name="$2"

    [ -f "$managed_source" ] || return 0
    if [ -e "/etc/init.d/$managed_name" ] || [ -e "/etc/rc.d/$managed_name" ]; then
        refresh_managed_path "$managed_source" "/etc/init.d/$managed_name" "init.d-$managed_name"
        refresh_managed_path "$managed_source" "/etc/rc.d/$managed_name" "rc.d-$managed_name"
    fi
}

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: run this installer as root."
    exit 1
fi

model="$(/usr/bin/get_sn_mac.sh model 2>/dev/null || true)"
board="$(/usr/bin/get_sn_mac.sh board 2>/dev/null || true)"
if [ "$model" != "F012" ] || [ "$board" != "CR0CN200400C10" ]; then
    echo "ERROR: expected K2 Pro model F012 and board CR0CN200400C10."
    echo "Detected: model=${model:-unknown} board=${board:-unknown}"
    exit 1
fi

validate_package

echo "This updates /mnt/UDISK/helper-script and preserves local hidden/state files."
echo "Existing helper-managed S97/S98 service files are refreshed with a backup."
echo "It does not flash firmware, MCU or CFS and does not restart printer services."
printf "Install/update Helper %s? [y/n]: " "$VERSION"
read confirm
[ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || { echo "Cancelled."; exit 0; }

mkdir -p "$TARGET" "$BACKUP_ROOT"
stamp="$(date +%Y%m%d_%H%M%S)"
SERVICE_BACKUP_DIR="$BACKUP_ROOT/managed-services-before-${VERSION#v}_$stamp"
if [ "$SOURCE" != "$TARGET" ] && [ -d "$TARGET" ]; then
    backup="$BACKUP_ROOT/helper-script-before-${VERSION#v}_$stamp.tar.gz"
    tar -czf "$backup" -C /mnt/UDISK helper-script
    echo "Backup: $backup"
    cp -a "$SOURCE"/. "$TARGET"/
fi

chmod 0755 "$TARGET/helper.sh" "$TARGET/go2rtc"
find "$TARGET" -maxdepth 1 -type f -name '*.py' -exec chmod 0755 {} \;
find "$TARGET/scripts" -maxdepth 1 -type f \( -name '*.sh' -o -name 'S[0-9]*' \) -exec chmod 0755 {} \;
find "$TARGET/scripts" -maxdepth 1 -type f -name '*.py' -exec chmod 0755 {} \;
find "$TARGET" -type d \( -name __pycache__ -o -name .ruff_cache -o -name .mypy_cache -o -name .pytest_cache \) -prune -exec rm -rf {} + 2>/dev/null || true
find "$TARGET" -type f \( -name '*.pyc' -o -name '*.pyo' \) -exec rm -f {} + 2>/dev/null || true
touch "$TARGET/.installed"

sync_managed_service "$TARGET/scripts/S97cfs_safe_monitor" "S97cfs_safe_monitor"
sync_managed_service "$TARGET/scripts/S98nozzle_camera_recover" "S98nozzle_camera_recover"

grep -q "$VERSION" "$TARGET/helper.sh"
python3 -B "$TARGET/scripts/k2_observability.py" --refresh-status >/dev/null 2>&1 || true
python3 -B "$TARGET/scripts/k2_observability.py" --ai-status || true
python3 -B "$TARGET/scripts/filament_calibration.py" --status || true
sync
echo "HELPER_INSTALL_OK|version=$VERSION|target=$TARGET"
