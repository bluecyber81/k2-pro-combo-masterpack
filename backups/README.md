# Backup-Staende

Stand: 2026-07-31

## GitHub-sicherer Restore

`k2pro_public_restore_20260731.tar.gz` enthaelt:

- aktuelle Druckerkonfiguration ohne Config-Git-Objekte
- aktuelle CFS-/Materialdaten ohne historische Archivsammlung
- relevante System-/Init-Dateien
- bereinigte Helper-Quelle `v5.2.21.86-status-dedicated`

Bewusst ausgeschlossen sind Moonraker-LMDB, Git-Interna, Zugangsdaten,
private Laufzeitzuordnungen und alte Diagnosearchive. Die lokale
Spoolman-Adresse in `moonraker.conf` ist absichtlich durch den Platzhalter
`HOME_ASSISTANT_OR_SPOOLMAN_HOST` ersetzt.

SHA-256: `12298df7202500128bf9f373107d4d2a6e2b0654ba9af92f9659131f595cdb78`

## Vollstaendige private Roharchive

Der aktuelle private Restore bleibt lokal unter `outputs/`:

- `K2-Pro-Combo-Restore-v5.2.21.86-status-dedicated-current-20260731.zip`
- enthaelt `K2-Pro-Combo-Printer-Restore-v5.2.21.86-final-20260731.tar.gz`
- Drucker-Payload SHA-256:
  `d1065f4613db524f5c3f3e25828a4ff7b52061e45562171f9a5695fd93575f87`

Die Roharchive enthalten unter anderem Moonraker-Datenbank, Config-Git,
Laufzeitstatus, Spoolman-Zuordnungen und ausfuehrliche Historie. Sie sind das
vollstaendigere Notfallbackup, aber nicht fuer ein oeffentliches
Git-Repository bestimmt.
