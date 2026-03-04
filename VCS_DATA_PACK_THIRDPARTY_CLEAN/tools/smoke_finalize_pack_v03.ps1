param(
  [Parameter(Mandatory=$true)][string]$PackDir,
  [switch]$ExpectMusic
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$pack = (Resolve-Path $PackDir).Path

function Assert-Exists([string]$p) {
  if (!(Test-Path -LiteralPath $p)) { throw "SMOKE FAIL: falta $p" }
  Write-Host "OK: $p" -ForegroundColor Green
}

$video = Join-Path $pack "video.mp4"
Assert-Exists $video

$srt = Join-Path $pack "subtitles.srt"
if (Test-Path -LiteralPath $srt) {
  $vsub = Join-Path $pack "video_subtitles.mp4"
  Assert-Exists $vsub
} else {
  Write-Host "INFO: no hay subtitles.srt (ok si el pack no trae subs)" -ForegroundColor Yellow
}

if ($ExpectMusic) {
  Assert-Exists (Join-Path $pack "video_music_auto.mp4")
  Assert-Exists (Join-Path $pack "video_final.mp4")
}

Assert-Exists (Join-Path $pack "pack.final_delivery.zip")
Assert-Exists (Join-Path $pack "pack.final_delivery.zip.sha256.txt")
Assert-Exists (Join-Path $pack "HANDOFF_READY.txt")

Write-Host ""
Write-Host "SMOKE OK" -ForegroundColor Green
