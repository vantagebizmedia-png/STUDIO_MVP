param(
    [Parameter(Mandatory = $true)]
    [string]$PackDir,

    [string]$MusicDir = ".\music",

    [string]$VideoName = "video.mp4",

    [string]$OutputVideoName = "video_music_auto.mp4",

    [double]$BgmVolume = 0.12,
    [double]$FadeInSec = 1.5,
    [double]$FadeOutSec = 2.5,

    [switch]$ReplaceOriginal
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PackDir  = (Resolve-Path -LiteralPath $PackDir).Path
$MusicDir = (Resolve-Path -LiteralPath $MusicDir).Path

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$picker = Join-Path $scriptRoot "pick_local_music_from_strategy.ps1"
$adder  = Join-Path $scriptRoot "add_bgm_to_pack.ps1"

if (-not (Test-Path -LiteralPath $picker -PathType Leaf)) {
    throw "No existe: $picker"
}
if (-not (Test-Path -LiteralPath $adder -PathType Leaf)) {
    throw "No existe: $adder"
}

$videoPath = Join-Path $PackDir $VideoName
if (-not (Test-Path -LiteralPath $videoPath -PathType Leaf)) {
    throw "No existe video del pack: $videoPath"
}

& powershell -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File $picker `
  -PackDir $PackDir `
  -MusicDir $MusicDir `
  -CopyIntoPack

if ($LASTEXITCODE -ne 0) {
    throw "pick_local_music_from_strategy.ps1 falló con exit code $LASTEXITCODE"
}

$selectionJson = Join-Path $PackDir "music_selection.json"
if (-not (Test-Path -LiteralPath $selectionJson -PathType Leaf)) {
    throw "No se generó music_selection.json"
}

$sel = Get-Content -LiteralPath $selectionJson -Raw | ConvertFrom-Json
$musicPath = [string]$sel.selected.copied_into_pack
if ([string]::IsNullOrWhiteSpace($musicPath)) {
    $musicPath = [string]$sel.selected.original_path
}

if (-not (Test-Path -LiteralPath $musicPath -PathType Leaf)) {
    throw "La música seleccionada no existe: $musicPath"
}

$outputPath = Join-Path $PackDir $OutputVideoName

$cmd = @(
    "-NoProfile",
    "-NoLogo",
    "-NonInteractive",
    "-ExecutionPolicy", "Bypass",
    "-File", $adder,
    "-VideoPath", $videoPath,
    "-MusicPath", $musicPath,
    "-OutputPath", $outputPath,
    "-BgmVolume", "$BgmVolume",
    "-FadeInSec", "$FadeInSec",
    "-FadeOutSec", "$FadeOutSec"
)

if ($ReplaceOriginal) {
    $cmd += "-ReplaceOriginal"
}

& powershell @cmd

if ($LASTEXITCODE -ne 0) {
    throw "add_bgm_to_pack.ps1 falló con exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
    throw "No se generó el video de salida con música: $outputPath"
}

Write-Host ""
Write-Host "=== AUTO MUSIC APPLIED ==="
Write-Host "PACK        :" $PackDir
Write-Host "VIDEO_IN    :" $videoPath
Write-Host "MUSIC_USED  :" $musicPath
Write-Host "VIDEO_OUT   :" $outputPath