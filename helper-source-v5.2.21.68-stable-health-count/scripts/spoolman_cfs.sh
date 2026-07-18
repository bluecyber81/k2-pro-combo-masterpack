#!/bin/sh
# spoolman_cfs.sh - install/control/configure Spoolman CFS slot sync for K2 Pro Combo
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

WORKER="$SCRIPT_DIR/spoolman_cfs_sync.py"
SERVICE_INIT=/etc/init.d/S99spoolman_cfs_sync
SERVICE_RC=/etc/rc.d/S99spoolman_cfs_sync
MAP="$SCRIPT_DIR/spoolman_cfs_map.json"
EXAMPLE="$SCRIPT_DIR/spoolman_cfs_map.example.json"
PY=/usr/bin/python3
[ -x /opt/bin/python3 ] && PY=/opt/bin/python3

write_service() {
    target="$1"
    cat > "$target" <<'EOSVC'
#!/bin/sh
HELPER=/mnt/UDISK/helper-script
PY=/usr/bin/python3
[ -x /opt/bin/python3 ] && PY=/opt/bin/python3
WORKER=$HELPER/spoolman_cfs_sync.py
PID=/tmp/spoolman_cfs_sync.pid
LOG=/tmp/spoolman_cfs_sync.log

is_running() {
    [ -f "$PID" ] || return 1
    pid="$(cat "$PID" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

start_service() {
    if is_running; then
        echo "running: $(cat "$PID")"
        return 0
    fi
    if [ ! -x "$WORKER" ]; then
        echo "worker missing or not executable: $WORKER"
        return 1
    fi
    PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --daemon >/dev/null 2>> "$LOG" &
    echo $! > "$PID"
    sleep 1
    if is_running; then
        echo "started: $(cat "$PID")"
        return 0
    fi
    echo "failed to start; see $LOG"
    return 1
}

stop_service() {
    if is_running; then
        kill "$(cat "$PID")" 2>/dev/null || true
        sleep 1
    fi
    rm -f "$PID"
    echo "stopped"
}

status_service() {
    if is_running; then
        echo "running: $(cat "$PID")"
    else
        echo "stopped"
    fi
    [ -f "$LOG" ] && tail -n 20 "$LOG" 2>/dev/null || true
}

case "$1" in
    start|boot) start_service ;;
    stop) stop_service ;;
    restart) stop_service; start_service ;;
    status) status_service ;;
    *) echo "Usage: $0 {start|stop|restart|status|boot}"; exit 2 ;;
esac
EOSVC
    chmod 755 "$target"
}

restart_service_if_present() {
    if [ -x "$SERVICE_INIT" ]; then
        "$SERVICE_INIT" restart || true
    elif [ -x "$SERVICE_RC" ]; then
        "$SERVICE_RC" restart || true
    fi
}

install_spoolman_cfs() {
    echo ""
    log_info "Installing Spoolman CFS sync service and tools..."
    if [ ! -f "$WORKER" ]; then
        log_error "Missing worker: $WORKER"
        return 1
    fi
    chmod 755 "$WORKER" 2>/dev/null || true
    [ -f "$EXAMPLE" ] && chmod 644 "$EXAMPLE" 2>/dev/null || true
    write_service "$SERVICE_INIT" || return 1
    mkdir -p /etc/rc.d 2>/dev/null || true
    cp -a "$SERVICE_INIT" "$SERVICE_RC" 2>/dev/null || true
    chmod 755 "$SERVICE_RC" 2>/dev/null || true
    mark_installed "spoolman_cfs_sync"
    log_success "Spoolman CFS sync installed."
    if [ -f "$MAP" ]; then
        log_info "Active map exists: $MAP"
        restart_service_if_present
    else
        log_warn "No active map yet. Run: helper.sh --spoolman-cfs-map-wizard"
    fi
}

remove_spoolman_cfs() {
    printf "%b\n" "${YELLOW}Remove Spoolman CFS sync service? Worker/map files are kept unless you delete them manually.${NC}"
    printf "Continue? [y/n]: "
    read confirm
    [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || { log_info "Cancelled."; return 0; }
    [ -x "$SERVICE_INIT" ] && "$SERVICE_INIT" stop 2>/dev/null || true
    [ -x "$SERVICE_RC" ] && "$SERVICE_RC" stop 2>/dev/null || true
    rm -f "$SERVICE_INIT" "$SERVICE_RC" /tmp/spoolman_cfs_sync.pid 2>/dev/null
    mark_removed "spoolman_cfs_sync"
    log_success "Spoolman CFS sync service removed."
}

status_spoolman_cfs() {
    sh "$SCRIPT_DIR/scripts/spoolman_cfs_status.sh"
}

case "$1" in
    install) install_spoolman_cfs ;;
    remove) remove_spoolman_cfs ;;
    restart) restart_service_if_present ;;
    status|map-status) status_spoolman_cfs ;;
    wizard|map-wizard) PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --wizard ;;
    list|list-spools) PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --list-spools ;;
    enable) PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --enable-map ; restart_service_if_present ;;
    disable) PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --disable-map ; restart_service_if_present ;;
    once|sync-once) PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" ;;
    *) echo "Usage: $0 {install|remove|restart|status|wizard|list|enable|disable|once}"; exit 2 ;;
esac
