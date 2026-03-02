param(
  [string]$WorkspaceRoot = "",
  [switch]$CleanRepoOutputs
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -lt 3) {
  $WorkspaceRoot = $env:STUDIO_WORKSPACE
}
if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -lt 3) {
  throw "Falta WorkspaceRoot y env:STUDIO_WORKSPACE no está seteado."
}

$WS = (Resolve-Path $WorkspaceRoot).Path
New-Item -ItemType Directory -Force (Join-Path $WS "runs") | Out-Null

# 1) Ejecuta smoke normal (puede escribir temporalmente dentro del repo)
$studioSmoke = Join-Path $repo "tools\studio.ps1"
if (-not (Test-Path $studioSmoke)) { throw "No existe: $studioSmoke" }

pwsh -NoProfile -ExecutionPolicy Bypass -File $studioSmoke -Mode smoke

# 2) Descubre el LIVE dir real: manifest_v03.json más reciente FUERA de exports/_freeze
$man = Get-ChildItem -LiteralPath $repo -Recurse -File -Filter manifest_v03.json -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '\\exports\\|\\_freeze_|\\__pycache__\\|\\.venv\\' } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $man) { throw "No encontré manifest_v03.json LIVE dentro del repo luego del smoke." }

$liveRepo = Split-Path $man.FullName -Parent
if (-not (Test-Path $liveRepo)) { throw "LIVE dir no existe: $liveRepo" }

# 3) Copia a workspace con ruta estable
$dstRoot = Join-Path $WS "runs\smoke_live_latest"
$dstLive = Join-Path $dstRoot "artifacts"

if (Test-Path $dstRoot) { Remove-Item -Recurse -Force $dstRoot }
New-Item -ItemType Directory -Force $dstLive | Out-Null

# IMPORTANTE: usar -Path (NO -LiteralPath) para permitir wildcard
Copy-Item -Recurse -Force -Path (Join-Path $liveRepo "*") -Destination $dstLive

# 4) (Opcional) Limpia outputs del repo (no borra código)
if ($CleanRepoOutputs) {
  $patterns = @("_demo_out","_demo_out_legacy","_v03_smoke_cfg","_v03_legacy_run","_v03_*","_freeze_*")
  foreach ($p in $patterns) {
    Get-ChildItem -LiteralPath $repo -Directory -Filter $p -ErrorAction SilentlyContinue |
      ForEach-Object {
        try { Remove-Item -Recurse -Force -LiteralPath $_.FullName } catch {}
      }
  }
}

# 5) DEVUELVE el LiveDir por pipeline (para que el caller lo capture)
Write-Output ("LIVE_WORKSPACE_DIR=" + $dstLive)
