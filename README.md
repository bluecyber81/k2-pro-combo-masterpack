# K2 Pro Combo Masterpack

Stand: 2026-08-01 Europe/Berlin

Aktueller Arbeits-, Diagnose- und Wiederherstellungsstand fuer den Creality
K2 Pro Combo. Das oeffentliche Repository enthaelt keine Passwoerter, Tokens,
privaten SSH-Schluessel, Browser-Sitzungen oder unbereinigten Laufzeitdaten.

## Bestaetigter Live-Stand

- Drucker: Creality K2 Pro Combo, Modell `F012`, Mainboard `CR0CN200400C10`
- Drucker-Firmware: `1.1.6.7`
- CFS-Firmware: `1.5.0`
- Helper: `v5.2.21.86-status-dedicated`
- Fluidd: `1.37.3`
- Mainsail: `2.18.2`
- go2rtc: `1.9.14`
- Spoolman: `0.24.0` ueber Home Assistant
- K2Dash: Upstream-Commit `5e960411b8b35a4d3b8ebc17f76b943929f59d20`
- HelixScreen: Stable `0.99.106` (`6f7f5bddb`) mit offizieller
  K2-Kamera-Erkennung; lokaler Diagnose-Socket und Rueckfall sind dokumentiert
- CFS-Datenbank: `1785291996`, 51 offizielle und 2 lokale Profile
- Gesamt-Health: `110 OK / 0 WARN / 0 FAIL`
- Helper-Regressionstests: `73/73` bestanden

## Aktuelle Struktur

- `docs/CURRENT_STATE_20260731.md` - verifizierter Drucker-, CFS-, Kamera- und Helper-Stand.
- `docs/UPDATE_AUDIT_20260731.md` - Firmware- und Upstream-Bewertung.
- `docs/UPDATE_AUDIT_20260801.md` - erneute Live- und Upstream-Pruefung.
- `docs/HELIXSCREEN_PI_UPDATE_20260801.md` - Stable-0.99.106-Installation,
  Kamera-Nachweis und Rueckfallweg.
- `docs/BACKUP_AND_RESTORE.md` - kontrollierte Wiederherstellungsreihenfolge.
- `helper-source-v5.2.21.86-status-dedicated/` - lesbare Helper-Quelle ohne generierte Python-Caches.
- `releases/` - unveraenderte, lokal validierte Helper-Installationsarchive.
- `backups/k2pro_public_restore_20260731.tar.gz` - oeffentlich sicherer Restore ohne Geheimnisse und Git-Interna.
- `helixscreen/` - getestete Raspberry-Pi-/HelixScreen-Overrides,
  Buildkorrektur, Hashes und Rueckfallhinweise.
- `k2dash/` - getestetes Pi-Paket, Rollback-Dateien und Quell-Patch.
- `live_snapshot_*` - historische, oeffentlich sichere Diagnose-Snapshots.
- `scripts/` - Werkzeuge fuer erneute Snapshots und kontrollierte Veroeffentlichung.
- `scripts/update_masterpack_manifest.ps1` - erzeugt Manifest und SHA-256-
  Liste reproduzierbar neu und schliesst Git-Interna automatisch aus.

## Wichtige Verbesserungen

- Der Helper ordnet Crealitys PA-/Flow-Kalibrierung ueber das autoritative
  Kalibrierlog dem richtigen CFS-Slot und Material zu.
- Profilwerte werden nur bei vollstaendiger, eindeutiger Materialzuordnung zur
  Uebernahme freigegeben.
- Der Duesenkamera-Guard unterscheidet Crealitys erwartetes Abschalten nach der
  Aufnahme von echten Kamera- und AI-Fehlern.
- Der CFS-Datenbank-Guard bewahrt offizielle Updates und lokale Profile, ohne
  eine neuere Herstellerdatenbank mit einer alten Kopie zu ueberschreiben.
- CFS Safe Tools protokolliert Status, Ereignisse und Wechselstatistik passiv;
  es sendet keine CFS-Motor-, RS485- oder Fremd-G-Codes.
- KAMP, Klipper Garbage Collection, G-Code-Vorpruefung, Zeitabschaetzung,
  Timelapse, Fluidd, Mainsail, go2rtc und Spoolman-Integration sind im Healthcheck enthalten.
- Die eigene Statusseite laeuft auf Port `4410`, getrennt vom
  Mainsail-Service-Worker.

## Wiederherstellung

Das GitHub-Archiv ist ein praktisch nutzbarer, auf Geheimnisse gepruefter
Public-Restore. Sein SHA-256 lautet:

```text
12298df7202500128bf9f373107d4d2a6e2b0654ba9af92f9659131f595cdb78
```

Die vollstaendigen Roharchive mit Moonraker-LMDB, Config-Git,
Laufzeitzuordnungen und lokaler Historie bleiben bewusst ausserhalb des
oeffentlichen Git-Verlaufs. Sie liegen im lokalen `outputs/`-Bestand und sind
der vollstaendigere Notfallback.

## Nicht blind aktualisieren

- Creality-Klipper und -Moonraker sind herstellerspezifische Forks; kein
  Vanilla-Core-Update ueber Fluidd oder Mainsail erzwingen.
- Keine Firmware-, MCU-, Kamera- oder CFS-Images ohne exakte F012-/Board-
  Zuordnung flashen.
- Keine fremden K2-Plus-CFS-Motorbefehle oder `tool.cfg` uebernehmen.
- Die Duesenkamera nicht dauerhaft einschalten; Creality aktiviert sie fuer
  PA, Flow und ausgewaehlte AI-Pruefungen bedarfsgesteuert.

Details, Hashes und Restore-Grenzen stehen in
`docs/CURRENT_STATE_20260731.md`, `backups/README.md` und
`SHA256SUMS_PACKAGE.txt`.
