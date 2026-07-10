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

echo ""
echo "Live CFS slot view:"
PYTHONDONTWRITEBYTECODE=1 python3 - << 'PYEOF'
import json
from pathlib import Path

box_path = Path("/mnt/UDISK/creality/userdata/box/material_box_info.json")
map_path = Path("/mnt/UDISK/helper-script/spoolman_cfs_map.json")

try:
    box = json.loads(box_path.read_text(encoding="utf-8"))
    info = (box.get("Material") or {}).get("info") or []
    slots = ((info[0] if info else {}).get("list") or [])
except Exception as exc:
    print("  [WARN] cannot read CFS material_box_info.json: %s" % exc)
    slots = []

try:
    slot_map = json.loads(map_path.read_text(encoding="utf-8"))
    mappings = slot_map.get("slots") or slot_map.get("map")
    if not isinstance(mappings, dict):
        mappings = {key: value for key, value in slot_map.items() if key.startswith("T") and isinstance(value, int)}
    enabled = slot_map.get("enabled", None)
except Exception:
    mappings = {}
    enabled = None

if enabled is not None:
    print("  map_enabled=%s" % enabled)
if not slots:
    print("  no live T1 slots found")
else:
    print("  %-4s %-8s %-7s %-18s %-46s %-9s %-7s" % ("Slot", "Spool", "Remain", "Brand", "Name", "Color", "RFID"))
    for index, slot in enumerate(slots):
        slot_name = "T1%s" % "ABCD"[index]
        spool_id = mappings.get(slot_name, "-")
        print("  %-4s %-8s %-7s %-18s %-46s %-9s %-7s" % (
            slot_name,
            spool_id,
            str(slot.get("remainLen", "")),
            str(slot.get("brand", ""))[:18],
            str(slot.get("name", ""))[:46],
            str(slot.get("color", "")),
            str(slot.get("rfid", "")),
        ))
PYEOF

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
