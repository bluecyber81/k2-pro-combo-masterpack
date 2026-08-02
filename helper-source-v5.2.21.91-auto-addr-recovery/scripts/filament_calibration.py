#!/usr/bin/env python3
"""Read-only Creality Auto PA and Flow Ratio result diagnostics.

The K2 Pro only runs the proprietary nozzle-camera calibration when a print
job is submitted with ``enableSelfTest=1``.  This module correlates the
manufacturer log, G-code metadata, current CFS selection and live Klipper
values.  It never starts a print, sends G-code, moves a CFS motor, or changes
filament/profile data.
"""

import argparse
import gzip
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path


BUILD = "filament-calibration-capture-1.4"
LOG_DIR = Path(
    os.environ.get(
        "K2_CALIBRATION_LOG_DIR", "/mnt/UDISK/creality/userdata/log"
    )
)
GCODE_DIR = Path(
    os.environ.get(
        "K2_CALIBRATION_GCODE_DIR", "/mnt/UDISK/printer_data/gcodes"
    )
)
BOX_DIR = Path(
    os.environ.get(
        "K2_CALIBRATION_BOX_DIR", "/mnt/UDISK/creality/userdata/box"
    )
)
CONFIG_DIR = Path(
    os.environ.get(
        "K2_CALIBRATION_CONFIG_DIR", "/mnt/UDISK/creality/userdata/config"
    )
)
HELPER_DIR = Path(
    os.environ.get("K2_CALIBRATION_HELPER_DIR", "/mnt/UDISK/helper-script")
)
MOONRAKER = os.environ.get(
    "K2_CALIBRATION_MOONRAKER", "http://127.0.0.1:7125"
).rstrip("/")
DEFAULT_REPORT = HELPER_DIR / "reports" / "filament_calibration_status.json"

LOG_NAME = "master-server.log"
SLOTS = ("T1A", "T1B", "T1C", "T1D")
TIMESTAMP_RE = re.compile(
    r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)\]"
)
SELF_TEST_RE = re.compile(r"with self test\s*=\s*([01])", re.I)
FLOW_FLAGS_RE = re.compile(
    r"flowdetect\s*=\s*(\d+)\s*,\s*flow_em_detect\s*=\s*(\d+)", re.I
)
START_FILE_RE = re.compile(
    r"(?:start print file|file name|checked print file name|"
    r"get print sd file path|current gcode file|get print file name)"
    r"\s*=\s*(.+?\.gcode)\s*$",
    re.I,
)
PRINTPRT_RE = re.compile(r"printprt:([^\"}\r\n]+?\.gcode)", re.I)
PA_RESULT_RE = re.compile(r"flow_pa result:\s*pressureAdvance\s*=\s*([-+.\deE]+)", re.I)
PA_BEST_RE = re.compile(
    r"flow_pa best_flow_pressure_advance\s*=\s*([-+.\deE]+)", re.I
)
PA_EFFECTIVE_RE = re.compile(
    r"flow_pa detect effective value\s*=\s*([-+.\deE]+)", re.I
)
PA_FALLBACK_RE = re.compile(
    r"using default PA value from printer\.cfg:\s*([-+.\deE]+)", re.I
)
PA_TASK_RESULT_RE = re.compile(
    r"\[flow_pa\]\s*Result for pressureAdvance task\s+(\d+):\s*"
    r"([-+.\deE]+)",
    re.I,
)
FLOW_RESULT_RE = re.compile(
    r"flow_em best_flow_percentage\s*=\s*([-+.\deE]+)", re.I
)
M221_RE = re.compile(r"\bM221\s+S\s*([-+.\deE]+)", re.I)
AI_PREF_RE = re.compile(
    r"flowDetect\s*=\s*(\d+).*?flowDetectMode\s*=\s*(\d+).*?"
    r"flowEmDetect\s*=\s*(\d+)",
    re.I,
)
T_COMMAND_MAP_RE = re.compile(
    r"T-Command map:\s*(T\d+)\((T\d+[A-D])\)=>(T\d+[A-D])", re.I
)
CFS_PARAMS_RE = re.compile(
    r"Flow(?:Pa|Em)_ExtractAndSetGcodeParams CFS\s+"
    r"t_command:\s*(T\d+)\s*,\s*"
    r"Vender:\s*(.*?)\s*,\s*"
    r"Remain Length:\s*([^,]+?)\s*,\s*"
    r"Color Value:\s*([^,]+?)\s*,\s*"
    r"Material Type:\s*([^,]+?)\s*,\s*"
    r"Material Name:\s*([^,]+?)\s*,\s*"
    r"Pressure Advance:\s*([-+.\deE]+)",
    re.I,
)

RELEVANT_TOKENS = (
    "with self test",
    "fluidd start print file",
    "start print file =",
    "printprt:",
    "flowdetect =",
    "flowdetectmode",
    "start flow_pa",
    "flow_pa ",
    "[flow_pa]",
    "start flow_em",
    "flow_em ",
    "[flow_em]",
    "ai flow_pa",
    "ai flow_em",
    "m221 s",
    "will load_ai_deal",
    "load_ai cmdtype[waste]",
)

