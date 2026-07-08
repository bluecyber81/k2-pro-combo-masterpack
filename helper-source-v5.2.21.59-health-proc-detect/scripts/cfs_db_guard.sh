#!/bin/sh
# cfs_db_guard.sh - repair durable K2 Pro CFS custom material profiles.

SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

GUARD_PY="$SCRIPT_DIR/scripts/cfs_db_guard.py"
PATCH_DIR="$SCRIPT_DIR/files/cfs_db_patch"
SERVICE=/etc/rc.d/S98cfs_db_guard
INIT_SERVICE=/etc/init.d/S98cfs_db_guard
RC_LOCAL=/etc/rc.local

write_service() {
    cat > "$SERVICE" << 'SHELL'
#!/bin/sh
HELPER=/mnt/UDISK/helper-script
PY="$HELPER/scripts/cfs_db_guard.py"

case "$1" in
    start|repair)
        PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --repair
        ;;
    boot)
        PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --boot --delay 120 >> /tmp/cfs_db_guard.log 2>&1 &
        echo "cfs_db_guard scheduled after boot"
        ;;
    status|check)
        PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --check
        ;;
    *)
        echo "Usage: $0 {start|repair|boot|status|check}"
        exit 2
        ;;
esac
SHELL
    chmod +x "$SERVICE"
    cp "$SERVICE" "$INIT_SERVICE"
}

patch_rc_local() {
    [ -f "$RC_LOCAL" ] || printf '#!/bin/sh\nexit 0\n' > "$RC_LOCAL"
    ts=$(date +%Y%m%d_%H%M%S)
    cp -a "$RC_LOCAL" "$SCRIPT_DIR/.rc.local.cfs_db_guard.bak.$ts" 2>/dev/null
    python3 - << 'PYEOF'
from pathlib import Path
path = Path('/etc/rc.local')
content = path.read_text() if path.exists() else '#!/bin/sh\nexit 0\n'
block = '# K2 CFS material DB guard\n/etc/rc.d/S98cfs_db_guard boot &\n'
content = content.replace('\n# K2 CFS material DB guard\n/etc/rc.d/S98cfs_db_guard boot &\n', '\n')
if 'exit 0' in content:
    content = content.replace('exit 0', block + 'exit 0', 1)
else:
    content = content.rstrip() + '\n' + block + 'exit 0\n'
path.write_text(content)
PYEOF
    chmod +x "$RC_LOCAL" 2>/dev/null || true
}

unpatch_rc_local() {
    [ -f "$RC_LOCAL" ] || return 0
    python3 - << 'PYEOF'
from pathlib import Path
path = Path('/etc/rc.local')
content = path.read_text()
content = content.replace('\n# K2 CFS material DB guard\n/etc/rc.d/S98cfs_db_guard boot &\n', '\n')
content = content.replace('# K2 CFS material DB guard\n/etc/rc.d/S98cfs_db_guard boot &\n', '')
path.write_text(content)
PYEOF
}

install_guard() {
    [ -f "$GUARD_PY" ] || { log_error "Missing $GUARD_PY"; return 1; }
    [ -d "$PATCH_DIR" ] || { log_error "Missing patch snapshot $PATCH_DIR"; return 1; }
    command -v python3 >/dev/null 2>&1 || { log_error "python3 not found"; return 1; }
    chmod +x "$GUARD_PY"
    write_service
    patch_rc_local
    "$SERVICE" repair || return 1
    mark_installed "cfs_db_guard"
    log_success "CFS material DB guard installed and repaired current DB if needed."
}

remove_guard() {
    unpatch_rc_local
    rm -f "$SERVICE" "$INIT_SERVICE"
    mark_removed "cfs_db_guard"
    log_success "CFS material DB guard removed. Database files were kept."
}

case "$1" in
    install) install_guard ;;
    remove) remove_guard ;;
    repair) PYTHONDONTWRITEBYTECODE=1 python3 -B "$GUARD_PY" --repair ;;
    check|status) [ -x "$SERVICE" ] && "$SERVICE" status || PYTHONDONTWRITEBYTECODE=1 python3 -B "$GUARD_PY" --check ;;
    *) echo "Usage: $0 [install|remove|repair|check|status]" ;;
esac
