#!/usr/bin/env python3
"""Regression tests for passive K-series insight tools."""

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def load_module(name: str, relative: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load {}".format(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BED_MESH = load_module("bed_mesh_insights", "scripts/bed_mesh_insights.py")
LAN = load_module("k2_lan_insights", "scripts/k2_lan_insights.py")
OBSERVABILITY = load_module("k2_observability", "scripts/k2_observability.py")
GCODE_PREFLIGHT = load_module("gcode_preflight", "scripts/gcode_preflight.py")
POST_UPDATE = load_module("post_update_guard", "scripts/post_update_guard.py")


class BedMeshInsightTests(unittest.TestCase):
    def test_plane_is_separated_from_shape(self) -> None:
        matrix = []
        for row in range(5):
            matrix.append([0.03 * column - 0.02 * row + 0.5 for column in range(5)])
        report = BED_MESH.analyze_payload(
            {
                "result": {
                    "status": {
                        "bed_mesh": {
                            "profile_name": "test",
                            "mesh_min": [0, 0],
                            "mesh_max": [40, 40],
                            "probed_matrix": matrix,
                        }
                    }
                }
            }
        )
        self.assertLess(report["residual"]["max_abs_mm"], 1e-9)
        self.assertAlmostEqual(report["plane"]["delta_x_mm"], 0.12, places=9)
        self.assertAlmostEqual(report["plane"]["delta_y_mm"], -0.08, places=9)

    def test_bowl_is_reported_as_residual_deformation(self) -> None:
        matrix = [
            [0.04 * ((column - 2) ** 2 + (row - 2) ** 2) for column in range(5)]
            for row in range(5)
        ]
        report = BED_MESH.analyze_payload(
            {
                "bed_mesh": {
                    "mesh_min": [0, 0],
                    "mesh_max": [40, 40],
                    "probed_matrix": matrix,
                }
            }
        )
        self.assertGreater(report["residual"]["peak_to_peak_mm"], 0.20)
        self.assertEqual(report["residual"]["level"], "WARN")
        self.assertLess(report["residual"]["center_minus_edge_mm"], -0.05)
        self.assertIn("center lower", report["residual"]["shape_hint"])

    def test_cli_reads_fixture_without_network(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = pathlib.Path(temporary) / "bed-mesh-fixture.json"
            fixture.write_text(
                json.dumps(
                    {
                        "bed_mesh": {
                            "mesh_min": [5, 5],
                            "mesh_max": [295, 295],
                            "probed_matrix": [[0.0, 0.1], [0.2, 0.3]],
                        }
                    }
                ),
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(ROOT / "scripts" / "bed_mesh_insights.py"),
                    "--input",
                    str(fixture),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("SAFETY|OK|read_only_existing_mesh", result.stdout)

    def test_full_and_adaptive_meshes_have_distinct_comparison_keys(self) -> None:
        full = BED_MESH.classify_mesh_scope([5.0, 5.0], [295.0, 295.0], 9, 9)
        adaptive = BED_MESH.classify_mesh_scope([141.0, 127.0], [159.0, 173.0], 3, 3)
        self.assertEqual(full["scope"], "full_plate")
        self.assertEqual(adaptive["scope"], "adaptive_region")
        self.assertNotEqual(full["comparison_key"], adaptive["comparison_key"])

    def test_report_warns_against_cross_scope_comparison(self) -> None:
        report = BED_MESH.analyze_payload(
            {
                "bed_mesh": {
                    "mesh_min": [141, 127],
                    "mesh_max": [159, 173],
                    "probed_matrix": [[0.0, 0.01, 0.02], [0.0, 0.01, 0.02], [0.0, 0.01, 0.02]],
                }
            }
        )
        rendered = BED_MESH.render_report(report)
        self.assertIn("scope=adaptive_region", rendered)
        self.assertIn("Compare residual values only when scope, grid and area match", rendered)


class K2LanInsightTests(unittest.TestCase):
    def test_request_table_is_get_only(self) -> None:
        LAN.validate_requests()
        requests = list(LAN.SAFE_REQUESTS) + [LAN.MATERIAL_REQUEST]
        self.assertTrue(all(request["method"] == "get" for request in requests))
        source = (ROOT / "scripts" / "k2_lan_insights.py").read_text(encoding="utf-8")
        self.assertNotIn('"method": "set"', source)

    def test_websocket_frame_roundtrip(self) -> None:
        for length in (1, 125, 126, 65535, 65536):
            payload = b"x" * length
            frame = LAN.encode_client_frame(payload)
            decoded, remainder = LAN.extract_frame(frame)
            self.assertIsNotNone(decoded)
            self.assertTrue(decoded[0])
            self.assertEqual(decoded[2], payload)
            self.assertEqual(remainder, b"")

    def test_summary_omits_rfid_and_identifiers(self) -> None:
        payload = {
            "state": 0,
            "printId": "private-print-id",
            "usedMaterialLength": 42,
            "boxsInfo": {
                "materialBoxs": [
                    {
                        "id": 1,
                        "type": 0,
                        "materials": [
                            {
                                "id": 2,
                                "vendor": "Sovol",
                                "type": "PLA",
                                "name": "Steel Blue",
                                "color": "#112233",
                                "percent": 75,
                                "selected": 1,
                                "rfid": "private-rfid",
                            }
                        ],
                    }
                ]
            },
        }
        report = LAN.summarize(payload)
        serialized = json.dumps(report)
        self.assertNotIn("private-print-id", serialized)
        self.assertNotIn("private-rfid", serialized)
        self.assertEqual(report["cfs"]["selected_slots"], ["T1C"])
        self.assertEqual(
            report["cfs"]["selection_semantics"],
            "ui_material_selection_not_proof_of_feed_arm",
        )

    def test_material_request_state_is_explicit(self) -> None:
        missing = LAN.summarize({}, materials_requested=True)
        self.assertTrue(missing["materials"]["requested"])
        self.assertFalse(missing["materials"]["response_received"])
        received = LAN.summarize({"retMaterials": []}, materials_requested=True)
        self.assertTrue(received["materials"]["response_received"])
        self.assertEqual(received["materials"]["profile_count"], 0)

    def test_selftests_run(self) -> None:
        for relative in (
            "scripts/bed_mesh_insights.py",
            "scripts/k2_lan_insights.py",
            "scripts/k2_observability.py",
            "scripts/gcode_preflight.py",
            "scripts/post_update_guard.py",
        ):
            result = subprocess.run(
                [sys.executable, "-B", str(ROOT / relative), "--selftest"],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("SELFTEST|OK|", result.stdout)


class K2ObservabilityTests(unittest.TestCase):
    def test_ai_preferences_keep_calibration_and_first_layer_separate(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "user_print_refer.json"
            path.write_text(
                json.dumps(
                    {
                        "ai_control": {
                            "switch": 1,
                            "firstFloor": 0,
                            "flowDetect": 1,
                            "flowDetectMode": 0,
                            "flowEmDetect": 1,
                            "wasteSwitch": 1,
                        }
                    }
                ),
                encoding="utf-8",
            )
            status = OBSERVABILITY.read_ai_preferences(path)
        self.assertTrue(status["calibration_ready"])
        self.assertEqual(status["first_layer"], 0)
        self.assertEqual(status["first_layer_camera"], "main")
        self.assertEqual(
            status["nozzle_camera_roles"],
            "auto_pa_flow_ratio_cfs_waste",
        )

    def test_nozzle_camera_lifecycle_classification(self) -> None:
        self.assertEqual(
            OBSERVABILITY.classify_nozzle_camera("1", True, False, False),
            "standby",
        )
        self.assertEqual(
            OBSERVABILITY.classify_nozzle_camera("0", True, True, True),
            "active",
        )
        self.assertEqual(
            OBSERVABILITY.classify_nozzle_camera("0", True, False, False),
            "waking_or_fault",
        )
        self.assertEqual(
            OBSERVABILITY.classify_nozzle_camera("1", True, True, True),
            "stopping",
        )

    def test_consumption_is_delta_based_and_dry_run(self) -> None:
        tracker, completed = OBSERVABILITY.update_consumption_tracker(
            {},
            "printing",
            "fixture.gcode",
            100.0,
            "T1A",
            "remaining_material_match",
            session_hash="fixture",
        )
        self.assertIsNone(completed)
        tracker, _ = OBSERVABILITY.update_consumption_tracker(
            tracker,
            "printing",
            "fixture.gcode",
            125.0,
            "T1A",
            "remaining_material_match",
            session_hash="fixture",
        )
        tracker, completed = OBSERVABILITY.update_consumption_tracker(
            tracker,
            "complete",
            "fixture.gcode",
            130.0,
            "T1A",
            "remaining_material_match",
            session_hash="fixture",
        )
        self.assertIsNotNone(completed)
        self.assertAlmostEqual(completed["observed_total_mm"], 30.0)
        self.assertAlmostEqual(completed["by_slot_mm"]["T1A"], 30.0)
        self.assertEqual(tracker["mode"], "dry_run_no_spoolman_writes")

    def test_low_confidence_usage_is_not_assigned_to_slot(self) -> None:
        tracker, _ = OBSERVABILITY.update_consumption_tracker(
            {},
            "printing",
            "fixture.gcode",
            0.0,
            "T1B",
            "box_filament_index",
        )
        tracker, _ = OBSERVABILITY.update_consumption_tracker(
            tracker,
            "printing",
            "fixture.gcode",
            12.0,
            "T1B",
            "box_filament_index",
        )
        active = tracker["active"]
        self.assertEqual(active["by_slot_mm"]["T1B"], 0.0)
        self.assertEqual(active["unattributed_mm"], 12.0)

    def test_mesh_fingerprint_is_stable_and_changes_with_matrix(self) -> None:
        payload = {
            "bed_mesh": {
                "profile_name": "default",
                "mesh_min": [0, 0],
                "mesh_max": [10, 10],
                "probed_matrix": [[0.0, 0.1], [0.2, 0.3]],
            }
        }
        first = OBSERVABILITY.mesh_fingerprint(payload)
        second = OBSERVABILITY.mesh_fingerprint(json.loads(json.dumps(payload)))
        self.assertEqual(first, second)
        payload["bed_mesh"]["probed_matrix"][1][1] = 0.31
        self.assertNotEqual(first, OBSERVABILITY.mesh_fingerprint(payload))


class GCodePreflightTests(unittest.TestCase):
    def test_realistic_creality_gcode_has_required_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "fixture.gcode"
            path.write_text(
                "\n".join(
                    (
                        "; generated by Creality_Print V7",
                        "; thumbnail begin 96x96 4",
                        "; AAAA",
                        "; thumbnail end",
                        "; total layers count = 2",
                        "; estimated printing time (normal mode) = 1m",
                        "; filament used [g] = 1",
                        "EXCLUDE_OBJECT_DEFINE NAME=test",
                        "START_PRINT EXTRUDER_TEMP=220 BED_TEMP=50",
                        "T0",
                    )
                )
                + "\n",
                encoding="utf-8",
            )
            report = GCODE_PREFLIGHT.scan_file(path)
        self.assertEqual(report["summary"]["WARN"], 0)
        self.assertEqual(report["summary"]["FAIL"], 0)

    def test_duplicate_mesh_m600_and_t4_are_detected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "bad.gcode"
            path.write_text(
                "T4\nSTART_PRINT\nG29\nBED_MESH_CALIBRATE\nM600\n",
                encoding="utf-8",
            )
            report = GCODE_PREFLIGHT.scan_file(path)
        codes = {row["code"] for row in report["findings"]}
        self.assertIn("MESH_COMMAND_DUPLICATE", codes)
        self.assertIn("M600_WITH_CFS", codes)
        self.assertIn("CFS_TOOL_OUT_OF_RANGE", codes)


class PostUpdateGuardTests(unittest.TestCase):
    def test_firmware_update_changes_are_reported_without_repair(self) -> None:
        baseline = {
            "identity": {
                "model": "F012",
                "board": "CR0CN200400C10",
                "firmware": "1.1.6.7",
            },
            "cfs_version": "1.5.0",
            "helper_version": "v77",
            "camera": {"model": "cam", "version": "250708"},
            "cfs_database": {
                "official_fingerprint_sha256": "a",
                "custom_count": 2,
            },
            "files": {},
        }
        current = json.loads(json.dumps(baseline))
        current["identity"]["firmware"] = "1.1.6.8"
        current["moonraker"] = {"reachable": True, "klippy_state": "ready"}
        findings = POST_UPDATE.compare_snapshots(baseline, current)
        codes = {row["code"] for row in findings}
        self.assertIn("FIRMWARE_CHANGED", codes)
        source = (ROOT / "scripts" / "post_update_guard.py").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("printer.gcode.script", source)
        self.assertNotIn('method="POST"', source)


if __name__ == "__main__":
    unittest.main()
