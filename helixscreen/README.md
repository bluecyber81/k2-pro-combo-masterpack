# HelixScreen K2 Pro Combo Overrides

`helixscreen_k2pro_overrides_20260710.tar.gz` ist die Sicherung der getesteten lokalen Anpassungen des separaten Raspberry-Pi-Displays.

Enthalten sind:

- K2-Pro-/CFS-sichere Settings- und Preset-Anpassung
- Querformat-Waechter und systemd-Drop-ins
- gueltige Display-Timerwerte fuer HelixScreen `v0.99.88`
- aktueller HelixScreen-Settings-Stand

Nur auf einer passenden HelixScreen-Installation wiederherstellen. Vorher die vorhandenen Dateien sichern und nachher `systemctl daemon-reload`, `systemctl restart helixscreen.service` sowie den Bericht unter `live_snapshot_20260710_210033/reports/helixscreen_pi_20260710_210033.txt` gegenpruefen.
