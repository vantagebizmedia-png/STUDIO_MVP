param(
  [Parameter(Mandatory=$true)][string]$PackDir,
  [int]$W = 1080,
  [int]$H = 1920,
  [int]$Fps = 30,
  [ValidateSet("crop","contain")][string]$Fit = "crop"
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$pack  = (Resolve-Path $PackDir).Path
$video = Join-Path $pack "video.mp4"
$srt   = Join-Path $pack "subtitles.srt"
$out   = Join-Path $pack "video_subtitles.mp4"

Write-Host "PACK : $pack"
Write-Host "VIDEO: $video"
Write-Host "SRT  : $srt"
Write-Host "OUT  : $out"

# 1) Render base
python -u tools\render_pack_v03.py --pack-dir $pack --w $W --h $H --fps $Fps --fit $Fit 2>&1 |
  Tee-Object (Join-Path $pack "render_last.log")

if (!(Test-Path -LiteralPath $video)) {
  throw "No se generó video.mp4 en: $pack"
}

# 2) Burn-in subtitles si existe
if (Test-Path -LiteralPath $srt) {
  python -u tools\burn_subtitles.py --video $video --srt $srt --output $out 2>&1 |
    Tee-Object (Join-Path $pack "burn_subs_last.log")

  if (Test-Path -LiteralPath $out) {
    Write-Host "OK: video_subtitles.mp4 creado" -ForegroundColor Green
  } else {
    throw "Falló burn_subtitles: no existe $out"
  }
} else {
  Write-Host "INFO: no existe subtitles.srt, se omite burn-in" -ForegroundColor Yellow
}

Get-ChildItem $pack -Filter "video*.mp4" | Select-Object Name,Length
