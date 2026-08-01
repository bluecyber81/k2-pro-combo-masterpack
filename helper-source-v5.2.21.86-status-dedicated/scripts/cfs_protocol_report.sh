#!/bin/sh
# cfs_protocol_report.sh - read-only CFS protocol, slot and database report

SCRIPT_DIR=/mnt/UDISK/helper-script
CONFIG_DIR=/mnt/UDISK/printer_data/config
BOX_DIR=/mnt/UDISK/creality/userdata/box

MODE="${1:-report}"

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required for the CFS protocol report."
    exit 1
fi

case "$MODE" in
    --compact|compact|summary)
        ;;
    *)
        echo "== CFS protocol and slot report =="
        echo "Safety: read-only only. This does not load, unload, extrude, cut, refresh or send raw BOX/RS485 commands."
        ;;
esac

python3 - "$MODE" "$CONFIG_DIR" "$BOX_DIR" << 'PYEOF'
import json
import pathlib
import sys
import urllib.request

mode = sys.argv[1]
config_dir = pathlib.Path(sys.argv[2])
box_dir = pathlib.Path(sys.argv[3])
compact = mode in ("--compact", "compact", "summary")


def load_json(path):
    try:
        return json.loads(path.read_text(errors="replace"))
    except Exception:
        return None


def fetch_moonraker(path):
    with urllib.request.urlopen("http://127.0.0.1:7125" + path, timeout=6) as response:
        return json.loads(response.read().decode()).get("result", {}).get("status", {})


def profile_candidates(material_id):
    material_id = str(material_id or "")
    plain = material_id.lstrip("0") or material_id
    candidates = {material_id, material_id.zfill(6), material_id.zfill(5), plain, plain.zfill(5), plain.zfill(6)}
    if len(material_id) == 6:
        candidates.add(material_id[1:])
        candidates.add(material_id[1:].zfill(5))
    return {c for c in candidates if c}


def profile_label(base):
    brand = str(base.get("brand") or "").strip()
    name = str(base.get("name") or "").strip()
    material = str(base.get("meterialType") or base.get("materialType") or "").strip()
    temp = ""
    if base.get("minTemp") and base.get("maxTemp"):
        temp = "%s-%sC" % (base.get("minTemp"), base.get("maxTemp"))
    label = "/".join(v for v in (brand, name) if v)
    if material:
        label = (label + " " + material).strip()
    if temp:
        label = (label + " " + temp).strip()
    return label or "(unnamed profile)"


def operation_mode(value):
    labels = {
        0: (
            "idle",
            "load/unload engine idle; stock Moonraker does not expose steady-feed arming",
        ),
        1: ("preloading", "preload operation is active"),
        2: ("printing_transition", "printing transition is active and may be brief"),
        3: ("wrapping", "rewind/wrapping operation is active"),
        4: ("error", "CFS operation engine reports an error state"),
        5: ("test", "CFS operation engine is in a service/test state"),
    }
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None, "unknown", "operation mode is unavailable or not numeric"
    if not number.is_integer():
        return None, "unknown", "operation mode is not an integer"
    code = int(number)
    label, note = labels.get(
        code,
        ("unknown", "operation mode is not documented by the known CFS protocol"),
    )
    return code, label, note


status_error = None
try:
    status = fetch_moonraker("/printer/objects/query?box&filament_rack&filament_switch_sensor%20filament_sensor")
except Exception as exc:
    status = {}
    status_error = str(exc)

box = status.get("box", {}) or {}
t1 = box.get("T1", {}) or {}
same_material = box.get("same_material", []) or []
mode_raw = t1.get("mode")
mode_code, mode_label, mode_note = operation_mode(mode_raw)
try:
    selected_index = int(box.get("filament"))
except (TypeError, ValueError):
    selected_index = 0
selected_slot = "T1" + "ABCD"[selected_index - 1] if 1 <= selected_index <= 4 else "unknown"

db = load_json(box_dir / "material_database.json") or {}
profiles_by_id = {}
for item in db.get("result", {}).get("list", []) or []:
    base = item.get("base", {}) or {}
    base_id = str(base.get("id") or "")
    if not base_id:
        continue
    profiles_by_id.setdefault(base_id, []).append(base)
    profiles_by_id.setdefault(base_id.zfill(6), []).append(base)

