param(
  [Parameter(Mandatory=$true)][string]$LiveDir,
  [Parameter(Mandatory=$true)][string]$OutDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg) { throw "FINALIZE FAIL: $msg" }

$live = (Resolve-Path -LiteralPath $LiveDir).Path
$out  = (Resolve-Path -LiteralPath (New-Item -ItemType Directory -Force -Path $OutDir)).Path

$videoBase = Join-Path $live "video.mp4"
$videoSubs = Join-Path $live "video_subtitles.mp4"

if (-not (Test-Path -LiteralPath $videoBase)) { Fail "Falta base: $videoBase" }
if (-not (Test-Path -LiteralPath $videoSubs)) { Fail "Falta subtitles: $videoSubs" }

# Contract outputs
$dstBase  = Join-Path $out "video.mp4"               # sin música
$dstFinal = Join-Path $out "video_final.mp4"         # versión final (hoy: con subtítulos)
$dstMusic = Join-Path $out "video_music_auto.mp4"    # hoy placeholder determinista

Copy-Item -LiteralPath $videoBase -Destination $dstBase  -Force
Copy-Item -LiteralPath $videoSubs -Destination $dstFinal -Force

# Placeholder determinista: hasta que exista música real
Copy-Item -LiteralPath $dstFinal -Destination $dstMusic -Force

Write-Host "OK finalize_v03 outputs:"
Get-Item -LiteralPath $dstBase, $dstFinal, $dstMusic | Select-Object Name,Length,FullName | Format-Table -AutoSize
