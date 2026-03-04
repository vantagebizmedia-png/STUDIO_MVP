param(
  [Parameter(Mandatory=$true)][string] $PackDir,
  [int] $Seed = 21,
  [int] $MaxScenes = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

# Repo root aunque lo ejecutes desde otro cwd
$Repo = Split-Path $PSScriptRoot -Parent

function Run-One([string]$tag, [string[]]$extraArgs) {
  Write-Host ""
  Write-Host "=== $tag ===" -ForegroundColor Cyan

  python run.py "IGNORED" --seed $Seed --max_scenes $MaxScenes --pack_dir "$PackDir" --music_mode off @extraArgs

  $out = Join-Path $Repo "workspace\output\video_final_latest.mp4"
  if (Test-Path $out) {
    $dst = Join-Path $Repo ("workspace\output\video_" + $tag + ".mp4")
    Copy-Item $out $dst -Force
    Write-Host "OK: $dst" -ForegroundColor Green
  } else {
    Write-Host "WARN: no encontré $out" -ForegroundColor Yellow
  }
}

Run-One "cine_A_balanced" @(
  "--motion","slow_zoom_in","--motion_strength","0.10",
  "--jitter_px","1.6","--jitter_hz","0.9",
  "--grain_amount","0.016","--vignette","0.14"
)

Run-One "cine_B_strong" @(
  "--motion","pan_up","--motion_strength","0.10",
  "--jitter_px","2.0","--jitter_hz","0.9",
  "--grain_amount","0.020","--vignette","0.18"
)

Run-One "cine_C_clean" @(
  "--motion","slow_zoom_in","--motion_strength","0.08",
  "--jitter_px","1.0","--jitter_hz","0.8",
  "--grain_amount","0.012","--vignette","0.10"
)

Run-One "cine_D_dynamic" @(
  "--motion","pan_right","--motion_strength","0.12",
  "--jitter_px","1.8","--jitter_hz","1.1",
  "--grain_amount","0.018","--vignette","0.16"
)

Write-Host ""
Write-Host "Listo. Revisa:" -ForegroundColor Green
Write-Host "  workspace\output\video_cine_A_balanced.mp4"
Write-Host "  workspace\output\video_cine_B_strong.mp4"
Write-Host "  workspace\output\video_cine_C_clean.mp4"
Write-Host "  workspace\output\video_cine_D_dynamic.mp4"