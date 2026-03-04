param(
  [Parameter(Mandatory=$true)][string]$PackDir,
  [int]$W = 1080,
  [int]$H = 1920,
  [int]$Fps = 30,
  [ValidateSet("crop","contain")][string]$Fit = "crop",

  # Música: ruta a un mp3/wav (si no, solo deja video.mp4 y video_subtitles.mp4)
  [string]$MusicFile = "",

  # Volumen música (0.0..1.0 típico)
  [double]$MusicVolume = 0.25,

  # Ducking simple: baja música cuando hay voz.
  # ratio mayor => más ducking.
  [double]$DuckingRatio = 8.0,

  # Empaquetado final
  [string]$ZipName = "pack.final_delivery.zip"
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$pack = (Resolve-Path $PackDir).Path

# 1) Siempre genera base + subs (si hay SRT)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\finalize_pack_v03.ps1 `
  -PackDir $pack -W $W -H $H -Fps $Fps -Fit $Fit -SubsField auto

$video      = Join-Path $pack "video.mp4"
$videoSubs  = Join-Path $pack "video_subtitles.mp4"
$videoMusic = Join-Path $pack "video_music_auto.mp4"
$videoFinal = Join-Path $pack "video_final.mp4"

if (!(Test-Path -LiteralPath $video)) { throw "Falta video.mp4 (no puedo continuar): $video" }

# 2) Música (opcional)
if ($MusicFile -and $MusicFile.Trim().Length -gt 0) {
  $music = (Resolve-Path $MusicFile).Path
  if (!(Test-Path -LiteralPath $music)) { throw "MusicFile no existe: $music" }

  # Si existe video_subtitles, usamos ese como base para el final con música.
  $baseForMusic = $video
  if (Test-Path -LiteralPath $videoSubs) { $baseForMusic = $videoSubs }

  Write-Host ""
  Write-Host "MUSIC: $music"
  Write-Host "BASE : $baseForMusic"
  Write-Host "OUT  : $videoMusic"
  Write-Host ""

  # Ducking simple con sidechaincompress:
  # - Stream 0: voz/video (incluye audio de voz)
  # - Stream 1: música
  # Mezcla: música atenuada por voz
  $ff = "ffmpeg"

  $filter = @"
[1:a]volume=${MusicVolume}[m];
[m][0:a]sidechaincompress=ratio=${DuckingRatio}:threshold=0.02:attack=5:release=200[md];
[0:a][md]amix=inputs=2:weights=1 1:normalize=0[aout]
"@.Trim()

  & $ff -hide_banner -y `
    -i $baseForMusic `
    -stream_loop -1 -i $music `
    -filter_complex $filter `
    -map 0:v:0 -map "[aout]" `
    -c:v copy `
    -c:a aac -b:a 192k -ar 44100 -ac 2 `
    -shortest `
    -movflags +faststart `
    -map_metadata -1 -map_chapters -1 `
    $videoMusic

  if (!(Test-Path -LiteralPath $videoMusic)) { throw "No se generó video_music_auto.mp4" }

  # Por ahora video_final = video_music_auto (placeholder limpio)
  Copy-Item -LiteralPath $videoMusic -Destination $videoFinal -Force
  Write-Host "OK: video_music_auto.mp4 y video_final.mp4 creados" -ForegroundColor Green
} else {
  Write-Host "INFO: MusicFile vacío, se omite música. (solo video.mp4 / video_subtitles.mp4)" -ForegroundColor Yellow
}

# 3) ZIP final + SHA256 + HANDOFF_READY.txt
$zipPath = Join-Path $pack $ZipName
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

# Incluye outputs “importantes” si existen
$include = @()
$include += $video
if (Test-Path -LiteralPath $videoSubs)  { $include += $videoSubs }
if (Test-Path -LiteralPath $videoMusic) { $include += $videoMusic }
if (Test-Path -LiteralPath $videoFinal) { $include += $videoFinal }

# Logs si existen
$log1 = Join-Path $pack "render_last.log"
$log2 = Join-Path $pack "subs_make_last.log"
$log3 = Join-Path $pack "burn_subs_last.log"
if (Test-Path -LiteralPath $log1) { $include += $log1 }
if (Test-Path -LiteralPath $log2) { $include += $log2 }
if (Test-Path -LiteralPath $log3) { $include += $log3 }

# Manifest si existe
$m1 = Join-Path $pack "manifest_v03.json"
$m2 = Join-Path $pack "manifest.json"
if (Test-Path -LiteralPath $m1) { $include += $m1 } elseif (Test-Path -LiteralPath $m2) { $include += $m2 }

Compress-Archive -LiteralPath $include -DestinationPath $zipPath -Force

$zh = Get-FileHash -Algorithm SHA256 $zipPath
$shaFile = "$zipPath.sha256.txt"
@(
  "FILE: $($zh.Path)"
  "SHA256: $($zh.Hash)"
) | Set-Content -Encoding UTF8 $shaFile

$handoff = Join-Path $pack "HANDOFF_READY.txt"
@(
  "HANDOFF_READY"
  "PACK: $pack"
  "ZIP: $zipPath"
  "ZIP_SHA256: $($zh.Hash)"
  ""
  "OUTPUTS:"
  ($include | ForEach-Object { " - " + $_ })
) | Set-Content -Encoding UTF8 $handoff

Write-Host ""
Write-Host "OK: ZIP + SHA256 + HANDOFF_READY.txt" -ForegroundColor Green
Write-Host "ZIP: $zipPath"
Write-Host "SHA: $shaFile"
Write-Host "TXT: $handoff"

