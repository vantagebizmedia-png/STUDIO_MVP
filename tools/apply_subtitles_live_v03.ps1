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

  $fontSize = [int][Math]::Round($VideoHeight * 0.025)
  if ($fontSize -lt 34) { $fontSize = 34 }
  if ($fontSize -gt 50) { $fontSize = 50 }

  $marginV = [int][Math]::Round($VideoHeight * 0.092)
  if ($marginV -lt 110) { $marginV = 110 }
  if ($marginV -gt 220) { $marginV = 220 }

  $marginLR = [int][Math]::Round($VideoWidth * 0.070)
  if ($marginLR -lt 56) { $marginLR = 56 }
  if ($marginLR -gt 120) { $marginLR = 120 }

  $outline = 2
  $shadow = 0
  $alignment = 2
  $bold = 1
  $spacing = 0.2

  return [pscustomobject]@{
    FontSize   = $fontSize
    MarginV    = $marginV
    MarginL    = $marginLR
    MarginR    = $marginLR
    Outline    = $outline
    Shadow     = $shadow
    Alignment  = $alignment
    Bold       = $bold
    Spacing    = $spacing
    BorderStyle = 3
    PrimaryColour = "&H00FFFFFF"
    OutlineColour = "&H00141414"
    BackColour    = "&H7A000000"
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
  "MarginL=$($style.MarginL)"
  "MarginR=$($style.MarginR)"
  "Alignment=$($style.Alignment)"
  "Bold=$($style.Bold)"
  "Spacing=$($style.Spacing)"
  "BorderStyle=$($style.BorderStyle)"
  "PrimaryColour=$($style.PrimaryColour)"
  "OutlineColour=$($style.OutlineColour)"
  "BackColour=$($style.BackColour)"
) -join ','

$subtitleFilter = "subtitles='$srtFileFF':force_style='$subtitleStyle'"

Write-Host "Aplicando burn-in de subtítulos..." -ForegroundColor Cyan
Write-Host "LIVE         : $live"
Write-Host "Base         : $videoBase"
Write-Host "SRT          : $srtFile"
Write-Host "Out          : $outVideo"
Write-Host "VideoW       : $($dims.Width)"
Write-Host "VideoH       : $($dims.Height)"
Write-Host "Fontsize     : $($style.FontSize)"
Write-Host "MarginV      : $($style.MarginV)"
Write-Host "MarginL      : $($style.MarginL)"
Write-Host "MarginR      : $($style.MarginR)"
Write-Host "Outline      : $($style.Outline)"
Write-Host "Shadow       : $($style.Shadow)"
Write-Host "Alignment    : $($style.Alignment)"
Write-Host "Bold         : $($style.Bold)"
Write-Host "Spacing      : $($style.Spacing)"
Write-Host "BorderStyle  : $($style.BorderStyle)"
Write-Host "PrimaryColor : $($style.PrimaryColour)"
Write-Host "OutlineColor : $($style.OutlineColour)"
Write-Host "BackColor    : $($style.BackColour)"

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
