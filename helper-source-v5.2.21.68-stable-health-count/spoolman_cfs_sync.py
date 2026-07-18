#!/usr/bin/env python3
"""Sync active Spoolman spool from the currently active Creality CFS slot.

v5.2.21.68-stable-health-count keeps the interactive map wizard, map
enable/disable, spool listing and one-shot sync support without exposing the
raw CFS/G-code expert-control paths from the full package.
"""
import argparse
import json
import os
import pathlib
import re
import time
import urllib.error
import urllib.request
from typing import Any, Dict, Iterable, List, Optional, Tuple

MOONRAKER = os.environ.get("MOONRAKER_URL", "http://127.0.0.1:7125").rstrip("/")
MAP_PATH = os.environ.get("CFS_SPOOL_MAP", "/mnt/UDISK/helper-script/spoolman_cfs_map.json")
EXAMPLE_MAP_PATH = "/mnt/UDISK/helper-script/spoolman_cfs_map.example.json"
REMAIN_PATH = "/mnt/UDISK/creality/userdata/box/remain_material_data.json"
LOG_PATH = "/tmp/spoolman_cfs_sync.log"
MOONRAKER_CONF = "/mnt/UDISK/printer_data/config/moonraker.conf"
SLOTS = ["T1A", "T1B", "T1C", "T1D"]
BUILD_LABEL = "5.2.21.68-stable-health-count"


def log(message: str) -> None:
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"{stamp} {message}"
    print(line, flush=True)
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError:
        pass


def positive_int_env(name: str, default: int) -> int:
    try:
        value = int(os.environ.get(name, str(default)))
    except (TypeError, ValueError):
        return default
    return value if value > 0 else default


def clean_color(value: Any) -> str:
    text = "".join(ch for ch in str(value or "") if ch in "0123456789abcdefABCDEF")
    if len(text) > 6:
        text = text[-6:]
    return text.upper()


def read_json_file(path: str, default: Any = None) -> Any:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return default