PA_ERROR_TOKENS = (
    "ai flow_pa detect fail",
    "ai flow_pa detect capture abnormal",
    "ai flow_pa detect value abnormal",
    "ai flow_pa detect canceled by user",
    "start flow detect fail",
    "flow_pa fail ret=",
    "flow_pa parse gcode fail",
    "flow_pa detect rapidtotargettemp failed",
    "[flow_pa]ai capture cmd fail",
    "[flow_pa]ai capture return error",
)
FLOW_ERROR_TOKENS = (
    "ai flow_em detect fail",
    "ai flow_em detect capture abnormal",
    "ai flow_em detect value abnormal",
    "ai flow_em detect canceled by user",
    "start flow_em detect fail",
    "flow_em parse gcode fail",
    "flow_em detect rapidtotargettemp failed",
    "[flow_em]ai capture cmd fail",
    "[flow_em]ai capture return error",
)
CANCEL_TOKENS = (
    "nozzle_clear canceled by user",
    "user stop print finish",
    "ai flow_pa detect canceled by user",
    "ai flow_em detect canceled by user",
)
FINISH_TOKENS = (
    "normal print finish",
    "print completed successfully",
    "print state = complete",
    "print finish",
)


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError, TypeError):
        return default


def as_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def clean_text(value):
    return str(value if value is not None else "").replace("|", "/").strip()


def clean_cfs_value(value):
    text = clean_text(value)
    return "" if text.lower() in ("", "-1", "none", "unknown") else text


def normalize_material_id(value):
    text = clean_cfs_value(value)
    if len(text) == 6 and text.startswith("0"):
        return text[1:]
    return text.lstrip("0") or text


def normalize_color(value):
    text = clean_cfs_value(value).lower().lstrip("#")
    if len(text) == 7 and text.startswith("0"):
        text = text[1:]
    return text


def log_sort_key(path):
    if path.name == LOG_NAME:
        return 10_000
    match = re.search(r"\.(\d+)(?:\.gz)?$", path.name)
    if not match:
        return 0
    # Larger rotation numbers are older and must be processed first.
    return 1_000 - int(match.group(1))


def find_log_paths(log_dir=LOG_DIR, max_archives=0):
    candidates = []
    current = Path(log_dir) / LOG_NAME
    if current.is_file():
        candidates.append(current)
    for number in range(1, max_archives + 1):
        for suffix in (".gz", ""):
            candidate = Path(log_dir) / ("%s.%d%s" % (LOG_NAME, number, suffix))
            if candidate.is_file():
                candidates.append(candidate)
                break
    return sorted(candidates, key=log_sort_key)


def iter_log_lines(path, tail_bytes=8 * 1024 * 1024):
    opener = gzip.open if str(path).endswith(".gz") else open
    try:
        if opener is open:
            handle = open(path, "rb")
            handle.seek(0, 2)
            size = handle.tell()
            handle.seek(max(0, size - tail_bytes), 0)
            if size > tail_bytes:
                handle.readline()
            line_iterator = (
                line.decode("utf-8", errors="replace") for line in handle
            )
        else:
            # Archive scans are deliberately opt-in because seeking a gzip
            # stream requires full decompression on this small OpenWrt host.
            handle = gzip.open(path, "rt", encoding="utf-8", errors="replace")
            line_iterator = handle
        with handle:
            for line in line_iterator:
                lower = line.lower()
                if (
                    "flow" in lower
                    or "self test" in lower
                    or "load_ai cmdtype[waste]" in lower
                    or "start print file" in lower
                    or "printprt:" in lower
                    or "file name =" in lower
                    or "web control start print" in lower
                    or "canceled by user" in lower
                    or "user stop print finish" in lower
                    or "normal print finish" in lower
                    or "print state = complete" in lower
                    or "print finish" in lower
                    or "t-command map:" in lower
                ):
                    yield line.rstrip("\r\n")
    except (OSError, EOFError):
        return


def event_time(line):
    match = TIMESTAMP_RE.match(line)
    return match.group(1) if match else ""


def new_job(sequence, line, requested):
    return {
        "sequence": sequence,
        "timestamp": event_time(line),
        "requested": requested,
        "source": "creality_or_display",
        "file": "",
        "flow_flags": {"auto_pa": None, "auto_flow": None},
        "pa": {
            "started": False,
            "measured": False,
            "result": None,
            "best": None,
            "effective": None,
            "fallback": False,
            "fallback_value": None,
            "task_results": {},
            "task_results_valid": 0,
            "task_results_invalid": 0,
            "errors": [],
        },
        "flow": {
            "started": False,
            "measured": False,
            "percentage": None,
            "m221": None,
            "unsupported": False,
            "errors": [],
        },
        "cfs_material": {
            "logical_command": "",
            "logical_slot": "",
            "physical_slot": "",
            "vendor": "",
            "remaining_percent": None,
            "color": "",
            "material_id": "",
            "type": "",
            "pressure_advance": None,
            "mapping_source": "",
        },
        "waste_checks": 0,
        "lifecycle": {
            "cancelled": False,
            "cancel_reason": "",
            "finished": False,
            "duplicate_start_requests": 0,
        },
        "evidence": [],
    }


def append_evidence(job, line, limit=80):
    if len(job["evidence"]) < limit:
        job["evidence"].append(line)


