param(
  [Parameter(Mandatory=$true)][string]$LiveDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg) {
  throw "SMOKE FAIL: $msg"
}

function Get-StringOrEmpty {
  param($Value)

  if ($null -eq $Value) { return "" }

  try { return ([string]$Value).Trim() }
  catch { return "" }
}

function Get-ObjectPropertyValue {
  param(
    $Object,
    [Parameter(Mandatory=$true)][string]$Name
  )

  if ($null -eq $Object) {
    return $null
  }

  try {
    if ($Object -is [System.Collections.IDictionary]) {
      if ($Object.Contains($Name)) {
        return $Object[$Name]
      }
      return $null
    }
  }
  catch {
    return $null
  }

  try {
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) {
      return $prop.Value
    }
  }
  catch {
    return $null
  }

  return $null
}

function Get-NormalizedStringItems {
  param($Value)

  $items = @()

  if ($null -eq $Value) {
    return @($items)
  }

  if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
    foreach ($item in @($Value)) {
      $normalized = (Get-StringOrEmpty -Value $item).ToLowerInvariant()
      if (-not [string]::IsNullOrWhiteSpace($normalized)) {
        $items += $normalized
      }
    }

    return @($items)
  }

  $single = (Get-StringOrEmpty -Value $Value).ToLowerInvariant()
  if (-not [string]::IsNullOrWhiteSpace($single)) {
    $items += $single
  }

  return @($items)
}

function Get-UniqueNormalizedStringItems {
  param($Value)

  $out = @()
  foreach ($item in (Get-NormalizedStringItems -Value $Value)) {
    if ($item -notin $out) {
      $out += $item
    }
  }

  return @($out)
}

function Test-ExactStringList {
  param(
    [string[]]$Left,
    [string[]]$Right
  )

  $l = @($Left)
  $r = @($Right)

  if ($l.Count -ne $r.Count) {
    return $false
  }

  for ($i = 0; $i -lt $l.Count; $i++) {
    if ($l[$i] -ne $r[$i]) {
      return $false
    }
  }

  return $true
}

$live = (Resolve-Path -LiteralPath $LiveDir).Path

