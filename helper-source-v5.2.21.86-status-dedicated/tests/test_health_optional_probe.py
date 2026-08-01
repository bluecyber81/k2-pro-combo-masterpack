#!/usr/bin/env python3
"""Regression checks for deterministic optional-probe health reporting."""

import pathlib
import unittest


HEALTH_SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "health.sh"


class OptionalProbeHealthTests(unittest.TestCase):
    def test_zero_and_nonzero_probe_counts_both_report_ok(self) -> None:
        source = HEALTH_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('if [ "$helix_probe" -gt 0 ]; then', source)
        self.assertIn(
            'ok "HelixPrint optional-plugin probe is harmless in Moonraker log: $helix_probe"',
            source,
        )
        self.assertIn(
            'ok "No HelixPrint optional-plugin probes in recent Moonraker log"',
            source,
        )


if __name__ == "__main__":
    unittest.main()
