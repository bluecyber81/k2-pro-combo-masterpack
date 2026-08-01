# HelixScreen fuer den K2 Pro Combo

Aktueller verifizierter Stand des separaten Raspberry-Pi-Displays:

- Upstream-Basis: HelixScreen `0.99.105`
- getesteter Entwicklungscommit: `c3d8be0978040d8b1948b9db5a29022c9c9cc659`
- Ziel: Raspberry Pi 64 Bit, DRM plus FBDEV-Rueckfall
- Anzeige: `1024x600` im Querformat
- normale Helix-Oberflaeche mit voller Druckerbedienung
- zusaetzliche Teststeuerung nur am lokalen Unix-Socket
  `/run/helixscreen/helixctl.sock`

## Aktuelle Dateien

- `helixscreen-k2-pro-combo-overrides.sh` bereinigt das K2-Pro-/CFS-Layout
  idempotent und entfernt die zweite Kamera-Instanz, die den sichtbaren Status
  faelschlich wieder auf `Kamera wird verbunden...` setzen konnte.
- `helixscreen_k2pro_main-c3d8be0_overrides_20260801.tar.gz` enthaelt den
  Override, die vier systemd-Drop-ins, den Querformatdienst und Buildinfos.
- `25-local-helixctl.conf` aktiviert den Steuer-Socket ohne HTTP-Listener.
- `DEV_BUILD_INFO_20260731.txt` dokumentiert Commit, Optionen und Binary-Hashes.
- `patches/0001-pi-dual-link-include-remote-linenoise.patch` repariert den
  FBDEV-Link des Upstream-Dual-Builds bei `ENABLE_REMOTE_CONTROL=yes`.

SHA-256 des aktuellen Override-Archivs:

```text
b8be7fdc7bdfd77208477459535bda67ae0d9666f874ef6dea6bd37b21f63492
```

Das rund 65 MB grosse, reproduzierbare Pi-Buildarchiv wird als GitHub-Release-
Anhang bereitgestellt und nicht dauerhaft in den Git-Verlauf aufgenommen.
Sein SHA-256 lautet:

```text
4e5663d310e403dd1e94e086e2c57314f31a47cecd9b81844edd4cbcde9c352f
```

## Wiederherstellung

Vor jeder Wiederherstellung zuerst den vorhandenen Helix-Ordner, die
persistenten Einstellungen unter `/home/mks/printer_data/config/helixscreen`
und die systemd-Drop-ins sichern. Der live erhaltene Stable-Rueckfallordner ist:

```text
/home/mks/helixscreen-stable-v0.99.105-before-main-c3d8be0-20260801_051305
```

Das Override-Archiv wird ab `/` entpackt. Anschliessend:

```sh
sudo systemctl daemon-reload
/home/mks/helixscreen-k2-pro-combo-overrides.sh
sudo systemctl restart helixscreen.service
systemctl is-active helixscreen.service
systemctl --failed
```

Die Archive vom 2026-07-12 und 2026-07-18 bleiben historische Rueckfallstaende
fuer die damaligen Stable-Versionen. Das vollstaendige Testergebnis steht in
`docs/HELIXSCREEN_PI_UPDATE_20260731.md`.