$manifestPath = Join-Path $live "manifest_v03.json"
$packPath = Join-Path $live "pack.json"

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  Fail "No existe manifest_v03.json en LIVE: $live"
}
if (-not (Test-Path -LiteralPath $packPath -PathType Leaf)) {
  Fail "No existe pack.json en LIVE: $live"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

$manifestScenes = Get-ObjectPropertyValue -Object $manifest -Name "scenes_v03"
$sceneBuilder = Get-ObjectPropertyValue -Object $manifest -Name "scene_builder_v03"

if (-not $manifestScenes) {
  Fail "manifest_v03.json no tiene scenes_v03"
}
if (-not $sceneBuilder) {
  Fail "manifest_v03.json no tiene scene_builder_v03"
}

$rootProviderOrderRaw = @(Get-NormalizedStringItems -Value (Get-ObjectPropertyValue -Object $sceneBuilder -Name "provider_order"))
$rootProviderOrder = @(Get-UniqueNormalizedStringItems -Value (Get-ObjectPropertyValue -Object $sceneBuilder -Name "provider_order"))

if ($rootProviderOrder.Count -lt 1) {
  Fail "scene_builder_v03.provider_order vacío"
}
if ($rootProviderOrderRaw.Count -ne $rootProviderOrder.Count) {
  Fail "scene_builder_v03.provider_order contiene duplicados"
}

$scenes = @($manifestScenes)
if ($scenes.Count -lt 1) {
  Fail "scenes_v03 vacío"
}

for ($i = 0; $i -lt $scenes.Count; $i++) {
  $scene = $scenes[$i]
  $sceneLabel = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $scene -Name "id")
  if ([string]::IsNullOrWhiteSpace($sceneLabel)) {
    $sceneLabel = ("scene_idx_{0}" -f $i)
  }

  $visualKind = (Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $scene -Name "visual_kind")).ToLowerInvariant()
  if ($visualKind -notin @("image", "video")) {
    Fail "$sceneLabel visual_kind inválido: '$visualKind'"
  }

  $sceneMeta = Get-ObjectPropertyValue -Object $scene -Name "meta"
  if (-not $sceneMeta) {
    Fail "$sceneLabel no tiene meta"
  }

  $visualEnrich = Get-ObjectPropertyValue -Object $sceneMeta -Name "visual_enrich"
  if (-not $visualEnrich) {
    Fail "$sceneLabel no tiene meta.visual_enrich"
  }

  $runtimeRequestedCapability = (Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_requested_capability")).ToLowerInvariant()
  if ($runtimeRequestedCapability -notin @("stock_image", "stock_video")) {
    Fail "$sceneLabel runtime_requested_capability inválido: '$runtimeRequestedCapability'"
  }

  $runtimeProviderSelectedRaw = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_provider_selected")
  $runtimeProviderSelected = $runtimeProviderSelectedRaw.ToLowerInvariant()

  if ([string]::IsNullOrWhiteSpace($runtimeProviderSelectedRaw)) {
    Fail "$sceneLabel runtime_provider_selected vacío"
  }
  if ($runtimeProviderSelectedRaw -ne $runtimeProviderSelected) {
    Fail "$sceneLabel runtime_provider_selected no normalizado: '$runtimeProviderSelectedRaw'"
  }

  $runtimeProviderOrderRaw = @(Get-NormalizedStringItems -Value (Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_provider_order"))
  $runtimeProviderOrder = @(Get-UniqueNormalizedStringItems -Value (Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_provider_order"))

  if ($runtimeProviderOrder.Count -lt 1) {
    Fail "$sceneLabel runtime_provider_order vacío"
  }
  if ($runtimeProviderOrderRaw.Count -ne $runtimeProviderOrder.Count) {
    Fail "$sceneLabel runtime_provider_order contiene duplicados"
  }
  if ($runtimeProviderSelected -notin $runtimeProviderOrder) {
    Fail "$sceneLabel runtime_provider_selected='$runtimeProviderSelected' no pertenece a runtime_provider_order"
  }

  foreach ($providerName in $runtimeProviderOrder) {
    if ($providerName -notin $rootProviderOrder) {
      Fail "$sceneLabel runtime_provider_order contiene provider fuera de scene_builder_v03.provider_order: '$providerName'"
    }
  }

  $runtimeProviderDetailRaw = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_provider_detail")
  $runtimeProviderDetail = $runtimeProviderDetailRaw.ToLowerInvariant()

  if (-not [string]::IsNullOrWhiteSpace($runtimeProviderDetailRaw) -and $runtimeProviderDetail -eq $runtimeProviderSelected) {
    Fail "$sceneLabel runtime_provider_detail duplica runtime_provider_selected"
  }

  $runtimeResolvedMediaKind = (Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_resolved_media_kind")).ToLowerInvariant()
  if ($runtimeResolvedMediaKind -notin @("image", "video")) {
    Fail "$sceneLabel runtime_resolved_media_kind inválido: '$runtimeResolvedMediaKind'"
  }
  if ($runtimeResolvedMediaKind -ne $visualKind) {
    Fail "$sceneLabel runtime_resolved_media_kind='$runtimeResolvedMediaKind' != visual_kind='$visualKind'"
  }

  $runtimeResolvedSourceKind = (Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_resolved_source_kind")).ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($runtimeResolvedSourceKind)) {
    Fail "$sceneLabel runtime_resolved_source_kind vacío"
  }

  $runtimeFallbackApplied = [bool](Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_fallback_applied")
  $runtimeFallbackReason = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_fallback_reason")

  if ($runtimeFallbackApplied -and [string]::IsNullOrWhiteSpace($runtimeFallbackReason)) {
    Fail "$sceneLabel runtime_fallback_applied=true pero runtime_fallback_reason vacío"
  }
  if (-not [string]::IsNullOrWhiteSpace($runtimeProviderDetailRaw) -and -not [string]::IsNullOrWhiteSpace($runtimeFallbackReason)) {
    if ($runtimeFallbackReason.ToLowerInvariant() -eq $runtimeProviderDetail) {
      Fail "$sceneLabel runtime_fallback_reason depende de runtime_provider_detail"
    }
  }

  $sceneAssets = Get-ObjectPropertyValue -Object $scene -Name "assets"
  if (-not $sceneAssets) {
    Fail "$sceneLabel no tiene assets"
  }

  $assetMetaName = if ($visualKind -eq "video") { "video_meta" } else { "image_meta" }
  $assetMeta = Get-ObjectPropertyValue -Object $sceneAssets -Name $assetMetaName
  if (-not $assetMeta) {
    Fail "$sceneLabel no tiene assets.$assetMetaName"
  }

  $assetProviderRaw = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $assetMeta -Name "provider")
  $assetProvider = $assetProviderRaw.ToLowerInvariant()

  if ([string]::IsNullOrWhiteSpace($assetProviderRaw)) {
    Fail "$sceneLabel $assetMetaName.provider vacío"
  }
  if ($assetProviderRaw -ne $assetProvider) {
    Fail "$sceneLabel $assetMetaName.provider no normalizado: '$assetProviderRaw'"
  }
  if ($assetProvider -ne $runtimeProviderSelected) {
    Fail "$sceneLabel $assetMetaName.provider='$assetProvider' != runtime_provider_selected='$runtimeProviderSelected'"
  }

  $assetProviderDetailRaw = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $assetMeta -Name "provider_detail")
  $assetProviderDetail = $assetProviderDetailRaw.ToLowerInvariant()
  if (-not [string]::IsNullOrWhiteSpace($assetProviderDetailRaw) -and $assetProviderDetail -eq $assetProvider) {
    Fail "$sceneLabel $assetMetaName.provider_detail duplica provider"
  }

  $assetProviderOrderRaw = @(Get-NormalizedStringItems -Value (Get-ObjectPropertyValue -Object $assetMeta -Name "provider_order"))
  $assetProviderOrder = @(Get-UniqueNormalizedStringItems -Value (Get-ObjectPropertyValue -Object $assetMeta -Name "provider_order"))

  if ($assetProviderOrder.Count -lt 1) {
    Fail "$sceneLabel $assetMetaName.provider_order vacío"
  }
  if ($assetProviderOrderRaw.Count -ne $assetProviderOrder.Count) {
    Fail "$sceneLabel $assetMetaName.provider_order contiene duplicados"
  }
  if (-not (Test-ExactStringList -Left $assetProviderOrder -Right $runtimeProviderOrder)) {
    Fail "$sceneLabel $assetMetaName.provider_order != runtime_provider_order"
  }

  $assetRequestedCapability = (Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $assetMeta -Name "requested_capability")).ToLowerInvariant()
  if ($assetRequestedCapability -ne $runtimeRequestedCapability) {
    Fail "$sceneLabel $assetMetaName.requested_capability='$assetRequestedCapability' != runtime_requested_capability='$runtimeRequestedCapability'"
  }

  $assetResolvedMediaKind = (Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $assetMeta -Name "resolved_media_kind")).ToLowerInvariant()
  if ($assetResolvedMediaKind -ne $runtimeResolvedMediaKind) {
    Fail "$sceneLabel $assetMetaName.resolved_media_kind='$assetResolvedMediaKind' != runtime_resolved_media_kind='$runtimeResolvedMediaKind'"
  }

  $assetResolvedSourceKind = (Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $assetMeta -Name "resolved_source_kind")).ToLowerInvariant()
  if ($assetResolvedSourceKind -ne $runtimeResolvedSourceKind) {
    Fail "$sceneLabel $assetMetaName.resolved_source_kind='$assetResolvedSourceKind' != runtime_resolved_source_kind='$runtimeResolvedSourceKind'"
  }

  $assetFallbackApplied = [bool](Get-ObjectPropertyValue -Object $assetMeta -Name "fallback_applied")
  $assetFallbackReason = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $assetMeta -Name "fallback_reason")

  if ($assetFallbackApplied -ne $runtimeFallbackApplied) {
    Fail "$sceneLabel $assetMetaName.fallback_applied != runtime_fallback_applied"
  }
  if ($assetFallbackReason -ne $runtimeFallbackReason) {
    Fail "$sceneLabel $assetMetaName.fallback_reason != runtime_fallback_reason"
  }
}

Write-Host ("SMOKE OK: LIVE provider contract v03. live={0} scenes={1}" -f $live, $scenes.Count) -ForegroundColor Green