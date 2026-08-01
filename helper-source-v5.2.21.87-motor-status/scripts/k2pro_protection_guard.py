#!/usr/bin/env python3
"""Read-only firmware, config, recovery, CFS and database guard for K2 Pro/F012."""

from __future__ import annotations

import argparse
import ast
import glob
import hashlib
import json
import os
import re
import subprocess
import tarfile
import urllib.request
from pathlib import Path
from typing import Any


EXPECTED_MODEL = "F012"
EXPECTED_BOARD = "CR0CN200400C10"
EXPECTED_SIZE = "300*300*300"
KNOWN_BASELINE_FIRMWARE = "1.1.6.7"
CUSTOM_PROFILE_IDS = ("90001", "90002")
SLOTS = ("T1A", "T1B", "T1C", "T1D")


def env_path(name: str, default: str) -> Path:
    return Path(os.environ.get(name, default))


CONFIG_DIR = env_path("K2_GUARD_CONFIG_DIR", "/mnt/UDISK/printer_data/config")
FACTORY_DIR = env_path(
    "K2_GUARD_FACTORY_DIR",
    "/usr/share/klipper/config/F012_CR0CN200400C10",
)
F012_FW_DIR = env_path("K2_GUARD_F012_FW_DIR", "/usr/share/klipper/fw/F012")
CFS_FW_DIR = env_path("K2_GUARD_CFS_FW_DIR", "/usr/share/klipper/fw/cfs")
AUTO_ADDR_WRAPPER = env_path(
    "K2_GUARD_AUTO_ADDR_WRAPPER",
    "/usr/share/klipper/klippy/extras/auto_addr_wrapper.py",
)
CAMERA_CONFIG = env_path(
    "K2_GUARD_CAMERA_CONFIG",
    "/mnt/UDISK/creality/userdata/config/cam_version.json",
)
CAMERA_FW_DIR = env_path("K2_GUARD_CAMERA_FW_DIR", "/usr/share/uvc/fw")
BOX_DIR = env_path("K2_GUARD_BOX_DIR", "/mnt/UDISK/creality/userdata/box")
HELPER_DIR = env_path("K2_GUARD_HELPER_DIR", "/mnt/UDISK/helper-script")
BACKUP_DIR = env_path(
    "K2_GUARD_BACKUP_DIR",
    "/mnt/UDISK/printer_data/backups/k2pro_helper",
)
UDISK_DIR = env_path("K2_GUARD_UDISK_DIR", "/mnt/UDISK")
RESTORE_PAYLOAD = env_path(
    "K2_GUARD_RESTORE_PAYLOAD",
    "/mnt/UDISK/k2pro_mod_restore_payload_current.tar.gz",
)
SYSTEM_VERSION = env_path(
    "K2_GUARD_SYSTEM_VERSION",
    "/mnt/UDISK/creality/userdata/config/system_version.json",
)
MCU_VERSION = env_path("K2_GUARD_MCU_VERSION", "/tmp/.mcu_version")
DB_GUARD_STATE = env_path(
    "K2_GUARD_DB_STATE",
    "/mnt/UDISK/helper-script/state/cfs_db_guard_state.json",
)
CFS_SAFE_STATE = env_path(
    "K2_GUARD_CFS_SAFE_STATE",
    "/mnt/UDISK/helper-script/state/cfs_safe_tools_state.json",
)
SPOOLMAN_MAP = env_path(
    "K2_GUARD_SPOOLMAN_MAP",
    "/mnt/UDISK/helper-script/spoolman_cfs_map.json",
)


class Report:
    def __init__(self) -> None:
        self.sections: list[dict[str, Any]] = []
        self.current: dict[str, Any] | None = None

    def section(self, name: str) -> None:
        row = {"name": name, "findings": [], "data": {}}
        self.sections.append(row)
        self.current = row

    def data(self, key: str, value: Any) -> None:
        if self.current is None:
            self.section("General")
        assert self.current is not None
        self.current["data"][key] = value

    def add(self, level: str, code: str, message: str) -> None:
        if self.current is None:
            self.section("General")
        assert self.current is not None
        self.current["findings"].append(
            {"level": level, "code": code, "message": message}
        )

    def findings(self) -> list[dict[str, str]]:
        return [
            finding
            for section in self.sections
            for finding in section["findings"]
        ]

    def counts(self) -> dict[str, int]:
        counts = {level: 0 for level in ("OK", "INFO", "WARN", "FAIL")}
        for finding in self.findings():
            counts[finding["level"]] = counts.get(finding["level"], 0) + 1
        return counts

    def failed(self) -> bool:
        return self.counts()["FAIL"] > 0

    def as_dict(self) -> dict[str, Any]:
        return {"sections": self.sections, "summary": self.counts()}


def run_text(command: list[str], timeout: int = 5) -> str:
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (FileNotFoundError, subprocess.SubprocessError):
        return ""
    return result.stdout.strip()


def read_json(path: Path, default: Any = None) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError, TypeError):
        return default


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def normalized_version(value: str) -> tuple[int, ...] | None:
    match = re.search(r"(\d+(?:\.\d+){1,4})", str(value or ""))
    if not match:
        return None
    return tuple(int(part) for part in match.group(1).split("."))


def version_compare(left: str, right: str) -> int | None:
    left_value = normalized_version(left)
    right_value = normalized_version(right)
    if left_value is None or right_value is None:
        return None
    width = max(len(left_value), len(right_value))
    left_value += (0,) * (width - len(left_value))
    right_value += (0,) * (width - len(right_value))
    return (left_value > right_value) - (left_value < right_value)


