#!/bin/sh
# Install and operate the passive CFS Safe Tools monitor.

SCRIPT_DIR="${K2_HELPER_DIR:-/mnt/UDISK/helper-script}"
. "$SCRIPT_DIR/scripts/system.sh"

WORKER="${CFS_SAFE_WORKER:-$SCRIPT_DIR/scripts/cfs_safe_tools.py}"
SERVICE_SOURCE="${CFS_SAFE_SERVICE_SOURCE:-$SCRIPT_DIR/scripts/S97cfs_safe_monitor}"
SERVICE_INIT="${CFS_SAFE_SERVICE_INIT:-/etc/init.d/S97cfs_safe_monitor}"
SERVICE_RC="${CFS_SAFE_SERVICE_RC:-/etc/rc.d/S97cfs_safe_monitor}"
RC_LOCAL="${CFS_SAFE_RC_LOCAL:-/etc/rc.local}"
BOOT_COMMENT="# K2 CFS Safe Tools passive monitor"
BOOT_LINE="${CFS_SAFE_BOOT_LINE:-/etc/rc.d/S97cfs_safe_monitor boot &}"
BACKUP_DIR="${CFS_SAFE_BACKUP_DIR:-/mnt/UDISK/printer_data/backups/k2pro_helper}"
PY="${CFS_SAFE_PY:-/usr/bin/python3}"

service_path() {
    [ -x "$SERVICE_INIT" ] && { echo "$SERVICE_INIT"; return; }
    [ -x "$SERVICE_RC" ] && { echo "$SERVICE_RC"; return; }
    echo "$SERVICE_INIT"
}

backup_rc_local() {
    [ -f "$RC_LOCAL" ] || { log_error "Missing $RC_LOCAL"; return 1; }
    mkdir -p "$BACKUP_DIR" || return 1
    RC_LOCAL_BACKUP="$BACKUP_DIR/rc.local.before_cfs_safe_tools_$(date +%Y%m%d_%H%M%S)_$$"
    cp -p "$RC_LOCAL" "$RC_LOCAL_BACKUP" || {
        log_error "Could not back up $RC_LOCAL"
        return 1
    }
}

rewrite_boot_hook() {
    action="$1"
    tmp="${RC_LOCAL}.cfs-safe.$$"
    cp -p "$RC_LOCAL" "$tmp" || return 1
    if [ "$action" = "add" ]; then
        awk -v comment="$BOOT_COMMENT" -v line="$BOOT_LINE" '
            $0 == comment || $0 == line { next }
            $0 == "exit 0" && !added { print comment; print line; added=1 }
            { print }
            END { if (!added) { print comment; print line } }
        ' "$RC_LOCAL" > "$tmp" || { rm -f "$tmp"; return 1; }
    else
        awk -v comment="$BOOT_COMMENT" -v line="$BOOT_LINE" '
            $0 == comment || $0 == line { next }
            { print }
        ' "$RC_LOCAL" > "$tmp" || { rm -f "$tmp"; return 1; }
    fi
    sh -n "$tmp" || { rm -f "$tmp"; log_error "Generated rc.local failed shell syntax validation"; return 1; }
    mv -f "$tmp" "$RC_LOCAL" || return 1
}

ensure_boot_hook() {
    if [ -f "$RC_LOCAL" ] && grep -Fqx "$BOOT_LINE" "$RC_LOCAL" 2>/dev/null; then
        log_info "CFS Safe Tools boot hook already present."
        return 0
    fi
    backup_rc_local || return 1
    rewrite_boot_hook add || return 1
    grep -Fqx "$BOOT_LINE" "$RC_LOCAL" || { log_error "CFS Safe Tools boot hook validation failed"; return 1; }
    log_success "Installed CFS Safe Tools boot hook. Backup: $RC_LOCAL_BACKUP"
}

remove_boot_hook() {
    if ! { grep -Fqx "$BOOT_COMMENT" "$RC_LOCAL" 2>/dev/null || grep -Fqx "$BOOT_LINE" "$RC_LOCAL" 2>/dev/null; }; then
        return 0
    fi
    backup_rc_local || return 1
    rewrite_boot_hook remove || return 1
    if grep -Fqx "$BOOT_LINE" "$RC_LOCAL" 2>/dev/null; then
        log_error "CFS Safe Tools boot hook removal validation failed"
        return 1
    fi
    log_success "Removed CFS Safe Tools boot hook. Backup: $RC_LOCAL_BACKUP"
}

install_tools() {
    [ -f "$WORKER" ] || { log_error "Missing $WORKER"; return 1; }
    [ -f "$SERVICE_SOURCE" ] || { log_error "Missing $SERVICE_SOURCE"; return 1; }
    [ -x "$PY" ] || { log_error "python3 not found: $PY"; return 1; }
    chmod 755 "$WORKER" "$SERVICE_SOURCE"
    PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --selftest || return 1
    mkdir -p "$SCRIPT_DIR/state" "$SCRIPT_DIR/reports" /etc/init.d /etc/rc.d
    cp -a "$SERVICE_SOURCE" "$SERVICE_INIT" || return 1
    cp -a "$SERVICE_SOURCE" "$SERVICE_RC" || return 1
    chmod 755 "$SERVICE_INIT" "$SERVICE_RC"
    ensure_boot_hook || return 1
    "$SERVICE_INIT" restart || return 1
    mark_installed "cfs_safe_tools"
    log_success "CFS Safe Tools installed. Passive monitor is running."
}

remove_tools() {
    service="$(service_path)"
    [ -x "$service" ] && "$service" stop >/dev/null 2>&1 || true
    remove_boot_hook || return 1
    rm -f "$SERVICE_INIT" "$SERVICE_RC"
    mark_removed "cfs_safe_tools"
    log_success "CFS Safe Tools service removed. Reports and worker were kept."
}

status_tools() {
    result=0
    service="$(service_path)"
    if [ -x "$service" ]; then
        "$service" status || result=1
    else
        echo "service: not installed"
        result=1
    fi
    if grep -Fqx "$BOOT_LINE" "$RC_LOCAL" 2>/dev/null; then
        echo "BOOT_HOOK|present|$BOOT_LINE"
    else
        echo "BOOT_HOOK|missing|$BOOT_LINE"
        result=1
    fi
    PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --status || result=1
    if [ -f "$SCRIPT_DIR/state/cfs_safe_tools_state.json" ]; then
        echo "STATE|$SCRIPT_DIR/state/cfs_safe_tools_state.json"
    fi
    return "$result"
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
