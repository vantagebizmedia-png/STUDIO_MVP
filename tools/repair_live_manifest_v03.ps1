param(
  [Parameter(Mandatory=$true)][string]$LiveDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Normalize-ToArray {
  param($Value)

  if ($null -eq $Value) { return @() }

  if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
    return @($Value)
  }

  return @($Value)
}

function Get-PositiveInt {
  param($Value)

  try {
    $n = [int]$Value
    if ($n -gt 0) { return $n }
  }
  catch { }

  return 0
}

function Get-IntOrZero {
  param($Value)

  try { return [int]$Value } catch { return 0 }
}

function Convert-ToPackRelativePath {
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

function Resolve-ExistingFileRelative {
  param(
    [Parameter(Mandatory=$true)][string]$BaseDir,
    [Parameter(Mandatory=$false)][string[]]$Candidates
  )

  $sharedPath = Join-Path $PSScriptRoot "scene_visual_shared_v03.ps1"
  if (-not (Test-Path -LiteralPath $sharedPath -PathType Leaf)) {
    throw ("No existe helper visual compartido: {0}" -f $sharedPath)
  }

  . $sharedPath
  return (Resolve-SceneAssetRelativePathShared -BaseDir $BaseDir -Candidates $Candidates)
}

function Get-ResolvedSceneVisualKind {
  param(
    [Parameter(Mandatory=$false)][string]$CurrentVisualKind,
    [Parameter(Mandatory=$false)][string]$ResolvedImage,
    [Parameter(Mandatory=$false)][string]$ResolvedVideo
  )

  $sharedPath = Join-Path $PSScriptRoot "scene_visual_shared_v03.ps1"
  if (-not (Test-Path -LiteralPath $sharedPath -PathType Leaf)) {
    throw ("No existe helper visual compartido: {0}" -f $sharedPath)
  }

  . $sharedPath
  return (Get-ResolvedVisualKindShared -CurrentVisualKind $CurrentVisualKind -ResolvedImage $ResolvedImage -ResolvedVideo $ResolvedVideo)
}
function Get-SceneText {
  param($Scene)

  $sharedPath = Join-Path $PSScriptRoot "scene_narrative_shared_v03.ps1"
  if (-not (Test-Path -LiteralPath $sharedPath -PathType Leaf)) {
    throw ("No existe helper narrative compartido: {0}" -f $sharedPath)
  }

  . $sharedPath
  return (Get-SceneTextShared -Scene $Scene)
}

function Get-SceneQuery {
  param($Scene)

  $sharedPath = Join-Path $PSScriptRoot "scene_narrative_shared_v03.ps1"
  if (-not (Test-Path -LiteralPath $sharedPath -PathType Leaf)) {
    throw ("No existe helper narrative compartido: {0}" -f $sharedPath)
  }

  . $sharedPath
  return (Get-SceneQueryShared -Scene $Scene)
}

function Get-ManifestTotalAudioMs {
  param($ManifestObj)

  $total = 0

  try {
    if ($ManifestObj.PSObject.Properties["total_audio_ms"] -and $null -ne $ManifestObj.total_audio_ms) {
      $total = Get-PositiveInt -Value $ManifestObj.total_audio_ms
    }
  }
  catch { $total = 0 }

  if ($total -le 0) {
    try {
      if ($ManifestObj.PSObject.Properties["scene_builder_v03"] -and $ManifestObj.scene_builder_v03) {
        $sb = $ManifestObj.scene_builder_v03
        if ($sb.PSObject.Properties["total_audio_ms"] -and $null -ne $sb.total_audio_ms) {
          $total = Get-PositiveInt -Value $sb.total_audio_ms
        }
      }
    }
    catch { $total = 0 }
  }

  if ($total -le 0) {
    try {
      foreach ($scene in @(Normalize-ToArray -Value $ManifestObj.scenes_v03)) {
        $en = Get-PositiveInt -Value $scene.end_ms
        if ($en -gt $total) { $total = $en }
      }
    }
    catch { $total = 0 }
  }

  if ($total -le 0) {
    try {
      $sumDur = 0
      foreach ($scene in @(Normalize-ToArray -Value $ManifestObj.scenes_v03)) {
        $dur = Get-PositiveInt -Value $scene.duration_ms
        if ($dur -le 0) {
          $st = Get-IntOrZero -Value $scene.start_ms
          $en = Get-IntOrZero -Value $scene.end_ms
          if ($en -gt $st) { $dur = [int]($en - $st) }
        }
        if ($dur -gt 0) { $sumDur += $dur }
      }
      if ($sumDur -gt 0) { $total = [int]$sumDur }
    }
    catch { $total = 0 }
  }

  if ($total -le 0) { $total = 20000 }
  return [int]$total
}

function Normalize-DurationsToTotal {
  param(
    [Parameter(Mandatory=$true)][int[]]$Durations,
    [Parameter(Mandatory=$true)][int]$TotalMs
  )

  $count = @($Durations).Count
  if ($count -lt 1) { return @() }
  if ($TotalMs -lt $count) { throw "TotalMs insuficiente para normalizar escenas: TotalMs=$TotalMs count=$count" }

  $clean = @()
  foreach ($d in $Durations) {
    $n = 0
    try { $n = [int]$d } catch { $n = 0 }
    if ($n -lt 0) { $n = 0 }
    $clean += $n
  }

  $sum = (@($clean) | Measure-Object -Sum).Sum
  if (-not $sum -or $sum -le 0) {
    $base = [int][Math]::Floor($TotalMs / $count)
    if ($base -lt 1) { $base = 1 }

    $out = @()
    $assigned = 0

    for ($i = 0; $i -lt $count; $i++) {
      if ($i -lt ($count - 1)) {
        $out += $base
        $assigned += $base
      }
      else {
        $out += [int]($TotalMs - $assigned)
      }
    }

    return @($out)
  }

  $scaled = @()
  $assignedScaled = 0

  for ($i = 0; $i -lt $count; $i++) {
    if ($i -lt ($count - 1)) {
      $raw = [int][Math]::Floor(($TotalMs * $clean[$i]) / [double]$sum)
      if ($raw -lt 1) { $raw = 1 }
      $scaled += $raw
      $assignedScaled += $raw
    }
    else {
      $last = [int]($TotalMs - $assignedScaled)
      if ($last -lt 1) { $last = 1 }
      $scaled += $last
    }
  }

  $sumScaled = (@($scaled) | Measure-Object -Sum).Sum
  if ($sumScaled -ne $TotalMs) {
    $delta = [int]($TotalMs - $sumScaled)
    $scaled[$scaled.Count - 1] = [int]($scaled[$scaled.Count - 1] + $delta)
  }

  if ($scaled[$scaled.Count - 1] -lt 1) {
    $need = [int](1 - $scaled[$scaled.Count - 1])
    for ($i = 0; $i -lt ($scaled.Count - 1) -and $need -gt 0; $i++) {
      $canTake = [Math]::Max(0, $scaled[$i] - 1)
      if ($canTake -le 0) { continue }

      $take = [Math]::Min($need, $canTake)
      $scaled[$i] = [int]($scaled[$i] - $take)
      $need = [int]($need - $take)
      $scaled[$scaled.Count - 1] = [int]($scaled[$scaled.Count - 1] + $take)
    }
  }

  $sumFinal = (@($scaled) | Measure-Object -Sum).Sum
  if ($sumFinal -ne $TotalMs) {
    throw "No se pudo normalizar durations exactamente al total_audio_ms"
  }

  return @($scaled)
}

function Write-JsonUtf8NoBom {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)]$Object
  )

  $enc = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 50), $enc)
}

