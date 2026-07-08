#!/bin/sh
# spoolman_cfs_status.sh - read-only Spoolman/CFS slot-map status for K2 Pro Combo

SCRIPT_DIR=/mnt/UDISK/helper-script

echo ""
echo "Spoolman CFS sync status"
echo "Status probe is read-only. Full-control commands below can actively set Spoolman active spools."
echo ""

if [ ! -x "$SCRIPT_DIR/spoolman_cfs_sync.py" ]; then
    echo "[WARN] worker missing or not executable: $SCRIPT_DIR/spoolman_cfs_sync.py"
    exit 0
fi

PYTHONDONTWRITEBYTECODE=1 python3 -B "$SCRIPT_DIR/spoolman_cfs_sync.py" --status > /tmp/spoolman_cfs_status.out 2>/tmp/spoolman_cfs_status.err
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "[WARN] status probe failed:"
    sed 's/^/  /' /tmp/spoolman_cfs_status.err 2>/dev/null || true
else
    sed 's/^/  /' /tmp/spoolman_cfs_status.out
fi
rm -f /tmp/spoolman_cfs_status.err /tmp/spoolman_cfs_status.out 2>/dev/null

service=""
[ -x /etc/init.d/S99spoolman_cfs_sync ] && service=/etc/init.d/S99spoolman_cfs_sync
[ -z "$service" ] && [ -x /etc/rc.d/S99spoolman_cfs_sync ] && service=/etc/rc.d/S99spoolman_cfs_sync
if [ -n "$service" ]; then
    echo ""
    echo "Service:"
    "$service" status 2>/dev/null || true
else
    echo ""
    echo "Service: not installed"
fi

echo ""
echo "Full-control setup:"
echo "  $SCRIPT_DIR/helper.sh --spoolman-cfs-map-wizard"
echo "  $SCRIPT_DIR/helper.sh --spoolman-cfs-sync-once"
echo "  $SCRIPT_DIR/helper.sh --spoolman-cfs-restart"
echo ""
