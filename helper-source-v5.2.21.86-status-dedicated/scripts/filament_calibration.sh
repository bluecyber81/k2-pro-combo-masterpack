#!/bin/sh
# Read-only Auto Pressure Advance / Flow Ratio result diagnostics.

SCRIPT_DIR="${K2_HELPER_DIR:-/mnt/UDISK/helper-script}"
PY="$SCRIPT_DIR/scripts/filament_calibration.py"

if [ ! -f "$PY" ]; then
    echo "FILAMENT_CALIBRATION|ERROR|worker missing: $PY"
    exit 1
fi

case "${1:-status}" in
    status)
        PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --status
        ;;
    json)
        PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --json
        ;;
    history)
        PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --status --archives "${2:-2}"
        ;;
    report)
        PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --write-report "${2:-$SCRIPT_DIR/reports/filament_calibration_status.json}"
        ;;
    selftest)
        PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" --selftest
        ;;
    *)
        echo "Usage: $0 {status|json|history [0..6]|report [PATH]|selftest}"
        exit 2
        ;;
esac
