param(
  [Parameter(Mandatory=$true)][string]$WorkspaceRoot,
  [int]$MaxScenes = 6,
  [int]$Seed = 123,
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

# Live dir (estable)
$live = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
if (-not (Test-Path -LiteralPath $live)) { throw "No existe LIVE: $live" }

$manifest = Join-Path $live "manifest_v03.json"
if (-not (Test-Path -LiteralPath $manifest)) { throw "Falta manifest_v03.json en LIVE: $manifest" }

$mRaw = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8
$m = $mRaw | ConvertFrom-Json

if (-not $m.scenes_v03) { $m | Add-Member -NotePropertyName scenes_v03 -NotePropertyValue @() }
if (-not $m.audio_clips) { throw "manifest sin audio_clips (requerido por smoke): $manifest" }
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

      $obj = [pscustomobject]@{
        id = ("scene_{0:000}" -f ($i+1))
        start_ms = [int]$start
        end_ms   = [int]$end
        text = ""
        assets = [pscustomobject]@{ image = "" }
      }
      $sc += $obj
    }
  }

  $m.scenes_v03 = $sc
}

function ScenesHaveValidImages {
  param([int]$N)

  if (-not $m.scenes_v03) { return $false }
  $sc = @($m.scenes_v03)
  if ($sc.Count -lt $N) { return $false }

  for ($i=0; $i -lt $N; $i++) {
    $scene = $sc[$i]
    if (-not $scene.assets -or -not $scene.assets.image) { return $false }
    $rel = [string]$scene.assets.image
    if (-not $rel) { return $false }
    $rel = $rel.Replace("/", "\")
    $abs = Join-Path $live $rel
    if (-not (Test-Path -LiteralPath $abs)) { return $false }
  }
  return $true
}

# Si no Force y ya está todo OK (scenes + images), hacemos skip limpio
if (-not $Force) {
  if (ScenesHaveValidImages -N $MaxScenes) {
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
$fallbackRel = $fallbackRel.Replace("/", "\")
$fallbackAbs = (Resolve-Path (Join-Path $live $fallbackRel)).Path

for ($i=0; $i -lt @($m.scenes_v03).Count; $i++) {
  $scene = $m.scenes_v03[$i]
  if (-not $scene.assets) {
    $scene | Add-Member -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{ image = "" })
  }
  if (-not $scene.assets.image) { $scene.assets.image = "" }

  $outName = ("scene_{0:000}.jpg" -f ($i+1))
  $outAbs  = Join-Path $assetsDir $outName
  $outRel  = ("assets/scenes_v03/{0}" -f $outName)

  $q = $scene.text
  if (-not $q -or $q.Trim().Length -lt 3) { $q = "motivación" }
  $q = $q.Trim()

  $picked = $null
  $cacheJson = Join-Path $cacheDir ("pixabay_scene_{0:000}.json" -f ($i+1))

  try {
    if ($env:PIXABAY_API_KEY -and (Test-Path -LiteralPath $pixQuery) -and (Test-Path -LiteralPath $dlTool)) {
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
    }
  } catch { $picked = $null }

  $ok = $false
  if ($picked) {
    try {
      pwsh -NoProfile -ExecutionPolicy Bypass -File $dlTool -Url $picked -OutPath $outAbs | Out-Null
      $scene.assets.image = $outRel
      $ok = $true
      Write-Host "OK: scene[$i] image=PIXABAY -> $outRel" -ForegroundColor DarkGray
    } catch { $ok = $false }
  }

  if (-not $ok) {
    Copy-Item -LiteralPath $fallbackAbs -Destination $outAbs -Force
    $scene.assets.image = $outRel
    Write-Host "OK: scene[$i] image=FALLBACK(artifacts.image) -> $outRel" -ForegroundColor DarkGray
  }
}

$out = $m | ConvertTo-Json -Depth 50
Set-Content -LiteralPath $manifest -Value $out -Encoding UTF8

Write-Host ("OK: scene_builder v03 aplicado. scenes={0} live={1} force={2}" -f @($m.scenes_v03).Count, $live, [bool]$Force) -ForegroundColor Green
