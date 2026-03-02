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
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Get-MaxWriteTimeUtc([string[]]$paths) {
  $max = [DateTime]::MinValue
  foreach ($p in $paths) {
    if (Test-Path -LiteralPath $p) {
      $t = (Get-Item -LiteralPath $p).LastWriteTimeUtc
      if ($t -gt $max) { $max = $t }
    }
  }
  return $max
}

$pack = (Resolve-Path $PackDir).Path

$video      = Join-Path $pack "video.mp4"
$videoSubs  = Join-Path $pack "video_subtitles.mp4"
$videoMusic = Join-Path $pack "video_music_auto.mp4"
$videoFinal = Join-Path $pack "video_final.mp4"

# 1) Base + subs (replay-strict: no regenera si ya existen)
$needBase = $false
if (!(Test-Path -LiteralPath $video)) {
  $needBase = $true
} else {
  $srtPath = Join-Path $pack "subtitles.srt"
  if ((Test-Path -LiteralPath $srtPath) -and !(Test-Path -LiteralPath $videoSubs)) {
    $needBase = $true
  }
}

if ($needBase) {
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\finalize_pack_v03.ps1 `
    -PackDir $pack -W $W -H $H -Fps $Fps -Fit $Fit -SubsField auto
} else {
  Write-Host "INFO: Reusing existing base/subs outputs in pack (replay strict)." -ForegroundColor Yellow
}

if (!(Test-Path -LiteralPath $video)) { throw "Falta video.mp4 (no puedo continuar): $video" }

# Captura versión de ffmpeg (primer línea)
$ffver = $null
try { $ffver = (& ffmpeg -version 2>$null | Select-Object -First 1) } catch { $ffver = $null }

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

  # Ducking + limiter (evita clipping)
  $filter = @"
[1:a:0]volume=${MusicVolume}[m];
[m][0:a]sidechaincompress=ratio=${DuckingRatio}:threshold=0.02:attack=5:release=200[md];
[0:a][md]amix=inputs=2:weights=1 1:normalize=0[mx];
[mx]alimiter=limit=0.98[aout]
"@.Trim()

  # REGLA: si pasas -MusicFile, SIEMPRE regenerar music/final (MusicVolume/DuckingRatio pueden cambiar)
  if (Test-Path -LiteralPath $videoMusic) { Remove-Item -LiteralPath $videoMusic -Force }
  if (Test-Path -LiteralPath $videoFinal) { Remove-Item -LiteralPath $videoFinal -Force }

  # Nota: el MP3 puede traer portada (attached pic) como stream de video: se descarta con -vn en el input de música.
  & ffmpeg -hide_banner -loglevel error -y `
    -i $baseForMusic `
    -stream_loop -1 -vn -i $music `
    -filter_complex $filter `
    -map 0:v:0 -map "[aout]" `
    -c:v copy `
    -c:a aac -b:a 192k -ar 44100 -ac 2 `
    -shortest `
    -movflags +faststart `
    -map_metadata -1 -map_chapters -1 `
    $videoMusic

  if (!(Test-Path -LiteralPath $videoMusic)) { throw "No se generó video_music_auto.mp4" }

  # Por ahora video_final = video_music_auto
  Copy-Item -LiteralPath $videoMusic -Destination $videoFinal -Force
  if (!(Test-Path -LiteralPath $videoFinal)) { throw "No se generó video_final.mp4" }

  Write-Host "OK: video_music_auto.mp4 y video_final.mp4 regenerados" -ForegroundColor Green
} else {
  Write-Host "INFO: MusicFile vacío, se omite música. (solo video.mp4 / video_subtitles.mp4)" -ForegroundColor Yellow
}

# 3) ZIP final + SHA256 + HANDOFF_READY.txt (re-empaquetar solo si hace falta)
$zipPath = Join-Path $pack $ZipName
$shaFile = "$zipPath.sha256.txt"
$handoff = Join-Path $pack "HANDOFF_READY.txt"

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

# ZIP: re-empaqueta solo si falta o si algún input es más nuevo
$needZip = $false
if (!(Test-Path -LiteralPath $zipPath)) {
  $needZip = $true
} else {
  $zipTime = (Get-Item -LiteralPath $zipPath).LastWriteTimeUtc
  $maxIn   = Get-MaxWriteTimeUtc $include
  if ($maxIn -gt $zipTime) { $needZip = $true }
}

if ($needZip) {
  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
  Compress-Archive -LiteralPath $include -DestinationPath $zipPath -Force
  Write-Host "INFO: ZIP actualizado por cambios en outputs." -ForegroundColor Yellow
} else {
  Write-Host "INFO: Reusing existing zip: $zipPath" -ForegroundColor Yellow
}

# SHA: si falta o si el zip cambió (timestamp)
$needSha = $false
if (!(Test-Path -LiteralPath $shaFile)) {
  $needSha = $true
} else {
  $shaTime = (Get-Item -LiteralPath $shaFile).LastWriteTimeUtc
  $zipTime = (Get-Item -LiteralPath $zipPath).LastWriteTimeUtc
  if ($zipTime -gt $shaTime) { $needSha = $true }
}

if ($needSha) {
  $zh = Get-FileHash -Algorithm SHA256 $zipPath
  @(
    "FILE: $($zh.Path)"
    "SHA256: $($zh.Hash)"
  ) | Set-Content -Encoding UTF8 $shaFile
} else {
  Write-Host "INFO: Reusing existing sha file: $shaFile" -ForegroundColor Yellow
}

# HANDOFF: si falta o si el zip cambió (timestamp)
$needHandoff = $false
if (!(Test-Path -LiteralPath $handoff)) {
  $needHandoff = $true
} else {
  $hTime  = (Get-Item -LiteralPath $handoff).LastWriteTimeUtc
  $zTime  = (Get-Item -LiteralPath $zipPath).LastWriteTimeUtc
  if ($zTime -gt $hTime) { $needHandoff = $true }
}

if ($needHandoff) {
  $zh = Get-FileHash -Algorithm SHA256 $zipPath
  $lines = @()
  $lines += "HANDOFF_READY"
  $lines += "PACK: $pack"
  $lines += "ZIP: $zipPath"
  $lines += "ZIP_SHA256: $($zh.Hash)"
  if ($ffver) { $lines += ("FFMPEG: " + $ffver) }
  $lines += ""
  $lines += "OUTPUTS:"
  $lines += ($include | ForEach-Object { " - " + $_ })

  $lines | Set-Content -Encoding UTF8 $handoff
} else {
  Write-Host "INFO: Reusing existing handoff file: $handoff" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "OK: ZIP + SHA256 + HANDOFF_READY.txt" -ForegroundColor Green
Write-Host "ZIP: $zipPath"
Write-Host "SHA: $shaFile"
Write-Host "TXT: $handoff"
