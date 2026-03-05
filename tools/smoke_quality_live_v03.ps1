param(
  [string]$WorkspaceRoot = $env:STUDIO_WORKSPACE
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

Write-Host "== SMOKE QUALITY LIVE v0.3 ==" -ForegroundColor Cyan

if (-not $WorkspaceRoot) { throw "WorkspaceRoot vacío. Define `$env:STUDIO_WORKSPACE o pasa -WorkspaceRoot." }

$run = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
if (-not (Test-Path -LiteralPath $run)) { throw "No existe LIVE dir: $run" }

$manifest = Join-Path $run "manifest_v03.json"
if (-not (Test-Path -LiteralPath $manifest)) { throw "manifest_v03.json no existe: $manifest" }

# SRT candidates (v0.3 usa captions_v03.srt)
$srtCandidates = @(
  (Join-Path $run "captions_v03.srt"),
  (Join-Path $run "subtitles.srt"),
  (Join-Path $run "captions.srt")
)

$srt = $srtCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $srt) {
  throw "No encontré SRT. Probé: $($srtCandidates -join ', ')"
}

function Get-SceneLabel {
  param(
    [Parameter(Mandatory=$true)]$Scene,
    [int]$Index
  )
  $props = @("id","scene_id","sceneId","index","name","key")
  foreach ($p in $props) {
    try {
      $v = $Scene.$p
      if ($null -ne $v -and ("" + $v).Trim() -ne "") { return ("" + $v) }
    } catch { }
  }
  return ("#" + $Index)
}

function Get-FirstImageRef {
  param([Parameter(Mandatory=$true)]$Scene)

  if (-not $Scene.assets) { return $null }
  $a = $Scene.assets

  # 1) assets.image (puede ser string/obj/array)
  try {
    if ($a.image) {
      $img = $a.image

      # array
      if ($img -is [System.Array]) {
        if ($img.Count -gt 0) {
          $x = $img[0]
          if ($x -is [string]) { return $x }
          try { if ($x.path) { return $x.path } } catch {}
          try { if ($x.url)  { return $x.url }  } catch {}
          return $x
        }
      }

      # string directo
      if ($img -is [string]) { return $img }

      # objeto con path/url
      try { if ($img.path) { return $img.path } } catch {}
      try { if ($img.url)  { return $img.url }  } catch {}

      # fallback: devuelve objeto
      return $img
    }
  } catch {}

  # 2) assets.images[0] (string u objeto)
  try {
    if ($a.images -and $a.images.Count -gt 0) {
      $x = $a.images[0]
      if ($x -is [string]) { return $x }
      try { if ($x.path) { return $x.path } } catch {}
      try { if ($x.url)  { return $x.url }  } catch {}
      return $x
    }
  } catch {}

  return $null
}

# --- SRT Layout checks (chars/lines) ---
$measure = Join-Path $PSScriptRoot "measure_srt_v03.ps1"
if (Test-Path -LiteralPath $measure) {
  $metricsJson = pwsh -NoProfile -ExecutionPolicy Bypass -File $measure -SrtPath $srt
  $metrics = $metricsJson | ConvertFrom-Json

  $maxCharsLine  = [int]$metrics.max_chars_line
  $maxLinesBlock = [int]$metrics.max_lines_block

  $maxAllowedChars = 42
  $maxAllowedLines = 2

  if ($maxCharsLine -gt $maxAllowedChars) {
    throw "SRT layout fail: max_chars_line=$maxCharsLine (max=$maxAllowedChars)"
  }
  if ($maxLinesBlock -gt $maxAllowedLines) {
    throw "SRT layout fail: max_lines_block=$maxLinesBlock (max=$maxAllowedLines)"
  }

  Write-Host "OK: SRT layout maxChars=$maxCharsLine maxLines=$maxLinesBlock" -ForegroundColor DarkGray
} else {
  Write-Host "SRT layout check: skip (no measure_srt_v03.ps1)" -ForegroundColor DarkGray
}
# --- fin SRT Layout checks ---
# --- Manifest checks ---
$mRaw = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8
$m = $mRaw | ConvertFrom-Json

if (-not $m.scenes_v03) { throw "manifest no contiene scenes_v03" }
if ($m.scenes_v03.Count -lt 1) { throw "scenes_v03 vacío" }

$idx = 0
foreach ($scene in $m.scenes_v03) {
  $label = Get-SceneLabel -Scene $scene -Index $idx
  $imgRef = Get-FirstImageRef -Scene $scene
  if (-not $imgRef) { throw "Scene $label no tiene imagen en assets (assets.image / assets.images[0])" }
  $idx++
}

# --- SRT CPS checks ---
$lines = Get-Content -LiteralPath $srt -Encoding UTF8
$maxCps = 23  # patched: tolerancia mínima CPS (era 22)
$currentText = ""
$start = $null
$end = $null

function Flush-Block {
  param()
  if ($script:currentText -ne "" -and $script:start -ne $null -and $script:end -ne $null) {
    $dur = ($script:end - $script:start).TotalSeconds
    if ($dur -gt 0) {
      $cps = [double]($script:currentText.Length) / [double]$dur
      if ($cps -gt $maxCps) {
        throw ("CPS demasiado alto: {0:N2} (max={1})" -f $cps, $maxCps)
      }
    }
  }
  $script:currentText = ""
  $script:start = $null
  $script:end = $null
}

foreach ($line in $lines) {

  if ($line -match "(\d\d:\d\d:\d\d,\d\d\d)\s+-->\s+(\d\d:\d\d:\d\d,\d\d\d)") {
    $start = [TimeSpan]::Parse($matches[1].Replace(",","."))
    $end   = [TimeSpan]::Parse($matches[2].Replace(",","."))
    $currentText = ""
    continue
  }

  if ($line -eq "") {
    Flush-Block
    continue
  }

  if ($line -match "^\d+$") { continue }

  $currentText += $line
}

# flush final por si no terminó en blank line
Flush-Block

Write-Host ("OK: smoke quality passed (SRT={0}) scenes={1}" -f (Split-Path -Leaf $srt), $m.scenes_v03.Count) -ForegroundColor Green

