# HelixScreen K2 Pro Combo Overrides

`helixscreen_k2pro_overrides_20260712.tar.gz` ist die Sicherung der getesteten lokalen Anpassungen des separaten Raspberry-Pi-Displays.

Enthalten sind:

- K2-Pro-/CFS-sichere Settings- und Preset-Anpassung
- `settings.json` als Symlink und dessen echtes Ziel unter `printer_data`
- Querformat-Waechter und systemd-Drop-ins
- gueltige Display-Timerwerte fuer HelixScreen `v0.99.89`
- updatefeste Bereinigung unnoetiger `/dev/tty1`-/`vtconsole`-Fehlermeldungen aus dem Upstream-Launcher
- aktueller HelixScreen-Settings-Stand

Nur auf einer passenden HelixScreen-Installation wiederherstellen. Zuerst HelixScreen `v0.99.89` installieren, dann die vorhandenen Dateien sichern und das Archiv ab `/` entpacken. Anschliessend `systemctl daemon-reload`, `systemctl restart helixscreen.service` und `systemctl --failed` ausfuehren. Der getestete Sollzustand steht in `docs/HELIXSCREEN_PI_UPDATE_20260712.md`.
