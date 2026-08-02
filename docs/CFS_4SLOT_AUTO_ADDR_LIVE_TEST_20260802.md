# K2 Pro Combo: CFS-4-Slot- und Auto-Addr-Live-Test

Stand: 2026-08-02 Europe/Berlin

## Zielsystem

- Modell: Creality K2 Pro Combo
- Modellkennung: `F012`
- Mainboard: `CR0CN200400C10`
- Drucker-Firmware: `1.1.6.7`
- CFS-Firmware: `1.5.0`
- Helper nach Abschluss: `v5.2.21.91-auto-addr-recovery`

## Ergebnis

Der getestete Hersteller-Vierfarbdruck `4color-3DBench_PLA_31m.gcode` wurde
vollstaendig abgeschlossen. Alle vier CFS-Slots wurden durch die originale
Creality-Steuerung geladen und entladen. Es gab keinen Klipper-Shutdown, keine
CFS-Trennung, keinen Pausezustand und keinen Ruecksprung des Druckfortschritts.

Nach dem Test wurde Helper v91 installiert. Ein spaeter kurz gestarteter Druck
wurde vom Benutzer bewusst abgebrochen; der Drucker wurde danach erneut als
`ready`, `standby` und mit Heizungszielen `0 C` bestaetigt.

## Vier-Slot-Telemetrie

- Datei: `4color-3DBench_PLA_31m.gcode`
- Beginn: `2026-08-02 10:23:07`
- Ende: `2026-08-02 11:06:24`
- Status: `complete`
- Telemetriepunkte: `795`
- CFS verbunden: `795/795`
- `motor_ready=true`: `795/795`
- Pause erkannt: `0`
- Fortschrittsrueckspruenge: `0`
- Slotfolge: `T1B -> T1A -> T1B -> T1C -> T1D`
- CFS-Wechselzaehler am Ende: `0,0,0,0`
- Druckdauer laut Klipper: `2360.16 s`
- Gesamtdauer: `2595.98 s`
- G-Code-Metadatenschaetzung: `2024 s`
- Abweichung gegen Gesamtdauer: `571.98 s` beziehungsweise `28.3 %`
- Maximale Hotendtemperatur: `242.0 C` bei maximalem Ziel `240.0 C`
- Maximale Betttemperatur: `58.1 C` bei maximalem Ziel `50.0 C`

Die Zeitkorrektur wird aus diesem einzelnen Mehrfarbdruck nicht neu angepasst.
Fuer eine belastbare allgemeine Korrektur sind mehrere einfarbige und
mehrfarbige Vergleichsdrucke erforderlich.

## Logauswertung

Im Testfenster wurden `23,574` Klipper-Logzeilen ausgewertet.

- `233` Meldungen `cmd_485_send_data_with_response timeout` entsprechen dem
  bekannten periodischen 10-Sekunden-Polling. Das CFS blieb verbunden.
- `1,575` rohe `Serial_485 #unknown`-Frames wurden vom Creality-Pythonpfad
  verarbeitet. Es folgte kein Kommunikationsabbruch.
- `12` als ERROR protokollierte Binardump-Zeilen (`buf_len`, `buf[...]`) waren
  Diagnoseausgaben erfolgreicher CFS-Kommandos, keine Druckfehler.
- Ein echter, aber nicht fataler `BlockingIOError: [Errno 11] Resource
  temporarily unavailable` entstand beim sehr ausfuehrlichen G-Code-Response-
  Logging waehrend der Druckkopf-/Pressure-Ausgabe. Der Druck lief weiter und
  wurde erfolgreich beendet.
- Keine Meldung zu MCU-Shutdown, verlorener Kommunikation, unbekanntem
  Funktionscode, fehlender Adresstabelle oder `motor_not_ready`.

Der einzelne G-Code-Response-Backpressure-Fehler bleibt ein kleiner
Hersteller-Fork-Befund. Ein Eingriff in den Klipper-Core ist aufgrund des
erfolgreichen Drucks nicht gerechtfertigt.

