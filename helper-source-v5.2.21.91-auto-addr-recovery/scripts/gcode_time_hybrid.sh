#!/bin/sh
# Keep the three K2 Pro factory sample files on the validated hybrid timeline.
set -eu

SCRIPT_DIR=/mnt/UDISK/helper-script
PACKAGE_DIR=$SCRIPT_DIR/files/gcode_time_hybrid/F012
SOURCE_DIR=/usr/share/klipper/gcodes/F012
USER_DIR=/mnt/UDISK/printer_data/gcodes
BACKUP_ROOT=/mnt/UDISK/printer_data/backups/k2pro_helper
STATE_FILE=$SCRIPT_DIR/.gcode_time_hybrid_backup
FEATURE=gcode_time_hybrid
AUDIT=$SCRIPT_DIR/scripts/gcode_time_audit.py

. "$SCRIPT_DIR/scripts/system.sh"

file_sha() {
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

expected_sha() {
    grep -F "  $1" "$PACKAGE_DIR/SHA256SUMS.txt" | head -n 1 | awk '{print $1}'
}

check_package() {
    [ -d "$PACKAGE_DIR" ] || { log_error "Package directory is missing: $PACKAGE_DIR"; return 1; }
    [ -f "$PACKAGE_DIR/SHA256SUMS.txt" ] || { log_error "Package checksums are missing."; return 1; }
    (cd "$PACKAGE_DIR" && sha256sum -c SHA256SUMS.txt >/dev/null)
}

check_printer_guard() {
    model="$(/usr/bin/get_sn_mac.sh model 2>/dev/null || true)"
    board="$(/usr/bin/get_sn_mac.sh board 2>/dev/null || true)"
    if [ "$model" != "F012" ] || [ "$board" != "CR0CN200400C10" ]; then
        log_error "Expected K2 Pro F012/CR0CN200400C10, got ${model:-unknown}/${board:-unknown}."
        return 1
    fi
}

require_standby() {
    state_json="$(wget -qO- 'http://127.0.0.1:7125/printer/objects/query?print_stats' 2>/dev/null || true)"
    echo "$state_json" | grep -q '"state": "standby"' || {
        log_error "Printer is not in standby; factory G-code update blocked."
        return 1
    }
}

status_one() {
    name="$1"
    expected="$(expected_sha "$name")"
    source_actual="$(file_sha "$SOURCE_DIR/$name")"
    user_actual="$(file_sha "$USER_DIR/$name")"
    source_state=DIFF
    user_state=DIFF
    [ -n "$expected" ] && [ "$source_actual" = "$expected" ] && source_state=OK
    [ -n "$expected" ] && [ "$user_actual" = "$expected" ] && user_state=OK
    echo "GCODE_TIME_FILE|name=$name|source=$source_state|user=$user_state|expected=$expected"
    [ "$source_state" = OK ] && [ "$user_state" = OK ]
}

all_match() {
    status_one '3DBench_PLA_21m.gcode' >/dev/null 2>&1 &&
    status_one '4color-3DBench_PLA_31m.gcode' >/dev/null 2>&1 &&
    status_one 'spatula_PLA_35m2s.gcode' >/dev/null 2>&1
}

status_all() {
    result=0
    echo ""
    echo "K2 Pro factory G-code hybrid-time status"
    echo "========================================"
    check_package || result=1
    status_one '3DBench_PLA_21m.gcode' || result=1
    status_one '4color-3DBench_PLA_31m.gcode' || result=1
    status_one 'spatula_PLA_35m2s.gcode' || result=1
    if [ -f "$AUDIT" ]; then
        python3 -B "$AUDIT" --directory "$USER_DIR" --max-files 200 || result=1
    else
        log_warn "Passive G-code time audit is missing: $AUDIT"
        result=1
    fi
    if [ "$result" -eq 0 ]; then
        log_success "Factory source and user copies use the hybrid timelines."
    else
        log_warn "At least one factory source or user copy differs. Run install after checking standby."
    fi
    echo "GCODE_TIME_STATUS|result=$result|boot_source=$SOURCE_DIR"
    return "$result"
}

copy_atomic() {
    source_file="$1"
    target_file="$2"
    temp_file="$(dirname "$target_file")/.$(basename "$target_file").hybrid-time-$$"
    cp -p "$source_file" "$temp_file"
    mv -f "$temp_file" "$target_file"
}

backup_pair() {
    backup_dir="$1"
    mkdir -p "$backup_dir/source" "$backup_dir/user"
    for name in \
        '3DBench_PLA_21m.gcode' \
        '4color-3DBench_PLA_31m.gcode' \
        'spatula_PLA_35m2s.gcode'; do
        cp -p "$SOURCE_DIR/$name" "$backup_dir/source/$name"
        cp -p "$USER_DIR/$name" "$backup_dir/user/$name"
    done
}

restore_pair() {
    backup_dir="$1"
    for name in \
        '3DBench_PLA_21m.gcode' \
        '4color-3DBench_PLA_31m.gcode' \
        'spatula_PLA_35m2s.gcode'; do
        copy_atomic "$backup_dir/source/$name" "$SOURCE_DIR/$name"
        copy_atomic "$backup_dir/user/$name" "$USER_DIR/$name"
    done
    sync
}

rollback_on_exit() {
    status=$?
    trap - EXIT HUP INT TERM
    if [ "$rollback" = 1 ]; then
        restore_pair "$rollback_dir" || true
    fi
    exit "$status"
}

install_all() {
    check_printer_guard
    require_standby
    check_package
    if [ ! -d "$SOURCE_DIR" ] || [ ! -d "$USER_DIR" ]; then
        log_error "Factory source or user G-code directory is missing."
        return 1
    fi

    if all_match; then
        mark_installed "$FEATURE"
        log_success "Factory G-code hybrid times are already boot-persistent."
        return 0
    fi

    stamp="$(date +%Y%m%d_%H%M%S)"
    backup_dir="$BACKUP_ROOT/gcode_time_hybrid_$stamp"
    backup_pair "$backup_dir"
    rollback=1
    rollback_dir="$backup_dir"
    trap 'rollback_on_exit' EXIT
    trap 'exit 130' HUP INT TERM

    for name in \
        '3DBench_PLA_21m.gcode' \
        '4color-3DBench_PLA_31m.gcode' \
        'spatula_PLA_35m2s.gcode'; do
        copy_atomic "$PACKAGE_DIR/$name" "$SOURCE_DIR/$name"
        copy_atomic "$PACKAGE_DIR/$name" "$USER_DIR/$name"
    done
    sync
    all_match

    printf '%s\n' "$backup_dir" > "$STATE_FILE.tmp"
    mv -f "$STATE_FILE.tmp" "$STATE_FILE"
    mark_installed "$FEATURE"
    rollback=0
    trap - EXIT HUP INT TERM
    log_success "Boot-persistent factory G-code hybrid times installed. Backup: $backup_dir"
    status_all
}

remove_all() {
    check_printer_guard
    require_standby
    [ -f "$STATE_FILE" ] || { log_error "No helper-managed factory G-code backup pointer found."; return 1; }
    original_backup="$(cat "$STATE_FILE")"
    case "$original_backup" in
        "$BACKUP_ROOT"/gcode_time_hybrid_*) ;;
        *) log_error "Invalid backup pointer: $original_backup"; return 1 ;;
    esac
    if [ ! -d "$original_backup/source" ] || [ ! -d "$original_backup/user" ]; then
        log_error "Original backup is incomplete: $original_backup"
        return 1
    fi

    stamp="$(date +%Y%m%d_%H%M%S)"
    safety_backup="$BACKUP_ROOT/gcode_time_hybrid_remove_$stamp"
    backup_pair "$safety_backup"
    rollback=1
    rollback_dir="$safety_backup"
    trap 'rollback_on_exit' EXIT
    trap 'exit 130' HUP INT TERM

    restore_pair "$original_backup"
    for name in \
        '3DBench_PLA_21m.gcode' \
        '4color-3DBench_PLA_31m.gcode' \
        'spatula_PLA_35m2s.gcode'; do
        cmp -s "$original_backup/source/$name" "$SOURCE_DIR/$name"
        cmp -s "$original_backup/user/$name" "$USER_DIR/$name"
    done

    rm -f "$STATE_FILE"
    mark_removed "$FEATURE"
    rollback=0
    trap - EXIT HUP INT TERM
    log_success "Original factory and user G-code files restored. Safety backup: $safety_backup"
}

case "${1:-status}" in
    install) install_all ;;
    status) status_all ;;
    remove) remove_all ;;
    *) echo "Usage: $0 {install|status|remove}"; exit 2 ;;
esac
