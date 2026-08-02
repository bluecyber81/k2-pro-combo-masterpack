#!/bin/sh
# Guarded recovery fix for Creality K2 Pro auto-address callbacks on firmware 1.1.6.7.
set -eu

SCRIPT_DIR=${K2_HELPER_DIR:-/mnt/UDISK/helper-script}
TARGET=/usr/share/klipper/klippy/extras/auto_addr_wrapper.py
PAYLOAD=$SCRIPT_DIR/files/auto_addr_recovery/auto_addr_wrapper.py
BACKUP_ROOT=/mnt/UDISK/printer_data/backups/k2pro_helper/auto_addr_recovery
STATE_FILE=$SCRIPT_DIR/.auto_addr_recovery_backup
FEATURE=auto_addr_recovery
EXPECTED_FIRMWARE=1.1.6.7
STOCK_SHA256=d413f7d641085cf7f8506558abbb973ded5c84e46bf2e151169ef12666a16b01
PATCHED_SHA256=304e49f651081ff9679bfbd355f4b656969c5d39a96498c4f30915248c09fa16

. "$SCRIPT_DIR/scripts/system.sh"
SCRIPT_DIR=${K2_HELPER_DIR:-/mnt/UDISK/helper-script}

file_sha() {
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

current_firmware() {
    if [ -x /etc/ota_bin/get_ota_current_version.sh ]; then
        /etc/ota_bin/get_ota_current_version.sh 2>/dev/null | tr -d '\r\n '
    fi
}

check_exact_printer() {
    model="$(/usr/bin/get_sn_mac.sh model 2>/dev/null || true)"
    board="$(/usr/bin/get_sn_mac.sh board 2>/dev/null || true)"
    firmware="$(current_firmware)"
    if [ "$model" != "F012" ] || [ "$board" != "CR0CN200400C10" ]; then
        log_error "Expected K2 Pro F012/CR0CN200400C10, got ${model:-unknown}/${board:-unknown}."
        return 1
    fi
    if [ "$firmware" != "$EXPECTED_FIRMWARE" ]; then
        log_error "This payload is only reviewed for firmware $EXPECTED_FIRMWARE; detected ${firmware:-unknown}."
        return 1
    fi
}

require_cold_standby() {
    python3 - <<'PYEOF'
import json
import sys
import urllib.request

url = (
    "http://127.0.0.1:7125/printer/objects/query?"
    "webhooks&print_stats&heater_bed&extruder"
)
try:
    with urllib.request.urlopen(url, timeout=5) as response:
        status = json.load(response)["result"]["status"]
except Exception as exc:
    print("AUTO_ADDR_RECOVERY_FAIL|moonraker=%s" % exc)
    raise SystemExit(1)

state = status.get("print_stats", {}).get("state", "unknown")
webhooks = status.get("webhooks", {}).get("state", "unknown")
extruder_target = float(status.get("extruder", {}).get("target", -1))
bed_target = float(status.get("heater_bed", {}).get("target", -1))
print(
    "AUTO_ADDR_RECOVERY_IDLE|webhooks=%s|print=%s|extruder_target=%.1f|bed_target=%.1f"
    % (webhooks, state, extruder_target, bed_target)
)
if webhooks != "ready" or state != "standby" or extruder_target != 0 or bed_target != 0:
    raise SystemExit(1)
PYEOF
}

verify_payload() {
    [ -f "$PAYLOAD" ] || { log_error "Payload missing: $PAYLOAD"; return 1; }
    actual="$(file_sha "$PAYLOAD")"
    if [ "$actual" != "$PATCHED_SHA256" ]; then
        log_error "Payload checksum mismatch: ${actual:-missing}"
        return 1
    fi
    python3 -B - "$PAYLOAD" <<'PYEOF'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PYEOF
    python3 -B "$SCRIPT_DIR/tests/test_auto_addr_recovery.py" --module "$PAYLOAD"
}

status_fix() {
    check_exact_printer || return 1
    verify_payload || return 1
    [ -f "$TARGET" ] || { log_error "Target missing: $TARGET"; return 1; }
    target_sha="$(file_sha "$TARGET")"
    case "$target_sha" in
        "$PATCHED_SHA256")
            log_success "auto_addr recovery guard is installed and exact."
            state=installed
            ;;
        "$STOCK_SHA256")
            log_warn "Stock 1.1.6.7 auto_addr file is present; the reviewed recovery guard is not installed."
            state=stock-affected
            ;;
        *)
            log_error "Unknown auto_addr target hash; no automatic write is allowed."
            state=unknown
            ;;
    esac
    echo "AUTO_ADDR_RECOVERY_STATUS|state=$state|firmware=$EXPECTED_FIRMWARE|target_sha=$target_sha|payload_sha=$PATCHED_SHA256"
    [ "$state" != unknown ]
}

