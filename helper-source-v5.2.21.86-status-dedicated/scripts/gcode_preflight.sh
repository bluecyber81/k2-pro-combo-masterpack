#!/bin/sh
# Read-only K2 Pro Combo G-code preflight wrapper.

SCRIPT_DIR="${K2_HELPER_DIR:-/mnt/UDISK/helper-script}"
PY="${K2_GCODE_PREFLIGHT_PY:-/usr/bin/python3}"
WORKER="${K2_GCODE_PREFLIGHT_WORKER:-$SCRIPT_DIR/scripts/gcode_preflight.py}"

[ -x "$PY" ] || PY=python3
[ -f "$WORKER" ] || {
    echo "GCODE_PREFLIGHT|FAIL|worker missing: $WORKER"
    exit 1
}

case "$1" in
    file)
        [ -n "$2" ] || {
            echo "Usage: $0 file PATH"
            exit 2
        }
        exec "$PY" -B "$WORKER" --file "$2"
        ;;
    recent|"")
        exec "$PY" -B "$WORKER" --recent "${2:-5}"
        ;;
    selftest)
        exec "$PY" -B "$WORKER" --selftest
        ;;
    *)
        echo "Usage: $0 {recent [count]|file PATH|selftest}"
        exit 2
        ;;
esac