def parse_calibration_logs(paths):
    jobs = []
    current = None
    global_preferences = {
        "auto_pa": None,
        "auto_flow": None,
        "flow_mode": None,
    }
    pending_source = ""
    pending_file = ""
    pending_sequence = 0
    pending_start_requests = 0
    sequence = 0

    for path in paths:
        for line in iter_log_lines(path):
            sequence += 1
            lower = line.lower()
            preference = AI_PREF_RE.search(line)
            if preference:
                global_preferences = {
                    "auto_pa": int(preference.group(1)),
                    "flow_mode": int(preference.group(2)),
                    "auto_flow": int(preference.group(3)),
                }

            if "web control start print local gcode" in lower:
                if (
                    current is not None
                    and not current["lifecycle"]["cancelled"]
                    and not current["lifecycle"]["finished"]
                ):
                    current["lifecycle"]["duplicate_start_requests"] += 1
                    append_evidence(current, line)
                pending_source = "creality_web_local"
                pending_file = ""
                pending_sequence = sequence
                pending_start_requests = 1
            elif "fluidd start print file" in lower:
                pending_source = "fluidd_or_mainsail"
                pending_file = ""
                pending_sequence = sequence
                pending_start_requests = 1

            file_match = START_FILE_RE.search(line) or PRINTPRT_RE.search(line)
            if file_match:
                candidate = file_match.group(1).strip()
                if not pending_file or "/" in candidate:
                    pending_file = candidate

            self_test = SELF_TEST_RE.search(line)
            if self_test:
                current = new_job(sequence, line, bool(int(self_test.group(1))))
                if pending_source and sequence - pending_sequence <= 200:
                    current["source"] = pending_source
                    current["file"] = pending_file
                    current["lifecycle"]["duplicate_start_requests"] = max(
                        0, pending_start_requests - 1
                    )
                jobs.append(current)
                append_evidence(current, line)
                pending_source = ""
                pending_file = ""
                pending_sequence = 0
                pending_start_requests = 0
                continue

            if current is None:
                continue

            if "fluidd start = 1" in lower:
                current["source"] = "fluidd_or_mainsail"

            if file_match and not current["file"]:
                current["file"] = file_match.group(1).strip()

            mapping = T_COMMAND_MAP_RE.search(line)
            if mapping:
                current["cfs_material"].update(
                    {
                        "logical_command": mapping.group(1).upper(),
                        "logical_slot": mapping.group(2).upper(),
                        "physical_slot": mapping.group(3).upper(),
                        "mapping_source": "creality_t_command_map",
                    }
                )

            cfs_params = CFS_PARAMS_RE.search(line)
            if cfs_params:
                material = current["cfs_material"]
                material["logical_command"] = cfs_params.group(1).upper()
                values = {
                    "vendor": clean_cfs_value(cfs_params.group(2)),
                    "color": clean_cfs_value(cfs_params.group(4)),
                    "material_id": clean_cfs_value(cfs_params.group(5)),
                    "type": clean_cfs_value(cfs_params.group(6)),
                }
                for key, value in values.items():
                    if value:
                        material[key] = value
                remaining = as_float(cfs_params.group(3))
                if remaining is not None and remaining >= 0:
                    material["remaining_percent"] = remaining
                pressure = as_float(cfs_params.group(7))
                if pressure is not None and pressure >= 0:
                    material["pressure_advance"] = pressure

            flags = FLOW_FLAGS_RE.search(line)
            if flags:
                current["flow_flags"] = {
                    "auto_pa": int(flags.group(1)),
                    "auto_flow": int(flags.group(2)),
                }

            if "start flow_pa detect" in lower and "fail" not in lower:
                current["pa"]["started"] = True
            if "start flow_em detect" in lower and "fail" not in lower:
                current["flow"]["started"] = True

            match = PA_RESULT_RE.search(line)
            if match:
                value = as_float(match.group(1))
                current["pa"]["result"] = value
            match = PA_BEST_RE.search(line)
            if match:
                value = as_float(match.group(1))
                current["pa"]["best"] = value
            match = PA_EFFECTIVE_RE.search(line)
            if match:
                current["pa"]["effective"] = as_float(match.group(1))
            match = PA_FALLBACK_RE.search(line)
            if match:
                current["pa"]["fallback"] = True
                current["pa"]["fallback_value"] = as_float(match.group(1))
                current["pa"]["measured"] = False
            match = PA_TASK_RESULT_RE.search(line)
            if match:
                current["pa"]["task_results"][match.group(1)] = as_float(
                    match.group(2)
                )

            match = FLOW_RESULT_RE.search(line)
            if match:
                value = as_float(match.group(1))
                current["flow"]["percentage"] = value
            if current["flow"]["started"]:
                match = M221_RE.search(line)
                if match:
                    current["flow"]["m221"] = as_float(match.group(1))

            if "current print material is not pla" in lower:
                current["flow"]["unsupported"] = True
            for token in PA_ERROR_TOKENS:
                if token in lower and line not in current["pa"]["errors"]:
                    current["pa"]["errors"].append(line)
            for token in FLOW_ERROR_TOKENS:
                if token in lower and line not in current["flow"]["errors"]:
                    current["flow"]["errors"].append(line)
            for token in CANCEL_TOKENS:
                if token in lower:
                    current["lifecycle"]["cancelled"] = True
                    if not current["lifecycle"]["cancel_reason"]:
                        current["lifecycle"]["cancel_reason"] = line
            for token in FINISH_TOKENS:
                if token in lower:
                    current["lifecycle"]["finished"] = True
            if "load_ai cmdtype[waste]" in lower:
                current["waste_checks"] += 1

            if (
                "flow_" in lower
                or "with self test" in lower
                or "load_ai cmdtype[waste]" in lower
                or "canceled by user" in lower
                or "user stop print finish" in lower
                or "t-command map:" in lower
            ):
                append_evidence(current, line)

    for job in jobs:
        pa = job["pa"]
        task_values = [
            value
            for value in pa.get("task_results", {}).values()
            if value is not None
        ]
        pa["task_results_valid"] = sum(value >= 0 for value in task_values)
        pa["task_results_invalid"] = sum(value < 0 for value in task_values)
        if task_values and pa["task_results_valid"] == 0:
            pa["fallback"] = True
            if pa.get("fallback_value") is None:
                pa["fallback_value"] = pa.get("effective")
            if pa.get("fallback_value") is None:
                pa["fallback_value"] = pa.get("best")
        pa_candidate = pa.get("best")
        if pa_candidate is None:
            pa_candidate = pa.get("result")
        pa["measured"] = bool(
            pa.get("started")
            and pa_candidate is not None
            and pa_candidate >= 0
            and not pa.get("fallback")
            and not pa.get("errors")
        )

        flow = job["flow"]
        flow["measured"] = bool(
            flow.get("started")
            and flow.get("percentage") is not None
            and flow.get("percentage") > 0
            and not flow.get("unsupported")
            and not flow.get("errors")
        )
        job["classification"] = classify_job(job)
    return {
        "jobs": jobs,
        "global_preferences": global_preferences,
        "log_files": [str(path) for path in paths],
    }


