# Backup And Restore Notes

## Was im frischen Backup steckt

Das frische Config/System-Backup wurde durch den installierten Helper erstellt:

`live_snapshot_20260708_204124/remote_files/k2pro_config_system_20260708_204402.tar.gz`

Der Helper-Backup-Scope umfasst:

- `/mnt/UDISK/printer_data/config`
- `/mnt/UDISK/printer_data/database`
- `/mnt/UDISK/creality/userdata/box`
- Helper-Installmarker `.installed`
- relevante Systemdateien wie `rc.local`, `nginx.conf`, Moonraker init/rc.d Dateien
- `df -h` und `uname` als Kontext

Der komplette Helper-Snapshot liegt hier:

`live_snapshot_20260708_204124/remote_files/helper-script-live_20260708_204124.tar.gz`

## Restore-Grundsatz

Restore nur machen, wenn es einen konkreten Grund gibt.
Vor jedem Restore zuerst ein neues Pre-Restore-Backup erzeugen.

Der installierte Helper hat eine interaktive Restore-Funktion:

```sh
cd /mnt/UDISK/helper-script
sh helper.sh --backup
sh helper.sh --restore
```

Der Restore-Pfad stellt standardmaessig nur `/mnt/UDISK/printer_data/config` wieder her.
Systemdateien und CFS-Materialdatenbankdaten im Tarball sind fuer manuelle Rettung gedacht.

## Frischen Snapshot spaeter erneut erzeugen

Vom Windows-Rechner aus kann das Script in `scripts/` erneut genutzt werden.
Passwort nicht in Dateien speichern.

Beispiel:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_live_snapshot_from_windows.ps1 -Password "DEIN_PASSWORT"
```

Das erzeugt auf dem Drucker wieder einen Ordner unter:

`/mnt/UDISK/printer_data/backups/codex/`

Danach kann der Ordner per `pscp -r` lokal heruntergeladen werden.

## Aktuelle CFS-Warnung

Der Live-Health-Check meldete repairable CFS-Materialdatenbank-Drift.
Nicht blind reparieren, wenn gerade ein Druck laeuft oder der Drucker aktiv arbeitet.

Bei ruhigem Idle-Zustand waere der vorgesehene Helper-Befehl:

```sh
cd /mnt/UDISK/helper-script
sh helper.sh --backup
sh helper.sh --cfs-db-repair
sh helper.sh --health-cfs
sh helper.sh --health
```
