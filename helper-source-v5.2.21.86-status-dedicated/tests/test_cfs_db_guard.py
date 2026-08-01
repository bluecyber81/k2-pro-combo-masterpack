#!/usr/bin/env python3
"""Regression tests for the update-aware CFS material DB guard."""

import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / "scripts" / "cfs_db_guard.py"
PATCH = ROOT / "files" / "cfs_db_patch"


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def save(path, payload):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


class GuardFixture:
    def __init__(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.box = self.root / "box"
        self.patch = self.root / "patch"
        self.state = self.root / "state" / "guard.json"
        shutil.copytree(PATCH, self.patch)
        (self.box / "usrMaterial").mkdir(parents=True)
        save(self.box / "usrMaterial" / "userMaterial.json", [])

    def close(self):
        self.temp.cleanup()

    def official_rows(self, count):
        return [
            {
                "engineVersion": "3.0.0",
                "base": {
                    "id": str(10000 + index),
                    "brand": "Creality",
                    "name": "Official %02d" % index,
                    "meterialType": "PLA",
                },
            }
            for index in range(count)
        ]

    def source_custom(self):
        rows = load(self.patch / "material_database.json")["result"]["list"]
        return [copy.deepcopy(row) for row in rows if str(row.get("base", {}).get("id")) in ("90001", "90002")]

    def write_db(self, rows):
        save(self.box / "material_database.json", {"result": {"count": len(rows), "list": rows}})

    def write_options(self, payload=None):
        save(self.box / "material_option.json", {} if payload is None else payload)

    def write_printer_status(self, state="standby", extruder_target=0, bed_target=0):
        path = self.root / "printer_status.json"
        save(
            path,
            {
                "result": {
                    "status": {
                        "print_stats": {"state": state},
                        "extruder": {"target": extruder_target},
                        "heater_bed": {"target": bed_target},
                    }
                }
            },
        )
        return path

    def run(self, *args, env_overrides=None):
        env = os.environ.copy()
        env.update(
            {
                "CFS_BOX_DIR": str(self.box),
                "CFS_PATCH_DIR": str(self.patch),
                "CFS_ARCHIVE_DIR": str(self.root / "archive"),
                "CFS_GUARD_LOG": str(self.root / "guard.log"),
                "CFS_GUARD_STATE": str(self.state),
            }
        )
        if env_overrides:
            env.update(env_overrides)
        return subprocess.run(
            [sys.executable, str(GUARD), *args],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )


class CfsDbGuardTests(unittest.TestCase):
    def setUp(self):
        self.fixture = GuardFixture()

    def tearDown(self):
        self.fixture.close()

    def test_newer_official_database_is_preserved(self):
        self.fixture.write_db(self.fixture.official_rows(60))
        self.fixture.write_options()
        result = self.fixture.run("--repair")
        self.assertEqual(result.returncode, 0, result.stdout)
        rows = load(self.fixture.box / "material_database.json")["result"]["list"]
        self.assertEqual(len(rows), 62)
        self.assertEqual(sum(1 for row in rows if str(row["base"]["id"]).startswith("10")), 60)
        state = load(self.fixture.state)
        self.assertEqual(state["official_profile_count"], 60)
        self.assertEqual(state["custom_profile_count"], 2)

    def test_local_custom_profile_edit_is_preserved(self):
        custom = self.fixture.source_custom()
        custom[0]["kvParam"]["filament_flow_ratio"] = "0.987"
        self.fixture.write_db(self.fixture.official_rows(3) + custom)
        self.fixture.write_options()
        result = self.fixture.run("--repair")
        self.assertEqual(result.returncode, 0, result.stdout)
        rows = load(self.fixture.box / "material_database.json")["result"]["list"]
        edited = next(row for row in rows if str(row["base"]["id"]) == "90001")
        self.assertEqual(edited["kvParam"]["filament_flow_ratio"], "0.987")
        self.assertIn("preserved locally edited profile 90001", result.stdout)

    def test_official_duplicate_ids_are_allowed(self):
        rows = self.fixture.official_rows(3)
        rows[1]["base"]["id"] = rows[0]["base"]["id"]
        rows[1]["base"]["name"] = "Official duplicate identity"
        self.fixture.write_db(rows)
        self.fixture.write_options()
        result = self.fixture.run("--repair")
        self.assertEqual(result.returncode, 0, result.stdout)
        final_rows = load(self.fixture.box / "material_database.json")["result"]["list"]
        self.assertEqual(len(final_rows), 5)

    def test_id_collision_aborts_without_writes(self):
        collision = self.fixture.source_custom()[0]
        collision["base"]["brand"] = "Other"
        collision["base"]["name"] = "Collision"
        self.fixture.write_db(self.fixture.official_rows(2) + [collision])
        self.fixture.write_options()
        before = (self.fixture.box / "material_database.json").read_bytes()
        result = self.fixture.run("--repair")
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertEqual((self.fixture.box / "material_database.json").read_bytes(), before)
        self.assertIn("ID collision", result.stdout)

    def test_missing_options_creates_custom_only_file(self):
        self.fixture.write_db(self.fixture.official_rows(2))
        result = self.fixture.run("--repair")
        self.assertEqual(result.returncode, 0, result.stdout)
        options = load(self.fixture.box / "material_option.json")
        self.assertEqual(set(options), {"eSUN", "Sovol"})

    def test_unknown_schema_aborts_without_writes(self):
        save(self.fixture.box / "material_database.json", {"result": {"list": "unexpected"}})
        self.fixture.write_options()
        before = (self.fixture.box / "material_database.json").read_bytes()
        result = self.fixture.run("--repair")
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertEqual((self.fixture.box / "material_database.json").read_bytes(), before)

    def test_official_fingerprint_change_is_recorded(self):
        rows = self.fixture.official_rows(4)
        self.fixture.write_db(rows)
        self.fixture.write_options()
        first = self.fixture.run("--repair")
        self.assertEqual(first.returncode, 0, first.stdout)
        first_fingerprint = load(self.fixture.state)["official_fingerprint_sha256"]
        current = load(self.fixture.box / "material_database.json")
        current["result"]["list"].append(self.fixture.official_rows(5)[-1])
        current["result"]["count"] = len(current["result"]["list"])
        save(self.fixture.box / "material_database.json", current)
        second = self.fixture.run("--repair")
        self.assertEqual(second.returncode, 0, second.stdout)
        state = load(self.fixture.state)
        self.assertNotEqual(state["official_fingerprint_sha256"], first_fingerprint)
        self.assertTrue(state["official_database_changed_since_last_run"])
        self.assertEqual(state["official_profile_count"], 5)

    def test_automatic_repair_runs_only_when_cold_and_idle(self):
        self.fixture.write_db(self.fixture.official_rows(2))
        self.fixture.write_options()
        status_path = self.fixture.write_printer_status()
        result = self.fixture.run(
            "--auto-repair-once",
            env_overrides={"CFS_GUARD_PRINTER_STATUS_FILE": str(status_path)},
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        rows = load(self.fixture.box / "material_database.json")["result"]["list"]
        self.assertEqual(len(rows), 4)
        self.assertIn("WATCH_REPAIR safe automatic repair", result.stdout)
        self.assertEqual(len(list((self.fixture.root / "archive").iterdir())), 1)

    def test_automatic_repair_defers_while_printing(self):
        self.fixture.write_db(self.fixture.official_rows(2))
        self.fixture.write_options()
        before = (self.fixture.box / "material_database.json").read_bytes()
        status_path = self.fixture.write_printer_status(state="printing")
        result = self.fixture.run(
            "--auto-repair-once",
            env_overrides={"CFS_GUARD_PRINTER_STATUS_FILE": str(status_path)},
        )
        self.assertEqual(result.returncode, 3, result.stdout)
        self.assertEqual((self.fixture.box / "material_database.json").read_bytes(), before)
        self.assertIn("WATCH_DEFER", result.stdout)
        self.assertFalse((self.fixture.root / "archive").exists())

    def test_automatic_repair_defers_while_heating(self):
        self.fixture.write_db(self.fixture.official_rows(2))
        self.fixture.write_options()
        before = (self.fixture.box / "material_database.json").read_bytes()
        status_path = self.fixture.write_printer_status(extruder_target=220)
        result = self.fixture.run(
            "--auto-repair-once",
            env_overrides={"CFS_GUARD_PRINTER_STATUS_FILE": str(status_path)},
        )
        self.assertEqual(result.returncode, 3, result.stdout)
        self.assertEqual((self.fixture.box / "material_database.json").read_bytes(), before)
        self.assertIn("heater targets", result.stdout)

    def test_automatic_repair_does_not_query_printer_without_drift(self):
        self.fixture.write_db(self.fixture.official_rows(2) + self.fixture.source_custom())
        self.fixture.write_options(load(self.fixture.patch / "material_option.json"))
        source_user = load(self.fixture.patch / "usrMaterial" / "userMaterial.json")
        save(self.fixture.box / "usrMaterial" / "userMaterial.json", source_user)
        for suffix in ("k2pro-esun-epla-hs-gray", "k2pro-sovol-pla-steel-blue"):
            for source_path in (self.fixture.patch / "usrMaterial").glob("*/*"):
                if source_path.name == suffix:
                    target = self.fixture.box / source_path.relative_to(self.fixture.patch)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if source_path.is_dir():
                        shutil.copytree(source_path, target)
                    else:
                        shutil.copy2(source_path, target)
        result = self.fixture.run(
            "--auto-repair-once",
            env_overrides={"CFS_GUARD_MOONRAKER_URL": "http://127.0.0.1:1"},
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("WATCH_DEFER", result.stdout)


if __name__ == "__main__":
    unittest.main()
