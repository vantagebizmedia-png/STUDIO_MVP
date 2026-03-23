param(
  [Parameter(Mandatory=$true)][string]$InVideo,
  [Parameter(Mandatory=$true)][string]$MusicBed,
  [Parameter(Mandatory=$true)][string]$OutVideo,
  [double]$MusicVolume = 0.18
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$psUtf8Compat = Join-Path $PSScriptRoot "ps_utf8_compat_v03.ps1"
if (-not (Test-Path -LiteralPath $psUtf8Compat -PathType Leaf)) {
  throw ("No existe helper utf8 compat: {0}" -f $psUtf8Compat)
}

. $psUtf8Compat

if (-not (Test-Path -LiteralPath $InVideo)) { throw "Falta InVideo: $InVideo" }
if (-not (Test-Path -LiteralPath $MusicBed)) { throw "Falta MusicBed: $MusicBed" }

$inV = (Resolve-Path -LiteralPath $InVideo).Path
$bed = (Resolve-Path -LiteralPath $MusicBed).Path

# mix estable:
# - stream 0 = audio original del video
# - stream 1 = music bed, loopeado si hace falta
# - volumen suave fijo
# - duración final sigue al video
# - sin ducking dinámico todavía
$filter = "[1:a]volume=$MusicVolume[a1];[0:a][a1]amix=inputs=2:duration=first:dropout_transition=0[aout]"

& ffmpeg -y -v error `
  -stream_loop -1 -i "$bed" `
  -i "$inV" `
  -filter_complex $filter `
  -map 1:v:0 `
  -map "[aout]" `
  -c:v copy `
  -c:a aac `
  -shortest `
  "$OutVideo"

if ($LASTEXITCODE -ne 0) {
  throw "ffmpeg mix falló"
}

if (-not (Test-Path -LiteralPath $OutVideo)) {
  throw "No se generó OutVideo: $OutVideo"
}

$len = (Get-Item -LiteralPath $OutVideo).Length
Write-Host ("OK: mix_music_into_video_v03 -> {0} ({1} bytes)" -f $OutVideo, $len) -ForegroundColor Green