def classify_job(job, live_print_state=""):
    if job.get("requested") is False:
        return "not_requested"
    if job.get("requested") is None:
        return "unknown"

    pa = job["pa"]
    flow = job["flow"]
    pa_ok = bool(pa["measured"] and not pa["fallback"])
    flow_ok = bool(flow["measured"])
    has_error = bool(pa["errors"] or flow["errors"])
    lifecycle = job.get("lifecycle") or {}

    if flow["unsupported"]:
        return "partial" if pa_ok else "unsupported"
    if pa_ok and flow_ok:
        return "complete"
    if pa["fallback"]:
        return "partial" if flow_ok else "fallback"
    if has_error:
        return "partial" if (pa_ok or flow_ok) else "failed"
    if lifecycle.get("cancelled"):
        return "partial" if (pa_ok or flow_ok) else "cancelled"
    if pa_ok or flow_ok:
        return "partial"
    if pa["started"] or flow["started"]:
        return "requested_pending"
    if live_print_state in ("printing", "paused"):
        return "requested_pending"
    return "requested_without_measurement"


def split_first(value):
    text = clean_text(value).strip("\"'")
    for separator in (";", ","):
        if separator in text:
            return text.split(separator, 1)[0].strip().strip("\"'")
    return text


def read_gcode_metadata(path):
    if not path or not Path(path).is_file():
        return {}
    path = Path(path)
    try:
        with path.open("rb") as handle:
            head = handle.read(256 * 1024)
            handle.seek(0, 2)
            size = handle.tell()
            handle.seek(max(0, size - 1024 * 1024), 0)
            tail = handle.read()
    except OSError:
        return {}
    text = (head + b"\n" + tail).decode("utf-8", errors="ignore")
    wanted = {
        "enable_pressure_advance",
        "filament_flow_ratio",
        "filament_ids",
        "filament_max_volumetric_speed",
        "filament_settings_id",
        "filament_type",
        "nozzle_diameter",
        "pressure_advance",
        "printer_model",
        "printer_settings_id",
    }
    values = {}
    for line in text.splitlines():
        match = re.match(r"^\s*;\s*([^=]+?)\s*=\s*(.*?)\s*$", line)
        if not match:
            continue
        key = re.sub(r"[^a-z0-9]+", "_", match.group(1).strip().lower()).strip("_")
        if key in wanted:
            values[key] = split_first(match.group(2))
    material = values.get("filament_type", "")
    values["flow_pla_family"] = "PLA" in material.upper()
    values["path"] = str(path)
    return values


def resolve_gcode_path(job, gcode_dir=GCODE_DIR):
    value = clean_text((job or {}).get("file"))
    if not value:
        return None
    candidate = Path(value)
    if candidate.is_file():
        return candidate
    candidate = Path(gcode_dir) / Path(value).name
    return candidate if candidate.is_file() else None


