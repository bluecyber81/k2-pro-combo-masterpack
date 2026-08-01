[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Original,

    [Parameter(Mandatory = $true)]
    [string]$Estimated,

    [Parameter(Mandatory = $true)]
    [string]$Calibration,

    [Parameter(Mandatory = $true)]
    [string]$Output
)

$ErrorActionPreference = 'Stop'

function Read-Utf8Text {
    param([string]$Path)
    return [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
}

function Split-TextLines {
    param([string]$Text)
    return [regex]::Split($Text, "\r?\n")
}

function Convert-TimeToSeconds {
    param([string]$Value)

    $seconds = 0
    $matches = [regex]::Matches($Value.ToLowerInvariant(), '(\d+)\s*([hms])')
    if ($matches.Count -eq 0) {
        throw "Unsupported estimated-time value: $Value"
    }

    foreach ($match in $matches) {
        $number = [int]$match.Groups[1].Value
        switch ($match.Groups[2].Value) {
            'h' { $seconds += $number * 3600 }
            'm' { $seconds += $number * 60 }
            's' { $seconds += $number }
        }
    }
    return $seconds
}

function Format-EstimatedTime {
    param([int]$Seconds)

    $hours = [math]::Floor($Seconds / 3600)
    $minutes = [math]::Floor(($Seconds % 3600) / 60)
    $remainingSeconds = $Seconds % 60
    if ($hours -gt 0) {
        return ('{0}h {1}m {2}s' -f $hours, $minutes, $remainingSeconds)
    }
    return ('{0}m {1}s' -f $minutes, $remainingSeconds)
}

function Get-EstimatedSeconds {
    param([string[]]$Lines)

    $values = @()
    foreach ($line in $Lines) {
        $match = [regex]::Match($line, '^\s*;\s*estimated printing time \(normal mode\)\s*=\s*(.+?)\s*$', 'IgnoreCase')
        if ($match.Success) {
            $values += Convert-TimeToSeconds $match.Groups[1].Value
        }
    }
    if ($values.Count -ne 1) {
        throw "Expected exactly one estimated printing time comment, found $($values.Count)."
    }
    return [int]$values[0]
}

function Get-ToolTransitions {
    param([string[]]$Lines)

    $tools = @()
    foreach ($line in $Lines) {
        $match = [regex]::Match($line, '^\s*T(\d+)\s*(?:;.*)?$')
        if ($match.Success) {
            $tools += [int]$match.Groups[1].Value
        }
    }

    $transitions = 0
    for ($index = 1; $index -lt $tools.Count; $index++) {
        if ($tools[$index] -ne $tools[$index - 1]) {
            $transitions++
        }
    }
    return $transitions
}

function Add-RemainingTimeOffset {
    param(
        [string]$Line,
        [int]$OffsetSeconds
    )

    if ($Line -notmatch '^\s*M73\b') {
        return $Line
    }

    $progressMatch = [regex]::Match($Line, '(?:^|\s)P(?<value>\d+(?:\.\d+)?)')
    $remainingMatch = [regex]::Match($Line, '(?:^|\s)R(?<value>\d+(?:\.\d+)?)')
    if (-not $progressMatch.Success -or -not $remainingMatch.Success) {
        return $Line
    }

    $progress = [double]::Parse($progressMatch.Groups['value'].Value, [Globalization.CultureInfo]::InvariantCulture)
    $remainingMinutes = [double]::Parse($remainingMatch.Groups['value'].Value, [Globalization.CultureInfo]::InvariantCulture)
    $remainingFraction = [math]::Max(0.0, [math]::Min(1.0, 1.0 - ($progress / 100.0)))
    $adjustedSeconds = ($remainingMinutes * 60.0) + ($OffsetSeconds * $remainingFraction)
    $adjustedMinutes = [int][math]::Floor(($adjustedSeconds / 60.0) + 0.5)

    $valueGroup = $remainingMatch.Groups['value']
    return $Line.Substring(0, $valueGroup.Index) + $adjustedMinutes.ToString([Globalization.CultureInfo]::InvariantCulture) + $Line.Substring($valueGroup.Index + $valueGroup.Length)
}

foreach ($path in @($Original, $Estimated, $Calibration)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file not found: $path"
    }
}

$settings = Get-Content -LiteralPath $Calibration -Raw | ConvertFrom-Json
$offsetSeconds = [int]$settings.offset_seconds
if ($offsetSeconds -lt -600 -or $offsetSeconds -gt 900) {
    throw "Calibration offset is outside the guarded range: $offsetSeconds seconds"
}

