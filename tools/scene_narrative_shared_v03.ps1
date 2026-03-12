Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FirstTrimmedSceneStringShared {
  param(
    [Parameter(Mandatory=$true)]$Scene,
    [Parameter(Mandatory=$true)][string[]]$Keys
  )

  foreach ($k in @($Keys)) {
    if ([string]::IsNullOrWhiteSpace($k)) { continue }

    try {
      $prop = $Scene.PSObject.Properties[$k]
      if (-not $prop) { continue }

      $raw = $prop.Value
      if ($null -eq $raw) { continue }

      $v = [string]$raw
      if (-not [string]::IsNullOrWhiteSpace($v)) {
        return $v.Trim()
      }
    }
    catch { }
  }

  return ""
}

function Get-SceneTextShared {
  param(
    [Parameter(Mandatory=$true)]$Scene
  )

  return (Get-FirstTrimmedSceneStringShared -Scene $Scene -Keys @(
    "text",
    "script_text",
    "narration",
    "caption",
    "onscreen"
  ))
}

function Get-SceneQueryShared {
  param(
    [Parameter(Mandatory=$true)]$Scene
  )

  $explicit = Get-FirstTrimmedSceneStringShared -Scene $Scene -Keys @(
    "image_query",
    "query",
    "stock_query"
  )

  if (-not [string]::IsNullOrWhiteSpace($explicit)) {
    return $explicit
  }

  $fallback = Get-SceneTextShared -Scene $Scene
  if (-not [string]::IsNullOrWhiteSpace($fallback)) {
    return $fallback
  }

  return "motivacion"
}

function Ensure-SceneNarrativeValuesShared {
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

  $textValue = Get-SceneTextShared -Scene $Scene
  if (-not [string]::IsNullOrWhiteSpace($textValue)) {
    if ([string]::IsNullOrWhiteSpace([string]$Scene.text)) {
      $Scene.text = [string]$textValue
    }

    if ([string]::IsNullOrWhiteSpace([string]$Scene.script_text)) {
      $Scene.script_text = [string]$textValue
    }
  }

  $explicitQuery = Get-FirstTrimmedSceneStringShared -Scene $Scene -Keys @(
    "image_query",
    "query",
    "stock_query"
  )

  if (-not [string]::IsNullOrWhiteSpace($explicitQuery)) {
    if ([string]::IsNullOrWhiteSpace([string]$Scene.image_query)) {
      $Scene.image_query = [string]$explicitQuery
    }
  }
}