function Write-JsonUtf8Bom {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)]$Object
  )

  $enc = [System.Text.UTF8Encoding]::new($true)
  [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 50), $enc)
}

$live = (Resolve-Path -LiteralPath $LiveDir).Path
$manifestPath = Join-Path $live "manifest_v03.json"

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "No existe manifest_v03.json en LIVE: $live"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

$scenes = @()
if ($manifest.PSObject.Properties["scenes_v03"] -and $manifest.scenes_v03) {
  $scenes = @(Normalize-ToArray -Value $manifest.scenes_v03)
}
elseif ($manifest.PSObject.Properties["scenes"] -and $manifest.scenes) {
  $legacy = @(Normalize-ToArray -Value $manifest.scenes)

  for ($i = 0; $i -lt $legacy.Count; $i++) {
    $row = $legacy[$i]

    $textValue = ""
    try {
      if ($row.PSObject.Properties["text"] -and $row.text) { $textValue = [string]$row.text }
      elseif ($row.PSObject.Properties["narration"] -and $row.narration) { $textValue = [string]$row.narration }
      elseif ($row.PSObject.Properties["onscreen"] -and $row.onscreen) { $textValue = [string]$row.onscreen }
    }
    catch { $textValue = "" }

    $imageValue = ""
    $audioValue = ""
    $videoValue = ""

    try {
      if ($row.PSObject.Properties["image"] -and $row.image) { $imageValue = [string]$row.image }
      if ($row.PSObject.Properties["audio"] -and $row.audio) { $audioValue = [string]$row.audio }
      if ($row.PSObject.Properties["video"] -and $row.video) { $videoValue = [string]$row.video }
    }
    catch { }

    try {
      if ($row.PSObject.Properties["artifacts"] -and $row.artifacts) {
        $arts = $row.artifacts
        if ([string]::IsNullOrWhiteSpace($imageValue) -and $arts.PSObject.Properties["image"] -and $arts.image) {
          $imageValue = [string]$arts.image
        }
        if ([string]::IsNullOrWhiteSpace($audioValue) -and $arts.PSObject.Properties["audio"] -and $arts.audio) {
          $audioValue = [string]$arts.audio
        }
        if ([string]::IsNullOrWhiteSpace($videoValue) -and $arts.PSObject.Properties["video"] -and $arts.video) {
          $videoValue = [string]$arts.video
        }
      }
    }
    catch { }

    $currentRequestedMediaType = ""
    $currentVisualRequestKind = ""
    $currentVisualSourceKind = ""
    $currentVisualCapability = ""

    try {
      if ($row.PSObject.Properties["requested_media_type"] -and $row.requested_media_type) {
        $currentRequestedMediaType = ([string]$row.requested_media_type).Trim().ToLowerInvariant()
      }
    }
    catch { $currentRequestedMediaType = "" }
    if ($currentRequestedMediaType -notin @("image","video")) { $currentRequestedMediaType = "" }

    try {
      if ($row.PSObject.Properties["visual_request_kind"] -and $row.visual_request_kind) {
        $currentVisualRequestKind = ([string]$row.visual_request_kind).Trim().ToLowerInvariant()
      }
    }
    catch { $currentVisualRequestKind = "" }
    if ($currentVisualRequestKind -notin @("image","video")) { $currentVisualRequestKind = "" }

    try {
      if ($row.PSObject.Properties["visual_source_kind"] -and $row.visual_source_kind) {
        $currentVisualSourceKind = ([string]$row.visual_source_kind).Trim().ToLowerInvariant()
      }
    }
    catch { $currentVisualSourceKind = "" }
    if ($currentVisualSourceKind -notmatch "(^|_)(image|video)$") { $currentVisualSourceKind = "" }

    try {
      if ($row.PSObject.Properties["visual_capability"] -and $row.visual_capability) {
        $currentVisualCapability = ([string]$row.visual_capability).Trim().ToLowerInvariant()
      }
    }
    catch { $currentVisualCapability = "" }
    if ($currentVisualCapability -notin @("stock_image","stock_video")) { $currentVisualCapability = "" }

    $initialVisualKind = $(if (-not [string]::IsNullOrWhiteSpace($videoValue) -and [string]::IsNullOrWhiteSpace($imageValue)) { "video" } else { "image" })
    $initialVisualSourceKind = $(if (-not [string]::IsNullOrWhiteSpace($currentVisualSourceKind)) { $currentVisualSourceKind } elseif ($initialVisualKind -eq "video") { "stock_video" } else { "stock_image" })
    $initialVisualCapability = $(if (-not [string]::IsNullOrWhiteSpace($currentVisualCapability)) { $currentVisualCapability } elseif ($initialVisualKind -eq "video") { "stock_video" } else { "stock_image" })

    $scenes += [pscustomobject]@{
      id                   = ("scene_{0:000}" -f ($i + 1))
      index                = [int]$i
      start_ms             = Get-IntOrZero -Value $row.start_ms
      end_ms               = Get-IntOrZero -Value $row.end_ms
      duration_ms          = Get-IntOrZero -Value $row.duration_ms
      text                 = [string]$textValue
      script_text          = [string]$textValue
      image_query          = ""
      query                = ""
      requested_media_type = [string]$currentRequestedMediaType
      visual_request_kind  = [string]$currentVisualRequestKind
      visual_kind          = [string]$initialVisualKind
      visual_source_kind   = [string]$initialVisualSourceKind
      visual_capability    = [string]$initialVisualCapability
      assets               = [pscustomobject]@{
        audio_clip = [string]$audioValue
        image      = [string]$imageValue
        video      = [string]$videoValue
      }
    }
  }
}
else {
  throw "manifest_v03.json no tiene scenes_v03 ni scenes para reparar"
}

