#!/usr/bin/env python3
"""Regression checks for the K2 Pro auto-address recovery payload."""

from __future__ import annotations

import argparse
import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_MODULE = ROOT / "files" / "auto_addr_recovery" / "auto_addr_wrapper.py"


def load_module(path: pathlib.Path):
    spec = importlib.util.spec_from_file_location("k2pro_auto_addr_recovery", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AutoAddrRecoveryTests(unittest.TestCase):
    module_path = DEFAULT_MODULE

    @classmethod
    def setUpClass(cls) -> None:
        cls.source = cls.module_path.read_text(encoding="utf-8")
        cls.module = load_module(cls.module_path)

    def new_instance(self):
        instance = self.module.AutoAddrWrapper.__new__(self.module.AutoAddrWrapper)
        instance.debug = False
        instance.uniid_changed = False
        return instance

    def make_package(self, function_code: int, slave_addr: int, data: list[int]):
        return self.module.DataPackage(
            self.module.PACK_HEAD,
            slave_addr,
            len(data) + 3,
            self.module.STATUS_OK,
            function_code,
            data,
            0,
        )

    def test_loader_ack_is_ignored_without_exception(self) -> None:
        self.new_instance().function_code_cb(
            self.make_package(
                self.module.CMD_LOADER_TO_APP,
                self.module.BROADCAST_ADDR,
                [],
            )
        )

    def test_unknown_ack_is_ignored_without_exception(self) -> None:
        self.new_instance().function_code_cb(
            self.make_package(0xFE, self.module.BROADCAST_ADDR, [])
        )

    def test_second_device_table_can_be_selected(self) -> None:
        mb_entry = self.module.AddrManager(
            0x01, [0x11], 1, 1, 1, 0, self.module.MODE_APP
        )
        clm_entry = self.module.AddrManager(
            0x81, [0x22], 1, 1, 0, 3, self.module.MODE_APP
        )
        self.module.dev_table_map_table = [
            self.module.DevTableMap(
                self.module.DEV_TYPE_MB, self.module.BROADCAST_ADDR_MB, [mb_entry]
            ),
            self.module.DevTableMap(
                self.module.DEV_TYPE_CLM, self.module.BROADCAST_ADDR_CLM, [clm_entry]
            ),
        ]
        self.new_instance().function_code_cb(
            self.make_package(
                self.module.CMD_ONLINE_CHECK,
                0x81,
                [self.module.DEV_TYPE_CLM, self.module.MODE_APP, 0x22],
            )
        )
        self.assertEqual(1, clm_entry.acked)
        self.assertEqual(0, clm_entry.lost_cnt)

    def test_existing_ten_second_cfs_poll_is_preserved(self) -> None:
        self.assertGreaterEqual(self.source.count("time_interval = 10"), 3)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--module", type=pathlib.Path, default=DEFAULT_MODULE)
    args, _ = parser.parse_known_args()
    AutoAddrRecoveryTests.module_path = args.module
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(AutoAddrRecoveryTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
