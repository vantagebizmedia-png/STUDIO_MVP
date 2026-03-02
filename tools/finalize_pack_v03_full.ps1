param(
  [Parameter(Mandatory=$true)][string]$PackDir,

  # Scene Builder
  [int]$MaxScenes = 6,

  # Subtitles style
  [string]$SrtName = "captions_v03.srt",
  [int]$FontSize = 52,
  [int]$MarginV  = 120,
  [int]$Outline  = 3,

  # Music (pasa tal cual a tu finalize estable)
  [string]$MusicFile = "",
  [double]$MusicVolume = 0.22,
  [double]$DuckingRatio = 8.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path
$pack = (Resolve-Path $PackDir).Path

$manifest = Join-Path $pack "manifest_v03.json"
if (-not (Test-Path $manifest)) { throw "Falta manifest_v03.json en: $pack" }

# 0) Paths
$applyScenes = Join-Path $repo "tools\apply_scene_builder_v03.ps1"
$applySubs   = Join-Path $repo "tools\apply_subtitles_v03.ps1"
$finalMusic  = Join-Path $repo "tools\finalize_pack_v03_music.ps1"

if (-not (Test-Path $applyScenes)) { throw "Falta: $applyScenes" }
if (-not (Test-Path $applySubs))   { throw "Falta: $applySubs" }
if (-not (Test-Path $finalMusic))  { throw "Falta: $finalMusic" }

# 1) Ensure scenes_v03
$m = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $m.scenes_v03) {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $applyScenes -PackDir $pack -MaxScenes $MaxScenes
}

# 2) Ensure subtitles outputs
$srtPath = Join-Path $pack $SrtName
$vidSubs = Join-Path $pack "video_subtitles.mp4"

if (-not (Test-Path $srtPath) -or -not (Test-Path $vidSubs)) {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $applySubs -PackDir $pack -SrtName $SrtName -FontSize $FontSize -MarginV $MarginV -Outline $Outline
}

# 3) Music + finalize/handoff (tu script estable)
if ($MusicFile -and $MusicFile.Trim().Length -gt 0) {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $finalMusic `
    -PackDir $pack `
    -MusicFile $MusicFile `
    -MusicVolume $MusicVolume `
    -DuckingRatio $DuckingRatio
} else {
  # Si no pasas MusicFile, corre finalize sin música (si tu script lo permite).
  # Si tu finalize requiere MusicFile, entonces simplemente omite este else.
  pwsh -NoProfile -ExecutionPolicy Bypass -File $finalMusic -PackDir $pack
}

Write-Host "OK: finalize_pack_v03_full (scenes_v03 + subtitles + music/handoff) Pack=$pack" -ForegroundColor Green