if (@($scenes).Count -lt 1) {
  throw "No hay escenas para reparar"
}

$totalAudioMs = Get-ManifestTotalAudioMs -ManifestObj $manifest

$rawDurations = @()
foreach ($scene in $scenes) {
  $dur = Get-PositiveInt -Value $scene.duration_ms
  if ($dur -le 0) {
    $st = Get-IntOrZero -Value $scene.start_ms
    $en = Get-IntOrZero -Value $scene.end_ms
    if ($en -gt $st) { $dur = [int]($en - $st) }
  }
  $rawDurations += [int]$dur
}

$timingSharedPath = Join-Path $PSScriptRoot "scene_timing_shared_v03.ps1"
if (-not (Test-Path -LiteralPath $timingSharedPath -PathType Leaf)) {
  throw ("No existe helper timing compartido: {0}" -f $timingSharedPath)
}

. $timingSharedPath

$shapeSharedPath = Join-Path $PSScriptRoot "scene_shape_shared_v03.ps1"
if (-not (Test-Path -LiteralPath $shapeSharedPath -PathType Leaf)) {
  throw ("No existe helper shape compartido: {0}" -f $shapeSharedPath)
}

. $shapeSharedPath

$narrativeSharedPath = Join-Path $PSScriptRoot "scene_narrative_shared_v03.ps1"
if (-not (Test-Path -LiteralPath $narrativeSharedPath -PathType Leaf)) {
  throw ("No existe helper narrative compartido: {0}" -f $narrativeSharedPath)
}