def first_nonempty(*values: str) -> str:
    for value in values:
        if str(value or "").strip():
            return str(value).strip()
    return ""


def identity() -> dict[str, str]:
    system = read_json(SYSTEM_VERSION, {}) or {}
    model = first_nonempty(
        os.environ.get("K2_GUARD_MODEL", ""),
        run_text(["/usr/bin/get_sn_mac.sh", "model"]),
    )
    if not model:
        active = read_text(CONFIG_DIR / "factory_printer.cfg")
        match = re.search(r"(?m)^\s*#\s*(F\d+)\s*$", active)
        model = match.group(1) if match else ""

    board = first_nonempty(
        os.environ.get("K2_GUARD_BOARD", ""),
        run_text(["/usr/bin/get_sn_mac.sh", "board"]),
        str(system.get("hw_version", "")),
        env_value("board"),
    )
    firmware = first_nonempty(
        os.environ.get("K2_GUARD_FIRMWARE", ""),
        run_text(["/etc/ota_bin/get_ota_current_version.sh"]),
        env_value("version"),
        str(system.get("sys_version", "")),
    )
    boot_partition = first_nonempty(
        os.environ.get("K2_GUARD_BOOT_PARTITION", ""),
        env_value("boot_partition"),
    )
    return {
        "model": model or "unknown",
        "board": board or "unknown",
        "firmware": firmware or "unknown",
        "boot_partition": boot_partition or "unknown",
    }


def env_value(name: str) -> str:
    output = run_text(["fw_printenv", name])
    if "=" in output:
        return output.split("=", 1)[1].strip()
    return output.strip()


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def camera_identity() -> dict[str, str]:
    data = read_json(CAMERA_CONFIG, {}) or {}
    main = data.get("main_cam", {}) if isinstance(data, dict) else {}
    return {
        "model": str(main.get("manufactory") or "unknown"),
        "version": str(main.get("cur_version") or "unknown"),
    }


def query_cfs_version() -> str:
    override = os.environ.get("K2_GUARD_CFS_VERSION", "")
    if override:
        return override
    try:
        with urllib.request.urlopen(
            "http://127.0.0.1:7125/printer/objects/query?box",
            timeout=4,
        ) as response:
            data = json.loads(response.read().decode("utf-8", errors="replace"))
        box = data.get("result", {}).get("status", {}).get("box", {}) or {}
        return str((box.get("T1", {}) or {}).get("version") or "")
    except Exception:
        return ""


def matching_files(directory: Path, pattern: str) -> list[Path]:
    try:
        return sorted(path for path in directory.glob(pattern) if path.is_file())
    except OSError:
        return []


