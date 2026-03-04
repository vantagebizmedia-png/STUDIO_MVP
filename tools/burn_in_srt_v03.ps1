param(
  [Parameter(Mandatory=$true)][string]$InVideo,
  [Parameter(Mandatory=$true)][string]$SrtPath,
  [Parameter(Mandatory=$true)][string]$OutVideo,

  [int]$FontSize = 18,
  [int]$Outline = 2,
  [int]$Shadow = 1,
  [int]$MarginV = 80,
  [int]$Alignment = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

if (-not (Test-Path -LiteralPath $InVideo)) { throw "Falta InVideo: $InVideo" }
if (-not (Test-Path -LiteralPath $SrtPath)) { throw "Falta SrtPath: $SrtPath" }

# ffmpeg subtitles necesita:
# - backslashes -> /
# - ":" -> "\:"
$srtF = ($SrtPath -replace '\\','/')
$srtF = ($srtF -replace ':','\:')

$style = "Fontsize=$FontSize,Outline=$Outline,Shadow=$Shadow,MarginV=$MarginV,Alignment=$Alignment"
$vf = "subtitles='$srtF':force_style='$style'"

ffmpeg -y -hide_banner -loglevel error -i $InVideo -vf $vf -c:a copy $OutVideo

if (-not (Test-Path -LiteralPath $OutVideo)) { throw "No se generó OutVideo: $OutVideo" }
$len = (Get-Item -LiteralPath $OutVideo).Length
Write-Host "OK: burn-in -> $OutVideo ($len bytes)"
