# Backup-Staende

## GitHub-sicherer Restore

`k2pro_public_restore_20260718.tar.gz` enthaelt:

- aktuelle Druckerkonfiguration ohne Config-Git-Objekte
- aktuelle CFS-/Materialdaten ohne historische Archivsammlung
- relevante System-/Init-Dateien
- bereinigte Helper-Quelle `v5.2.21.68-stable-health-count`

Bewusst ausgeschlossen sind Moonraker-LMDB, Git-Interna, private Laufzeitzuordnungen und alte Diagnosearchive. Damit bleibt das Paket fuer eine oeffentliche Ablage geeignet und deckt trotzdem die praktische Neuinstallation nach einem Firmware-Reset ab.

SHA-256: `8F18A13574228E6A4D1B31A7F977CF93606A1763B57EDBEA8165E61F01FF47E3`

## Vollstaendige private Roharchive

Diese Dateien bleiben lokal unter `outputs/k2pro_masterpack_20260718_101800/remote_files/`:

- `k2pro_config_system_20260718_101959.tar.gz` - SHA-256 `B5E95EBE3FE5F08EF9679713E1B82E7EBAE647E33DD9B918B9E9FC9A5A16F1FA`
- `helper-script-live_20260718_101800.tar.gz` - SHA-256 `7DDA33420A9A53F689C4D440DCD0407B8D18A3EC3BB8D9FAB5633DE25507684C`

Die Roharchive enthalten unter anderem Moonraker-Datenbank, Config-Git, Laufzeitstatus, Spoolman-Zuordnungen und ausfuehrliche Historie. Sie sind das vollstaendigere Notfallbackup, aber nicht fuer ein oeffentliches Git-Repository bestimmt.
