#!/bin/sh
# klipper_gc.sh - guarded upstream Klipper garbage-collection module for K2 Pro

SCRIPT_DIR=/mnt/UDISK/helper-script
CONFIG_DIR=/mnt/UDISK/printer_data/config
MODULE_SRC=$SCRIPT_DIR/files/klipper_gc/garbage_collection.py
MODULE_DST=/usr/share/klipper/klippy/extras/garbage_collection.py
GC_CFG=$CONFIG_DIR/k2pro_garbage_collection.cfg
MAIN_CFG=$CONFIG_DIR/printer.cfg
EXPECTED_SHA=6d339dcd08752fb95322ca5fb71a7624fec07cdaf639cb47803653346db232ff
BACKUP_ROOT=/mnt/UDISK/printer_data/backups/k2pro_helper

. "$SCRIPT_DIR/scripts/system.sh"

file_sha() {
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

compile_module() {
    python3 - "$1" <<'PYEOF'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PYEOF
}

new_backup_dir() {
    stamp="$(date +%Y%m%d_%H%M%S)"
    BACKUP_DIR="$BACKUP_ROOT/klipper_gc_$stamp"
    mkdir -p "$BACKUP_DIR"
    cp -p "$MAIN_CFG" "$BACKUP_DIR/printer.cfg" || return 1

    if [ -f "$MODULE_DST" ]; then
        cp -p "$MODULE_DST" "$BACKUP_DIR/garbage_collection.py"
        echo present > "$BACKUP_DIR/module_previous_state"
    else
        echo absent > "$BACKUP_DIR/module_previous_state"
    fi
    if [ -f "$GC_CFG" ]; then
        cp -p "$GC_CFG" "$BACKUP_DIR/k2pro_garbage_collection.cfg"
        echo present > "$BACKUP_DIR/config_previous_state"
    else
        echo absent > "$BACKUP_DIR/config_previous_state"
    fi

    cat > "$BACKUP_DIR/rollback.sh" <<EOF
#!/bin/sh
set -eu
cp -p '$BACKUP_DIR/printer.cfg' '$MAIN_CFG'
if test "\$(cat '$BACKUP_DIR/module_previous_state')" = present; then
    cp -p '$BACKUP_DIR/garbage_collection.py' '$MODULE_DST'
else
    rm -f '$MODULE_DST'
fi
if test "\$(cat '$BACKUP_DIR/config_previous_state')" = present; then
    cp -p '$BACKUP_DIR/k2pro_garbage_collection.cfg' '$GC_CFG'
else
    rm -f '$GC_CFG'
fi
sync
echo 'Rollback restored. Perform one full Linux reboot; do not restart only Klipper on K2/CFS.'
EOF
    chmod 0755 "$BACKUP_DIR/rollback.sh"
}

status_gc() {
    result=0
    echo ""
    echo "Klipper Garbage Collection status"
    echo "================================="

    if [ -f "$MODULE_DST" ]; then
        actual="$(file_sha "$MODULE_DST")"
        if [ "$actual" = "$EXPECTED_SHA" ]; then
            log_success "Official module is installed with the expected SHA256."
        else
            log_error "Installed module hash differs: ${actual:-unavailable}"
            result=1
        fi
        if compile_module "$MODULE_DST" >/dev/null 2>&1; then
            log_success "Installed module compiles with the printer Python."
        else
            log_error "Installed module does not compile."
            result=1
        fi
    else
        log_error "Module is missing: $MODULE_DST"
        result=1
    fi

    if [ -f "$GC_CFG" ] && grep -q '^\[garbage_collection\]$' "$GC_CFG" 2>/dev/null; then
        log_success "Garbage-collection config exists."
    else
        log_error "Garbage-collection config is missing or invalid: $GC_CFG"
        result=1
    fi

    if grep -Fxq '[include k2pro_garbage_collection.cfg]' "$MAIN_CFG" 2>/dev/null; then
        log_success "printer.cfg include is active."
    else
        log_error "printer.cfg include is missing."
        result=1
    fi

    if is_installed klipper_gc; then
        log_success "Helper install marker is present."
    else
        log_warn "Helper install marker is missing."
    fi

    echo "GC_STATUS|result=$result|expected_sha=$EXPECTED_SHA"
    return "$result"
}

install_gc() {
    [ -f "$MODULE_SRC" ] || { log_error "Bundled module missing: $MODULE_SRC"; return 1; }
    [ -f "$MAIN_CFG" ] || { log_error "printer.cfg missing: $MAIN_CFG"; return 1; }
    command -v sha256sum >/dev/null 2>&1 || { log_error "sha256sum is required."; return 1; }

    source_sha="$(file_sha "$MODULE_SRC")"
    [ "$source_sha" = "$EXPECTED_SHA" ] || {
        log_error "Bundled module hash mismatch: ${source_sha:-unavailable}"
        return 1
    }
    compile_module "$MODULE_SRC" >/dev/null 2>&1 || {
        log_error "Bundled module does not compile with printer Python."
        return 1
    }

    new_backup_dir || { log_error "Could not create GC backup."; return 1; }
    cp "$MODULE_SRC" "$MODULE_DST" || return 1
    chmod 0644 "$MODULE_DST"
    cat > "$GC_CFG" <<'EOF'
# K2 Pro Combo: upstream Klipper garbage-collection optimization.
# It freezes long-lived startup objects after Klipper becomes ready. Normal
# garbage collection remains active for objects allocated later.
[garbage_collection]
EOF
    chmod 0644 "$GC_CFG"
    add_include_to_printer_cfg "k2pro_garbage_collection.cfg" || return 1
    compile_module "$MODULE_DST" >/dev/null 2>&1 || return 1
    mark_installed klipper_gc

    cat > "$BACKUP_DIR/INSTALL_MANIFEST.txt" <<EOF
installed_at=$(date -Iseconds 2>/dev/null || date)
module_sha256=$source_sha
module=$MODULE_DST
config=$GC_CFG
include=[include k2pro_garbage_collection.cfg]
EOF
    sync
    log_success "Klipper Garbage Collection installed. Backup: $BACKUP_DIR"
    restart_klipper force
}

remove_gc() {
    [ -f "$MAIN_CFG" ] || { log_error "printer.cfg missing: $MAIN_CFG"; return 1; }
    new_backup_dir || { log_error "Could not create GC removal backup."; return 1; }
    remove_include_from_printer_cfg "k2pro_garbage_collection.cfg"
    rm -f "$GC_CFG"

    if [ -f "$MODULE_DST" ]; then
        installed_sha="$(file_sha "$MODULE_DST")"
        if [ "$installed_sha" = "$EXPECTED_SHA" ]; then
            rm -f "$MODULE_DST"
        else
            log_warn "A different garbage_collection.py is installed; preserving it."
        fi
    fi
    mark_removed klipper_gc
    sync
    log_success "Helper-managed Klipper Garbage Collection removed. Backup: $BACKUP_DIR"
    restart_klipper force
}

case "$1" in
    install) install_gc ;;
    status) status_gc ;;
    remove) remove_gc ;;
    *) echo "Usage: $0 {install|status|remove}"; exit 2 ;;
esac
