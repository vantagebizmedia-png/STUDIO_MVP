param(
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath ".\run.py")) { throw "Ejecuta desde la raíz (run.py)" }

function Get-DirSizeMB([string]$Path) {
  if (!(Test-Path -LiteralPath $Path)) { return 0.0 }

  $m = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
       Measure-Object -Property Length -Sum

  $sum = 0
  if ($null -ne $m -and ($m.PSObject.Properties.Name -contains "Sum") -and $m.Sum) {
    $sum = [double]$m.Sum
  }

  return [Math]::Round(($sum / 1MB), 2)
}

$targets = @(
  ".\workspace",
  ".\_demo_out",
  ".\_demo_out_legacy",
  ".\_v03_legacy_run",
  ".\_v03_from_config",
  ".\_v03_a1111_run",
  ".\_v03_free_run",
  ".\_backup"
) | Where-Object { Test-Path -LiteralPath $_ }

Write-Host "== CLEANUP WORKSPACE v0.3 ==" -ForegroundColor Cyan
if ($targets.Count -eq 0) {
  Write-Host "Nada que archivar (no se encontraron carpetas target)." -ForegroundColor Yellow
} else {
  Write-Host "Targets detectados:" -ForegroundColor Cyan
  foreach ($t in $targets) {
    $mb = Get-DirSizeMB $t
    Write-Host (" - {0}  ({1} MB)" -f $t, $mb)
  }
}

Write-Host ""
Write-Host "También se eliminarán caches seguros: __pycache__, *.pyc, .pytest_cache, .mypy_cache" -ForegroundColor Cyan

if (-not $Execute) {
  Write-Host ""
  Write-Host "PREVIEW ONLY. Para ejecutar de verdad:" -ForegroundColor Yellow
  Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\cleanup_workspace.ps1 -Execute" -ForegroundColor Yellow
  exit 0
}

# 1) Archivar targets
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$archiveRoot = ".\_archive\workspace_trim_$ts"
New-Item -ItemType Directory -Force $archiveRoot | Out-Null

foreach ($t in $targets) {
  $name = Split-Path -Leaf $t
  $dst = Join-Path $archiveRoot $name
  Write-Host ("ARCHIVE: {0} -> {1}" -f $t, $dst) -ForegroundColor Cyan
  Move-Item -LiteralPath $t -Destination $dst -Force
}

# 2) Limpiar caches compiladas (seguro)
Write-Host "CLEAN: __pycache__" -ForegroundColor Cyan
Get-ChildItem -LiteralPath "." -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -Recurse -Force -LiteralPath $_.FullName }

Write-Host "CLEAN: *.pyc" -ForegroundColor Cyan
Get-ChildItem -LiteralPath "." -Recurse -File -Filter "*.pyc" -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -Force -LiteralPath $_.FullName }

foreach ($c in @(".\.pytest_cache",".\.mypy_cache")) {
  if (Test-Path -LiteralPath $c) {
    Write-Host ("CLEAN: {0}" -f $c) -ForegroundColor Cyan
    Remove-Item -Recurse -Force -LiteralPath $c
  }
}

Write-Host ""
Write-Host ("OK cleanup. Archivado en: {0}" -f $archiveRoot) -ForegroundColor Green
