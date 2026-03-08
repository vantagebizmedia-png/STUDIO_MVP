param(
  [Parameter(Mandatory=$false)][string]$LiveDir,
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Resolve-LiveDir {
  param(
    [string]$LiveDir,
    [string]$WorkspaceRoot
  )

  if ($LiveDir -and $LiveDir.Trim().Length -gt 0) {
    return (Resolve-Path $LiveDir).Path
  }

  if ($WorkspaceRoot -and $WorkspaceRoot.Trim().Length -gt 0) {
    $candidate = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
    return (Resolve-Path $candidate).Path
  }

  throw "Falta -LiveDir o -WorkspaceRoot"
}

function Read-JsonFile {
  param([Parameter(Mandatory=$true)][string]$Path)
  return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-ScalarText {
  param($Value)

  if ($null -eq $Value) { return "" }

  if ($Value -is [string]) {
    return $Value.Trim()
  }

  $p = $Value.PSObject.Properties["path"]
  if ($null -ne $p) {
    return ([string]$p.Value).Trim()
  }

  $p = $Value.PSObject.Properties["text"]
  if ($null -ne $p) {
    return ([string]$p.Value).Trim()
  }

  return ([string]$Value).Trim()
}

function Get-SceneText {
  param($Scene)

  foreach ($name in @("text","script","caption","subtitle","narration","voice_text")) {
    $p = $Scene.PSObject.Properties[$name]
    if ($null -ne $p) {
      $v = Get-ScalarText -Value $p.Value
      if ($v.Length -gt 0) { return $v }
    }
  }

  return ""
}

function Get-SceneImage {
  param($Scene)

  foreach ($name in @("image","image_path")) {
    $p = $Scene.PSObject.Properties[$name]
    if ($null -ne $p) {
      $v = Get-ScalarText -Value $p.Value
      if ($v.Length -gt 0) { return $v }
    }
  }

  $assetsProp = $Scene.PSObject.Properties["assets"]
  if ($null -ne $assetsProp -and $null -ne $assetsProp.Value) {
    $assets = $assetsProp.Value
    foreach ($name in @("image","image_path")) {
      $p = $assets.PSObject.Properties[$name]
      if ($null -ne $p) {
        $v = Get-ScalarText -Value $p.Value
        if ($v.Length -gt 0) { return $v }
      }
    }
  }

  return ""
}

function Get-SceneAudio {
  param($Scene)

  foreach ($name in @("audio","audio_clip","audio_path")) {
    $p = $Scene.PSObject.Properties[$name]
    if ($null -ne $p) {
      $v = Get-ScalarText -Value $p.Value
      if ($v.Length -gt 0) { return $v }
    }
  }

  $assetsProp = $Scene.PSObject.Properties["assets"]
  if ($null -ne $assetsProp -and $null -ne $assetsProp.Value) {
    $assets = $assetsProp.Value
    foreach ($name in @("audio","audio_clip","audio_path")) {
      $p = $assets.PSObject.Properties[$name]
      if ($null -ne $p) {
        $v = Get-ScalarText -Value $p.Value
        if ($v.Length -gt 0) { return $v }
      }
    }
  }

  return ""
}

function Get-SceneStartMs {
  param($Scene)

  foreach ($name in @("start_ms","t0_ms","from_ms")) {
    $p = $Scene.PSObject.Properties[$name]
    if ($null -ne $p) { return [int64]$p.Value }
  }

  return 0
}

function Get-SceneEndMs {
  param($Scene)

  foreach ($name in @("end_ms","t1_ms","to_ms")) {
    $p = $Scene.PSObject.Properties[$name]
    if ($null -ne $p) { return [int64]$p.Value }
  }

  return 0
}

function Ms-ToTime {
  param([int64]$Ms)

  if ($Ms -lt 0) { $Ms = 0 }
  $ts = [TimeSpan]::FromMilliseconds($Ms)
  return "{0:00}:{1:00}:{2:00}.{3:000}" -f [int]$ts.Hours, [int]$ts.Minutes, [int]$ts.Seconds, [int]$ts.Milliseconds
}

$live = Resolve-LiveDir -LiveDir $LiveDir -WorkspaceRoot $WorkspaceRoot
$manifestPath = Join-Path $live "manifest_v03.json"

if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "Falta manifest_v03.json en: $live"
}

$manifest = Read-JsonFile -Path $manifestPath

$scenes = $null
if ($null -ne $manifest.PSObject.Properties["scenes_v03"]) {
  $scenes = @($manifest.scenes_v03)
} elseif ($null -ne $manifest.PSObject.Properties["scenes"]) {
  $scenes = @($manifest.scenes)
} else {
  throw "El manifest no contiene scenes_v03 ni scenes"
}

$previewDir = Join-Path $live "preview"
New-Item -ItemType Directory -Force -Path $previewDir | Out-Null

$sceneRows = New-Object System.Collections.Generic.List[object]

for ($i = 0; $i -lt $scenes.Count; $i++) {
  $scene = $scenes[$i]

  $startMs = Get-SceneStartMs -Scene $scene
  $endMs   = Get-SceneEndMs   -Scene $scene
  $durMs   = [Math]::Max(0, ($endMs - $startMs))

  $text  = Get-SceneText  -Scene $scene
  $image = Get-SceneImage -Scene $scene
  $audio = Get-SceneAudio -Scene $scene

  $sceneRows.Add([pscustomobject]@{
    scene_index = $i
    scene_id    = ("scene_{0:d3}" -f ($i + 1))
    start_ms    = $startMs
    end_ms      = $endMs
    duration_ms = $durMs
    start_tc    = (Ms-ToTime -Ms $startMs)
    end_tc      = (Ms-ToTime -Ms $endMs)
    image       = $image
    audio       = $audio
    text        = $text
  }) | Out-Null
}

$jsonPath = Join-Path $previewDir "scene_index.json"
$txtPath  = Join-Path $previewDir "scene_index.txt"
$ovrPath  = Join-Path $previewDir "overrides_v03.json"

$sceneRows | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("STUDIO_MVP PREVIEW v0.3") | Out-Null
$lines.Add("LIVE: $live") | Out-Null
$lines.Add("MANIFEST: $manifestPath") | Out-Null
$lines.Add("SCENES: $($sceneRows.Count)") | Out-Null
$lines.Add("") | Out-Null

foreach ($row in $sceneRows) {
  $lines.Add(("[{0}] {1}  {2} -> {3}  dur={4}ms" -f $row.scene_index, $row.scene_id, $row.start_tc, $row.end_tc, $row.duration_ms)) | Out-Null
  $lines.Add(("  IMAGE: {0}" -f $row.image)) | Out-Null
  $lines.Add(("  AUDIO: {0}" -f $row.audio)) | Out-Null
  $lines.Add(("  TEXT : {0}" -f $row.text)) | Out-Null
  $lines.Add("") | Out-Null
}

[System.IO.File]::WriteAllLines($txtPath, $lines, [System.Text.UTF8Encoding]::new($false))

if (-not (Test-Path -LiteralPath $ovrPath)) {
  $defaultOverrides = [pscustomobject]@{
    version = "v0.3"
    live_dir = $live
    created_utc = [DateTime]::UtcNow.ToString("o")
    notes = @(
      "Editar este archivo de overrides en vez del manifest",
      "Los cambios deben ser explícitos y deterministas"
    )
    scene_overrides = @()
    actions = [pscustomobject]@{
      regenerate_srt = $false
      regenerate_render = $false
      regenerate_final = $false
    }
  }

  $defaultOverrides | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ovrPath -Encoding UTF8
}

Write-Host "OK preview generado" -ForegroundColor Green
Write-Host "  JSON : $jsonPath"
Write-Host "  TXT  : $txtPath"
Write-Host "  OVR  : $ovrPath"