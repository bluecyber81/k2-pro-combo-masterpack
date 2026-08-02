#!/usr/bin/env python3
"""Regression checks for package labels and managed-service drift handling."""

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION = "v5.2.21.91-auto-addr-recovery"


class PackageConsistencyTests(unittest.TestCase):
    def test_primary_package_labels_match(self) -> None:
        for relative in (
            "helper.sh",
            "install_k2pro.sh",
            "scripts/preflight_k2pro.sh",
            "START_HERE_K2_PRO_COMBO.md",
        ):
            source = (ROOT / relative).read_text(encoding="utf-8")
            self.assertIn(VERSION, source, relative)

    def test_spoolman_build_label_matches_package(self) -> None:
        source = (ROOT / "spoolman_cfs_sync.py").read_text(encoding="utf-8")
        self.assertIn('BUILD_LABEL = "5.2.21.91-auto-addr-recovery"', source)

    def test_auto_addr_recovery_is_exact_and_integrated(self) -> None:
        for relative in (
            "scripts/auto_addr_recovery.sh",
            "tests/test_auto_addr_recovery.py",
            "files/auto_addr_recovery/auto_addr_wrapper.py",
            "docs/K2_PRO_AUTO_ADDR_RECOVERY_2026-08-02.md",
        ):
            self.assertTrue((ROOT / relative).is_file(), relative)
        helper = (ROOT / "helper.sh").read_text(encoding="utf-8")
        installer = (ROOT / "install_k2pro.sh").read_text(encoding="utf-8")
        module = (ROOT / "scripts" / "auto_addr_recovery.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("--auto-addr-status", helper)
        self.assertIn("--auto-addr-install", helper)
        self.assertIn("--auto-addr-restore", helper)
        self.assertIn("auto_addr_recovery.sh\" selftest", installer)
        self.assertIn("d413f7d641085cf7f8506558abbb973d", module)
        self.assertIn("304e49f651081ff9679bfbd355f4b656", module)
        self.assertIn("require_cold_standby", module)
    def test_status_page_has_cache_and_script_fallbacks(self) -> None:
        html = (ROOT / "web" / "k2-status" / "index.html").read_text(
            encoding="utf-8"
        )
        hub = (ROOT / "scripts" / "k2_status_hub.sh").read_text(encoding="utf-8")
        self.assertIn('http-equiv="Cache-Control"', html)
        self.assertIn('id="startup"', html)
        self.assertIn('href="status.json"', html)
        self.assertIn('rel="icon" href="data:,"', html)
        self.assertIn("usage.last_completed", html)
        self.assertIn("k2_status_nginx.py", hub)
        self.assertIn("http://PRINTER-IP:4410/", hub)
        self.assertNotIn("4409/k2-status", hub)
        dependencies = (ROOT / "scripts" / "dependency_audit_k2pro.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn('k2_status_hub.sh" status', dependencies)
        self.assertIn('port_row "K2 status" 4410', dependencies)
        self.assertNotIn("Fluidd K2 status link", dependencies)

    def test_cfs_guard_has_cold_idle_watcher(self) -> None:
        source = (ROOT / "scripts" / "cfs_db_guard.py").read_text(encoding="utf-8")
        service = (ROOT / "scripts" / "cfs_db_guard.sh").read_text(encoding="utf-8")
        self.assertIn("--watch", source)
        self.assertIn("printer_safe_for_automatic_repair", source)
        self.assertIn("--watch --delay", service)
        self.assertIn("cfs_db_guard_watch.pid", service)

    def test_compact_cfs_scan_has_a_bounded_gcode_budget(self) -> None:
        source = (ROOT / "scripts" / "cfs_safety_scan.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("CFS_SCAN_MAX_SECONDS", source)
        self.assertIn("gcode_deadline", source)
        self.assertIn('"16" if compact_mode else "120"', source)
        self.assertIn('"300000" if compact_mode else "5000000"', source)
        health = (ROOT / "scripts" / "health.sh").read_text(encoding="utf-8")
        self.assertIn("Compact G-code safety scan used its bounded", health)
        self.assertNotIn("G-code safety scan was limited to newest files", health)

    def test_installer_refreshes_managed_service_copies(self) -> None:
        source = (ROOT / "install_k2pro.sh").read_text(encoding="utf-8")
        self.assertIn("sha256sum -c PACKAGE_SHA256SUMS.txt", source)
        self.assertIn('sync_managed_service "$TARGET/scripts/S97cfs_safe_monitor"', source)
        self.assertIn('sync_managed_service "$TARGET/scripts/S98nozzle_camera_recover"', source)
        self.assertIn("does not restart printer services", source)

    def test_health_reports_managed_service_drift(self) -> None:
        source = (ROOT / "scripts" / "health.sh").read_text(encoding="utf-8")
        self.assertIn("check_managed_service_copy()", source)
        self.assertIn("installed copy differs from the helper source", source)

    def test_protection_guard_is_packaged_and_integrated(self) -> None:
        self.assertTrue((ROOT / "scripts" / "k2pro_protection_guard.py").is_file())
        self.assertTrue((ROOT / "scripts" / "k2pro_protection_guard.sh").is_file())
        helper = (ROOT / "helper.sh").read_text(encoding="utf-8")
        health = (ROOT / "scripts" / "health.sh").read_text(encoding="utf-8")
        installer = (ROOT / "install_k2pro.sh").read_text(encoding="utf-8")
        self.assertIn("--protection-status", helper)
        self.assertIn("check_protection_guard()", health)
        self.assertIn("k2pro_protection_guard.py\" --selftest", installer)

    def test_passive_kseries_insights_are_packaged_and_integrated(self) -> None:
        for relative in (
            "scripts/bed_mesh_insights.py",
            "scripts/bed_mesh_insights.sh",
            "scripts/k2_lan_insights.py",
            "scripts/k2_lan_insights.sh",
            "scripts/k2_observability.py",
            "scripts/filament_calibration.py",
            "scripts/filament_calibration.sh",
            "scripts/motor_controller_report.py",
            "scripts/motor_controller_report.sh",
            "scripts/gcode_preflight.py",
            "scripts/gcode_preflight.sh",
            "scripts/gcode_time_audit.py",
            "scripts/post_update_guard.py",
            "scripts/post_update_guard.sh",
            "scripts/k2_status_hub.sh",
            "web/k2-status/index.html",
            "web/k2-status/status.json",
            "docs/K_SERIES_PROJECT_INSIGHTS_K2_PRO_2026-07-30.md",
            "docs/K2_PRO_AI_NOZZLE_CAMERA_2026-07-31.md",
            "docs/K2_PRO_CFS_MOTOR_CONTROLLER_2026-08-01.md",
        ):
            self.assertTrue((ROOT / relative).is_file(), relative)
        helper = (ROOT / "helper.sh").read_text(encoding="utf-8")
        installer = (ROOT / "install_k2pro.sh").read_text(encoding="utf-8")
        self.assertIn("--bed-mesh-insights", helper)
        self.assertIn("--k2-lan-insights", helper)
        self.assertIn("--gcode-preflight", helper)
        self.assertIn("--post-update-status", helper)
        self.assertIn("--status-hub-install", helper)
        self.assertIn("--motor-controller-status", helper)
        self.assertIn("bed_mesh_insights.py\" --selftest", installer)
        self.assertIn("k2_lan_insights.py\" --selftest", installer)
        self.assertIn("k2_observability.py\" --selftest", installer)
        self.assertIn("filament_calibration.py\" --selftest", installer)
        self.assertIn("gcode_preflight.py\" --selftest", installer)
        self.assertIn("gcode_time_audit.py\" --selftest", installer)
        self.assertIn("post_update_guard.py\" --selftest", installer)
        self.assertIn("motor_controller_report.py\" --selftest", installer)

    def test_motor_controller_report_is_read_only_and_integrated(self) -> None:
        helper = (ROOT / "helper.sh").read_text(encoding="utf-8")
        health = (ROOT / "scripts" / "health.sh").read_text(encoding="utf-8")
        worker = (ROOT / "scripts" / "motor_controller_report.py").read_text(
            encoding="utf-8"
        )
        self.assertIn("--motor-controller-status", helper)
        self.assertIn("check_motor_controllers()", health)
        self.assertIn("MOTOR_CONTROLLER_SUMMARY|", worker)
        self.assertIn("read_only", worker)
        self.assertNotIn("printer.gcode.script", worker)
        self.assertNotIn("/printer/gcode", worker)

    def test_generated_status_json_is_excluded_from_package_manifest(self) -> None:
        source = (ROOT / "tools" / "update_manifest.ps1").read_text(
            encoding="utf-8"
        )
        self.assertIn(r"web\k2-status\status.json", source)

    def test_generated_python_bytecode_is_not_packaged(self) -> None:
        cache_dirs = [path.relative_to(ROOT) for path in ROOT.rglob("__pycache__")]
        bytecode_files = [
            path.relative_to(ROOT)
            for pattern in ("*.pyc", "*.pyo")
            for path in ROOT.rglob(pattern)
        ]
        installer = (ROOT / "install_k2pro.sh").read_text(encoding="utf-8")
        self.assertEqual([], cache_dirs, f"generated cache directories: {cache_dirs}")
        self.assertEqual([], bytecode_files, f"generated bytecode: {bytecode_files}")
        for cache_name in ("__pycache__", ".ruff_cache", ".mypy_cache", ".pytest_cache"):
            self.assertIn(f"-name {cache_name}", installer)
        self.assertIn("-name '*.pyc'", installer)
        self.assertIn("-name '*.pyo'", installer)
        self.assertIn("-exec rm -f {} +", installer)

    def test_nozzle_camera_power_guard_is_exact_and_nonblocking(self) -> None:
        guard = (ROOT / "scripts" / "nozzle_camera_power_guard.sh").read_text(
            encoding="utf-8"
        )
        stock_path = ROOT / "files" / "nozzle_camera" / "nozzle_cam_power.sh"
        stock = stock_path.read_text(encoding="utf-8")
        installer = (ROOT / "install_k2pro.sh").read_text(encoding="utf-8")
        helper = (ROOT / "helper.sh").read_text(encoding="utf-8")
        self.assertTrue(stock_path.is_file())
        self.assertIn(
            'EXPECTED_SHA256="35f8441be73a5c2741993832795bd0dee'
            '7dfba28277e8d2f795aa1d7abb274b9"',
            guard,
        )
        self.assertIn('model" = "F012"', guard)
        self.assertIn('board" = "CR0CN200400C10"', guard)
        self.assertIn("printer_cold_idle", guard)
        self.assertIn("NOZZLE_POWER_BACKUP", guard)
        self.assertNotIn("sleep ", stock)
        self.assertNotIn("cam_sub_busy", stock)
        self.assertIn("nozzle_camera_power_guard.sh\" selftest", installer)
        self.assertIn("--nozzle-power-status", helper)
        self.assertIn("--nozzle-power-restore", helper)

    def test_nozzle_ai_probe_restores_standby_and_reports_readiness(self) -> None:
        probe = (ROOT / "scripts" / "nozzle_camera_recover.sh").read_text(
            encoding="utf-8"
        )
        helper = (ROOT / "helper.sh").read_text(encoding="utf-8")
        health = (ROOT / "scripts" / "health.sh").read_text(encoding="utf-8")
        observability = (ROOT / "scripts" / "k2_observability.py").read_text(
            encoding="utf-8"
        )
        self.assertIn("printer_cold_idle", probe)
        self.assertIn("probe_cleanup", probe)
        self.assertIn("restored to on-demand standby", probe)
        self.assertIn("Auto PA, Flow Ratio and selected CFS waste checks", probe)
        self.assertIn("first-layer and ongoing print-fault detection use the main", probe.lower())
        self.assertIn("tail -n 30000", probe)
        self.assertIn("compressed archives are skipped", probe)
        self.assertIn("NOZZLE_LOG_CLASSIFICATION|", probe)
        self.assertIn("--nozzle-ai-status", helper)
        self.assertIn("AI_CALIBRATION_READY|yes", health)
        self.assertIn("--ai-status", observability)
        self.assertNotIn("AI/flow/first-layer checks", probe)

    def test_flow_and_pressure_advance_are_not_changed(self) -> None:
        helper = (ROOT / "helper.sh").read_text(encoding="utf-8")
        status_page = (ROOT / "web" / "k2-status" / "index.html").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("FLOW_RATIO_CALIBRATE", helper)
        self.assertNotIn("PRESSURE_ADVANCE_CALIBRATE", helper)
        self.assertNotIn("printer.gcode.script", status_page)

    def test_filament_calibration_capture_is_read_only_and_integrated(self) -> None:
        helper = (ROOT / "helper.sh").read_text(encoding="utf-8")
        worker = (ROOT / "scripts" / "filament_calibration.py").read_text(
            encoding="utf-8"
        )
        health = (ROOT / "scripts" / "health.sh").read_text(encoding="utf-8")
        dependencies = (ROOT / "scripts" / "dependency_audit_k2pro.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("--filament-calibration-status", helper)
        self.assertIn("--filament-calibration-history", helper)
        self.assertIn("measurement_source=no", worker)
        self.assertIn("safe_to_persist=", worker)
        self.assertIn("CALIBRATED_MATERIAL|", worker)
        self.assertIn("PROFILE_RECOMMENDATION|", worker)
        self.assertIn("PA/Flow result capture", health)
        self.assertIn("Filament PA/Flow result worker", dependencies)
        self.assertIn("Filament PA/Flow result wrapper", dependencies)
        self.assertNotIn('method="POST"', worker)
        self.assertNotIn("printer.gcode.script", worker)


if __name__ == "__main__":
    unittest.main()
