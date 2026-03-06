param(
  [Parameter(Mandatory=$true)][string]$InVideo,
  [Parameter(Mandatory=$true)][string]$SrtPath,
  [Parameter(Mandatory=$true)][string]$OutVideo,

  [int]$FontSize = 32,
  [int]$Outline = 2,
  [int]$Shadow = 0,
  [int]$MarginV = 120,
  [int]$MarginH = 120,
  [int]$Alignment = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

if (-not (Test-Path -LiteralPath $InVideo)) { throw "Falta InVideo: $InVideo" }
if (-not (Test-Path -LiteralPath $SrtPath)) { throw "Falta SrtPath: $SrtPath" }

function Escape-ForFfmpeg([string]$p) {
  $x = $p -replace '\\','/'
  $x = $x -replace ':','\:'
  $x = $x -replace "'","\'"
  return $x
}

$inV = (Resolve-Path -LiteralPath $InVideo).Path
$srt = (Resolve-Path -LiteralPath $SrtPath).Path
$srtEsc = Escape-ForFfmpeg $srt

$style = "Fontsize=$FontSize,Outline=$Outline,Shadow=$Shadow,MarginV=$MarginV,MarginL=$MarginH,MarginR=$MarginH,Alignment=$Alignment,WrapStyle=2"

Write-Host ("Using SRT: {0}" -f $srt)
Write-Host ("Fallback style font={0} marginH={1}px marginV={2}px" -f $FontSize,$MarginH,$MarginV)

$vf = "subtitles=filename='$srtEsc':force_style='$style'"

& ffmpeg -y -v error -i "$inV" -vf "$vf" -c:a copy "$OutVideo"
if ($LASTEXITCODE -ne 0) { throw "ffmpeg burn-in falló" }

if (-not (Test-Path -LiteralPath $OutVideo)) { throw "No se generó OutVideo: $OutVideo" }

$len = (Get-Item -LiteralPath $OutVideo).Length
Write-Host ("OK: burn-in fallback -> {0} ({1} bytes)" -f $OutVideo,$len) -ForegroundColor Green