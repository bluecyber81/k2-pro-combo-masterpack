# K2Dash fuer den K2 Pro Combo

Getesteter Pi-Build auf Basis von Upstream-Commit `b7dc27d` aus `pdromnt/k2dash`.

Die K2-Pro-Anpassung bietet:

- volle Druckersteuerung ueber Moonraker und Creality-WebSocket
- CFS-Anzeige und Dateifunktionen
- Hauptkamera ueber den stabilen go2rtc-Pfad des Druckers
- nginx-Reverse-Proxy auf Port `8090`
- blockierten alten Direkt-Signalisierungsendpunkt, der am K2 Pro HTTP 502 und Kamera-Dienstabbrueche ausloesen konnte
- Rollback auf den vorherigen Read-only-Stand

## Dateien

- `k2dash-full-go2rtc-pi-final-20260718_092156.tar.gz`: getestetes Installationspaket
- `deploy/`: Installations-, nginx-, Systemd- und Rollback-Dateien
- `source/k2dash-k2pro-go2rtc.patch`: Patch gegen Upstream `b7dc27d`
- `source/.env.pi-full.example`: getestete Build-Parameter

## Verifizierter Live-Stand

- Dienst enabled und active
- Startseite HTTP 200
- Kameraframe HTTP 200 mit JPEG-Daten
- K2Dash-Tests: 7 von 7 bestanden
- TypeScript-Build und ESLint bestanden

Vor einer Neuinstallation immer die vorhandenen Verzeichnisse `/opt/k2dash-readonly` und `/etc/systemd/system/k2dash-readonly.service` sichern. Der Unit-Name ist historisch; der installierte Dienst ist der Full-Control-Build.
