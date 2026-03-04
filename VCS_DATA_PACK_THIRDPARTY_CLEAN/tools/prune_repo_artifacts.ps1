param(
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath ".\run.py")) { throw "Ejecuta desde la raíz (run.py)" }

Write-Host "== PRUNE repo artifacts (top-level) ==" -ForegroundColor Cyan
Write-Host "Esto NO toca studio/ cli/ app/ tests/ tools/ config/ workspace." -ForegroundColor Cyan
Write-Host "Solo mueve artefactos conocidos a _archive (reversible)." -ForegroundColor Cyan
Write-Host ""

# Directorios a mover (solo patrones conocidos)
$dirPatterns = @(
  "_share_bundle_*",
  "handoff_*",
  "mvp_workspace",
  "output",
  "runs",
  "cache"
)

# Archivos a mover (solo patrones conocidos)
$filePatterns = @(
  "STUDIO_SHARE_*.zip",
  "handoff_*.zip"
)

$dirsToMove = @()
foreach ($p in $dirPatterns) {
  $dirsToMove += Get-ChildItem -LiteralPath "." -Directory -Filter $p -ErrorAction SilentlyContinue
}

$filesToMove = @()
foreach ($p in $filePatterns) {
  $filesToMove += Get-ChildItem -LiteralPath "." -File -Filter $p -ErrorAction SilentlyContinue
}

# Dedup
$dirsToMove  = $dirsToMove  | Sort-Object FullName -Unique
$filesToMove = $filesToMove | Sort-Object FullName -Unique

if (((@($dirsToMove)).Count + (@($filesToMove)).Count) -eq 0) {
  Write-Host "Nada que mover. Repo ya está limpio a nivel top-level." -ForegroundColor Green
  exit 0
}

Write-Host "Se detectó lo siguiente para archivar:" -ForegroundColor Yellow
foreach ($d in $dirsToMove)  { Write-Host (" [DIR ] " + $d.Name) }
foreach ($f in $filesToMove) { Write-Host (" [FILE] " + $f.Name) }

if (-not $Execute) {
  Write-Host ""
  Write-Host "PREVIEW ONLY. Para ejecutar:" -ForegroundColor Yellow
  Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\prune_repo_artifacts.ps1 -Execute" -ForegroundColor Yellow
  exit 0
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$dstRoot = ".\_archive\repo_artifacts_$ts"
New-Item -ItemType Directory -Force $dstRoot | Out-Null

foreach ($d in $dirsToMove) {
  $dst = Join-Path $dstRoot $d.Name
  Write-Host ("MOVE DIR: {0} -> {1}" -f $d.FullName, $dst) -ForegroundColor Cyan
  Move-Item -LiteralPath $d.FullName -Destination $dst -Force
}

foreach ($f in $filesToMove) {
  $dst = Join-Path $dstRoot $f.Name
  Write-Host ("MOVE FILE: {0} -> {1}" -f $f.FullName, $dst) -ForegroundColor Cyan
  Move-Item -LiteralPath $f.FullName -Destination $dst -Force
}

Write-Host ""
Write-Host ("OK: archivado en {0}" -f $dstRoot) -ForegroundColor Green
