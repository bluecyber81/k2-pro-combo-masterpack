#!/usr/bin/env python3
"""Capture and compare a passive K2 Pro post-update baseline."""

import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile
import time
import urllib.request
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import k2pro_protection_guard  # noqa: E402


HELPER_DIR = Path(os.environ.get("K2_POST_UPDATE_HELPER_DIR", "/mnt/UDISK/helper-script"))
CONFIG_DIR = Path(
    os.environ.get("K2_POST_UPDATE_CONFIG_DIR", "/mnt/UDISK/printer_data/config")
)
BOX_DIR = Path(
    os.environ.get("K2_POST_UPDATE_BOX_DIR", "/mnt/UDISK/creality/userdata/box")
)
BASELINE_PATH = Path(
    os.environ.get(
        "K2_POST_UPDATE_BASELINE",
        str(HELPER_DIR / "state" / "post_update_baseline.json"),
    )
)
MOONRAKER_URL = os.environ.get(
    "K2_POST_UPDATE_MOONRAKER_URL", "http://127.0.0.1:7125"
).rstrip("/")
EXPECTED_MODEL = "F012"
EXPECTED_BOARD = "CR0CN200400C10"
BUILD = "k2-post-update-guard-1.0"
CORE_FILES = (
    Path("/usr/share/klipper/klippy/klippy.py"),
    Path("/usr/share/moonraker/moonraker.py"),
    Path("/usr/share/fluidd/.version"),
    Path("/usr/share/mainsail/.version"),
)


def now_text():
    return time.strftime("%Y-%m-%d %H:%M:%S")


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError, TypeError):
        return default


def path_is_within(path, directory):
    try:
        Path(path).resolve().relative_to(Path(directory).resolve())
        return True
    except ValueError:
        return False


