# HelixScreen Raspberry Pi - Stand 2026-07-18

- Debian `13.6`, Kernel `6.18.38-v8-16k+`
- HelixScreen `v0.99.94`
- Dienst `helixscreen.service`: enabled und active
- Landschaftsmodus, lokale Schreibpfade und K2-Pro-/CFS-Overrides aktiv
- Keine fehlgeschlagenen Systemd-Units
- Keine ausstehenden APT-Paketupdates

Zusaetzlich laeuft K2Dash dauerhaft als `k2dash-readonly.service` mit der Beschreibung `K2Dash full dashboard`. Der historische Unit-Name bleibt fuer einen einfachen Rollback erhalten. Das Dashboard besitzt volle Steuerfunktionen; die Kamera wird ueber den lokalen nginx-Proxy zu go2rtc bereitgestellt.

Validierung:

- K2Dash-Startseite: HTTP 200
- go2rtc-Kameraframe ueber den Pi: HTTP 200
- nginx-Konfiguration: gueltig
- K2Dash-Systemd-Dienst: enabled und active
- HelixScreen-Systemd-Dienst: enabled und active

Der aktuelle Override-Tarball ist `helixscreen/helixscreen_k2pro_overrides_20260718.tar.gz`.
