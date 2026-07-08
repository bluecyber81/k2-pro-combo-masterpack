param(
    [string]$Repository = "bluecyber81/k2-pro-combo-masterpack"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

git status -sb
gh auth status

if (-not (Test-Path -LiteralPath ".git")) {
    throw "This folder is not a git repository."
}

$remote = git remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) {
    gh repo create $Repository --private --source . --remote origin --push --description "Private K2 Pro Combo maintenance masterpack and backups"
} else {
    git push -u origin main
}

gh repo view $Repository --web
