Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$ws = $env:STUDIO_WORKSPACE
if (-not $ws) { throw "STUDIO_WORKSPACE no esta seteado." }
if (-not [IO.Path]::IsPathRooted($ws)) { throw "STUDIO_WORKSPACE debe ser absoluto: $ws" }

function DirSize([string]$p) {
  if (!(Test-Path -LiteralPath $p)) { return 0 }
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

$runs  = Join-Path $ws "runs"
$out   = Join-Path $ws "output"
$cache = Join-Path $ws "cache"

Write-Host "WS: $ws" -ForegroundColor Cyan
Write-Host ("runs  : {0}" -f (Fmt (DirSize $runs)))  -ForegroundColor Yellow
Write-Host ("output: {0}" -f (Fmt (DirSize $out)))   -ForegroundColor Yellow
Write-Host ("cache : {0}" -f (Fmt (DirSize $cache))) -ForegroundColor Yellow

# Top 10 biggest run folders
if (Test-Path -LiteralPath $runs) {
  $dirs = Get-ChildItem -LiteralPath $runs -Directory -ErrorAction SilentlyContinue
  $rows = foreach ($d in $dirs) {
    $sz = DirSize $d.FullName
    [pscustomobject]@{ Run=$d.Name; SizeBytes=$sz; Size=Fmt $sz; LastWrite=$d.LastWriteTime }
  }
  Write-Host "`nTop runs por tamano:" -ForegroundColor Cyan
  $rows | Sort-Object SizeBytes -Descending | Select-Object -First 10 | Format-Table Run,Size,LastWrite -AutoSize
}