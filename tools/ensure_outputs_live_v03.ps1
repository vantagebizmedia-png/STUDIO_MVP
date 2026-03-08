param(
  [Parameter(Mandatory=$false)][string]$LiveDir,
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Resolve-LiveDir {
  param(
    [string]$LiveDir,
    [string]$WorkspaceRoot
  )

  if ($LiveDir -and $LiveDir.Trim().Length -gt 0) {
    return (Resolve-Path $LiveDir).Path
  }

  if ($WorkspaceRoot -and $WorkspaceRoot.Trim().Length -gt 0) {
    $candidate = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
    return (Resolve-Path $candidate).Path
  }

  throw "Falta -LiveDir o -WorkspaceRoot"
}

function Resolve-MusicFile {
  param([Parameter(Mandatory=$true)][string]$LiveDir)

  $candidates = @(
    (Join-Path $LiveDir "music\track.mp3"),
    (Join-Path $LiveDir "music\music.mp3"),
    (Join-Path $LiveDir "artifacts\music.mp3"),
    (Join-Path $LiveDir "track.mp3")
  )

  foreach ($p in $candidates) {
    if (Test-Path -LiteralPath $p) {
      return $p
    }
  }

  return $null
}

$live = Resolve-LiveDir -LiveDir $LiveDir -WorkspaceRoot $WorkspaceRoot

$videoBase   = Join-Path $live "video.mp4"
$videoSubs   = Join-Path $live "video_subs.mp4"
$videoFinal  = Join-Path $live "video_final.mp4"

$legacySubs1 = Join-Path $live "video_subtitles.mp4"
$legacySubs2 = Join-Path $live "video_music_auto.mp4"

if (-not (Test-Path -LiteralPath $videoBase)) {
  throw "Falta video base: $videoBase"
}

$subtitleBase = $null
if (Test-Path -LiteralPath $videoSubs) {
  $subtitleBase = $videoSubs
} else {
  $subtitleBase = $videoBase
}

$musicFile = Resolve-MusicFile -LiveDir $live

Write-Host "== ENSURE OUTPUTS LIVE v0.3 ==" -ForegroundColor Cyan
Write-Host "LIVE         : $live"
Write-Host "VIDEO_BASE   : $videoBase"
Write-Host "VIDEO_SUBS   : $videoSubs"
Write-Host "SUBTITLE_BASE: $subtitleBase"
Write-Host "MUSIC        : $musicFile"
Write-Host "VIDEO_FINAL  : $videoFinal"

if (Test-Path -LiteralPath $videoFinal) {
  Remove-Item -LiteralPath $videoFinal -Force -ErrorAction SilentlyContinue
}

if ($musicFile) {
  Write-Host "Generando video_final.mp4 con música..." -ForegroundColor Yellow

  & ffmpeg `
    -y `
    -i $subtitleBase `
    -i $musicFile `
    -filter_complex "[1:a]volume=0.12[a1];[0:a][a1]amix=inputs=2:duration=first:dropout_transition=2" `
    -c:v copy `
    -c:a aac `
    -b:a 192k `
    $videoFinal

  if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg falló mezclando música"
  }
}
else {
  Write-Host "No hay música. Copiando base subtitulada a video_final.mp4..." -ForegroundColor Yellow
  Copy-Item -LiteralPath $subtitleBase -Destination $videoFinal -Force
}

if (-not (Test-Path -LiteralPath $videoFinal)) {
  throw "No se generó video_final.mp4"
}

if (Test-Path -LiteralPath $legacySubs1) {
  Remove-Item -LiteralPath $legacySubs1 -Force -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $legacySubs2) {
  Remove-Item -LiteralPath $legacySubs2 -Force -ErrorAction SilentlyContinue
}

$baseLen  = (Get-Item -LiteralPath $videoBase).Length
$finalLen = (Get-Item -LiteralPath $videoFinal).Length

Write-Host "OK outputs asegurados" -ForegroundColor Green
Write-Host ("  video.mp4       -> {0} bytes" -f $baseLen)
Write-Host ("  video_final.mp4 -> {0} bytes" -f $finalLen)
if (Test-Path -LiteralPath $videoSubs) {
  $subsLen = (Get-Item -LiteralPath $videoSubs).Length
  Write-Host ("  video_subs.mp4  -> {0} bytes (intermedio)" -f $subsLen)
}