#!/bin/sh
# Install and operate the passive CFS Safe Tools monitor.

SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

WORKER="$SCRIPT_DIR/scripts/cfs_safe_tools.py"
SERVICE_SOURCE="$SCRIPT_DIR/scripts/S97cfs_safe_monitor"
SERVICE_INIT=/etc/init.d/S97cfs_safe_monitor
SERVICE_RC=/etc/rc.d/S97cfs_safe_monitor
PY=/usr/bin/python3

service_path() {
    [ -x "$SERVICE_INIT" ] && { echo "$SERVICE_INIT"; return; }
    [ -x "$SERVICE_RC" ] && { echo "$SERVICE_RC"; return; }
    echo "$SERVICE_INIT"
}

install_tools() {
    [ -f "$WORKER" ] || { log_error "Missing $WORKER"; return 1; }
    [ -f "$SERVICE_SOURCE" ] || { log_error "Missing $SERVICE_SOURCE"; return 1; }
    command -v python3 >/dev/null 2>&1 || { log_error "python3 not found"; return 1; }
    chmod 755 "$WORKER" "$SERVICE_SOURCE"
    PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --selftest || return 1
    mkdir -p "$SCRIPT_DIR/state" "$SCRIPT_DIR/reports" /etc/init.d /etc/rc.d
    cp -a "$SERVICE_SOURCE" "$SERVICE_INIT" || return 1
    cp -a "$SERVICE_SOURCE" "$SERVICE_RC" || return 1
    chmod 755 "$SERVICE_INIT" "$SERVICE_RC"
    "$SERVICE_INIT" restart || return 1
    mark_installed "cfs_safe_tools"
    log_success "CFS Safe Tools installed. Passive monitor is running."
}

remove_tools() {
    service="$(service_path)"
    [ -x "$service" ] && "$service" stop >/dev/null 2>&1 || true
    rm -f "$SERVICE_INIT" "$SERVICE_RC"
    mark_removed "cfs_safe_tools"
    log_success "CFS Safe Tools service removed. Reports and worker were kept."
}

status_tools() {
    service="$(service_path)"
    if [ -x "$service" ]; then
        "$service" status || true
    else
        echo "service: not installed"
    fi
    PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --status
    if [ -f "$SCRIPT_DIR/state/cfs_safe_tools_state.json" ]; then
        echo "STATE|$SCRIPT_DIR/state/cfs_safe_tools_state.json"
    fi
}

case "$1" in
    install) install_tools ;;
    remove) remove_tools ;;
    start|stop|restart)
        service="$(service_path)"
        [ -x "$service" ] || { log_error "CFS Safe Tools service is not installed"; exit 1; }
        "$service" "$1"
        ;;
    status) status_tools ;;
    events) PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --events --event-limit "${2:-20}" ;;
    gcode) PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --gcode-report ;;
    selftest) PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --selftest ;;
    *) echo "Usage: $0 {install|remove|start|stop|restart|status|events [limit]|gcode|selftest}"; exit 2 ;;
esac
