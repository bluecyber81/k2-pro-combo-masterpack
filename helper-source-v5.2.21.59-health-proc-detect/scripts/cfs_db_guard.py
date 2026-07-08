#!/usr/bin/env python3
"""Keep the K2 Pro CFS custom material database entries durable.

This guard is intentionally narrow: it never sends CFS/BOX commands and never
loads, unloads, extrudes or moves filament. It only validates JSON files and
merges the known custom profiles from the helper's patch snapshot when Creality
restores the stock material database during boot.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any


BOX_DIR = Path("/mnt/UDISK/creality/userdata/box")
PATCH_DIR = Path("/mnt/UDISK/helper-script/files/cfs_db_patch")
ARCHIVE_DIR = BOX_DIR / "archive"
LOG_FILE = Path("/tmp/cfs_db_guard.log")
CUSTOM_PROFILE_IDS = ("90001", "90002")
CUSTOM_USER_PATH_SUFFIXES = (
    "k2pro-esun-epla-hs-gray",
    "k2pro-sovol-pla-steel-blue",
)


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


def profile_id(item: dict[str, Any]) -> str:
    base = item.get("base") or {}
    return str(base.get("id") or "")


def merge_material_database(check_only: bool) -> tuple[bool, list[str]]:
    current_path = BOX_DIR / "material_database.json"
    source_path = PATCH_DIR / "material_database.json"
    current = read_json(current_path)
    source = read_json(source_path)
    current_list = current.get("result", {}).get("list")
    source_list = source.get("result", {}).get("list")
    if not isinstance(current_list, list) or not isinstance(source_list, list):
        raise GuardError("material_database.json has unexpected structure")

    source_profiles = {
        profile_id(item): item for item in source_list if profile_id(item) in CUSTOM_PROFILE_IDS
    }
    if set(source_profiles) != set(CUSTOM_PROFILE_IDS):
        raise GuardError("patch snapshot does not contain all custom profiles")

    changed = False
    notes: list[str] = []
    index = {profile_id(item): pos for pos, item in enumerate(current_list)}
    for custom_id, source_item in source_profiles.items():
        if custom_id in index:
            if current_list[index[custom_id]] != source_item:
                current_list[index[custom_id]] = source_item
                changed = True
                notes.append("updated profile %s" % custom_id)
            else:
                notes.append("profile %s already ok" % custom_id)
        else:
            current_list.append(source_item)
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
        if not check_only:
            copy_file_atomic(source_path, current_path)
        return True, ["restored material_option.json"]

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
        return 1

    if changed:
        log("Repair changed files: %s" % "; ".join(changes))
    else:
        log("No CFS DB repair needed: %s" % "; ".join(changes))

    ok, verify_notes = verify_live_ids()
    for note in verify_notes:
        log("VERIFY %s" % note)
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Check only.")
    parser.add_argument("--repair", action="store_true", help="Repair if needed.")
    parser.add_argument("--boot", action="store_true", help="Delay, then repair once after boot.")
    parser.add_argument("--delay", type=int, default=90)
    args = parser.parse_args()

    if args.boot:
        time.sleep(max(0, args.delay))
        return repair_with_prebackup()
    if args.check:
        return run(check_only=True)
    return repair_with_prebackup()


if __name__ == "__main__":
    sys.exit(main())
