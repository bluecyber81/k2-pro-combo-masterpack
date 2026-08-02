[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$rootPath = (Resolve-Path -LiteralPath $Root).Path

foreach ($command in @('shellcheck', 'shfmt', 'ruff', 'python', 'sh')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command is missing: $command"
    }
}

$shellFiles = @(
    Get-Item -LiteralPath (Join-Path $rootPath 'helper.sh')
    Get-Item -LiteralPath (Join-Path $rootPath 'install_k2pro.sh')
    Get-ChildItem -LiteralPath (Join-Path $rootPath 'scripts') -File |
        Where-Object { $_.Extension -eq '.sh' -or $_.Name -match '^S[0-9]+' }
    Get-ChildItem -LiteralPath (Join-Path $rootPath 'tests') -File -Filter '*.sh'
)

& shellcheck --severity=error -- @($shellFiles.FullName)
if ($LASTEXITCODE -ne 0) {
    throw 'ShellCheck found an error-severity issue.'
}

foreach ($file in $shellFiles) {
    $null = & shfmt -ln posix $file.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "shfmt could not parse: $($file.FullName)"
    }
}

$pythonFiles = @(
    Get-ChildItem -LiteralPath $rootPath -Recurse -File -Filter '*.py' |
        Where-Object {
            $_.FullName -notmatch '\\backups\\' -and
            $_.FullName -notmatch '\\reports\\' -and
            $_.FullName -notmatch '\\state\\'
        }
)

$ruffPythonFiles = @(
    $pythonFiles | Where-Object {
        $_.FullName -ne (Join-Path $rootPath 'files\auto_addr_recovery\auto_addr_wrapper.py')
    }
)

& ruff check --no-cache --select F --target-version py39 -- @($ruffPythonFiles.FullName)
if ($LASTEXITCODE -ne 0) {
    throw 'Ruff found a Python correctness issue.'
}

& python -B (Join-Path $PSScriptRoot 'validate_python.py') $rootPath
if ($LASTEXITCODE -ne 0) {
    throw 'Python or JSON validation failed.'
}

$oldNoBytecode = $env:PYTHONDONTWRITEBYTECODE
$env:PYTHONDONTWRITEBYTECODE = '1'
try {
    Push-Location -LiteralPath $rootPath
    try {
        & python -B -m unittest discover -s tests -p 'test_*.py' -v
        if ($LASTEXITCODE -ne 0) {
            throw 'Python regression tests failed.'
        }

        & sh tests/test_cfs_safe_boot_hook.sh
        if ($LASTEXITCODE -ne 0) {
            throw 'Shell integration tests failed.'
        }

        & sh -c 'K2_HELPER_DIR=. sh scripts/nozzle_camera_power_guard.sh selftest'
        if ($LASTEXITCODE -ne 0) {
            throw 'Nozzle-camera power guard selftest failed.'
        }

        & sh -c 'K2_HELPER_DIR=. sh scripts/auto_addr_recovery.sh selftest'
        if ($LASTEXITCODE -ne 0) {
            throw 'Auto-address recovery guard selftest failed.'
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    $env:PYTHONDONTWRITEBYTECODE = $oldNoBytecode
}

Write-Host "K2_HELPER_VALIDATION_OK shell=$($shellFiles.Count) python=$($pythonFiles.Count) shell_tests=3"
