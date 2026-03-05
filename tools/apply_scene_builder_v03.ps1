param(
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot,
  [Parameter(Mandatory=$false)][string]$PackDir,
  [int]$MaxScenes = 6,
  [int]$Seed = 123,
  [switch]$Force,

  # v0.3+: opciones rápidas/deterministas
  # -SkipPixabay: NO usa Pixabay aunque exista PIXABAY_API_KEY (solo fallback determinista)
  # -SkipEnrich : NO ejecuta enrich_scene_queries_v03.ps1
  [switch]$SkipPixabay,
  [switch]$SkipEnrich
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

# Compat: si te pasaron -PackDir (live dir), derivamos WorkspaceRoot
if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) {
  if (-not $PackDir -or $PackDir.Trim().Length -eq 0) { throw "Falta -WorkspaceRoot o -PackDir" }
  $PackDir = (Resolve-Path $PackDir).Path

  # Si PackDir apunta a ...\runs\smoke_live_latest, subimos 2 niveles al WorkspaceRoot
  $WorkspaceRoot = (Resolve-Path (Join-Path $PackDir "..\..")).Path
}

# Live dir (estable)
$live = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
if (-not (Test-Path -LiteralPath $live)) { throw "No existe LIVE: $live" }

$manifest = Join-Path $live "manifest_v03.json"
if (-not (Test-Path -LiteralPath $manifest)) { throw "Falta manifest_v03.json en LIVE: $manifest" }

$mRaw = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8
$m = $mRaw | ConvertFrom-Json

if (-not $m.scenes_v03) { $m | Add-Member -NotePropertyName scenes_v03 -NotePropertyValue @() }

# --- audio_clips: asegurar + normalizar (determinista, StrictMode-safe) ---
$AudioClipsChanged = $false
$AudioClipsCreatedFallback = $false

function Normalize-AudioClipsToArray {
  param($Value)

  if ($null -eq $Value) { return @() }

  if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
    return @($Value)
  }

  return @($Value)
}

$hasProp = ($m.PSObject.Properties.Name -contains "audio_clips")
$ac = $null
if ($hasProp) { $ac = $m.audio_clips }

$acArr = Normalize-AudioClipsToArray -Value $ac

if (-not $hasProp -or $null -eq $ac -or $acArr.Count -eq 0) {
  $acArr = @([pscustomobject]@{ id="clip_001"; start_ms=0; end_ms=20000; text="" })
  $AudioClipsChanged = $true
  $AudioClipsCreatedFallback = $true
} else {
  if (-not (($ac -is [System.Collections.IEnumerable]) -and -not ($ac -is [string]))) {
    $AudioClipsChanged = $true
  }
}

$m | Add-Member -Force -NotePropertyName audio_clips -NotePropertyValue $acArr

if ($AudioClipsCreatedFallback) {
  Write-Host "WARN: manifest sin audio_clips -> fallback determinista clip_001 (0..20000ms)" -ForegroundColor DarkYellow
} elseif ($AudioClipsChanged) {
  Write-Host "OK: audio_clips normalizado a array (sin cambiar contenido)" -ForegroundColor DarkGray
}
# --- fin audio_clips ---
if (-not $m.artifacts -or -not $m.artifacts.image) { throw "manifest sin artifacts.image (fallback requerido): $manifest" }

function Ensure-Scenes {
  param([int]$N)

  $sc = @()
  if ($m.scenes_v03) { $sc = @($m.scenes_v03) }

  if ($sc.Count -gt $N) { $sc = $sc[0..($N-1)] }

  if ($sc.Count -lt $N) {
    $lastEnd = 0
    foreach ($c in $m.audio_clips) {
      $e = [int]$c.end_ms
      if ($e -gt $lastEnd) { $lastEnd = $e }
    }
    if ($lastEnd -le 0) { $lastEnd = 20000 }

    $slice = [int][Math]::Floor($lastEnd / $N)
    if ($slice -lt 1000) { $slice = 1000 }

    for ($i=$sc.Count; $i -lt $N; $i++) {
      $start = $i * $slice
      $end   = [Math]::Min($lastEnd, ($i+1) * $slice)
      if ($i -eq ($N-1)) { $end = $lastEnd }

      # CANON: assets.image = array[{path="..."}]
      $obj = [pscustomobject]@{
        id       = ("scene_{0:000}" -f ($i+1))
        start_ms = [int]$start
        end_ms   = [int]$end
        text     = ""
        assets   = [pscustomobject]@{
          image = @([pscustomobject]@{ path = "" })
        }
      }
      $sc += $obj
    }
  }

  $m.scenes_v03 = $sc
}

