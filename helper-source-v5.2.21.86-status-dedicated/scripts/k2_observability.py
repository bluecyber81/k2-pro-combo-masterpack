#!/usr/bin/env python3
"""Passive observability helpers for the Creality K2 Pro Combo.

The module records existing bed meshes and estimates per-slot filament use from
Creality's read-only LAN status counter. It never sends G-code, CFS/BOX, serial,
heater, motor, file-delete, or Spoolman write requests.
"""

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import bed_mesh_insights  # noqa: E402
import k2_lan_insights  # noqa: E402


HELPER_DIR = Path(os.environ.get("K2_OBSERVABILITY_HELPER_DIR", "/mnt/UDISK/helper-script"))
REPORT_DIR = HELPER_DIR / "reports"
WEB_DIR = HELPER_DIR / "web" / "k2-status"
MESH_HISTORY_PATH = REPORT_DIR / "bed_mesh_history.jsonl"
CONSUMPTION_PATH = REPORT_DIR / "cfs_consumption_dry_run.jsonl"
STATUS_JSON_PATH = WEB_DIR / "status.json"
STATE_PATH = HELPER_DIR / "state" / "cfs_safe_tools_state.json"
AI_PREFERENCES_PATH = Path(
    os.environ.get(
        "K2_AI_PREFERENCES_PATH",
        "/mnt/UDISK/creality/userdata/config/user_print_refer.json",
    )
)
NOZZLE_GPIO_PATH = Path(
    os.environ.get("K2_NOZZLE_GPIO_PATH", "/sys/class/gpio/gpio162/value")
)
BUILD = "k2-observability-1.1"
SLOTS = ("T1A", "T1B", "T1C", "T1D")


def now_text():
    return time.strftime("%Y-%m-%d %H:%M:%S")


def as_number(value):
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number != number or number in (float("inf"), float("-inf")):
        return None
    return number


def normalized_flag(value):
    if value is True or value == 1 or str(value).strip().lower() in ("1", "true", "on"):
        return 1
    if value is False or value == 0 or str(value).strip().lower() in ("0", "false", "off"):
        return 0
    return None


def read_ai_preferences(path=AI_PREFERENCES_PATH):
    try:
        payload = json.loads(Path(path).read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError, TypeError):
        payload = {}
    control = payload.get("ai_control")
    if not isinstance(control, dict):
        control = {}

    def pick(name):
        value = control.get(name)
        if value is None:
            value = payload.get(name)
        return normalized_flag(value)

    auto_pa = pick("flowDetect")
    flow_ratio = pick("flowEmDetect")
    return {
        "available": bool(payload),
        "switch": pick("switch"),
        "detection": pick("detection"),
        "pause_print": pick("pausePrint"),
        "first_layer": pick("firstFloor"),
        "waste": pick("wasteSwitch"),
        "auto_pa": auto_pa,
        "flow_ratio": flow_ratio,
        "flow_mode": control.get("flowDetectMode"),
        "calibration_ready": auto_pa == 1 and flow_ratio == 1,
        "per_job_print_calibration_required": True,
        "first_layer_camera": "main",
        "nozzle_camera_roles": "auto_pa_flow_ratio_cfs_waste",
    }


def process_running(fragment, proc_root=Path("/proc")):
    try:
        paths = list(Path(proc_root).glob("[0-9]*/cmdline"))
    except OSError:
        return False
    for path in paths:
        try:
            command = path.read_bytes().replace(b"\0", b" ").decode(
                "utf-8", errors="replace"
            )
        except OSError:
            continue
        if fragment in command:
            return True
    return False


def classify_nozzle_camera(gpio, main_present, sub_present, cam_sub_running):
    if not main_present:
        return "main_camera_missing"
    if gpio == "1" and not sub_present and not cam_sub_running:
        return "standby"
    if gpio == "0" and sub_present and cam_sub_running:
        return "active"
    if gpio == "1" and (sub_present or cam_sub_running):
        return "stopping"
    if gpio == "0" and not (sub_present and cam_sub_running):
        return "waking_or_fault"
    return "unknown"


def matching_device_nodes(directory, patterns):
    root = Path(directory)
    if not root.is_dir():
        return []
    nodes = []
    for pattern in patterns:
        for path in root.glob(pattern):
            if path.exists():
                nodes.append(str(path))
    return sorted(set(nodes))


