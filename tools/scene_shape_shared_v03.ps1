Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToScenePsoShared {
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

function New-SceneScaffoldShared {
  param(
    [Parameter(Mandatory=$true)][int]$Ordinal
  )

  if ($Ordinal -lt 1) {
    throw ("Ordinal inválido para New-SceneScaffoldShared: {0}" -f $Ordinal)
  }

  return [pscustomobject]@{
    id                   = ("scene_{0:000}" -f $Ordinal)
    start_ms             = 0
    end_ms               = 0
    duration_ms          = 0
    text                 = ""
    script_text          = ""
    image_query          = ""
    requested_media_type = ""
    visual_request_kind  = ""
    visual_kind          = "image"
    visual_source_kind   = "fallback_image"
    visual_capability    = "stock_image"
    assets               = [pscustomobject]@{
      audio_clip = ""
      image      = ""
      video      = ""
    }
  }
}

function Ensure-SceneNarrativeSlotsShared {
  param(
    [Parameter(Mandatory=$true)]$Scene
  )

  if (-not ($Scene.PSObject.Properties.Name -contains "text")) {
    $Scene | Add-Member -Force -NotePropertyName text -NotePropertyValue ""
  }

  if (-not ($Scene.PSObject.Properties.Name -contains "script_text")) {
    $Scene | Add-Member -Force -NotePropertyName script_text -NotePropertyValue ""
  }

  if (-not ($Scene.PSObject.Properties.Name -contains "image_query")) {
    $Scene | Add-Member -Force -NotePropertyName image_query -NotePropertyValue ""
  }

  if (-not ($Scene.PSObject.Properties.Name -contains "requested_media_type")) {
    $Scene | Add-Member -Force -NotePropertyName requested_media_type -NotePropertyValue ""
  }

  if (-not ($Scene.PSObject.Properties.Name -contains "visual_request_kind")) {
    $Scene | Add-Member -Force -NotePropertyName visual_request_kind -NotePropertyValue ""
  }

  $requestedMediaType = ""
  try { $requestedMediaType = ([string]$Scene.requested_media_type).Trim().ToLowerInvariant() } catch { $requestedMediaType = "" }
  if ($requestedMediaType -notin @("image","video")) { $requestedMediaType = "" }

  $visualRequestKind = ""
  try { $visualRequestKind = ([string]$Scene.visual_request_kind).Trim().ToLowerInvariant() } catch { $visualRequestKind = "" }
  if ($visualRequestKind -notin @("image","video")) { $visualRequestKind = "" }

  if (-not [string]::IsNullOrWhiteSpace($requestedMediaType) -and [string]::IsNullOrWhiteSpace($visualRequestKind)) {
    $Scene.visual_request_kind = $requestedMediaType
    return
  }

  if (-not [string]::IsNullOrWhiteSpace($visualRequestKind) -and [string]::IsNullOrWhiteSpace($requestedMediaType)) {
    $Scene.requested_media_type = $visualRequestKind
    return
  }

  if (
    (-not [string]::IsNullOrWhiteSpace($requestedMediaType)) -and
    (-not [string]::IsNullOrWhiteSpace($visualRequestKind))
  ) {
    return
  }

  $legacyCapability = ""
  if ($Scene.PSObject.Properties.Name -contains "visual_capability") {
    try { $legacyCapability = ([string]$Scene.visual_capability).Trim().ToLowerInvariant() } catch { $legacyCapability = "" }
  }

  $legacyKind = ""
  if ($Scene.PSObject.Properties.Name -contains "visual_kind") {
    try { $legacyKind = ([string]$Scene.visual_kind).Trim().ToLowerInvariant() } catch { $legacyKind = "" }
  }

  if (($legacyCapability -eq "stock_video") -or ($legacyKind -eq "video")) {
    $Scene.requested_media_type = "video"
    $Scene.visual_request_kind  = "video"
  }
}

function Ensure-SceneAssetSlotsShared {
  param(
    [Parameter(Mandatory=$true)]$Scene
  )

  if (-not ($Scene.PSObject.Properties.Name -contains "assets") -or -not $Scene.assets) {
    $Scene | Add-Member -Force -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{})
  }
  else {
    $Scene.assets = Convert-ToScenePsoShared -Value $Scene.assets
  }

  if (-not ($Scene.assets.PSObject.Properties.Name -contains "audio_clip")) {
    $Scene.assets | Add-Member -Force -NotePropertyName audio_clip -NotePropertyValue ""
  }

  if (-not ($Scene.assets.PSObject.Properties.Name -contains "image")) {
    $Scene.assets | Add-Member -Force -NotePropertyName image -NotePropertyValue ""
  }

  if (-not ($Scene.assets.PSObject.Properties.Name -contains "video")) {
    $Scene.assets | Add-Member -Force -NotePropertyName video -NotePropertyValue ""
  }
}