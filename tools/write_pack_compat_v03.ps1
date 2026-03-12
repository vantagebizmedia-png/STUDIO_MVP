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

function Get-IntOrZero {
  param($Value)

  try { return [int]$Value } catch { return 0 }
}

function Get-AssetPathValue {
  param($AssetsObj, [string]$Key)

  if (-not $AssetsObj) { return "" }

  $prop = $AssetsObj.PSObject.Properties[$Key]
  if (-not $prop -or -not $prop.Value) { return "" }

  $v = $prop.Value

  if ($v -is [string]) { return [string]$v }

  if ($v -is [pscustomobject] -or $v -is [hashtable]) {
    $p = $v.PSObject.Properties["path"]
    if ($p -and $p.Value) { return [string]$p.Value }
    return ""
  }

  if (($v -is [System.Collections.IEnumerable]) -and -not ($v -is [string])) {
    $arr = @($v)
    if (@($arr).Count -ge 1) {
      $x = $arr[0]
      if ($x -is [string]) { return [string]$x }
      if ($x -is [pscustomobject] -or $x -is [hashtable]) {
        $p0 = $x.PSObject.Properties["path"]
        if ($p0 -and $p0.Value) { return [string]$p0.Value }
      }
    }
  }

  return ""
}

function Write-JsonUtf8NoBom {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)]$Object
  )

  $enc = [System.Text.UTF8Encoding]::new($false)
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

$packCompatScenes = @()

for ($i = 0; $i -lt $scenes.Count; $i++) {
  $scene = $scenes[$i]

  $imgPath = ""
  $audioPath = ""
  $sceneId = ""
  $sceneText = ""
  $sceneStart = 0
  $sceneEnd = 0

  try {
    if ($scene.assets) {
      $imgPath = [string](Get-AssetPathValue -AssetsObj $scene.assets -Key "image")
      if ([string]::IsNullOrWhiteSpace($audioPath) -and $scene.assets.PSObject.Properties["audio_clip"] -and $scene.assets.audio_clip) {
        $audioPath = [string]$scene.assets.audio_clip
      }
    }
  }
  catch {
    $imgPath = ""
    $audioPath = ""
  }

  try { $sceneId = [string]$scene.id } catch { $sceneId = "" }
  try { $sceneText = [string]$scene.text } catch { $sceneText = "" }
  try { $sceneStart = [int]$scene.start_ms } catch { $sceneStart = 0 }
  try { $sceneEnd = [int]$scene.end_ms } catch { $sceneEnd = 0 }

  $sceneIndex = 0
  try {
    $digits = ($sceneId -replace '[^\d]','')
    if (-not [string]::IsNullOrWhiteSpace($digits)) {
      $sceneIndex = [int]$digits
    }
  }
  catch { $sceneIndex = 0 }

  if ($sceneIndex -le 0) {
    $sceneIndex = $i + 1
  }

  $packCompatScenes += [pscustomobject]@{
    id         = $sceneId
    index      = [int]$sceneIndex
    text       = $sceneText
    narration  = $sceneText
    onscreen   = $sceneText
    audio_text = $sceneText
    image      = $imgPath
    audio      = $audioPath
    start_ms   = $sceneStart
    end_ms     = $sceneEnd
  }
}

$manifestScript = ""
try {
  if ($manifest.PSObject.Properties["script"] -and $manifest.script) {
    $manifestScript = [string]$manifest.script
  }
  elseif ($manifest.PSObject.Properties["text"] -and $manifest.text) {
    if ($manifest.text -is [string]) {
      $manifestScript = [string]$manifest.text
    }
    elseif ($manifest.text.PSObject.Properties["script"] -and $manifest.text.script) {
      $manifestScript = [string]$manifest.text.script
    }
  }

  if ([string]::IsNullOrWhiteSpace($manifestScript)) {
    $parts = @()
    foreach ($scene in $scenes) {
      try {
        if ($scene.PSObject.Properties["text"] -and -not [string]::IsNullOrWhiteSpace([string]$scene.text)) {
          $parts += [string]$scene.text
        }
      }
      catch { }
    }

    if ($parts.Count -gt 0) {
      $manifestScript = ($parts -join " ").Trim()
    }
  }
}
catch {
  $manifestScript = ""
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

$totalAudioMs = 0
$sceneBuilderMaxScenes = @($scenes).Count
$sceneBuilderNote = "synced_by_write_pack_compat_v03"

try {
  if ($manifest.PSObject.Properties["scene_builder_v03"] -and $manifest.scene_builder_v03) {
    $sb = $manifest.scene_builder_v03

    if ($sb.PSObject.Properties["total_audio_ms"] -and $null -ne $sb.total_audio_ms) {
      $totalAudioMs = [int]$sb.total_audio_ms
    }

    if ($sb.PSObject.Properties["max_scenes"] -and $null -ne $sb.max_scenes) {
      $sceneBuilderMaxScenes = [int]$sb.max_scenes
    }

    if ($sb.PSObject.Properties["note"] -and -not [string]::IsNullOrWhiteSpace([string]$sb.note)) {
      $sceneBuilderNote = [string]$sb.note
    }
  }
}
catch { }

if ($totalAudioMs -le 0) {
  try {
    if ($manifest.PSObject.Properties["total_audio_ms"] -and $null -ne $manifest.total_audio_ms) {
      $totalAudioMs = [int]$manifest.total_audio_ms
    }
  }
  catch { $totalAudioMs = 0 }
}

if ($totalAudioMs -le 0) {
  foreach ($scene in $scenes) {
    try {
      $e = [int]$scene.end_ms
      if ($e -gt $totalAudioMs) { $totalAudioMs = $e }
    }
    catch { }
  }
}

$sceneBuilderMeta = [pscustomobject]@{
  max_scenes     = [int]$sceneBuilderMaxScenes
  total_audio_ms = [int]$totalAudioMs
  note           = [string]$sceneBuilderNote
}

$audioClips = @()
try {
  if ($manifest.PSObject.Properties["audio_clips"] -and $manifest.audio_clips) {
    $audioClips = @(Normalize-ToArray -Value $manifest.audio_clips)
  }
}
catch {
  $audioClips = @()
}

$packCompat = [pscustomobject]@{
  version           = "v03"
  total_audio_ms    = [int]$totalAudioMs
  script            = $manifestScript
  scenes            = $packCompatScenes
  scenes_v03        = $scenes
  audio_clips       = $audioClips
  artifacts         = [pscustomobject]@{
    image = $artifactImage
    audio = $artifactAudio
  }
  scene_builder_v03 = $sceneBuilderMeta
}

$packJsonPath = Join-Path $live "pack.json"
Write-JsonUtf8NoBom -Path $packJsonPath -Object $packCompat

Write-Host ("OK: pack compat v03 escrito. live={0}" -f $live) -ForegroundColor Green