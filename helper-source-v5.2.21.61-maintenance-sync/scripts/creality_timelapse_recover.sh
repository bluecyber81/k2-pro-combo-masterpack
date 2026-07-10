#!/bin/sh
# creality_timelapse_recover.sh - recover stock Creality raw H264 timelapse files.
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

RECOVER_PY="$SCRIPT_DIR/creality_timelapse_recover.py"
SERVICE=/etc/rc.d/S99timelapse_recover
INIT_SERVICE=/etc/init.d/S99timelapse_recover
RC_LOCAL=/etc/rc.local
PID=/tmp/creality_timelapse_recover.pid
LOG=/tmp/creality_timelapse_recover.log

write_service() {
    cat > "$SERVICE" << 'SHELL'
#!/bin/sh
HELPER=/mnt/UDISK/helper-script
PY="$HELPER/creality_timelapse_recover.py"
PID=/tmp/creality_timelapse_recover.pid
LOG=/tmp/creality_timelapse_recover.log

is_running() {
    [ -f "$PID" ] || return 1
    pid="$(cat "$PID" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

start_service() {
    if is_running; then
        echo "creality_timelapse_recover already running: $(cat "$PID")"
        return 0
    fi
    mkdir -p /tmp
    PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --daemon >> "$LOG" 2>&1 &
    echo $! > "$PID"
    echo "creality_timelapse_recover started: $(cat "$PID")"
}

stop_service() {
    if is_running; then
        kill "$(cat "$PID")" 2>/dev/null
        sleep 1
    fi
    for pid in $(ps | grep "$PY" | grep -- "--daemon" | grep -v grep | awk '{print $1}'); do
        kill "$pid" 2>/dev/null
    done
    rm -f "$PID"
    echo "creality_timelapse_recover stopped"
}

case "$1" in
    start) start_service ;;
    boot) sleep 45; start_service ;;
    stop) stop_service ;;
    restart) stop_service; start_service ;;
    status)
        if is_running; then echo "running: $(cat "$PID")"; else echo "stopped"; fi
        PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --status
        ;;
    once) PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --once --force ;;
    *) echo "Usage: $0 {start|boot|stop|restart|status|once}"; exit 2 ;;
esac
SHELL
    chmod +x "$SERVICE"
    cp "$SERVICE" "$INIT_SERVICE"
}

patch_rc_local() {
    [ -f "$RC_LOCAL" ] || printf '#!/bin/sh\nexit 0\n' > "$RC_LOCAL"
    ts=$(date +%Y%m%d_%H%M%S)
    cp -a "$RC_LOCAL" "$SCRIPT_DIR/.rc.local.timelapse_recover.bak.$ts" 2>/dev/null
    python3 - << 'PYEOF'
from pathlib import Path
path = Path('/etc/rc.local')
content = path.read_text() if path.exists() else '#!/bin/sh\nexit 0\n'
block = '# K2 Creality timelapse recover\n/etc/rc.d/S99timelapse_recover boot &\n'
content = content.replace('\n# K2 Creality timelapse recover\n/etc/rc.d/S99timelapse_recover boot &\n', '\n')
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
content = content.replace('\n# K2 Creality timelapse recover\n/etc/rc.d/S99timelapse_recover boot &\n', '\n')
content = content.replace('# K2 Creality timelapse recover\n/etc/rc.d/S99timelapse_recover boot &\n', '')
path.write_text(content)
PYEOF
}

install_recover() {
    [ -f "$RECOVER_PY" ] || { log_error "Missing $RECOVER_PY"; return 1; }
    command -v python3 >/dev/null 2>&1 || { log_error "python3 not found"; return 1; }
    [ -x /usr/bin/ffmpeg ] || { log_error "/usr/bin/ffmpeg not found"; return 1; }
    mkdir -p /mnt/UDISK/creality/userdata/delay_image/video /mnt/UDISK/creality/userdata/delay_image/cover
    chmod +x "$RECOVER_PY"
    write_service
    patch_rc_local
    "$SERVICE" once || return 1
    "$SERVICE" restart || return 1
    mark_installed "creality_timelapse_recover"
    log_success "Creality timelapse recover installed and running."
}

remove_recover() {
    [ -x "$SERVICE" ] && "$SERVICE" stop 2>/dev/null
    unpatch_rc_local
    rm -f "$SERVICE" "$INIT_SERVICE"
    mark_removed "creality_timelapse_recover"
    log_success "Creality timelapse recover removed. Existing videos were kept."
}

case "$1" in
    install) install_recover ;;
    remove) remove_recover ;;
    status) [ -x "$SERVICE" ] && "$SERVICE" status || PYTHONDONTWRITEBYTECODE=1 python3 -B "$RECOVER_PY" --status ;;
    once) PYTHONDONTWRITEBYTECODE=1 python3 -B "$RECOVER_PY" --once --force ;;
    *) echo "Usage: $0 [install|remove|status|once]" ;;
esac
