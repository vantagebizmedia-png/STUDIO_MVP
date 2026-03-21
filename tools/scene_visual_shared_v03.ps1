Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToPackRelativePathShared {
  param(
    [Parameter(Mandatory=$true)][string]$BaseDir,
    [Parameter(Mandatory=$true)][string]$AbsolutePath
  )

  $base = (Resolve-Path -LiteralPath $BaseDir).Path
  $abs  = (Resolve-Path -LiteralPath $AbsolutePath).Path

  $baseUri = [System.Uri]::new($base.TrimEnd('\','/') + [System.IO.Path]::DirectorySeparatorChar)
  $absUri  = [System.Uri]::new($abs)
  $relUri  = $baseUri.MakeRelativeUri($absUri)
  $rel     = [System.Uri]::UnescapeDataString($relUri.ToString())

  return ($rel -replace '\\','/').Replace('\','/')
}

function Resolve-SceneAssetRelativePathShared {
  param(
    [Parameter(Mandatory=$false)][string]$BaseDir,
    [Parameter(Mandatory=$false)][string[]]$Candidates
  )

  if ([string]::IsNullOrWhiteSpace($BaseDir)) { return "" }

  foreach ($raw in @($Candidates)) {
    $candidate = [string]$raw
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }

    $candidate = $candidate.Trim()

    if ([System.IO.Path]::IsPathRooted($candidate)) {
      if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Convert-ToPackRelativePathShared -BaseDir $BaseDir -AbsolutePath $candidate)
      }
      continue
    }

    $abs = Join-Path $BaseDir ($candidate -replace '/', '\')
    if (Test-Path -LiteralPath $abs -PathType Leaf) {
      return (($candidate -replace '\\','/').Trim())
    }
  }

  return ""
}

function Get-ResolvedVisualKindShared {
  param(
    [Parameter(Mandatory=$false)][string]$CurrentVisualKind,
    [Parameter(Mandatory=$false)][string]$RequestedMediaType,
    [Parameter(Mandatory=$false)][string]$VisualRequestKind,
    [Parameter(Mandatory=$false)][string]$ResolvedImage,
    [Parameter(Mandatory=$false)][string]$ResolvedVideo
  )

  $vk = ""
  try { $vk = ([string]$CurrentVisualKind).Trim().ToLowerInvariant() } catch { $vk = "" }
  if ($vk -notin @("image","video")) { $vk = "" }

  $requested = ""
  try { $requested = ([string]$RequestedMediaType).Trim().ToLowerInvariant() } catch { $requested = "" }
  if ($requested -notin @("image","video")) { $requested = "" }

  $requestKind = ""
  try { $requestKind = ([string]$VisualRequestKind).Trim().ToLowerInvariant() } catch { $requestKind = "" }
  if ($requestKind -notin @("image","video")) { $requestKind = "" }

  $intentKind = ""
  if (-not [string]::IsNullOrWhiteSpace($requested)) {
    $intentKind = $requested
  }
  elseif (-not [string]::IsNullOrWhiteSpace($requestKind)) {
    $intentKind = $requestKind
  }

  $hasImage = -not [string]::IsNullOrWhiteSpace([string]$ResolvedImage)
  $hasVideo = -not [string]::IsNullOrWhiteSpace([string]$ResolvedVideo)

  if ($intentKind -eq "video") {
    if ($hasVideo) { return "video" }
    if ($hasImage) { return "image" }
    return "image"
  }

  if ($intentKind -eq "image") {
    if ($hasImage) { return "image" }
    if ($hasVideo) { return "video" }
    return "image"
  }

  if (($vk -eq "video") -and $hasVideo) { return "video" }
  if ($hasImage) { return "image" }
  if ($hasVideo) { return "video" }

  return "image"
}

function Get-ResolvedVisualSourceKindShared {
  param(
    [Parameter(Mandatory=$false)][string]$CurrentVisualSourceKind,
    [Parameter(Mandatory=$false)][string]$RuntimeResolvedSourceKind,
    [Parameter(Mandatory=$false)][string]$AssetResolvedSourceKind,
    [Parameter(Mandatory=$false)][string]$VisualKind
  )

  $vk = ""
  try { $vk = ([string]$VisualKind).Trim().ToLowerInvariant() } catch { $vk = "" }
  if ($vk -notin @("image","video")) { $vk = "" }

  $currentSource = ""
  try { $currentSource = ([string]$CurrentVisualSourceKind).Trim().ToLowerInvariant() } catch { $currentSource = "" }
  if ($currentSource -notmatch "(^|_)(image|video)$") { $currentSource = "" }

  $runtimeSource = ""
  try { $runtimeSource = ([string]$RuntimeResolvedSourceKind).Trim().ToLowerInvariant() } catch { $runtimeSource = "" }
  if ($runtimeSource -notmatch "(^|_)(image|video)$") { $runtimeSource = "" }

  $assetSource = ""
  try { $assetSource = ([string]$AssetResolvedSourceKind).Trim().ToLowerInvariant() } catch { $assetSource = "" }
  if ($assetSource -notmatch "(^|_)(image|video)$") { $assetSource = "" }

  if ($vk -eq "video") {
    if ($currentSource -match "(^|_)video$") { return $currentSource }
    if ($runtimeSource -match "(^|_)video$") { return $runtimeSource }
    if ($assetSource -match "(^|_)video$") { return $assetSource }
    return "stock_video"
  }

  if ($vk -eq "image") {
    if ($currentSource -match "(^|_)image$") { return $currentSource }
    if ($runtimeSource -match "(^|_)image$") { return $runtimeSource }
    if ($assetSource -match "(^|_)image$") { return $assetSource }
    return "stock_image"
  }

  if (-not [string]::IsNullOrWhiteSpace($currentSource)) { return $currentSource }
  if (-not [string]::IsNullOrWhiteSpace($runtimeSource)) { return $runtimeSource }
  if (-not [string]::IsNullOrWhiteSpace($assetSource)) { return $assetSource }

  return "stock_image"
}