def firmware_report(report: Report) -> None:
    report.section("Firmware compatibility")
    live = identity()
    report.data("identity", live)

    if live["model"] == EXPECTED_MODEL:
        report.add("OK", "MODEL_EXACT", "Model is exact K2 Pro/F012")
    else:
        report.add(
            "FAIL",
            "MODEL_MISMATCH",
            "Expected F012, detected %s" % live["model"],
        )

    if live["board"] == EXPECTED_BOARD:
        report.add("OK", "BOARD_EXACT", "Board is exact %s" % EXPECTED_BOARD)
    else:
        report.add(
            "FAIL",
            "BOARD_MISMATCH",
            "Expected %s, detected %s" % (EXPECTED_BOARD, live["board"]),
        )

    compare = version_compare(live["firmware"], KNOWN_BASELINE_FIRMWARE)
    if compare is None:
        report.add(
            "WARN",
            "FIRMWARE_UNKNOWN",
            "Could not parse installed firmware version %s" % live["firmware"],
        )
    elif compare < 0:
        report.add(
            "WARN",
            "FIRMWARE_BELOW_BASELINE",
            "Installed firmware %s is older than known baseline %s"
            % (live["firmware"], KNOWN_BASELINE_FIRMWARE),
        )
    elif compare == 0:
        report.add(
            "OK",
            "FIRMWARE_BASELINE",
            "Installed firmware matches known F012 baseline %s"
            % KNOWN_BASELINE_FIRMWARE,
        )
    else:
        report.add(
            "INFO",
            "FIRMWARE_NEWER",
            "Installed firmware %s is newer than the known baseline and needs release review"
            % live["firmware"],
        )

    if live["boot_partition"] in ("bootA", "bootB"):
        report.add(
            "OK",
            "BOOT_PARTITION",
            "A/B boot partition is readable: %s" % live["boot_partition"],
        )
    else:
        report.add(
            "WARN",
            "BOOT_PARTITION_UNKNOWN",
            "A/B boot partition could not be confirmed",
        )

    if FACTORY_DIR.is_dir():
        report.add(
            "OK",
            "FACTORY_TREE_EXACT",
            "Exact F012/board factory tree is present",
        )
    else:
        report.add(
            "FAIL",
            "FACTORY_TREE_MISSING",
            "Exact F012/board factory tree is missing: %s" % FACTORY_DIR,
        )

    firmware_1167 = version_compare(live["firmware"], "1.1.6.7")
    if firmware_1167 is not None and firmware_1167 >= 0:
        wrapper_text = read_text(AUTO_ADDR_WRAPPER)
        if "DEV_TYPE_CFS_PRO = 10" in wrapper_text:
            report.add(
                "OK",
                "CFS2_HOST_SUPPORT",
                "Firmware host layer contains the 1.1.6.7 CFS-Pro protocol marker",
            )
        else:
            report.add(
                "FAIL",
                "CFS2_HOST_SUPPORT_MISSING",
                "Firmware 1.1.6.7 or newer is active, but its CFS-Pro host marker is missing",
            )
        if "time_interval = 10.0" in wrapper_text:
            report.add(
                "OK",
                "CFS_POLL_INTERVAL",
                "Reviewed 10-second idle CFS polling interval is active",
            )
        else:
            report.add(
                "INFO",
                "CFS_POLL_INTERVAL_STOCK",
                "CFS host layer uses the firmware default polling interval",
            )

    camera = camera_identity()
    report.data("camera", camera)
    camera_files = matching_files(CAMERA_FW_DIR, "*.bin")
    exact_camera = [
        path for path in camera_files if camera["model"].lower() in path.name.lower()
    ]
    foreign_camera = [
        path for path in camera_files if camera["model"].lower() not in path.name.lower()
    ]
    if exact_camera:
        report.add(
            "OK",
            "CAMERA_IMAGE_EXACT",
            "Exact camera recovery image found for %s" % camera["model"],
        )
    elif foreign_camera:
        report.add(
            "INFO",
            "CAMERA_IMAGE_MISMATCH_BLOCKED",
            "No image matches %s; foreign camera image remains blocked"
            % camera["model"],
        )
    else:
        report.add(
            "INFO",
            "CAMERA_IMAGE_ABSENT",
            "No local camera recovery image is installed",
        )

    required_f012 = {
        "main_mcu": "mcu0_*.bin",
        "nozzle_mcu": "noz0_*.bin",
        "motor_x": "mot0_*.bin",
        "motor_y": "mot1_*.bin",
        "motor_extruder": "mot2_*.bin",
        "rfid": "rfid/rfd0_*.bin",
    }
    missing = [
        label
        for label, pattern in required_f012.items()
        if not matching_files(F012_FW_DIR, pattern)
    ]
    if missing:
        report.add(
            "FAIL",
            "F012_MCU_BUNDLE_INCOMPLETE",
            "Missing exact F012 firmware groups: %s" % ",".join(missing),
        )
    else:
        report.add(
            "OK",
            "F012_MCU_BUNDLE",
            "Exact F012 MCU, motor and RFID bundles are present",
        )

    cfs_version = query_cfs_version()
    report.data("cfs_version", cfs_version or "unknown")
    cfs_suffix = re.sub(r"\D", "", cfs_version)
    cfs_images = matching_files(CFS_FW_DIR, "cfs0_*.bin")
    cfs_image_suffixes = sorted(
        {
            match.group(1)
            for path in cfs_images
            if (match := re.search(r"_(\d+)\.bin$", path.name))
        }
    )
    report.data("cfs_image_suffixes", cfs_image_suffixes)
    if cfs_suffix and any("_%s.bin" % cfs_suffix in path.name for path in cfs_images):
        report.add(
            "OK",
            "CFS_IMAGE_MATCH",
            "Bundled CFS image matches connected version %s" % cfs_version,
        )
    elif (
        cfs_suffix.isdigit()
        and cfs_image_suffixes
        and any(int(suffix) > int(cfs_suffix) for suffix in cfs_image_suffixes)
    ):
        newest = max(cfs_image_suffixes, key=int)
        display_version = ".".join(newest) if len(newest) == 3 else newest
        report.add(
            "INFO",
            "CFS_UPDATE_AVAILABLE",
            "Connected CFS is %s; firmware bundles newer CFS %s as a separate update"
            % (cfs_version, display_version),
        )
    elif cfs_images:
        report.add(
            "WARN",
            "CFS_IMAGE_VERSION_REVIEW",
            "CFS images exist, but none can be matched to live version %s"
            % (cfs_version or "unknown"),
        )
    else:
        report.add(
            "WARN",
            "CFS_IMAGE_MISSING",
            "No local CFS firmware image found",
        )

    if MCU_VERSION.is_file():
        report.add(
            "OK",
            "MCU_VERSION_EVIDENCE",
            "Live MCU version inventory exists",
        )
    else:
        report.add(
            "INFO",
            "MCU_VERSION_EVIDENCE_MISSING",
            "Live MCU version inventory file is unavailable",
        )


def section_value(text: str, section: str, key: str) -> str:
    current = ""
    for raw_line in text.splitlines():
        line = raw_line.strip()
        section_match = re.match(r"^\[([^\]]+)\]$", line)
        if section_match:
            current = section_match.group(1).strip()
            continue
        if current != section or not line or line.startswith(("#", ";")):
            continue
        key_match = re.match(r"^%s\s*[:=]\s*(.*?)\s*$" % re.escape(key), line)
        if key_match:
            return key_match.group(1).split("#", 1)[0].strip()
    return ""


def has_pattern(text: str, pattern: str) -> bool:
    return re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE) is not None


def path_is_within(path: Path, directory: Path) -> bool:
    try:
        path.resolve().relative_to(directory.resolve())
        return True
    except (OSError, ValueError):
        return False