## Auto-Addr-Recovery

Der urspruengliche Live-Stand von `auto_addr_wrapper.py` hatte SHA-256:

`d413f7d641085cf7f8506558abbb973ded5c84e46bf2e151169ef12666a16b01`

Der installierte, getestete Recovery-Stand hat SHA-256:

`304e49f651081ff9679bfbd355f4b656969c5d39a96498c4f30915248c09fa16`

Der Patch behandelt unbekannte ACK-Antworten defensiv und sucht beim
Wiederfinden eines CFS-Geraets in beiden bekannten Herstellertabellen. Das
periodische 10-Sekunden-CFS-Polling bleibt unveraendert. Vor der Installation
wurde ein Modulbackup angelegt unter:

`/mnt/UDISK/printer_data/backups/k2pro_helper/auto_addr_recovery/20260802_101313`

Vier spezielle Auto-Addr-Regressionstests wurden bestanden.

## Motorcontroller-Diagnose

Der F012-Updater meldet fuer `/dev/ttyS2` und `/dev/ttyS3` jeweils einen
Handshake-Rueckgabewert `2`, entdeckt danach aber X/Y-Controller und RFID
erfolgreich. Gleichzeitig meldete Klipper waehrend des gesamten Vier-Slot-
Tests `motor_ready=true`.

Helper v91 bewertet deshalb exakt diese Versionsabfrage-Luecke nur als Warnung,
wenn der Runtime-Status bereit und das CFS verbunden ist. Reale Updaterfehler,
fehlende Runtime-Bereitschaft oder ein getrenntes CFS bleiben Fehler.

Nach Installation ergab die CFS-Gesundheitspruefung:

- Gesamt: `30 OK / 1 WARN / 0 FAIL`
- CFS Safe Tools: `6 OK / 0 WARN / 0 FAIL`
- Controller: `2`
- Motor-App: `081`
- Updater-Fehler: `0`
- bekannte Handshake-Luecken: `2`
- CFS-Datenbank: `53` Profile, inklusive lokaler Profile `90001` und `90002`

## Helper v91

- Volltest: `94` Python-Regressionstests bestanden
- Shell-Pruefungen: `51`
- Python-Pruefungen: `32`
- Shell-Testgruppen: `3`
- ShellCheck, shfmt, Ruff, Python-Compile und JSON-Validierung bestanden
- Paketmanifest: `136` Dateien
- Live-Installer: alle Dateien verifiziert, Tests bestanden
- Installerbackup:
  `/mnt/UDISK/printer_data/backups/k2pro_helper/helper-script-before-5.2.21.91-auto-addr-recovery_20260802_113848.tar.gz`

## Belege

- `K2-Pro-CFS-4Slot-Live-Telemetry-20260802.jsonl`
- `K2-Pro-CFS-4Slot-Evidence-20260802.tar.gz`
- `K2-Pro-CFS-4Slot-Analysis-20260802.json`
- `K2-Pro-CFS-4Slot-Final-Camera-20260802.jpg`
- `Creality-Helper-Script-K2-Pro-Combo-v5.2.21.91-auto-addr-recovery-reviewed-final.zip`

SHA-256 des Belegarchivs:

`b2563904c6f96ca006fb4b1b56ba8eca0c9305901fdd8266504d0b88ffab2d16`

SHA-256 des Helper-ZIP:

`1d70c9290a717224bfc602aa62aa5273671c119f566e5f35863e66d17bece49e`

## Schlussfolgerung

CFS 1.5.0, alle vier Slots, Motorcontroller-Runtime und die installierte
Auto-Addr-Wiederherstellung arbeiteten im realen Test zusammen. Die
verbleibenden Meldungen sind aktuell Diagnose- oder Versionsabfrage-Luecken,
keine nachgewiesenen Bewegungs- oder CFS-Ausfaelle. Weitere direkte
RS485-Motorbefehle oder ein Core-Update sind aus diesem Befund nicht sinnvoll.