same_by_slot = {}
for entry in same_material:
    try:
        material_id, color, slots, label = entry[:4]
    except Exception:
        continue
    for slot in slots or []:
        same_by_slot[str(slot)] = {
            "material_id": str(material_id),
            "color": str(color),
            "label": str(label or ""),
        }

material_ids = [str(v) for v in (t1.get("material_type", []) or [])]
colors = [str(v) for v in (t1.get("color_value", []) or [])]
remain = [str(v) for v in (t1.get("remain_len", []) or [])]
venders = [str(v) for v in (t1.get("vender", []) or [])]

slots = ["T1A", "T1B", "T1C", "T1D"]
slot_rows = []
blank_labels = 0
missing_db = 0
ambiguous_db = 0

for idx, slot in enumerate(slots):
    material_id = material_ids[idx] if idx < len(material_ids) else ""
    color = colors[idx] if idx < len(colors) else ""
    remain_len = remain[idx] if idx < len(remain) else ""
    vender = venders[idx] if idx < len(venders) else ""
    same = same_by_slot.get(slot, {})
    live_label = same.get("label", "")
    active_material = material_id not in ("", "-1", "None", "none", "null")
    matches = []
    if active_material:
        seen = set()
        for candidate in profile_candidates(material_id):
            for base in profiles_by_id.get(candidate, []):
                key = (base.get("id"), base.get("brand"), base.get("name"), base.get("meterialType"))
                if key not in seen:
                    seen.add(key)
                    matches.append(base)
    if not active_material:
        db_label = "(empty/no material)"
    elif not matches:
        missing_db += 1
        db_label = "(no matching DB profile)"
    elif len(matches) > 1:
        ambiguous_db += 1
        db_label = "AMBIGUOUS: " + " | ".join(profile_label(base) for base in matches[:3])
    else:
        db_label = profile_label(matches[0])
    if active_material and not live_label and matches:
        blank_labels += 1
    slot_rows.append({
        "slot": slot,
        "material_id": material_id,
        "color": color,
        "remain": remain_len,
        "vender": vender,
        "live_label": live_label,
        "db_label": db_label,
    })

box_cfg = (config_dir / "box.cfg").read_text(errors="replace") if (config_dir / "box.cfg").exists() else ""
gcode_macro_cfg = (config_dir / "gcode_macro.cfg").read_text(errors="replace") if (config_dir / "gcode_macro.cfg").exists() else ""
official_m8200 = "[gcode_macro M8200]" in box_cfg and "CR_BOX_EXTRUDE" in box_cfg
stock_start_end = "BOX_START_PRINT" in gcode_macro_cfg and "BOX_END_PRINT" in gcode_macro_cfg

if compact:
    print(
        "CFS_PROTOCOL_SUMMARY|status_error=%s|state=%s|t1_state=%s|t1_version=%s|slot_count=%d|"
        "operation_mode=%s|operation_label=%s|blank_live_labels=%d|db_missing=%d|"
        "db_ambiguous=%d|official_m8200=%s|stock_start_end=%s"
        % (
            bool(status_error),
            box.get("state"),
            t1.get("state"),
            t1.get("version"),
            len(slot_rows),
            mode_code,
            mode_label,
            blank_labels,
            missing_db,
            ambiguous_db,
            official_m8200,
            stock_start_end,
        )
    )
    if status_error:
        print("CFS_PROTOCOL_STATUS_ERROR|%s" % status_error)
    sys.exit(1 if status_error else 0)

if status_error:
    print("STATUS_ERROR|%s" % status_error)

print("Bus:")
print("- device: /dev/ttyS5")
print("- baud: 230400")
print("- stack: serial_485 -> auto_addr -> box_wrapper -> filament_rack_wrapper")
print("- frame: head 0xF7, addr, len, status, function, data, crc8(poly 0x07)")
print("- material-box addresses: 0x01..0x04, shown as T1A..T4D")
print("")

