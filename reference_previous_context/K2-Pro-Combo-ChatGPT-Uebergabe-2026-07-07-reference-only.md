# Creality K2 Pro Combo - ChatGPT Uebergabe

Stand: 2026-07-07

Diese Datei ist eine sichere Zusammenfassung fuer ChatGPT oder einen neuen Support-Thread. Zugangsdaten, Tokens und Passwoerter sind absichtlich nicht enthalten.

## Drucker

- Modell: Creality K2 Pro Combo
- Live-Modellkennung: `F012`
- Board: `CR0CN200400C10`
- Bauraum: `300x300x300`
- Drucker-IP im lokalen Netz: `192.168.178.74`
- Firmware live: `1.1.6.3`
- CFS/T1 Firmware live: `1.4.2`
- Druckerzustand beim letzten Check: idle/standby, keine akuten Fehler

## Installierter Helper

- Installierter Helper: `v5.2.21.50-reviewed`
- Lokales Paket:
  `C:\Users\bluec\Documents\Codex\2026-06-26\pr\outputs\Creality-Helper-Script-K2-Pro-Combo-v5.2.21.50-reviewed-nozzle-usb-diagnose.zip`
- SHA256:
  `EA7C9238D57A88609839FD7044D1FCE5A31B250CA71A1B34E7909E5D7B498DED`
- Paket auf Drucker:
  `/mnt/UDISK/Creality-Helper-Script-K2-Pro-Combo-v5.2.21.50-reviewed-nozzle-usb-diagnose.zip`
- Backup vor Installation:
  `/mnt/UDISK/printer_data/backups/k2pro_helper/helper-script-before-v5.2.21.50-20260707_181253.tar.gz`

## Lokale Reports

Alle wichtigen Reports liegen lokal hier:

`C:\Users\bluec\Documents\Codex\2026-06-26\pr\outputs\k2pro_v5.2.21.50_reports_20260707_1815`

Enthalten:

- `health_all_v50.txt`
- `health_camera_v50.txt`
- `health_frontends_v50.txt`
- `health_cfs_v50.txt`
- `health_firmware_v50.txt`
- `dependency_audit_v50.txt`
- `menu_audit_v50.txt`
- `nozzle_diag_v50.txt`
- `k2pro_preflight_report.txt`
- `deep_file_audit_20260707_181444.txt`

## Letzte Pruefergebnisse

- Full Health: `OK 67 / WARN 0 / FAIL 0`
- Deep File Audit: `OK 180 / INFO 8 / WARN 0 / FAIL 0`
- CFS Health: `OK 23 / WARN 0 / FAIL 0`
- Dependency Audit: `OK 63 / WARN_OR_INFO 12 / FAIL 0`
- Firmware/System Health: `OK 2 / WARN 0 / FAIL 0`
- Kamera Health: `OK 12 / WARN 0 / FAIL 0`
- Frontend Health: `OK 7 / WARN 0 / FAIL 0`

## Aktive/installierte Module

Als installiert und erkannt gemeldet:

- Moonraker Extensions
- Fluidd
- Mainsail
- Camera Support mit go2rtc/WebRTC
- Fans Control Macros
- Useful Macros
- Improved Shapers
- KAMP-K2 Adaptive Mesh
- Creality Timelapse Recover
- Spoolman CFS Sync
- Entware
- CFS Material DB Guard
- Git Backup local

Nicht installiert/absichtlich aus:

- OctoEverywhere
- Mobileraker Helper auf dem Drucker
- Moonraker Timelapse Plugin
- M600 manual change
- HelixScreen auf dem Drucker
- Z-Offset-Makros

## Wichtige Entscheidungen und Regeln

- Creality Klipper/Moonraker-Core nicht blind ueber Web-Update ersetzen.
- Firmware, MCU und CFS nicht blind flashen.
- CFS nicht mit direkten `BOX_LOAD_MATERIAL` oder `BOX_EXTRUDE_MATERIAL` Tests steuern.
- CFS/Materialwechsel ueber Display, Creality/CFS Workflow, Slicer-Toolchange und offizielle BOX/CFS-Ablaeufe verwenden.
- `M600` nur fuer Drucker ohne CFS/Box, nicht fuer den K2 Pro Combo mit CFS.
- `SAVE_CONFIG` nicht nur wegen `auto_addr` ausfuehren. `auto_addr` als einziges pending item ist bei Creality/CFS erwartbar.
- Nozzle-AI-Kamera nicht dauerhaft einschalten. Sie wird von Creality bedarfsgesteuert fuer AI/Flow/First-Layer genutzt.
- HelixScreen bleibt Test/Experiment, solange Stock-Display, CFS, AI und Kamera funktionieren.

