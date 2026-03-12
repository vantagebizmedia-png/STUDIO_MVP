Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-AssetValueShared {
  param($Value)

  if ($null -eq $Value) { return "" }

  if ($Value -is [string]) {
    return [string]$Value
  }

  if ($Value -is [pscustomobject] -or $Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
    try {
      if ($Value.PSObject.Properties["path"] -and $Value.path) {
        return [string]$Value.path
      }
    }
    catch { }

    return ""
  }

  if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
    $arr = @($Value)
    if ($arr.Count -gt 0) {
      return (Resolve-AssetValueShared -Value $arr[0])
    }
  }

  return ""
}

function Get-AssetPathValueShared {
  param(
    $AssetsObj,
    [string]$Key
  )

  if (-not $AssetsObj) { return "" }
  if ([string]::IsNullOrWhiteSpace($Key)) { return "" }

  $prop = $null
  try {
    $prop = $AssetsObj.PSObject.Properties[$Key]
  }
  catch {
    $prop = $null
  }

  if (-not $prop) { return "" }

  return (Resolve-AssetValueShared -Value $prop.Value)
}