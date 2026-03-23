param(
  [Parameter(Mandatory=$true)][string]$LiveDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$psUtf8Compat = Join-Path $PSScriptRoot "ps_utf8_compat_v03.ps1"
if (-not (Test-Path -LiteralPath $psUtf8Compat -PathType Leaf)) {
  throw ("No existe helper utf8 compat: {0}" -f $psUtf8Compat)
}

. $psUtf8Compat

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
  Write-Host "Música detectada. Mezclando audio real..." -ForegroundColor Cyan

  $tmpMusic = Join-Path $live "_tmp_music_auto.mp4"
  if (Test-Path -LiteralPath $tmpMusic) {
    Remove-Item -LiteralPath $tmpMusic -Force
  }

  # Mix determinista:
  # - audio principal del video_subs al frente
  # - música más baja
  # - duración final = shortest (la del video)
  # - reencode video+audio para salida estable
  $filter = "[1:a]volume=0.12[a1];[0:a][a1]amix=inputs=2:duration=first:dropout_transition=0,volume=2[aout]"

  & ffmpeg -hide_banner -loglevel error -y `
    -i $videoSubs `
    -stream_loop -1 -i $music `
    -filter_complex $filter `
    -map 0:v:0 `
    -map "[aout]" `
    -c:v libx264 `
    -preset medium `
    -crf 18 `
    -pix_fmt yuv420p `
    -c:a aac `
    -b:a 192k `
    -ar 44100 `
    -ac 2 `
    -shortest `
    -movflags +faststart `
    -map_metadata -1 `
    -map_chapters -1 `
    $tmpMusic

  if ($LASTEXITCODE -ne 0) {
    Fail "ffmpeg falló mezclando música"
  }

  if (-not (Test-Path -LiteralPath $tmpMusic)) {
    Fail "No se generó salida temporal con música"
  }

  Move-Item -LiteralPath $tmpMusic -Destination $videoMusicAuto -Force
  Copy-Item -LiteralPath $videoMusicAuto -Destination $videoFinal -Force

  Write-Host "OK: video_music_auto.mp4 generado con mezcla real" -ForegroundColor Green
  Write-Host "OK: video_final.mp4 sincronizado desde video_music_auto.mp4" -ForegroundColor Green
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
