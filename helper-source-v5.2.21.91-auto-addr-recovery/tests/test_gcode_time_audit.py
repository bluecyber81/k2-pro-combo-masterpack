#!/usr/bin/env python3
"""Regression tests for the passive G-code time audit."""

import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PATH = ROOT / "scripts" / "gcode_time_audit.py"
SPEC = importlib.util.spec_from_file_location("gcode_time_audit", PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load {}".format(PATH))
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class GCodeTimeAuditTests(unittest.TestCase):
    def test_large_cfs_gap_is_reported(self):
        report = AUDIT.analyze_lines(
            (
                "; estimated printing time (normal mode) = 4h\n",
                '; post_process = "K2Pro-CrealityPrint-Estimator.cmd"\n',
                "M73 P0 R100\n",
                "T0\n",
                "T1\n",
            )
        )
        self.assertEqual(report["level"], "WARN")
        self.assertIn("configured_postprocessor_not_applied", report["findings"])
        self.assertIn("cfs_remaining_time_omits_large_transition_share", report["findings"])

    def test_v2_complete_timeline_is_ok(self):
        report = AUDIT.analyze_lines(
            (
                "; estimated printing time (normal mode) = 1h\n",
                "M73 P0 R60\n",
                "T0\n",
                "T1\n",
                "; Processed by klipper_estimator test\n",
                "; K2PRO_HYBRID_TIME v2 strategy=creality-cfs base=3500 offset=100 target=3600 transitions=1 cfs_gap=1200 m73_start=2300 applied_offset=100 samples=10\n",
            )
        )
        self.assertEqual(report["level"], "OK")
        self.assertEqual(report["findings"], [])


if __name__ == "__main__":
    unittest.main()
