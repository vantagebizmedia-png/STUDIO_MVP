param(
  [Parameter(Mandatory=$true)][string]$PackDir,
  [int]$W = 1080,
  [int]$H = 1920,
  [int]$Fps = 30,
  [ValidateSet("crop","contain")][string]$Fit = "crop",
  [ValidateSet("auto","none")][string]$SubsField = "auto"
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$pack = (Resolve-Path $PackDir).Path

$video = Join-Path $pack "video.mp4"
$srt   = Join-Path $pack "subtitles.srt"
$vidSub= Join-Path $pack "video_subtitles.mp4"

$logRender = Join-Path $pack "render_last.log"
$logSubs   = Join-Path $pack "subs_make_last.log"
$logBurn   = Join-Path $pack "burn_subs_last.log"

Write-Host "PACK : $pack"
Write-Host "W/H  : $W x $H   FPS: $Fps   FIT: $Fit"
Write-Host "VIDEO: $video"
Write-Host "SRT  : $srt"
Write-Host "VSUB : $vidSub"
Write-Host ""

# 0) Validaciones mínimas
if (!(Test-Path -LiteralPath $pack)) { throw "PackDir no existe: $pack" }
if (!(Test-Path -LiteralPath (Join-Path $pack "manifest_v03.json")) -and !(Test-Path -LiteralPath (Join-Path $pack "manifest.json"))) {
  Write-Host "WARN: no encontré manifest_v03.json/manifest.json en el pack (sigo igual)." -ForegroundColor Yellow
}

# 1) Render base -> video.mp4
python -u tools\render_pack_v03.py --pack-dir $pack --w $W --h $H --fps $Fps --fit $Fit 2>&1 |
  Tee-Object $logRender

if (!(Test-Path -LiteralPath $video)) {
  throw "No se generó video.mp4 en: $pack"
}

# 2) Genera subtitles.srt si falta
if (!(Test-Path -LiteralPath $srt)) {
  Write-Host "INFO: no existe subtitles.srt, generando..." -ForegroundColor Yellow
  python -u tools\make_subtitles_from_pack_v03.py --pack $pack --output $srt --field $SubsField 2>&1 |
    Tee-Object $logSubs
} else {
  Write-Host "OK: subtitles.srt ya existe (no regenero)." -ForegroundColor Green
}

# 3) Burn-in subs -> video_subtitles.mp4 si existe SRT
if (Test-Path -LiteralPath $srt) {
  python -u tools\burn_subtitles.py --video $video --srt $srt --output $vidSub 2>&1 |
    Tee-Object $logBurn

  if (Test-Path -LiteralPath $vidSub) {
    Write-Host "OK: video_subtitles.mp4 creado" -ForegroundColor Green
  } else {
    throw "Falló burn_subtitles: no existe $vidSub"
  }
} else {
  Write-Host "INFO: no existe subtitles.srt, se omite burn-in" -ForegroundColor Yellow
}

Write-Host ""
Get-ChildItem $pack -Filter "video*.mp4" | Select-Object Name,Length