def atomic_write_baseline(path, payload):
    target = Path(path)
    if target.parent != Path("/tmp") and not path_is_within(target, HELPER_DIR):
        raise ValueError("baseline must stay under the helper directory or /tmp")
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_file():
        backup = target.with_name(
            target.stem + ".before-" + time.strftime("%Y%m%d_%H%M%S") + target.suffix
        )
        shutil.copy2(target, backup)
    temporary = target.with_name(target.name + ".tmp.%s" % os.getpid())
    temporary.write_text(
        json.dumps(payload, ensure_ascii=True, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(target)


def get_json(path, timeout=5):
    request = urllib.request.Request(
        MOONRAKER_URL + path,
        headers={"User-Agent": "k2-post-update-guard/1"},
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8", errors="replace"))


def moonraker_info():
    try:
        result = get_json("/server/info", timeout=5).get("result", {}) or {}
    except Exception as exc:
        return {"reachable": False, "error": str(exc)}
    return {
        "reachable": True,
        "klippy_state": result.get("klippy_state"),
        "moonraker_version": result.get("moonraker_version"),
        "api_version": result.get("api_version"),
    }


def read_first_line(path):
    try:
        with Path(path).open("r", encoding="utf-8", errors="replace") as handle:
            return handle.readline().strip()[:200]
    except OSError:
        return ""


def helper_version():
    for line in (
        read_first_line(HELPER_DIR / "helper.sh"),
        read_first_line(HELPER_DIR / "README.md"),
    ):
        if "v5." in line:
            return line
    return "unknown"


def cfs_database_snapshot():
    path = BOX_DIR / "material_database.json"
    document = read_json(path, {}) or {}
    metadata = k2pro_protection_guard.database_metadata(document)
    return {
        "path": str(path),
        "version": metadata.get("version"),
        "profile_count": metadata.get("total_count"),
        "official_count": metadata.get("official_count"),
        "custom_count": len(metadata.get("custom_ids") or []),
        "official_fingerprint_sha256": metadata.get("official_fingerprint"),
        "file_sha256": sha256_file(path) if path.is_file() else None,
    }


def config_files():
    rows = []
    if CONFIG_DIR.is_dir():
        for path in CONFIG_DIR.glob("*.cfg"):
            if not path.is_file() or ".bak" in path.name or path.name.endswith("~"):
                continue
            rows.append(path)
    return sorted(rows, key=lambda item: item.name.lower())


def file_inventory():
    files = config_files()
    files.extend(path for path in CORE_FILES if path.is_file())
    for path in (
        HELPER_DIR / "helper.sh",
        HELPER_DIR / "PACKAGE_SHA256SUMS.txt",
        HELPER_DIR / ".installed",
    ):
        if path.is_file():
            files.append(path)
    inventory = {}
    for path in files:
        try:
            inventory[str(path)] = {
                "sha256": sha256_file(path),
                "size": path.stat().st_size,
            }
        except OSError:
            continue
    return inventory


def capture_snapshot():
    live_identity = k2pro_protection_guard.identity()
    camera = k2pro_protection_guard.camera_identity()
    cfs_version = k2pro_protection_guard.query_cfs_version()
    return {
        "build": BUILD,
        "captured_at": now_text(),
        "identity": live_identity,
        "cfs_version": cfs_version or "unknown",
        "camera": camera,
        "helper_version": helper_version(),
        "moonraker": moonraker_info(),
        "cfs_database": cfs_database_snapshot(),
        "files": file_inventory(),
        "safety": "read_only_capture_no_repair_no_restart_no_firmware_no_gcode",
    }


def add_finding(findings, level, code, message):
    findings.append({"level": level, "code": code, "message": message})


def compare_snapshots(baseline, current):
    findings = []
    if not isinstance(baseline, dict):
        add_finding(
            findings,
            "WARN",
            "BASELINE_MISSING",
            "no post-update baseline exists; capture one after a verified healthy state",
        )
        return findings

    baseline_identity = baseline.get("identity") or {}
    current_identity = current.get("identity") or {}
    for key, expected in (
        ("model", EXPECTED_MODEL),
        ("board", EXPECTED_BOARD),
    ):
        value = current_identity.get(key)
        if value != expected:
            add_finding(
                findings,
                "FAIL",
                "IDENTITY_" + key.upper(),
                "current %s is %s; expected %s" % (key, value, expected),
            )
        elif baseline_identity.get(key) != value:
            add_finding(
                findings,
                "FAIL",
                "IDENTITY_CHANGED_" + key.upper(),
                "%s changed from baseline %s to %s"
                % (key, baseline_identity.get(key), value),
            )
        else:
            add_finding(
                findings,
                "OK",
                "IDENTITY_" + key.upper(),
                "%s remains %s" % (key, value),
            )

    firmware_changed = (
        baseline_identity.get("firmware") != current_identity.get("firmware")
    )
    if firmware_changed:
        add_finding(
            findings,
            "INFO",
            "FIRMWARE_CHANGED",
            "firmware changed from %s to %s; review config/core drift below"
            % (
                baseline_identity.get("firmware"),
                current_identity.get("firmware"),
            ),
        )
    else:
        add_finding(
            findings,
            "OK",
            "FIRMWARE_STABLE",
            "firmware remains %s" % current_identity.get("firmware"),
        )

    for key, code in (
        ("cfs_version", "CFS_VERSION"),
        ("helper_version", "HELPER_VERSION"),
    ):
        before = baseline.get(key)
        after = current.get(key)
        if before == after:
            add_finding(findings, "OK", code + "_STABLE", "%s remains %s" % (key, after))
        else:
            add_finding(
                findings,
                "INFO",
                code + "_CHANGED",
                "%s changed from %s to %s" % (key, before, after),
            )

    for key in ("model", "version"):
        before = (baseline.get("camera") or {}).get(key)
        after = (current.get("camera") or {}).get(key)
        if before != after:
            add_finding(
                findings,
                "INFO",
                "CAMERA_" + key.upper() + "_CHANGED",
                "camera %s changed from %s to %s" % (key, before, after),
            )

    before_db = baseline.get("cfs_database") or {}
    after_db = current.get("cfs_database") or {}
    if (
        before_db.get("official_fingerprint_sha256")
        != after_db.get("official_fingerprint_sha256")
    ):
        add_finding(
            findings,
            "INFO",
            "CFS_DATABASE_BASE_CHANGED",
            "official CFS database fingerprint changed; preserve the new official base and merge custom profiles only",
        )
    else:
        add_finding(
            findings,
            "OK",
            "CFS_DATABASE_BASE_STABLE",
            "official CFS database fingerprint is unchanged",
        )
    if int(after_db.get("custom_count") or 0) < int(before_db.get("custom_count") or 0):
        add_finding(
            findings,
            "WARN",
            "CFS_CUSTOM_PROFILES_LOST",
            "custom CFS profile count decreased from %s to %s"
            % (before_db.get("custom_count"), after_db.get("custom_count")),
        )

    before_files = baseline.get("files") or {}
    after_files = current.get("files") or {}
    removed = sorted(set(before_files) - set(after_files))
    added = sorted(set(after_files) - set(before_files))
    changed = sorted(
        path
        for path in set(before_files) & set(after_files)
        if before_files[path].get("sha256") != after_files[path].get("sha256")
    )
    for path in removed:
        add_finding(
            findings,
            "FAIL",
            "FILE_REMOVED",
            "baseline file is missing: " + path,
        )
    for path in added:
        add_finding(
            findings,
            "INFO",
            "FILE_ADDED",
            "new tracked file: " + path,
        )
    for path in changed:
        config_change = path.startswith(str(CONFIG_DIR))
        level = "INFO" if firmware_changed or not config_change else "WARN"
        code = "CONFIG_CHANGED" if config_change else "COMPONENT_CHANGED"
        add_finding(findings, level, code, "tracked file changed: " + path)
    if not removed and not added and not changed:
        add_finding(
            findings,
            "OK",
            "TRACKED_FILES_STABLE",
            "all tracked config, core, helper and frontend files match the baseline",
        )

    moonraker = current.get("moonraker") or {}
    if moonraker.get("reachable") and moonraker.get("klippy_state") == "ready":
        add_finding(
            findings,
            "OK",
            "MOONRAKER_READY",
            "Moonraker is reachable and Klippy is ready",
        )
    else:
        add_finding(
            findings,
            "FAIL",
            "MOONRAKER_NOT_READY",
            "Moonraker/Klippy is not ready: %s" % moonraker,
        )
    return findings


def report(baseline, current):
    findings = compare_snapshots(baseline, current)
    counts = {level: 0 for level in ("OK", "INFO", "WARN", "FAIL")}
    for row in findings:
        counts[row["level"]] += 1
    return {
        "build": BUILD,
        "baseline_path": str(BASELINE_PATH),
        "baseline_captured_at": (baseline or {}).get("captured_at")
        if isinstance(baseline, dict)
        else None,
        "checked_at": now_text(),
        "current": current,
        "findings": findings,
        "summary": counts,
        "safety": "read_only_compare_no_repair_no_restart_no_firmware_no_gcode",
    }


def render(payload):
    lines = [
        "== K2 Pro post-update guard ==",
        "Safety: snapshot/compare only; no repair, restart, firmware, CFS, heater, motion, or G-code action.",
        "BASELINE|path=%s|captured=%s"
        % (payload["baseline_path"], payload.get("baseline_captured_at")),
    ]
    for row in payload["findings"]:
        lines.append("[%s] %s: %s" % (row["level"], row["code"], row["message"]))
    lines.append(
        "SUMMARY|OK={OK}|INFO={INFO}|WARN={WARN}|FAIL={FAIL}".format(
            **payload["summary"]
        )
    )
    return "\n".join(lines)


def selftest():
    baseline = {
        "identity": {
            "model": EXPECTED_MODEL,
            "board": EXPECTED_BOARD,
            "firmware": "1.1.6.7",
        },
        "cfs_version": "1.5.0",
        "helper_version": "v-test",
        "camera": {"model": "cam", "version": "250708"},
        "cfs_database": {
            "official_fingerprint_sha256": "abc",
            "custom_count": 2,
        },
        "files": {str(CONFIG_DIR / "printer.cfg"): {"sha256": "a"}},
    }
    current = json.loads(json.dumps(baseline))
    current["moonraker"] = {"reachable": True, "klippy_state": "ready"}
    stable = compare_snapshots(baseline, current)
    if any(row["level"] in ("WARN", "FAIL") for row in stable):
        raise RuntimeError("stable baseline comparison produced warning/failure")
    current["identity"]["firmware"] = "1.1.6.8"
    current["files"][str(CONFIG_DIR / "printer.cfg")]["sha256"] = "b"
    current["cfs_database"]["official_fingerprint_sha256"] = "def"
    changed = compare_snapshots(baseline, current)
    codes = {row["code"] for row in changed}
    if not {"FIRMWARE_CHANGED", "CONFIG_CHANGED", "CFS_DATABASE_BASE_CHANGED"}.issubset(
        codes
    ):
        raise RuntimeError("update changes were not detected")
    with tempfile.TemporaryDirectory() as temporary:
        target = Path(temporary) / "baseline.json"
        old_helper = os.environ.get("K2_POST_UPDATE_HELPER_DIR")
        try:
            globals()["HELPER_DIR"] = Path(temporary)
            atomic_write_baseline(target, baseline)
            if read_json(target, {}) != baseline:
                raise RuntimeError("baseline atomic write failed")
        finally:
            globals()["HELPER_DIR"] = Path(old_helper) if old_helper else Path(
                "/mnt/UDISK/helper-script"
            )
    print("SELFTEST|OK|identity, firmware, database and tracked-file comparison")
    return 0


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--capture", action="store_true")
    action.add_argument("--status", action="store_true")
    action.add_argument("--selftest", action="store_true")
    parser.add_argument("--json", action="store_true")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    if args.selftest:
        return selftest()
    current = capture_snapshot()
    identity = current.get("identity") or {}
    if identity.get("model") != EXPECTED_MODEL or identity.get("board") != EXPECTED_BOARD:
        print(
            "POST_UPDATE_GUARD|FAIL|expected F012/CR0CN200400C10, got %s/%s"
            % (identity.get("model"), identity.get("board")),
            file=sys.stderr,
        )
        return 1
    if args.capture:
        atomic_write_baseline(BASELINE_PATH, current)
        print(
            "POST_UPDATE_BASELINE|OK|captured=%s|firmware=%s|cfs=%s|files=%s|path=%s"
            % (
                current["captured_at"],
                identity.get("firmware"),
                current.get("cfs_version"),
                len(current.get("files") or {}),
                BASELINE_PATH,
            )
        )
        return 0
    baseline = read_json(BASELINE_PATH, None)
    payload = report(baseline, current)
    if args.json:
        print(json.dumps(payload, ensure_ascii=True, indent=2, sort_keys=True))
    else:
        print(render(payload))
    return 1 if payload["summary"]["FAIL"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
