param(
  [Parameter(Mandatory=$true)][string]$PackDir,
  [int]$MaxScenes = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path -LiteralPath ".").Path
$pack = (Resolve-Path -LiteralPath $PackDir).Path

$manifest = Join-Path $pack "manifest_v03.json"
if (-not (Test-Path -LiteralPath $manifest)) { throw "Falta manifest_v03.json en: $pack" }

# --- PATCH principal (tu diseño original) ---
$pyPatcher = Join-Path $repo "tools\patch_manifest_scene_builder_v03.py"
if (-not (Test-Path -LiteralPath $pyPatcher)) { throw "Falta patcher: $pyPatcher" }

# usa python del venv si existe
$py = "python"
$venvPy = Join-Path $repo ".venv\Scripts\python.exe"
if (Test-Path -LiteralPath $venvPy) { $py = $venvPy }

& $py -u $pyPatcher --pack-dir $pack --max-scenes $MaxScenes

# sanity mínimo
$m = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $m.scenes_v03) { throw "Patch no produjo scenes_v03[] en manifest." }

$sc = @($m.scenes_v03)
if ($sc.Count -lt 1) { throw "scenes_v03[] vacío." }

$first = $sc[0]
if (-not ($first.PSObject.Properties.Name -contains "start_ms")) { throw "scenes_v03[0] sin start_ms." }
if (-not ($first.PSObject.Properties.Name -contains "end_ms"))   { throw "scenes_v03[0] sin end_ms." }

# --- HYBRID v1: optional pixabay assets injection (manifest_v03.json) ---
try {
  $hybridCfg = Join-Path $repo "config\hybrid.local.json"
  if (Test-Path -LiteralPath $hybridCfg) {
    $cfgObj = Get-Content -LiteralPath $hybridCfg -Raw | ConvertFrom-Json
    if ($cfgObj.hybrid_v1.enabled -eq $true) {
      $code = @"
from pathlib import Path
from studio.hybrid_assets_v01 import apply_hybrid_assets_to_manifest
changed, msg = apply_hybrid_assets_to_manifest(Path(r'''$manifest'''))
print("HYBRID:", "changed" if changed else "no-op", msg)
"@
      & $py -c $code
    } else {
      Write-Host "HYBRID: disabled, skip"
    }
  } else {
    Write-Host "HYBRID: config/hybrid.local.json no existe, skip"
  }
} catch {
  Write-Host ("HYBRID: error (non-fatal): {0}" -f $_.Exception.Message)
}
# --- end HYBRID v1 ---

Write-Host "OK: Scene Builder v03 aplicado. Pack=$pack scenes_v03=$($sc.Count) (scenes legacy preservado)" -ForegroundColor Green