print("Live CFS:")
print("BOX_STATE|%s" % box.get("state"))
print("BOX_ENABLE|%s" % box.get("enable"))
print("BOX_AUTO_REFILL|%s" % box.get("auto_refill"))
print("T1_STATE|%s" % t1.get("state"))
print("T1_VERSION|%s" % t1.get("version"))
print("T1_SN|%s" % t1.get("sn"))
print("T1_OPERATION_MODE|raw=%s|code=%s|label=%s" % (mode_raw, mode_code, mode_label))
print("T1_OPERATION_MODE_NOTE|%s" % mode_note)
print("CFS_SELECTED_SLOT|%s|semantics=material_selection_not_feed_arm" % selected_slot)
print("")

print("Slots:")
for row in slot_rows:
    note = "OK"
    if row["db_label"].startswith("(no matching"):
        note = "DB_MISSING"
    elif row["db_label"].startswith("AMBIGUOUS"):
        note = "DB_AMBIGUOUS"
    elif row["material_id"] not in ("", "-1") and not row["live_label"]:
        note = "LIVE_LABEL_EMPTY_DB_OK"
    print(
        "%s|id=%s|color=%s|remain=%s|live_label=%s|db=%s|%s"
        % (
            row["slot"],
            row["material_id"],
            row["color"],
            row["remain"],
            row["live_label"] or "(empty)",
            row["db_label"],
            note,
        )
    )
print("")

print("Creality command model:")
print("OFFICIAL_M8200_PATH|%s" % official_m8200)
print("STOCK_START_END_CFS_PATH|%s" % stock_start_end)
print("- M8200 P/C/R/L/W/F/O maps to CR_BOX_* inside stock box.cfg.")
print("- T/toolchange and Creality UI should use the stock CFS path.")
print("- START_PRINT/END_PRINT must keep BOX_START_PRINT, BOX_END and BOX_END_PRINT.")
print("")

print("State semantics:")
print("- T1 mode is the load/unload operation engine, not a persistent feed-enabled flag.")
print("- Mode 0 is normal after steady feed has been armed; it does not prove that feed is off.")
print("- Mode 2 is a short printing transition and may disappear before a UI samples it.")
print("- The selected slot identifies material/UI selection, not the hidden steady-feed arm state.")
print("- Buffer-arm state exists on RS485 but is not exposed by the stock Moonraker box object.")
print("")

print("Risk policy:")
print("- Safe: Moonraker object reads, CFS DB JSON validation, log scans, G-code scans.")
print("- Avoid blindly: BOX_SEND_DATA, BOX_INFO_REFRESH, BOX_SET_PRE_LOADING, BOX_LOAD_MATERIAL, BOX_EXTRUDE_MATERIAL, BOX_RETRUDE_MATERIAL, raw _CFS_LOAD/_CFS_UNLOAD.")
print("- Reason: those commands can send RS485 commands or move/heat/cut/extrude material.")
print("")

print(
    "CFS_PROTOCOL_SUMMARY|status_error=%s|state=%s|t1_state=%s|t1_version=%s|slot_count=%d|"
    "operation_mode=%s|operation_label=%s|blank_live_labels=%d|db_missing=%d|"
    "db_ambiguous=%d|official_m8200=%s|stock_start_end=%s"
    % (
        bool(status_error),
        box.get("state"),
        t1.get("state"),
        t1.get("version"),
        len(slot_rows),
        mode_code,
        mode_label,
        blank_labels,
        missing_db,
        ambiguous_db,
        official_m8200,
        stock_start_end,
    )
)

if blank_labels:
    print("NOTE: One or more live CFS labels are empty while the DB profile exists. This is a Creality live-state/display quirk; do not use BOX_INFO_REFRESH just to force it.")
if ambiguous_db:
    print("NOTE: One or more material IDs map to multiple DB profiles. This is common for generic/custom profiles sharing Creality IDs; choose the intended slicer/CFS profile explicitly.")
if status_error:
    print("ACTION: Live CFS status was unavailable. Re-run on the printer with Moonraker running before making CFS DB repair decisions.")
elif missing_db:
    print("ACTION: A live CFS material ID is missing from the database. Run helper.sh --cfs-db-repair, then recheck.")
else:
    print("ACTION: No CFS DB repair is required from this report.")

sys.exit(1 if status_error else 0)
PYEOF
