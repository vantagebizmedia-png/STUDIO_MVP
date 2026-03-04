param(
  [ValidateSet("safe","aggressive")]
  [string]$Mode = "safe",

  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$ws = $env:STUDIO_WORKSPACE
if (-not $ws) { throw "STUDIO_WORKSPACE no está seteado." }
if (-not [IO.Path]::IsPathRooted($ws)) { throw "STUDIO_WORKSPACE debe ser absoluto: $ws" }

$outDir = Join-Path $ws "output"
if (!(Test-Path $outDir)) { throw "No existe output dir: $outDir" }

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$arch = Join-Path $outDir ("_archive\" + $ts)
New-Item -ItemType Directory -Force $arch | Out-Null

$keep = New-Object System.Collections.Generic.HashSet[string]
$masterLatest = Join-Path $outDir "video_final_latest.mp4"
$socialLatest = Join-Path $outDir "video_final_latest_social.mp4"

if (Test-Path $socialLatest) { [void]$keep.Add((Resolve-Path $socialLatest).Path) }

if ($Mode -eq "safe") {
  if (Test-Path $masterLatest) { [void]$keep.Add((Resolve-Path $masterLatest).Path) }
}

# Candidatos a mover (solo duplicados/alias típicos)
$candidates = @()
$candidates += Get-ChildItem $outDir -File -Filter "video_FINAL_*.mp4" -ErrorAction SilentlyContinue
$candidates += Get-ChildItem $outDir -File -Filter "video_latest.mp4" -ErrorAction SilentlyContinue
$candidates += Get-ChildItem $outDir -File -Filter "video_final_*.mp4" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -ne "video_final_latest.mp4" -and $_.Name -ne "video_final_latest_social.mp4" }

# En modo aggressive, también movemos el master latest (dejando solo social)
if ($Mode -eq "aggressive" -and (Test-Path $masterLatest)) {
  $candidates += Get-Item $masterLatest
}

# Dedup por path
$seen = New-Object System.Collections.Generic.HashSet[string]
$toMove = @()
foreach ($f in $candidates) {
  if (-not $f) { continue }
  $p = (Resolve-Path $f.FullName).Path
  if ($keep.Contains($p)) { continue }
  if ($seen.Contains($p)) { continue }
  [void]$seen.Add($p)
  $toMove += $f
}

Write-Host "PRUNE Mode=$Mode DryRun=$($DryRun.IsPresent)" -ForegroundColor Cyan
Write-Host "Output: $outDir" -ForegroundColor DarkGray
Write-Host "Archive: $arch" -ForegroundColor DarkGray
Write-Host ("Keep: " + ($keep.Count)) -ForegroundColor DarkGray
Write-Host ("Move: " + ($toMove.Count)) -ForegroundColor Yellow

foreach ($f in $toMove) {
  $dst = Join-Path $arch $f.Name
  if ($DryRun) {
    Write-Host ("DRYRUN: move {0} -> {1}" -f $f.FullName, $dst)
  } else {
    Move-Item -LiteralPath $f.FullName -Destination $dst -Force
    Write-Host ("moved: {0}" -f $f.Name) -ForegroundColor Green
  }
}

Write-Host "DONE." -ForegroundColor Cyan
