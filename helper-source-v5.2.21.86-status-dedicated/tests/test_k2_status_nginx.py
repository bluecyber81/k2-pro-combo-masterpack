import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("k2_status_nginx", ROOT / "scripts" / "k2_status_nginx.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SAMPLE = """events {}
http {
    server {
        listen 4408 default_server;
        root /usr/share/fluidd;
        location / { try_files $uri $uri/ /index.html; }
    }
    server {
        listen 4409 default_server;
        root /usr/share/mainsail;
        location / { try_files $uri $uri/ /index.html; }
    }
    server {
        listen 80;
        location / { return 204; }
    }
}
"""


class StatusNginxTests(unittest.TestCase):
    def test_install_adds_service_worker_free_endpoint(self):
        patched, ports = MODULE.patch_content(SAMPLE)
        self.assertEqual(set(ports), {"4408", "4409", "4410"})
        self.assertEqual(patched.count(MODULE.BEGIN), 1)
        self.assertEqual(patched.count('Cache-Control "no-store'), 1)
        self.assertIn("listen 4410 default_server", patched)
        self.assertIn("/mnt/UDISK/helper-script/web/k2-status", patched)
        self.assertIn("listen 4408", patched)
        self.assertIn("listen 4409", patched)

    def test_install_is_idempotent(self):
        once, _ = MODULE.patch_content(SAMPLE)
        twice, _ = MODULE.patch_content(once)
        self.assertEqual(once, twice)

    def test_check_and_remove(self):
        patched, _ = MODULE.patch_content(SAMPLE)
        valid, ports = MODULE.check_content(patched)
        self.assertTrue(valid)
        self.assertEqual(ports, ["4410"])
        removed, _ = MODULE.patch_content(patched, install=False)
        self.assertNotIn(MODULE.BEGIN, removed)
        self.assertNotIn("listen 4410", removed)

    def test_missing_frontend_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "4408 and 4409"):
            MODULE.patch_content(SAMPLE.replace("listen 4409", "listen 4420"))

    def test_foreign_status_port_is_not_overwritten(self):
        foreign = SAMPLE.replace(
            "server {\n        listen 80;",
            "server {\n        listen 4410;\n        location / { return 204; }\n    }\n    server {\n        listen 80;",
        )
        with self.assertRaisesRegex(RuntimeError, "Foreign"):
            MODULE.patch_content(foreign)

    def test_legacy_same_origin_locations_are_removed(self):
        legacy = SAMPLE.replace(
            "location / { try_files $uri $uri/ /index.html; }",
            "# K2_STATUS_CACHE_BEGIN\n"
            "        location /k2-status/ { add_header Cache-Control no-store; }\n"
            "        # K2_STATUS_CACHE_END\n"
            "        location / { try_files $uri $uri/ /index.html; }",
        )
        patched, _ = MODULE.patch_content(legacy)
        self.assertNotIn(MODULE.LEGACY_BEGIN, patched)
        self.assertNotIn("location /k2-status/", patched)
        self.assertEqual(patched.count(MODULE.BEGIN), 1)


if __name__ == "__main__":
    unittest.main()