## Kamera

Hauptkamera:

- `camera_main` online
- go2rtc laeuft direkt mit `#format=creality`
- `k2rtc.py` ist nicht mehr als Bridge-Prozess erforderlich
- Mainsail/Fluidd Kamera funktioniert ueber go2rtc
- WebRTC/Frame URLs wurden erfolgreich getestet

Nozzle-AI-Kamera:

- Im Idle/Standby kann `camera_sub` offline sein.
- Das ist nicht automatisch ein Fehler.
- Creality schaltet die Nozzle-AI-Kamera offenbar nur bei Bedarf ein, z.B. AI-Erkennung, Flow, First Layer.
- Neuer Helper-Befehl:
  `helper.sh --nozzle-camera-diagnose`
- Diagnose prueft read-only:
  - `ubus` Kamera-Status
  - GPIO/Node Status
  - `/dev/video*`
  - `/dev/v4l/by-id`
  - `/etc/hotplug.d/usb/60-v4l`
  - `udevadm`
  - UVC/BIND/nozzle/camera Logs

Letzter Diagnosebefund:

- `gpio=1`
- `node=missing`
- `video2=missing`
- `hotplug=present`
- `udevadm=present`
- `recent_usb_log_hits=7`

Interpretation:

- Im Leerlauf ist das akzeptabel.
- Nur wenn AI/Flow/First-Layer wirklich fehlschlaegt, sollte man gezielt weiter pruefen oder recovery testen.

## Mainsail / Fluidd / G-Code Preview

- Fluidd: `v1.37.2`
- Mainsail: `v2.18.2`
- Moonraker Webcam Entry fuer Mainsail ist kompatibel:
  - `enabled=True`
  - `service=webrtc-go2rtc`
  - `target_fps=20`
  - `target_fps_idle=20`
  - `aspect_ratio=16:9`
- Mainsail Dashboard:
  - Webcam Panel sichtbar
  - Spoolman Panel sichtbar
- G-Code Metascan/Preview funktioniert:
  - Beispiel: `1familie_wendt_namensschild.st.gcode`
  - Thumbnails gefunden: `3`
- `queue_gcode_uploads` ist aktiviert.
- Object Processing ist aktiviert.

## Timelapse

- Creality Timelapse Recover ist installiert und aktiv.
- Ziel: Crealitys eigene Timelapse-/Delay-Image-Pfade reparieren, wenn `main_output.h264` vorhanden ist, aber MP4/JSON nicht sauber erzeugt werden.
- Moonraker Timelapse Plugin bleibt optional und ist nicht Standard, weil Creality Timelapse Recover fuer diesen Drucker bevorzugt ist.
- `/usr/bin/wget` ist inzwischen vorhanden.
- `ffmpeg` ist vorhanden.

## CFS / Materialdatenbank

Letzter CFS Status:

- `BOX_STATE=connect`
- `BOX_ENABLE=1`
- `BOX_AUTO_REFILL=1`
- `BOX_FILAMENT_USEUP=1`
- `T1_STATE=connect`
- `T1_VERSION=1.4.2`
- `MOTOR_READY=True`
- `SAVE_CONFIG_PENDING=True`
- `SAVE_CONFIG_PENDING_ITEMS=auto_addr`
- `AUTO_ADDR_ONLY_PENDING=True`

Live Slots:

- `T1_MATERIAL=101001,090001,000002,090002`
- `T1_REMAIN=100,100,100,100`

CFS Sicherheit:

- Keine riskanten CFS-Befehle in Custom Configs.
- Keine riskanten CFS-Befehle in gescannten G-Code Dateien.
- Keine aktuellen schweren CFS key60/direct macro Fehler.
- RS485 Timeout/Noise im akzeptablen Bereich.

Materialdatenbank:

