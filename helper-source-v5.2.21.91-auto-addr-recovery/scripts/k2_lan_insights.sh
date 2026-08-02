#!/bin/sh
# Fixed GET-only K2 LAN WebSocket diagnostics.

SCRIPT_DIR="${K2_HELPER_DIR:-/mnt/UDISK/helper-script}"
PY="${K2_LAN_PY:-/usr/bin/python3}"
WORKER="${K2_LAN_WORKER:-$SCRIPT_DIR/scripts/k2_lan_insights.py}"

[ -x "$PY" ] || {
    echo "K2_LAN_API|FAIL|python3 not found: $PY"
    exit 1
}
[ -f "$WORKER" ] || {
    echo "K2_LAN_API|FAIL|worker not found: $WORKER"
    exit 1
}

case "${1:-status}" in
    status)
        shift
        PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" "$@"
        ;;
    materials)
        shift
        PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --include-materials "$@"
        ;;
    selftest)
        PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --selftest
        ;;
    *)
        echo "Usage: $0 {status|materials|selftest}"
        exit 2
        ;;
esac
