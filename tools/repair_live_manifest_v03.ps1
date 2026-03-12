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

  $candidates = @()

  try { if ($Scene.PSObject.Properties["text"] -and $Scene.text) { $candidates += [string]$Scene.text } } catch { }
  try { if ($Scene.PSObject.Properties["script_text"] -and $Scene.script_text) { $candidates += [string]$Scene.script_text } } catch { }
  try { if ($Scene.PSObject.Properties["narration"] -and $Scene.narration) { $candidates += [string]$Scene.narration } } catch { }
  try { if ($Scene.PSObject.Properties["onscreen"] -and $Scene.onscreen) { $candidates += [string]$Scene.onscreen } } catch { }

  foreach ($v in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($v)) {
      return $v.Trim()
    }
  }

  return ""
}

function Get-SceneQuery {
  param($Scene)

  $candidates = @()

  try { if ($Scene.PSObject.Properties["image_query"] -and $Scene.image_query) { $candidates += [string]$Scene.image_query } } catch { }
  try { if ($Scene.PSObject.Properties["query"] -and $Scene.query) { $candidates += [string]$Scene.query } } catch { }
  try { if ($Scene.PSObject.Properties["stock_query"] -and $Scene.stock_query) { $candidates += [string]$Scene.stock_query } } catch { }

  foreach ($v in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($v)) {
      return $v.Trim()
    }
  }

  $fallback = Get-SceneText -Scene $Scene
  if (-not [string]::IsNullOrWhiteSpace($fallback)) {
    return $fallback
  }

  return "motivacion"
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

    $scenes += [pscustomobject]@{
      id                 = ("scene_{0:000}" -f ($i + 1))
      index              = [int]$i
      start_ms           = Get-IntOrZero -Value $row.start_ms
      end_ms             = Get-IntOrZero -Value $row.end_ms
      duration_ms        = Get-IntOrZero -Value $row.duration_ms
      text               = [string]$textValue
      script_text        = [string]$textValue
      image_query        = ""
      query              = ""
      visual_kind        = $(if (-not [string]::IsNullOrWhiteSpace($videoValue) -and [string]::IsNullOrWhiteSpace($imageValue)) { "video" } else { "image" })
      visual_source_kind = $(if (-not [string]::IsNullOrWhiteSpace($videoValue) -and [string]::IsNullOrWhiteSpace($imageValue)) { "stock_video" } else { "stock_image" })
      visual_capability  = $(if (-not [string]::IsNullOrWhiteSpace($videoValue) -and [string]::IsNullOrWhiteSpace($imageValue)) { "stock_video" } else { "stock_image" })
      assets             = [pscustomobject]@{
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

$visualMetaSharedPath = Join-Path $PSScriptRoot "scene_visual_meta_shared_v03.ps1"
if (-not (Test-Path -LiteralPath $visualMetaSharedPath -PathType Leaf)) {
  throw ("No existe helper visual meta compartido: {0}" -f $visualMetaSharedPath)
}

. $visualMetaSharedPath

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

  $sceneText = Get-SceneText -Scene $scene
  $sceneQuery = Get-SceneQuery -Scene $scene

  $currentVisualKind = ""
  try {
    if ($scene.PSObject.Properties["visual_kind"] -and $scene.visual_kind) {
      $currentVisualKind = ([string]$scene.visual_kind).Trim().ToLowerInvariant()
    }
  }
  catch { $currentVisualKind = "" }

  $resolvedAudio = Resolve-ExistingFileRelative -BaseDir $live -Candidates @(
    [string]$scene.assets.audio_clip,
    ("artifacts/audio_s{0:d2}.wav" -f $ord),
    ("assets/audio_clips/s{0:d2}.wav" -f $ord),
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

  $finalVisualKind = Get-ResolvedSceneVisualKind -CurrentVisualKind $currentVisualKind -ResolvedImage $resolvedImage -ResolvedVideo $resolvedVideo

  if ((-not $hasImage) -and (-not $hasVideo)) {
    $warnings.Add(("scene_{0:d2}: no se encontró image/video real" -f $ord)) | Out-Null
  }

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

  $scene.assets.audio_clip = [string]$resolvedAudio

  if ($finalVisualKind -eq "video") {
    $scene.assets.video = [string]$resolvedVideo
    $scene.assets.image = ""

    $scene | Add-Member -Force -NotePropertyName visual_kind -NotePropertyValue "video"
    $scene | Add-Member -Force -NotePropertyName visual_source_kind -NotePropertyValue "stock_video"
    $scene | Add-Member -Force -NotePropertyName visual_capability -NotePropertyValue "stock_video"

    Update-SceneVisualMetaShared -Scene $scene -Kind "video" -Query ([string]$sceneQuery) -FallbackProvider "repair_live_manifest_v03" | Out-Null
  }
  else {
    $scene.assets.image = [string]$resolvedImage
    $scene.assets.video = ""

    $scene | Add-Member -Force -NotePropertyName visual_kind -NotePropertyValue "image"
    $scene | Add-Member -Force -NotePropertyName visual_source_kind -NotePropertyValue "stock_image"
    $scene | Add-Member -Force -NotePropertyName visual_capability -NotePropertyValue "stock_image"

    Update-SceneVisualMetaShared -Scene $scene -Kind "image" -Query ([string]$sceneQuery) -FallbackProvider "repair_live_manifest_v03" | Out-Null
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
    image      = [string]$scene.assets.image
    audio      = [string]$scene.assets.audio_clip
    start_ms   = [int]$st
    end_ms     = [int]$en
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
try {
  if ($manifest.PSObject.Properties["scene_builder_v03"] -and $manifest.scene_builder_v03) {
    $sbOld = $manifest.scene_builder_v03
    if ($sbOld.PSObject.Properties["note"] -and $sbOld.note) {
      $existingNote = [string]$sbOld.note
    }
  }
}
catch { $existingNote = "" }

$noteValue = "repaired_by_repair_live_manifest_v03"
if (-not [string]::IsNullOrWhiteSpace($existingNote)) {
  $noteValue = ($existingNote.Trim() + "; repaired_by_repair_live_manifest_v03")
}

$sceneBuilderMeta = [pscustomobject]@{
  max_scenes     = [int]$scenes.Count
  total_audio_ms = [int]$totalAudioMs
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