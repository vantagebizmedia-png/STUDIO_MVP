param(
  [Parameter(Mandatory=$true)][string]$PackDir,
  [int]$MaxScenes = 6,
  [int]$Seed = 123
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path
$pack = (Resolve-Path $PackDir).Path
$manifest = Join-Path $pack "manifest_v03.json"
if (-not (Test-Path $manifest)) { throw "Falta manifest_v03.json en: $pack" }

# API key requerida
$k1 = (($env:OPENAI_STUDIO_PIXABAY_API_KEY ?? "")).Trim()
$k2 = (($env:PIXABAY_API_KEY ?? "")).Trim()
if (($k1.Length -lt 5) -and ($k2.Length -lt 5)) {
  throw "Falta API key. Define OPENAI_STUDIO_PIXABAY_API_KEY o PIXABAY_API_KEY en el entorno."
}

function Set-JsonProp {
  param(
    [Parameter(Mandatory=$true)][object]$Obj,
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][object]$Value
  )
  # Add-Member -Force crea o sobrescribe sin fallar en StrictMode
  $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force | Out-Null
}

# 0) Forzar RUN no-strict y limpiar cache para forzar request
$m = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json

Set-JsonProp -Obj $m -Name "replay_strict" -Value $false
Set-JsonProp -Obj $m -Name "seed"         -Value ([int]$Seed)
Set-JsonProp -Obj $m -Name "stock_cache"  -Value (@{})

# fuerza regeneración limpia (si existe)
if ($m.PSObject.Properties.Name -contains "scenes_v03") {
  $null = $m.PSObject.Properties.Remove("scenes_v03")
}

# escribir manifest
($m | ConvertTo-Json -Depth 80) | Set-Content -LiteralPath $manifest -Encoding UTF8

# limpiar assets (imágenes y clips) para forzar regeneración
$imgDir = Join-Path $pack "assets\images"
$acDir  = Join-Path $pack "assets\audio_clips"
if (Test-Path $imgDir) {
  Get-ChildItem -LiteralPath $imgDir -File | Remove-Item -Force
}
if (Test-Path $acDir) {
  Get-ChildItem -LiteralPath $acDir -File | Remove-Item -Force
}

# 1) Primera pasada: debe bajar pixabay real
$apply = Join-Path $repo "tools\apply_scene_builder_v03.ps1"
if (-not (Test-Path $apply)) { throw "Falta: $apply" }

pwsh -NoProfile -ExecutionPolicy Bypass -File $apply -PackDir $pack -MaxScenes $MaxScenes

$m1 = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $m1.scenes_v03) { throw "No hay scenes_v03 tras apply." }
$sc = @($m1.scenes_v03)
if ($sc.Count -lt 1) { throw "scenes_v03 vacío." }

$pixCount = 0
for ($i=0; $i -lt $sc.Count; $i++) {
  $s = $sc[$i]

  $imgRel = $s.assets.image
  if (-not $imgRel) { throw "scenes_v03[$i] sin assets.image" }
  $imgPath = Join-Path $pack $imgRel
  if (-not (Test-Path $imgPath)) { throw "Imagen no existe: $imgPath" }

  $meta = $s.assets.image_meta
  if (-not $meta) { throw "scenes_v03[$i] sin assets.image_meta" }

  if ($meta.provider -eq "pixabay") { $pixCount++ }
}

if ($pixCount -lt 1) {
  throw "No se obtuvo provider pixabay real. pixCount=$pixCount (revisa key/permisos/red)."
}

# 2) Segunda pasada: debe dar cache_hit true (sin re-descargar)
pwsh -NoProfile -ExecutionPolicy Bypass -File $apply -PackDir $pack -MaxScenes $MaxScenes

$m2 = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
$sc2 = @($m2.scenes_v03)

$hitCount = 0
for ($i=0; $i -lt $sc2.Count; $i++) {
  $meta = $sc2[$i].assets.image_meta
  if ($meta -and $meta.provider -eq "pixabay" -and $meta.cache_hit -eq $true) { $hitCount++ }
}

if ($hitCount -lt 1) {
  throw "No vi cache_hit=true en segunda pasada. hitCount=$hitCount"
}

Write-Host "SMOKE OK: Pixabay real + cache determinista. pack=$pack scenes=$($sc2.Count) pixCount=$pixCount cacheHitCount=$hitCount" -ForegroundColor Green
