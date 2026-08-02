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

function Get-HybridMarker {
    param([string[]]$Lines)

    $markers = @($Lines | Where-Object { $_ -match '^\s*;\s*K2PRO_HYBRID_TIME\b' })
    if ($markers.Count -eq 0) {
        return $null
    }
    if ($markers.Count -ne 1) {
        throw "Expected at most one K2PRO_HYBRID_TIME marker, found $($markers.Count)."
    }
    $match = [regex]::Match(
        $markers[0],
        'K2PRO_HYBRID_TIME\s+v(?<version>\d+)\s+strategy=(?<strategy>\S+)\s+base=(?<base>\d+)\s+offset=(?<offset>-?\d+)\s+target=(?<target>\d+)',
        'IgnoreCase'
    )
    if (-not $match.Success) {
        throw "Existing K2PRO_HYBRID_TIME marker is malformed."
    }
    return [pscustomobject]@{
        Version = [int]$match.Groups['version'].Value
        Strategy = $match.Groups['strategy'].Value
        BaseSeconds = [int]$match.Groups['base'].Value
        OffsetSeconds = [int]$match.Groups['offset'].Value
        TargetSeconds = [int]$match.Groups['target'].Value
    }
}

function Get-CfsTimeline {
    param([string[]]$Lines)

    $records = New-Object System.Collections.Generic.List[object]
    $lastTool = $null
    $transitionsSeen = 0
    foreach ($line in $Lines) {
        $match = [regex]::Match($line, '^\s*T(\d+)\s*(?:;.*)?$')
        if ($match.Success) {
            $tool = [int]$match.Groups[1].Value
            if ($null -ne $lastTool -and $tool -ne $lastTool) {
                $transitionsSeen++
            }
            $lastTool = $tool
        }
        if ($line -match '^\s*M73\b') {
            $records.Add(
                [pscustomobject]@{
                    Line = $line
                    TransitionsSeen = $transitionsSeen
                }
            )
        }
    }

    return [pscustomobject]@{
        Transitions = $transitionsSeen
        Records = $records.ToArray()
    }
}

function Get-RemainingMinutes {
    param([string]$Line)

    $remainingMatch = [regex]::Match($Line, '(?:^|\s)R(?<value>\d+(?:\.\d+)?)')
    if (-not $remainingMatch.Success) {
        return $null
    }
    return [double]::Parse(
        $remainingMatch.Groups['value'].Value,
        [Globalization.CultureInfo]::InvariantCulture
    )
}

function Add-RemainingTimeAdjustment {
    param(
        [string]$Line,
        [int]$OffsetSeconds,
        [int]$CfsGapSeconds = 0,
        [double]$RemainingTransitionFraction = 0.0
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
    $transitionFraction = [math]::Max(0.0, [math]::Min(1.0, $RemainingTransitionFraction))
    $adjustedSeconds = ($remainingMinutes * 60.0) + ($OffsetSeconds * $remainingFraction) + ($CfsGapSeconds * $transitionFraction)
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
$existingHybrid = Get-HybridMarker $originalLines

$cfsTimeline = Get-CfsTimeline $originalLines
$transitions = [int]$cfsTimeline.Transitions
$isCfs = $transitions -gt 0
$crealitySeconds = Get-EstimatedSeconds $originalLines
$estimatorSeconds = Get-EstimatedSeconds $estimatedLines
$baseSeconds = if ($existingHybrid) {
    $existingHybrid.BaseSeconds
} elseif ($isCfs) {
    $crealitySeconds
} else {
    $estimatorSeconds
}
$targetSeconds = if ($existingHybrid) {
    $existingHybrid.TargetSeconds
} else {
    $baseSeconds + $offsetSeconds
}
$effectiveOffsetSeconds = if ($existingHybrid) { 0 } else { $offsetSeconds }
$strategy = if ($existingHybrid) {
    $existingHybrid.Strategy
} elseif ($isCfs) {
    'creality-cfs'
} else {
    'klipper-motion'
}

$sourceM73 = @()
$sourceM73Seconds = 0
$cfsGapSeconds = 0
if ($isCfs) {
    $sourceM73 = @($cfsTimeline.Records)
    $estimatedM73Count = @($estimatedLines | Where-Object { $_ -match '^\s*M73\b' }).Count
    if ($sourceM73.Count -eq 0 -or $sourceM73.Count -ne $estimatedM73Count) {
        throw "CFS M73 timelines differ (Creality=$($sourceM73.Count), estimator=$estimatedM73Count)."
    }
    $sourceRemainingMinutes = @(
        $sourceM73 | ForEach-Object { Get-RemainingMinutes $_.Line } | Where-Object { $null -ne $_ }
    )
    if ($sourceRemainingMinutes.Count -eq 0) {
        throw "CFS source has no usable M73 remaining-time values."
    }
    $sourceM73Seconds = [int][math]::Round(
        (($sourceRemainingMinutes | Measure-Object -Maximum).Maximum * 60.0)
    )
    $cfsGapSeconds = [int][math]::Max(
        0,
        $targetSeconds - $sourceM73Seconds - $effectiveOffsetSeconds
    )
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
        $remainingTransitionFraction = 0.0
        if ($isCfs) {
            $sourceRecord = $sourceM73[$m73Index]
            $line = $sourceRecord.Line
            $remainingTransitions = [math]::Max(
                0,
                $transitions - [int]$sourceRecord.TransitionsSeen
            )
            $remainingTransitionFraction = $remainingTransitions / [double]$transitions
        }
        $line = Add-RemainingTimeAdjustment `
            -Line $line `
            -OffsetSeconds $effectiveOffsetSeconds `
            -CfsGapSeconds $cfsGapSeconds `
            -RemainingTransitionFraction $remainingTransitionFraction
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

$marker = '; K2PRO_HYBRID_TIME v2 strategy={0} base={1} offset={2} target={3} transitions={4} cfs_gap={5} m73_start={6} applied_offset={7} samples={8}' -f $strategy, $baseSeconds, $offsetSeconds, $targetSeconds, $transitions, $cfsGapSeconds, $sourceM73Seconds, $effectiveOffsetSeconds, [int]$settings.sample_count
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
    applied_offset_seconds = $effectiveOffsetSeconds
    cfs_gap_seconds = $cfsGapSeconds
    source_m73_seconds = $sourceM73Seconds
    target_seconds = $targetSeconds
    output = $outputFullPath
} | ConvertTo-Json -Compress