def active_config_files() -> list[Path]:
    """Resolve the active Klipper include tree starting at printer.cfg."""
    root = CONFIG_DIR.resolve()
    queue = [root / "printer.cfg"]
    seen: set[Path] = set()
    ordered: list[Path] = []
    include_pattern = re.compile(
        r"^\s*\[include\s+([^\]]+)\]\s*(?:[#;].*)?$",
        flags=re.IGNORECASE,
    )

    while queue:
        candidate = queue.pop(0)
        try:
            resolved = candidate.resolve()
        except OSError:
            continue
        if resolved in seen or not path_is_within(resolved, root) or not resolved.is_file():
            continue
        seen.add(resolved)
        ordered.append(resolved)

        for raw_line in read_text(resolved).splitlines():
            match = include_pattern.match(raw_line)
            if not match:
                continue
            include_value = match.group(1).strip().strip("\"'")
            include_path = Path(include_value)
            search_path = include_path if include_path.is_absolute() else resolved.parent / include_path
            matches = sorted(Path(path) for path in glob.glob(str(search_path)))
            if not matches and resolved.parent != root and not include_path.is_absolute():
                matches = sorted(Path(path) for path in glob.glob(str(root / include_path)))
            queue.extend(matches)
    return ordered


def config_report(report: Report) -> None:
    report.section("Low-level config drift")
    active_hashes: dict[str, str] = {}
    factory_hashes: dict[str, str] = {}

    for name in ("box.cfg", "motor_control.cfg"):
        active = CONFIG_DIR / name
        factory = FACTORY_DIR / name
        if not active.is_file() or not factory.is_file():
            report.add(
                "FAIL",
                "LOW_LEVEL_CONFIG_MISSING",
                "%s is missing from active or exact factory tree" % name,
            )
            continue
        active_hash = sha256_file(active)
        factory_hash = sha256_file(factory)
        active_hashes[name] = active_hash
        factory_hashes[name] = factory_hash
        if active_hash == factory_hash:
            report.add(
                "OK",
                "LOW_LEVEL_CONFIG_MATCH",
                "%s matches exact F012 factory source" % name,
            )
        else:
            report.add(
                "FAIL",
                "LOW_LEVEL_CONFIG_DRIFT",
                "%s differs from exact F012 factory source" % name,
            )

    report.data("active_hashes", active_hashes)
    report.data("factory_hashes", factory_hashes)

    factory_printer = CONFIG_DIR / "factory_printer.cfg"
    text = read_text(factory_printer)
    if not text:
        report.add(
            "FAIL",
            "ACTIVE_FACTORY_CONFIG_MISSING",
            "Active factory_printer.cfg is missing or unreadable",
        )
        return

    size_match = has_pattern(
        text,
        r"^\s*#\s*Printer_size:\s*300[\*x]300[\*x]300\s*$",
    )
    model_match = has_pattern(text, r"^\s*#\s*F012\s*$")
    geometry = {
        "stepper_x": section_value(text, "stepper_x", "position_max"),
        "stepper_y": section_value(text, "stepper_y", "position_max"),
        "stepper_z": section_value(text, "stepper_z", "position_max"),
    }
    report.data("geometry", geometry)

    if model_match and size_match:
        report.add(
            "OK",
            "ACTIVE_MODEL_SHAPE",
            "Active factory config declares F012 and %s" % EXPECTED_SIZE,
        )
    else:
        report.add(
            "FAIL",
            "ACTIVE_MODEL_SHAPE_MISMATCH",
            "Active factory config does not declare exact F012/%s" % EXPECTED_SIZE,
        )

    expected_geometry = {
        "stepper_x": "302",
        "stepper_y": "332",
        "stepper_z": "303",
    }
    if geometry == expected_geometry:
        report.add(
            "OK",
            "ACTIVE_GEOMETRY_EXACT",
            "Active X/Y/Z limits match K2 Pro F012",
        )
    else:
        report.add(
            "FAIL",
            "ACTIVE_GEOMETRY_MISMATCH",
            "Expected X/Y/Z 302/332/303, got %s/%s/%s"
            % (
                geometry["stepper_x"] or "missing",
                geometry["stepper_y"] or "missing",
                geometry["stepper_z"] or "missing",
            ),
        )

    active_paths = active_config_files()
    try:
        active_labels = [str(path.relative_to(CONFIG_DIR.resolve())) for path in active_paths]
    except ValueError:
        active_labels = [str(path) for path in active_paths]
    report.data("active_config_files", active_labels)
    if active_paths:
        report.add(
            "OK",
            "ACTIVE_CONFIG_TREE",
            "Resolved %d active Klipper config files from printer.cfg" % len(active_paths),
        )
    else:
        report.add(
            "FAIL",
            "ACTIVE_CONFIG_TREE_MISSING",
            "printer.cfg or its active include tree is unavailable",
        )

    all_config = "\n".join(read_text(path) for path in active_paths)
    if has_pattern(all_config, r"^\s*min_extrude_temp\s*:\s*0(?:\.0*)?\s*(?:#.*)?$"):
        report.add(
            "FAIL",
            "COLD_EXTRUSION_GUARD_DISABLED",
            "A config sets min_extrude_temp to 0",
        )
    else:
        report.add(
            "OK",
            "COLD_EXTRUSION_GUARD",
            "No active config disables the minimum extrusion temperature",
        )

    stock_box = (CONFIG_DIR / "box.cfg").resolve()
    custom_config = "\n".join(
        read_text(path) for path in active_paths if path.resolve() != stock_box
    )
    if has_pattern(custom_config, r"(?<![A-Za-z0-9_])BOX_SEND_DATA(?![A-Za-z0-9_])"):
        report.add(
            "FAIL",
            "RAW_CFS_COMMAND_FOUND",
            "BOX_SEND_DATA is present outside stock box.cfg",
        )
    else:
        report.add(
            "OK",
            "RAW_CFS_COMMAND_BLOCKED",
            "No raw BOX_SEND_DATA command exists outside stock box.cfg",
        )

    box_text = read_text(CONFIG_DIR / "box.cfg")
    if "[gcode_macro M8200]" in box_text and all(
        token in box_text
        for token in (
            "CR_BOX_PRE_OPT",
            "CR_BOX_CUT",
            "CR_BOX_RETRUDE",
            "CR_BOX_EXTRUDE",
            "CR_BOX_WASTE",
            "CR_BOX_FLUSH",
            "CR_BOX_END_OPT",
        )
    ):
        report.add(
            "OK",
            "STOCK_M8200_TRANSACTION",
            "Stock M8200/CR_BOX transaction path is intact",
        )
    else:
        report.add(
            "FAIL",
            "STOCK_M8200_TRANSACTION_MISSING",
            "Stock M8200/CR_BOX transaction path is incomplete",
        )

    vendor_factory = FACTORY_DIR / "factory_printer.cfg"
    if vendor_factory.is_file():
        active_hash = sha256_file(factory_printer)
        vendor_hash = sha256_file(vendor_factory)
        report.data("active_factory_printer_sha256", active_hash)
        report.data("vendor_factory_printer_sha256", vendor_hash)
        if active_hash == vendor_hash:
            report.add(
                "OK",
                "FACTORY_PRINTER_HASH_MATCH",
                "Active factory_printer.cfg matches packaged reference",
            )
        else:
            report.add(
                "INFO",
                "FACTORY_PRINTER_RUNTIME_VARIANT",
                "Active factory_printer.cfg is a validated runtime variant; structural F012 checks are authoritative",
            )


