#!/usr/bin/env python3
"""Regression tests for the guarded Windows K2 Pro hybrid time wrapper."""

import json
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "extras" / "windows" / "klipper-estimator" / "K2Pro-Hybrid-Time.ps1"


def run_wrapper(original_text, estimated_text, offset_seconds=60):
    powershell = shutil.which("powershell.exe") or shutil.which("powershell")
    if not powershell:
        raise unittest.SkipTest("PowerShell is unavailable")
    temporary = tempfile.TemporaryDirectory()
    root = pathlib.Path(temporary.name)
    original = root / "original.gcode"
    estimated = root / "estimated.gcode"
    output = root / "output.gcode"
    calibration = root / "calibration.json"
    original.write_text(original_text, encoding="utf-8")
    estimated.write_text(estimated_text, encoding="utf-8")
    calibration.write_text(
        json.dumps({"offset_seconds": offset_seconds, "sample_count": 10}),
        encoding="utf-8",
    )
    result = subprocess.run(
        [
            powershell,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(WRAPPER),
            "-Original",
            str(original),
            "-Estimated",
            str(estimated),
            "-Calibration",
            str(calibration),
            "-Output",
            str(output),
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    text = output.read_text(encoding="utf-8") if output.exists() else ""
    temporary.cleanup()
    return result, text


def m73_values(text):
    values = []
    for line in text.splitlines():
        if not re.match(r"^\s*M73\b", line):
            continue
        progress = re.search(r"(?:^|\s)P([0-9.]+)", line)
        remaining = re.search(r"(?:^|\s)R([0-9.]+)", line)
        if progress and remaining:
            values.append((float(progress.group(1)), float(remaining.group(1))))
    return values


class HybridTimeTests(unittest.TestCase):
    def test_cfs_gap_tracks_remaining_tool_transitions(self):
        original = "\n".join(
            (
                "; estimated printing time (normal mode) = 1h",
                "M73 P0 R20",
                "T0",
                "M73 P25 R15",
                "T1",
                "M73 P50 R10",
                "T0",
                "M73 P100 R0",
                "G1 X10",
                "",
            )
        )
        estimated = "\n".join(
            (
                "; estimated printing time (normal mode) = 20m",
                "M73 P0 R20",
                "T0",
                "M73 P25 R15",
                "T1",
                "M73 P50 R10",
                "T0",
                "M73 P100 R0",
                "G1 X10",
                "; Processed by klipper_estimator test",
                "",
            )
        )
        result, output = run_wrapper(original, estimated)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(m73_values(output), [(0.0, 61.0), (25.0, 56.0), (50.0, 31.0), (100.0, 0.0)])
        self.assertIn("estimated printing time (normal mode) = 1h 1m 0s", output)
        self.assertIn("K2PRO_HYBRID_TIME v2", output)
        self.assertIn("cfs_gap=2400", output)
        self.assertIn("m73_start=1200", output)
        self.assertIn("G1 X10", output)

    def test_single_color_keeps_estimator_timeline_and_decaying_offset(self):
        original = "\n".join(
            (
                "; estimated printing time (normal mode) = 40m",
                "T0",
                "M73 P0 R40",
                "M73 P50 R20",
                "M73 P100 R0",
                "G1 X20",
                "",
            )
        )
        estimated = "\n".join(
            (
                "; estimated printing time (normal mode) = 42m",
                "T0",
                "M73 P0 R42",
                "M73 P50 R21",
                "M73 P100 R0",
                "G1 X20",
                "; Processed by klipper_estimator test",
                "",
            )
        )
        result, output = run_wrapper(original, estimated)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(m73_values(output), [(0.0, 43.0), (50.0, 22.0), (100.0, 0.0)])
        self.assertIn("strategy=klipper-motion", output)
        self.assertIn("cfs_gap=0", output)
        self.assertIn("estimated printing time (normal mode) = 43m 0s", output)

    def test_v1_cfs_file_is_upgraded_without_double_offset(self):
        v1 = "\n".join(
            (
                "; estimated printing time (normal mode) = 1h 1m 0s",
                "M73 P0 R21",
                "T0",
                "M73 P25 R16",
                "T1",
                "M73 P50 R11",
                "T0",
                "M73 P100 R0",
                "G1 X10",
                "; K2PRO_HYBRID_TIME v1 strategy=creality-cfs base=3600 offset=60 target=3660 transitions=2 samples=9",
                "",
            )
        )
        result, output = run_wrapper(v1, v1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(m73_values(output), [(0.0, 61.0), (25.0, 56.0), (50.0, 31.0), (100.0, 0.0)])
        self.assertIn("target=3660", output)
        self.assertIn("applied_offset=0", output)
        self.assertEqual(output.count("K2PRO_HYBRID_TIME"), 1)


if __name__ == "__main__":
    unittest.main()
