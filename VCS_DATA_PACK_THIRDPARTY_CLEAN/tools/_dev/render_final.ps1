param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $PackDir,
  [int] $Seed = 21,
  [int] $MaxScenes = 4,

  # preset cine (elige 1)
  [ValidateSet("A","B","C","D")]
  [string] $Preset = "B",

  # si lo pones, apaga grain+vignette para iterar rápido
  [switch] $Fast,

  # música
  [ValidateSet("off","fixed","random","topic","menu")]
  [string] $MusicMode = "off",

  # solo aplica cuando MusicMode = fixed. Si lo dejas vacío, intenta Repo\music\bg.mp3
  [string] $Music = "",

  [double] $MusicVolume = 0.22,
  [double] $Ducking     = 0.70,

  [ValidateSet("fixed","dynamic")]
  [string] $DuckingMode = "fixed"
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

# Repo root (tools/..)
$Repo = Split-Path $PSScriptRoot -Parent

$presets = @{
  "A" = @("--motion","slow_zoom_in","--motion_strength","0.10","--jitter_px","1.6","--jitter_hz","0.9","--grain_amount","0.016","--vignette","0.14")
  "B" = @("--motion","pan_up","--motion_strength","0.10","--jitter_px","2.0","--jitter_hz","0.9","--grain_amount","0.020","--vignette","0.18")
  "C" = @("--motion","slow_zoom_in","--motion_strength","0.08","--jitter_px","1.0","--jitter_hz","0.8","--grain_amount","0.012","--vignette","0.10")
  "D" = @("--motion","pan_right","--motion_strength","0.12","--jitter_px","1.8","--jitter_hz","1.1","--grain_amount","0.018","--vignette","0.16")
}

$argsList = @($presets[$Preset])

if ($Fast) {
  # Reemplaza grain/vignette por OFF (rápido)
  for ($i=0; $i -lt $argsList.Count; $i++) {
    if ($argsList[$i] -eq "--grain_amount") { $argsList[$i+1] = "0.0" }
    if ($argsList[$i] -eq "--vignette")     { $argsList[$i+1] = "0.0" }
  }
}

# Música (determinista si usas fixed + ruta fija)
$musicArgs = @("--music_mode","off")
if ($MusicMode -ne "off") {
  $musicArgs = @(
    "--music_mode",$MusicMode,
    "--music_volume",[string]$MusicVolume,
    "--ducking",[string]$Ducking,
    "--ducking_mode",$DuckingMode
  )

  if ($MusicMode -eq "fixed") {
    if (-not $Music) {
      $defaultMusic = Join-Path $Repo "music\bg.mp3"
      if (Test-Path $defaultMusic) { $Music = $defaultMusic }
      else { throw "MusicMode=fixed pero no diste -Music y no existe $defaultMusic" }
    }
    $musicArgs += @("--music",$Music)
  }
}

Write-Host ""
Write-Host "FINAL preset=$Preset  Fast=$Fast  MusicMode=$MusicMode  DuckingMode=$DuckingMode" -ForegroundColor Cyan

python run.py "IGNORED" --seed $Seed --max_scenes $MaxScenes --pack_dir "$PackDir" @musicArgs @argsList

$out = Join-Path $Repo "workspace\output\video_final_latest.mp4"
if (Test-Path $out) {
  $suffix = if ($Fast) { "FAST" } else { "CINE" }
  if ($MusicMode -ne "off") {
    $suffix = $suffix + "_MUSIC_" + $DuckingMode.ToUpper()
  }
  $dst = Join-Path $Repo ("workspace\output\video_FINAL_" + $suffix + "_" + $Preset + ".mp4")
  Copy-Item $out $dst -Force
  Write-Host "OK: $dst" -ForegroundColor Green
} else {
  Write-Host "WARN: no encontré $out" -ForegroundColor Yellow
}