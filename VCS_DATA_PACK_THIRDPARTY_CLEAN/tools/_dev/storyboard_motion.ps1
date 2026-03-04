param(
  [Parameter(Mandatory=$true)]
  [string] $PackDir,

  # Si lo das, aplica a TODAS las escenas
  [string] $MotionAll = "",

  # Si lo das, aplica a índices específicos (requiere -Motion)
  [int[]] $SceneIndex = @(),

  [string] $Motion = "",

  # Limpia (remove) motion/motion_profile en todas las escenas
  [switch] $Clear,

  # No escribe, solo muestra lo que haría
  [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sbPath = Join-Path $PackDir "storyboard.json"
if (-not (Test-Path $sbPath)) { throw "No existe storyboard.json en: $PackDir" }

# Leer storyboard
$sb = Get-Content $sbPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($sb.Count -lt 1) { throw "storyboard.json vacío" }

function Set-Motion([object]$scene, [string]$val) {
  $scene | Add-Member -Force -NotePropertyName "motion" -NotePropertyValue $val
  # Por compat: si existía motion_profile, lo dejamos pero alineado
  $scene | Add-Member -Force -NotePropertyName "motion_profile" -NotePropertyValue $val
}

function Clear-Motion([object]$scene) {
  # ConvertFrom-Json devuelve PSCustomObject; se puede eliminar propiedad así:
  if ($scene.PSObject.Properties["motion"]) { $scene.PSObject.Properties.Remove("motion") }
  if ($scene.PSObject.Properties["motion_profile"]) { $scene.PSObject.Properties.Remove("motion_profile") }
}

# Backup
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$bak = "$sbPath.bak_motiontool_$ts"
Copy-Item $sbPath $bak -Force

# Plan
if ($Clear) {
  for ($i=0; $i -lt $sb.Count; $i++) { Clear-Motion $sb[$i] }
  $plan = "CLEAR all"
}
elseif ($MotionAll) {
  for ($i=0; $i -lt $sb.Count; $i++) { Set-Motion $sb[$i] $MotionAll }
  $plan = "SET ALL = $MotionAll"
}
elseif ($SceneIndex.Count -gt 0) {
  if (-not $Motion) { throw "Si usas -SceneIndex debes dar -Motion" }
  foreach ($idx in $SceneIndex) {
    if ($idx -lt 0 -or $idx -ge $sb.Count) { throw "SceneIndex fuera de rango: $idx (0..$($sb.Count-1))" }
    Set-Motion $sb[$idx] $Motion
  }
  $plan = "SET scenes [$($SceneIndex -join ',')] = $Motion"
}
else {
  throw "Debes usar -Clear o -MotionAll o (-SceneIndex + -Motion)"
}

Write-Host "PLAN: $plan" -ForegroundColor Cyan
Write-Host "BACKUP: $bak" -ForegroundColor DarkGray

# Mostrar preview de primeras escenas
Write-Host ""
Write-Host "PREVIEW (primeras 4 escenas):" -ForegroundColor Cyan
$max = [Math]::Min(4, $sb.Count)
for ($i=0; $i -lt $max; $i++) {
  $m = ""
  if ($sb[$i].PSObject.Properties["motion"]) { $m = $sb[$i].motion }
  elseif ($sb[$i].PSObject.Properties["motion_profile"]) { $m = $sb[$i].motion_profile }
  Write-Host ("  scene[{0}] motion={1}" -f $i, $m)
}

if ($DryRun) {
  Write-Host ""
  Write-Host "DRY RUN: no se escribió storyboard.json" -ForegroundColor Yellow
  exit 0
}

# Guardar UTF-8 sin BOM
$jsonOut = $sb | ConvertTo-Json -Depth 50
[System.IO.File]::WriteAllText($sbPath, $jsonOut, [Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "OK: actualizado -> $sbPath" -ForegroundColor Green
exit 0