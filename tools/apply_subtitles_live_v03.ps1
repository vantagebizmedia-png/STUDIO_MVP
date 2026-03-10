param(
  [Parameter(Mandatory=$false)][string]$LiveDir,
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Fail([string]$m) {
  throw "APPLY_SUBTITLES_LIVE_V03 FAIL: $m"
}

function Get-VideoDimensions {
  param(
    [Parameter(Mandatory=$true)][string]$VideoPath
  )

  $ffprobeJson = & ffprobe `
    -v error `
    -select_streams v:0 `
    -show_entries stream=width,height `
    -of json `
    $VideoPath

  if ($LASTEXITCODE -ne 0) {
    Fail "ffprobe falló leyendo dimensiones de video"
  }

  if ([string]::IsNullOrWhiteSpace($ffprobeJson)) {
    Fail "ffprobe no devolvió dimensiones"
  }

  $obj = $ffprobeJson | ConvertFrom-Json
  $streams = @($obj.streams)
  if ($streams.Count -lt 1) {
    Fail "ffprobe no encontró stream de video"
  }

  $stream0 = $streams[0]
  $wProp = $stream0.PSObject.Properties["width"]
  $hProp = $stream0.PSObject.Properties["height"]

  if ($null -eq $wProp -or $null -eq $wProp.Value) {
    Fail "ffprobe no devolvió width"
  }
  if ($null -eq $hProp -or $null -eq $hProp.Value) {
    Fail "ffprobe no devolvió height"
  }

  return [pscustomobject]@{
    Width  = [int]$wProp.Value
    Height = [int]$hProp.Value
  }
}

function Get-SubtitleStyle {
  param(
    [Parameter(Mandatory=$true)][int]$VideoWidth,
    [Parameter(Mandatory=$true)][int]$VideoHeight
  )

  $fontSize = [int][Math]::Round($VideoHeight * 0.027)
  if ($fontSize -lt 34) { $fontSize = 34 }
  if ($fontSize -gt 56) { $fontSize = 56 }

  $marginV = [int][Math]::Round($VideoHeight * 0.075)
  if ($marginV -lt 70) { $marginV = 70 }
  if ($marginV -gt 180) { $marginV = 180 }

  $outline = 3
  $shadow = 0
  $alignment = 2
  $bold = 1

  return [pscustomobject]@{
    FontSize  = $fontSize
    MarginV   = $marginV
    Outline   = $outline
    Shadow    = $shadow
    Alignment = $alignment
    Bold      = $bold
  }
}

if (-not $LiveDir -or $LiveDir.Trim().Length -eq 0) {
  if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) {
    Fail "Falta -LiveDir o -WorkspaceRoot"
  }
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}

$live = (Resolve-Path $LiveDir).Path

$videoBase = Join-Path $live "video.mp4"
$srtFile   = Join-Path $live "captions_v03.srt"
$outVideo  = Join-Path $live "video_subs.mp4"

if (-not (Test-Path -LiteralPath $videoBase)) {
  Fail "Falta video base: $videoBase"
}

if (-not (Test-Path -LiteralPath $srtFile)) {
  Fail "Falta SRT: $srtFile"
}

$dims = Get-VideoDimensions -VideoPath $videoBase
$style = Get-SubtitleStyle -VideoWidth $dims.Width -VideoHeight $dims.Height

$srtFileFF = ($srtFile -replace '\\','/') -replace ':','\:'

$subtitleStyle = @(
  "Fontsize=$($style.FontSize)"
  "Outline=$($style.Outline)"
  "Shadow=$($style.Shadow)"
  "MarginV=$($style.MarginV)"
  "Alignment=$($style.Alignment)"
  "Bold=$($style.Bold)"
) -join ','

$subtitleFilter = "subtitles='$srtFileFF':force_style='$subtitleStyle'"

Write-Host "Aplicando burn-in de subtítulos..." -ForegroundColor Cyan
Write-Host "LIVE      : $live"
Write-Host "Base      : $videoBase"
Write-Host "SRT       : $srtFile"
Write-Host "Out       : $outVideo"
Write-Host "VideoW    : $($dims.Width)"
Write-Host "VideoH    : $($dims.Height)"
Write-Host "Fontsize  : $($style.FontSize)"
Write-Host "MarginV   : $($style.MarginV)"
Write-Host "Outline   : $($style.Outline)"
Write-Host "Shadow    : $($style.Shadow)"
Write-Host "Alignment : $($style.Alignment)"
Write-Host "Bold      : $($style.Bold)"

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
  $outVideo

if ($LASTEXITCODE -ne 0) {
  Fail "ffmpeg falló aplicando subtítulos"
}

if (-not (Test-Path -LiteralPath $outVideo)) {
  Fail "No se generó el archivo esperado: $outVideo"
}

$len = (Get-Item -LiteralPath $outVideo).Length
Write-Host ("OK: subtítulos aplicados -> {0} bytes" -f $len) -ForegroundColor Green
