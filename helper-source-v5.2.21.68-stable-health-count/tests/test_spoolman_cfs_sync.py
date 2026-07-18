#!/usr/bin/env python3
"""Regression tests for the K2 Pro Spoolman/CFS worker."""

import contextlib
import importlib.util
import pathlib
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "spoolman_cfs_sync.py"
SPEC = importlib.util.spec_from_file_location("spoolman_cfs_sync", MODULE_PATH)
SYNC = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(SYNC)


class StartupClockTests(unittest.TestCase):
    def test_wall_clock_jump_does_not_end_readiness_wait(self) -> None:
        with contextlib.ExitStack() as stack:
            stack.enter_context(
                mock.patch.object(SYNC.time, "monotonic", side_effect=[100.0, 100.0, 105.0])
            )
            stack.enter_context(
                mock.patch.object(
                    SYNC.time,
                    "time",
                    side_effect=AssertionError("readiness must not use the wall clock"),
                )
            )
            stack.enter_context(mock.patch.object(SYNC.time, "sleep", return_value=None))
            stack.enter_context(
                mock.patch.object(
                    SYNC,
                    "moonraker_ready",
                    side_effect=[(False, "Klippy state initializing"), (True, "ready")],
                )
            )
            ok, message = SYNC.wait_for_ready(max_wait=180)

        self.assertTrue(ok)
        self.assertEqual(message, "ready")


if __name__ == "__main__":
    unittest.main()
