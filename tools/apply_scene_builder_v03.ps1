param(
  [Parameter(Mandatory=$true)][string]$PackDir,
  [int]$MaxScenes = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path
$pack = (Resolve-Path $PackDir).Path

$manifest = Join-Path $pack "manifest_v03.json"
if (-not (Test-Path $manifest)) { throw "Falta manifest_v03.json en: $pack" }

$py = Join-Path $repo "tools\patch_manifest_scene_builder_v03.py"
if (-not (Test-Path $py)) { throw "Falta patcher: $py" }

python -u $py --pack-dir $pack --max-scenes $MaxScenes

$m = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $m.scenes_v03) { throw "Patch no produjo scenes_v03[] en manifest." }

$sc = @($m.scenes_v03)
if ($sc.Count -lt 1) { throw "scenes_v03[] vacío." }

$first = $sc[0]
if (-not ($first.PSObject.Properties.Name -contains "start_ms")) { throw "scenes_v03[0] sin start_ms." }
if (-not ($first.PSObject.Properties.Name -contains "end_ms"))   { throw "scenes_v03[0] sin end_ms." }
if (-not ($first.PSObject.Properties.Name -contains "assets"))   { throw "scenes_v03[0] sin assets." }

Write-Host "OK: Scene Builder v03 aplicado. Pack=$pack scenes_v03=$($sc.Count) (scenes legacy preservado)" -ForegroundColor Green
