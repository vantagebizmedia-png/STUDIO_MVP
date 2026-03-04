param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $PackDir,

  [ValidateSet("A","B","C","D")]
  [string] $Preset = "B",

  [int] $Seed = 21,
  [int] $MaxScenes = 4,

  # música final
  [ValidateSet("fixed","dynamic")]
  [string] $DuckingMode = "dynamic"
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$Repo = Split-Path $PSScriptRoot -Parent

function Must-ExistFile([string]$p) { if (!(Test-Path $p -PathType Leaf)) { throw "FALTA archivo: $p" } }
function Must-ExistDir([string]$p)  { if (!(Test-Path $p -PathType Container)) { throw "FALTA directorio: $p" } }

# --- Validar herramientas requeridas ---
$final = Join-Path $Repo "tools\final.ps1"
$export = Join-Path $Repo "tools\export_release.ps1"
$vcs = Join-Path $Repo "tools\vcs_thirdparty_pack.ps1"
Must-ExistFile $final
Must-ExistFile $export
Must-ExistFile $vcs

# --- Validar PackDir ---
Must-ExistDir $PackDir
$PackDir = (Resolve-Path $PackDir).Path

Write-Host ""
Write-Host "=== SMOKE_RELEASE_ALL ===" -ForegroundColor Cyan
Write-Host "PackDir: $PackDir" -ForegroundColor DarkGray
Write-Host "Preset:  $Preset" -ForegroundColor DarkGray
Write-Host "Scenes:  $MaxScenes" -ForegroundColor DarkGray

# 1) compileall
Write-Host ""
Write-Host "[1/5] compileall ..." -ForegroundColor Cyan
python -m compileall (Join-Path $Repo "app") -q
if ($LASTEXITCODE -ne 0) { throw "compileall falló" }
Write-Host "OK: compileall" -ForegroundColor Green

# 2) FAST
Write-Host ""
Write-Host "[2/5] FINAL FAST ..." -ForegroundColor Cyan
pwsh -NoProfile -ExecutionPolicy Bypass -File $final -PackDir $PackDir -Seed $Seed -MaxScenes $MaxScenes -Preset $Preset -Mode FAST

$fastOut = Join-Path $Repo ("workspace\output\video_FINAL_FAST_{0}.mp4" -f $Preset)
Must-ExistFile $fastOut
Write-Host "OK: FAST output -> $fastOut" -ForegroundColor Green

# 3) CINE + MUSIC (dynamic por defecto)
Write-Host ""
Write-Host "[3/5] FINAL CINE + MUSIC ($DuckingMode) ..." -ForegroundColor Cyan
pwsh -NoProfile -ExecutionPolicy Bypass -File $final -PackDir $PackDir -Seed $Seed -MaxScenes $MaxScenes -Preset $Preset -Mode CINE -MusicMode fixed -DuckingMode $DuckingMode

$cineOut = Join-Path $Repo ("workspace\output\video_FINAL_CINE_MUSIC_{0}_{1}.mp4" -f $DuckingMode.ToUpper(), $Preset)
Must-ExistFile $cineOut
Write-Host "OK: CINE output -> $cineOut" -ForegroundColor Green

# 4) Export release (folder + zip)
Write-Host ""
Write-Host "[4/5] export_release.ps1 ..." -ForegroundColor Cyan
pwsh -NoProfile -ExecutionPolicy Bypass -File $export -PackDir $PackDir -Preset $Preset

# Encontrar el ZIP más reciente del release de video
$relRoot = Join-Path $Repo "workspace\release"
Must-ExistDir $relRoot

$zipVideo = Get-ChildItem $relRoot -File -Filter ("STUDIO_RELEASE_*_{0}_*.zip" -f $Preset) -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $zipVideo) { throw "No encontré ZIP de release STUDIO_RELEASE_*_{Preset}_*.zip en: $relRoot" }
Write-Host "OK: ZIP release video -> $($zipVideo.FullName)" -ForegroundColor Green

# 5) VCS third-party pack + zip
Write-Host ""
Write-Host "[5/5] vcs_thirdparty_pack.ps1 -Zip ..." -ForegroundColor Cyan
pwsh -NoProfile -ExecutionPolicy Bypass -File $vcs -Zip

$zipVcs = Get-ChildItem $relRoot -File -Filter "VCS_DATA_PACK_THIRDPARTY_*.zip" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $zipVcs) { throw "No encontré ZIP VCS_DATA_PACK_THIRDPARTY_*.zip en: $relRoot" }
Write-Host "OK: ZIP third-party -> $($zipVcs.FullName)" -ForegroundColor Green

Write-Host ""
Write-Host " SMOKE_RELEASE_ALL PASS" -ForegroundColor Green
Write-Host " - FAST:  $fastOut" -ForegroundColor DarkGray
Write-Host " - CINE:  $cineOut" -ForegroundColor DarkGray
Write-Host " - ZIP1:  $($zipVideo.FullName)" -ForegroundColor DarkGray
Write-Host " - ZIP2:  $($zipVcs.FullName)" -ForegroundColor DarkGray