def write_json_file(path: str, data: Dict[str, Any]) -> None:
    target = pathlib.Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        backup = target.with_name(target.name + ".bak." + time.strftime("%Y%m%d_%H%M%S"))
        backup.write_bytes(target.read_bytes())
        print(f"Backed up existing map to {backup}")
    tmp = target.with_name(target.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(target)
    os.chmod(target, 0o644)


def http_json(base: str, path: str, method: str = "GET", payload: Any = None, timeout: int = 5) -> Any:
    data = None
    headers = {"User-Agent": f"k2pro-helper-spoolman-cfs/{BUILD_LABEL}"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def moonraker_json(path: str, method: str = "GET", payload: Any = None, timeout: int = 5) -> Any:
    return http_json(MOONRAKER, path, method=method, payload=payload, timeout=timeout)


def detect_slot(box_status: Dict[str, Any]) -> Optional[str]:
    remain = read_json_file(REMAIN_PATH, {}).get("remain_material", {})
    remain_type = str(remain.get("type") or "")
    remain_color = clean_color(remain.get("color"))
    for row in box_status.get("same_material", []) or []:
        if len(row) < 3:
            continue
        material_type = str(row[0])
        color = clean_color(row[1])
        slots = row[2] or []
        if material_type == remain_type and color == remain_color and slots:
            slot = str(slots[0])
            if slot in SLOTS:
                return slot

    value = box_status.get("filament")
    try:
        idx = int(value)
    except Exception:
        idx = 0
    if 1 <= idx <= 4:
        return "T1" + "ABCD"[idx - 1]
    return None


def normalize_spool_id(value: Any) -> Optional[int]:
    if value in (None, "", 0, "0", False):
        return None
    try:
        parsed = int(str(value).strip())
    except Exception:
        return None
    return parsed if parsed > 0 else None


def map_state() -> Dict[str, Any]:
    mapping = read_json_file(MAP_PATH, {}) or {}
    values = [mapping.get(slot) for slot in SLOTS]
    ids_1_to_4 = bool(mapping) and all(str(value) == str(index) for index, value in enumerate(values, 1))
    missing = [slot for slot in SLOTS if normalize_spool_id(mapping.get(slot)) is None]
    enabled = mapping.get("enabled")
    if not mapping:
        state = "missing"
    elif enabled is False:
        state = "disabled"
    elif missing:
        state = "incomplete"
    else:
        state = "ready"
    return {
        "state": state,
        "enabled": enabled,
        "ids_1_to_4": ids_1_to_4,
        "missing_slots": missing,
        "slots": {slot: mapping.get(slot) for slot in SLOTS},
        "raw": mapping,
    }


def map_config_blocker() -> Optional[str]:
    state = map_state()
    if state["state"] == "missing":
        return (
            "spool map missing or empty. Run helper.sh --spoolman-cfs-map-wizard "
            "or create spoolman_cfs_map.json with real T1A/T1B/T1C/T1D spool IDs"
        )
    if state["state"] == "disabled":
        return "spool map disabled; run helper.sh --spoolman-cfs-map-wizard or --spoolman-cfs-map-enable"
    if state["state"] == "incomplete":
        return "spool map incomplete; missing real Spoolman spool IDs for " + ",".join(state["missing_slots"])
    return None


def print_status() -> None:
    state = map_state()
    print("MAP_PATH=" + MAP_PATH)
    print("EXAMPLE_MAP_PATH=" + EXAMPLE_MAP_PATH)
    print("MAP_STATE=" + state["state"])
    print("MAP_ENABLED=" + str(state["enabled"]))
    if state["enabled"] is None and state["state"] == "ready":
        print("MAP_LEGACY_ENABLED=True")
        print("MAP_LEGACY_NOTE=legacy map has no enabled field but all T1 slots have positive Spoolman IDs")
    print("MAP_IDS_1_TO_4=" + str(state["ids_1_to_4"]))
    print("MAP_IDS_1_TO_4_NOTE=IDs 1-4 can be real Spoolman spool IDs; this is informational only")
    print("MAP_MISSING_SLOTS=" + (",".join(state["missing_slots"]) if state["missing_slots"] else "none"))
    for slot, value in state["slots"].items():
        print(f"MAP_SLOT_{slot}={value}")
    blocker = map_config_blocker()
    print("MAP_BLOCKER=" + (blocker or "none"))
    try:
        status = moonraker_json("/server/spoolman/status", timeout=3).get("result", {})
        print("SPOOLMAN_CONNECTED=" + str(status.get("spoolman_connected")))
        print("SPOOLMAN_ACTIVE_SPOOL=" + str(status.get("spool_id")))
    except Exception as exc:
        print("SPOOLMAN_STATUS_ERROR=" + str(exc))
    try:
        box = moonraker_json("/printer/objects/query?box", timeout=3).get("result", {}).get("status", {}).get("box", {})
        for slot, data in live_slot_metadata(box).items():
            print(f"CFS_SLOT_{slot}_MATERIAL=" + data.get("cfs_filament_id", ""))
            print(f"CFS_SLOT_{slot}_COLOR=" + data.get("cfs_color", ""))
            print(f"CFS_SLOT_{slot}_REMAIN_PERCENT=" + data.get("cfs_remain_percent", ""))
    except Exception as exc:
        print("CFS_SLOT_STATUS_ERROR=" + str(exc))


def parse_moonraker_spoolman_url() -> Optional[str]:
    env_url = os.environ.get("SPOOLMAN_URL")
    if env_url:
        return env_url.rstrip("/")
    try:
        content = pathlib.Path(MOONRAKER_CONF).read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None
    in_section = False
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            in_section = line.lower() == "[spoolman]"
            continue
        if not in_section:
            continue
        m = re.match(r"(server|url|spoolman_url)\s*[:=]\s*(\S+)", line, re.I)
        if m:
            return m.group(2).rstrip("/")
    return None


def flatten_spools(data: Any) -> List[Dict[str, Any]]:
    if isinstance(data, dict):
        for key in ("items", "data", "result", "spools"):
            if isinstance(data.get(key), list):
                return [x for x in data[key] if isinstance(x, dict)]
        if "id" in data:
            return [data]
    if isinstance(data, list):
        return [x for x in data if isinstance(x, dict)]
    return []


def spoolman_direct_json(path: str, method: str = "GET", payload: Any = None, timeout: int = 6) -> Any:
    base = parse_moonraker_spoolman_url() or "http://127.0.0.1:7912"
    return http_json(base, path, method=method, payload=payload, timeout=timeout)


def list_spools() -> List[Dict[str, Any]]:
    errors = []
    for path in ("/api/v1/spool", "/api/v1/spool?limit=500", "/spool"):
        try:
            data = spoolman_direct_json(path)
            spools = flatten_spools(data)
            if spools:
                return spools
        except Exception as exc:
            errors.append(f"{path}: {exc}")
    if errors:
        print("SPOOL_LIST_WARNING=" + " | ".join(errors[:3]))
    return []


def spool_label(spool: Dict[str, Any]) -> str:
    filament = spool.get("filament") or {}
    vendor = filament.get("vendor") or filament.get("manufacturer") or {}
    vendor_name = vendor.get("name") if isinstance(vendor, dict) else vendor
    parts = [
        f"id={spool.get('id')}",
        f"name={spool.get('name') or spool.get('display_name') or ''}",
        f"material={filament.get('material') or spool.get('material') or ''}",
        f"filament={filament.get('name') or ''}",
        f"vendor={vendor_name or ''}",
        f"color=#{clean_color(filament.get('color_hex') or spool.get('color_hex'))}",
    ]
    return " | ".join(parts)


def print_spools() -> List[Dict[str, Any]]:
    spools = list_spools()
    if not spools:
        print("No spools could be listed through the direct Spoolman API. You can still enter IDs manually.")
        return []
    print("Available Spoolman spools:")
    for spool in sorted(spools, key=lambda item: normalize_spool_id(item.get("id")) or 0)[:200]:
        print("  " + spool_label(spool))
    if len(spools) > 200:
        print(f"  ... {len(spools)-200} more not shown")
    return spools


def encode_extra_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return json.dumps(str(value))


def slot_index(slot: str) -> int:
    return SLOTS.index(slot)


def live_slot_metadata(box_status: Dict[str, Any]) -> Dict[str, Dict[str, str]]:
    t1 = box_status.get("T1") or {}
    materials = t1.get("material_type") or []
    colors = t1.get("color_value") or []
    remains = t1.get("remain_len") or []
    result: Dict[str, Dict[str, str]] = {}
    for slot in SLOTS:
        idx = slot_index(slot)
        material = str(materials[idx]) if idx < len(materials) else ""
        raw_color = str(colors[idx]) if idx < len(colors) else ""
        remain = str(remains[idx]) if idx < len(remains) else ""
        if material in ("", "-1", "None") or raw_color in ("", "-1", "None"):
            continue
        color = clean_color(raw_color)
        marker = f"K2PRO-CFS-{slot}-{material}-{color}"
        data = {
            "cfs_marker": encode_extra_value(marker),
            "cfs_box": encode_extra_value("T1"),
            "cfs_slot": encode_extra_value(slot),
            "cfs_filament_id": encode_extra_value(material),
            "cfs_color": encode_extra_value(color),
            "auto_synced": encode_extra_value(True),
            "source": encode_extra_value("creality_cfs_live_slot_metadata"),
        }
        if remain not in ("", "-1", "None"):
            data["cfs_remain_percent"] = str(remain)
        result[slot] = data
    return result


def sync_spool_extra(spool_id: int, updates: Dict[str, str]) -> bool:
    spool = spoolman_direct_json(f"/api/v1/spool/{spool_id}", timeout=6)
    extra = dict(spool.get("extra") or {})
    changed = False
    for key, value in updates.items():
        if extra.get(key) != value:
            extra[key] = value
            changed = True
    if not changed:
        return False
    spoolman_direct_json(f"/api/v1/spool/{spool_id}", method="PATCH", payload={"extra": extra}, timeout=8)
    return True


def sync_slot_metadata(mapping: Dict[str, Any], box_status: Dict[str, Any]) -> str:
    metadata = live_slot_metadata(box_status)
    changed: List[str] = []
    checked = 0
    for slot in SLOTS:
        spool_id = normalize_spool_id(mapping.get(slot))
        updates = metadata.get(slot)
        if spool_id is None or not updates:
            continue
        checked += 1
        if sync_spool_extra(spool_id, updates):
            changed.append(f"{slot}:{spool_id}")
    if changed:
        return "CFS metadata updated " + ",".join(changed)
    if checked:
        return f"CFS metadata current for {checked} mapped slots"
    return "no live CFS metadata to sync"


def prompt_spool_id(slot: str) -> int:
    while True:
        value = input(f"Spoolman spool ID for {slot}: ").strip()
        parsed = normalize_spool_id(value)
        if parsed is not None:
            return parsed
        print("Please enter a positive numeric Spoolman spool ID.")


def run_wizard() -> None:
    print("K2 Pro Combo Spoolman CFS map wizard")
    print("This creates/enables spoolman_cfs_map.json with real T1A/T1B/T1C/T1D spool IDs.")
    print("")
    print_spools()
    print("")
    mapping = {
        "enabled": True,
        "_generated_by": "k2pro-helper-v5.2.21.68-stable-health-count",
        "_generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    for slot in SLOTS:
        mapping[slot] = prompt_spool_id(slot)
    write_json_file(MAP_PATH, mapping)
    print(f"Wrote active map: {MAP_PATH}")
    print_status()


def set_map_enabled(enabled: bool) -> None:
    mapping = read_json_file(MAP_PATH, {}) or {}
    if not mapping:
        raise SystemExit("Map missing. Run --wizard first.")
    mapping["enabled"] = bool(enabled)
    mapping["_last_enabled_change"] = time.strftime("%Y-%m-%d %H:%M:%S")
    write_json_file(MAP_PATH, mapping)
    print(("Enabled" if enabled else "Disabled") + f" map: {MAP_PATH}")
    print_status()


def sync_once(sync_metadata: bool = True) -> Tuple[bool, str]:
    mapping = read_json_file(MAP_PATH, {}) or {}
    blocker = map_config_blocker()
    if blocker:
        return False, blocker

    query = moonraker_json("/printer/objects/query?box&print_stats")
    box = query.get("result", {}).get("status", {}).get("box", {})
    metadata_message = ""
    if sync_metadata:
        try:
            metadata_message = sync_slot_metadata(mapping, box)
        except Exception as exc:
            metadata_message = "CFS metadata sync warning: " + str(exc)
    slot = detect_slot(box)
    if not slot:
        message = "no active CFS slot detected"
        if metadata_message:
            message += "; " + metadata_message
        return False, message

    spool_id = normalize_spool_id(mapping.get(slot))
    if spool_id is None:
        message = f"slot {slot} has no mapped Spoolman spool"
        if metadata_message:
            message += "; " + metadata_message
        return False, message

    status = moonraker_json("/server/spoolman/status").get("result", {})
    current = normalize_spool_id(status.get("spool_id"))
    if current == spool_id:
        message = f"slot {slot} already active as spool {spool_id}"
        if metadata_message:
            message += "; " + metadata_message
        return True, message

    moonraker_json("/server/spoolman/spool_id", method="POST", payload={"spool_id": spool_id})
    message = f"set active spool to {spool_id} for CFS slot {slot}"
    if metadata_message:
        message += "; " + metadata_message
    return True, message


def moonraker_ready() -> Tuple[bool, str]:
    info = moonraker_json("/server/info", timeout=3).get("result", {})
    if not info.get("klippy_connected"):
        return False, "Klippy not connected"
    if info.get("klippy_state") != "ready":
        return False, f"Klippy state {info.get('klippy_state')}"
    failed = info.get("failed_components") or []
    if failed:
        return False, "failed components: " + ",".join(map(str, failed))

    status = moonraker_json("/server/spoolman/status", timeout=3).get("result", {})
    if not status.get("spoolman_connected"):
        return False, "Spoolman not connected"
    return True, "Moonraker and Spoolman ready"


def wait_for_ready(max_wait: int = 180) -> Tuple[bool, str]:
    # The K2 initially boots with a 2020 wall clock and jumps forward after
    # time sync. A monotonic clock keeps that jump from ending this wait early.
    start = time.monotonic()
    last_message = ""
    while time.monotonic() - start < max_wait:
        try:
            ok, message = moonraker_ready()
            if ok:
                return True, message
            last_message = message
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
            last_message = str(exc)
        time.sleep(5)
    return False, last_message or "readiness timeout"


def main() -> None:
    parser = argparse.ArgumentParser(description="Sync active Spoolman spool from Creality CFS slot state.")
    parser.add_argument("--daemon", action="store_true")
    parser.add_argument("--interval", type=int, default=int(os.environ.get("CFS_SYNC_INTERVAL", "15")))
    parser.add_argument("--status", action="store_true", help="Read-only map and Moonraker Spoolman status.")
    parser.add_argument("--wizard", action="store_true", help="Interactive wizard to create/enable the CFS slot map.")
    parser.add_argument("--list-spools", action="store_true", help="List spools from the direct Spoolman API when reachable.")
    parser.add_argument("--enable-map", action="store_true", help="Set enabled=true in the active map.")
    parser.add_argument("--disable-map", action="store_true", help="Set enabled=false in the active map.")
    args = parser.parse_args()

    if args.status:
        print_status()
        return
    if args.list_spools:
        print_spools()
        return
    if args.wizard:
        run_wizard()
        return
    if args.enable_map:
        set_map_enabled(True)
        return
    if args.disable_map:
        set_map_enabled(False)
        return

    log("Spoolman CFS sync started")
    blocker = map_config_blocker()
    if blocker:
        log("WARN " + blocker)
        return
    heartbeat_interval = max(
        positive_int_env("CFS_SYNC_HEARTBEAT", 1800),
        max(args.interval, 5),
    )
    metadata_interval = max(
        positive_int_env("CFS_METADATA_SYNC_INTERVAL", 300),
        max(args.interval, 5),
    )
    warn_repeat_interval = max(
        positive_int_env("CFS_SYNC_WARN_REPEAT", 300),
        max(args.interval, 5),
    )
    last_log_signature = None
    last_log_time = 0.0
    last_metadata_sync = 0.0
    if args.daemon:
        ok, message = wait_for_ready()
        log(("OK " if ok else "WARN ") + "startup readiness: " + message)
        log(
            "INFO daemon repeat log compression active "
            f"(ok heartbeat={heartbeat_interval}s, warn repeat={warn_repeat_interval}s)"
        )
    while True:
        try:
            now = time.monotonic()
            sync_metadata = (not args.daemon) or (now - last_metadata_sync) >= metadata_interval
            ok, message = sync_once(sync_metadata=sync_metadata)
            if sync_metadata:
                last_metadata_sync = now
            line = ("OK " if ok else "WARN ") + message
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
            ok = False
            line = f"WARN sync failed: {exc}"

        now = time.monotonic()
        repeat_interval = heartbeat_interval if ok else warn_repeat_interval
        should_log = (
            not args.daemon
            or line != last_log_signature
            or (now - last_log_time) >= repeat_interval
        )
        if should_log:
            suffix = ""
            if args.daemon and line == last_log_signature:
                suffix = " (heartbeat)" if ok else " (still failing)"
            log(line + suffix)
            last_log_signature = line
            last_log_time = now
        if not args.daemon:
            break
        time.sleep(max(args.interval, 5))


if __name__ == "__main__":
    main()
