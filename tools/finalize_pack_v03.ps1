param(
  [Parameter(Mandatory=$true)][string]$PackDir,
  [int]$W = 1080,
  [int]$H = 1920,
  [int]$Fps = 30,
  [ValidateSet("crop","contain")][string]$Fit = "crop",
  [ValidateSet("auto","none")][string]$SubsField = "auto"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$pack = (Resolve-Path $PackDir).Path

$video        = Join-Path $pack "video.mp4"
$captionsV03  = Join-Path $pack "captions_v03.srt"
$legacySrt    = Join-Path $pack "subtitles.srt"
$legacyVSub   = Join-Path $pack "video_subtitles.mp4"

$logRender = Join-Path $pack "render_last.log"
$logSubs   = Join-Path $pack "subs_make_last.log"

Write-Host "PACK         : $pack"
Write-Host "W/H          : $W x $H   FPS: $Fps   FIT: $Fit"
Write-Host "VIDEO        : $video"
Write-Host "CAPTIONS_V03 : $captionsV03"
Write-Host "LEGACY_SRT   : $legacySrt"
Write-Host ""

if (!(Test-Path -LiteralPath $pack)) {
  throw "PackDir no existe: $pack"
}

if (!(Test-Path -LiteralPath (Join-Path $pack "manifest_v03.json")) -and !(Test-Path -LiteralPath (Join-Path $pack "manifest.json"))) {
  Write-Host "WARN: no encontré manifest_v03.json/manifest.json en el pack (sigo igual)." -ForegroundColor Yellow
}

# 1) Render base limpio -> video.mp4
python -u tools\render_pack_v03.py --pack-dir $pack --w $W --h $H --fps $Fps --fit $Fit 2>&1 |
  Tee-Object $logRender

if (!(Test-Path -LiteralPath $video)) {
  throw "No se generó video.mp4 en: $pack"
}

Write-Host "OK: video.mp4 generado" -ForegroundColor Green

# 2) Resolver subtítulos canónicos -> captions_v03.srt
if (Test-Path -LiteralPath $captionsV03) {
  Write-Host "OK: captions_v03.srt ya existe (no regenero)." -ForegroundColor Green
}
elseif (Test-Path -LiteralPath $legacySrt) {
  Copy-Item -LiteralPath $legacySrt -Destination $captionsV03 -Force
  Write-Host "OK: subtitles.srt -> captions_v03.srt" -ForegroundColor Green
}
else {
  Write-Host "INFO: no existe captions_v03.srt/subtitles.srt, generando captions_v03.srt..." -ForegroundColor Yellow
  python -u tools\make_subtitles_from_pack_v03.py --pack $pack --output $captionsV03 --field $SubsField 2>&1 |
    Tee-Object $logSubs
}

if (!(Test-Path -LiteralPath $captionsV03)) {
  throw "No se generó captions_v03.srt en: $pack"
}

# 3) Compatibilidad legacy: mantener subtitles.srt sincronizado
if (!(Test-Path -LiteralPath $legacySrt)) {
  Copy-Item -LiteralPath $captionsV03 -Destination $legacySrt -Force
  Write-Host "OK: captions_v03.srt -> subtitles.srt (compat legacy)" -ForegroundColor Green
} else {
  Copy-Item -LiteralPath $captionsV03 -Destination $legacySrt -Force
  Write-Host "OK: subtitles.srt resincronizado desde captions_v03.srt" -ForegroundColor Green
}

# 4) Limpiar artefacto legacy con burn-in para evitar doble texto
if (Test-Path -LiteralPath $legacyVSub) {
  Remove-Item -LiteralPath $legacyVSub -Force -ErrorAction SilentlyContinue
  Write-Host "OK: eliminado legacy video_subtitles.mp4" -ForegroundColor Green
}

Write-Host ""
Get-ChildItem -LiteralPath $pack |
  Where-Object { $_.Name -in @("video.mp4","captions_v03.srt","subtitles.srt","video_subtitles.mp4") } |
  Select-Object Name,Length