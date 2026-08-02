# Backup-Staende

Stand: 2026-08-02

## GitHub-sicherer Restore

`k2pro_public_restore_20260802.tar.gz` enthaelt:

- aktuelle Druckerkonfiguration ohne Config-Git-Objekte
- aktuelle CFS-/Materialdaten ohne historische Archivsammlung
- relevante System-/Init-Dateien
- bereinigte Helper-Quelle `v5.2.21.91-auto-addr-recovery`

Bewusst ausgeschlossen sind Moonraker-LMDB, Git-Interna, Zugangsdaten,
private Laufzeitzuordnungen und alte Diagnosearchive. Die lokale
Spoolman-Adresse in `moonraker.conf` ist absichtlich durch den Platzhalter
`HOME_ASSISTANT_OR_SPOOLMAN_HOST` ersetzt.

SHA-256: `00dab9f6d27ef088521684e06fdbfc5cdcc417f011a7b876b550c15f48e820ad`

## Vollstaendige private Roharchive

Der aktuelle private Restore bleibt lokal unter `outputs/`:

- `K2-Pro-Combo-Restore-v5.2.21.91-auto-addr-recovery-current-20260802.zip`
- enthaelt `K2-Pro-Combo-Printer-Restore-v5.2.21.91-final-20260802.tar.gz`
- Drucker-Payload SHA-256:
  `65addb7c42dd5bf53944ab3f63673c040163bbeac2f8e9b46b69da37c6538383`
- Privates Wrapper-ZIP SHA-256:
  `621c5de46874a4fd2c45b10461a34dca90a36a5b03f1a84829958babfeb03492`

Der Public-Restore enthaelt zusaetzlich den getesteten `auto_addr_wrapper.py`-
Fix als kontrollierte Systemreferenz und den Vier-Slot-Live-Testbericht.

Die Roharchive enthalten unter anderem Moonraker-Datenbank, Config-Git,
Laufzeitstatus, Spoolman-Zuordnungen und ausfuehrliche Historie. Sie sind das
vollstaendigere Notfallbackup, aber nicht fuer ein oeffentliches
Git-Repository bestimmt.