def read_nozzle_camera_status(
    gpio_path=NOZZLE_GPIO_PATH,
    proc_root=Path("/proc"),
    by_id_path=Path("/dev/v4l/by-id"),
):
    try:
        gpio = Path(gpio_path).read_text(encoding="ascii", errors="replace").strip()
    except OSError:
        gpio = None
    main_nodes = matching_device_nodes(by_id_path, ("*main*",))
    sub_nodes = matching_device_nodes(by_id_path, ("*sub*", "*nozzle*"))
    cam_sub_running = process_running("cam_sub_app", proc_root=proc_root)
    lifecycle = classify_nozzle_camera(
        gpio,
        bool(main_nodes),
        bool(sub_nodes),
        cam_sub_running,
    )
    return {
        "gpio162": gpio,
        "main_present": bool(main_nodes),
        "sub_present": bool(sub_nodes),
        "cam_sub_running": cam_sub_running,
        "lifecycle": lifecycle,
        "expected_idle_state": "standby",
    }


def path_is_within(path, directory):
    try:
        Path(path).resolve().relative_to(Path(directory).resolve())
        return True
    except ValueError:
        return False


def atomic_write_json(path, payload):
    target = Path(path)
    allowed = path_is_within(target, HELPER_DIR) or target.parent == Path("/tmp")
    if not allowed:
        raise ValueError("observability output must stay under the helper directory or /tmp")
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".tmp.%s" % os.getpid())
    temporary.write_text(
        json.dumps(payload, ensure_ascii=True, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(target)


def append_jsonl(path, payload, max_bytes=1048576):
    target = Path(path)
    if target.parent != Path("/tmp") and not path_is_within(target, REPORT_DIR):
        raise ValueError("observability history must stay under the helper reports directory or /tmp")
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
        handle.write(json.dumps(payload, ensure_ascii=True, sort_keys=True) + "\n")


def read_jsonl(path, limit=20):
    target = Path(path)
    if not target.is_file():
        return []
    try:
        with target.open("rb") as handle:
            handle.seek(0, 2)
            size = handle.tell()
            handle.seek(max(0, size - 524288))
            data = handle.read()
    except OSError:
        return []
    if size > len(data):
        newline = data.find(b"\n")
        if newline >= 0:
            data = data[newline + 1 :]
    rows = []
    for line in data.decode("utf-8", errors="ignore").splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows[-max(1, int(limit)) :]


def slot_confidence(source):
    mapping = {
        "remaining_material_match": (
            "medium",
            "remaining-material type/color matches a CFS slot; feed-arm state is not exposed",
        ),
        "box_filament_index": (
            "low",
            "BOX selected-material index only; feed-arm state is not exposed",
        ),
        "lan_selected_slot": (
            "low",
            "LAN UI selection only; feed-arm state is not exposed",
        ),
        "transition_continuity": (
            "medium",
            "slot was retained across a short transition; feed-arm state is not exposed",
        ),
    }
    level, note = mapping.get(
        str(source or "unknown"),
        ("unknown", "no reliable slot-selection evidence is available"),
    )
    return {"level": level, "source": source or "unknown", "note": note}


def status_from_payload(payload):
    return bed_mesh_insights.extract_status(payload)


def mesh_fingerprint(payload):
    status = status_from_payload(payload)
    mesh = status.get("bed_mesh")
    if not isinstance(mesh, dict):
        raise bed_mesh_insights.MeshError("Moonraker returned no bed_mesh object")
    material = {
        "profile_name": mesh.get("profile_name"),
        "mesh_min": mesh.get("mesh_min"),
        "mesh_max": mesh.get("mesh_max"),
        "probed_matrix": mesh.get("probed_matrix"),
    }
    encoded = json.dumps(material, ensure_ascii=True, separators=(",", ":"), sort_keys=True)
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def mesh_history_snapshot(payload, observed_at=None):
    report = bed_mesh_insights.analyze_payload(payload)
    report["observed_at"] = observed_at or now_text()
    report["fingerprint_sha256"] = mesh_fingerprint(payload)
    report["temperature_semantics"] = (
        "temperature_observed_when_mesh_change_was_detected_not_proven_probe_temperature"
    )
    report["history_safety"] = "passive_existing_mesh_only"
    return report


def capture_mesh_history(payload, path=MESH_HISTORY_PATH):
    snapshot = mesh_history_snapshot(payload)
    rows = read_jsonl(path, limit=1)
    previous = rows[-1] if rows else {}
    changed = previous.get("fingerprint_sha256") != snapshot["fingerprint_sha256"]
    if changed:
        append_jsonl(path, snapshot)
    return {
        "changed": changed,
        "path": str(path),
        "snapshot": snapshot,
        "previous_fingerprint_sha256": previous.get("fingerprint_sha256"),
    }


def fetch_and_capture_mesh(base_url, timeout=5.0, path=MESH_HISTORY_PATH):
    payload = bed_mesh_insights.fetch_payload(base_url, timeout)
    return capture_mesh_history(payload, path=path)


def short_session_hash(value):
    text = str(value or "")
    if not text:
        return None
    return hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()[:16]


def read_lan_usage(host="127.0.0.1", port=9999, timeout=3.0):
    raw = k2_lan_insights.fetch_status(host, int(port), float(timeout), include_materials=False)
    used = as_number(raw.get("usedMaterialLength"))
    _slots, selected = k2_lan_insights.summarize_materials(raw)
    session_seed = raw.get("printId")
    return {
        "timestamp": now_text(),
        "used_material_length_mm": used,
        "session_hash": short_session_hash(session_seed),
        "print_id_present": bool(session_seed),
        "lan_state": raw.get("state"),
        "lan_selected_slots": [slot for slot in selected if slot in SLOTS],
        "safety": "fixed_get_requests_only_no_set_no_spoolman_write",
    }


def new_consumption_session(
    print_file,
    used_material_mm,
    slot,
    source,
    session_hash=None,
    started_mid_print=False,
):
    confidence = slot_confidence(source)
    return {
        "session_hash": session_hash or short_session_hash(
            "%s|%s" % (print_file or "unknown", now_text())
        ),
        "print_file": Path(str(print_file or "unknown")).name,
        "started": now_text(),
        "finished": None,
        "started_mid_print": bool(started_mid_print),
        "baseline_counter_mm": used_material_mm,
        "last_counter_mm": used_material_mm,
        "observed_total_mm": 0.0,
        "by_slot_mm": {name: 0.0 for name in SLOTS},
        "unattributed_mm": 0.0,
        "last_slot": slot,
        "last_slot_source": source or "unknown",
        "last_slot_confidence": confidence["level"],
        "samples": 1,
        "counter_resets": 0,
        "counter_anomalies": 0,
        "state": "printing",
        "semantics": "dry_run_estimate_includes_purge_and_depends_on_slot_selection_evidence",
    }


def add_consumption_delta(session, delta, slot, source):
    if delta <= 0:
        return
    confidence = slot_confidence(source)
    session["observed_total_mm"] = round(
        float(session.get("observed_total_mm") or 0.0) + delta,
        3,
    )
    if slot in SLOTS and confidence["level"] in ("medium", "high"):
        values = session.setdefault("by_slot_mm", {name: 0.0 for name in SLOTS})
        values[slot] = round(float(values.get(slot) or 0.0) + delta, 3)
    else:
        session["unattributed_mm"] = round(
            float(session.get("unattributed_mm") or 0.0) + delta,
            3,
        )
    session["last_slot"] = slot
    session["last_slot_source"] = source or "unknown"
    session["last_slot_confidence"] = confidence["level"]


def update_consumption_tracker(
    tracker,
    print_state,
    print_file,
    used_material_mm,
    slot,
    slot_source,
    session_hash=None,
):
    data = dict(tracker or {})
    active = data.get("active")
    completed = None
    printing = str(print_state or "").lower() == "printing"
    used = as_number(used_material_mm)

    if printing and active is None:
        active = new_consumption_session(
            print_file,
            used,
            slot,
            slot_source,
            session_hash=session_hash,
            started_mid_print=bool(used and used > 1.0),
        )
        data["active"] = active
        data["updated"] = now_text()
        data["mode"] = "dry_run_no_spoolman_writes"
        return data, None

    if printing and active is not None:
        if session_hash and active.get("session_hash") not in (None, session_hash):
            active["finished"] = now_text()
            active["state"] = "superseded_by_new_print_id"
            completed = dict(active)
            active = new_consumption_session(
                print_file,
                used,
                slot,
                slot_source,
                session_hash=session_hash,
                started_mid_print=bool(used and used > 1.0),
            )
            data["active"] = active
        elif used is not None:
            previous = as_number(active.get("last_counter_mm"))
            if previous is None:
                active["last_counter_mm"] = used
            else:
                delta = used - previous
                if delta < -0.5:
                    active["counter_resets"] = int(active.get("counter_resets") or 0) + 1
                elif delta > 20000.0:
                    active["counter_anomalies"] = int(active.get("counter_anomalies") or 0) + 1
                else:
                    add_consumption_delta(active, max(0.0, delta), slot, slot_source)
                active["last_counter_mm"] = used
            active["samples"] = int(active.get("samples") or 0) + 1
        data["active"] = active
        data["updated"] = now_text()
        data["mode"] = "dry_run_no_spoolman_writes"
        return data, completed

    if not printing and active is not None:
        if used is not None:
            previous = as_number(active.get("last_counter_mm"))
            if previous is not None and 0.0 <= used - previous <= 20000.0:
                add_consumption_delta(active, used - previous, slot, slot_source)
        active["finished"] = now_text()
        active["state"] = str(print_state or "finished")
        completed = dict(active)
        data["last_completed"] = completed
        data["active"] = None

    data["updated"] = now_text()
    data["mode"] = "dry_run_no_spoolman_writes"
    return data, completed


def record_completed_consumption(completed, path=CONSUMPTION_PATH):
    if not completed:
        return False
    append_jsonl(
        path,
        {
            "timestamp": now_text(),
            "type": "cfs_consumption_dry_run",
            "session": completed,
            "safety": "no_spoolman_writes_no_cfs_commands",
        },
    )
    return True


def version_from_file(path):
    target = Path(path)
    if not target.is_file():
        return None
    try:
        value = target.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None
    return value.splitlines()[0][:80] if value else None


def compact_status_payload(
    state,
    latest_mesh=None,
    ai_preferences=None,
    nozzle_camera=None,
):
    current = (state or {}).get("current") or {}
    full = (state or {}).get("last_full_status") or {}
    consumption = (state or {}).get("consumption_dry_run") or {}
    mesh = latest_mesh or (state or {}).get("latest_mesh") or {}
    ai = read_ai_preferences() if ai_preferences is None else ai_preferences
    nozzle = read_nozzle_camera_status() if nozzle_camera is None else nozzle_camera
    confidence = slot_confidence(
        current.get("selected_slot_source")
        or current.get("active_slot_source")
        or full.get("selected_slot_source")
    )
    return {
        "build": BUILD,
        "updated": now_text(),
        "safety": "read_only_status_and_dry_run_estimates",
        "printer": {
            "state": current.get("print_state") or full.get("print_state"),
            "file": Path(str(current.get("print_file") or full.get("print_file") or "")).name,
            "bed_temperature_c": current.get("bed_temperature_c"),
            "bed_target_c": current.get("bed_target_c"),
            "extruder_temperature_c": current.get("extruder_temperature_c"),
            "extruder_target_c": current.get("extruder_target_c"),
        },
        "cfs": {
            "box_state": current.get("box_state") or full.get("box_state"),
            "t1_state": current.get("t1_state") or full.get("t1_state"),
            "version": full.get("t1_version"),
            "temperature_c": full.get("temperature_c"),
            "humidity_percent": current.get("humidity_percent")
            if current.get("humidity_percent") is not None
            else full.get("humidity_percent"),
            "mode": current.get("mode") if current.get("mode") is not None else full.get("mode"),
            "selected_slot": current.get("active_slot") or full.get("selected_slot"),
            "slot_confidence": confidence,
            "active_spool": current.get("active_spool") or full.get("active_spool"),
        },
        "consumption_dry_run": consumption,
        "bed_mesh": mesh,
        "ai": {
            **ai,
            "nozzle_camera": nozzle,
        },
        "frontends": {
            "fluidd": version_from_file("/usr/share/fluidd/.version"),
            "mainsail": version_from_file("/usr/share/mainsail/.version"),
        },
    }


def write_compact_status(state, latest_mesh=None, path=STATUS_JSON_PATH):
    payload = compact_status_payload(state, latest_mesh=latest_mesh)
    atomic_write_json(path, payload)
    return payload


def selftest():
    failures = []
    if slot_confidence("remaining_material_match")["level"] != "medium":
        failures.append("remaining-material confidence mapping failed")
    if slot_confidence("box_filament_index")["level"] != "low":
        failures.append("BOX index confidence mapping failed")
    if classify_nozzle_camera("1", True, False, False) != "standby":
        failures.append("nozzle camera standby classification failed")
    if classify_nozzle_camera("0", True, True, True) != "active":
        failures.append("nozzle camera active classification failed")
    if classify_nozzle_camera("0", True, False, False) != "waking_or_fault":
        failures.append("nozzle camera inconsistent classification failed")

    tracker, completed = update_consumption_tracker(
        {},
        "printing",
        "test.gcode",
        10.0,
        "T1A",
        "remaining_material_match",
        session_hash="abc",
    )
    if completed is not None:
        failures.append("new session completed unexpectedly")
    tracker, _ = update_consumption_tracker(
        tracker,
        "printing",
        "test.gcode",
        25.5,
        "T1A",
        "remaining_material_match",
        session_hash="abc",
    )
    tracker, completed = update_consumption_tracker(
        tracker,
        "complete",
        "test.gcode",
        30.0,
        "T1A",
        "remaining_material_match",
        session_hash="abc",
    )
    if not completed or abs(completed["by_slot_mm"]["T1A"] - 20.0) > 0.001:
        failures.append("consumption delta accounting failed")
    if tracker.get("active") is not None:
        failures.append("completed session remained active")

    payload = {
        "bed_mesh": {
            "profile_name": "test",
            "mesh_min": [0, 0],
            "mesh_max": [10, 10],
            "probed_matrix": [[0.0, 0.1], [0.2, 0.3]],
        }
    }
    with Path("/tmp/k2-observability-selftest.jsonl").open("w", encoding="utf-8") as handle:
        handle.write("")
    try:
        first = capture_mesh_history(payload, Path("/tmp/k2-observability-selftest.jsonl"))
        second = capture_mesh_history(payload, Path("/tmp/k2-observability-selftest.jsonl"))
        if not first["changed"] or second["changed"]:
            failures.append("mesh deduplication failed")
    finally:
        Path("/tmp/k2-observability-selftest.jsonl").unlink(missing_ok=True)

    source = Path(__file__).read_text(encoding="utf-8", errors="replace")
    for token in (
        "method=" + '"POST"',
        '"method"' + ': "set"',
        "BOX_" + "LOAD",
        "BOX_" + "RETRUDE",
        "SET_" + "HEATER",
        "subprocess" + ".",
        "os." + "system(",
    ):
        if token in source:
            failures.append("forbidden active token present: " + token)
    if failures:
        for failure in failures:
            print("SELFTEST_FAIL|" + failure)
        return 1
    print(
        "SELFTEST|OK|mesh history, slot confidence, dry-run consumption "
        "and nozzle AI lifecycle classification"
    )
    return 0


def print_ai_status():
    ai = read_ai_preferences()
    nozzle = read_nozzle_camera_status()
    print(
        "AI_CONTROL|available=%s|switch=%s|detection=%s|pause_print=%s|"
        "first_layer=%s|waste=%s|auto_pa=%s|flow_ratio=%s|flow_mode=%s"
        % (
            int(bool(ai["available"])),
            ai["switch"],
            ai["detection"],
            ai["pause_print"],
            ai["first_layer"],
            ai["waste"],
            ai["auto_pa"],
            ai["flow_ratio"],
            ai["flow_mode"],
        )
    )
    print(
        "AI_CALIBRATION_READY|%s|per_job_print_calibration_required=1"
        % ("yes" if ai["calibration_ready"] else "no")
    )
    print(
        "NOZZLE_LIFECYCLE|%s|gpio162=%s|main_present=%s|sub_present=%s|"
        "cam_sub_running=%s"
        % (
            nozzle["lifecycle"],
            nozzle["gpio162"],
            int(nozzle["main_present"]),
            int(nozzle["sub_present"]),
            int(nozzle["cam_sub_running"]),
        )
    )
    print(
        "NOZZLE_ROLE|auto_pa_flow_ratio_cfs_waste|"
        "first_layer_detection=main_camera"
    )
    if not ai["available"] or nozzle["lifecycle"] in (
        "main_camera_missing",
        "waking_or_fault",
        "unknown",
    ):
        return 2
    return 0


def refresh_status(capture_mesh=False):
    state = {}
    try:
        state = json.loads(STATE_PATH.read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError, TypeError):
        state = {}
    latest_mesh = state.get("latest_mesh") or {}
    capture = None
    if capture_mesh:
        capture = fetch_and_capture_mesh(
            bed_mesh_insights.DEFAULT_MOONRAKER_URL,
            timeout=5.0,
            path=MESH_HISTORY_PATH,
        )
        latest_mesh = capture["snapshot"]
    payload = write_compact_status(state, latest_mesh=latest_mesh)
    print(
        "K2_STATUS|OK|updated=%s|mesh_captured=%s|path=%s"
        % (payload["updated"], bool(capture), STATUS_JSON_PATH)
    )
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--selftest", action="store_true")
    action.add_argument("--refresh-status", action="store_true")
    action.add_argument("--capture-mesh", action="store_true")
    action.add_argument("--ai-status", action="store_true")
    args = parser.parse_args(argv or sys.argv[1:])
    if args.selftest:
        return selftest()
    if args.refresh_status:
        return refresh_status(capture_mesh=False)
    if args.capture_mesh:
        return refresh_status(capture_mesh=True)
    if args.ai_status:
        return print_ai_status()
    parser.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
