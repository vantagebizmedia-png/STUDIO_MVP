param(
  [Parameter(Mandatory=$true)][string]$LiveDir,
  [int]$MaxScenes = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

function Fail([string]$msg) { throw "SMOKE FAIL: $msg" }

if (-not (Test-Path -LiteralPath $LiveDir)) { Fail "No existe LiveDir: $LiveDir" }
$LiveDir = (Resolve-Path $LiveDir).Path

$man = Join-Path $LiveDir "manifest_v03.json"
if (-not (Test-Path -LiteralPath $man)) { Fail "Falta manifest_v03.json en: $LiveDir" }

# Outputs de subtítulos (lo mínimo que esperamos en LIVE)
$needLive = @(
  (Join-Path $LiveDir "captions_v03.srt"),
  (Join-Path $LiveDir "video_subtitles.mp4")
)
foreach ($p in $needLive) {
  if (-not (Test-Path -LiteralPath $p)) { Fail "Falta output LIVE requerido: $p" }
}

$m = Get-Content -LiteralPath $man -Raw -Encoding UTF8 | ConvertFrom-Json

# Preferimos scenes_v03; fallback a scenes si existiera
$scenes = @()
if ($m.PSObject.Properties["scenes_v03"] -and $m.scenes_v03) {
  $scenes = @($m.scenes_v03)
} elseif ($m.PSObject.Properties["scenes"] -and $m.scenes) {
  $scenes = @($m.scenes)
} else {
  Fail "manifest no tiene scenes_v03[] ni scenes[]"
}

if ($scenes.Count -lt 1) { Fail "No hay escenas en manifest" }

$take = [Math]::Min($MaxScenes, $scenes.Count)

function Get-AssetPathValue($assetsObj, [string]$key) {
  if (-not $assetsObj) { return "" }
  $prop = $assetsObj.PSObject.Properties[$key]
  if (-not $prop -or -not $prop.Value) { return "" }

  $v = $prop.Value

  # string directo
  if ($v -is [string]) { return [string]$v }

  # objeto con .path
  if ($v -is [pscustomobject] -or $v -is [hashtable]) {
    $p = $v.PSObject.Properties["path"]
    if ($p -and $p.Value) { return [string]$p.Value }
    return ""
  }

  # array: primer item string u objeto{path}
  if ($v -is [object[]]) {
    $arr = @($v)
    if ($arr.Count -ge 1) {
      $x = $arr[0]
      if ($x -is [string]) { return [string]$x }
      if ($x -is [pscustomobject] -or $x -is [hashtable]) {
        $p0 = $x.PSObject.Properties["path"]
        if ($p0 -and $p0.Value) { return [string]$p0.Value }
      }
    }
  }

  return ""
}

for ($i=0; $i -lt $take; $i++) {
  $s = $scenes[$i]

  $assetsProp = $s.PSObject.Properties["assets"]
  if (-not $assetsProp -or -not $assetsProp.Value) {
    Fail ("Escena {0} sin assets" -f $i)
  }

  $a = $assetsProp.Value

  $img = Get-AssetPathValue $a "image"
  $vid = Get-AssetPathValue $a "video"

  $cand = ""
  if ($img) { $cand = $img }
  elseif ($vid) { $cand = $vid }

  if (-not $cand) {
    Fail ("Escena {0} sin asset visual válido (esperaba assets.image[0].path o assets.video[0].path existente)" -f $i)
  }

  # Resolver relativo a LiveDir
  $full = $cand
  if (-not [System.IO.Path]::IsPathRooted($cand)) {
    $full = Join-Path $LiveDir $cand
  }

  if (-not (Test-Path -LiteralPath $full)) {
    Fail ("Escena {0} asset visual no existe: {1} (resuelto: {2})" -f $i,$cand,$full)
  }
}

Write-Host ("SMOKE OK: LIVE subtitles v03 + assets (image|video). live={0} scenes={1}" -f $LiveDir,$take) -ForegroundColor Green
