# K2 Pro Combo Masterpack

Stand: 2026-07-08 20:41:24 Europe/Berlin

Dieses Paket ist der aktuelle Arbeits- und Sicherungsstand fuer den Creality K2 Pro Combo auf `192.168.178.74`.
Es enthaelt keine Passwoerter, Tokens oder SSH-Zugangsdaten.

## Wichtig zuerst

- Live-Zugriff wurde verifiziert: `root`, Host `K2Pro-Chris`, Firmware `1.1.6.3`.
- Installierter Helper: `v5.2.21.59-health-proc-detect`.
- Frischer Live-Snapshot: `live_snapshot_20260708_204124/`.
- Frisches Config/System-Backup: `live_snapshot_20260708_204124/remote_files/k2pro_config_system_20260708_204402.tar.gz`.
- Frischer kompletter Helper-Snapshot: `live_snapshot_20260708_204124/remote_files/helper-script-live_20260708_204124.tar.gz`.
- Live-Health: `OK 65 / WARN 4 / FAIL 0`.

## Struktur

- `docs/` - aktuelle Zusammenfassung, Warnungen, Backup/Restore-Hinweise.
- `scripts/` - Script zum erneuten Erzeugen eines Live-Snapshots.
- `live_snapshot_20260708_204124/` - heute direkt vom Drucker gezogene Reports, Backups und Hashes.
- `helper-source-v5.2.21.59-health-proc-detect/` - die aktuelle Helper-Quelle zum Lesen/Pruefen/Neuinstallieren.
- `reference_previous_context/` - aeltere Uebergabe vom 2026-07-07, nur als Kontext, nicht als aktueller Stand.

## Nicht blind machen

- Kein Core-Klipper/Moonraker-Update ueber Web-Update auf diesem Creality-Stack.
- Kein Firmware-/MCU-/CFS-Flash ohne konkreten Grund.
- Keine direkten CFS-Load/Unload/Extrude-Tests per Makro.
- Kein `SAVE_CONFIG` nur wegen `auto_addr`.
- Nozzle-AI-Kamera nicht dauerhaft erzwingen; sie ist Creality-gesteuert und im Idle oft standby/offline.

## Aktueller Hinweis

Der frische Health-Check hat `WARN 4`, aber `FAIL 0`.
Die wichtigste Warnung ist repairable CFS-Materialdatenbank-Drift. Details stehen in:

`docs/CURRENT_STATE_20260708_204124.md`
