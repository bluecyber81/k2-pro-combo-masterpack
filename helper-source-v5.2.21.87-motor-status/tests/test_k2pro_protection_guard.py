#!/usr/bin/env python3
"""Regression tests for the read-only K2 Pro protection guard."""

import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "k2pro_protection_guard.py"


def write(path: pathlib.Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def material_database() -> dict:
    rows = [
        {"base": {"id": "101001", "brand": "Creality", "name": "Hyper PLA"}},
        {"base": {"id": "90001", "brand": "eSUN", "name": "ePLA-HS+ Gray"}},
        {"base": {"id": "90002", "brand": "Sovol", "name": "PLA Steel Blue"}},
    ]
    return {"result": {"version": 123, "list": rows}}


class ProtectionGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.base = pathlib.Path(self.temp.name)
        self.config = self.base / "config"
        self.factory = self.base / "factory"
        self.f012_fw = self.base / "fw" / "F012"
        self.cfs_fw = self.base / "fw" / "cfs"
        self.camera_fw = self.base / "camera_fw"
        self.box = self.base / "box"
        self.helper = self.base / "helper"
        self.backups = self.base / "backups"
        self.udisk = self.base / "udisk"
        self.restore = self.base / "restore.tar.gz"
        self.auto_addr_wrapper = self.base / "auto_addr_wrapper.py"

        active_factory = """# F012
# Printer_size: 300*300*300
[include box.cfg]
[include motor_control.cfg]
[stepper_x]
position_max: 302
[stepper_y]
position_max: 332
[stepper_z]
position_max: 303
[extruder]
min_extrude_temp: 170
"""
        box_cfg = """[gcode_macro M8200]
gcode:
  CR_BOX_PRE_OPT
  CR_BOX_CUT
  CR_BOX_RETRUDE
  CR_BOX_EXTRUDE
  CR_BOX_WASTE
  CR_BOX_FLUSH
  CR_BOX_END_OPT
"""
        motor_cfg = "[motor_control]\n"
        for directory in (self.config, self.factory):
            write(directory / "box.cfg", box_cfg)
            write(directory / "motor_control.cfg", motor_cfg)
            write(directory / "factory_printer.cfg", active_factory)
        write(self.config / "printer.cfg", "[include factory_printer.cfg]\n")

        for relative in (
            "mcu0_test.bin",
            "noz0_test.bin",
            "mot0_test.bin",
            "mot1_test.bin",
            "mot2_test.bin",
            "rfid/rfd0_test.bin",
        ):
            write(self.f012_fw / relative, "firmware")
        write(self.cfs_fw / "cfs0_test_142.bin", "firmware")
        write(
            self.base / "cam_version.json",
            json.dumps(
                {
                    "main_cam": {
                        "manufactory": "CCX2F4013",
                        "cur_version": "250708",
                    }
                }
            ),
        )
        write(self.camera_fw / "UVC-UnionImage-CCX1F4013-test.bin", "foreign")
        write(
            self.auto_addr_wrapper,
            "DEV_TYPE_CFS_PRO = 10\n"
            "def process_all():\n"
            "    time_interval = 10.0\n",
        )

        database = material_database()
        write(self.box / "material_database.json", json.dumps(database))
        write(
            self.helper / "files" / "cfs_db_patch" / "material_database.json",
            json.dumps(database),
        )
        write(self.helper / "scripts" / "cfs_db_guard.py", "# guard\n")
        write(self.base / "S98cfs_db_guard", "# service\n")
        write(
            self.helper / "spoolman_cfs_map.json",
            json.dumps(
                {"enabled": True, "T1A": 1, "T1B": 2, "T1C": 3, "T1D": 4}
            ),
        )

        official = [database["result"]["list"][0]]
        fingerprint = hashlib.sha256(
            json.dumps(
                official,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        ).hexdigest()
        write(
            self.helper / "state" / "cfs_db_guard_state.json",
            json.dumps({"official_fingerprint_sha256": fingerprint}),
        )
        write(
            self.helper / "state" / "cfs_safe_tools_state.json",
            json.dumps(
                {
                    "current": {
                        "box_state": "connect",
                        "t1_state": "connect",
                    },
                    "last_full_status": {
                        "findings": [{"level": "OK", "code": "CFS_CONNECTED"}],
                        "rs485": {
                            "timeouts": 1,
                            "unknown_frames": 0,
                            "buf_len": 0,
                            "severe": 0,
                        },
                    },
                }
            ),
        )

        for directory in (
            self.base / "database",
            self.helper / "state",
            self.backups,
            self.udisk,
        ):
            directory.mkdir(parents=True, exist_ok=True)
        self._make_tar(self.restore)
        self._make_tar(self.backups / "k2pro_config_system_test.tar.gz")
        self._make_tar(self.backups / "helper-script-before-test.tar.gz")
        write(self.base / "mcu_version", "mcu0_test\n")

        self.env = os.environ.copy()
        self.env.update(
            {
                "K2_GUARD_MODEL": "F012",
                "K2_GUARD_BOARD": "CR0CN200400C10",
                "K2_GUARD_FIRMWARE": "1.1.6.3",
                "K2_GUARD_BOOT_PARTITION": "bootA",
                "K2_GUARD_CFS_VERSION": "1.4.2",
                "K2_GUARD_CONFIG_DIR": str(self.config),
                "K2_GUARD_FACTORY_DIR": str(self.factory),
                "K2_GUARD_F012_FW_DIR": str(self.f012_fw),
                "K2_GUARD_CFS_FW_DIR": str(self.cfs_fw),
                "K2_GUARD_AUTO_ADDR_WRAPPER": str(self.auto_addr_wrapper),
                "K2_GUARD_CAMERA_CONFIG": str(self.base / "cam_version.json"),
                "K2_GUARD_CAMERA_FW_DIR": str(self.camera_fw),
                "K2_GUARD_BOX_DIR": str(self.box),
                "K2_GUARD_HELPER_DIR": str(self.helper),
                "K2_GUARD_BACKUP_DIR": str(self.backups),
                "K2_GUARD_UDISK_DIR": str(self.udisk),
                "K2_GUARD_RESTORE_PAYLOAD": str(self.restore),
                "K2_GUARD_SYSTEM_VERSION": str(self.base / "system_version.json"),
                "K2_GUARD_MCU_VERSION": str(self.base / "mcu_version"),
                "K2_GUARD_DB_STATE": str(
                    self.helper / "state" / "cfs_db_guard_state.json"
                ),
                "K2_GUARD_CFS_SAFE_STATE": str(
                    self.helper / "state" / "cfs_safe_tools_state.json"
                ),
                "K2_GUARD_SPOOLMAN_MAP": str(
                    self.helper / "spoolman_cfs_map.json"
                ),
                "K2_GUARD_DB_SERVICE": str(self.base / "S98cfs_db_guard"),
                "K2_GUARD_MOONRAKER_DATABASE": str(self.base / "database"),
            }
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _make_tar(self, path: pathlib.Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = self.base / "tar-payload.txt"
        payload.write_text("ok", encoding="utf-8")
        with tarfile.open(path, "w:gz") as archive:
            archive.add(payload, arcname="payload.txt")

    def run_guard(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-B", str(SCRIPT), *arguments],
            check=False,
            capture_output=True,
            text=True,
            env=self.env,
        )

    def test_full_status_passes_exact_f012_fixture(self) -> None:
        result = self.run_guard("--status", "--compact")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("FAIL=0", result.stdout)

    def test_wrong_board_is_blocked(self) -> None:
        self.env["K2_GUARD_BOARD"] = "CR0CN240319C13"
        result = self.run_guard("--firmware")
        self.assertEqual(result.returncode, 1)
        self.assertIn("BOARD_MISMATCH", result.stdout)

    def test_low_level_config_drift_is_blocked(self) -> None:
        write(self.config / "motor_control.cfg", "[motor_control]\nchanged: 1\n")
        result = self.run_guard("--config")
        self.assertEqual(result.returncode, 1)
        self.assertIn("LOW_LEVEL_CONFIG_DRIFT", result.stdout)

    def test_cold_extrusion_guard_disable_is_blocked(self) -> None:
        write(self.config / "custom.cfg", "[extruder]\nmin_extrude_temp: 0\n")
        write(
            self.config / "printer.cfg",
            "[include factory_printer.cfg]\n[include custom.cfg]\n",
        )
        result = self.run_guard("--config")
        self.assertEqual(result.returncode, 1)
        self.assertIn("COLD_EXTRUSION_GUARD_DISABLED", result.stdout)

    def test_stale_backup_is_not_treated_as_active_config(self) -> None:
        write(
            self.config / "printer-20260730_120000.cfg",
            "[extruder]\nmin_extrude_temp: 0\n"
            "[gcode_macro UNSAFE_STALE_BACKUP]\n"
            "gcode:\n"
            "  BOX_SEND_DATA DATA=00\n",
        )
        result = self.run_guard("--config")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("COLD_EXTRUSION_GUARD_DISABLED", result.stdout)
        self.assertNotIn("RAW_CFS_COMMAND_FOUND", result.stdout)

    def test_nested_active_include_is_scanned(self) -> None:
        write(
            self.config / "nested" / "unsafe.cfg",
            "[gcode_macro ACTIVE_UNSAFE]\n"
            "gcode:\n"
            "  BOX_SEND_DATA DATA=00\n",
        )
        write(
            self.config / "printer.cfg",
            "[include factory_printer.cfg]\n"
            "[include nested/unsafe.cfg]\n",
        )
        result = self.run_guard("--config")
        self.assertEqual(result.returncode, 1)
        self.assertIn("RAW_CFS_COMMAND_FOUND", result.stdout)

    def test_foreign_camera_image_is_informational(self) -> None:
        result = self.run_guard("--firmware")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("CAMERA_IMAGE_MISMATCH_BLOCKED", result.stdout)

    def test_firmware_1167_recognizes_cfs2_host_and_newer_cfs_image(self) -> None:
        self.env["K2_GUARD_FIRMWARE"] = "1.1.6.7"
        (self.cfs_fw / "cfs0_test_142.bin").unlink()
        write(self.cfs_fw / "cfs0_050_G30-cfs0_000_150.bin", "firmware")
        result = self.run_guard("--firmware")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("CFS2_HOST_SUPPORT", result.stdout)
        self.assertIn("CFS_UPDATE_AVAILABLE", result.stdout)

    def test_newer_connected_state_ignores_stale_boot_failure(self) -> None:
        state_path = self.helper / "state" / "cfs_safe_tools_state.json"
        write(
            state_path,
            json.dumps(
                {
                    "current": {
                        "box_state": "connect",
                        "t1_state": "connect",
                        "timestamp": "2026-07-29 16:32:20",
                    },
                    "last_full_status": {
                        "timestamp": "2026-07-29 16:27:52",
                        "findings": [
                            {"level": "FAIL", "code": "CFS_DISCONNECTED"}
                        ],
                    },
                }
            ),
        )
        result = self.run_guard("--cfs")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("CFS_SAFE_MONITOR_STALE", result.stdout)

    def test_official_database_change_preserves_custom_policy(self) -> None:
        state_path = self.helper / "state" / "cfs_db_guard_state.json"
        write(state_path, json.dumps({"official_fingerprint_sha256": "0" * 64}))
        result = self.run_guard("--database")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("OFFICIAL_DATABASE_CHANGED", result.stdout)
        self.assertIn("CUSTOM_PROFILES_PRESENT", result.stdout)

    def test_ota_gate_requires_exact_board_and_trusted_hash(self) -> None:
        image = (
            self.udisk
            / "CR0CN200400C10_R_202607260000_ota_img_V1.1.6.4.img"
        )
        image.write_bytes(b"test-image")
        expected = hashlib.sha256(image.read_bytes()).hexdigest()
        result = self.run_guard(
            "--check-ota",
            str(image),
            "--expected-sha256",
            expected,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("OTA_HASH_MATCH", result.stdout)

    def test_ota_gate_blocks_foreign_board(self) -> None:
        image = self.udisk / "F008_R_ota_img_V1.1.6.4.img"
        image.write_bytes(b"test-image")
        expected = hashlib.sha256(image.read_bytes()).hexdigest()
        result = self.run_guard(
            "--check-ota",
            str(image),
            "--expected-sha256",
            expected,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("OTA_BOARD_TOKEN_MISSING", result.stdout)


if __name__ == "__main__":
    unittest.main()
