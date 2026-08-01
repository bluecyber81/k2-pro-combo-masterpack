#!/bin/sh
# Strictly read-only K2 Pro motor-controller status wrapper.
set -u

SCRIPT_DIR=${K2_HELPER_DIR:-/mnt/UDISK/helper-script}
WORKER="$SCRIPT_DIR/scripts/motor_controller_report.py"

if [ ! -f "$WORKER" ]; then
    echo "[FAIL] Motor-controller report worker is missing: $WORKER"
    exit 2
fi

exec python3 -B "$WORKER" "$@"
