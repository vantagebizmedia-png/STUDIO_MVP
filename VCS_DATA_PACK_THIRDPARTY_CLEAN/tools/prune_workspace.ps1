param(
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath ".\workspace")) {
  Write-Host "SKIP: no existe .\workspace" -ForegroundColor Yellow
  exit 0
}

# Solo dejamos estos (top-level) dentro de workspace:
$keep = @("cache","tmp")

Write-Host "== PRUNE workspace ==" -ForegroundColor Cyan
Write-Host "Keep top-level: cache/, tmp/" -ForegroundColor Cyan

$dirs = Get-ChildItem -LiteralPath ".\workspace" -Directory -ErrorAction SilentlyContinue
if (-not $dirs) {
  Write-Host "workspace está vacío." -ForegroundColor Yellow
  exit 0
}

$toMove = @()
foreach ($d in $dirs) {
  if ($keep -notcontains $d.Name) { $toMove += $d }
}

Write-Host "Encontrados:" -ForegroundColor Cyan
foreach ($d in $dirs) { Write-Host (" - " + $d.Name) }

if ($toMove.Count -eq 0) {
  Write-Host "Nada que mover. workspace ya está mínimo." -ForegroundColor Green
} else {
  Write-Host ""
  Write-Host "Se moverán a _archive (reversible):" -ForegroundColor Yellow
  foreach ($d in $toMove) { Write-Host (" - " + $d.FullName) }

  if (-not $Execute) {
    Write-Host ""
    Write-Host "PREVIEW ONLY. Para ejecutar:" -ForegroundColor Yellow
    Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\prune_workspace.ps1 -Execute" -ForegroundColor Yellow
    exit 0
  }

  $ts = Get-Date -Format "yyyyMMdd_HHmmss"
  $dstRoot = ".\_archive\workspace_prune_$ts"
  New-Item -ItemType Directory -Force $dstRoot | Out-Null

  foreach ($d in $toMove) {
    $dst = Join-Path $dstRoot $d.Name
    Write-Host ("MOVE: {0} -> {1}" -f $d.FullName, $dst) -ForegroundColor Cyan
    Move-Item -LiteralPath $d.FullName -Destination $dst -Force
  }

  Write-Host ("OK: movido a {0}" -f $dstRoot) -ForegroundColor Green
}

# Asegurar estructura mínima requerida
New-Item -ItemType Directory -Force ".\workspace\cache\voice"  | Out-Null
New-Item -ItemType Directory -Force ".\workspace\cache\images" | Out-Null
New-Item -ItemType Directory -Force ".\workspace\tmp"          | Out-Null
Write-Host "OK: workspace mínimo asegurado (cache/voice, cache/images, tmp)" -ForegroundColor Green