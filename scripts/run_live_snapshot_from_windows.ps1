param(
    [string]$PrinterIp = "192.168.178.74",
    [string]$User = "root",
    [Parameter(Mandatory = $true)]
    [string]$Password,
    [string]$Stamp = (Get-Date -Format "yyyyMMdd_HHmmss")
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$localCollector = Join-Path $scriptDir "collect_k2pro_masterpack_snapshot.sh"

if (-not (Test-Path -LiteralPath $localCollector)) {
    throw "Collector script not found: $localCollector"
}

$remoteCollector = "/tmp/collect_k2pro_masterpack_snapshot.sh"

& pscp -batch -pw $Password $localCollector "${User}@${PrinterIp}:$remoteCollector"
if ($LASTEXITCODE -ne 0) {
    throw "pscp upload failed"
}

& plink -batch -ssh -l $User -pw $Password $PrinterIp "chmod +x $remoteCollector; sh $remoteCollector $Stamp"
if ($LASTEXITCODE -ne 0) {
    throw "remote collector failed"
}
