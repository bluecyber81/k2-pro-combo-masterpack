#!/usr/bin/env python3
"""Regression tests for the read-only K2 Pro motor-controller report."""

import importlib.util
import pathlib
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKER = ROOT / "scripts" / "motor_controller_report.py"
SPEC = importlib.util.spec_from_file_location("motor_controller_report", WORKER)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class MotorControllerReportTests(unittest.TestCase):
    def test_healthy_k2_pro_runtime(self) -> None:
        status, rs485, mcu = MODULE.healthy_fixture()
        report = MODULE.analyze(
            status,
            rs485,
            mcu,
            "send msg timeout\naddr [85] dev [motor], update: done\n",
            "[INFO] motor init complete\n",
            "# FW: mot2_023_C30-mot2_002_071.bin\n",
        )
        self.assertEqual(report.exit_code, 0)
        self.assertEqual(report.summary_fields["motor_app"], "081")
        self.assertEqual(report.summary_fields["extruder_app"], "081")
        self.assertEqual(report.summary_fields["cfs_app"], "150")
        self.assertEqual(report.summary_fields["updater_failures"], "0")
        self.assertIn("read_only=true", report.summary())

    def test_real_updater_failure_is_not_hidden_by_discovery_noise(self) -> None:
        status, rs485, mcu = MODULE.healthy_fixture()
        report = MODULE.analyze(
            status,
            rs485,
            mcu,
            "send msg timeout\nhandshake /dev/ttyS3 fail\n",
            "",
            "",
        )
        self.assertEqual(report.exit_code, 2)
        self.assertEqual(report.summary_fields["updater_failures"], "1")

    def test_motor_error_keys_are_log_evidence_only(self) -> None:
        status, rs485, mcu = MODULE.healthy_fixture()
        report = MODULE.analyze(
            status,
            rs485,
            mcu,
            "addr [85] dev [motor], update: done\n",
            "[WARNING] closed loop reported key789\n",
            "",
        )
        self.assertEqual(report.exit_code, 1)
        self.assertEqual(report.summary_fields["motor_error_keys"], "789")

    def test_worker_has_no_control_or_write_surface(self) -> None:
        source = WORKER.read_text(encoding="utf-8")
        wrapper = (ROOT / "scripts" / "motor_controller_report.sh").read_text(
            encoding="utf-8"
        )
        combined = source + wrapper
        forbidden = (
            "printer.gcode.script",
            "/printer/gcode",
            "BOX_SEND_DATA",
            "MOTOR_FLASH_PARAM",
            "MOTOR_SYS_PARAM",
            "MOTOR_CONTROL DATA",
            "MOTOR_REBOOT",
            "MOTOR_BOOT",
            "MOTOR_SET_ADDR",
            "subprocess",
            "os.system",
        )
        for token in forbidden:
            self.assertNotIn(token, combined, token)


if __name__ == "__main__":
    unittest.main()
