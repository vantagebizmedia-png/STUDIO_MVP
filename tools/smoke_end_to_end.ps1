param(
  [string]$Prompt = "smoke test",
  [int]$Seed = 1
)

$ErrorActionPreference = "Stop"

# Workspace temporal dedicado
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$env:STUDIO_WORKSPACE = Join-Path $env:USERPROFILE ("STUDIO_WORKSPACE_SMOKE_" + $stamp)
New-Item -ItemType Directory -Force $env:STUDIO_WORKSPACE | Out-Null
New-Item -ItemType Directory -Force (Join-Path $env:STUDIO_WORKSPACE "runs") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $env:STUDIO_WORKSPACE "cache") | Out-Null

Write-Host "STUDIO_WORKSPACE=$env:STUDIO_WORKSPACE"

# Timestamps BEFORE (repo)
$repoRuns = ".\workspace\runs"
$repoCache = ".\workspace\cache"
$tRuns0 = if (Test-Path $repoRuns) { (Get-Item $repoRuns).LastWriteTime } else { $null }
$tCache0 = if (Test-Path $repoCache) { (Get-Item $repoCache).LastWriteTime } else { $null }
Write-Host "repo runs BEFORE = $tRuns0"
Write-Host "repo cache BEFORE = $tCache0"

# Ejecutar run
python run.py "$Prompt" --seed $Seed

# Detectar run_id más reciente en workspace externo
$latestRun = Get-ChildItem (Join-Path $env:STUDIO_WORKSPACE "runs") -Directory |
             Sort-Object LastWriteTime -Descending |
             Select-Object -First 1

if (-not $latestRun) { throw "No se creó ningún run en $env:STUDIO_WORKSPACE\runs" }

$finalMp4 = Join-Path $latestRun.FullName "render\video_final.mp4"
if (!(Test-Path $finalMp4)) {
  throw "No encontré video_final.mp4 en: $finalMp4"
}

Write-Host "OK: video final externo: $finalMp4"

# Timestamps AFTER (repo)  no deben cambiar por este smoke
$tRuns1 = if (Test-Path $repoRuns) { (Get-Item $repoRuns).LastWriteTime } else { $null }
$tCache1 = if (Test-Path $repoCache) { (Get-Item $repoCache).LastWriteTime } else { $null }

Write-Host "repo runs AFTER  = $tRuns1"
Write-Host "repo cache AFTER = $tCache1"

if ($tRuns0 -and $tRuns1 -and ($tRuns1 -ne $tRuns0)) {
  Write-Warning "WARN: workspace/runs del repo cambió timestamp (posible escritura dentro del repo)."
} else {
  Write-Host "OK: repo workspace/runs no cambió."
}

if ($tCache0 -and $tCache1 -and ($tCache1 -ne $tCache0)) {
  Write-Warning "WARN: workspace/cache del repo cambió timestamp (posible escritura dentro del repo)."
} else {
  Write-Host "OK: repo workspace/cache no cambió."
}

Write-Host ""
Write-Host "SMOKE PASS"
Write-Host "External run dir: $($latestRun.FullName)"
Write-Host "External video:   $finalMp4"
