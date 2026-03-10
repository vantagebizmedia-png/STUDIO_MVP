param(
  [Parameter(Mandatory=$false)][string]$LiveDir,
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

if (-not $LiveDir -or $LiveDir.Trim().Length -eq 0) {
  if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) {
    throw "Falta -LiveDir o -WorkspaceRoot"
  }
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}

$live = (Resolve-Path $LiveDir).Path

$videoBase = Join-Path $live "video.mp4"
$srtFile   = Join-Path $live "captions_v03.srt"
$outVideo  = Join-Path $live "video_subs.mp4"

if (-not (Test-Path -LiteralPath $videoBase)) {
  throw "Falta video base: $videoBase"
}

if (-not (Test-Path -LiteralPath $srtFile)) {
  throw "Falta SRT: $srtFile"
}

$videoBaseFF = $videoBase -replace '\\','/'
$srtFileFF   = ($srtFile -replace '\\','/') -replace ':','\:'
$outVideoFF  = $outVideo

$subtitleFilter = "subtitles='$srtFileFF':force_style='FontName=Arial,Fontsize=18,Outline=1,Shadow=0,MarginV=110,Alignment=2'"

Write-Host "Aplicando burn-in de subtítulos..."
Write-Host "LIVE : $live"
Write-Host "Base : $videoBase"
Write-Host "SRT  : $srtFile"
Write-Host "Out  : $outVideo"

if (Test-Path -LiteralPath $outVideo) {
  Remove-Item -LiteralPath $outVideo -Force -ErrorAction SilentlyContinue
}

& ffmpeg `
  -y `
  -i $videoBase `
  -vf $subtitleFilter `
  -c:v libx264 `
  -pix_fmt yuv420p `
  -preset veryfast `
  -crf 18 `
  -c:a copy `
  $outVideoFF

if ($LASTEXITCODE -ne 0) {
  throw "ffmpeg falló aplicando subtítulos"
}

if (-not (Test-Path -LiteralPath $outVideo)) {
  throw "No se generó el archivo esperado: $outVideo"
}

$len = (Get-Item -LiteralPath $outVideo).Length
Write-Host ("OK: subtítulos aplicados -> {0} bytes" -f $len) -ForegroundColor Green