def http_get_json(path, timeout=5):
    request = urllib.request.Request(
        MOONRAKER + path,
        headers={"User-Agent": "k2pro-" + BUILD},
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8", errors="replace"))


def material_database():
    data = read_json(BOX_DIR / "material_database.json", {}) or {}
    result = {}
    for entry in data.get("result", {}).get("list", []) or []:
        base = entry.get("base", {}) or {}
        params = entry.get("kvParam", {}) or {}
        identifier = clean_text(base.get("id"))
        if identifier:
            result[identifier] = {
                "id": identifier,
                "brand": clean_text(base.get("brand")),
                "name": clean_text(base.get("name")),
                "type": clean_text(
                    base.get("meterialType")
                    or base.get("type")
                    or base.get("material_type")
                    or params.get("filament_type")
                ),
                "pressure": as_float(
                    params.get("pressure_advance")
                    if params.get("pressure_advance") is not None
                    else base.get("pressure")
                ),
                "flow_ratio": as_float(params.get("filament_flow_ratio")),
            }
    return result


def lookup_material(database, identifier):
    value = clean_text(identifier)
    candidates = (
        value,
        value[1:] if len(value) == 6 else value,
        value.lstrip("0") or value,
        value.zfill(5),
        value.zfill(6),
    )
    for candidate in candidates:
        if candidate in database:
            return database[candidate]
    return {}


def cfs_inventory(box):
    t1 = box.get("T1", {}) or {}
    material_ids = t1.get("material_type", []) or []
    colors = t1.get("color_value", []) or []
    remain = t1.get("remain_len", []) or []
    database = material_database()
    row_types = {}
    for row in box.get("same_material", []) or []:
        if len(row) < 4:
            continue
        for slot in row[2] or []:
            row_types[clean_text(slot)] = clean_text(row[3])
    spool_map = read_json(HELPER_DIR / "spoolman_cfs_map.json", {}) or {}
    inventory = []
    for index, slot in enumerate(SLOTS):
        material_id = clean_text(material_ids[index]) if len(material_ids) > index else ""
        profile = lookup_material(database, material_id)
        spool_id = spool_map.get(slot)
        if spool_id is None and isinstance(spool_map.get("slots"), dict):
            spool_id = spool_map["slots"].get(slot)
        inventory.append(
            {
                "slot": slot,
                "material_id": material_id,
                "brand": profile.get("brand", ""),
                "name": profile.get("name", ""),
                "type": profile.get("type") or row_types.get(slot, ""),
                "color": clean_text(colors[index]) if len(colors) > index else "",
                "remaining_percent": as_float(remain[index]) if len(remain) > index else None,
                "database_pressure": profile.get("pressure"),
                "database_flow_ratio": profile.get("flow_ratio"),
                "spoolman_spool_id": spool_id,
                "cfs_version": clean_text(t1.get("version")),
            }
        )
    return inventory


def selected_cfs_material(box, inventory=None):
    try:
        index = int(box.get("filament") or 0)
    except (TypeError, ValueError):
        index = 0
    rows = cfs_inventory(box) if inventory is None else inventory
    if 1 <= index <= len(rows):
        selected = dict(rows[index - 1])
        selected["selection_source"] = "live_box_pointer"
        return selected
    return {"slot": "", "selection_source": "live_box_pointer"}


def resolve_calibrated_material(job, inventory):
    captured = (job or {}).get("cfs_material") or {}
    physical_slot = clean_text(captured.get("physical_slot")).upper()
    material_id = clean_text(captured.get("material_id"))
    color = clean_text(captured.get("color"))
    by_slot = {row.get("slot"): row for row in inventory or []}
    matched = by_slot.get(physical_slot)
    source = "creality_log_map"

    if matched is None and (material_id or color):
        candidates = []
        for row in inventory or []:
            id_matches = not material_id or (
                normalize_material_id(row.get("material_id"))
                == normalize_material_id(material_id)
            )
            color_matches = not color or (
                normalize_color(row.get("color")) == normalize_color(color)
            )
            if id_matches and color_matches:
                candidates.append(row)
        if len(candidates) == 1:
            matched = candidates[0]
            physical_slot = clean_text(matched.get("slot"))
            source = "unique_live_inventory_match"

    id_verified = bool(
        matched
        and material_id
        and normalize_material_id(matched.get("material_id"))
        == normalize_material_id(material_id)
    )
    color_verified = bool(
        matched
        and color
        and normalize_color(matched.get("color")) == normalize_color(color)
    )
    verified = bool(matched and id_verified and color_verified)
    if verified and captured.get("mapping_source"):
        source = "creality_log_map+live_inventory"
    elif matched and physical_slot and not verified:
        source = "log_map_inventory_mismatch"

    database = material_database()
    canonical_id = clean_text((matched or {}).get("material_id")) or material_id
    profile = lookup_material(database, canonical_id)
    return {
        "logical_command": clean_text(captured.get("logical_command")),
        "logical_slot": clean_text(captured.get("logical_slot")),
        "slot": physical_slot,
        "material_id": canonical_id,
        "brand": clean_text((matched or {}).get("brand")) or profile.get("brand", ""),
        "name": clean_text((matched or {}).get("name")) or profile.get("name", ""),
        "type": (
            clean_text((matched or {}).get("type"))
            or profile.get("type", "")
            or clean_text(captured.get("type"))
        ),
        "color": clean_text((matched or {}).get("color")) or color,
        "remaining_percent": (matched or {}).get(
            "remaining_percent", captured.get("remaining_percent")
        ),
        "database_pressure": (matched or {}).get(
            "database_pressure", profile.get("pressure")
        ),
        "database_flow_ratio": (matched or {}).get(
            "database_flow_ratio", profile.get("flow_ratio")
        ),
        "spoolman_spool_id": (matched or {}).get("spoolman_spool_id"),
        "attribution": source,
        "verified": verified,
    }


def live_snapshot():
    payload = http_get_json(
        "/printer/objects/query?print_stats&virtual_sdcard&extruder&gcode_move&box",
        timeout=6,
    )
    status = payload.get("result", {}).get("status", {}) or {}
    print_stats = status.get("print_stats", {}) or {}
    extruder = status.get("extruder", {}) or {}
    gcode_move = status.get("gcode_move", {}) or {}
    box = status.get("box", {}) or {}
    flow_file = read_json(CONFIG_DIR / "flow_rate.json", {}) or {}
    inventory = cfs_inventory(box)
    return {
        "print_state": clean_text(print_stats.get("state")),
        "current_file": clean_text(print_stats.get("filename")),
        "runtime_pressure_advance": as_float(extruder.get("pressure_advance")),
        "runtime_extrude_factor": as_float(gcode_move.get("extrude_factor")),
        "flow_rate_file_percent": as_float(flow_file.get("value")),
        "cfs": selected_cfs_material(box, inventory=inventory),
        "cfs_inventory": inventory,
    }


def ai_preferences():
    data = read_json(CONFIG_DIR / "user_print_refer.json", {}) or {}
    ai = data.get("ai_control", {}) or {}
    return {
        "auto_pa": ai.get("flowDetect", data.get("flowDetect")),
        "auto_flow": ai.get("flowEmDetect", data.get("flowEmDetect")),
        "flow_mode": ai.get("flowDetectMode"),
    }


def result_value(job):
    if not job:
        return {"pressure_advance": None, "flow_percentage": None}
    pa = job["pa"]
    value = pa.get("best")
    if value is None:
        value = pa.get("result")
    return {
        "pressure_advance": value if pa.get("measured") and not pa.get("fallback") else None,
        "flow_percentage": (
            job["flow"].get("percentage") if job["flow"].get("measured") else None
        ),
    }


def profile_recommendation(job):
    result = result_value(job)
    metadata = (job or {}).get("gcode_metadata") or {}
    material = (job or {}).get("calibrated_material") or {}
    base_flow_ratio = as_float(metadata.get("filament_flow_ratio"))
    flow_percentage = result.get("flow_percentage")
    recommended_flow_ratio = None
    if base_flow_ratio is not None and flow_percentage is not None:
        recommended_flow_ratio = round(base_flow_ratio * flow_percentage / 100.0, 6)
    complete = bool(
        (job or {}).get("classification") == "complete"
        and result.get("pressure_advance") is not None
        and flow_percentage is not None
    )
    safe = bool(
        complete
        and material.get("verified")
        and metadata.get("flow_pla_family")
        and base_flow_ratio is not None
        and base_flow_ratio > 0
        and recommended_flow_ratio is not None
        and recommended_flow_ratio > 0
    )
    if not complete:
        reason = "measurement_incomplete"
    elif not material.get("verified"):
        reason = "material_or_slot_unverified"
    elif not metadata.get("flow_pla_family"):
        reason = "gcode_material_not_pla"
    elif recommended_flow_ratio is None or recommended_flow_ratio <= 0:
        reason = "base_flow_ratio_missing"
    else:
        reason = "verified"
    return {
        "pressure_advance": result.get("pressure_advance"),
        "base_flow_ratio": base_flow_ratio,
        "flow_percentage": flow_percentage,
        "flow_ratio": recommended_flow_ratio,
        "slot": material.get("slot", ""),
        "material_id": material.get("material_id", ""),
        "profile": metadata.get("filament_settings_id", ""),
        "safe_to_persist": safe,
        "reason": reason,
    }


def build_report(log_dir=LOG_DIR, gcode_dir=GCODE_DIR, max_archives=0):
    parsed = parse_calibration_logs(find_log_paths(log_dir, max_archives=max_archives))
    try:
        live = live_snapshot()
        live_error = ""
    except Exception as exc:
        live = {
            "print_state": "unavailable",
            "current_file": "",
            "runtime_pressure_advance": None,
            "runtime_extrude_factor": None,
            "flow_rate_file_percent": None,
            "cfs": {},
            "cfs_inventory": [],
        }
        live_error = str(exc)

    for job in parsed["jobs"]:
        job["classification"] = classify_job(job, live.get("print_state", ""))
        path = resolve_gcode_path(job, gcode_dir)
        job["gcode_metadata"] = read_gcode_metadata(path)
        job["calibrated_material"] = resolve_calibrated_material(
            job, live.get("cfs_inventory", [])
        )

    latest = parsed["jobs"][-1] if parsed["jobs"] else None
    requested = [job for job in parsed["jobs"] if job.get("requested")]
    latest_requested = requested[-1] if requested else None
    preferences = ai_preferences()
    return {
        "build": BUILD,
        "generated_epoch": int(time.time()),
        "log_files": parsed["log_files"],
        "global_preferences_log": parsed["global_preferences"],
        "global_preferences_file": preferences,
        "live": live,
        "live_error": live_error,
        "latest_job": latest,
        "latest_requested_job": latest_requested,
        "confirmed_result": result_value(latest_requested),
        "profile_recommendation": profile_recommendation(latest_requested),
        "jobs": parsed["jobs"][-12:],
        "safety": {
            "read_only": True,
            "starts_print": False,
            "sends_gcode": False,
            "writes_profile": False,
            "runtime_values_are_measurements": False,
        },
    }


def format_number(value, digits=4):
    if value is None:
        return ""
    return ("%.*f" % (digits, value)).rstrip("0").rstrip(".")


def print_job(prefix, job):
    if not job:
        print(prefix + "|none")
        return
    print(
        "%s|status=%s|requested=%s|source=%s|time=%s|file=%s"
        % (
            prefix,
            job.get("classification"),
            int(bool(job.get("requested"))),
            clean_text(job.get("source")),
            clean_text(job.get("timestamp")),
            clean_text(Path(job.get("file") or "").name),
        )
    )
    pa = job["pa"]
    flow = job["flow"]
    pa_value = result_value(job)["pressure_advance"]
    print(
        "PA_RESULT|started=%s|measured=%s|value=%s|effective=%s|"
        "fallback=%s|errors=%s"
        % (
            int(pa["started"]),
            int(pa_value is not None),
            format_number(pa_value),
            format_number(pa.get("effective")),
            int(pa["fallback"]),
            len(pa["errors"]),
        )
    )
    print(
        "FLOW_RESULT|started=%s|measured=%s|percent=%s|m221=%s|"
        "unsupported=%s|errors=%s"
        % (
            int(flow["started"]),
            int(flow["measured"]),
            format_number(flow.get("percentage"), 2),
            format_number(flow.get("m221"), 2),
            int(flow["unsupported"]),
            len(flow["errors"]),
        )
    )
    lifecycle = job.get("lifecycle") or {}
    print(
        "CALIBRATION_LIFECYCLE|cancelled=%s|finished=%s|"
        "duplicate_start_requests=%s|reason=%s"
        % (
            int(bool(lifecycle.get("cancelled"))),
            int(bool(lifecycle.get("finished"))),
            int(lifecycle.get("duplicate_start_requests") or 0),
            clean_text(lifecycle.get("cancel_reason")),
        )
    )
    metadata = job.get("gcode_metadata") or {}
    print(
        "GCODE_MATERIAL|type=%s|profile=%s|id=%s|flow_ratio=%s|"
        "pa_enabled=%s|pa=%s|pla_flow_eligible=%s"
        % (
            clean_text(metadata.get("filament_type")),
            clean_text(metadata.get("filament_settings_id")),
            clean_text(metadata.get("filament_ids")),
            clean_text(metadata.get("filament_flow_ratio")),
            clean_text(metadata.get("enable_pressure_advance")),
            clean_text(metadata.get("pressure_advance")),
            int(bool(metadata.get("flow_pla_family"))),
        )
    )


def print_calibrated_material(job):
    material = (job or {}).get("calibrated_material") or {}
    print(
        "CALIBRATED_MATERIAL|logical=%s|slot=%s|id=%s|brand=%s|name=%s|"
        "type=%s|color=%s|remaining_percent=%s|spoolman=%s|verified=%s|"
        "attribution=%s"
        % (
            clean_text(material.get("logical_slot")),
            clean_text(material.get("slot")),
            clean_text(material.get("material_id")),
            clean_text(material.get("brand")),
            clean_text(material.get("name")),
            clean_text(material.get("type")),
            clean_text(material.get("color")),
            format_number(material.get("remaining_percent"), 1),
            clean_text(material.get("spoolman_spool_id")),
            int(bool(material.get("verified"))),
            clean_text(material.get("attribution")),
        )
    )


def print_status(report):
    file_preferences = report["global_preferences_file"]
    log_preferences = report["global_preferences_log"]
    print("FILAMENT_CALIBRATION|build=%s|read_only=1" % report["build"])
    print(
        "CALIBRATION_CONTROL|auto_pa=%s|auto_flow=%s|flow_mode=%s|"
        "per_job_enableSelfTest_required=1"
        % (
            clean_text(file_preferences.get("auto_pa")),
            clean_text(file_preferences.get("auto_flow")),
            clean_text(file_preferences.get("flow_mode")),
        )
    )
    print(
        "CALIBRATION_LOG_PREFS|auto_pa=%s|auto_flow=%s|flow_mode=%s|logs=%s"
        % (
            clean_text(log_preferences.get("auto_pa")),
            clean_text(log_preferences.get("auto_flow")),
            clean_text(log_preferences.get("flow_mode")),
            len(report["log_files"]),
        )
    )
    live = report["live"]
    cfs = live.get("cfs") or {}
    print(
        "CURRENT_MATERIAL|slot=%s|id=%s|brand=%s|name=%s|type=%s|"
        "remaining_percent=%s|db_pa=%s|db_flow_ratio=%s|"
        "database_values_are_measurements=0|spoolman=%s|cfs_fw=%s|"
        "selection_source=%s|calibration_attribution=0"
        % (
            clean_text(cfs.get("slot")),
            clean_text(cfs.get("material_id")),
            clean_text(cfs.get("brand")),
            clean_text(cfs.get("name")),
            clean_text(cfs.get("type")),
            format_number(cfs.get("remaining_percent"), 1),
            format_number(cfs.get("database_pressure")),
            format_number(cfs.get("database_flow_ratio")),
            clean_text(cfs.get("spoolman_spool_id")),
            clean_text(cfs.get("cfs_version")),
            clean_text(cfs.get("selection_source")),
        )
    )
    print(
        "CURRENT_RUNTIME|state=%s|file=%s|pressure_advance=%s|"
        "extrude_factor_percent=%s|flow_rate_file_percent=%s|"
        "measurement_source=no"
        % (
            clean_text(live.get("print_state")),
            clean_text(live.get("current_file")),
            format_number(live.get("runtime_pressure_advance")),
            format_number(
                live.get("runtime_extrude_factor") * 100
                if live.get("runtime_extrude_factor") is not None
                else None,
                2,
            ),
            format_number(live.get("flow_rate_file_percent"), 2),
        )
    )
    print_job("LATEST_JOB", report["latest_job"])
    print_job("LATEST_CALIBRATION", report["latest_requested_job"])
    print_calibrated_material(report["latest_requested_job"])
    confirmed = report["confirmed_result"]
    recommendation = report["profile_recommendation"]
    print(
        "CONFIRMED_MEASUREMENT|pressure_advance=%s|flow_percentage=%s|"
        "safe_to_persist=%s"
        % (
            format_number(confirmed.get("pressure_advance")),
            format_number(confirmed.get("flow_percentage"), 2),
            int(bool(recommendation.get("safe_to_persist"))),
        )
    )
    print(
        "PROFILE_RECOMMENDATION|pressure_advance=%s|base_flow_ratio=%s|"
        "flow_percentage=%s|flow_ratio=%s|slot=%s|id=%s|profile=%s|"
        "safe_to_persist=%s|reason=%s"
        % (
            format_number(recommendation.get("pressure_advance")),
            format_number(recommendation.get("base_flow_ratio")),
            format_number(recommendation.get("flow_percentage"), 2),
            format_number(recommendation.get("flow_ratio"), 6),
            clean_text(recommendation.get("slot")),
            clean_text(recommendation.get("material_id")),
            clean_text(recommendation.get("profile")),
            int(bool(recommendation.get("safe_to_persist"))),
            clean_text(recommendation.get("reason")),
        )
    )
    if report["latest_requested_job"] is None:
        print(
            "NEXT_STEP|start a small supported PLA job from Creality Print "
            "with Print calibration enabled; Fluidd/Mainsail/K2Dash normal "
            "starts do not request it"
        )
    elif report["latest_requested_job"]["classification"] != "complete":
        print(
            "NEXT_STEP|do not copy runtime/default values; review the requested "
            "job result and repeat only after the reported cause is resolved"
        )
    else:
        print(
            "NEXT_STEP|the measured values may be copied to the exact matching "
            "filament profile after material and CFS slot verification"
        )


def write_report(report, path):
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".tmp")
    temporary.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    temporary.replace(target)
    print("CALIBRATION_REPORT|written=%s" % target)


