# Backup And Restore Notes

## Aktuelle Sicherungen

- Oeffentlich sicherer Live-Report: `live_snapshot_20260718_101800/`
- Oeffentlich sicherer Restore: `backups/k2pro_public_restore_20260718.tar.gz`
- Bereinigte Neuinstallationsquelle: `helper-source-v5.2.21.68-stable-health-count/`
- HelixScreen-Overrides: `helixscreen/helixscreen_k2pro_overrides_20260718.tar.gz`
- K2Dash-Pi-Paket: `k2dash/k2dash-full-go2rtc-pi-final-20260718_092156.tar.gz`
- Separates Home-Assistant-Teilbackup fuer Spoolman wurde am 2026-07-10 erzeugt.

Der Public-Restore enthaelt Druckerkonfiguration, aktuelle CFS-/Materialdaten, relevante Systemdateien und die bereinigte Helper-Quelle. Er enthaelt bewusst keine Moonraker-LMDB, keine Config-Git-Objekte und keine privaten Laufzeitzuordnungen. Die vollstaendigen Roharchive liegen lokal unter `outputs/k2pro_masterpack_20260718_101800/remote_files/`; ihre Hashes stehen in `backups/README.md`.

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
10. HelixScreen und K2Dash erst nach erfolgreichem Drucker-Basistest wiederherstellen.

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
