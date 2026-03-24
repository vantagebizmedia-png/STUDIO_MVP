param(
    [Parameter(Mandatory = $true)]
    [string]$PackDir,

    [string]$MusicDir = ".\music",

    [string]$VideoName = "video.mp4",

    [string]$OutputVideoName = "video_music_auto.mp4",

    [string]$FinalVideoName = "video_final.mp4",

    [double]$BgmVolume = 0.12,
    [double]$FadeInSec = 1.5,
    [double]$FadeOutSec = 2.5
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PackDir  = (Resolve-Path -LiteralPath $PackDir).Path
$MusicDir = (Resolve-Path -LiteralPath $MusicDir).Path

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$applyScript = Join-Path $scriptRoot "apply_auto_music_to_pack.ps1"
if (-not (Test-Path -LiteralPath $applyScript -PathType Leaf)) {
    throw "No existe: $applyScript"
}

& powershell -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File $applyScript `
  -PackDir $PackDir `
  -MusicDir $MusicDir `
  -VideoName $VideoName `
  -OutputVideoName $OutputVideoName `
  -BgmVolume $BgmVolume `
  -FadeInSec $FadeInSec `
  -FadeOutSec $FadeOutSec

if ($LASTEXITCODE -ne 0) {
    throw "apply_auto_music_to_pack.ps1 falló con exit code $LASTEXITCODE"
}

$outVideo = Join-Path $PackDir $OutputVideoName
if (-not (Test-Path -LiteralPath $outVideo -PathType Leaf)) {
    throw "No se generó el video con música: $outVideo"
}

$finalVideo = Join-Path $PackDir $FinalVideoName
Copy-Item -LiteralPath $outVideo -Destination $finalVideo -Force

Write-Host ""
Write-Host "=== FINALIZE PACK AUTO MUSIC ==="
Write-Host "PACK       :" $PackDir
Write-Host "VIDEO_OUT  :" $outVideo
Write-Host "VIDEO_FINAL:" $finalVideo
Write-Host "OK         : True"