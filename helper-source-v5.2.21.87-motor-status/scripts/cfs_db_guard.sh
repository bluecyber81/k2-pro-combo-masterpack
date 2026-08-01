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
PID_FILE=/tmp/cfs_db_guard_watch.pid
LOG_FILE=/tmp/cfs_db_guard.log

watch_running() {
    [ -s "$PID_FILE" ] || return 1
    pid=$(cat "$PID_FILE" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

start_watch() {
    delay="${1:-0}"
    if watch_running; then
        echo "cfs_db_guard watcher already running pid=$(cat "$PID_FILE")"
        return 0
    fi
    rm -f "$PID_FILE"
    PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --watch --delay "$delay" --interval 300 >> "$LOG_FILE" 2>&1 &
    pid=$!
    echo "$pid" > "$PID_FILE"
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        echo "cfs_db_guard watcher started pid=$pid delay=${delay}s"
        return 0
    fi
    rm -f "$PID_FILE"
    echo "cfs_db_guard watcher failed to start"
    return 1
}

stop_watch() {
    if watch_running; then
        pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null || true
        echo "cfs_db_guard watcher stopped pid=$pid"
    fi
    rm -f "$PID_FILE"
}

case "$1" in
    start|watch)
        start_watch 0
        ;;
    repair)
        PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --repair
        ;;
    boot)
        start_watch 120
        ;;
    stop)
        stop_watch
        ;;
    restart)
        stop_watch
        start_watch 0
        ;;
    status|check)
        if watch_running; then
            echo "cfs_db_guard watcher running pid=$(cat "$PID_FILE")"
        else
            echo "cfs_db_guard watcher not running"
        fi
        PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --check
        ;;
    archive-status)
        PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --archive-status
        ;;
    rotate-backups)
        keep="${2:-12}"
        PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --rotate-backups --keep "$keep"
        ;;
    *)
        echo "Usage: $0 {start|watch|stop|restart|repair|boot|status|check|archive-status|rotate-backups [keep]}"
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
    "$SERVICE" start || return 1
    log_success "CFS material DB guard installed; cold-idle watcher is running."
}

remove_guard() {
    [ -x "$SERVICE" ] && "$SERVICE" stop
    unpatch_rc_local
    rm -f "$SERVICE" "$INIT_SERVICE"
    mark_removed "cfs_db_guard"
    log_success "CFS material DB guard removed. Database files were kept."
}

case "$1" in
    install) install_guard ;;
    remove) remove_guard ;;
    repair) PYTHONDONTWRITEBYTECODE=1 python3 -B "$GUARD_PY" --repair ;;
    start|watch|stop|restart) [ -x "$SERVICE" ] && "$SERVICE" "$1" ;;
    check|status) [ -x "$SERVICE" ] && "$SERVICE" status || PYTHONDONTWRITEBYTECODE=1 python3 -B "$GUARD_PY" --check ;;
    archive-status) PYTHONDONTWRITEBYTECODE=1 python3 -B "$GUARD_PY" --archive-status ;;
    rotate-backups) PYTHONDONTWRITEBYTECODE=1 python3 -B "$GUARD_PY" --rotate-backups --keep "${2:-12}" ;;
    *) echo "Usage: $0 [install|remove|start|watch|stop|restart|repair|check|status|archive-status|rotate-backups [keep]]" ;;
esac
