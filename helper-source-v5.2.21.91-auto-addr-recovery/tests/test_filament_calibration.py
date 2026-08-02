#!/usr/bin/env python3
"""Regression tests for read-only K2 Pro filament calibration capture."""

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "filament_calibration.py"
SPEC = importlib.util.spec_from_file_location("filament_calibration", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FilamentCalibrationTests(unittest.TestCase):
    def parse(self, lines):
        original = MODULE.iter_log_lines
        try:
            MODULE.iter_log_lines = lambda _path: iter(lines)
            return MODULE.parse_calibration_logs([Path("fixture.log")])
        finally:
            MODULE.iter_log_lines = original

    def test_successful_pa_and_flow_are_confirmed(self):
        parsed = self.parse(
            [
                "[2026-07-31 10:00:00.000]- with self test = 1",
                "[2026-07-31 10:00:01.000]- start print file = /gcodes/test.gcode",
                "[2026-07-31 10:00:02.000]- flowdetect = 1, flow_em_detect = 1",
                "[2026-07-31 10:00:03.000]- start flow_pa detect",
                "[2026-07-31 10:00:04.000]- flow_pa result: pressureAdvance=0.049",
                "[2026-07-31 10:00:05.000]- flow_pa best_flow_pressure_advance = 0.047",
                "[2026-07-31 10:00:06.000]- start flow_em detect",
                "[2026-07-31 10:00:07.000]- flow_em best_flow_percentage = 96",
                "[2026-07-31 10:00:08.000]- M221 S96",
            ]
        )
        job = parsed["jobs"][0]
        self.assertEqual(job["classification"], "complete")
        self.assertEqual(
            MODULE.result_value(job),
            {"pressure_advance": 0.047, "flow_percentage": 96.0},
        )

    def test_default_pa_is_not_reported_as_measurement(self):
        parsed = self.parse(
            [
                "[2026-07-31 10:00:00.000]- with self test = 1",
                "[2026-07-31 10:00:03.000]- start flow_pa detect",
                "[2026-07-31 10:00:04.000]- flow_pa result: pressureAdvance=-1",
                "[2026-07-31 10:00:05.000]- AI result flow_pa is invalid (< 0), using default PA value from printer.cfg: 0.038",
                "[2026-07-31 10:00:06.000]- flow_pa detect effective value = 0.038",
            ]
        )
        job = parsed["jobs"][0]
        self.assertEqual(job["classification"], "fallback")
        self.assertIsNone(MODULE.result_value(job)["pressure_advance"])
        self.assertEqual(job["pa"]["fallback_value"], 0.038)

    def test_all_negative_pa_tasks_are_fallback_even_with_best_value(self):
        parsed = self.parse(
            [
                "[2026-07-31 14:20:06.000]- with self test = 1",
                "[2026-07-31 14:20:06.100]- start flow_pa detect",
                *[
                    "[2026-07-31 14:24:37.000]- [flow_pa]Result for "
                    f"pressureAdvance task {index}: -1.000000"
                    for index in range(5)
                ],
                "[2026-07-31 14:24:43.000]- "
                "flow_pa best_flow_pressure_advance = 0.040000",
                "[2026-07-31 14:24:43.100]- "
                "flow_pa detect effective value = 0.040",
            ]
        )
        job = parsed["jobs"][0]
        self.assertEqual(job["classification"], "fallback")
        self.assertFalse(job["pa"]["measured"])
        self.assertEqual(job["pa"]["task_results_valid"], 0)
        self.assertEqual(job["pa"]["task_results_invalid"], 5)
        self.assertEqual(job["pa"]["fallback_value"], 0.04)
        self.assertIsNone(MODULE.result_value(job)["pressure_advance"])

    def test_non_pla_flow_rejection_is_explicit(self):
        parsed = self.parse(
            [
                "[2026-07-31 10:00:00.000]- with self test = 1",
                "[2026-07-31 10:00:01.000]- start flow_em detect",
                "[2026-07-31 10:00:02.000]- ai flow_em detect fail, current print material is not PLA",
            ]
        )
        job = parsed["jobs"][0]
        self.assertEqual(job["classification"], "unsupported")
        self.assertTrue(job["flow"]["unsupported"])

    def test_capture_error_is_failed(self):
        parsed = self.parse(
            [
                "[2026-07-31 10:00:00.000]- with self test = 1",
                "[2026-07-31 10:00:01.000]- start flow_pa detect",
                "[2026-07-31 10:00:02.000]- ai flow_pa detect capture abnormal",
            ]
        )
        self.assertEqual(parsed["jobs"][0]["classification"], "failed")

    def test_nozzle_camera_race_does_not_confirm_copied_defaults(self):
        parsed = self.parse(
            [
                "[2026-07-31 11:28:39.000]- with self test = 1",
                "[2026-07-31 11:38:23.000]- start flow detect fail, "
                "nozzle_camera_is_exist = 0, aiConfig.flowdetect = 1",
                "[2026-07-31 11:38:27.000]- "
                "flow_pa best_flow_pressure_advance = 0.040000",
                "[2026-07-31 11:38:27.100]- "
                "flow_pa detect effective value = 0.040",
                "[2026-07-31 11:38:27.200]- start flow_em detect fail, "
                "nozzle_camera_is_exist = 0, aiConfig.flow_em_detect = 1",
                "[2026-07-31 11:38:27.300]- M221 S100",
                "[2026-07-31 11:43:12.000]- print state = complete",
                "[2026-07-31 11:43:12.100]- Print Finish",
            ]
        )
        job = parsed["jobs"][0]
        self.assertEqual(job["classification"], "failed")
        self.assertFalse(job["pa"]["started"])
        self.assertFalse(job["pa"]["measured"])
        self.assertFalse(job["flow"]["started"])
        self.assertFalse(job["flow"]["measured"])
        self.assertTrue(job["lifecycle"]["finished"])
        self.assertEqual(
            MODULE.result_value(job),
            {"pressure_advance": None, "flow_percentage": None},
        )

    def test_waste_only_fluidd_job_is_not_calibration(self):
        parsed = self.parse(
            [
                "[2026-07-31 10:00:00.000]- fluidd start print file",
                "[2026-07-31 10:00:01.000]- with self test = 0",
                "[2026-07-31 10:00:02.000]- fluidd start = 1",
                "[2026-07-31 10:00:03.000]- fluidd start print file = /gcodes/a.gcode",
                "[2026-07-31 10:00:04.000]- load_ai cmdtype[waste] = { }",
            ]
        )
        job = parsed["jobs"][0]
        self.assertEqual(job["classification"], "not_requested")
        self.assertEqual(job["source"], "fluidd_or_mainsail")
        self.assertEqual(job["waste_checks"], 1)

    def test_requested_without_marker_is_not_invented(self):
        parsed = self.parse(
            [
                "[2026-07-31 10:00:00.000]- with self test = 1",
                "[2026-07-31 10:00:01.000]- start print file = /gcodes/a.gcode",
            ]
        )
        job = parsed["jobs"][0]
        self.assertEqual(job["classification"], "requested_without_measurement")
        self.assertEqual(
            MODULE.result_value(job),
            {"pressure_advance": None, "flow_percentage": None},
        )

    def test_creality_web_job_correlates_file_and_cancel_lifecycle(self):
        parsed = self.parse(
            [
                "[2026-07-31 09:59:00.000]- fluidd start print file",
                "[2026-07-31 10:00:00.000]- web control start print local gcode",
                "[2026-07-31 10:00:00.100]- file name = /gcodes/test.gcode",
                "[2026-07-31 10:00:01.000]- with self test = 1",
                "[2026-07-31 10:00:01.100]- flowdetect = 1, flow_em_detect = 1",
                "[2026-07-31 10:00:02.000]- web control start print local gcode",
                "[2026-07-31 10:00:03.000]- NOZZLE_CLEAR canceled by user",
                "[2026-07-31 10:00:04.000]- user stop print finish",
            ]
        )
        job = parsed["jobs"][0]
        self.assertEqual(job["source"], "creality_web_local")
        self.assertEqual(job["file"], "/gcodes/test.gcode")
        self.assertEqual(job["classification"], "cancelled")
        self.assertTrue(job["lifecycle"]["cancelled"])
        self.assertEqual(job["lifecycle"]["duplicate_start_requests"], 1)

    def test_gcode_metadata_and_pla_eligibility(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.gcode"
            path.write_text(
                "G28\n"
                "; filament_type = PLA\n"
                "; filament_settings_id = eSUN ePLA-HS+ Gray\n"
                "; filament_flow_ratio = 0.97\n"
                "; enable_pressure_advance = 1\n"
                "; pressure_advance = 0.045\n",
                encoding="utf-8",
            )
            metadata = MODULE.read_gcode_metadata(path)
        self.assertEqual(metadata["filament_type"], "PLA")
        self.assertEqual(metadata["filament_flow_ratio"], "0.97")
        self.assertTrue(metadata["flow_pla_family"])

    def test_cfs_mapping_survives_unload_and_builds_profile_recommendation(self):
        parsed = self.parse(
            [
                "[2026-07-31 16:43:24.000]- with self test = 1",
                "[2026-07-31 16:55:11.000]- start flow_pa detect",
                "[2026-07-31 16:55:12.000]- T-Command map: T0(T1A)=>T1B",
                "[2026-07-31 16:55:12.100]- "
                "FlowPa_ExtractAndSetGcodeParams CFS t_command: T0, "
                "Vender: unknown, Remain Length: 100, Color Value: 9ea7ae, "
                "Material Type: 90001, Material Name: PLA, Pressure Advance: 0.040",
                "[2026-07-31 16:59:10.000]- "
                "flow_pa best_flow_pressure_advance = 0.056",
                "[2026-07-31 16:59:39.000]- start flow_em detect",
                "[2026-07-31 17:04:52.000]- flow_em best_flow_percentage = 96",
                "[2026-07-31 17:08:00.000]- print state = complete",
            ]
        )
        job = parsed["jobs"][0]
        job["gcode_metadata"] = {
            "filament_type": "PLA",
            "filament_settings_id": "eSUN PLA HS+ Gray",
            "filament_flow_ratio": "0.98",
            "flow_pla_family": True,
        }
        inventory = [
            {
                "slot": "T1A",
                "material_id": "101001",
                "brand": "Creality",
                "name": "Hyper PLA",
                "type": "PLA",
                "color": "0FFFFFF",
            },
            {
                "slot": "T1B",
                "material_id": "090001",
                "brand": "eSUN",
                "name": "ePLA-HS+ Gray",
                "type": "PLA",
                "color": "09ea7ae",
                "remaining_percent": 100.0,
                "spoolman_spool_id": 2,
            },
        ]
        job["calibrated_material"] = MODULE.resolve_calibrated_material(job, inventory)
        recommendation = MODULE.profile_recommendation(job)

        self.assertEqual(job["calibrated_material"]["slot"], "T1B")
        self.assertEqual(job["calibrated_material"]["material_id"], "090001")
        self.assertTrue(job["calibrated_material"]["verified"])
        self.assertEqual(recommendation["pressure_advance"], 0.056)
        self.assertEqual(recommendation["flow_ratio"], 0.9408)
        self.assertTrue(recommendation["safe_to_persist"])

    def test_source_contains_no_control_plane_writes(self):
        source = MODULE_PATH.read_text(encoding="utf-8")
        for token in (
            'method="POST"',
            '"method": "set"',
            "printer.gcode.script",
            "enableSelfTest\":1",
            "BOX_LOAD",
            "BOX_RETRUDE",
            "SET_HEATER",
            "subprocess.",
            "os.system(",
        ):
            self.assertNotIn(token, source)


if __name__ == "__main__":
    unittest.main()