. $narrativeSharedPath

$visualMetaSharedPath = Join-Path $PSScriptRoot "scene_visual_meta_shared_v03.ps1"
if (-not (Test-Path -LiteralPath $visualMetaSharedPath -PathType Leaf)) {
  throw ("No existe helper visual meta compartido: {0}" -f $visualMetaSharedPath)
}

. $visualMetaSharedPath

$visualSharedPath = Join-Path $PSScriptRoot "scene_visual_shared_v03.ps1"
if (-not (Test-Path -LiteralPath $visualSharedPath -PathType Leaf)) {
  throw ("No existe helper visual compartido: {0}" -f $visualSharedPath)
}

. $visualSharedPath

$durations = @(Normalize-DurationsToTotal -Durations $rawDurations -TotalMs $totalAudioMs)
$timeline = @(Build-SceneTimelineShared -Durations $durations -TotalMs $totalAudioMs)

$warnings = New-Object System.Collections.Generic.List[string]
$audioClips = @()
$legacyScenes = @()

for ($i = 0; $i -lt $scenes.Count; $i++) {
  $scene = $scenes[$i]
  $ord = $i + 1
  $sceneDirRel = ("artifacts/scenes/scene_{0:d2}" -f $ord)

  Ensure-SceneAssetSlotsShared -Scene $scene
  Ensure-SceneNarrativeSlotsShared -Scene $scene
  Ensure-SceneNarrativeValuesShared -Scene $scene

  $sceneText = Get-SceneText -Scene $scene
  $sceneQuery = Get-SceneQuery -Scene $scene

  $currentVisualKind = ""
  try {
    if ($scene.PSObject.Properties["visual_kind"] -and $scene.visual_kind) {
      $currentVisualKind = ([string]$scene.visual_kind).Trim().ToLowerInvariant()
    }
  }
  catch { $currentVisualKind = "" }
  if ($currentVisualKind -notin @("image","video")) { $currentVisualKind = "" }

  $currentRequestedMediaType = ""
  try {
    if ($scene.PSObject.Properties["requested_media_type"] -and $scene.requested_media_type) {
      $currentRequestedMediaType = ([string]$scene.requested_media_type).Trim().ToLowerInvariant()
    }
  }
  catch { $currentRequestedMediaType = "" }
  if ($currentRequestedMediaType -notin @("image","video")) { $currentRequestedMediaType = "" }

  $currentVisualRequestKind = ""
  try {
    if ($scene.PSObject.Properties["visual_request_kind"] -and $scene.visual_request_kind) {
      $currentVisualRequestKind = ([string]$scene.visual_request_kind).Trim().ToLowerInvariant()
    }
  }
  catch { $currentVisualRequestKind = "" }
  if ($currentVisualRequestKind -notin @("image","video")) { $currentVisualRequestKind = "" }

  $currentVisualSourceKind = ""
  try {
    if ($scene.PSObject.Properties["visual_source_kind"] -and $scene.visual_source_kind) {
      $currentVisualSourceKind = ([string]$scene.visual_source_kind).Trim().ToLowerInvariant()
    }
  }
  catch { $currentVisualSourceKind = "" }
  if ($currentVisualSourceKind -notmatch "(^|_)(image|video)$") { $currentVisualSourceKind = "" }

  $resolvedAudio = Resolve-ExistingFileRelative -BaseDir $live -Candidates @(
    [string]$scene.assets.audio_clip,
    ("assets/audio_clips/s{0:d2}.wav" -f $ord),
    ("artifacts/audio_s{0:d2}.wav" -f $ord),
    ($sceneDirRel + "/audio.wav")
  )

  $resolvedImage = Resolve-ExistingFileRelative -BaseDir $live -Candidates @(
    [string]$scene.assets.image,
    ($sceneDirRel + "/image.png"),
    ($sceneDirRel + "/image.jpg"),
    ($sceneDirRel + "/image.jpeg"),
    ($sceneDirRel + "/image.webp"),
    "artifacts/image.png",
    "artifacts/image.jpg",
    "artifacts/image.jpeg",
    "artifacts/image.webp"
  )

  $resolvedVideo = Resolve-ExistingFileRelative -BaseDir $live -Candidates @(
    [string]$scene.assets.video,
    ($sceneDirRel + "/video.mp4"),
    ($sceneDirRel + "/video.mov"),
    ($sceneDirRel + "/video.webm")
  )

  if ([string]::IsNullOrWhiteSpace($resolvedAudio)) {
    $warnings.Add(("scene_{0:d2}: no se encontró audio_clip real" -f $ord)) | Out-Null
  }

  $hasImage = -not [string]::IsNullOrWhiteSpace($resolvedImage)
  $hasVideo = -not [string]::IsNullOrWhiteSpace($resolvedVideo)

  $finalVisualKind = Get-ResolvedVisualKindShared `
    -CurrentVisualKind $currentVisualKind `
    -RequestedMediaType $currentRequestedMediaType `
    -VisualRequestKind $currentVisualRequestKind `
    -ResolvedImage $resolvedImage `
    -ResolvedVideo $resolvedVideo

  if ((-not $hasImage) -and (-not $hasVideo)) {
    $warnings.Add(("scene_{0:d2}: no se encontró image/video real" -f $ord)) | Out-Null
  }

  $runtimeResolvedSourceKind = ""
  try {
    if (
      $scene.PSObject.Properties["meta"] -and
      $scene.meta -and
      $scene.meta.PSObject.Properties["visual_enrich"] -and
      $scene.meta.visual_enrich -and
      $scene.meta.visual_enrich.PSObject.Properties["runtime_resolved_source_kind"] -and
      $scene.meta.visual_enrich.runtime_resolved_source_kind
    ) {
      $runtimeResolvedSourceKind = ([string]$scene.meta.visual_enrich.runtime_resolved_source_kind).Trim().ToLowerInvariant()
    }
  }
  catch { $runtimeResolvedSourceKind = "" }
  if ($runtimeResolvedSourceKind -notmatch "(^|_)(image|video)$") { $runtimeResolvedSourceKind = "" }

  $assetResolvedSourceKind = ""
  if ($finalVisualKind -eq "video") {
    try {
      if (
        $scene.assets.PSObject.Properties["video_meta"] -and
        $scene.assets.video_meta -and
        $scene.assets.video_meta.PSObject.Properties["resolved_source_kind"] -and
        $scene.assets.video_meta.resolved_source_kind
      ) {
        $assetResolvedSourceKind = ([string]$scene.assets.video_meta.resolved_source_kind).Trim().ToLowerInvariant()
      }
    }
    catch { $assetResolvedSourceKind = "" }
  }
  else {
    try {
      if (
        $scene.assets.PSObject.Properties["image_meta"] -and
        $scene.assets.image_meta -and
        $scene.assets.image_meta.PSObject.Properties["resolved_source_kind"] -and
        $scene.assets.image_meta.resolved_source_kind
      ) {
        $assetResolvedSourceKind = ([string]$scene.assets.image_meta.resolved_source_kind).Trim().ToLowerInvariant()
      }
    }
    catch { $assetResolvedSourceKind = "" }
  }
  if ($assetResolvedSourceKind -notmatch "(^|_)(image|video)$") { $assetResolvedSourceKind = "" }

  $finalVisualSourceKind = Get-ResolvedVisualSourceKindShared `
    -CurrentVisualSourceKind $currentVisualSourceKind `
    -RuntimeResolvedSourceKind $runtimeResolvedSourceKind `
    -AssetResolvedSourceKind $assetResolvedSourceKind `
    -VisualKind $finalVisualKind

  $finalVisualCapability = $(if ($finalVisualKind -eq "video") { "stock_video" } else { "stock_image" })

  $slot = $timeline[$i]

  $st = [int]$slot.start_ms
  $en = [int]$slot.end_ms

  $scene | Add-Member -Force -NotePropertyName id -NotePropertyValue ("scene_{0:000}" -f $ord)
  $scene | Add-Member -Force -NotePropertyName index -NotePropertyValue ([int]($ord - 1))
  $scene | Add-Member -Force -NotePropertyName text -NotePropertyValue ([string]$sceneText)
  $scene | Add-Member -Force -NotePropertyName script_text -NotePropertyValue ([string]$sceneText)
  $scene | Add-Member -Force -NotePropertyName image_query -NotePropertyValue ([string]$sceneQuery)
  $scene | Add-Member -Force -NotePropertyName query -NotePropertyValue ([string]$sceneQuery)
  $scene | Add-Member -Force -NotePropertyName start_ms -NotePropertyValue ([int]$st)
  $scene | Add-Member -Force -NotePropertyName end_ms -NotePropertyValue ([int]$en)
  $scene | Add-Member -Force -NotePropertyName duration_ms -NotePropertyValue ([int]($en - $st))

  if (-not [string]::IsNullOrWhiteSpace($currentRequestedMediaType)) {
    $scene | Add-Member -Force -NotePropertyName requested_media_type -NotePropertyValue ([string]$currentRequestedMediaType)
  }

  if (-not [string]::IsNullOrWhiteSpace($currentVisualRequestKind)) {
    $scene | Add-Member -Force -NotePropertyName visual_request_kind -NotePropertyValue ([string]$currentVisualRequestKind)
  }

  $scene.assets.audio_clip = [string]$resolvedAudio

  if ($finalVisualKind -eq "video") {
    $scene.assets.video = [string]$resolvedVideo
    $scene.assets.image = ""

    $scene | Add-Member -Force -NotePropertyName visual_kind -NotePropertyValue "video"
    $scene | Add-Member -Force -NotePropertyName visual_source_kind -NotePropertyValue ([string]$finalVisualSourceKind)
    $scene | Add-Member -Force -NotePropertyName visual_capability -NotePropertyValue ([string]$finalVisualCapability)

    Update-SceneVisualMetaShared -Scene $scene -Kind "video" -Query ([string]$sceneQuery) -FallbackProvider "repair_live_manifest_v03" | Out-Null

    try {
      if (-not ($scene.PSObject.Properties["meta"] -and $scene.meta)) {
        $scene | Add-Member -Force -NotePropertyName meta -NotePropertyValue ([pscustomobject]@{})
      }
      if (-not ($scene.meta.PSObject.Properties["visual_enrich"] -and $scene.meta.visual_enrich)) {
        $scene.meta | Add-Member -Force -NotePropertyName visual_enrich -NotePropertyValue ([pscustomobject]@{})
      }
      $scene.meta.visual_enrich | Add-Member -Force -NotePropertyName runtime_resolved_media_kind -NotePropertyValue "video"
      $scene.meta.visual_enrich | Add-Member -Force -NotePropertyName runtime_resolved_source_kind -NotePropertyValue ([string]$finalVisualSourceKind)
    }
    catch { }

    try {
      if (-not ($scene.assets.PSObject.Properties["video_meta"] -and $scene.assets.video_meta)) {
        $scene.assets | Add-Member -Force -NotePropertyName video_meta -NotePropertyValue ([pscustomobject]@{})
      }
      $scene.assets.video_meta | Add-Member -Force -NotePropertyName resolved_source_kind -NotePropertyValue ([string]$finalVisualSourceKind)
    }
    catch { }
  }
  else {
    $scene.assets.image = [string]$resolvedImage
    $scene.assets.video = ""

    $scene | Add-Member -Force -NotePropertyName visual_kind -NotePropertyValue "image"
    $scene | Add-Member -Force -NotePropertyName visual_source_kind -NotePropertyValue ([string]$finalVisualSourceKind)
    $scene | Add-Member -Force -NotePropertyName visual_capability -NotePropertyValue ([string]$finalVisualCapability)

    Update-SceneVisualMetaShared -Scene $scene -Kind "image" -Query ([string]$sceneQuery) -FallbackProvider "repair_live_manifest_v03" | Out-Null

    try {
      if (-not ($scene.PSObject.Properties["meta"] -and $scene.meta)) {
        $scene | Add-Member -Force -NotePropertyName meta -NotePropertyValue ([pscustomobject]@{})
      }
      if (-not ($scene.meta.PSObject.Properties["visual_enrich"] -and $scene.meta.visual_enrich)) {
        $scene.meta | Add-Member -Force -NotePropertyName visual_enrich -NotePropertyValue ([pscustomobject]@{})
      }
      $scene.meta.visual_enrich | Add-Member -Force -NotePropertyName runtime_resolved_media_kind -NotePropertyValue "image"
      $scene.meta.visual_enrich | Add-Member -Force -NotePropertyName runtime_resolved_source_kind -NotePropertyValue ([string]$finalVisualSourceKind)
    }
    catch { }

    try {
      if (-not ($scene.assets.PSObject.Properties["image_meta"] -and $scene.assets.image_meta)) {
        $scene.assets | Add-Member -Force -NotePropertyName image_meta -NotePropertyValue ([pscustomobject]@{})
      }
      $scene.assets.image_meta | Add-Member -Force -NotePropertyName resolved_source_kind -NotePropertyValue ([string]$finalVisualSourceKind)
    }
    catch { }
  }

  $audioClips += [pscustomobject]@{
    id       = ("clip_{0:000}" -f $ord)
    start_ms = [int]$st
    end_ms   = [int]$en
    text     = [string]$sceneText
    path     = [string]$scene.assets.audio_clip
  }

  $legacyScenes += [pscustomobject]@{
    id         = [string]$scene.id
    index      = [int]$ord
    text       = [string]$sceneText
    narration  = [string]$sceneText
    onscreen   = [string]$sceneText
    audio_text = [string]$sceneText
    visual_kind = [string]$finalVisualKind
    image      = [string]$scene.assets.image
    video      = [string]$scene.assets.video
    audio      = [string]$scene.assets.audio_clip
    start_ms   = [int]$st
    end_ms     = [int]$en
    duration_ms = [int]($en - $st)
  }
}

$scriptValue = ""
try {
  if ($manifest.PSObject.Properties["script"] -and $manifest.script) {
    $scriptValue = [string]$manifest.script
  }
}
catch { $scriptValue = "" }

if ([string]::IsNullOrWhiteSpace($scriptValue)) {
  $parts = @()
  foreach ($scene in $scenes) {
    $txt = Get-SceneText -Scene $scene
    if (-not [string]::IsNullOrWhiteSpace($txt)) { $parts += $txt }
  }
  if ($parts.Count -gt 0) {
    $scriptValue = ($parts -join " ").Trim()
  }
}

$artifactImage = ""
$artifactAudio = ""

try {
  if ($manifest.PSObject.Properties["artifacts"] -and $manifest.artifacts) {
    if ($manifest.artifacts.PSObject.Properties["image"] -and $manifest.artifacts.image) {
      $artifactImage = [string]$manifest.artifacts.image
    }
    if ($manifest.artifacts.PSObject.Properties["audio"] -and $manifest.artifacts.audio) {
      $artifactAudio = [string]$manifest.artifacts.audio
    }
  }
}
catch {
  $artifactImage = ""
  $artifactAudio = ""
}

if ([string]::IsNullOrWhiteSpace($artifactImage) -and $legacyScenes.Count -gt 0) {
  $artifactImage = [string]$legacyScenes[0].image
}
if ([string]::IsNullOrWhiteSpace($artifactAudio) -and $legacyScenes.Count -gt 0) {
  $artifactAudio = [string]$legacyScenes[0].audio
}

$existingNote = ""
$existingProviderOrder = @()

try {
  if ($manifest.PSObject.Properties["scene_builder_v03"] -and $manifest.scene_builder_v03) {
    $sbOld = $manifest.scene_builder_v03

    if ($sbOld.PSObject.Properties["note"] -and $sbOld.note) {
      $existingNote = [string]$sbOld.note
    }

    if ($sbOld.PSObject.Properties["provider_order"] -and $sbOld.provider_order) {
      $existingProviderOrder = @(
        $sbOld.provider_order |
          ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
          Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
          Select-Object -Unique
      )
    }
  }
}
catch {
  $existingNote = ""
  $existingProviderOrder = @()
}

if (@($existingProviderOrder).Count -lt 1) {
  $existingProviderOrder = @("pixabay")
}

$noteValue = "repaired_by_repair_live_manifest_v03"
if (-not [string]::IsNullOrWhiteSpace($existingNote)) {
  $noteValue = ($existingNote.Trim() + "; repaired_by_repair_live_manifest_v03")
}

$sceneBuilderMeta = [pscustomobject]@{
  max_scenes     = [int]$scenes.Count
  total_audio_ms = [int]$totalAudioMs
  provider_order = @($existingProviderOrder)
  note           = [string]$noteValue
}

$manifest | Add-Member -Force -NotePropertyName total_audio_ms -NotePropertyValue ([int]$totalAudioMs)
$manifest | Add-Member -Force -NotePropertyName script -NotePropertyValue ([string]$scriptValue)
$manifest | Add-Member -Force -NotePropertyName audio_clips -NotePropertyValue $audioClips
$manifest | Add-Member -Force -NotePropertyName scenes_v03 -NotePropertyValue @($scenes)
$manifest | Add-Member -Force -NotePropertyName scenes -NotePropertyValue @($legacyScenes)
$manifest | Add-Member -Force -NotePropertyName scene_builder_v03 -NotePropertyValue $sceneBuilderMeta
$manifest | Add-Member -Force -NotePropertyName artifacts -NotePropertyValue ([pscustomobject]@{
  image = [string]$artifactImage
  audio = [string]$artifactAudio
})

$packSyncTool = Join-Path $PSScriptRoot "write_pack_compat_v03.ps1"

Write-JsonUtf8NoBom -Path $manifestPath -Object $manifest

if (-not (Test-Path -LiteralPath $packSyncTool -PathType Leaf)) {
  throw ("No existe tool compartida de pack compat: {0}" -f $packSyncTool)
}

& pwsh -NoProfile -ExecutionPolicy Bypass -File $packSyncTool -LiveDir $live | Out-Null
$packSyncExit = $LASTEXITCODE

if ($packSyncExit -ne 0) {
  throw ("write_pack_compat_v03.ps1 devolvió exit code {0}" -f $packSyncExit)
}

Write-Host ("OK: repair_live_manifest_v03 aplicado. live={0}" -f $live) -ForegroundColor Green
Write-Host ("  scenes={0} total_audio_ms={1} warnings={2}" -f @($scenes).Count, $totalAudioMs, $warnings.Count) -ForegroundColor Green

if ($warnings.Count -gt 0) {
  Write-Host "WARNINGS:" -ForegroundColor Yellow
  foreach ($w in $warnings) {
    Write-Host ("  - " + $w) -ForegroundColor Yellow
  }
}
