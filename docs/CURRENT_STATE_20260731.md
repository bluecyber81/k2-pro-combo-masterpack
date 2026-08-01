# Creality K2 Pro Combo - Wissensstand v5.2.21.86 vom 2026-07-31

## Geltungsbereich

Dieser Stand gilt ausschliesslich fuer den live geprueften Drucker:

- Modell: Creality K2 Pro Combo
- Modellkennung: `F012`
- Mainboard: `CR0CN200400C10`
- Firmware: `1.1.6.7`
- CFS-Firmware: `1.5.0`
- Hauptkamera: `CCX2F4013`, Firmware `250708`
- Duesen-/Subkamera: `STD-8062V0`, Firmware `0723V2`
- Helper: `v5.2.21.86-status-dedicated`

Zugangsdaten werden in diesem Dokument nicht wiederholt.

## Verifizierter Abschlussstand

- Druckauftrag beendet, Klipper bereit, Heizungsziele `0 C`
- Freier UDISK-Speicher vor dem Restore-Bau: etwa `25.6 GB`
- Vollstaendiger Live-Healthcheck: `110 OK / 0 WARN / 0 FAIL`
- Paketmanifest: `124/124` SHA-256-Eintraege bestanden
- Python-Regressionstests: `73/73` bestanden
- Validator: `49` Shell-Dateien, `25` Python-Dateien und `2` Shelltests
- Abhaengigkeiten: `94 OK / 17 INFO / 0 FAIL`
- Fluidd-, Mainsail-, Frame- und WebRTC-Endpunkte: HTTP `200`
- CFS-Firmware `1.5.0`, vier Live-IDs vorhanden
- CFS-Watcher und Datenbank-Guard laufen
- Kein schwerer RS485-, MCU-, Klipper- oder Moonraker-Fehler

Der abschliessende Abhaengigkeitsaudit meldet `94 OK / 17 INFO / 0 FAIL`.
Die 17 Abhaengigkeitsmeldungen sind bewusst nur informativ. Nicht auf dem
Drucker installiert sind beispielsweise OctoEverywhere und HelixScreen;
HelixScreen gehoert auf den Raspberry Pi. `/usr/bin/wget` ist vorhanden.

## Statusseite ohne Mainsail-Service-Worker-Konflikt

Ein frisches Chrome-Profil zeigte die Statusseite korrekt, waehrend das echte
lang verwendete Chrome-Profil unter `:4409/k2-status/` nur das leere
Mainsail-Grundgeruest darstellte. Damit war der Restfehler eindeutig als
Same-Origin-Service-Worker-Interception nachgewiesen, nicht als Fehler des
Status-HTMLs oder der JSON-Erzeugung.

Die Statusseite laeuft deshalb nun auf einem eigenen Ursprung:

```text
http://192.168.178.74:4410/
```

Der Nginx-Patcher entfernt nur seine eigenen alten v85-Regeln, schuetzt fremde
Listener, legt vor jeder Aenderung ein Backup an, prueft `nginx -t`, laedt
Nginx neu und verlangt danach HTTP 200, `no-store` und gueltiges Status-JSON.
Scheitert diese Livepruefung, wird die vorige Nginx-Datei automatisch
wiederhergestellt. Fluidd 4408 und Mainsail 4409 bleiben unveraendert.

Verifiziert wurden die echte Desktop-Chrome-Sitzung und eine mobile
390-Pixel-Ansicht: Liveinhalt sichtbar, CFS `1.5.0`, keine horizontale
Ueberbreite und keine Seitenfehler. Ein ueberfluessiger Favicon-404 wurde mit
einem eingebetteten leeren Icon beseitigt.

## Behobene falsche Kalibrierzuordnung

Nach einem CFS-Unload zeigt der Live-Pointer `box.filament` wieder auf T1A.
Dieser Pointer ist deshalb kein Beweis dafuer, aus welchem Fach der soeben
kalibrierte Druck kam. Die vorherige Diagnose konnte dadurch einen gueltigen
T1B-Kalibrierlauf faelschlich als T1A anzeigen.

Der Helper liest nun Crealitys autoritative Zuordnung aus dem Kalibrierlog:

```text
T0(T1A)=>T1B
```

Danach werden Slot, Material-ID und Farbe gegen die aktuelle CFS-Inventur
verifiziert. Der beobachtete Lauf ergab:

```text
CALIBRATED_MATERIAL|logical=T1A|slot=T1B|id=090001|brand=eSUN|name=ePLA-HS+ Gray|type=PLA|color=09ea7ae|remaining_percent=100|spoolman=2|verified=1|attribution=creality_log_map+live_inventory
```

`CURRENT_MATERIAL` bleibt als Live-Pointer sichtbar, ist aber nun deutlich mit
`calibration_attribution=0` gekennzeichnet und wird nicht mehr als Quelle der
abgeschlossenen Kalibrierung ausgegeben.

## Gemessene Filamentwerte

Crealitys echter Duesenkamera-Ablauf hat beide Phasen erfolgreich beendet:

- Pressure Advance: `0.056`
- Flow-Ergebnis: `96 %`
- Basis-Flow-Ratio des Profils: `0.98`
- Berechnete Flow-Ratio: `0.98 x 0.96 = 0.9408`

Der Helper gibt deshalb nur fuer das exakt verifizierte PLA-Material aus:

```text
PROFILE_RECOMMENDATION|pressure_advance=0.056|base_flow_ratio=0.98|flow_percentage=96|flow_ratio=0.9408|slot=T1B|id=090001|safe_to_persist=1|reason=verified
```

