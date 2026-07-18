#!/usr/bin/env python3
"""Passive CFS diagnostics and event statistics for the K2 Pro Combo.

This module only reads Moonraker, Creality JSON files and logs. It never
sends G-code, CFS/BOX commands, HTTP writes, or serial data.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path


MOONRAKER = os.environ.get("MOONRAKER_URL", "http://127.0.0.1:7125").rstrip("/")
BOX_DIR = Path(os.environ.get("CFS_BOX_DIR", "/mnt/UDISK/creality/userdata/box"))
HELPER_DIR = Path(os.environ.get("CFS_HELPER_DIR", "/mnt/UDISK/helper-script"))
LOG_PATH = Path(os.environ.get("CFS_KLIPPY_LOG", "/mnt/UDISK/printer_data/logs/klippy.log"))
GCODE_DIR = Path(os.environ.get("CFS_GCODE_DIR", "/mnt/UDISK/printer_data/gcodes"))
MAP_PATH = HELPER_DIR / "spoolman_cfs_map.json"
REMAIN_PATH = BOX_DIR / "remain_material_data.json"
DB_PATH = BOX_DIR / "material_database.json"
STATE_DIR = HELPER_DIR / "state"
REPORT_DIR = HELPER_DIR / "reports"
DEFAULT_STATE_FILE = STATE_DIR / "cfs_safe_tools_state.json"
DEFAULT_EVENT_FILE = REPORT_DIR / "cfs_safe_events.jsonl"
SLOTS = ("T1A", "T1B", "T1C", "T1D")
BUILD = "cfs-safe-tools-1.1"


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return default


def http_get_json(path, timeout=5):
    request = urllib.request.Request(
        MOONRAKER + path,
        headers={"User-Agent": "k2pro-" + BUILD},
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8", errors="replace"))


def clean_color(value):
    text = "".join(ch for ch in str(value or "") if ch in "0123456789abcdefABCDEF")
    return text[-6:].upper() if text else ""


def as_number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def normalize_spool_id(value):
    try:
        parsed = int(str(value).strip())
    except (TypeError, ValueError):
        return None
    return parsed if parsed > 0 else None


def detect_active_slot(box):
    remain = (read_json(REMAIN_PATH, {}) or {}).get("remain_material", {}) or {}
    remain_type = str(remain.get("type") or "")
    remain_color = clean_color(remain.get("color"))
    for row in box.get("same_material", []) or []:
        if len(row) < 3:
            continue
        material_type, color, slots = str(row[0]), clean_color(row[1]), row[2] or []
        if material_type == remain_type and color == remain_color and slots:
            slot = str(slots[0])
            if slot in SLOTS:
                return slot
    try:
        index = int(box.get("filament"))
    except (TypeError, ValueError):
        index = 0
    return "T1" + "ABCD"[index - 1] if 1 <= index <= 4 else None


def profile_candidates(material_id):
    material_id = str(material_id or "")
    plain = material_id.lstrip("0") or material_id
    values = {
        material_id,
        material_id.zfill(5),
        material_id.zfill(6),
        plain,
        plain.zfill(5),
        plain.zfill(6),
    }
    if len(material_id) == 6:
        values.add(material_id[1:])
    return {value for value in values if value}


def database_status(box):
    database = read_json(DB_PATH, {}) or {}
    entries = database.get("result", {}).get("list", []) or []
    profile_ids = set()
    profile_labels = {}
    for entry in entries:
        base = entry.get("base", {}) or {}
        profile_id = str(base.get("id") or "")
        if not profile_id:
            continue
        profile_ids.add(profile_id)
        profile_ids.add(profile_id.zfill(6))
        profile_labels[profile_id] = "/".join(
            value for value in (str(base.get("brand") or ""), str(base.get("name") or "")) if value
        )

    t1 = box.get("T1", {}) or {}
    live_ids = [str(value) for value in (t1.get("material_type", []) or [])]
    live_ids = [value for value in live_ids if value not in ("", "-1", "None", "none")]
    missing = []
    for material_id in live_ids:
        if not (profile_candidates(material_id) & profile_ids):
            missing.append(material_id)

    custom = {}
    for profile_id in ("90001", "90002"):
        custom[profile_id] = profile_labels.get(profile_id) or profile_labels.get(profile_id.zfill(6))
    return {
        "profile_count": len(entries),
        "live_ids": live_ids,
        "missing_live_ids": missing,
        "custom_profiles": custom,
        "material_option_present": (BOX_DIR / "material_option.json").is_file(),
    }


def map_status():
    data = read_json(MAP_PATH, {}) or {}
    mapping = data.get("slots") or data.get("map")
    if not isinstance(mapping, dict):
        mapping = {slot: data.get(slot) for slot in SLOTS}
    normalized = {slot: normalize_spool_id(mapping.get(slot)) for slot in SLOTS}
    return {
        "enabled": data.get("enabled", True) is not False,
        "slots": normalized,
        "missing": [slot for slot, spool_id in normalized.items() if spool_id is None],
    }


def tail_text(path, byte_count=524288):
    try:
        with Path(path).open("rb") as handle:
            handle.seek(0, 2)
            size = handle.tell()
            handle.seek(max(0, size - byte_count), 0)
            return handle.read().decode("utf-8", errors="ignore")
    except OSError:
        return ""


def rs485_status():
    text = tail_text(LOG_PATH)
    severe_patterns = (
        "Internal error on command:BOX",
        "No active exception to reraise",
        "key60",
        "key831",
    )
    return {
        "timeouts": len(re.findall(r"cmd_485_send_data_with_response timeout", text, re.I)),
        "buf_len": len(re.findall(r"buf_len\s*=\s*0x", text, re.I)),
        "unknown_frames": len(re.findall(r"Serial_485: got .*?#name': '#unknown'", text)),
        "severe": sum(text.lower().count(pattern.lower()) for pattern in severe_patterns),
    }


def live_status():
    query = http_get_json(
        "/printer/objects/query?box&filament_rack&filament_switch_sensor%20filament_sensor&print_stats",
        timeout=6,
    )
    status = query.get("result", {}).get("status", {}) or {}
    box = status.get("box", {}) or {}
    try:
        spoolman = http_get_json("/server/spoolman/status", timeout=4).get("result", {}) or {}
    except Exception as exc:
        spoolman = {"spoolman_connected": False, "error": str(exc)}
    return status, box, spoolman


def build_snapshot(humidity_warn=40.0, humidity_fail=60.0):
    status, box, spoolman = live_status()
    t1 = box.get("T1", {}) or {}
    active_slot = detect_active_slot(box)
    mapping = map_status()
    database = database_status(box)
    rs485 = rs485_status()
    humidity = as_number(t1.get("dry_and_humidity"))
    temperature = as_number(t1.get("temperature"))
    sensor = status.get("filament_switch_sensor filament_sensor", {}) or {}
    print_stats = status.get("print_stats", {}) or {}
    active_spool = normalize_spool_id(spoolman.get("spool_id"))
    expected_spool = mapping["slots"].get(active_slot) if active_slot else None

    findings = []

    def finding(level, code, message):
        findings.append({"level": level, "code": code, "message": message})

    if box.get("state") != "connect" or t1.get("state") != "connect":
        finding("FAIL", "CFS_DISCONNECTED", "CFS/BOX is not fully connected")
    else:
        finding("OK", "CFS_CONNECTED", "CFS/BOX and T1 are connected")

    if humidity is None:
        finding("WARN", "HUMIDITY_UNKNOWN", "CFS humidity is unavailable")
    elif humidity >= humidity_fail:
        finding("FAIL", "HUMIDITY_HIGH", "CFS humidity is %.0f%%" % humidity)
    elif humidity >= humidity_warn:
        finding("WARN", "HUMIDITY_ELEVATED", "CFS humidity is %.0f%%" % humidity)
    else:
        finding("OK", "HUMIDITY_OK", "CFS humidity is %.0f%%" % humidity)

    if database["missing_live_ids"]:
        finding("WARN", "DB_LIVE_ID_MISSING", "Missing live material IDs: " + ",".join(database["missing_live_ids"]))
    elif not all(database["custom_profiles"].values()) or not database["material_option_present"]:
        finding("WARN", "DB_CUSTOM_DRIFT", "One or more custom CFS database files/profiles are missing")
    else:
        finding("OK", "DB_OK", "Live IDs and custom CFS profiles are present")

    if mapping["missing"] or not mapping["enabled"]:
        finding("WARN", "SPOOL_MAP_INCOMPLETE", "Spoolman slot map is disabled or incomplete")
    elif not spoolman.get("spoolman_connected"):
        finding("WARN", "SPOOLMAN_OFFLINE", "Moonraker is not connected to Spoolman")
    elif active_slot and expected_spool != active_spool:
        finding(
            "WARN",
            "SPOOLMAN_MISMATCH",
            "%s maps to spool %s but active spool is %s" % (active_slot, expected_spool, active_spool),
        )
    else:
        finding("OK", "SPOOLMAN_OK", "CFS slot map and active Spoolman spool agree")

    if rs485["severe"]:
        finding("FAIL", "RS485_SEVERE", "Severe CFS/BOX evidence in recent Klipper log")
    elif rs485["timeouts"] > 80:
        finding("WARN", "RS485_TIMEOUT_HIGH", "Recent RS485 timeout count is %d" % rs485["timeouts"])
    else:
        finding("OK", "RS485_OK", "RS485 polling noise is within the known baseline")

    return {
        "build": BUILD,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "box_state": box.get("state"),
        "t1_state": t1.get("state"),
        "t1_version": t1.get("version"),
        "temperature_c": temperature,
        "humidity_percent": humidity,
        "mode": t1.get("mode"),
        "measuring_wheel": as_number(t1.get("measuring_wheel")),
        "active_slot": active_slot,
        "filament_detected": sensor.get("filament_detected"),
        "print_state": print_stats.get("state"),
        "print_file": print_stats.get("filename"),
        "spoolman_connected": bool(spoolman.get("spoolman_connected")),
        "active_spool": active_spool,
        "expected_spool": expected_spool,
        "map": mapping,
        "database": database,
        "rs485": rs485,
        "findings": findings,
    }


def event_signature(snapshot):
    return {
        key: snapshot.get(key)
        for key in (
            "box_state",
            "t1_state",
            "mode",
            "active_slot",
            "filament_detected",
            "print_state",
            "active_spool",
        )
    }


def build_event_snapshot():
    status, box, spoolman = live_status()
    t1 = box.get("T1", {}) or {}
    sensor = status.get("filament_switch_sensor filament_sensor", {}) or {}
    print_stats = status.get("print_stats", {}) or {}
    return {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "box_state": box.get("state"),
        "t1_state": t1.get("state"),
        "mode": t1.get("mode"),
        "active_slot": detect_active_slot(box),
        "filament_detected": sensor.get("filament_detected"),
        "print_state": print_stats.get("state"),
        "print_file": print_stats.get("filename"),
        "active_spool": normalize_spool_id(spoolman.get("spool_id")),
        "humidity_percent": as_number(t1.get("dry_and_humidity")),
        "measuring_wheel": as_number(t1.get("measuring_wheel")),
    }


def detect_events(previous, current):
    events = []
    for key, current_value in event_signature(current).items():
        previous_value = event_signature(previous).get(key)
        if current_value != previous_value:
            events.append({
                "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
                "field": key,
                "from": previous_value,
                "to": current_value,
            })
    return events


def path_is_within(path, directory):
    try:
        Path(path).resolve().relative_to(Path(directory).resolve())
        return True
    except ValueError:
        return False


def save_state(path, payload):
    target = Path(path)
    if target.parent != Path("/tmp") and not path_is_within(target, STATE_DIR):
        raise ValueError("State files must stay under /tmp or the helper state directory")
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".tmp.%s" % os.getpid())
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(target)


def append_event(path, payload, max_bytes=1048576):
    target = Path(path)
    if not path_is_within(target, REPORT_DIR):
        raise ValueError("Event files must stay under the helper reports directory")
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.stat().st_size > max_bytes:
        with target.open("rb") as handle:
            handle.seek(max(0, target.stat().st_size - max_bytes // 2))
            tail = handle.read()
        newline = tail.find(b"\n")
        if newline >= 0:
            tail = tail[newline + 1 :]
        temporary = target.with_name(target.name + ".rotate.%s" % os.getpid())
        temporary.write_bytes(tail)
        temporary.replace(target)
    with target.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")


def read_events(path, limit=20):
    target = Path(path)
    if not target.exists():
        return []
    rows = []
    for line in tail_text(target, 524288).splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows[-max(1, limit) :]


def new_print_session(current):
    return {
        "file": current.get("print_file"),
        "started": current.get("timestamp"),
        "finished": None,
        "start_slot": current.get("active_slot"),
        "last_slot": current.get("active_slot"),
        "tool_changes": 0,
        "state": current.get("print_state"),
    }


def daemon(interval, full_interval, state_file, event_file, humidity_warn, humidity_fail):
    interval = max(1.0, float(interval))
    full_interval = max(30.0, float(full_interval))
    retry_delay = max(5.0, interval)
    while True:
        try:
            previous = build_event_snapshot()
            last_full = build_snapshot(humidity_warn, humidity_fail)
            break
        except Exception as exc:
            print("DAEMON_WAIT|Moonraker/CFS not ready: %s" % exc, flush=True)
            time.sleep(retry_delay)
    session = new_print_session(previous) if previous.get("print_state") == "printing" else None
    last_session = None
    recent = []
    event_count = 0
    last_full_at = time.monotonic()
    last_write_at = 0.0

    while True:
        try:
            current = build_event_snapshot()
        except Exception as exc:
            print("DAEMON_RETRY|live state unavailable: %s" % exc, flush=True)
            time.sleep(retry_delay)
            continue
        events = detect_events(previous, current)
        if previous.get("print_state") != "printing" and current.get("print_state") == "printing":
            session = new_print_session(current)
        if (
            session
            and current.get("print_state") == "printing"
            and previous.get("active_slot")
            and current.get("active_slot")
            and previous.get("active_slot") != current.get("active_slot")
        ):
            session["tool_changes"] += 1
            session["last_slot"] = current.get("active_slot")
        if session and previous.get("print_state") == "printing" and current.get("print_state") != "printing":
            session["finished"] = current.get("timestamp")
            session["state"] = current.get("print_state")
            completed = {
                "timestamp": current.get("timestamp"),
                "type": "print_session",
                "session": dict(session),
            }
            append_event(event_file, completed)
            recent.append(completed)
            event_count += 1
            last_session = dict(session)
            session = None

        for event in events:
            event["type"] = "transition"
            append_event(event_file, event)
            recent.append(event)
            event_count += 1
        recent = recent[-20:]

        now = time.monotonic()
        if now - last_full_at >= full_interval:
            try:
                last_full = build_snapshot(humidity_warn, humidity_fail)
                last_full_at = now
            except Exception as exc:
                print("DAEMON_RETRY|full status unavailable: %s" % exc, flush=True)
        if events or now - last_write_at >= 60.0:
            payload = {
                "build": BUILD,
                "updated": time.strftime("%Y-%m-%d %H:%M:%S"),
                "current": current,
                "last_full_status": last_full,
                "active_print_session": session,
                "last_print_session": last_session,
                "events_since_start": event_count,
                "recent_events": recent,
            }
            save_state(state_file, payload)
            last_write_at = now
        previous = current
        time.sleep(interval)


def print_events(path, limit):
    rows = read_events(path, limit)
    print("== CFS Safe Tools events ==")
    print("EVENT_SUMMARY|count=%s|file=%s" % (len(rows), path))
    for row in rows:
        if row.get("type") == "print_session":
            session = row.get("session", {})
            print(
                "PRINT_SESSION|%s|file=%s|tool_changes=%s|state=%s"
                % (row.get("timestamp"), session.get("file"), session.get("tool_changes"), session.get("state"))
            )
        else:
            print(
                "EVENT|%s|%s|%s->%s"
                % (row.get("timestamp"), row.get("field"), row.get("from"), row.get("to"))
            )


def watch(seconds, interval, state_file, humidity_warn, humidity_fail):
    started = time.monotonic()
    previous = build_event_snapshot()
    events = []
    samples = 1
    while time.monotonic() - started < seconds:
        time.sleep(interval)
        current = build_event_snapshot()
        events.extend(detect_events(previous, current))
        previous = current
        samples += 1
    final = build_snapshot(humidity_warn, humidity_fail)
    events.extend(detect_events(previous, final))
    payload = {
        "build": BUILD,
        "started": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - (time.monotonic() - started))),
        "finished": time.strftime("%Y-%m-%d %H:%M:%S"),
        "samples": samples,
        "events": events,
        "final": final,
    }
    save_state(state_file, payload)
    return payload


def parse_setting(line, name):
    prefix = "; " + name + " ="
    return line.split("=", 1)[1].strip() if line.startswith(prefix) else None


def read_head_tail_lines(path, head_bytes=32768, tail_bytes=262144):
    with path.open("rb") as handle:
        handle.seek(0, 2)
        size = handle.tell()
        handle.seek(0)
        head = handle.read(min(size, head_bytes))
        tail_start = max(len(head), size - tail_bytes)
        handle.seek(tail_start)
        tail = handle.read()
    return (head + b"\n" + tail).decode("utf-8", errors="ignore").splitlines()


def scan_gcode(path):
    data = {
        "file": path.name,
        "generated_by": "",
        "tool_commands": 0,
        "unique_tools": set(),
        "tool_count": 0,
        "reported_changes": None,
        "filament_g": "",
        "flush_multiplier": "",
        "prime_tower_width": "",
        "flush_into_infill": "",
        "flush_into_support": "",
    }
    tool_re = re.compile(r"^T([0-9]+)(?:\s|$)")
    try:
        # Creality stores the slicer settings and totals at the end. Reading
        # only the file edges avoids a full scan of large multi-color jobs.
        for line in read_head_tail_lines(path):
            stripped = line.strip()
            match = tool_re.match(stripped)
            if match:
                data["tool_commands"] += 1
                data["unique_tools"].add(int(match.group(1)))
            if stripped.startswith("; generated by "):
                data["generated_by"] = stripped[2:]
            elif stripped.startswith("; total filament change ="):
                try:
                    data["reported_changes"] = int(stripped.split("=", 1)[1].strip())
                except ValueError:
                    pass
            elif stripped.startswith("; filament used [g] ="):
                data["filament_g"] = stripped.split("=", 1)[1].strip()
                data["tool_count"] = len([value for value in data["filament_g"].split(",") if value.strip()])
            elif stripped.startswith("; filament_colour =") and not data["tool_count"]:
                colors = stripped.split("=", 1)[1].strip()
                data["tool_count"] = len([value for value in colors.split(",") if value.strip()])
            for name, key in (
                ("flush_multiplier", "flush_multiplier"),
                ("prime_tower_width", "prime_tower_width"),
                ("flush_into_infill", "flush_into_infill"),
                ("flush_into_support", "flush_into_support"),
            ):
                value = parse_setting(stripped, name)
                if value is not None:
                    data[key] = value
    except OSError as exc:
        data["error"] = str(exc)
    data["unique_tools"] = sorted(data["unique_tools"])
    if data["tool_count"] > 1:
        data["unique_tools"] = list(range(data["tool_count"]))
    if data["reported_changes"] is not None:
        data["changes"] = data["reported_changes"]
    elif data["tool_count"] > 1 or len(data["unique_tools"]) > 1:
        data["changes"] = max(0, data["tool_commands"] - 1)
    else:
        data["changes"] = 0
    return data


def gcode_report(limit=10):
    rows = [scan_gcode(path) for path in sorted(GCODE_DIR.glob("*.gcode"))]
    rows.sort(key=lambda row: (row.get("changes", 0), row.get("tool_commands", 0)), reverse=True)
    changed_rows = [row for row in rows if row.get("changes", 0) > 0]
    return {
        "files_scanned": len(rows),
        "multicolor_files": len(changed_rows),
        "top": changed_rows[:limit],
    }


def print_status(snapshot):
    print("== CFS Safe Tools ==")
    print("Safety: passive only; no G-code, CFS/BOX, serial, cutter, heater or motor commands.")
    print("BUILD|%s" % snapshot["build"])
    print(
        "LIVE|box=%s|t1=%s|fw=%s|slot=%s|spool=%s|print=%s|filament=%s"
        % (
            snapshot["box_state"],
            snapshot["t1_state"],
            snapshot["t1_version"],
            snapshot["active_slot"],
            snapshot["active_spool"],
            snapshot["print_state"],
            snapshot["filament_detected"],
        )
    )
    print(
        "ENV|temperature_c=%s|humidity_percent=%s|mode=%s|measuring_wheel=%s"
        % (
            snapshot["temperature_c"],
            snapshot["humidity_percent"],
            snapshot["mode"],
            snapshot["measuring_wheel"],
        )
    )
    database = snapshot["database"]
    print(
        "DB|profiles=%s|live_ids=%s|missing=%s|custom_90001=%s|custom_90002=%s|option=%s"
        % (
            database["profile_count"],
            ",".join(database["live_ids"]),
            ",".join(database["missing_live_ids"]) or "none",
            bool(database["custom_profiles"].get("90001")),
            bool(database["custom_profiles"].get("90002")),
            database["material_option_present"],
        )
    )
    rs485 = snapshot["rs485"]
    print(
        "RS485|timeouts=%s|unknown_frames=%s|buf_len=%s|severe=%s"
        % (rs485["timeouts"], rs485["unknown_frames"], rs485["buf_len"], rs485["severe"])
    )
    counts = {level: 0 for level in ("OK", "WARN", "FAIL")}
    for row in snapshot["findings"]:
        counts[row["level"]] += 1
        print("[%s] %s: %s" % (row["level"], row["code"], row["message"]))
    print("SUMMARY|OK=%d|WARN=%d|FAIL=%d" % (counts["OK"], counts["WARN"], counts["FAIL"]))


def print_gcode_report(report):
    print("== Stored G-code change potential ==")
    print("GCODE_SUMMARY|files=%d|multicolor=%d" % (report["files_scanned"], report["multicolor_files"]))
    for row in report["top"]:
        print(
            "GCODE|changes=%s|tools=%s|flush_multiplier=%s|prime_tower=%s|infill=%s|support=%s|file=%s"
            % (
                row["changes"],
                str(row.get("tool_count") or len(row["unique_tools"]) or 1),
                row["flush_multiplier"] or "unknown",
                row["prime_tower_width"] or "unknown",
                row["flush_into_infill"] or "unknown",
                row["flush_into_support"] or "unknown",
                row["file"],
            )
        )


def selftest():
    failures = []
    source = Path(__file__).read_text(encoding="utf-8", errors="replace")
    forbidden = (
        "BOX_" + "SEND_DATA",
        "BOX_" + "LOAD_MATERIAL",
        "BOX_" + "RETRUDE_MATERIAL",
        "M" + "8200",
        "method=" + '"POST"',
        "subprocess" + ".",
        "os." + "system(",
    )
    for token in forbidden:
        if token in source:
            failures.append("forbidden token present: " + token)

    base = {
        "box_state": "connect",
        "t1_state": "connect",
        "mode": "0",
        "active_slot": "T1A",
        "filament_detected": False,
        "print_state": "standby",
        "active_spool": 1,
    }
    if detect_events(base, dict(base)):
        failures.append("unchanged snapshots created events")
    changed = dict(base)
    changed["active_slot"] = "T1B"
    changed["active_spool"] = 2
    events = detect_events(base, changed)
    if {row["field"] for row in events} != {"active_slot", "active_spool"}:
        failures.append("slot/spool transition detection failed")
    try:
        save_state("/root/cfs_safe_tools_state.json", {})
        failures.append("state path guard failed")
    except ValueError:
        pass
    try:
        save_state(STATE_DIR / "selftest.json", {"ok": True})
        (STATE_DIR / "selftest.json").unlink(missing_ok=True)
    except Exception as exc:
        failures.append("helper state path failed: %s" % exc)

    if failures:
        for failure in failures:
            print("SELFTEST_FAIL|" + failure)
        return 1
    print("SELFTEST_OK|passive source scan, event detection and state path guards passed")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Passive K2 Pro CFS diagnostics")
    parser.add_argument("--status", action="store_true", help="show a live health summary")
    parser.add_argument("--watch", type=int, metavar="SECONDS", help="passively sample live state")
    parser.add_argument("--daemon", action="store_true", help="run passive event monitor")
    parser.add_argument("--interval", type=float, default=2.0, help="watch sample interval")
    parser.add_argument("--full-interval", type=float, default=300.0, help="full daemon health interval")
    parser.add_argument("--state-file", default=str(DEFAULT_STATE_FILE))
    parser.add_argument("--event-file", default=str(DEFAULT_EVENT_FILE))
    parser.add_argument("--events", action="store_true", help="show recent passive events")
    parser.add_argument("--event-limit", type=int, default=20)
    parser.add_argument("--gcode-report", action="store_true", help="analyze stored G-code change counts")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--json", action="store_true", help="emit JSON for status/watch")
    parser.add_argument("--humidity-warn", type=float, default=40.0)
    parser.add_argument("--humidity-fail", type=float, default=60.0)
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    action_selected = args.status or args.watch is not None or args.gcode_report or args.daemon or args.events
    if not action_selected:
        args.status = True

    if args.status:
        snapshot = build_snapshot(args.humidity_warn, args.humidity_fail)
        if args.json:
            print(json.dumps(snapshot, indent=2, sort_keys=True))
        else:
            print_status(snapshot)

    if args.watch is not None:
        if args.watch < 1 or args.watch > 3600:
            parser.error("--watch must be between 1 and 3600 seconds")
        if args.interval < 0.5:
            parser.error("--interval must be at least 0.5 seconds")
        payload = watch(
            args.watch,
            args.interval,
            args.state_file,
            args.humidity_warn,
            args.humidity_fail,
        )
        if args.json:
            print(json.dumps(payload, indent=2, sort_keys=True))
        else:
            print("WATCH|samples=%d|events=%d|state_file=%s" % (payload["samples"], len(payload["events"]), args.state_file))
            for event in payload["events"]:
                print("EVENT|%s|%s|%s->%s" % (event["timestamp"], event["field"], event["from"], event["to"]))

    if args.gcode_report:
        print_gcode_report(gcode_report())
    if args.events:
        print_events(args.event_file, args.event_limit)
    if args.daemon:
        try:
            daemon(
                args.interval,
                args.full_interval,
                args.state_file,
                args.event_file,
                args.humidity_warn,
                args.humidity_fail,
            )
        except KeyboardInterrupt:
            return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
