param(
  [Parameter(Mandatory=$true)][string]$PackDir,
  [int]$MaxScenes = 6,

  # Subtitles style
  [string]$SrtName = "captions_v03.srt",
  [int]$FontSize = 52,
  [int]$MarginV  = 120,
  [int]$Outline  = 3,

  # Music (opcional)
  [string]$MusicFile = "",
  [double]$MusicVolume = 0.22,
  [double]$DuckingRatio = 8.0,

  [switch]$ExpectMusic
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path
$pack = (Resolve-Path $PackDir).Path

$full = Join-Path $repo "tools\finalize_pack_v03_full.ps1"
if (-not (Test-Path $full)) { throw "Falta: $full" }

# 1) Corre finalize full
if ($MusicFile -and $MusicFile.Trim().Length -gt 0) {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $full `
    -PackDir $pack `
    -MaxScenes $MaxScenes `
    -SrtName $SrtName -FontSize $FontSize -MarginV $MarginV -Outline $Outline `
    -MusicFile $MusicFile -MusicVolume $MusicVolume -DuckingRatio $DuckingRatio
} else {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $full `
    -PackDir $pack `
    -MaxScenes $MaxScenes `
    -SrtName $SrtName -FontSize $FontSize -MarginV $MarginV -Outline $Outline
}

# 2) Reusa smoke existente
$sm = Join-Path $repo "tools\smoke_finalize_pack_v03.ps1"
if (-not (Test-Path $sm)) { throw "Falta: $sm" }

if ($ExpectMusic) {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $sm -PackDir $pack -ExpectMusic
} else {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $sm -PackDir $pack
}

Write-Host "SMOKE OK: finalize_full_v03 (full pipeline + handoff). pack=$pack expectMusic=$ExpectMusic" -ForegroundColor Green
