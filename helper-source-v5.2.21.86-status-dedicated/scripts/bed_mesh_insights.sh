#!/bin/sh
# Read-only analysis of the currently stored Moonraker bed mesh.

SCRIPT_DIR="${K2_HELPER_DIR:-/mnt/UDISK/helper-script}"
PY="${BED_MESH_PY:-/usr/bin/python3}"
WORKER="${BED_MESH_WORKER:-$SCRIPT_DIR/scripts/bed_mesh_insights.py}"

[ -x "$PY" ] || {
    echo "BED_MESH|FAIL|python3 not found: $PY"
    exit 1
}
[ -f "$WORKER" ] || {
    echo "BED_MESH|FAIL|worker not found: $WORKER"
    exit 1
}

case "${1:-status}" in
    status)
        shift
        PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" "$@"
        ;;
    selftest)
        PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$WORKER" --selftest
        ;;
    *)
        echo "Usage: $0 {status|selftest}"
        exit 2
        ;;
esac
