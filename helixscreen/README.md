# HelixScreen fuer den K2 Pro Combo

Aktueller verifizierter Stand des separaten Raspberry-Pi-Displays:

- Upstream-Basis: HelixScreen `0.99.106`
- exakter Upstream-Commit: `6f7f5bddb`
- Ziel: Raspberry Pi 64 Bit, DRM plus FBDEV-Rueckfall
- Anzeige: `1024x600` im Querformat
- normale Helix-Oberflaeche mit voller Druckerbedienung
- zusaetzliche Teststeuerung nur am lokalen Unix-Socket
  `/run/helixscreen/helixctl.sock`

## Aktuelle Dateien

- `helixscreen-k2-pro-combo-overrides.sh` bereinigt das K2-Pro-/CFS-Layout
  idempotent und entfernt die zweite Kamera-Instanz, die den sichtbaren Status
  faelschlich wieder auf `Kamera wird verbunden...` setzen konnte.
- `helixscreen_k2pro_v0.99.106_6f7f5bdd_overrides_20260801.tar.gz` enthaelt den
  Override, die vier systemd-Drop-ins, den Querformatdienst und Buildinfos.
- `25-local-helixctl.conf` aktiviert den Steuer-Socket ohne HTTP-Listener.
- `DEV_BUILD_INFO_20260801.txt` dokumentiert Commit, Optionen und Binary-Hashes.
- `patches/0001-pi-dual-link-include-remote-linenoise.patch` repariert den
  FBDEV-Link des Upstream-Dual-Builds bei `ENABLE_REMOTE_CONTROL=yes`.
- `patches/0002-pi-dual-link-native-libraries.patch` stellt die nativen
  DRM-/Input-Linkbibliotheken bereit und haelt den FBDEV-Link frei davon.

SHA-256 des aktuellen Override-Archivs:

```text
3a2c97aa1344548e19b8b9c770fdc320ea3948c92ce917950f1b7ae21eb367fd
```

Das rund 65 MB grosse, normalisierte Pi-Buildarchiv wird als GitHub-Release-
Anhang bereitgestellt und nicht dauerhaft in den Git-Verlauf aufgenommen.
Sein SHA-256 lautet:

```text
a399aac6fcbd50b7bdfc4518e267c58ea1b98da4625217f09bc1e58f6bac147f
```

## Wiederherstellung

Vor jeder Wiederherstellung zuerst den vorhandenen Helix-Ordner, die
persistenten Einstellungen unter `/home/mks/printer_data/config/helixscreen`
und die systemd-Drop-ins sichern. Die aktuellen Rueckfallstaende sind:

```text
/home/mks/backups/helixscreen_pre_v099106_20260801_123231
/home/mks/backups/helixscreen_official_v099106_before_remote_20260801_144338
```

Das Override-Archiv wird ab `/` entpackt. Anschliessend:

```sh
sudo systemctl daemon-reload
/home/mks/helixscreen-k2-pro-combo-overrides.sh
sudo systemctl restart helixscreen.service
systemctl is-active helixscreen.service
systemctl --failed
```

Die Archive vom 2026-07-12, 2026-07-18 und der gepinnte Entwicklungsstand
`c3d8be0` bleiben historische Rueckfallstaende. Das vollstaendige aktuelle
Testergebnis steht in `docs/HELIXSCREEN_PI_UPDATE_20260801.md`.
