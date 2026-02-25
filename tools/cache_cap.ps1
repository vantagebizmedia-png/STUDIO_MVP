param(
  [int]$MaxMB = 300,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$ws = $env:STUDIO_WORKSPACE
if (-not $ws) { throw "STUDIO_WORKSPACE no esta seteado." }
if (-not [IO.Path]::IsPathRooted($ws)) { throw "STUDIO_WORKSPACE debe ser absoluto: $ws" }

$cache = Join-Path $ws "cache"
if (!(Test-Path -LiteralPath $cache)) { Write-Host "No existe cache/." -ForegroundColor Yellow; exit 0 }

function SizeBytes([string]$p) {
  $sum = (Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
  if (-not $sum) { $sum = 0 }
  return [int64]$sum
}
function Fmt([int64]$b) {
  if ($b -ge 1GB) { return "{0:n2} GB" -f ($b/1GB) }
  if ($b -ge 1MB) { return "{0:n2} MB" -f ($b/1MB) }
  if ($b -ge 1KB) { return "{0:n2} KB" -f ($b/1KB) }
  return "$b B"
}

$maxBytes = [int64]$MaxMB * 1MB
$cur = SizeBytes $cache

Write-Host ("CACHE_CAP DryRun={0} MaxMB={1} Current={2}" -f $DryRun.IsPresent,$MaxMB,(Fmt $cur)) -ForegroundColor Cyan
if ($cur -le $maxBytes) { Write-Host "OK: cache bajo el limite." -ForegroundColor Green; exit 0 }

$files = Get-ChildItem -LiteralPath $cache -Recurse -File -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime,Length

$deleted = 0
foreach ($f in $files) {
  if ($cur -le $maxBytes) { break }
  if ($DryRun) {
    Write-Host ("DRYRUN delete: {0}" -f $f.FullName)
  } else {
    Remove-Item -LiteralPath $f.FullName -Force
  }
  $cur -= [int64]$f.Length
  $deleted += 1
}

Write-Host ("DONE: deleted={0} newSize={1}" -f $deleted,(Fmt $cur)) -ForegroundColor Yellow