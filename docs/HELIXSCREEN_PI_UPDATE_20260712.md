# HelixScreen Raspberry Pi - Stand 2026-07-12

## Installierter Stand

- Debian 13 (trixie), alle angebotenen stabilen Pakete installiert
- HelixScreen `v0.99.89`
- Raspberry Pi 5, 1024 x 600, DRM `/dev/dri/card1`, Querformat
- K2 Pro Combo als entfernter Moonraker-Drucker
- CFS-sichere Filamentsensorrolle und CFS Load/Unload-Makros erhalten

## Durchgefuehrte Aktualisierung

- Vorheriges Pi-/HelixScreen-System vollstaendig als gezieltes Restore-Archiv gesichert
- 48 stabile Debian-Pakete ohne neue oder entfernte Pakete aktualisiert
- Offizielles HelixScreen-Release-Archiv per SHA-256 geprueft und auf `v0.99.89` aktualisiert
- Lokale Einstellungen, Querformat-Drop-ins, Bilder und Filamentzuordnungen erhalten
- Unnoetige Permission-denied-Ausgaben des Upstream-Launchers updatefest bereinigt; die eigentliche Konsolenbehandlung bleibt unveraendert

## Verifikation

- Pi-/HelixScreen-Test: `37 OK / 0 WARN / 0 FAIL`
- HelixScreen-Dienst aktiv, `NRestarts=0`
- Touchgeraet vorhanden, DRM-Ausgabe aktiv, 1024 x 600 erkannt
- K2 Moonraker, Webcam, Kamerabild und Spoolman jeweils HTTP 200
- CFS verbunden, Firmware `1.4.2`, Drucker `ready/standby`
- APT und DPKG sauber, keine ausgefallenen systemd-Dienste, kein Neustart erforderlich
- Drucker-Gesundheit nach dem Pi-Update: `73 OK / 0 WARN / 0 FAIL`

## Restore-Dateien

- Getestete lokale Overrides: `helixscreen/helixscreen_k2pro_overrides_20260712.tar.gz`
- SHA-256: `helixscreen/helixscreen_k2pro_overrides_20260712.tar.gz.sha256`
- Das vollstaendige Vor-Update-Archiv liegt ausserhalb dieses Repositories im lokalen Output-Verzeichnis und auf dem Display-Pi.
