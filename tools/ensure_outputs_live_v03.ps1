param(
  [Parameter(Mandatory=$true)][string]$LiveDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Fail([string]$msg) { throw "ENSURE OUTPUTS FAIL: $msg" }

$live = (Resolve-Path $LiveDir).Path

$videoBase      = Join-Path $live "video.mp4"
$videoSubs      = Join-Path $live "video_subs.mp4"
$videoLegacySub = Join-Path $live "video_subtitles.mp4"
$videoMusicAuto = Join-Path $live "video_music_auto.mp4"
$videoFinal     = Join-Path $live "video_final.mp4"
$captionsV03    = Join-Path $live "captions_v03.srt"

# Música opcional conocida
$musicCandidates = @(
  (Join-Path $live "music.wav"),
  (Join-Path $live "music.mp3"),
  (Join-Path $live "artifacts\music.wav"),
  (Join-Path $live "artifacts\music.mp3")
)
$music = $musicCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

Write-Host "== ENSURE OUTPUTS LIVE v0.3 =="
Write-Host "LIVE         : $live"
Write-Host "VIDEO_BASE   : $videoBase"
Write-Host "VIDEO_SUBS   : $videoSubs"
Write-Host "SUBTITLE_BASE: $videoSubs"
Write-Host "MUSIC        : $music"
Write-Host "VIDEO_MUSIC  : $videoMusicAuto"
Write-Host "VIDEO_FINAL  : $videoFinal"

if (-not (Test-Path -LiteralPath $videoBase)) {
  Fail "Falta video base: $videoBase"
}

if (-not (Test-Path -LiteralPath $captionsV03)) {
  Fail "Falta captions_v03.srt: $captionsV03"
}

# Compat: si existe legacy pero no existe canonical, lo copiamos
if ((-not (Test-Path -LiteralPath $videoSubs)) -and (Test-Path -LiteralPath $videoLegacySub)) {
  Copy-Item -LiteralPath $videoLegacySub -Destination $videoSubs -Force
  Write-Host "OK: video_subtitles.mp4 -> video_subs.mp4" -ForegroundColor Green
}

if (-not (Test-Path -LiteralPath $videoSubs)) {
  Fail "Falta video subtitulado base: $videoSubs"
}

# Mantener alias legacy sincronizado
Copy-Item -LiteralPath $videoSubs -Destination $videoLegacySub -Force

if ($music) {
  Write-Host "INFO: hay música detectada, pero este ensure no mezcla audio; conserva salidas existentes." -ForegroundColor Yellow

  if (-not (Test-Path -LiteralPath $videoMusicAuto)) {
    Copy-Item -LiteralPath $videoSubs -Destination $videoMusicAuto -Force
    Write-Host "WARN: video_music_auto.mp4 no existía; copiado desde video_subs.mp4 como fallback" -ForegroundColor Yellow
  }

  if (-not (Test-Path -LiteralPath $videoFinal)) {
    Copy-Item -LiteralPath $videoMusicAuto -Destination $videoFinal -Force
    Write-Host "WARN: video_final.mp4 no existía; copiado desde video_music_auto.mp4" -ForegroundColor Yellow
  }
}
else {
  Write-Host "No hay música. Copiando base subtitulada a video_music_auto.mp4 y video_final.mp4..." -ForegroundColor Yellow
  Copy-Item -LiteralPath $videoSubs -Destination $videoMusicAuto -Force
  Copy-Item -LiteralPath $videoSubs -Destination $videoFinal -Force
}

if (-not (Test-Path -LiteralPath $videoMusicAuto)) {
  Fail "No se logró asegurar video_music_auto.mp4"
}

if (-not (Test-Path -LiteralPath $videoFinal)) {
  Fail "No se logró asegurar video_final.mp4"
}

Write-Host "OK outputs asegurados" -ForegroundColor Green
Write-Host ("  video.mp4            -> {0} bytes" -f (Get-Item -LiteralPath $videoBase).Length)
Write-Host ("  video_subs.mp4       -> {0} bytes (intermedio)" -f (Get-Item -LiteralPath $videoSubs).Length)
Write-Host ("  video_subtitles.mp4  -> {0} bytes (alias legacy)" -f (Get-Item -LiteralPath $videoLegacySub).Length)
Write-Host ("  video_music_auto.mp4 -> {0} bytes" -f (Get-Item -LiteralPath $videoMusicAuto).Length)
Write-Host ("  video_final.mp4      -> {0} bytes" -f (Get-Item -LiteralPath $videoFinal).Length)