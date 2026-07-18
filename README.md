# K2 Pro Combo Masterpack

Stand: 2026-07-18 10:20 Europe/Berlin

Aktueller Arbeits-, Diagnose- und Wiederherstellungsstand fuer den Creality K2 Pro Combo. Das Paket enthaelt keine Passwoerter, Tokens, privaten SSH-Schluessel oder Browser-Sitzungen.

## Bestaetigter Live-Stand

- Drucker-Firmware: `1.1.6.3`
- CFS-Firmware: `1.4.2`
- Helper: `v5.2.21.68-stable-health-count`
- Fluidd: `1.37.2`
- Mainsail: `2.18.2`
- go2rtc: `1.9.14`
- HelixScreen auf dem separaten Raspberry Pi: `v0.99.94`
- K2Dash auf dem Raspberry Pi: permanenter Full-Control-Build auf Port `8090`, Kamera ueber go2rtc
- Raspberry-Pi-Pakete: aktuell, `0` ausstehend
- Gesamt-Health: `OK 83 / WARN 0 / FAIL 0`
- CFS-Health: `OK 28 / WARN 0 / FAIL 0`
- Kamera-Health: `OK 14 / WARN 0 / FAIL 0`
- CFS-Datenbank: `1784085280`, 50 offizielle und 2 lokale Profile

## Aktuelle Struktur

- `docs/CURRENT_STATE_20260718_101800.md` - kompakter, bestaetigter Ist-Stand.
- `docs/HELIXSCREEN_PI_UPDATE_20260718.md` - verifizierter Pi-/HelixScreen-/K2Dash-Stand.
- `docs/BACKUP_AND_RESTORE.md` - sichere Wiederherstellungsreihenfolge.
- `helper-source-v5.2.21.68-stable-health-count/` - bereinigte Helper-Quelle ohne Laufzeitdaten.
- `helixscreen/` - getestete Raspberry-Pi-/HelixScreen-Overrides fuer den K2 Pro Combo.
- `k2dash/` - getestetes Pi-Paket, Rollback-Dateien und Quell-Patch gegen Upstream `b7dc27d`.
- `backups/k2pro_public_restore_20260718.tar.gz` - oeffentlich sichere Wiederherstellung ohne Moonraker-Datenbank und Git-Interna.
- `live_snapshot_20260718_101800/` - aktueller oeffentlich sicherer Report-Snapshot.
- `live_snapshot_20260712_084930/` - vorheriger historischer Stand.
- `live_snapshot_20260710_210033/` - vorheriger historischer Stand.
- `scripts/` - erneute Live-Snapshot-Erstellung unter Windows und auf dem Drucker.
- `live_snapshot_20260708_204124/` - vorheriger historischer Stand.
- `reference_previous_context/` - aeltere Uebergabe, nur als Referenz.

## Wichtige Verbesserungen seit dem alten Stand

- CFS-Materialdatenbank und beide benutzerdefinierten Profile sind konsistent.
- Der CFS-DB-Guard erkennt Herstellerupdates per Fingerprint, bewahrt offizielle Profile und bricht bei lokalen Kollisionen ohne Schreibzugriff ab.
- CFS Safe Tools laeuft als passiver Dienst fuer Status, Ereignisse und Werkzeugwechselstatistik; es sendet keine G-Codes oder Busbefehle.
- Alle vier CFS-Slots sind mit Spoolman verbunden; der aktive Slot stimmt.
- Helper-Menue, Installationsstatus und Git-Backup-Erkennung wurden korrigiert.
- Klipper Garbage Collection, bootfeste Factory-G-Code-Hybridzeiten und Moonraker-Webcam-Test-Kompatibilitaet sind installiert und geprueft.
- Lokales Config-Git ist sauber und hat den aktuellen Kammer-Temperaturabgleich committed.
- Entware-Paketlisten wurden aktualisiert; keine Pakete sind ausstehend.
- HelixScreen-Timerwerte wurden auf gueltige Werte korrigiert, Landschaftsmodus und CFS-sichere Sensorrolle bleiben updatefest.
- HelixScreen wurde auf `v0.99.94` aktualisiert; Querformat, CFS-sichere Sensorrolle und lokale Systemd-Overrides bleiben updatefest.
- Alle 48 angebotenen stabilen Debian-Paketupdates des Display-Pi wurden ohne Paketentfernung installiert.
- Raspberry Pi, HelixScreen, Moonraker-Zugriff, Kamera und Spoolman wurden vom Pi aus mit HTTP 200 validiert.
- K2Dash laeuft dauerhaft mit Druckersteuerung. Der fragile direkte Creality-WebRTC-Signalisierungsweg wurde durch den bereits bewaehrten go2rtc-Stream ersetzt; Dashboard und Kameraframe liefern HTTP 200.

## Backup-Ebenen

- Das GitHub-Archiv enthaelt einen praktisch wiederherstellbaren, auf Geheimnisse geprueften Public-Restore-Stand.
- Die vollstaendigen Roharchive mit Moonraker-LMDB, Config-Git, Laufzeitstatus und lokalen Zuordnungen liegen lokal unter `outputs/k2pro_masterpack_20260718_101800/remote_files/` und bleiben bewusst ausserhalb des oeffentlichen Git-Verlaufs.
- Hashes und genaue Restore-Grenzen stehen in `backups/README.md`.

## Nicht blind aktualisieren

- Creality-Klipper und -Moonraker sind herstellerspezifische Forks. Kein Vanilla-Core-Update ueber Fluidd/Mainsail erzwingen.
- Keine Firmware-, MCU- oder CFS-Flashs ohne konkretes, fuer K2 Pro bestaetigtes Paket.
- Keine direkten CFS-Load/Unload/Extrude-Tests per Fremdmakro.
- Nozzle-AI-Kamera nicht dauerhaft einschalten; Creality aktiviert sie bedarfsgesteuert.
- Spoolman `0.24.0` existiert upstream, ist aber im verwendeten Home-Assistant-App-Kanal noch nicht als installierbarer Build freigegeben. Installiert und kanalaktuell ist `0.23.1-0`.

Details und Hashes stehen in `docs/CURRENT_STATE_20260718_101800.md` und `SHA256SUMS_PACKAGE.txt`.