def selftest():
    failures = []
    sample = [
        "[2026-07-31 10:00:00.000]-[INF]- with self test = 1",
        "[2026-07-31 10:00:00.100]-[INF]- start print file = /gcodes/a.gcode",
        "[2026-07-31 10:00:01.000]-[INF]- flowdetect = 1, flow_em_detect = 1",
        "[2026-07-31 10:00:02.000]-[INF]- start flow_pa detect",
        "[2026-07-31 10:00:02.100]-[INF]- T-Command map: T0(T1A)=>T1B",
        "[2026-07-31 10:00:02.200]-[INF]- "
        "FlowPa_ExtractAndSetGcodeParams CFS t_command: T0, Vender: unknown, "
        "Remain Length: 100, Color Value: 9ea7ae, Material Type: 90001, "
        "Material Name: PLA, Pressure Advance: 0.040",
        "[2026-07-31 10:00:03.000]-[INF]- flow_pa result: pressureAdvance=0.047",
        "[2026-07-31 10:00:04.000]-[INF]- flow_pa best_flow_pressure_advance = 0.046",
        "[2026-07-31 10:00:05.000]-[INF]- start flow_em detect",
        "[2026-07-31 10:00:06.000]-[INF]- flow_em best_flow_percentage = 97",
        "[2026-07-31 10:00:07.000]-[INF]- M221 S97",
    ]

    original = iter_log_lines
    try:
        globals()["iter_log_lines"] = lambda _path: iter(sample)
        parsed = parse_calibration_logs([Path("synthetic.log")])
    finally:
        globals()["iter_log_lines"] = original
    job = parsed["jobs"][0]
    if job["classification"] != "complete":
        failures.append("complete classification failed")
    if result_value(job) != {"pressure_advance": 0.046, "flow_percentage": 97.0}:
        failures.append("confirmed result extraction failed")
    job["gcode_metadata"] = {
        "filament_flow_ratio": "0.98",
        "filament_settings_id": "eSUN PLA HS+ Gray",
        "flow_pla_family": True,
    }
    job["calibrated_material"] = resolve_calibrated_material(
        job,
        [
            {
                "slot": "T1B",
                "material_id": "090001",
                "brand": "eSUN",
                "name": "ePLA-HS+ Gray",
                "type": "PLA",
                "color": "09ea7ae",
                "remaining_percent": 100.0,
            }
        ],
    )
    recommendation = profile_recommendation(job)
    if job["calibrated_material"]["slot"] != "T1B":
        failures.append("physical CFS slot attribution failed")
    if not job["calibrated_material"]["verified"]:
        failures.append("CFS material verification failed")
    if recommendation["flow_ratio"] != 0.9506 or not recommendation["safe_to_persist"]:
        failures.append("profile flow-ratio recommendation failed")

    fallback = new_job(1, sample[0], True)
    fallback["pa"].update(
        {
            "started": True,
            "measured": False,
            "fallback": True,
            "fallback_value": 0.038,
        }
    )
    if classify_job(fallback) != "fallback":
        failures.append("fallback classification failed")

    unsupported = new_job(1, sample[0], True)
    unsupported["pa"].update({"started": True, "measured": True, "best": 0.05})
    unsupported["flow"].update({"started": True, "unsupported": True})
    if classify_job(unsupported) != "partial":
        failures.append("unsupported partial classification failed")

    ordinary = new_job(1, sample[0], False)
    ordinary["waste_checks"] = 2
    if classify_job(ordinary) != "not_requested":
        failures.append("waste-only ordinary print classification failed")

    if failures:
        for failure in failures:
            print("SELFTEST_FAIL|" + failure)
        return 1
    print(
        "SELFTEST|OK|requested, measured, fallback, unsupported and "
        "waste-only states plus physical CFS attribution"
    )
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--status", action="store_true")
    action.add_argument("--json", action="store_true")
    action.add_argument("--write-report", metavar="PATH", nargs="?", const=str(DEFAULT_REPORT))
    action.add_argument("--selftest", action="store_true")
    parser.add_argument("--log-dir", default=str(LOG_DIR))
    parser.add_argument("--gcode-dir", default=str(GCODE_DIR))
    parser.add_argument(
        "--archives",
        type=int,
        default=0,
        choices=range(0, 7),
        metavar="0..6",
        help="also scan this many rotated gzip logs (slower on the printer)",
    )
    args = parser.parse_args(argv or sys.argv[1:])

    if args.selftest:
        return selftest()
    report = build_report(
        Path(args.log_dir), Path(args.gcode_dir), max_archives=args.archives
    )
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    elif args.write_report:
        write_report(report, args.write_report)
        print_status(report)
    else:
        print_status(report)
    return 0 if not report["live_error"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
