# K2 Pro Combo: Aktualitaets- und Entwicklungscheck

Stand: 2026-08-01, Druckerpruefung vom 2026-07-31 plus Pi-Displaytest

## Ergebnis

Der Drucker und der zugehoerige Raspberry Pi sind im geprueften Zustand stabil. Es wurde kein Firmware-, MCU-, Kamera- oder CFS-Flash ausgefuehrt. Fuer den K2 Pro ist derzeit kein neueres offizielles Firmwarepaket als 1.1.6.7 veroeffentlicht.

## Live-Stand

- Drucker: Creality K2 Pro, Hardware CR0CN200400C10 / F012
- Drucker-Firmware: 1.1.6.7
- CFS: 1.5.0, verbunden und betriebsbereit
- Helper: v5.2.21.86-status-dedicated
- Mainsail: 2.18.2
- Fluidd: 1.37.3
- go2rtc: 1.9.14
- HelixScreen: Pi-Entwicklungsstand `0.99.105-c3d8be0`, Stable-Rueckfall vorhanden
- K2Dash: aktueller Upstream-Commit 5e960411b8b35a4d3b8ebc17f76b943929f59d20
- Spoolman: 0.24.0 ueber Home Assistant, Dienst gesund
- CFS-Filamentdatenbank: Version 1785291996, 50 offizielle und 2 benutzerdefinierte Profile

## Verifikation

- Gesamtheitspruefung: 110 OK, 0 WARN, 0 FAIL
- Abhaengigkeiten: 94 OK, 17 INFO, 0 FAIL
- Helper-Tests: 73 von 73 bestanden
- ShellCheck, shfmt, Ruff, Python- und JSON-Pruefungen bestanden
- CFS-Pruefung: 28 OK, 0 WARN, 0 FAIL
- Firmware-/Guard-Pruefung: 37 OK, 4 INFO, 0 WARN, 0 FAIL
- Frontend-Pruefung: 7 OK, 0 WARN, 0 FAIL
- Hauptkamera liefert aktuell HTTP 200; die Duesenkamera ist im Leerlauf erwartungsgemaess im bedarfsgesteuerten Standby
- Freier Speicher: Drucker-UDISK rund 25 GB; Raspberry Pi rund 100 GB
- Raspberry Pi: keine fehlgeschlagenen Dienste, keine Paketupdates offen, keine Drosselung

## Aktuelle Upstream-Bewertung

### Direkt einsetzbar

Der installierte stabile Stand von Mainsail, Fluidd, go2rtc, HelixScreen und KAMP-K2 ist aktuell. KAMP verwendet bereits den aktuellen 5-mm-Mesh-Rand und enthaelt den Fix gegen Duesenschleifen beim Filamentwechsel.

### Beobachten

- Spoolman 0.26.0 ist neu und bringt eine schnellere, mobilfreundliche Oberflaeche sowie mehrere Verwaltungs-, Leistungs- und Backup-Verbesserungen. Das Home-Assistant-Add-on bietet auf diesem System aber weiterhin 0.24.0 als neuesten Stand an. Kein erzwungenes Container-Update ausserhalb des Supervisors.
- HelixScreen `main` wurde auf dem getrennten Display-Pi bewusst bei Commit
  `c3d8be0` getestet und installiert. Kamera, CFS, Temperaturen, Querformat und
  lokale Screenshot-Steuerung sind verifiziert. Fuer eine normale Installation
  bleibt Stable 0.99.105 die Empfehlung; der Entwicklungsstand ist nur mit dem
  dokumentierten Rueckfallpfad sinnvoll.
- Upstream-`main` stand nach Abschluss bereits auf `85d5508ba`. Diese neueren,
  noch nicht als Release markierten Commits wurden nicht ungeprueft nachgezogen.
- Mainsail- und Fluidd-Entwicklungszweige enthalten kleinere Korrekturen, derzeit aber keinen fuer diesen Drucker notwendigen Fix.

### Nicht installieren

- K2 OpenKlipper v0.1.0-alpha.1 wurde nur eingeschraenkt auf einem K2 Plus getestet. Die K2-Pro- und CFS-Kompatibilitaet ist nicht ausreichend belegt.
- Filament-Sync besitzt neue, noch unveroeffentlichte Korrekturen. Seine mitgelieferte Materialdatenbank ist aelter als der Live-Stand und sein Schreibweg wuerde mit dem vorhandenen CFS-DB-Guard konkurrieren.
- Upstream-Klipper oder -Moonraker nicht ueber Crealitys angepasste K2-Forks installieren.

## Erledigte Wartungspunkte

- Das oeffentliche Masterpack wurde von Helper v62 auf den geprueften
  v86-Quell- und Archivstand gebracht.
- Ein bereinigter Public-Restore mit 191 geprueften Dateien ersetzt keine
  privaten Roharchive, enthaelt aber keine Zugangsdaten oder Git-Interna.
- Der separate Helix-Pi besitzt nun einen atomaren Stable-Rueckfall, das
  reproduzierbare Buildarchiv und ein kleines, oeffentlich sicheres
  Override-Archiv.

## Quellen

- https://www.crealitycloud.com/de/downloads/firmware/flagship-series/k2-pro
- https://github.com/mainsail-crew/mainsail/releases/tag/v2.18.2
- https://github.com/fluidd-core/fluidd/releases/tag/v1.37.3
- https://github.com/AlexxIT/go2rtc/releases/
- https://github.com/prestonbrown/helixscreen/releases/tag/v0.99.105
- https://github.com/Donkie/Spoolman/releases/tag/v0.26.0
- https://github.com/grant0013/K2-OpenKlipper/releases/tag/v0.1.0-alpha.1
- https://github.com/grant0013/KAMP-K2/releases/tag/v1.1.0
