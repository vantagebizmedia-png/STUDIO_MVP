param(
  [int]$MaxAgeDays = 14,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$ws = $env:STUDIO_WORKSPACE
if (-not $ws) { throw "STUDIO_WORKSPACE no esta seteado." }
if (-not [IO.Path]::IsPathRooted($ws)) { throw "STUDIO_WORKSPACE debe ser absoluto: $ws" }

$cache = Join-Path $ws "cache"
if (!(Test-Path -LiteralPath $cache)) {
  Write-Host "No existe cache/. Nada que limpiar." -ForegroundColor Yellow
  exit 0
}

$cutoff = (Get-Date).AddDays(-1 * $MaxAgeDays)

$files = Get-ChildItem -LiteralPath $cache -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -lt $cutoff }

Write-Host ("CACHE_GC DryRun={0} MaxAgeDays={1} cutoff={2}" -f $DryRun.IsPresent,$MaxAgeDays,$cutoff) -ForegroundColor Cyan
Write-Host ("Cache: {0}" -f $cache) -ForegroundColor DarkGray
Write-Host ("Files to delete: {0}" -f @($files).Count) -ForegroundColor Yellow

foreach ($f in $files) {
  if ($DryRun) {
    Write-Host ("DRYRUN delete: {0}" -f $f.FullName)
  } else {
    Remove-Item -LiteralPath $f.FullName -Force
  }
}

Write-Host "DONE." -ForegroundColor Cyan