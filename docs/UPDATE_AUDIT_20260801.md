# K2 Pro Combo: Live- und Upstream-Pruefung 2026-08-01

## Ergebnis

Der Drucker ist kalt und im Standby voll funktionsfaehig. Die komplette
Helper-Pruefung endete mit `110 OK / 0 WARN / 0 FAIL`. Es wurde kein Druck,
keine Kalibrierung und kein Firmware-, MCU-, Kamera- oder CFS-Flash gestartet.

## Verifizierter Live-Stand

- Modell `F012`, Mainboard `CR0CN200400C10`
- Drucker-Firmware `1.1.6.7`
- CFS-Firmware `1.5.0`, verbunden, Betriebsmodus `idle`
- Helper `v5.2.21.86-status-dedicated`
- Fluidd `1.37.3`, Mainsail `2.18.2`, go2rtc `1.9.14`
- K2Dash Commit `5e960411b8b35a4d3b8ebc17f76b943929f59d20`
- Spoolman `0.24.0` ueber das Home-Assistant-Add-on
- CFS-Datenbank `1785291996`, 51 offizielle und 2 lokale Profile

Die vier CFS-Slots sind vollstaendig Spoolman 1 bis 4 zugeordnet. Der aktive
Spool stimmt mit dem ausgewaehlten CFS-Slot ueberein. Die zwei mehrdeutigen
Material-IDs sind erwartete gemeinsame IDs von Hersteller- und kalibrierten
Benutzerprofilen; es fehlt keine Live-ID.

## Funktionspruefung

- Klipper ist `ready`; Extruder und Bett sind ungeheizt.
- Herstellerdateien `box.cfg` und `motor_control.cfg` stimmen bytegenau mit
  dem F012-Stand ueberein.
- Keine fremden CFS-Motorbefehle, Probe-Bypaesse oder Cold-Extrusion-Bypaesse.
- KAMP ist mit 5 mm Mesh-Rand aktiv; Klipper Garbage Collection ist aktiv.
- Hauptkamera, go2rtc, Fluidd-Proxy und Mainsail-Proxy liefern HTTP 200.
- Die Duesenkamera befindet sich korrekt im bedarfsgesteuerten Standby.
- Creality-Timelapse ist aktiv; keine unvollstaendige Aufnahme unter 1 MB.
- Statusseite auf Port 4410 liefert HTML und gueltiges JSON ohne Cache.
- Keine aktuellen schweren Klipper-, Moonraker-, Kamera- oder CFS-Logfehler.
- UDISK: rund 25.2 GB frei; Root-Dateisystem: 31 Prozent belegt.

## Update-Entscheidungen

### Direkt umgesetzt

- Raspberry-Pi-Systempakete einschliesslich Kernel, Sicherheitsbibliotheken
  und `raspi-config` wurden aus den Debian-/Raspberry-Pi-Repositories
  aktualisiert und nach Neustart ohne fehlgeschlagene Units verifiziert.
- HelixScreen Stable `0.99.106` wird mit der offiziellen K2-Kamera-Erkennung,
  zwei reinen Pi-Dual-Link-Korrekturen und einem ausschliesslich lokalen
  Diagnose-Socket eingesetzt. Der getrennte Bericht dokumentiert Build,
  Live-Test, verworfene A/B-Varianten und Rueckfall.
- Git-Zeilenendungsregeln decken alle Helper-Bootskripte ab, damit Windows-
  Checkouts keine ungueltigen CRLF-Startdateien erzeugen.

### Bewusst nicht erzwungen

- Es ist kein neueres exakt passendes offizielles K2-Pro-F012-Paket als
  `1.1.6.7` veroeffentlicht.
- Kein glaubwuerdiges neueres K2-Pro-CFS-, MCU- oder Kamera-Image mit passender
  Board-Zuordnung wurde gefunden.
- Spoolman `0.26.0` ist Upstream aktuell, das Home-Assistant-Add-on bietet aber
  weiterhin `0.24.0-0`. Ein Fremdcontainer wuerde Supervisor-Updates, Backups
  und die getestete CFS-Synchronisierung umgehen.
- Crealitys Klipper und Moonraker bleiben als Hersteller-Forks erhalten.
  Vanilla-Upstream ist kein kompatibles In-place-Update.
- Keine Alpha-/Beta-Firmware, K2-Plus-`tool.cfg`, Roh-RS485-Motorbefehle,
  Probe-Bypaesse oder OpenKlipper-Images wurden installiert.

### Beobachten

- Mainsail `develop` enthaelt nach `2.18.2` unter anderem eine schnellere
  Konsole, einen Preset-Korrekturstand und neue Logtypen. Keiner dieser noch
  ungetaggten Commits behebt einen aktuellen K2-Livefehler.
- Fluidd `develop` enthaelt nach `1.37.3` eine Korrektur fuer Werkzeugposition,
  Extrusionsmodi und Grenzen in der G-Code-Vorschau. Die installierte Vorschau
  verarbeitet die vorhandenen K2-Dateien aktuell korrekt; der Fix wird beim
  naechsten Stable-Release erneut bewertet.
- HelixScreens Snapshot-Abruf kann beim Verlassen der Startseite selten in den
  vorhandenen Fuenf-Sekunden-Abbruchschutz laufen. Der Dienst bleibt stabil
  und die Anzeige erholt sich. Ein kuerzerer lokaler Timeout und ein
  CPU-lastiger MJPEG-Transcoder wurden nach Messung bewusst nicht uebernommen.
- K2 OpenKlipper `v0.1.0-alpha.1` ist ein echtes Vorabprojekt, aber nicht als
  In-place-Update fuer einen K2 Pro Combo mit Creality-CFS freigegeben.

## Quellen

- https://www.crealitycloud.com/de/downloads/firmware/flagship-series/k2-pro
- https://github.com/prestonbrown/helixscreen/releases/tag/v0.99.106
- https://github.com/Donkie/Spoolman/releases/tag/v0.26.0
- https://github.com/mainsail-crew/mainsail/releases/tag/v2.18.2
- https://github.com/fluidd-core/fluidd/releases/tag/v1.37.3
- https://github.com/AlexxIT/go2rtc/releases/tag/v1.9.14
- https://github.com/CrealityOfficial/CrealityPrint/releases/tag/v7.2.0
- https://github.com/pdromnt/k2dash
