param(
  [Parameter(Mandatory=$false)][string]$LiveDir,
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$psUtf8Compat = Join-Path $PSScriptRoot "ps_utf8_compat_v03.ps1"
if (-not (Test-Path -LiteralPath $psUtf8Compat -PathType Leaf)) {
  throw ("No existe helper utf8 compat: {0}" -f $psUtf8Compat)
}

. $psUtf8Compat

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

function Write-JsonFile {
  param(
    [Parameter(Mandatory=$true)]$Object,
    [Parameter(Mandatory=$true)][string]$Path
  )

  $json = $Object | ConvertTo-Json -Depth 100
  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Ensure-NoteProperty {
  param(
    [Parameter(Mandatory=$true)]$Object,
    [Parameter(Mandatory=$true)][string]$Name,
    $Value
  )

  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  } else {
    $prop.Value = $Value
  }
}

function Set-SceneTextValue {
  param(
    [Parameter(Mandatory=$true)]$Scene,
    [Parameter(Mandatory=$true)][string]$Value
  )

  foreach ($name in @("text","script","caption","subtitle","narration","voice_text")) {
    $prop = $Scene.PSObject.Properties[$name]
    if ($null -ne $prop) {
      $prop.Value = $Value
      return
    }
  }

  Ensure-NoteProperty -Object $Scene -Name "text" -Value $Value
}

function Set-PathLikeValue {
  param(
    [Parameter(Mandatory=$true)]$Object,
    [Parameter(Mandatory=$true)][string]$PropName,
    [Parameter(Mandatory=$true)][string]$PathValue
  )

  $prop = $Object.PSObject.Properties[$PropName]
  if ($null -eq $prop) {
    return $false
  }

  if ($null -eq $prop.Value) {
    $prop.Value = $PathValue
    return $true
  }

  if ($prop.Value -is [string]) {
    $prop.Value = $PathValue
    return $true
  }

  $pathProp = $prop.Value.PSObject.Properties["path"]
  if ($null -ne $pathProp) {
    $pathProp.Value = $PathValue
    return $true
  }

  $prop.Value = $PathValue
  return $true
}

function Set-SceneImagePath {
  param(
    [Parameter(Mandatory=$true)]$Scene,
    [Parameter(Mandatory=$true)][string]$PathValue
  )

  $done = $false

  foreach ($name in @("image","image_path")) {
    if (Set-PathLikeValue -Object $Scene -PropName $name -PathValue $PathValue) {
      $done = $true
    }
  }

  $assetsProp = $Scene.PSObject.Properties["assets"]
  if ($null -ne $assetsProp -and $null -ne $assetsProp.Value) {
    $assets = $assetsProp.Value
    foreach ($name in @("image","image_path")) {
      if (Set-PathLikeValue -Object $assets -PropName $name -PathValue $PathValue) {
        $done = $true
      }
    }
  }

  if (-not $done) {
    Ensure-NoteProperty -Object $Scene -Name "image_path" -Value $PathValue
  }
}

function Set-SceneAudioPath {
  param(
    [Parameter(Mandatory=$true)]$Scene,
    [Parameter(Mandatory=$true)][string]$PathValue
  )

  $done = $false

  foreach ($name in @("audio","audio_clip","audio_path")) {
    if (Set-PathLikeValue -Object $Scene -PropName $name -PathValue $PathValue) {
      $done = $true
    }
  }

  $assetsProp = $Scene.PSObject.Properties["assets"]
  if ($null -ne $assetsProp -and $null -ne $assetsProp.Value) {
    $assets = $assetsProp.Value
    foreach ($name in @("audio","audio_clip","audio_path")) {
      if (Set-PathLikeValue -Object $assets -PropName $name -PathValue $PathValue) {
        $done = $true
      }
    }
  }

  if (-not $done) {
    Ensure-NoteProperty -Object $Scene -Name "audio_path" -Value $PathValue
  }
}

function Set-SceneMsValue {
  param(
    [Parameter(Mandatory=$true)]$Scene,
    [Parameter(Mandatory=$true)][string]$PrimaryName,
    [Parameter(Mandatory=$true)][Int64]$Value
  )

  $prop = $Scene.PSObject.Properties[$PrimaryName]
  if ($null -ne $prop) {
    $prop.Value = $Value
  } else {
    Ensure-NoteProperty -Object $Scene -Name $PrimaryName -Value $Value
  }
}

$live = Resolve-LiveDir -LiveDir $LiveDir -WorkspaceRoot $WorkspaceRoot

$previewDir   = Join-Path $live "preview"
$manifestPath = Join-Path $live "manifest_v03.json"
$ovrPath      = Join-Path $previewDir "overrides_v03.json"
$summaryPath  = Join-Path $previewDir "overrides_applied_summary.txt"

if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "Falta manifest_v03.json en: $manifestPath"
}

