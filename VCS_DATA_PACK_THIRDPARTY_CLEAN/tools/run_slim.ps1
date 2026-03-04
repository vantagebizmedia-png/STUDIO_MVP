param(
  [string]$RunId = "latest",
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$ws = $env:STUDIO_WORKSPACE
if (-not $ws) { throw "STUDIO_WORKSPACE no esta seteado." }
if (-not [IO.Path]::IsPathRooted($ws)) { throw "STUDIO_WORKSPACE debe ser absoluto: $ws" }

$runs = Join-Path $ws "runs"
if (!(Test-Path -LiteralPath $runs)) { Write-Host "No existe runs/." -ForegroundColor Yellow; exit 0 }

$runDir = $null
if ($RunId -eq "latest") {
  $runDir = Get-ChildItem -LiteralPath $runs -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
} else {
  $p = Join-Path $runs $RunId
  if (Test-Path -LiteralPath $p) { $runDir = Get-Item -LiteralPath $p }
}

if (-not $runDir) { throw "No encontre run: $RunId" }

Write-Host ("RUN_SLIM DryRun={0} Run={1}" -f $DryRun.IsPresent,$runDir.FullName) -ForegroundColor Cyan

$targets = @(
  (Join-Path $runDir.FullName "render"),
  (Join-Path $runDir.FullName "tmp"),
  (Join-Path $runDir.FullName "_tmp")
)

foreach ($t in $targets) {
  if (Test-Path -LiteralPath $t) {
    if ($DryRun) { Write-Host ("DRYRUN remove dir: {0}" -f $t) -ForegroundColor Yellow }
    else { Remove-Item -LiteralPath $t -Recurse -Force; Write-Host ("removed: {0}" -f $t) -ForegroundColor Green }
  }
}

Write-Host "DONE." -ForegroundColor Cyan