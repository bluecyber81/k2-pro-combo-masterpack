#!/usr/bin/env python3
"""Keep the K2 Pro CFS custom material database entries durable.

This guard is intentionally narrow: it never sends CFS/BOX commands and never
loads, unloads, extrudes or moves filament. It only validates JSON files and
merges the known custom profiles from the helper's patch snapshot when Creality
restores the stock material database during boot.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any, Optional


BOX_DIR = Path(os.environ.get("CFS_BOX_DIR", "/mnt/UDISK/creality/userdata/box"))
PATCH_DIR = Path(os.environ.get("CFS_PATCH_DIR", "/mnt/UDISK/helper-script/files/cfs_db_patch"))
ARCHIVE_DIR = Path(os.environ.get("CFS_ARCHIVE_DIR", str(BOX_DIR / "archive")))
LOG_FILE = Path(os.environ.get("CFS_GUARD_LOG", "/tmp/cfs_db_guard.log"))
STATE_FILE = Path(
    os.environ.get(
        "CFS_GUARD_STATE",
        "/mnt/UDISK/helper-script/state/cfs_db_guard_state.json",
    )
)
CUSTOM_PROFILE_IDS = ("90001", "90002")
CUSTOM_USER_PATH_SUFFIXES = (
    "k2pro-esun-epla-hs-gray",
    "k2pro-sovol-pla-steel-blue",
)
DEFAULT_ARCHIVE_KEEP = int(os.environ.get("CFS_DB_GUARD_KEEP_ARCHIVES", "12"))
DEFAULT_WATCH_INTERVAL = int(os.environ.get("CFS_DB_GUARD_WATCH_INTERVAL", "300"))
MOONRAKER_URL = os.environ.get(
    "CFS_GUARD_MOONRAKER_URL",
    "http://127.0.0.1:7125",
).rstrip("/")
PRINTER_STATUS_FILE = os.environ.get("CFS_GUARD_PRINTER_STATUS_FILE")


class GuardError(RuntimeError):
    pass


def log(message: str) -> None:
    line = "%s %s" % (datetime.now().strftime("%Y-%m-%d %H:%M:%S"), message)
    print(line)
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with LOG_FILE.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except Exception:
        pass


def read_json(path: Path) -> Any:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError as exc:
        raise GuardError("missing %s" % path) from exc
    except Exception as exc:
        raise GuardError("invalid JSON %s: %s" % (path, exc)) from exc


def write_json_atomic(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp.%s" % os.getpid())
    with tmp.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    tmp.replace(path)


def copy_file_atomic(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(dst.name + ".tmp.%s" % os.getpid())
    shutil.copy2(src, tmp)
    tmp.replace(dst)


def backup_current(reason: str) -> Path:
    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    target = ARCHIVE_DIR / ("cfs_db_guard_%s_%s_%s" % (reason, stamp, os.getpid()))
    target.mkdir(parents=True, exist_ok=False)
    for rel in (
        "material_database.json",
        "material_option.json",
        "material_box_info.json",
        "material_modify_info.json",
        "tn_data.json",
        "usrMaterial/userMaterial.json",
    ):
        src = BOX_DIR / rel
        if src.exists():
            dst = target / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
    return target


def guard_archives() -> list[Path]:
    if not ARCHIVE_DIR.exists():
        return []
    return sorted(
        [
            path
            for path in ARCHIVE_DIR.iterdir()
            if path.is_dir() and path.name.startswith("cfs_db_guard_")
        ],
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )


def archive_status(keep: int = DEFAULT_ARCHIVE_KEEP) -> int:
    archives = guard_archives()
    log("ARCHIVE_STATUS count=%s keep=%s dir=%s" % (len(archives), keep, ARCHIVE_DIR))
    for index, path in enumerate(archives[: max(keep, 0) + 5], 1):
        state = "keep" if index <= keep else "old"
        log("ARCHIVE_%02d %s %s" % (index, state, path))
    if len(archives) > keep:
        log("ARCHIVE_ROTATE_AVAILABLE old=%s command=--rotate-backups --keep %s" % (len(archives) - keep, keep))
    return 0


def rotate_archives(keep: int = DEFAULT_ARCHIVE_KEEP) -> int:
    archives = guard_archives()
    if keep < 1:
        log("ERROR keep must be >= 1")
        return 2
    old_archives = archives[keep:]
    for path in old_archives:
        try:
            shutil.rmtree(path)
            log("ARCHIVE_REMOVED %s" % path)
        except Exception as exc:
            log("ERROR cannot remove old archive %s: %s" % (path, exc))
            return 2
    log("ARCHIVE_ROTATE_DONE kept=%s removed=%s" % (min(len(archives), keep), len(old_archives)))
    return 0


def profile_id(item: dict[str, Any]) -> str:
    base = item.get("base") or {}
    return str(base.get("id") or "")


def profile_identity(item: dict[str, Any]) -> tuple[str, str, str]:
    base = item.get("base") or {}
    material_type = base.get("meterialType", base.get("materialType", ""))
    values = (base.get("brand"), base.get("name"), material_type)
    return (
        " ".join(str(values[0] or "").split()).casefold(),
        " ".join(str(values[1] or "").split()).casefold(),
        " ".join(str(values[2] or "").split()).casefold(),
    )


def database_list(document: Any, label: str) -> list[dict[str, Any]]:
    if not isinstance(document, dict):
        raise GuardError("%s has unexpected structure" % label)
    rows = document.get("result", {}).get("list")
    if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
        raise GuardError("%s has unexpected structure" % label)
    return rows


def validate_inputs() -> None:
    current_rows = database_list(read_json(BOX_DIR / "material_database.json"), "material_database.json")
    source_rows = database_list(read_json(PATCH_DIR / "material_database.json"), "patch material_database.json")
    source_ids = {profile_id(row) for row in source_rows if profile_id(row) in CUSTOM_PROFILE_IDS}
    if source_ids != set(CUSTOM_PROFILE_IDS):
        raise GuardError("patch snapshot does not contain all custom profiles")
    current_ids = [
        profile_id(row)
        for row in current_rows
        if profile_id(row) in CUSTOM_PROFILE_IDS
    ]
    duplicates = sorted({value for value in current_ids if current_ids.count(value) > 1})
    if duplicates:
        raise GuardError("duplicate custom material profile IDs: %s" % ",".join(duplicates))

    source_options = read_json(PATCH_DIR / "material_option.json")
    if not isinstance(source_options, dict):
        raise GuardError("patch material_option.json has unexpected structure")
    current_options_path = BOX_DIR / "material_option.json"
    if current_options_path.exists() and not isinstance(read_json(current_options_path), dict):
        raise GuardError("material_option.json has unexpected structure")

    current_user = read_json(BOX_DIR / "usrMaterial" / "userMaterial.json")
    source_user = read_json(PATCH_DIR / "usrMaterial" / "userMaterial.json")
    if not isinstance(current_user, list) or not isinstance(source_user, list):
        raise GuardError("userMaterial.json has unexpected structure")


def database_metadata(document: Any) -> dict[str, Any]:
    rows = database_list(document, "material_database.json")
    database_version = None
    if isinstance(document, dict):
        database_version = document.get("version")
        result = document.get("result")
        if database_version is None and isinstance(result, dict):
            database_version = result.get("version")
    official_rows = [row for row in rows if profile_id(row) not in CUSTOM_PROFILE_IDS]
    custom_ids = sorted(profile_id(row) for row in rows if profile_id(row) in CUSTOM_PROFILE_IDS)
    encoded = json.dumps(
        official_rows,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return {
        "database_version": str(database_version) if database_version is not None else "unknown",
        "official_profile_count": len(official_rows),
        "custom_profile_count": len(custom_ids),
        "total_profile_count": len(rows),
        "custom_profile_ids": custom_ids,
        "official_fingerprint_sha256": hashlib.sha256(encoded).hexdigest(),
    }


def report_and_store_database_state(check_only: bool) -> None:
    current = read_json(BOX_DIR / "material_database.json")
    metadata = database_metadata(current)
    previous: Any = {}
    if STATE_FILE.exists():
        try:
            previous = read_json(STATE_FILE)
        except GuardError as exc:
            log("WARNING ignoring invalid previous guard state: %s" % exc)
    previous_fingerprint = previous.get("official_fingerprint_sha256") if isinstance(previous, dict) else None
    changed = bool(previous_fingerprint and previous_fingerprint != metadata["official_fingerprint_sha256"])
    status = "changed" if changed else ("first-seen" if not previous_fingerprint else "unchanged")
    log(
        "DB_BASE_STATUS version=%s official=%s custom=%s total=%s status=%s fingerprint=%s"
        % (
            metadata["database_version"],
            metadata["official_profile_count"],
            metadata["custom_profile_count"],
            metadata["total_profile_count"],
            status,
            metadata["official_fingerprint_sha256"][:16],
        )
    )
    if not check_only:
        metadata.update(
            {
                "schema_version": 1,
                "last_seen": datetime.now().isoformat(timespec="seconds"),
                "official_database_changed_since_last_run": changed,
                "previous_official_fingerprint_sha256": previous_fingerprint,
            }
        )
        write_json_atomic(STATE_FILE, metadata)


def merge_material_database(check_only: bool) -> tuple[bool, list[str]]:
    current_path = BOX_DIR / "material_database.json"
    source_path = PATCH_DIR / "material_database.json"
    current = read_json(current_path)
    source = read_json(source_path)
    current_list = database_list(current, "material_database.json")
    source_list = database_list(source, "patch material_database.json")

    source_profiles = {
        profile_id(item): item for item in source_list if profile_id(item) in CUSTOM_PROFILE_IDS
    }
    if set(source_profiles) != set(CUSTOM_PROFILE_IDS):
        raise GuardError("patch snapshot does not contain all custom profiles")

    changed = False
    notes: list[str] = []
    index = {profile_id(item): pos for pos, item in enumerate(current_list) if profile_id(item)}
    identity_index = {
        profile_identity(item): profile_id(item)
        for item in current_list
        if all(profile_identity(item)) and profile_id(item)
    }
    for custom_id, source_item in source_profiles.items():
        source_identity = profile_identity(source_item)
        if custom_id in index:
            current_item = current_list[index[custom_id]]
            if profile_identity(current_item) != source_identity:
                raise GuardError(
                    "custom profile ID collision %s: current=%s patch=%s"
                    % (custom_id, profile_identity(current_item), source_identity)
                )
            if current_item != source_item:
                notes.append("preserved locally edited profile %s" % custom_id)
            else:
                notes.append("profile %s already ok" % custom_id)
        else:
            existing_identity_id = identity_index.get(source_identity)
            if existing_identity_id:
                raise GuardError(
                    "custom profile identity collision %s already uses ID %s"
                    % (source_identity, existing_identity_id)
                )
            current_list.append(source_item)
            index[custom_id] = len(current_list) - 1
            identity_index[source_identity] = custom_id
            changed = True
            notes.append("added profile %s" % custom_id)

    result = current.setdefault("result", {})
    if isinstance(result, dict):
        if result.get("count") != len(current_list):
            result["count"] = len(current_list)
            changed = True
            notes.append("fixed profile count")

    if changed and not check_only:
        write_json_atomic(current_path, current)
    return changed, notes


def merge_option_text(current: str, source: str) -> tuple[str, bool]:
    seen = set()
    lines: list[str] = []
    changed = False
    for line in current.splitlines():
        if line not in seen:
            lines.append(line)
            seen.add(line)
    for line in source.splitlines():
        if line and line not in seen:
            lines.append(line)
            seen.add(line)
            changed = True
    return "\n".join(lines), changed


def merge_material_options(check_only: bool) -> tuple[bool, list[str]]:
    current_path = BOX_DIR / "material_option.json"
    source_path = PATCH_DIR / "material_option.json"
    source = read_json(source_path)
    notes: list[str] = []
    if not current_path.exists():
        minimal = {
            vendor: source[vendor]
            for vendor in ("eSUN", "Sovol")
            if isinstance(source.get(vendor), dict)
        }
        if not minimal:
            raise GuardError("patch material_option.json has no custom vendor options")
        if not check_only:
            write_json_atomic(current_path, minimal)
        return True, ["created minimal custom material_option.json"]

    current = read_json(current_path)
    if not isinstance(current, dict) or not isinstance(source, dict):
        raise GuardError("material_option.json has unexpected structure")

    changed = False
    for vendor in ("eSUN", "Sovol"):
        source_vendor = source.get(vendor)
        if not isinstance(source_vendor, dict):
            continue
        current_vendor = current.setdefault(vendor, {})
        if not isinstance(current_vendor, dict):
            current[vendor] = {}
            current_vendor = current[vendor]
            changed = True
        for material, source_value in source_vendor.items():
            if material not in current_vendor:
                current_vendor[material] = source_value
                changed = True
                notes.append("added option %s/%s" % (vendor, material))
            elif isinstance(current_vendor[material], str) and isinstance(source_value, str):
                merged, did_change = merge_option_text(current_vendor[material], source_value)
                if did_change:
                    current_vendor[material] = merged
                    changed = True
                    notes.append("merged option %s/%s" % (vendor, material))

    if changed and not check_only:
        write_json_atomic(current_path, current)
    if not notes:
        notes.append("material options already ok")
    return changed, notes


def merge_user_material(check_only: bool) -> tuple[bool, list[str]]:
    current_path = BOX_DIR / "usrMaterial" / "userMaterial.json"
    source_path = PATCH_DIR / "usrMaterial" / "userMaterial.json"
    current = read_json(current_path)
    source = read_json(source_path)
    if not isinstance(current, list) or not isinstance(source, list):
        raise GuardError("userMaterial.json has unexpected structure")

    changed = False
    notes: list[str] = []
    current_paths = {str(item.get("path") or "") for item in current if isinstance(item, dict)}
    for source_item in source:
        if not isinstance(source_item, dict):
            continue
        source_item_path = str(source_item.get("path") or "")
        if not any(source_item_path.endswith(suffix) for suffix in CUSTOM_USER_PATH_SUFFIXES):
            continue
        if source_item_path not in current_paths:
            current.append(source_item)
            current_paths.add(source_item_path)
            changed = True
            notes.append("added user material index %s" % Path(source_item_path).name)

    for suffix in CUSTOM_USER_PATH_SUFFIXES:
        src_paths = [p for p in (PATCH_DIR / "usrMaterial").glob("*/*") if p.name == suffix]
        for src_path in src_paths:
            rel = src_path.relative_to(PATCH_DIR)
            dst_path = BOX_DIR / rel
            if not dst_path.exists():
                if not check_only:
                    dst_path.parent.mkdir(parents=True, exist_ok=True)
                    if src_path.is_dir():
                        shutil.copytree(src_path, dst_path)
                    else:
                        copy_file_atomic(src_path, dst_path)
                changed = True
                notes.append("restored user material files %s" % suffix)

    if changed and not check_only:
        write_json_atomic(current_path, current)
    if not notes:
        notes.append("user materials already ok")
    return changed, notes


def verify_live_ids() -> tuple[bool, list[str]]:
    db = read_json(BOX_DIR / "material_database.json")
    profile_ids = {
        profile_id(item)
        for item in db.get("result", {}).get("list", [])
        if isinstance(item, dict) and profile_id(item)
    }
    ok = all(custom_id in profile_ids for custom_id in CUSTOM_PROFILE_IDS)
    notes = ["profile %s=%s" % (custom_id, "ok" if custom_id in profile_ids else "missing") for custom_id in CUSTOM_PROFILE_IDS]
    return ok, notes


def run(check_only: bool) -> int:
    if not PATCH_DIR.exists():
        log("ERROR patch snapshot missing: %s" % PATCH_DIR)
        return 2

    changes: list[str] = []
    try:
        validate_inputs()
        db_changed, db_notes = merge_material_database(check_only)
        opt_changed, opt_notes = merge_material_options(check_only)
        user_changed, user_notes = merge_user_material(check_only)
        changed = db_changed or opt_changed or user_changed
        changes.extend(db_notes + opt_notes + user_notes)
    except GuardError as exc:
        log("ERROR %s" % exc)
        return 2

    if changed and check_only:
        for note in changes:
            log("CHECK repair needed: %s" % note)
        report_and_store_database_state(check_only=True)
        return 1

    if changed:
        log("Repair changed files: %s" % "; ".join(changes))
    else:
        log("No CFS DB repair needed: %s" % "; ".join(changes))

    ok, verify_notes = verify_live_ids()
    for note in verify_notes:
        log("VERIFY %s" % note)
    report_and_store_database_state(check_only=check_only)
    return 0 if ok else 1


def repair_with_prebackup() -> int:
    try:
        need_repair = run(check_only=True)
    except Exception as exc:
        log("ERROR precheck failed: %s" % exc)
        return 2
    if need_repair == 0:
        return run(check_only=False)
    if need_repair == 1:
        backup = backup_current("before_repair")
        log("Pre-repair backup: %s" % backup)
        return run(check_only=False)
    return need_repair


def database_signature() -> tuple[tuple[str, int, int], ...]:
    signature: list[tuple[str, int, int]] = []
    for path in (
        BOX_DIR / "material_database.json",
        BOX_DIR / "material_option.json",
        BOX_DIR / "usrMaterial" / "userMaterial.json",
    ):
        try:
            stat = path.stat()
            signature.append((str(path), stat.st_size, stat.st_mtime_ns))
        except FileNotFoundError:
            signature.append((str(path), -1, -1))
    return tuple(signature)


def moonraker_status() -> dict[str, Any]:
    if PRINTER_STATUS_FILE:
        payload = read_json(Path(PRINTER_STATUS_FILE))
    else:
        url = "%s/printer/objects/query?print_stats&extruder&heater_bed" % MOONRAKER_URL
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(request, timeout=4) as response:
            payload = json.load(response)
    if not isinstance(payload, dict):
        raise GuardError("Moonraker status has unexpected structure")
    result = payload.get("result")
    status = result.get("status") if isinstance(result, dict) else None
    if not isinstance(status, dict):
        raise GuardError("Moonraker status is missing result.status")
    return status


def printer_safe_for_automatic_repair() -> tuple[bool, str]:
    try:
        status = moonraker_status()
        print_stats = status.get("print_stats")
        extruder = status.get("extruder")
        heater_bed = status.get("heater_bed")
        if (
            not isinstance(print_stats, dict)
            or not isinstance(extruder, dict)
            or not isinstance(heater_bed, dict)
        ):
            raise GuardError("Moonraker status is missing required printer objects")
        state = str(print_stats.get("state") or "unknown").casefold()
        extruder_target = float(extruder.get("target") or 0)
        bed_target = float(heater_bed.get("target") or 0)
    except Exception as exc:
        return False, "printer status unavailable: %s" % exc

    if state not in {"standby", "complete", "cancelled"}:
        return False, "printer state=%s" % state
    if extruder_target > 0.1 or bed_target > 0.1:
        return (
            False,
            "heater targets extruder=%.1f bed=%.1f" % (extruder_target, bed_target),
        )
    return True, "state=%s heater targets=0" % state


def automatic_repair_once() -> int:
    need_repair = run(check_only=True)
    if need_repair != 1:
        return need_repair

    safe, reason = printer_safe_for_automatic_repair()
    if not safe:
        log("WATCH_DEFER repair needed but %s" % reason)
        return 3

    log("WATCH_REPAIR safe automatic repair: %s" % reason)
    result = repair_with_prebackup()
    if result == 0:
        rotate_archives(DEFAULT_ARCHIVE_KEEP)
    return result


def watch_forever(delay: int, interval: int) -> int:
    delay = max(0, delay)
    interval = max(60, interval)
    if delay:
        time.sleep(delay)
    log("WATCH_STARTED interval=%ss" % interval)
    previous_signature: Optional[tuple[tuple[str, int, int], ...]] = None
    while True:
        try:
            current_signature = database_signature()
            if previous_signature is None or current_signature != previous_signature:
                result = automatic_repair_once()
                if result != 3:
                    previous_signature = database_signature()
            time.sleep(interval)
        except KeyboardInterrupt:
            log("WATCH_STOPPED")
            return 0
        except Exception as exc:
            log("WATCH_ERROR %s" % exc)
            time.sleep(interval)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Check only.")
    parser.add_argument("--repair", action="store_true", help="Repair if needed.")
    parser.add_argument("--boot", action="store_true", help="Delay, then repair once after boot.")
    parser.add_argument(
        "--auto-repair-once",
        action="store_true",
        help="Repair only when Moonraker reports a cold, idle printer.",
    )
    parser.add_argument(
        "--watch",
        action="store_true",
        help="Watch for Creality DB rewrites and repair only while cold and idle.",
    )
    parser.add_argument("--delay", type=int, default=90)
    parser.add_argument("--interval", type=int, default=DEFAULT_WATCH_INTERVAL)
    parser.add_argument("--archive-status", action="store_true", help="Show CFS DB guard backup archive status.")
    parser.add_argument("--rotate-backups", action="store_true", help="Remove old CFS DB guard archives beyond --keep.")
    parser.add_argument("--keep", type=int, default=DEFAULT_ARCHIVE_KEEP, help="Archive count to keep for --archive-status/--rotate-backups.")
    args = parser.parse_args()

    if args.archive_status:
        return archive_status(args.keep)
    if args.rotate_backups:
        return rotate_archives(args.keep)
    if args.watch:
        return watch_forever(args.delay, args.interval)
    if args.auto_repair_once:
        return automatic_repair_once()
    if args.boot:
        time.sleep(max(0, args.delay))
        return repair_with_prebackup()
    if args.check:
        return run(check_only=True)
    return repair_with_prebackup()


if __name__ == "__main__":
    sys.exit(main())
