# Backup And Restore Notes

## Aktuelle Sicherungen

- Voller Live-Snapshot: `live_snapshot_20260712_084930/`
- Config/System: `live_snapshot_20260712_084930/remote_files/k2pro_config_system_20260712_084930.tar.gz`
- Kompletter Helper: `live_snapshot_20260712_084930/remote_files/helper-script-live-v62-20260712_085000.tar.gz`
- Bereinigte Neuinstallationsquelle: `helper-source-v5.2.21.62-cfs-safe-tools/`
- Separates Home-Assistant-Teilbackup fuer Spoolman wurde am 2026-07-10 erzeugt.

Das Config/System-Archiv enthaelt die Druckerkonfiguration, Moonraker-Datenbank, CFS-/Materialdaten und relevante Systemdateien. Der Helper-Snapshot enthaelt den installierten Live-Stand inklusive lokaler Laufzeitkonfiguration.

## Sichere Reihenfolge nach Firmware-Reset

1. Drucker vollstaendig starten und Firmware-/Boardkennung pruefen.
2. Vor jeder Wiederherstellung einen neuen Ist-Stand sichern.
3. Helper nach `/mnt/UDISK/helper-script` zurueckspielen und Rechte pruefen.
4. `helper.sh --preflight` und `helper.sh --status` ausfuehren.
5. Druckerkonfiguration nur bei passender K2-Pro-Firmware wiederherstellen.
6. Klipper/Moonraker neu starten und `helper.sh --health` ausfuehren.
7. CFS nur lesend mit `helper.sh --health-cfs` und `scripts/cfs_db_guard.sh` pruefen.
8. Spoolman-Mapping mit `helper.sh --spoolman-cfs-status` kontrollieren.
9. Kamera, Timelapse, Fluidd und Mainsail einzeln pruefen.

## Helper-Befehle

```sh
cd /mnt/UDISK/helper-script
sh helper.sh --backup
sh helper.sh --preflight
sh helper.sh --health
sh helper.sh --health-cfs
sh helper.sh --spoolman-cfs-status
sh helper.sh --cfs-safe-status
sh helper.sh --cfs-safe-events
sh helper.sh --health-camera
sh helper.sh --health-frontends
```

Die interaktive Helper-Restore-Funktion stellt standardmaessig nur `printer_data/config` wieder her. System- und CFS-Daten aus dem Tarball sind fuer eine kontrollierte manuelle Rettung gedacht.

## Nicht automatisch wiederherstellen

- Keine fremde oder Vanilla-Klipper-/Moonraker-Core-Version.
- Keine MCU-/CFS-Firmware aus einem Backup flashen.
- Keine direkten CFS-Materialbewegungsbefehle zum Testen.
- Keine Nozzle-AI-Kamera dauerhaft erzwingen.
- Keine Spoolman-Datenbank ueberschreiben, bevor das Home-Assistant-Backup und der aktuelle Serverstand geprueft wurden.

## Neuen Snapshot erzeugen

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_live_snapshot_from_windows.ps1 -Password "DEIN_PASSWORT"
```

Passwoerter bleiben ausserhalb des Repositories. Vor einer Veroeffentlichung immer erneut nach Tokens, privaten Schluesseln und Laufzeitdateien suchen.
