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

$PackDir = (Resolve-Path -LiteralPath $PackDir).Path
$MusicDir = (Resolve-Path -LiteralPath $MusicDir).Path

$picker = Join-Path (Get-Location) "tools\pick_local_music_from_strategy.ps1"
$adder  = Join-Path (Get-Location) "tools\add_bgm_to_pack.ps1"

if (-not (Test-Path -LiteralPath $picker)) {
    throw "No existe: $picker"
}
if (-not (Test-Path -LiteralPath $adder)) {
    throw "No existe: $adder"
}

$videoPath = Join-Path $PackDir $VideoName
if (-not (Test-Path -LiteralPath $videoPath)) {
    throw "No existe video del pack: $videoPath"
}

powershell -ExecutionPolicy Bypass -File $picker `
  -PackDir $PackDir `
  -MusicDir $MusicDir `
  -CopyIntoPack

$selectionJson = Join-Path $PackDir "music_selection.json"
if (-not (Test-Path -LiteralPath $selectionJson)) {
    throw "No se generó music_selection.json"
}

$sel = Get-Content -LiteralPath $selectionJson -Raw | ConvertFrom-Json
$musicPath = [string]$sel.selected.copied_into_pack
if ([string]::IsNullOrWhiteSpace($musicPath)) {
    $musicPath = [string]$sel.selected.original_path
}

if (-not (Test-Path -LiteralPath $musicPath)) {
    throw "La música seleccionada no existe: $musicPath"
}

$outputPath = Join-Path $PackDir $OutputVideoName

$cmd = @(
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

powershell @cmd

Write-Host ""
Write-Host "=== AUTO MUSIC APPLIED ==="
Write-Host "PACK        :" $PackDir
Write-Host "VIDEO_IN    :" $videoPath
Write-Host "MUSIC_USED  :" $musicPath
Write-Host "VIDEO_OUT   :" $outputPath
