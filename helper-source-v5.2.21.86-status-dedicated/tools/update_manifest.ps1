[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$rootPath = (Resolve-Path -LiteralPath $Root).Path
$manifestPath = Join-Path $rootPath 'PACKAGE_SHA256SUMS.txt'

$files = Get-ChildItem -LiteralPath $rootPath -Recurse -File |
    Where-Object {
        $_.FullName -ne $manifestPath -and
        $_.FullName -ne (Join-Path $rootPath 'web\k2-status\status.json') -and
        $_.FullName -notmatch '\\(?:\.mypy_cache|\.ruff_cache|\.tmp-[^\\]+|__pycache__|backups|reports|state)\\'
    } |
    Sort-Object FullName

$lines = foreach ($file in $files) {
    $relative = $file.FullName.Substring($rootPath.Length).TrimStart('\').Replace('\', '/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $relative"
}

$content = ($lines -join "`n") + "`n"
[IO.File]::WriteAllText($manifestPath, $content, [Text.UTF8Encoding]::new($false))

Write-Host "PACKAGE_MANIFEST_UPDATED files=$($files.Count) path=$manifestPath"
