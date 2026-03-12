Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToVisualMetaPsoShared {
  param([object]$Value)

  if ($null -eq $Value) { return [pscustomobject]@{} }
  if ($Value -is [pscustomobject]) { return $Value }

  if ($Value -is [System.Collections.IDictionary]) {
    $h = @{}
    foreach ($k in $Value.Keys) {
      $h[[string]$k] = $Value[$k]
    }
    return [pscustomobject]$h
  }

  if ($Value -is [string] -or $Value -is [ValueType]) {
    return [pscustomobject]@{}
  }

  return [pscustomobject]$Value
}

function Ensure-SceneVisualMetaSlotShared {
  param(
    [Parameter(Mandatory=$true)]$Scene,
    [Parameter(Mandatory=$true)][ValidateSet("image","video")][string]$Kind
  )

  if (-not ($Scene.PSObject.Properties.Name -contains "assets") -or -not $Scene.assets) {
    $Scene | Add-Member -Force -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{})
  }

  $propName = if ($Kind -eq "video") { "video_meta" } else { "image_meta" }

  $meta = $null
  try {
    if ($Scene.assets.PSObject.Properties[$propName] -and $Scene.assets.$propName) {
      $meta = $Scene.assets.$propName
    }
  }
  catch {
    $meta = $null
  }

  if (-not $meta) {
    $meta = [pscustomobject]@{}
    if (-not ($Scene.assets.PSObject.Properties.Name -contains $propName)) {
      $Scene.assets | Add-Member -Force -NotePropertyName $propName -NotePropertyValue $meta
    }
    else {
      $Scene.assets.$propName = $meta
    }
  }
  else {
    $meta = Convert-ToVisualMetaPsoShared -Value $meta
    $Scene.assets.$propName = $meta
  }

  return $meta
}

function Clear-InactiveSceneVisualMetaShared {
  param(
    [Parameter(Mandatory=$true)]$Scene,
    [Parameter(Mandatory=$true)][ValidateSet("image","video")][string]$ActiveKind
  )

  if (-not ($Scene.PSObject.Properties.Name -contains "assets") -or -not $Scene.assets) {
    return
  }

  $inactiveProp = if ($ActiveKind -eq "video") { "image_meta" } else { "video_meta" }

  if ($Scene.assets.PSObject.Properties.Name -contains $inactiveProp) {
    $Scene.assets.$inactiveProp = $null
  }
}

function Update-SceneVisualMetaShared {
  param(
    [Parameter(Mandatory=$true)]$Scene,
    [Parameter(Mandatory=$true)][ValidateSet("image","video")][string]$Kind,
    [Parameter(Mandatory=$false)][string]$Query = "",
    [Parameter(Mandatory=$false)][string]$FallbackProvider = "repair_live_manifest_v03"
  )

  $meta = Ensure-SceneVisualMetaSlotShared -Scene $Scene -Kind $Kind
  $sourceKind = if ($Kind -eq "video") { "stock_video" } else { "stock_image" }

  $providerValue = $FallbackProvider
  try {
    if ($meta.PSObject.Properties["provider"] -and -not [string]::IsNullOrWhiteSpace([string]$meta.provider)) {
      $providerValue = [string]$meta.provider
    }
  }
  catch { }

  $cacheHitValue = $false
  try {
    if ($meta.PSObject.Properties["cache_hit"]) {
      $cacheHitValue = [bool]$meta.cache_hit
    }
  }
  catch { }

  $cacheKeyValue = ""
  try {
    if ($meta.PSObject.Properties["cache_key"] -and $meta.cache_key) {
      $cacheKeyValue = [string]$meta.cache_key
    }
  }
  catch { }

  $meta | Add-Member -Force -NotePropertyName provider -NotePropertyValue $providerValue
  $meta | Add-Member -Force -NotePropertyName cache_hit -NotePropertyValue $cacheHitValue
  $meta | Add-Member -Force -NotePropertyName cache_key -NotePropertyValue $cacheKeyValue
  $meta | Add-Member -Force -NotePropertyName query -NotePropertyValue ([string]$Query)
  $meta | Add-Member -Force -NotePropertyName source_kind -NotePropertyValue $sourceKind

  Clear-InactiveSceneVisualMetaShared -Scene $Scene -ActiveKind $Kind

  return $meta
}