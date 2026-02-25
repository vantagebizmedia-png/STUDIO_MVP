param(
  # Mantén las últimas N carpetas (por fecha)
  [int]$KeepLast = 20,

  # Y/o elimina carpetas más viejas que N días (0 = deshabilitado)
  [int]$MaxAgeDays = 0,

  # Solo previsualiza (no borra)
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$ws = $env:STUDIO_WORKSPACE
if (-not $ws) { throw "STUDIO_WORKSPACE no esta seteado." }
if (-not [IO.Path]::IsPathRooted($ws)) { throw "STUDIO_WORKSPACE debe ser absoluto: $ws" }

$outDir = Join-Path $ws "output"
$archDir = Join-Path $outDir "_archive"
if (!(Test-Path -LiteralPath $archDir)) {
  Write-Host "No existe _archive. Nada que limpiar." -ForegroundColor Yellow
  exit 0
}

# Carpetas dentro de _archive (cada una es un snapshot timestamp)
$folders = Get-ChildItem -LiteralPath $archDir -Directory -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending

if (-not $folders -or $folders.Count -eq 0) {
  Write-Host "Archive vacío. Nada que limpiar." -ForegroundColor Yellow
  exit 0
}

$keepSet = New-Object System.Collections.Generic.HashSet[string]

# 1) KeepLast
if ($KeepLast -gt 0) {
  $folders | Select-Object -First $KeepLast | ForEach-Object {
    [void]$keepSet.Add((Resolve-Path -LiteralPath $_.FullName).Path)
  }
}

# 2) MaxAgeDays
$cutoff = $null
if ($MaxAgeDays -gt 0) {
  $cutoff = (Get-Date).AddDays(-1 * $MaxAgeDays)
}

$toDelete = @()

foreach ($f in $folders) {
  $fp = (Resolve-Path -LiteralPath $f.FullName).Path

  # Regla: si está en keepSet, se conserva siempre
  if ($keepSet.Contains($fp)) { continue }

  # Si MaxAgeDays está activo, solo borra si es más viejo que cutoff
  if ($cutoff) {
    if ($f.LastWriteTime -lt $cutoff) { $toDelete += $f }
  } else {
    # Si no hay cutoff, borra todo lo que no esté en keepSet
    $toDelete += $f
  }
}

Write-Host ("ARCHIVE_GC DryRun={0} KeepLast={1} MaxAgeDays={2}" -f $DryRun.IsPresent,$KeepLast,$MaxAgeDays) -ForegroundColor Cyan
Write-Host ("Archive: {0}" -f $archDir) -ForegroundColor DarkGray
Write-Host ("Total folders: {0} | Will delete: {1}" -f $folders.Count,$toDelete.Count) -ForegroundColor Yellow

foreach ($f in $toDelete) {
  if ($DryRun) {
    Write-Host ("DRYRUN delete: {0} (LastWriteTime={1})" -f $f.FullName,$f.LastWriteTime)
  } else {
    Remove-Item -LiteralPath $f.FullName -Recurse -Force
    Write-Host ("deleted: {0}" -f $f.Name) -ForegroundColor Green
  }
}

Write-Host "DONE." -ForegroundColor Cyan