def tar_is_valid(path: Path) -> bool:
    try:
        if not path.is_file() or path.stat().st_size <= 0:
            return False
        with tarfile.open(path, "r:*") as archive:
            next(iter(archive), None)
        return True
    except (OSError, tarfile.TarError):
        return False


def newest_valid_archive(pattern: str) -> Path | None:
    try:
        candidates = sorted(
            (path for path in BACKUP_DIR.glob(pattern) if path.is_file()),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
    except OSError:
        return None
    for path in candidates:
        if tar_is_valid(path):
            return path
    return None


def local_ota_images() -> list[Path]:
    candidates: list[Path] = []
    for directory in (UDISK_DIR, UDISK_DIR / "firmware", UDISK_DIR / "ota"):
        if not directory.is_dir():
            continue
        try:
            candidates.extend(path for path in directory.glob("*.img") if path.is_file())
        except OSError:
            continue
    unique = {str(path.resolve()): path for path in candidates}
    return sorted(unique.values())


def recovery_report(report: Report) -> None:
    report.section("Recovery inventory")
    live = identity()
    report.data("boot_partition", live["boot_partition"])

    config_backup = newest_valid_archive("k2pro_config_system_*.tar.gz")
    if config_backup:
        report.add(
            "OK",
            "CONFIG_BACKUP_VALID",
            "Valid config/system backup: %s" % config_backup.name,
        )
    else:
        report.add(
            "WARN",
            "CONFIG_BACKUP_MISSING",
            "No valid k2pro_config_system backup was found",
        )

    helper_backup = newest_valid_archive("helper-script-before-*.tar.gz")
    if helper_backup:
        report.add(
            "OK",
            "HELPER_BACKUP_VALID",
            "Valid pre-install helper backup: %s" % helper_backup.name,
        )
    else:
        report.add(
            "WARN",
            "HELPER_BACKUP_MISSING",
            "No valid pre-install helper backup was found",
        )

    if tar_is_valid(RESTORE_PAYLOAD):
        report.add(
            "OK",
            "RESTORE_PAYLOAD_VALID",
            "Current restore payload is readable",
        )
    else:
        report.add(
            "WARN",
            "RESTORE_PAYLOAD_MISSING",
            "Current restore payload is missing or invalid",
        )

    required_data = {
        "printer_config": CONFIG_DIR,
        "moonraker_database": env_path(
            "K2_GUARD_MOONRAKER_DATABASE",
            "/mnt/UDISK/printer_data/database",
        ),
        "cfs_database": BOX_DIR,
        "helper_state": HELPER_DIR / "state",
        "spoolman_map": SPOOLMAN_MAP,
    }
    missing = [label for label, path in required_data.items() if not path.exists()]
    if missing:
        report.add(
            "WARN",
            "RECOVERY_DATA_GAPS",
            "Recovery-relevant live paths missing: %s" % ",".join(missing),
        )
    else:
        report.add(
            "OK",
            "RECOVERY_DATA_PRESENT",
            "Config, Moonraker DB, CFS DB, helper state and Spoolman map are present",
        )

    current_images = [
        path
        for path in local_ota_images()
        if EXPECTED_BOARD.lower() in path.name.lower()
        and live["firmware"].lower() in path.name.lower()
    ]
    report.data("local_ota_images", [str(path) for path in local_ota_images()])
    if current_images:
        report.add(
            "OK",
            "CURRENT_OTA_IMAGE_PRESENT",
            "Exact current board/version OTA image is stored locally",
        )
    else:
        report.add(
            "INFO",
            "CURRENT_OTA_IMAGE_ABSENT",
            "No exact current OTA image is stored on UDISK; obtain one before experimental flashing",
        )

    camera = camera_identity()
    exact_camera = matching_files(CAMERA_FW_DIR, "*%s*.bin" % camera["model"])
    if exact_camera:
        report.add(
            "OK",
            "CAMERA_RECOVERY_PRESENT",
            "Exact camera recovery image is present",
        )
    else:
        report.add(
            "INFO",
            "CAMERA_RECOVERY_ABSENT",
            "No exact %s camera recovery image is present" % camera["model"],
        )

    if F012_FW_DIR.is_dir() and CFS_FW_DIR.is_dir():
        report.add(
            "OK",
            "PERIPHERAL_BUNDLES_PRESENT",
            "F012 MCU/motor/RFID and CFS firmware directories are present",
        )
    else:
        report.add(
            "FAIL",
            "PERIPHERAL_BUNDLES_MISSING",
            "F012 or CFS peripheral firmware directory is missing",
        )


def profile_id(item: dict[str, Any]) -> str:
    base = item.get("base") or {}
    return str(base.get("id") or "")


def database_rows(document: Any) -> list[dict[str, Any]]:
    if not isinstance(document, dict):
        return []
    result = document.get("result")
    if not isinstance(result, dict):
        return []
    rows = result.get("list")
    if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
        return []
    return rows


def database_metadata(document: Any) -> dict[str, Any]:
    rows = database_rows(document)
    result = document.get("result", {}) if isinstance(document, dict) else {}
    version = document.get("version") if isinstance(document, dict) else None
    if version is None and isinstance(result, dict):
        version = result.get("version")
    official = [row for row in rows if profile_id(row) not in CUSTOM_PROFILE_IDS]
    custom = sorted(
        profile_id(row) for row in rows if profile_id(row) in CUSTOM_PROFILE_IDS
    )
    encoded = json.dumps(
        official,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return {
        "version": str(version) if version is not None else "unknown",
        "official_count": len(official),
        "custom_ids": custom,
        "total_count": len(rows),
        "official_fingerprint": hashlib.sha256(encoded).hexdigest(),
    }


def database_report(report: Report) -> None:
    report.section("CFS database protection")
    document = read_json(BOX_DIR / "material_database.json")
    rows = database_rows(document)
    if not rows:
        report.add(
            "FAIL",
            "CFS_DATABASE_INVALID",
            "material_database.json is missing or has an invalid structure",
        )
        return

    metadata = database_metadata(document)
    report.data("database", metadata)
    if set(metadata["custom_ids"]) == set(CUSTOM_PROFILE_IDS):
        report.add(
            "OK",
            "CUSTOM_PROFILES_PRESENT",
            "Custom profiles 90001 and 90002 are present",
        )
    else:
        report.add(
            "WARN",
            "CUSTOM_PROFILES_DRIFT",
            "Expected custom profile IDs 90001/90002, found %s"
            % (",".join(metadata["custom_ids"]) or "none"),
        )

    state = read_json(DB_GUARD_STATE, {}) or {}
    state_fingerprint = str(state.get("official_fingerprint_sha256") or "")
    if state_fingerprint == metadata["official_fingerprint"]:
        report.add(
            "OK",
            "OFFICIAL_DATABASE_TRACKED",
            "Official database fingerprint is tracked without restoring an older base",
        )
    elif state_fingerprint:
        report.add(
            "WARN",
            "OFFICIAL_DATABASE_CHANGED",
            "Official database changed since the guard state; preserve the new base and merge custom profiles only",
        )
    else:
        report.add(
            "INFO",
            "OFFICIAL_DATABASE_FIRST_SEEN",
            "No prior official database fingerprint is available",
        )

    guard_source = HELPER_DIR / "scripts" / "cfs_db_guard.py"
    guard_service = Path(
        os.environ.get("K2_GUARD_DB_SERVICE", "/etc/rc.d/S98cfs_db_guard")
    )
    if guard_source.is_file() and guard_service.is_file():
        report.add(
            "OK",
            "DATABASE_GUARD_INSTALLED",
            "CFS database guard source and boot service are present",
        )
    else:
        report.add(
            "WARN",
            "DATABASE_GUARD_INCOMPLETE",
            "CFS database guard source or boot service is missing",
        )

    patch_database = read_json(
        HELPER_DIR / "files" / "cfs_db_patch" / "material_database.json"
    )
    patch_ids = {
        profile_id(row)
        for row in database_rows(patch_database)
        if profile_id(row) in CUSTOM_PROFILE_IDS
    }
    if patch_ids == set(CUSTOM_PROFILE_IDS):
        report.add(
            "OK",
            "CUSTOM_PATCH_SOURCE",
            "Custom-only merge source contains both protected profiles",
        )
    else:
        report.add(
            "FAIL",
            "CUSTOM_PATCH_SOURCE_INVALID",
            "Custom merge source does not contain both protected profiles",
        )

    mapping = read_json(SPOOLMAN_MAP, {}) or {}
    mapped = {
        slot: mapping.get(slot)
        for slot in SLOTS
        if str(mapping.get(slot) or "").isdigit()
        and int(str(mapping.get(slot))) > 0
    }
    if len(mapped) == len(SLOTS):
        report.add(
            "OK",
            "SPOOLMAN_MAP_COMPLETE",
            "Spoolman map contains positive IDs for T1A through T1D",
        )
    else:
        report.add(
            "WARN",
            "SPOOLMAN_MAP_INCOMPLETE",
            "Spoolman map is missing one or more T1 slot IDs",
        )


def cfs_report(report: Report) -> None:
    report.section("Passive CFS diagnostics")
    state = read_json(CFS_SAFE_STATE, {}) or {}
    current = state.get("current", {}) if isinstance(state, dict) else {}
    full = state.get("last_full_status", {}) if isinstance(state, dict) else {}
    report.data("current", current)

    if current.get("box_state") == "connect" and current.get("t1_state") == "connect":
        report.add(
            "OK",
            "CFS_CONNECTED",
            "Passive monitor reports BOX and T1 connected",
        )
    else:
        report.add(
            "WARN",
            "CFS_STATE_REVIEW",
            "Passive monitor does not currently show BOX and T1 connected",
        )

    findings = full.get("findings", []) if isinstance(full, dict) else []
    failed = [
        row
        for row in findings
        if isinstance(row, dict) and row.get("level") == "FAIL"
    ]
    warned = [
        row
        for row in findings
        if isinstance(row, dict) and row.get("level") == "WARN"
    ]
    current_timestamp = str(current.get("timestamp") or "")
    full_timestamp = str(full.get("timestamp") or "")
    current_connected = (
        current.get("box_state") == "connect"
        and current.get("t1_state") == "connect"
    )
    stale_full_status = bool(
        current_connected
        and current_timestamp
        and full_timestamp
        and current_timestamp > full_timestamp
    )
    if failed and stale_full_status:
        report.add(
            "INFO",
            "CFS_SAFE_MONITOR_STALE",
            "Newer live BOX/T1 state is connected; ignoring stale pre-connect monitor findings",
        )
    elif failed:
        report.add(
            "FAIL",
            "CFS_SAFE_MONITOR_FAIL",
            "Passive CFS monitor has %d failure finding(s)" % len(failed),
        )
    elif warned and stale_full_status:
        report.add(
            "INFO",
            "CFS_SAFE_MONITOR_STALE_WARN",
            "Newer live BOX/T1 state is connected; stale monitor warnings need no action",
        )
    elif warned:
        report.add(
            "WARN",
            "CFS_SAFE_MONITOR_WARN",
            "Passive CFS monitor has %d warning finding(s)" % len(warned),
        )
    elif findings:
        report.add(
            "OK",
            "CFS_SAFE_MONITOR_CLEAN",
            "Passive CFS monitor has no warning or failure findings",
        )
    else:
        report.add(
            "WARN",
            "CFS_SAFE_MONITOR_STATE_MISSING",
            "Passive CFS monitor has no full status snapshot",
        )

    rs485 = full.get("rs485", {}) if isinstance(full, dict) else {}
    report.data("rs485", rs485)
    if rs485:
        report.add(
            "INFO",
            "RS485_PASSIVE_COUNTS",
            "Recent log counts: timeouts=%s unknown=%s buf_len=%s severe=%s"
            % (
                rs485.get("timeouts", "unknown"),
                rs485.get("unknown_frames", "unknown"),
                rs485.get("buf_len", "unknown"),
                rs485.get("severe", "unknown"),
            ),
        )


def check_ota_image(
    report: Report,
    path: Path,
    expected_sha256: str,
) -> None:
    report.section("OTA image gate")
    live = identity()
    try:
        resolved = path.expanduser().resolve(strict=True)
    except OSError:
        report.add("FAIL", "OTA_FILE_MISSING", "OTA image does not exist: %s" % path)
        return

    if not resolved.is_file() or resolved.suffix.lower() != ".img":
        report.add(
            "FAIL",
            "OTA_FILE_TYPE",
            "OTA gate accepts only a regular .img file",
        )
        return

    name = resolved.name
    lower_name = name.lower()
    report.data("path", str(resolved))
    report.data("size", resolved.stat().st_size)

    if EXPECTED_BOARD.lower() not in lower_name:
        report.add(
            "FAIL",
            "OTA_BOARD_TOKEN_MISSING",
            "Filename does not contain exact board %s" % EXPECTED_BOARD,
        )
    else:
        report.add(
            "OK",
            "OTA_BOARD_TOKEN_EXACT",
            "Filename contains exact board %s" % EXPECTED_BOARD,
        )

    foreign_tokens = (
        "f008",
        "k2plus",
        "k2_plus",
        "cr0cn240319c13",
        "ccx1f4013",
    )
    found_foreign = [token for token in foreign_tokens if token in lower_name]
    if found_foreign:
        report.add(
            "FAIL",
            "OTA_FOREIGN_TOKEN",
            "Filename contains foreign model/board token(s): %s"
            % ",".join(found_foreign),
        )

    match = re.search(r"[_-]V(\d+(?:\.\d+){2,4})(?:[._-]|$)", name, re.IGNORECASE)
    image_version = match.group(1) if match else ""
    report.data("image_version", image_version or "unknown")
    if not image_version:
        report.add(
            "FAIL",
            "OTA_VERSION_UNKNOWN",
            "Could not parse OTA version from filename",
        )
    else:
        compare = version_compare(image_version, live["firmware"])
        if compare is not None and compare < 0:
            report.add(
                "FAIL",
                "OTA_DOWNGRADE_BLOCKED",
                "Image %s is older than installed %s"
                % (image_version, live["firmware"]),
            )
        elif compare == 0:
            report.add(
                "INFO",
                "OTA_SAME_VERSION",
                "Image version equals installed firmware %s" % live["firmware"],
            )
        else:
            report.add(
                "OK",
                "OTA_VERSION_DIRECTION",
                "Image version is not older than installed firmware",
            )

    actual_hash = sha256_file(resolved)
    report.data("sha256", actual_hash)
    normalized_expected = expected_sha256.strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", normalized_expected):
        report.add(
            "FAIL",
            "OTA_HASH_REQUIRED",
            "A trusted 64-character expected SHA256 is required",
        )
    elif actual_hash != normalized_expected:
        report.add(
            "FAIL",
            "OTA_HASH_MISMATCH",
            "OTA SHA256 does not match the trusted expected value",
        )
    else:
        report.add(
            "OK",
            "OTA_HASH_MATCH",
            "OTA SHA256 matches the trusted expected value",
        )

    report.add(
        "INFO",
        "OTA_GATE_LIMIT",
        "Passing this gate confirms filename identity, version direction and hash only; it never flashes",
    )


def print_report(report: Report, compact: bool, as_json: bool) -> None:
    if as_json:
        print(json.dumps(report.as_dict(), ensure_ascii=False, indent=2, sort_keys=True))
        return

    counts = report.counts()
    if compact:
        print(
            "K2_GUARD_SUMMARY|OK=%d|INFO=%d|WARN=%d|FAIL=%d"
            % (counts["OK"], counts["INFO"], counts["WARN"], counts["FAIL"])
        )
        for finding in report.findings():
            if finding["level"] in ("WARN", "FAIL"):
                print(
                    "%s|%s|%s"
                    % (finding["level"], finding["code"], finding["message"])
                )
        return

    print("== K2 Pro protection status ==")
    print(
        "Safety: read-only. No firmware, G-code, serial, CFS, cutter, heater, motor or restart command is sent."
    )
    for section in report.sections:
        print("")
        print("== %s ==" % section["name"])
        for key, value in section["data"].items():
            if isinstance(value, (dict, list)):
                rendered = json.dumps(value, ensure_ascii=False, sort_keys=True)
            else:
                rendered = str(value)
            print("DATA|%s|%s" % (key, rendered))
        for finding in section["findings"]:
            print(
                "[%s] %s: %s"
                % (finding["level"], finding["code"], finding["message"])
            )
    print("")
    print(
        "SUMMARY|OK=%d|INFO=%d|WARN=%d|FAIL=%d"
        % (counts["OK"], counts["INFO"], counts["WARN"], counts["FAIL"])
    )


def source_selftest() -> int:
    source = Path(__file__).read_text(encoding="utf-8", errors="replace")
    tree = ast.parse(source)
    allowed_commands = {
        "/usr/bin/get_sn_mac.sh",
        "/etc/ota_bin/get_ota_current_version.sh",
        "fw_printenv",
    }
    invalid_commands = []
    network_writes = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id == "run_text":
            if not node.args or not isinstance(node.args[0], (ast.List, ast.Tuple)):
                invalid_commands.append("dynamic")
                continue
            values = node.args[0].elts
            first = values[0] if values else None
            if not isinstance(first, ast.Constant) or first.value not in allowed_commands:
                invalid_commands.append(str(getattr(first, "value", "dynamic")))
        if (
            isinstance(node.func, ast.Attribute)
            and node.func.attr == "Request"
            and isinstance(node.func.value, ast.Attribute)
            and node.func.value.attr == "request"
        ):
            network_writes.append("urllib.request.Request")
        for keyword in node.keywords:
            if (
                keyword.arg == "method"
                and isinstance(keyword.value, ast.Constant)
                and str(keyword.value.value).upper() != "GET"
            ):
                network_writes.append("HTTP_%s" % str(keyword.value.value))
    if invalid_commands:
        print(
            "SELFTEST_FAIL|non-read-only subprocess command(s): %s"
            % ",".join(invalid_commands)
        )
        return 1
    if network_writes:
        print(
            "SELFTEST_FAIL|network write primitive(s): %s"
            % ",".join(network_writes)
        )
        return 1
    if version_compare("1.1.6.7", "1.1.6.3") != 1:
        print("SELFTEST_FAIL|version comparison")
        return 1
    print("SELFTEST_OK|read-only source scan and version comparison passed")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--status", action="store_true", help="run every read-only guard")
    action.add_argument("--firmware", action="store_true", help="firmware and hardware identity")
    action.add_argument("--config", action="store_true", help="low-level config drift")
    action.add_argument("--recovery", action="store_true", help="recovery inventory")
    action.add_argument("--database", action="store_true", help="CFS database protection")
    action.add_argument("--cfs", action="store_true", help="passive CFS monitor state")
    action.add_argument("--check-ota", metavar="PATH", help="validate an OTA filename and hash")
    action.add_argument("--selftest", action="store_true")
    parser.add_argument("--expected-sha256", default="")
    parser.add_argument("--compact", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    if args.selftest:
        return source_selftest()

    report = Report()
    if args.check_ota:
        check_ota_image(report, Path(args.check_ota), args.expected_sha256)
    elif args.firmware:
        firmware_report(report)
    elif args.config:
        config_report(report)
    elif args.recovery:
        recovery_report(report)
    elif args.database:
        database_report(report)
    elif args.cfs:
        cfs_report(report)
    else:
        firmware_report(report)
        config_report(report)
        recovery_report(report)
        database_report(report)
        cfs_report(report)

    print_report(report, args.compact, args.json)
    return 1 if report.failed() else 0


if __name__ == "__main__":
    raise SystemExit(main())
