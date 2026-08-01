# GitHub-Aktualisierung

Dieses Paket ist lokal bereits als Git-Repo vorbereitet und mit `bluecyber81/k2-pro-combo-masterpack` verbunden.

## Wichtig

Nur die bereinigte Helper-Quelle, oeffentliche Reports und der Public-Restore duerfen in einen oeffentlichen Branch. Vollstaendige Config/System-Archive enthalten eine Moonraker-LMDB mit API-Schluessel und bleiben lokal.

## Einmaliger Login

Falls `gh auth status` meldet, dass du nicht eingeloggt bist:

```powershell
gh auth login
```

Nimm GitHub.com, HTTPS und Browser-Login.

## Aktualisierung

Vor dem Push im Paketordner ausfuehren und die Aenderung ueber einen eigenen
Branch pruefen:

```powershell
git status
git diff --check
git switch -c agent/sync-k2-masterpack
git add <gepruefte-Pfade>
git commit -m "Sync K2 Pro Combo live state YYYY-MM-DD"
git push -u origin agent/sync-k2-masterpack
gh pr create --draft
```

Erst nach erfolgreicher Geheimnis-, Hash- und Inhaltspruefung darf der Pull
Request nach `main` uebernommen werden.