`safe_to_persist=1` setzt vollstaendige PA- und Flow-Ergebnisse, PLA-Metadaten
und eine exakte Material-/Slot-Uebereinstimmung voraus. Unvollstaendige oder
nicht eindeutig zuordenbare Ergebnisse werden nicht freigegeben.

Das neue Creality-Print-Profil heisst:

```text
eSUN PLA HS+ Gray calibrated @Creality K2 Pro 0.4 nozzle
```

Es ueberschreibt nur PA und Flow Ratio. Das Hersteller-Basisprofil bleibt
unveraendert und kuenftige CFS-Datenbankupdates werden dadurch nicht blockiert.

## Korrekte Duesenkamera-Logik

Die Duesenkamera wird nur fuer Auto PA, Auto Flow und ausgewaehlte
CFS-Abfallpruefungen eingeschaltet. Ihr korrekter Leerlauf ist ausgeschaltet.

Meldungen wie `xioctl error 19` oder `No such device` direkt nach erfolgreicher
Aufnahme koennen beim von Creality angeforderten Abschalten entstehen. Der
Helper klassifiziert sie nur dann als `expected_poweroff_noise`, wenn alle
folgenden Belege zusammen vorhanden sind:

- gueltiges PA- oder Flow-Ergebnis
- erfolgreiche Bildaufnahme
- expliziter Creality-Power-off
- `subCameraAbnormal: 0`
- kein harter AI-/Kameraabbruch

Unpassender Geraeteverlust, AC05xx-Fehler, ein positiver
`subCameraAbnormal`-Wert oder fehlende Ergebnisse bleiben Warnungen. Es werden
keine echten Fehler weggefiltert.

## Behobener Full-Health-Haenger

Der kompakte CFS-Sicherheitsscan konnte zuvor bis zu etwa 48 MB aus G-Code
lesen. Im Full-Health-Menue wirkte das wie ein Haenger.

Der kompakte Lauf ist nun begrenzt auf:

- die 16 neuesten G-Code-Dateien
- maximal 300 kB pro Datei
- maximal 12 Sekunden Laufzeit

Der detaillierte manuelle CFS-Scan behaelt seine groesseren Grenzen. Die
bewusste Begrenzung wird als Information behandelt; echte CFS-Risiken und
Zeitueberschreitungen bleiben Warnungen. Der kompakte Live-Lauf brauchte `9 s`.

## Herstellerstand und Konfiguration

Der nach dem Firmwareupdate gemeldete Baseline-Unterschied wurde untersucht.
Gegenueber den automatischen Backups hatten sich nur die 9x9-Punkte des
gueltigen `[bed_mesh default]` geaendert. `box.cfg`, `motor_control.cfg`,
Geometrie, Extrusionsschutz und alle 13 aktiven Includes bestanden die Pruefung.
Der verifizierte aktuelle Stand wurde deshalb als neue Baseline aufgenommen.

Crealitys Stock-Klipper, Moonraker, Display-, AI-, CFS- und MCU-Komponenten
bleiben autoritativ. Es wurde kein blinder Upstream-Austausch vorgenommen.

## Wiederherstellung

Wichtige Live-Rueckfallkopien:

```text
/mnt/UDISK/printer_data/backups/k2pro_helper/20260731_184802_pre_v86_status_dedicated/helper-script.tar.gz
/mnt/UDISK/printer_data/backups/k2pro_helper/20260731_184802_pre_v86_status_dedicated/nginx.conf
/mnt/UDISK/printer_data/backups/k2pro_helper/helper-script-before-5.2.21.86-status-dedicated_20260731_185209.tar.gz
/mnt/UDISK/printer_data/backups/k2pro_helper/nginx-before-k2-status-20260731_185310-17481.conf
```

Aktueller Wiederherstellungs-Payload auf dem Drucker:

```text
/mnt/UDISK/k2pro_mod_restore_payload_current.tar.gz
/mnt/UDISK/printer_data/backups/k2pro_helper/K2-Pro-Combo-Printer-Restore-v5.2.21.86-final-20260731.tar.gz
SHA-256 d1065f4613db524f5c3f3e25828a4ff7b52061e45562171f9a5695fd93575f87
```

Die vorherigen v84- und fruehen v86-Payloads bleiben als Rueckfallkopien
erhalten.

Lokale Helper-Pakete:

```text
ZIP SHA-256    1caa039e8b32c098856f06765775f6b0df82793b7fb8d65b87a6e86ee6d84d1c
TAR.GZ SHA-256 813d656bd577200f10ffda60fd8572eacc560439b79f99efc83bc53be7f1cd5e
```

## Nicht veraendert

- keine Firmware, MCU-, CFS- oder Kamera-Firmware geflasht
- keine CFS-Motor- oder fremden K2-Plus-Befehle installiert
- keine Bewegung, Heizung oder Kalibrierung blind gestartet
- keine FritzBox- oder Router-Aenderung
- Duesenkamera nicht dauerhaft eingeschaltet

## Ergebnis

Die neuen Erkenntnisse liefern nicht nur mehr Diagnoseausgabe. Sie verhindern
eine konkrete falsche CFS-Slot-Zuordnung, machen PA/Flow-Profilwerte erst nach
echter Materialverifikation freigabefaehig, unterscheiden normalen
Duesenkamera-Power-off von realen Fehlern und beseitigen den beobachteten
Full-Health-Haenger. Zusaetzlich ist die Statusseite vom Mainsail-Service-
Worker entkoppelt. Der Live-Abschluss ist fehlerfrei und rueckrollbar.
