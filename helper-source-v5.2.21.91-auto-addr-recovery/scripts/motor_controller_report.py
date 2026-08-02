#!/usr/bin/env python3
"""Read-only K2 Pro CFS and motor-controller health report."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
import time
import urllib.request
from dataclasses import dataclass, field
from typing import Any


DEFAULT_STATUS_URL = (
    "http://127.0.0.1:7125/printer/objects/query?"
    "print_stats&extruder&heater_bed&motor_control&box"
)
MOTOR_ERROR_RE = re.compile(r"\bkey(?:\s*[:=]?\s*)(78[1-9]|79[0-7])\b", re.I)
CONFIG_FW_RE = re.compile(r"FW:\s*(mot\S+?_(\d{3})\.bin)", re.I)
APP_REV_RE = re.compile(r"_(\d{3})(?:\.bin)?$")
UPDATER_FAILURES = (
    re.compile(r"\bfw_update\s+fail", re.I),
    re.compile(r"\bupdate\s+fw\s+bin\s+fail", re.I),
    re.compile(r"\bhandshake\b.*\bfail", re.I),
    re.compile(r"\bstartup\s+app\s+fail", re.I),
    re.compile(r"\bupdate\s*:\s*fail(?:ed)?\b", re.I),
)
EXPECTED_RUNTIME_HANDSHAKE_GAP = re.compile(
    r"\bhandshake\s+/dev/ttyS[23]\s+fail,\s*ret=2\b", re.I
)


@dataclass
class Reporter:
    lines: list[str] = field(default_factory=list)
    ok_count: int = 0
    info_count: int = 0
    warn_count: int = 0
    fail_count: int = 0
    summary_fields: dict[str, str] = field(default_factory=dict)

    def add(self, level: str, message: str) -> None:
        normalized = level.upper()
        self.lines.append(f"[{normalized}] {message}")
        if normalized == "OK":
            self.ok_count += 1
        elif normalized == "INFO":
            self.info_count += 1
        elif normalized == "WARN":
            self.warn_count += 1
        elif normalized == "FAIL":
            self.fail_count += 1

    @property
    def exit_code(self) -> int:
        if self.fail_count:
            return 2
        if self.warn_count:
            return 1
        return 0

    def summary(self) -> str:
        fields = {
            "ok": str(self.ok_count),
            "info": str(self.info_count),
            "warn": str(self.warn_count),
            "fail": str(self.fail_count),
            **self.summary_fields,
            "read_only": "true",
        }
        values = "|".join(f"{key}={value}" for key, value in fields.items())
        return f"MOTOR_CONTROLLER_SUMMARY|{values}"


def read_text(path: str, max_bytes: int = 4 * 1024 * 1024) -> str:
    source = pathlib.Path(path)
    if not source.is_file():
        return ""
    with source.open("rb") as handle:
        handle.seek(0, os.SEEK_END)
        size = handle.tell()
        handle.seek(max(0, size - max_bytes), os.SEEK_SET)
        data = handle.read()
    return data.decode("utf-8", errors="replace")


def load_json(path: str) -> dict[str, Any]:
    text = read_text(path)
    if not text:
        return {}
    value = json.loads(text)
    return value if isinstance(value, dict) else {}


def fetch_status(url: str, attempts: int = 4) -> dict[str, Any]:
    last_error: Exception | None = None
    latest: dict[str, Any] = {}
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                payload = json.loads(response.read().decode("utf-8"))
            latest = payload.get("result", {}).get("status", {})
            motor = latest.get("motor_control", {})
            if motor.get("motor_ready") is True:
                return latest
        except Exception as exc:  # pragma: no cover - exercised through CLI failures
            last_error = exc
        if attempt + 1 < attempts:
            time.sleep(1)
    if latest:
        return latest
    if last_error:
        raise RuntimeError(str(last_error)) from last_error
    raise RuntimeError("Moonraker returned no status data")


def app_revision(version: Any) -> str:
    match = APP_REV_RE.search(str(version or ""))
    return match.group(1) if match else "unknown"


def cfs_revision_to_display(revision: str) -> str:
    if len(revision) == 3 and revision.isdigit():
        return ".".join(revision)
    return "unknown"


def update_state_is_done(value: Any) -> bool:
    return str(value or "").strip().lower() in {"done", "none", "not_needed"}


def analyze(
    status: dict[str, Any],
    rs485: dict[str, Any],
    mcu: dict[str, Any],
    updater_log: str,
    klippy_log: str,
    motor_config: str,
) -> Reporter:
    report = Reporter()

    print_stats = status.get("print_stats", {})
    extruder = status.get("extruder", {})
    heater_bed = status.get("heater_bed", {})
    motor = status.get("motor_control", {})
    box = status.get("box", {})
    t1 = box.get("T1", {}) if isinstance(box.get("T1"), dict) else {}

    state = str(print_stats.get("state") or "unknown")
    report.add(
        "INFO",
        "Printer state=%s, hotend target=%s C, bed target=%s C"
        % (state, extruder.get("target"), heater_bed.get("target")),
    )

    motor_ready = motor.get("motor_ready") is True
    report.summary_fields["motor_ready"] = str(motor_ready).lower()
    if motor_ready:
        report.add("OK", "Klipper motor_control reports motor_ready=true")
    else:
        report.add("FAIL", "Klipper motor_control is not ready")

    is_homing = motor.get("is_homing") is True
    report.summary_fields["is_homing"] = str(is_homing).lower()
    report.add("INFO", f"Homing activity={str(is_homing).lower()}")
    cut = motor.get("cut", {}) if isinstance(motor.get("cut"), dict) else {}
    report.add(
        "INFO",
        "Cutter feedback state=%s, X reference=%s"
        % (cut.get("state", "unknown"), cut.get("pos_x", "unknown")),
    )

    box_state = str(box.get("state") or "unknown")
    cfs_version = str(t1.get("version") or "unknown")
    report.summary_fields["cfs_connected"] = str(box_state == "connect").lower()
    report.summary_fields["cfs_version"] = cfs_version
    if box_state == "connect":
        report.add("OK", f"CFS/BOX connected; reported firmware={cfs_version}")
    else:
        report.add("WARN", f"CFS/BOX state is {box_state}")
    report.add("INFO", f"CFS mode={t1.get('mode', 'unknown')}")

    controllers = rs485.get("Motors", [])
    controllers = controllers if isinstance(controllers, list) else []
    report.summary_fields["controllers"] = str(len(controllers))
    if len(controllers) == 2:
        report.add("OK", "Two external X/Y motor controllers were discovered")
    else:
        report.add("WARN", f"Expected two X/Y motor controllers, found {len(controllers)}")

    motor_revisions: list[str] = []
    for index, controller in enumerate(controllers, 1):
        if not isinstance(controller, dict):
            report.add("FAIL", f"Motor controller {index} has invalid version data")
            continue
        version = str(controller.get("version") or "unknown")
        revision = app_revision(version)
        motor_revisions.append(revision)
        update = str(controller.get("update") or "unknown")
        addr = str(controller.get("addr") or index)
        if update_state_is_done(update):
            report.add("OK", f"Motor controller addr={addr}: version={version}, update={update}")
        else:
            report.add("FAIL", f"Motor controller addr={addr}: update state={update}")

    known_motor_revisions = sorted(set(item for item in motor_revisions if item != "unknown"))
    report.summary_fields["motor_app"] = (
        ",".join(known_motor_revisions) if known_motor_revisions else "unknown"
    )
    if len(known_motor_revisions) > 1:
        report.add("FAIL", "X/Y motor controllers do not use the same application revision")

    cfs_devices = rs485.get("CFSs", [])
    cfs_devices = cfs_devices if isinstance(cfs_devices, list) else []
    cfs_app_revision = "unknown"
    if cfs_devices:
        first_cfs = cfs_devices[0] if isinstance(cfs_devices[0], dict) else {}
        cfs_fw = str(first_cfs.get("version") or "unknown")
        cfs_app_revision = app_revision(cfs_fw)
        cfs_update = str(first_cfs.get("update") or "unknown")
        report.summary_fields["cfs_app"] = cfs_app_revision
        if update_state_is_done(cfs_update):
            report.add("OK", f"CFS controller firmware={cfs_fw}, update={cfs_update}")
        else:
            report.add("FAIL", f"CFS controller update state={cfs_update}")
        translated = cfs_revision_to_display(cfs_app_revision)
        if cfs_version not in {"unknown", "-1", "None"} and translated != cfs_version:
            report.add(
                "WARN",
                f"CFS runtime version {cfs_version} differs from updater image {translated}",
            )
    else:
        report.summary_fields["cfs_app"] = "unknown"
        if box_state == "connect" and cfs_version not in {"unknown", "-1", "None"}:
            report.add(
                "INFO",
                "CFS is connected at runtime but the vendor updater did not populate "
                ".485_mcu_version",
            )
        else:
            report.add("WARN", "No CFS controller entry found in .485_mcu_version")

    extruder_info = mcu.get("extruder", {})
    extruder_info = extruder_info if isinstance(extruder_info, dict) else {}
    extruder_version = str(extruder_info.get("version") or "unknown")
    extruder_revision = app_revision(extruder_version)
    report.summary_fields["extruder_app"] = extruder_revision
    if extruder_revision == "unknown":
        level = "WARN" if motor_ready else "FAIL"
        report.add(
            level,
            "Extruder motor-controller version is unavailable in the vendor version table; "
            f"runtime motor_ready={str(motor_ready).lower()}",
        )
    else:
        report.add("OK", f"Extruder motor controller version={extruder_version}")
        if known_motor_revisions and extruder_revision not in known_motor_revisions:
            report.add(
                "WARN",
                "Extruder and X/Y application revisions differ: "
                f"E={extruder_revision}, XY={','.join(known_motor_revisions)}",
            )

    for name, label in (("mcu0", "Main MCU"), ("noz0", "Nozzle MCU")):
        value = mcu.get(name, {})
        version = value.get("version") if isinstance(value, dict) else None
        if version:
            report.add("OK", f"{label} version={version}")
        else:
            level = "INFO" if motor_ready else "WARN"
            report.add(
                level,
                f"{label} version is unavailable in the vendor version table",
            )

    config_match = CONFIG_FW_RE.search(motor_config)
    if config_match and known_motor_revisions:
        configured_file = config_match.group(1)
        configured_revision = config_match.group(2)
        if configured_revision != known_motor_revisions[0]:
            report.add(
                "INFO",
                "Vendor config comment is stale (%s); live controller revision is %s. "
                "No config edit is required."
                % (configured_file, known_motor_revisions[0]),
            )

    discovery_timeouts = sum(
        1 for line in updater_log.splitlines() if "send msg timeout" in line.lower()
    )
    detected_updater_failures = [
        line.strip()
        for line in updater_log.splitlines()
        if any(pattern.search(line) for pattern in UPDATER_FAILURES)
    ]
    runtime_handshake_gaps = [
        line
        for line in detected_updater_failures
        if motor_ready and EXPECTED_RUNTIME_HANDSHAKE_GAP.search(line)
    ]
    updater_failure_lines = [
        line for line in detected_updater_failures if line not in runtime_handshake_gaps
    ]
    update_done_count = sum(
        1 for line in updater_log.splitlines() if re.search(r"update\s*:\s*done", line, re.I)
    )
    report.summary_fields["updater_failures"] = str(len(updater_failure_lines))
    report.summary_fields["updater_handshake_gaps"] = str(len(runtime_handshake_gaps))
    if updater_failure_lines:
        report.add("FAIL", f"MCU updater reports {len(updater_failure_lines)} real failure line(s)")
    elif runtime_handshake_gaps:
        report.add(
            "WARN",
            "Vendor MCU version probing reported %d expected ttyS2/ttyS3 ret=2 "
            "handshake gap(s), but runtime motor_ready=true; this is not classified "
            "as a flash failure" % len(runtime_handshake_gaps),
        )
    elif updater_log:
        report.add("OK", "MCU updater log contains no real flash or handshake failure")
    else:
        report.add("WARN", "MCU updater log is unavailable")
    report.add(
        "INFO",
        f"Updater evidence: update_done={update_done_count}, discovery_timeouts={discovery_timeouts}",
    )
    if discovery_timeouts:
        report.add(
            "INFO",
            "Discovery timeouts occur while probing unused/broadcast addresses and are not "
            "treated as update failures.",
        )

    motor_error_keys: list[str] = []
    startup_none = 0
    for line in klippy_log.splitlines():
        lowered = line.lower()
        if "update_flash_param" in lowered and "result is none" in lowered:
            startup_none += 1
        match = MOTOR_ERROR_RE.search(line)
        if match and ("[error]" in lowered or "[warning]" in lowered):
            motor_error_keys.append(match.group(1))
    unique_motor_keys = sorted(set(motor_error_keys), key=int)
    report.summary_fields["motor_error_keys"] = (
        ",".join(unique_motor_keys) if unique_motor_keys else "none"
    )
    if unique_motor_keys:
        report.add(
            "WARN",
            "Recent Klipper log contains motor error-key evidence: "
            + ",".join(unique_motor_keys),
        )
    else:
        report.add("OK", "No key781-key797 motor error evidence in the recent Klipper log")
    if startup_none:
        level = "INFO" if motor_ready else "WARN"
        report.add(
            level,
            f"Vendor startup logged {startup_none} parameter acknowledgement(s) as None; "
            f"current motor_ready={str(motor_ready).lower()}.",
        )

    report.add(
        "INFO",
        "Safety: this report performs HTTP GET and file reads only; it never sends G-code, "
        "motor, CFS, calibration, reboot or flash commands.",
    )
    return report


def healthy_fixture() -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    status = {
        "print_stats": {"state": "standby"},
        "extruder": {"target": 0.0},
        "heater_bed": {"target": 0.0},
        "motor_control": {
            "motor_ready": True,
            "is_homing": False,
            "cut": {"state": True, "pos_x": -9.5},
        },
        "box": {"state": "connect", "T1": {"version": "1.5.0", "mode": "0"}},
    }
    rs485 = {
        "Motors": [
            {"addr": "85", "version": "mot2_023_C30-mot2_002_081", "update": "done"},
            {"addr": "86", "version": "mot2_023_C30-mot2_002_081", "update": "done"},
        ],
        "CFSs": [
            {"addr": "01", "version": "cfs0_050_G32-cfs0_000_150", "update": "done"}
        ],
    }
    mcu = {
        "mcu0": {"version": "mcu0_120_G32-mcu0_001_000"},
        "noz0": {"version": "noz0_130_G30-noz0_021_000"},
        "extruder": {"version": "mot2_022_C30-mot2_002_081"},
    }
    return status, rs485, mcu


def selftest() -> int:
    status, rs485, mcu = healthy_fixture()
    result = analyze(
        status,
        rs485,
        mcu,
        "send msg timeout\naddr [85] dev [motor], update: done\n",
        "[INFO] printer ready\n",
        "# FW: mot2_023_C30-mot2_002_071.bin\n",
    )
    assert result.exit_code == 0
    assert result.summary_fields["motor_app"] == "081"
    assert result.summary_fields["extruder_app"] == "081"
    assert result.summary_fields["cfs_app"] == "150"
    assert result.summary_fields["updater_failures"] == "0"
    assert any("stale" in line for line in result.lines)
    print("MOTOR_CONTROLLER_SELFTEST_OK")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--status-json", help="Use a local Moonraker status fixture")
    parser.add_argument(
        "--status-url", default=os.environ.get("K2_MOTOR_STATUS_URL", DEFAULT_STATUS_URL)
    )
    parser.add_argument(
        "--rs485-version",
        default=os.environ.get("K2_RS485_VERSION_FILE", "/tmp/.485_mcu_version"),
    )
    parser.add_argument(
        "--mcu-version", default=os.environ.get("K2_MCU_VERSION_FILE", "/tmp/.mcu_version")
    )
    parser.add_argument(
        "--updater-log", default=os.environ.get("K2_MCU_UPDATE_LOG", "/tmp/mcu_update.log")
    )
    parser.add_argument(
        "--klippy-log",
        default=os.environ.get(
            "K2_KLIPPY_LOG", "/mnt/UDISK/printer_data/logs/klippy.log"
        ),
    )
    parser.add_argument(
        "--motor-config",
        default=os.environ.get(
            "K2_MOTOR_CONFIG", "/mnt/UDISK/printer_data/config/motor_control.cfg"
        ),
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    if args.selftest:
        return selftest()

    try:
        if args.status_json:
            payload = load_json(args.status_json)
            status = payload.get("result", {}).get("status", payload)
        else:
            status = fetch_status(args.status_url)
        result = analyze(
            status,
            load_json(args.rs485_version),
            load_json(args.mcu_version),
            read_text(args.updater_log),
            read_text(args.klippy_log),
            read_text(args.motor_config, max_bytes=512 * 1024),
        )
    except Exception as exc:
        result = Reporter()
        result.add("FAIL", f"Motor-controller report could not be generated: {exc}")
        result.summary_fields["motor_ready"] = "unknown"
        result.summary_fields["controllers"] = "unknown"
        result.summary_fields["updater_failures"] = "unknown"
        result.summary_fields["motor_error_keys"] = "unknown"

    print("K2 Pro Combo Motorcontroller-Status (read-only)")
    for line in result.lines:
        print(line)
    print(result.summary())
    return result.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