if (-not (Test-Path -LiteralPath $ovrPath)) {
  throw "Falta overrides_v03.json en: $ovrPath"
}

$manifest  = Read-JsonFile -Path $manifestPath
$overrides = Read-JsonFile -Path $ovrPath

$scenesPropName = $null
if ($null -ne $manifest.PSObject.Properties["scenes_v03"]) {
  $scenesPropName = "scenes_v03"
} elseif ($null -ne $manifest.PSObject.Properties["scenes"]) {
  $scenesPropName = "scenes"
} else {
  throw "El manifest no contiene scenes_v03 ni scenes"
}

$scenes = @($manifest.$scenesPropName)

$sceneOverridesProp = $overrides.PSObject.Properties["scene_overrides"]
if ($null -eq $sceneOverridesProp -or $null -eq $sceneOverridesProp.Value) {
  throw "overrides_v03.json no contiene scene_overrides"
}

$sceneOverrides = @($sceneOverridesProp.Value)

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("STUDIO_MVP APPLY PREVIEW OVERRIDES v0.3") | Out-Null
$summary.Add("LIVE: $live") | Out-Null
$summary.Add("MANIFEST: $manifestPath") | Out-Null
$summary.Add("OVERRIDES: $ovrPath") | Out-Null
$summary.Add("COUNT: $($sceneOverrides.Count)") | Out-Null
$summary.Add("") | Out-Null

if ($sceneOverrides.Count -eq 0) {
  $summary.Add("No hay scene_overrides para aplicar.") | Out-Null
  [System.IO.File]::WriteAllLines($summaryPath, $summary, [System.Text.UTF8Encoding]::new($false))
  Write-Host "Sin cambios: scene_overrides vacío" -ForegroundColor Yellow
  Write-Host "SUMMARY: $summaryPath"
  exit 0
}

$manifestBackup = "$manifestPath.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item -LiteralPath $manifestPath -Destination $manifestBackup -Force

foreach ($ovr in $sceneOverrides) {
  $idxProp = $ovr.PSObject.Properties["scene_index"]
  if ($null -eq $idxProp) {
    throw "Cada override requiere scene_index"
  }

  $idx = [int]$idxProp.Value

  if ($idx -lt 0 -or $idx -ge $scenes.Count) {
    throw "scene_index fuera de rango: $idx"
  }

  $scene = $scenes[$idx]
  $summary.Add(("[scene {0}] inicio" -f $idx)) | Out-Null

  $p = $ovr.PSObject.Properties["text"]
  if ($null -ne $p -and $null -ne $p.Value) {
    $value = [string]$p.Value
    Set-SceneTextValue -Scene $scene -Value $value
    $summary.Add(("  text        = {0}" -f $value)) | Out-Null
  }

  $p = $ovr.PSObject.Properties["image_path"]
  if ($null -ne $p -and $null -ne $p.Value) {
    $value = [string]$p.Value
    Set-SceneImagePath -Scene $scene -PathValue $value
    $summary.Add(("  image_path  = {0}" -f $value)) | Out-Null
  }

  $p = $ovr.PSObject.Properties["audio_path"]
  if ($null -ne $p -and $null -ne $p.Value) {
    $value = [string]$p.Value
    Set-SceneAudioPath -Scene $scene -PathValue $value
    $summary.Add(("  audio_path  = {0}" -f $value)) | Out-Null
  }

  $p = $ovr.PSObject.Properties["start_ms"]
  if ($null -ne $p -and $null -ne $p.Value) {
    $value = [int64]$p.Value
    Set-SceneMsValue -Scene $scene -PrimaryName "start_ms" -Value $value
    $summary.Add(("  start_ms    = {0}" -f $value)) | Out-Null
  }

  $p = $ovr.PSObject.Properties["end_ms"]
  if ($null -ne $p -and $null -ne $p.Value) {
    $value = [int64]$p.Value
    Set-SceneMsValue -Scene $scene -PrimaryName "end_ms" -Value $value
    $summary.Add(("  end_ms      = {0}" -f $value)) | Out-Null
  }

  $summary.Add("") | Out-Null
}

Ensure-NoteProperty -Object $manifest -Name "preview_overrides_applied_utc" -Value ([DateTime]::UtcNow.ToString("o"))

Write-JsonFile -Object $manifest -Path $manifestPath
[System.IO.File]::WriteAllLines($summaryPath, $summary, [System.Text.UTF8Encoding]::new($false))

Write-Host "OK overrides aplicados" -ForegroundColor Green
Write-Host "  Manifest backup : $manifestBackup"
Write-Host "  Manifest actual : $manifestPath"
Write-Host "  Summary         : $summaryPath"
