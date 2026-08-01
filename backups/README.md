# Backup-Staende

Stand: 2026-08-01

## GitHub-sicherer Restore

`k2pro_public_restore_20260801.tar.gz` enthaelt:

- aktuelle Druckerkonfiguration ohne Config-Git-Objekte
- aktuelle CFS-/Materialdaten ohne historische Archivsammlung
- relevante System-/Init-Dateien
- bereinigte Helper-Quelle `v5.2.21.87-motor-status`

Bewusst ausgeschlossen sind Moonraker-LMDB, Git-Interna, Zugangsdaten,
private Laufzeitzuordnungen und alte Diagnosearchive. Die lokale
Spoolman-Adresse in `moonraker.conf` ist absichtlich durch den Platzhalter
`HOME_ASSISTANT_OR_SPOOLMAN_HOST` ersetzt.

SHA-256: `28617e8d2d106c17f1577f06ff80dd3a15c84db1b0f8ee75911b50cfbf58442d`

## Vollstaendige private Roharchive

Der aktuelle private Restore bleibt lokal unter `outputs/`:

- `K2-Pro-Combo-Restore-v5.2.21.87-motor-status-current-20260801.zip`
- enthaelt `K2-Pro-Combo-Printer-Restore-v5.2.21.87-final-20260801.tar.gz`
- Drucker-Payload SHA-256:
  `d446c75879fe0d76e2415c6912ab89b4d5078d20ea602d36d20414641f72fbc3`
- Privates Wrapper-ZIP SHA-256:
  `1d298f197b17358dafee8c07cd5ce213adeef085f2e63538bae278ef72f98936`

Die Roharchive enthalten unter anderem Moonraker-Datenbank, Config-Git,
Laufzeitstatus, Spoolman-Zuordnungen und ausfuehrliche Historie. Sie sind das
vollstaendigere Notfallbackup, aber nicht fuer ein oeffentliches
Git-Repository bestimmt.