copy_atomic() {
    source_file="$1"
    target_file="$2"
    candidate="${target_file}.new.$$"
    cp -p "$source_file" "$candidate"
    chmod 0644 "$candidate"
    python3 -B - "$candidate" <<'PYEOF'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PYEOF
    mv -f "$candidate" "$target_file"
}

install_fix() {
    [ "$(id -u)" = 0 ] || { log_error "Run as root."; return 1; }
    check_exact_printer || return 1
    require_cold_standby || { log_error "Printer must be ready, cold and in standby."; return 1; }
    verify_payload || return 1
    [ -f "$TARGET" ] || { log_error "Target missing: $TARGET"; return 1; }

    target_sha="$(file_sha "$TARGET")"
    if [ "$target_sha" = "$PATCHED_SHA256" ]; then
        mark_installed "$FEATURE"
        log_success "auto_addr recovery guard is already installed."
        return 0
    fi
    if [ "$target_sha" != "$STOCK_SHA256" ]; then
        log_error "Refusing unknown target hash: ${target_sha:-missing}"
        return 1
    fi

    stamp="$(date +%Y%m%d_%H%M%S)"
    backup_dir="$BACKUP_ROOT/$stamp"
    mkdir -p "$backup_dir"
    cp -p "$TARGET" "$backup_dir/auto_addr_wrapper.py"
    echo "$STOCK_SHA256  auto_addr_wrapper.py" > "$backup_dir/SHA256SUMS.txt"
    (cd "$backup_dir" && sha256sum -c SHA256SUMS.txt >/dev/null)
    printf '%s\n' "$backup_dir" > "$STATE_FILE"

    rollback=1
    trap 'if [ "$rollback" = 1 ]; then copy_atomic "$backup_dir/auto_addr_wrapper.py" "$TARGET" || true; fi' EXIT HUP INT TERM
    copy_atomic "$PAYLOAD" "$TARGET"
    [ "$(file_sha "$TARGET")" = "$PATCHED_SHA256" ]
    python3 -B "$SCRIPT_DIR/tests/test_auto_addr_recovery.py" --module "$TARGET"
    rollback=0
    trap - EXIT HUP INT TERM
    mark_installed "$FEATURE"
    sync
    log_success "Installed guarded auto_addr recovery fix."
    log_info "Backup: $backup_dir"
    log_warn "A safe full K2/CFS reboot is required before the new module is loaded."
}

restore_fix() {
    [ "$(id -u)" = 0 ] || { log_error "Run as root."; return 1; }
    check_exact_printer || return 1
    require_cold_standby || { log_error "Printer must be ready, cold and in standby."; return 1; }
    [ -f "$STATE_FILE" ] || { log_error "No helper backup state found."; return 1; }
    backup_dir="$(cat "$STATE_FILE")"
    backup_file="$backup_dir/auto_addr_wrapper.py"
    [ -f "$backup_file" ] || { log_error "Backup file missing: $backup_file"; return 1; }
    [ "$(file_sha "$backup_file")" = "$STOCK_SHA256" ] || { log_error "Backup checksum is not the reviewed stock file."; return 1; }

    copy_atomic "$backup_file" "$TARGET"
    [ "$(file_sha "$TARGET")" = "$STOCK_SHA256" ]
    mark_removed "$FEATURE"
    sync
    log_success "Restored the original 1.1.6.7 auto_addr module."
    log_warn "A safe full K2/CFS reboot is required before the restored module is loaded."
}

selftest() {
    verify_payload
    grep -Fq 'if ack_data is None:' "$PAYLOAD"
    grep -Fq 'if dev_table_index is None:' "$PAYLOAD"
    if grep -Fq 'ack_data.dev_type == dev_table_map.dev_type):' "$PAYLOAD" && ! grep -Fq 'elif (ack_data.dev_type == dev_table_map.dev_type):' "$PAYLOAD"; then
        log_error "Payload still has the unconditional first-table break."
        return 1
    fi
    log_success "auto_addr recovery payload selftest passed."
}

case "${1:-status}" in
    status) status_fix ;;
    install|repair) install_fix ;;
    restore|remove) restore_fix ;;
    selftest) selftest ;;
    *) echo "Usage: $0 {status|install|repair|restore|remove|selftest}"; exit 2 ;;
esac