- `material_database.json` valide
- `material_box_info.json` valide
- `material_modify_info.json` valide
- `tn_data.json` valide
- `usrMaterial/userMaterial.json` valide
- `material_option.json` valide
- Live IDs matchen Datenbank
- Custom Profile vorhanden:
  - `90001` = `eSUN/ePLA-HS+ Gray`
  - `90002` = `Sovol/PLA Steel Blue`
- CFS DB Guard ist installiert und meldet: keine Reparatur noetig.

## Spoolman

- Spoolman CFS Sync ist installiert.
- Worker ist vorhanden und ausfuehrbar.
- Slot Map ist vorhanden.
- Service laeuft.
- Moonraker Spoolman Verbindung ist gesund.

## Entware / Tools

Entware ist installiert und erkannt.

Wichtige Tools vorhanden:

- `wget`
- `curl`
- `python3`
- `rsync`
- `git`
- `ffmpeg`
- `jq`
- `sqlite3`
- `unzip`
- `tar`
- `gzip`
- `xz`
- `base64`
- `timeout`
- `udevadm`
- `v4l2-ctl`
- `opkg`
- `sftp-server`

## KAMP

- KAMP-K2 Adaptive Mesh ist installiert und erkannt.
- KAMP wurde auf diesem Drucker getestet.
- Empfehlung: installiert lassen, aber Start-/End-Makros und CFS nicht blind ueberschreiben.

## Bekannte harmlose Meldungen

- HelixPrint optional-plugin probe im Moonraker Log ist harmlos.
- Nozzle-AI-Kamera offline im Leerlauf ist INFO, kein Fehler.
- `SAVE_CONFIG pending only auto_addr` ist erwartbare Creality/CFS-Situation.
- Creality vendor git/update warnings bei Moonraker/Klipper Core sind kein Grund fuer ein blindes Update.

## Was aktuell nicht zu tun ist

- Kein blindes Klipper/Moonraker-Core-Update.
- Kein CFS/MCU/Firmware-Flash ohne konkrete Version, Quelle, Risikoanalyse und Backup.
- Keine direkten CFS Extrude/Load Tests.
- Kein M600 mit CFS.
- Keine Z-Offset-Makros ohne Expert-Test.
- Nozzle-AI-Kamera nicht dauerhaft erzwingen.
- HelixScreen nicht auf dem Drucker installieren, solange Stock-Display/CFS/AI funktionieren.

## Wenn spaeter erneut geprueft werden soll

Sinnvolle read-only Befehle:

```sh
/mnt/UDISK/helper-script/helper.sh --version
/mnt/UDISK/helper-script/helper.sh --status
/mnt/UDISK/helper-script/helper.sh --health
/mnt/UDISK/helper-script/helper.sh --health-camera
/mnt/UDISK/helper-script/helper.sh --health-cfs
/mnt/UDISK/helper-script/helper.sh --health-frontends
/mnt/UDISK/helper-script/helper.sh --health-firmware
/mnt/UDISK/helper-script/helper.sh --dependency-audit
/mnt/UDISK/helper-script/helper.sh --deep-file-audit
/mnt/UDISK/helper-script/helper.sh --menu-audit
/mnt/UDISK/helper-script/helper.sh --nozzle-camera-diagnose
```

## Kurze Frage fuer ChatGPT

Wenn du ChatGPT neu fragen willst, kannst du das hier einfuegen:

> Ich habe einen Creality K2 Pro Combo mit Firmware 1.1.6.3 und CFS 1.4.2. Ein angepasster K2-Pro-Combo Helper v5.2.21.50 ist installiert. Letzte Healthchecks waren OK 67 WARN 0 FAIL 0, Deep File Audit OK 180 INFO 8 WARN 0 FAIL 0. Fluidd, Mainsail, go2rtc Kamera, CFS, Spoolman Sync, Timelapse Recover, KAMP-K2, Entware und CFS DB Guard sind installiert. Nozzle-AI-Kamera ist im Idle offline/standby und soll nicht dauerhaft erzwungen werden. Bitte bewerte Verbesserungen nur K2-Pro-Combo-spezifisch, ohne blind Klipper/Moonraker-Core, Firmware, CFS oder MCU zu flashen, und beachte, dass direkte BOX_LOAD_MATERIAL/BOX_EXTRUDE_MATERIAL Tests vermieden werden sollen.

