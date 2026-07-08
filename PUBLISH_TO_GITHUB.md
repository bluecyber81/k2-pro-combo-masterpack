# Publish To GitHub

Dieses Paket ist lokal bereits als Git-Repo vorbereitet.

Aktueller lokaler Commit:

- `e5aa1ed Preserve package file line endings`
- `96c5ed2 Add K2 Pro Combo masterpack 2026-07-08`

## Wichtig

Dieses Repo sollte privat bleiben. Es enthaelt echte Drucker-Backups, lokale IPs, Systemreports und CFS-/Materialdaten.

## Einmaliger Login

Falls `gh auth status` meldet, dass du nicht eingeloggt bist:

```powershell
gh auth login
```

Nimm GitHub.com, HTTPS und Browser-Login.

## Private Repo-Erstellung und Push

Danach im Paketordner ausfuehren:

```powershell
.\scripts\publish_private_repo.ps1
```

Standard-Repo:

`bluecyber81/k2-pro-combo-masterpack`

