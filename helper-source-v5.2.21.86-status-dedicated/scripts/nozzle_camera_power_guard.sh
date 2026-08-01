#!/bin/sh
# Exact F012 nozzle-camera power-script guard.
set -u

SCRIPT_DIR="${K2_HELPER_DIR:-/mnt/UDISK/helper-script}"
BUNDLED="$SCRIPT_DIR/files/nozzle_camera/nozzle_cam_power.sh"
ROM_SOURCE="/rom/usr/bin/nozzle_cam_power.sh"
LIVE_TARGET="/usr/bin/nozzle_cam_power.sh"
BACKUP_ROOT="/mnt/UDISK/printer_data/backups/k2pro_helper/nozzle-camera-power"
EXPECTED_SHA256="35f8441be73a5c2741993832795bd0dee7dfba28277e8d2f795aa1d7abb274b9"

hash_file() {
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

identity_ok() {
    model="$(/usr/bin/get_sn_mac.sh model 2>/dev/null || true)"
    board="$(/usr/bin/get_sn_mac.sh board 2>/dev/null || true)"
    [ "$model" = "F012" ] && [ "$board" = "CR0CN200400C10" ]
}

package_ok() {
    [ -f "$BUNDLED" ] || return 1
    [ -f "$ROM_SOURCE" ] || return 1
    [ "$(hash_file "$BUNDLED")" = "$EXPECTED_SHA256" ] || return 1
    [ "$(hash_file "$ROM_SOURCE")" = "$EXPECTED_SHA256" ] || return 1
}

printer_cold_idle() {
    python3 -B - <<'PYEOF'
import json
import urllib.request

url = (
    "http://127.0.0.1:7125/printer/objects/query"
    "?print_stats&heater_bed&extruder"
)
with urllib.request.urlopen(url, timeout=4) as response:
    status = json.load(response)["result"]["status"]
state = status["print_stats"]["state"]
bed_target = float(status["heater_bed"]["target"])
extruder_target = float(status["extruder"]["target"])
allowed = {"standby", "complete", "cancelled", "error"}
if state not in allowed or bed_target != 0.0 or extruder_target != 0.0:
    raise SystemExit(1)
print(
    "NOZZLE_POWER_SAFE_STATE"
    f"|state={state}|bed_target={bed_target}|extruder_target={extruder_target}"
)
PYEOF
}

status_report() {
    echo "== K2 Pro nozzle-camera power-script guard =="
    echo "Safety: read-only status; no camera, heater, motion or restart command."

    if ! identity_ok; then
        echo "NOZZLE_POWER|FAIL|expected exact F012 / CR0CN200400C10"
        return 1
    fi
    if ! package_ok; then
        echo "NOZZLE_POWER|FAIL|bundled or ROM stock source does not match expected firmware hash"
        return 1
    fi
    if [ ! -f "$LIVE_TARGET" ]; then
        echo "NOZZLE_POWER|FAIL|live script missing: $LIVE_TARGET"
        return 1
    fi

    live_hash="$(hash_file "$LIVE_TARGET")"
    echo "NOZZLE_POWER_HASH|live=$live_hash|stock=$EXPECTED_SHA256"
    if [ "$live_hash" = "$EXPECTED_SHA256" ]; then
        echo "NOZZLE_POWER|OK|live script matches the nonblocking F012 firmware source"
        return 0
    fi

    if grep -Eq 'OFF_IMAGE_WAIT_SECONDS|cam_sub_busy|sleep[[:space:]]+["$]?delay|waited=.*OFF_IMAGE' "$LIVE_TARGET"; then
        echo "NOZZLE_POWER|WARN|blocking legacy guard detected; it can trigger false key564 heater shutdowns"
    else
        echo "NOZZLE_POWER|WARN|live script differs from exact F012 firmware source"
    fi
    return 2
}

restore_stock() {
    [ "$(id -u)" = "0" ] || {
        echo "NOZZLE_POWER|FAIL|run as root"
        return 1
    }
    identity_ok || {
        echo "NOZZLE_POWER|FAIL|expected exact F012 / CR0CN200400C10"
        return 1
    }
    package_ok || {
        echo "NOZZLE_POWER|FAIL|bundled or ROM source hash mismatch; refusing write"
        return 1
    }
    printer_cold_idle || {
        echo "NOZZLE_POWER|FAIL|printer must be idle with both heater targets at 0"
        return 1
    }

    if [ -f "$LIVE_TARGET" ] && cmp -s "$LIVE_TARGET" "$ROM_SOURCE"; then
        echo "NOZZLE_POWER|OK|live script already matches stock"
        return 0
    fi

    mkdir -p "$BACKUP_ROOT"
    stamp="$(date +%Y%m%d_%H%M%S)"
    if [ -f "$LIVE_TARGET" ]; then
        backup="$BACKUP_ROOT/nozzle_cam_power.sh.before-stock-$stamp"
        cp -p "$LIVE_TARGET" "$backup"
        echo "NOZZLE_POWER_BACKUP|$backup"
    fi

    candidate="$LIVE_TARGET.new.$$"
    cp "$ROM_SOURCE" "$candidate"
    chmod 0755 "$candidate"
    [ "$(hash_file "$candidate")" = "$EXPECTED_SHA256" ] || {
        rm -f "$candidate"
        echo "NOZZLE_POWER|FAIL|candidate hash mismatch"
        return 1
    }
    mv "$candidate" "$LIVE_TARGET"
    sync
    echo "NOZZLE_POWER|OK|restored exact nonblocking F012 firmware script"
    echo "NOZZLE_POWER_NOTE|no Klipper, camera or printer service restart is required"
}

selftest() {
    [ -f "$BUNDLED" ] || {
        echo "SELFTEST|FAIL|bundled stock script missing"
        return 1
    }
    [ "$(hash_file "$BUNDLED")" = "$EXPECTED_SHA256" ] || {
        echo "SELFTEST|FAIL|bundled stock hash mismatch"
        return 1
    }
    sh -n "$BUNDLED" || return 1
    if grep -Eq 'OFF_IMAGE_WAIT_SECONDS|cam_sub_busy|sleep[[:space:]]' "$BUNDLED"; then
        echo "SELFTEST|FAIL|bundled power script contains a blocking wait"
        return 1
    fi
    echo "SELFTEST|OK|exact F012 nozzle-camera power script is nonblocking"
}

case "${1:-status}" in
    status)
        status_report
        ;;
    restore-stock|restore)
        restore_stock
        ;;
    selftest)
        selftest
        ;;
    *)
        echo "Usage: $0 {status|restore-stock|selftest}"
        exit 2
        ;;
esac