function Get-AssetPathValue($assetsObj, [string]$key) {
  if (-not $assetsObj) { return "" }
  $prop = $assetsObj.PSObject.Properties[$key]
  if (-not $prop -or -not $prop.Value) { return "" }

  $v = $prop.Value

  if ($v -is [string]) { return [string]$v }

  if ($v -is [pscustomobject] -or $v -is [hashtable]) {
    $p = $v.PSObject.Properties["path"]
    if ($p -and $p.Value) { return [string]$p.Value }
    return ""
  }

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

function ScenesHaveValidImages {
  param([int]$N)

  if (-not $m.scenes_v03) { return $false }
  $sc = @($m.scenes_v03)
  if ($sc.Count -lt $N) { return $false }

  for ($i=0; $i -lt $N; $i++) {
    $scene = $sc[$i]
    if (-not $scene.assets) { return $false }

    $imgRel = Get-AssetPathValue $scene.assets "image"
    $vidRel = Get-AssetPathValue $scene.assets "video"

    $cand = ""
    if ($imgRel) { $cand = $imgRel } elseif ($vidRel) { $cand = $vidRel }
    if (-not $cand) { return $false }

    $full = $cand
    if (-not [System.IO.Path]::IsPathRooted($cand)) {
      $full = Join-Path $live ($cand -replace '/', '\')
    }

    if (-not (Test-Path -LiteralPath $full)) { return $false }
  }

  return $true
}

# Si no Force y ya está todo OK (scenes + images), hacemos skip limpio
# PERO: si este script normalizó/creó audio_clips, guardamos el manifest 1 vez antes de salir.
if (-not $Force) {
  if (ScenesHaveValidImages -N $MaxScenes) {

    if ($AudioClipsChanged) {
      $out = $m | ConvertTo-Json -Depth 50
      $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
      [System.IO.File]::WriteAllText($manifest, $out, $utf8NoBom)
      Write-Host "OK: manifest actualizado (solo audio_clips) antes de SKIP" -ForegroundColor DarkGray
    }

    Write-Host "SKIP: scene_builder v03 (ya hay scenes+images válidos). scenes=$(@($m.scenes_v03).Count) MaxScenes=$MaxScenes" -ForegroundColor DarkGray
    exit 0
  }
}
Ensure-Scenes -N $MaxScenes

# Texto por escena (determinista simple)
$scriptText = ""
try {
  if ($m.script) { $scriptText = [string]$m.script }
  elseif ($m.text -and $m.text.script) { $scriptText = [string]$m.text.script }
} catch { $scriptText = "" }

if ($scriptText) {
  $parts = ($scriptText -split '(?<=[\.\!\?])\s+') | Where-Object { $_ -and $_.Trim().Length -gt 0 }
  if ($parts.Count -gt 0) {
    $n = @($m.scenes_v03).Count
    for ($i=0; $i -lt $n; $i++) {
      $idx = [Math]::Min($parts.Count-1, $i)
      $m.scenes_v03[$i].text = ($parts[$idx].Trim())
    }
  }
}

$cacheDir = Join-Path $live "cache_v03"
if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }

$pixQuery = Join-Path $repo "tools\stock_query_pixabay_v03.ps1"
$dlTool   = Join-Path $repo "tools\download_file_v03.ps1"

$assetsDir = Join-Path $live "assets\scenes_v03"
if (-not (Test-Path -LiteralPath $assetsDir)) { New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null }

$fallbackRel = [string]$m.artifacts.image
$fallbackAbs = (Resolve-Path (Join-Path $live ($fallbackRel -replace '/', '\'))).Path

for ($i=0; $i -lt @($m.scenes_v03).Count; $i++) {
  $scene = $m.scenes_v03[$i]

  if (-not $scene.assets) {
    $scene | Add-Member -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{
      image = @([pscustomobject]@{ path = "" })
    })
  }

  # Asegura canon array[{path}]
  $imgCur = $scene.assets.PSObject.Properties["image"]
  if (-not $imgCur -or -not $imgCur.Value) {
    $scene.assets | Add-Member -Force -NotePropertyName "image" -NotePropertyValue @([pscustomobject]@{ path = "" })
  } elseif ($imgCur.Value -is [string]) {
    $scene.assets.image = @([pscustomobject]@{ path = [string]$imgCur.Value })
  }

  $outName = ("scene_{0:000}.jpg" -f ($i+1))
  $outAbs  = Join-Path $assetsDir $outName
  $outRel  = ("assets/scenes_v03/{0}" -f $outName)

  $q = $scene.text
  if (-not $q -or $q.Trim().Length -lt 3) { $q = "motivación" }
  $q = $q.Trim()

  # --- v0.3+: SkipPixabay => fuerza fallback determinista (rápido/offline) ---
  $canPixabay = $false
  if (-not $SkipPixabay) {
    if ($env:PIXABAY_API_KEY -and (Test-Path -LiteralPath $pixQuery) -and (Test-Path -LiteralPath $dlTool)) {
      $canPixabay = $true
    }
  }

  $picked = $null
  $cacheJson = Join-Path $cacheDir ("pixabay_scene_{0:000}.json" -f ($i+1))

  if ($canPixabay) {
    try {
      if (-not (Test-Path -LiteralPath $cacheJson)) {
        pwsh -NoProfile -ExecutionPolicy Bypass -File $pixQuery -Query $q -OutJsonPath $cacheJson -Seed $Seed | Out-Null
      }

      $cj = Get-Content -LiteralPath $cacheJson -Raw -Encoding UTF8 | ConvertFrom-Json
      $hits = @()
      if ($cj -and $cj.hits) { $hits = @($cj.hits) }

      if ($hits.Count -gt 0) {
        $k = ($Seed + $i) % $hits.Count
        $picked = [string]$hits[$k].url
      }
    } catch { $picked = $null }
  }

  $ok = $false
  if ($picked) {
    try {
      pwsh -NoProfile -ExecutionPolicy Bypass -File $dlTool -Url $picked -OutPath $outAbs | Out-Null
      $scene.assets.image = @([pscustomobject]@{ path = $outRel })
      $ok = $true
      Write-Host "OK: scene[$i] image=PIXABAY -> $outRel" -ForegroundColor DarkGray
    } catch { $ok = $false }
  }

  if (-not $ok) {
    Copy-Item -LiteralPath $fallbackAbs -Destination $outAbs -Force
    $scene.assets.image = @([pscustomobject]@{ path = $outRel })
    if ($SkipPixabay) {
      Write-Host "OK: scene[$i] image=FALLBACK(SkipPixabay) -> $outRel" -ForegroundColor DarkGray
    } else {
      Write-Host "OK: scene[$i] image=FALLBACK(artifacts.image) -> $outRel" -ForegroundColor DarkGray
    }
  }
}

# Guardar manifest UTF-8 sin BOM
$out = $m | ConvertTo-Json -Depth 50
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifest, $out, $utf8NoBom)

# --- v0.3: enrich stock_query por escena (determinista) ---
if (-not $SkipEnrich) {
  try {
    $enricher = Join-Path $repo "tools\enrich_scene_queries_v03.ps1"
    if (Test-Path -LiteralPath $enricher) {

      $manifestGuess = $null

      # Caso smoke/live estándar
      if ($WorkspaceRoot -and $WorkspaceRoot.Trim().Length -gt 0) {
        $mg = Join-Path $WorkspaceRoot "runs\smoke_live_latest\manifest_v03.json"
        if (Test-Path -LiteralPath $mg) { $manifestGuess = $mg }
      }

      # Caso PackDir (si existe en este script)
      if (-not $manifestGuess -and (Get-Variable -Name PackDir -ErrorAction SilentlyContinue)) {
        if ($PackDir -and (Test-Path -LiteralPath $PackDir)) {
          $mg2 = Join-Path $PackDir "manifest_v03.json"
          if (Test-Path -LiteralPath $mg2) { $manifestGuess = $mg2 }
        }
      }

      if ($manifestGuess -and (Test-Path -LiteralPath $manifestGuess)) {
        pwsh -NoProfile -ExecutionPolicy Bypass -File $enricher -ManifestPath $manifestGuess -Seed $Seed | Out-Null
        Write-Host "OK: enrich_scene_queries_v03 aplicado (manifest=$manifestGuess)" -ForegroundColor DarkGray
      } else {
        Write-Host "WARN: no encontré manifest_v03.json para enriquecer queries" -ForegroundColor Yellow
      }

    } else {
      Write-Host "WARN: faltan tool enrich_scene_queries_v03.ps1 (skip)" -ForegroundColor Yellow
    }
  } catch {
    Write-Host ("WARN: enrich_scene_queries_v03 falló (skip): {0}" -f $_.Exception.Message) -ForegroundColor Yellow
  }
} else {
  Write-Host "SKIP: enrich_scene_queries_v03 (SkipEnrich=True)" -ForegroundColor DarkGray
}
# --- fin enrich ---

Write-Host ("OK: scene_builder v03 aplicado. scenes={0} live={1} force={2} skipPixabay={3} skipEnrich={4}" -f @($m.scenes_v03).Count, $live, [bool]$Force, [bool]$SkipPixabay, [bool]$SkipEnrich) -ForegroundColor Green