[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$GeneratedDate = (Get-Date -Format 'yyyy-MM-dd')
)

$ErrorActionPreference = 'Stop'

$rootPath = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
$manifestPath = Join-Path $rootPath 'PACKAGE_MANIFEST.txt'
$hashPath = Join-Path $rootPath 'SHA256SUMS_PACKAGE.txt'
$gitPrefix = (Join-Path $rootPath '.git') + [IO.Path]::DirectorySeparatorChar

$files = Get-ChildItem -LiteralPath $rootPath -File -Recurse -Force |
    Where-Object {
        -not $_.FullName.StartsWith($gitPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        $_.FullName -ne $manifestPath -and
        $_.FullName -ne $hashPath
    } |
    ForEach-Object {
        [pscustomobject]@{
            Path = [IO.Path]::GetRelativePath($rootPath, $_.FullName).Replace('\', '/')
            FullName = $_.FullName
            Length = $_.Length
        }
    } |
    Sort-Object Path

$manifestLines = @(
    'K2 Pro Combo Masterpack manifest'
    "Generated: $GeneratedDate Europe/Berlin"
    "File count before manifest/hash files: $($files.Count)"
    ''
)
$manifestLines += $files | ForEach-Object { "$($_.Path)`t$($_.Length)" }

$hashLines = foreach ($file in $files) {
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($file.Path)"
}

$utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($manifestPath, (($manifestLines -join "`n") + "`n"), $utf8NoBom)
[IO.File]::WriteAllText($hashPath, (($hashLines -join "`n") + "`n"), $utf8NoBom)

Write-Output "MASTERPACK_MANIFEST_UPDATED files=$($files.Count)"
