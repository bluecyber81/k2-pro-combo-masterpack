#!/bin/sh
# k2pro_protection_guard.sh - read-only F012 firmware/config/recovery gate.

SCRIPT_DIR="${K2_HELPER_DIR:-/mnt/UDISK/helper-script}"
PYTHON="${K2_GUARD_PYTHON:-/usr/bin/python3}"
GUARD="${K2_GUARD_SCRIPT:-$SCRIPT_DIR/scripts/k2pro_protection_guard.py}"

[ -x "$PYTHON" ] || {
    echo "ERROR: python3 not found: $PYTHON"
    exit 1
}
[ -f "$GUARD" ] || {
    echo "ERROR: K2 Pro protection guard missing: $GUARD"
    exit 1
}

mode="${1:-status}"
shift 2>/dev/null || true

case "$mode" in
    status|full)
        exec "$PYTHON" -B "$GUARD" --status "$@"
        ;;
    compact)
        exec "$PYTHON" -B "$GUARD" --status --compact "$@"
        ;;
    firmware)
        exec "$PYTHON" -B "$GUARD" --firmware "$@"
        ;;
    config|drift)
        exec "$PYTHON" -B "$GUARD" --config "$@"
        ;;
    recovery)
        exec "$PYTHON" -B "$GUARD" --recovery "$@"
        ;;
    database|db)
        exec "$PYTHON" -B "$GUARD" --database "$@"
        ;;
    cfs)
        exec "$PYTHON" -B "$GUARD" --cfs "$@"
        ;;
    check-ota)
        image="${1:-}"
        expected="${2:-}"
        [ -n "$image" ] || {
            echo "Usage: $0 check-ota IMAGE EXPECTED_SHA256"
            exit 2
        }
        exec "$PYTHON" -B "$GUARD" --check-ota "$image" --expected-sha256 "$expected"
        ;;
    selftest)
        exec "$PYTHON" -B "$GUARD" --selftest
        ;;
    *)
        echo "Usage: $0 {status|compact|firmware|config|recovery|database|cfs|check-ota IMAGE EXPECTED_SHA256|selftest}"
        exit 2
        ;;
esac
