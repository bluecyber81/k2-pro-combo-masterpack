# K2 Pro Combo Masterpack

Stand: 2026-07-10 21:05 Europe/Berlin

Aktueller Arbeits-, Diagnose- und Wiederherstellungsstand fuer den Creality K2 Pro Combo. Das Paket enthaelt keine Passwoerter, Tokens, privaten SSH-Schluessel oder Browser-Sitzungen.

## Bestaetigter Live-Stand

- Drucker-Firmware: `1.1.6.3`
- CFS-Firmware: `1.4.2`
- Helper: `v5.2.21.61-maintenance-sync`
- Fluidd: `1.37.2`
- Mainsail: `2.18.2`
- go2rtc: `1.9.14`
- HelixScreen auf dem separaten Raspberry Pi: `v0.99.88`
- Gesamt-Health: `OK 69 / WARN 0 / FAIL 0`
- CFS-Health: `OK 23 / WARN 0 / FAIL 0`
- Kamera-Health: `OK 12 / WARN 0 / FAIL 0`

## Aktuelle Struktur

- `docs/CURRENT_STATE_20260710_210033.md` - kompakter, bestaetigter Ist-Stand.
- `docs/BACKUP_AND_RESTORE.md` - sichere Wiederherstellungsreihenfolge.
- `helper-source-v5.2.21.61-maintenance-sync/` - bereinigte Helper-Quelle ohne Laufzeitdaten.
- `helixscreen/` - getestete Raspberry-Pi-/HelixScreen-Overrides fuer den K2 Pro Combo.
- `live_snapshot_20260710_210033/` - Reports, Helper-Snapshot und Config/System-Backup vom Drucker.
- `scripts/` - erneute Live-Snapshot-Erstellung unter Windows und auf dem Drucker.
- `live_snapshot_20260708_204124/` - vorheriger historischer Stand.
- `reference_previous_context/` - aeltere Uebergabe, nur als Referenz.

## Wichtige Verbesserungen seit dem alten Stand

- CFS-Materialdatenbank und beide benutzerdefinierten Profile sind konsistent.
- Alle vier CFS-Slots sind mit Spoolman verbunden; der aktive Slot stimmt.
- Helper-Menue, Installationsstatus und Git-Backup-Erkennung wurden korrigiert.
- Lokales Config-Git ist sauber und hat den aktuellen Kammer-Temperaturabgleich committed.
- Entware-Paketlisten wurden aktualisiert; keine Pakete sind ausstehend.
- HelixScreen-Timerwerte wurden auf gueltige Werte korrigiert, Landschaftsmodus und CFS-sichere Sensorrolle bleiben updatefest.
- Raspberry Pi, HelixScreen, Moonraker-Zugriff, Kamera und Spoolman wurden vom Pi aus mit HTTP 200 validiert.

## Nicht blind aktualisieren

- Creality-Klipper und -Moonraker sind herstellerspezifische Forks. Kein Vanilla-Core-Update ueber Fluidd/Mainsail erzwingen.
- Keine Firmware-, MCU- oder CFS-Flashs ohne konkretes, fuer K2 Pro bestaetigtes Paket.
- Keine direkten CFS-Load/Unload/Extrude-Tests per Fremdmakro.
- Nozzle-AI-Kamera nicht dauerhaft einschalten; Creality aktiviert sie bedarfsgesteuert.
- Spoolman `0.24.0` existiert upstream, ist aber im verwendeten Home-Assistant-App-Kanal noch nicht als installierbarer Build freigegeben. Installiert und kanalaktuell ist `0.23.1-0`.

Details und Hashes stehen in `docs/CURRENT_STATE_20260710_210033.md` und `SHA256SUMS_PACKAGE.txt`.