$originalText = Read-Utf8Text $Original
$estimatedText = Read-Utf8Text $Estimated
$newline = if ($estimatedText.Contains("`r`n")) { "`r`n" } else { "`n" }
$originalEndsWithNewline = $originalText.EndsWith("`n")
$originalLines = Split-TextLines $originalText
$estimatedLines = Split-TextLines $estimatedText

$transitions = Get-ToolTransitions $originalLines
$isCfs = $transitions -gt 0
$crealitySeconds = Get-EstimatedSeconds $originalLines
$estimatorSeconds = Get-EstimatedSeconds $estimatedLines
$baseSeconds = if ($isCfs) { $crealitySeconds } else { $estimatorSeconds }
$targetSeconds = $baseSeconds + $offsetSeconds
$strategy = if ($isCfs) { 'creality-cfs' } else { 'klipper-motion' }

$sourceM73 = @()
if ($isCfs) {
    $sourceM73 = @($originalLines | Where-Object { $_ -match '^\s*M73\b' })
    $estimatedM73Count = @($estimatedLines | Where-Object { $_ -match '^\s*M73\b' }).Count
    if ($sourceM73.Count -eq 0 -or $sourceM73.Count -ne $estimatedM73Count) {
        throw "CFS M73 timelines differ (Creality=$($sourceM73.Count), estimator=$estimatedM73Count)."
    }
}

$resultLines = New-Object System.Collections.Generic.List[string]
$m73Index = 0
$timeCommentCount = 0
foreach ($estimatedLine in $estimatedLines) {
    if ($estimatedLine -match '^\s*;\s*K2PRO_HYBRID_TIME\b') {
        continue
    }

    $line = $estimatedLine
    if ($line -match '^\s*M73\b') {
        if ($isCfs) {
            $line = $sourceM73[$m73Index]
        }
        $line = Add-RemainingTimeOffset -Line $line -OffsetSeconds $offsetSeconds
        $m73Index++
    }

    if ($line -match '^\s*;\s*estimated printing time \(normal mode\)\s*=') {
        $line = '; estimated printing time (normal mode) = ' + (Format-EstimatedTime $targetSeconds)
        $timeCommentCount++
    }
    $resultLines.Add($line)
}

if ($timeCommentCount -ne 1) {
    throw "Hybrid output has $timeCommentCount estimated-time comments instead of one."
}

$marker = '; K2PRO_HYBRID_TIME v1 strategy={0} base={1} offset={2} target={3} transitions={4} samples={5}' -f $strategy, $baseSeconds, $offsetSeconds, $targetSeconds, $transitions, [int]$settings.sample_count
$insertAt = $resultLines.Count
if ($insertAt -gt 0 -and $resultLines[$insertAt - 1] -eq '') {
    $insertAt--
}
$resultLines.Insert($insertAt, $marker)

if (-not $originalEndsWithNewline -and $resultLines.Count -gt 0 -and $resultLines[$resultLines.Count - 1] -eq '') {
    $resultLines.RemoveAt($resultLines.Count - 1)
} elseif ($originalEndsWithNewline -and ($resultLines.Count -eq 0 -or $resultLines[$resultLines.Count - 1] -ne '')) {
    $resultLines.Add('')
}

$outputText = [string]::Join($newline, $resultLines)
$outputFullPath = [System.IO.Path]::GetFullPath($Output)
$outputDirectory = [System.IO.Path]::GetDirectoryName($outputFullPath)
if (-not [System.IO.Directory]::Exists($outputDirectory)) {
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}

$temporaryOutput = Join-Path $outputDirectory ('.k2pro-hybrid-{0}-{1}.tmp' -f $PID, [Guid]::NewGuid().ToString('N'))
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($temporaryOutput, $outputText, $utf8NoBom)

try {
    if (Test-Path -LiteralPath $outputFullPath) {
        $replaceBackup = $outputFullPath + '.k2hybrid-replace-' + $PID + '.bak'
        [System.IO.File]::Replace($temporaryOutput, $outputFullPath, $replaceBackup, $true)
        Remove-Item -LiteralPath $replaceBackup -Force
    } else {
        [System.IO.File]::Move($temporaryOutput, $outputFullPath)
    }
} finally {
    if (Test-Path -LiteralPath $temporaryOutput) {
        Remove-Item -LiteralPath $temporaryOutput -Force
    }
}

[pscustomobject]@{
    strategy = $strategy
    transitions = $transitions
    creality_seconds = $crealitySeconds
    estimator_seconds = $estimatorSeconds
    offset_seconds = $offsetSeconds
    target_seconds = $targetSeconds
    output = $outputFullPath
} | ConvertTo-Json -Compress
