param(
  [int]$KeepLast = 30,
  [int]$MaxAgeDays = 0,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$ws = $env:STUDIO_WORKSPACE
if (-not $ws) { throw "STUDIO_WORKSPACE no esta seteado." }
if (-not [IO.Path]::IsPathRooted($ws)) { throw "STUDIO_WORKSPACE debe ser absoluto: $ws" }

$runsDir = Join-Path $ws "runs"
if (!(Test-Path -LiteralPath $runsDir)) {
  Write-Host "No existe runs/. Nada que limpiar." -ForegroundColor Yellow
  exit 0
}

$dirs = Get-ChildItem -LiteralPath $runsDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if (-not $dirs) {
  Write-Host "runs/ vacio. Nada que limpiar." -ForegroundColor Yellow
  exit 0
}

$keepSet = New-Object System.Collections.Generic.HashSet[string]
if ($KeepLast -gt 0) {
  $dirs | Select-Object -First $KeepLast | ForEach-Object { [void]$keepSet.Add($_.FullName) }
}

$cutoff = $null
if ($MaxAgeDays -gt 0) { $cutoff = (Get-Date).AddDays(-1 * $MaxAgeDays) }

$toDelete = @()
foreach ($d in $dirs) {
  if ($keepSet.Contains($d.FullName)) { continue }
  if ($cutoff) {
    if ($d.LastWriteTime -lt $cutoff) { $toDelete += $d }
  } else {
    $toDelete += $d
  }
}

Write-Host ("RUNS_GC DryRun={0} KeepLast={1} MaxAgeDays={2}" -f $DryRun.IsPresent,$KeepLast,$MaxAgeDays) -ForegroundColor Cyan
Write-Host ("Runs: {0}" -f $runsDir) -ForegroundColor DarkGray
Write-Host ("Total: {0} | Will delete: {1}" -f $dirs.Count,$toDelete.Count) -ForegroundColor Yellow

foreach ($d in $toDelete) {
  if ($DryRun) {
    Write-Host ("DRYRUN delete: {0} (LastWrite={1})" -f $d.FullName,$d.LastWriteTime)
  } else {
    Remove-Item -LiteralPath $d.FullName -Recurse -Force
    Write-Host ("deleted: {0}" -f $d.Name) -ForegroundColor Green
  }
}

Write-Host "DONE." -ForegroundColor Cyan