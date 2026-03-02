param(
  [string]$PackDir = "C:\Users\vanta\Documents\STUDIO_WORKSPACE\exports\pack_v03_359ac8c6_s01",
  [string]$SrtName = "captions_v03.srt"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$pack = (Resolve-Path $PackDir).Path
$manifest = Join-Path $pack "manifest_v03.json"
if (-not (Test-Path $manifest)) { throw "Falta manifest_v03.json en: $pack" }

$m = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $m.scenes_v03) { throw "manifest no tiene scenes_v03[] (corre Scene Builder primero)" }
$sc = @($m.scenes_v03)
if ($sc.Count -lt 1) { throw "scenes_v03[] vacío" }

$srt = Join-Path $pack $SrtName
if (-not (Test-Path $srt)) { throw "Falta SRT: $srt (corre apply_subtitles_v03.ps1)" }
if ( (Get-Item -LiteralPath $srt).Length -le 10 ) { throw "SRT vacío: $srt" }

$vid = Join-Path $pack "video_subtitles.mp4"
if (-not (Test-Path $vid)) { throw "Falta video_subtitles.mp4 (corre apply_subtitles_v03.ps1)" }
if ( (Get-Item -LiteralPath $vid).Length -lt 50000 ) { throw "video_subtitles.mp4 demasiado pequeño: $vid" }

Write-Host "SMOKE OK: Subtitles v03. pack=$pack srt=$SrtName scenes_v03=$($sc.Count)" -ForegroundColor Green
