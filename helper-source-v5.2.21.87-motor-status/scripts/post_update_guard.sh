#!/bin/sh
# Passive K2 Pro post-update baseline wrapper.

SCRIPT_DIR="${K2_HELPER_DIR:-/mnt/UDISK/helper-script}"
PY="${K2_POST_UPDATE_PY:-/usr/bin/python3}"
WORKER="${K2_POST_UPDATE_WORKER:-$SCRIPT_DIR/scripts/post_update_guard.py}"

[ -x "$PY" ] || PY=python3
[ -f "$WORKER" ] || {
    echo "POST_UPDATE_GUARD|FAIL|worker missing: $WORKER"
    exit 1
}

case "$1" in
    capture)
        exec "$PY" -B "$WORKER" --capture
        ;;
    status|"")
        exec "$PY" -B "$WORKER" --status
        ;;
    json)
        exec "$PY" -B "$WORKER" --status --json
        ;;
    selftest)
        exec "$PY" -B "$WORKER" --selftest
        ;;
    *)
        echo "Usage: $0 {capture|status|json|selftest}"
        exit 2
        ;;
esac
