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

  $runtimeQueryRaw = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_query")
  if ([string]::IsNullOrWhiteSpace($runtimeQueryRaw)) {
    Fail "$sceneLabel runtime_query vacío"
  }

  $runtimeQueryAuthority = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_query_authority")
  if ([string]::IsNullOrWhiteSpace($runtimeQueryAuthority)) {
    Fail "$sceneLabel runtime_query_authority vacío"
  }

  $sceneImageQueryRaw = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $scene -Name "image_query")
  if ([string]::IsNullOrWhiteSpace($sceneImageQueryRaw)) {
    Fail "$sceneLabel image_query vacío en scene"
  }
  if ($sceneImageQueryRaw -ne $runtimeQueryRaw) {
    Fail "$sceneLabel image_query='$sceneImageQueryRaw' != runtime_query='$runtimeQueryRaw'"
  }

  $queryRaw = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $visualEnrich -Name "query")
  $usedQueryRaw = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $visualEnrich -Name "used_query")

  $rawQueryCandidatesValue = Get-ObjectPropertyValue -Object $visualEnrich -Name "query_candidates"
  $queryCandidates = @()

  if (($rawQueryCandidatesValue -is [System.Collections.IEnumerable]) -and -not ($rawQueryCandidatesValue -is [string])) {
    foreach ($candidate in @($rawQueryCandidatesValue)) {
      $candidateText = Get-StringOrEmpty -Value $candidate
      if (-not [string]::IsNullOrWhiteSpace($candidateText)) {
        $queryCandidates += $candidateText
      }
    }
  }
  elseif ($null -ne $rawQueryCandidatesValue) {
    $singleCandidate = Get-StringOrEmpty -Value $rawQueryCandidatesValue
    if (-not [string]::IsNullOrWhiteSpace($singleCandidate)) {
      $queryCandidates += $singleCandidate
    }
  }

  if ($queryCandidates.Count -lt 1) {
    Fail "$sceneLabel visual_enrich.query_candidates vacío"
  }

  if (-not [string]::IsNullOrWhiteSpace($queryRaw) -and $queryRaw -ne $queryCandidates[0]) {
    Fail "$sceneLabel visual_enrich.query debe coincidir con query_candidates[0]"
  }

  if (-not [string]::IsNullOrWhiteSpace($usedQueryRaw) -and $usedQueryRaw -notin $queryCandidates) {
    Fail "$sceneLabel visual_enrich.used_query debe pertenecer a query_candidates"
  }

  $candidateAuthorityMatch = [regex]::Match($runtimeQueryAuthority, '^visual_enrich\.query_candidates\[(\d+)\]$')

  if ($runtimeQueryAuthority -eq "visual_enrich.used_query") {
    if ([string]::IsNullOrWhiteSpace($usedQueryRaw)) {
      Fail "$sceneLabel runtime_query_authority='visual_enrich.used_query' pero used_query vacío"
    }
    if ($runtimeQueryRaw -ne $usedQueryRaw) {
      Fail "$sceneLabel runtime_query no coincide con used_query"
    }
  }
  elseif ($runtimeQueryAuthority -eq "visual_enrich.query") {
    if ([string]::IsNullOrWhiteSpace($queryRaw)) {
      Fail "$sceneLabel runtime_query_authority='visual_enrich.query' pero query vacío"
    }
    if ($runtimeQueryRaw -ne $queryRaw) {
      Fail "$sceneLabel runtime_query no coincide con query"
    }
  }
  elseif ($candidateAuthorityMatch.Success) {
    $candidateIndex = [int]$candidateAuthorityMatch.Groups[1].Value
    if ($candidateIndex -lt 0 -or $candidateIndex -ge $queryCandidates.Count) {
      Fail "$sceneLabel runtime_query_authority fuera de rango: '$runtimeQueryAuthority'"
    }
    if ($runtimeQueryRaw -ne $queryCandidates[$candidateIndex]) {
      Fail "$sceneLabel runtime_query no coincide con $runtimeQueryAuthority"
    }
  }
  elseif ($runtimeQueryAuthority -eq "live_manifest_patch._pick_visual_query") {
    if ($runtimeQueryRaw -ne $sceneImageQueryRaw) {
      Fail "$sceneLabel runtime_query_authority='live_manifest_patch._pick_visual_query' pero image_query no coincide"
    }
  }
  elseif ($runtimeQueryAuthority -in @(
    "visual_enrich.runtime_query",
    "scene.image_query",
    "scene.script_text",
    "scene.text",
    "apply_scene_builder.default"
  )) {
    Fail "$sceneLabel runtime_query_authority no permitida para contrato upstream: '$runtimeQueryAuthority'"
  }
  else {
    Fail "$sceneLabel runtime_query_authority no reconocida: '$runtimeQueryAuthority'"
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

  if ($visualEnrich.PSObject.Properties.Name -notcontains "runtime_video_request_resolved_to_image") {
    Fail "$sceneLabel runtime_video_request_resolved_to_image ausente"
  }
  if ($visualEnrich.PSObject.Properties.Name -notcontains "runtime_image_request_resolved_to_video") {
    Fail "$sceneLabel runtime_image_request_resolved_to_video ausente"
  }

  $runtimeVideoRequestResolvedToImage = [bool](Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_video_request_resolved_to_image")
  $runtimeImageRequestResolvedToVideo = [bool](Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_image_request_resolved_to_video")

  if ($runtimeVideoRequestResolvedToImage -and $runtimeImageRequestResolvedToVideo) {
    Fail "$sceneLabel runtime cross-media flags conflictivos"
  }

  if ($runtimeRequestedCapability -eq "stock_video") {
    $expectedRuntimeVideoRequestResolvedToImage = ($runtimeResolvedMediaKind -eq "image")
    if ($runtimeVideoRequestResolvedToImage -ne $expectedRuntimeVideoRequestResolvedToImage) {
      Fail "$sceneLabel runtime_video_request_resolved_to_image inconsistente con requested_capability='$runtimeRequestedCapability' y resolved_media_kind='$runtimeResolvedMediaKind'"
    }
    if ($runtimeImageRequestResolvedToVideo) {
      Fail "$sceneLabel runtime_image_request_resolved_to_video no aplica para requested_capability='stock_video'"
    }
  }
  elseif ($runtimeRequestedCapability -eq "stock_image") {
    $expectedRuntimeImageRequestResolvedToVideo = ($runtimeResolvedMediaKind -eq "video")
    if ($runtimeImageRequestResolvedToVideo -ne $expectedRuntimeImageRequestResolvedToVideo) {
      Fail "$sceneLabel runtime_image_request_resolved_to_video inconsistente con requested_capability='$runtimeRequestedCapability' y resolved_media_kind='$runtimeResolvedMediaKind'"
    }
    if ($runtimeVideoRequestResolvedToImage) {
      Fail "$sceneLabel runtime_video_request_resolved_to_image no aplica para requested_capability='stock_image'"
    }
  }

  $runtimeFallbackApplied = [bool](Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_fallback_applied")
  $runtimeFallbackReason = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $visualEnrich -Name "runtime_fallback_reason")

  if ($runtimeFallbackApplied -and [string]::IsNullOrWhiteSpace($runtimeFallbackReason)) {
    Fail "$sceneLabel runtime_fallback_applied=true pero runtime_fallback_reason vacío"
  }

  if ($runtimeVideoRequestResolvedToImage) {
    if (-not $runtimeFallbackApplied) {
      Fail "$sceneLabel runtime_video_request_resolved_to_image=true requiere runtime_fallback_applied=true"
    }
    if ($runtimeFallbackReason -ne "video_request_resolved_to_image") {
      Fail "$sceneLabel runtime_fallback_reason debe ser 'video_request_resolved_to_image' cuando runtime_video_request_resolved_to_image=true"
    }
  }

  if ($runtimeImageRequestResolvedToVideo) {
    if (-not $runtimeFallbackApplied) {
      Fail "$sceneLabel runtime_image_request_resolved_to_video=true requiere runtime_fallback_applied=true"
    }
    if ($runtimeFallbackReason -ne "image_request_resolved_to_video") {
      Fail "$sceneLabel runtime_fallback_reason debe ser 'image_request_resolved_to_video' cuando runtime_image_request_resolved_to_video=true"
    }
  }

  if ((-not $runtimeVideoRequestResolvedToImage) -and ($runtimeFallbackReason -eq "video_request_resolved_to_image")) {
    Fail "$sceneLabel runtime_fallback_reason='video_request_resolved_to_image' sin runtime_video_request_resolved_to_image=true"
  }
  if ((-not $runtimeImageRequestResolvedToVideo) -and ($runtimeFallbackReason -eq "image_request_resolved_to_video")) {
    Fail "$sceneLabel runtime_fallback_reason='image_request_resolved_to_video' sin runtime_image_request_resolved_to_video=true"
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

  $assetQueryRaw = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $assetMeta -Name "query")
  if ([string]::IsNullOrWhiteSpace($assetQueryRaw)) {
    Fail "$sceneLabel $assetMetaName.query vacío"
  }
  if ($assetQueryRaw -ne $runtimeQueryRaw) {
    Fail "$sceneLabel $assetMetaName.query='$assetQueryRaw' != runtime_query='$runtimeQueryRaw'"
  }

  $assetQueryAuthority = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $assetMeta -Name "query_authority")
  if ([string]::IsNullOrWhiteSpace($assetQueryAuthority)) {
    Fail "$sceneLabel $assetMetaName.query_authority vacío"
  }
  if ($assetQueryAuthority -ne $runtimeQueryAuthority) {
    Fail "$sceneLabel $assetMetaName.query_authority='$assetQueryAuthority' != runtime_query_authority='$runtimeQueryAuthority'"
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

  if ($assetMeta.PSObject.Properties.Name -notcontains "video_request_resolved_to_image") {
    Fail "$sceneLabel $assetMetaName.video_request_resolved_to_image ausente"
  }
  if ($assetMeta.PSObject.Properties.Name -notcontains "image_request_resolved_to_video") {
    Fail "$sceneLabel $assetMetaName.image_request_resolved_to_video ausente"
  }

  $assetVideoRequestResolvedToImage = [bool](Get-ObjectPropertyValue -Object $assetMeta -Name "video_request_resolved_to_image")
  $assetImageRequestResolvedToVideo = [bool](Get-ObjectPropertyValue -Object $assetMeta -Name "image_request_resolved_to_video")

  if ($assetVideoRequestResolvedToImage -and $assetImageRequestResolvedToVideo) {
    Fail "$sceneLabel $assetMetaName cross-media flags conflictivos"
  }

  $assetFallbackApplied = [bool](Get-ObjectPropertyValue -Object $assetMeta -Name "fallback_applied")
  $assetFallbackReason = Get-StringOrEmpty -Value (Get-ObjectPropertyValue -Object $assetMeta -Name "fallback_reason")

  if ($assetFallbackApplied -ne $runtimeFallbackApplied) {
    Fail "$sceneLabel $assetMetaName.fallback_applied != runtime_fallback_applied"
  }
  if ($assetFallbackReason -ne $runtimeFallbackReason) {
    Fail "$sceneLabel $assetMetaName.fallback_reason != runtime_fallback_reason"
  }
  if ($assetVideoRequestResolvedToImage -ne $runtimeVideoRequestResolvedToImage) {
    Fail "$sceneLabel $assetMetaName.video_request_resolved_to_image != runtime_video_request_resolved_to_image"
  }
  if ($assetImageRequestResolvedToVideo -ne $runtimeImageRequestResolvedToVideo) {
    Fail "$sceneLabel $assetMetaName.image_request_resolved_to_video != runtime_image_request_resolved_to_video"
  }
}

Write-Host ("SMOKE OK: LIVE provider contract v03. live={0} scenes={1}" -f $live, $scenes.Count) -ForegroundColor Green