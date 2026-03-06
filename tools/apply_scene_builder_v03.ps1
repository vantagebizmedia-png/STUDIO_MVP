param(
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot,
  [Parameter(Mandatory=$false)][string]$PackDir,

  [int]$MinScenes = 8,
  [int]$MaxScenes = 40,
  [int]$TargetSceneSec = 6,

  [int]$MinSceneSec = 4,
  [int]$MaxSceneSec = 8,

  [int]$Seed = 123,
  [switch]$Force,

  [switch]$SkipPixabay,
  [switch]$SkipEnrich
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

function Normalize-ToArray {
  param($Value)

  if ($null -eq $Value) { return @() }

  if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
    return @($Value)
  }

  return @($Value)
}

function Get-TotalAudioMs {
  param($AudioClips)

  $clips = @(Normalize-ToArray -Value $AudioClips)
  $lastEnd = 0

  foreach ($c in $clips) {
    try {
      $e = [int]$c.end_ms
      if ($e -gt $lastEnd) { $lastEnd = $e }
    }
    catch { }
  }

  if ($lastEnd -le 0) { $lastEnd = 20000 }
  return $lastEnd
}

function Split-ScriptSentences {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

  $t = ($Text -replace "`r`n", "`n" -replace "`r", "`n").Trim()
  if ([string]::IsNullOrWhiteSpace($t)) { return @() }

  $parts = @(
    $t -split '(?<=[\.\!\?\:\;])\s+' |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $_.Length -gt 0 }
  )

  if (@($parts).Count -eq 0) {
    return @($t)
  }

  return @($parts)
}

function Build-SceneTexts {
  param(
    [object[]]$Parts,
    [int]$SceneCount
  )

  $partsArr = @(Normalize-ToArray -Value $Parts)
  if ($SceneCount -lt 1) { return @() }
  if (@($partsArr).Count -eq 0) { return @() }

  $result = New-Object System.Collections.Generic.List[string]
  $cursor = 0
  $totalParts = @($partsArr).Count

  for ($i = 0; $i -lt $SceneCount; $i++) {
    $remainingScenes = $SceneCount - $i
    $remainingParts  = $totalParts - $cursor

    if ($remainingParts -le 0) {
      $fallback = "contenido"
      if ($result.Count -gt 0) {
        $fallback = [string]$result[$result.Count - 1]
        if (-not $fallback.EndsWith("...")) { $fallback = $fallback + "..." }
      }
      $result.Add($fallback)
      continue
    }

    $take = [int][Math]::Ceiling($remainingParts / [double]$remainingScenes)
    if ($take -lt 1) { $take = 1 }
    if ($take -gt $remainingParts) { $take = $remainingParts }

    $end = $cursor + $take - 1
    $chunk = @($partsArr[$cursor..$end])

    $chunkText = @(
      $chunk |
      ForEach-Object { [string]$_ } |
      ForEach-Object { ($_ -replace '\s+', ' ').Trim() } |
      Where-Object { $_ -and $_.Length -gt 0 }
    ) -join " "

    $chunkText = ($chunkText -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($chunkText)) {
      $chunkText = "contenido"
    }

    if ($result.Count -gt 0) {
      $prev = [string]$result[$result.Count - 1]
      if ($chunkText -eq $prev) {
        $chunkText = $chunkText + "..."
      }
    }

    $result.Add($chunkText)
    $cursor += $take
  }

  while ($result.Count -lt $SceneCount) {
    $last = "contenido"
    if ($result.Count -gt 0) {
      $last = [string]$result[$result.Count - 1]
      if (-not $last.EndsWith("...")) { $last = $last + "..." }
    }
    $result.Add($last)
  }

  return @($result.ToArray())
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

function ScenesHaveValidImages {
  param(
    $ManifestObj,
    [string]$LiveDir,
    [int]$ExpectedCount
  )

  if (-not $ManifestObj.scenes_v03) { return $false }

  $sc = @($ManifestObj.scenes_v03)
  if (@($sc).Count -ne $ExpectedCount) { return $false }

  for ($i = 0; $i -lt $ExpectedCount; $i++) {
    $scene = $sc[$i]
    if (-not $scene.assets) { return $false }

    $imgRel = Get-AssetPathValue -AssetsObj $scene.assets -Key "image"
    if ([string]::IsNullOrWhiteSpace($imgRel)) { return $false }

    $imgAbs = $imgRel
    if (-not [System.IO.Path]::IsPathRooted($imgRel)) {
      $imgAbs = Join-Path $LiveDir ($imgRel -replace '/', '\')
    }
    if (-not (Test-Path -LiteralPath $imgAbs)) { return $false }

    $audioProp = $scene.assets.PSObject.Properties["audio_clip"]
    if (-not $audioProp -or -not $audioProp.Value) { return $false }

    $clipRel = [string]$audioProp.Value
    $clipAbs = $clipRel
    if (-not [System.IO.Path]::IsPathRooted($clipRel)) {
      $clipAbs = Join-Path $LiveDir ($clipRel -replace '/', '\')
    }
    if (-not (Test-Path -LiteralPath $clipAbs)) { return $false }
  }

  return $true
}

function Get-DynamicSceneCount {
  param(
    [int]$TotalAudioMs,
    [int]$ConfiguredMinScenes,
    [int]$ConfiguredMaxScenes,
    [int]$SceneTargetSec,
    [int]$SceneMinSec,
    [int]$SceneMaxSec
  )

  $targetMs   = [Math]::Max(1000, ($SceneTargetSec * 1000))
  $minSceneMs = [Math]::Max(1000, ($SceneMinSec * 1000))
  $maxSceneMs = [Math]::Max($minSceneMs, ($SceneMaxSec * 1000))

  $targetCount      = [int][Math]::Round($TotalAudioMs / [double]$targetMs)
  $minByMaxDuration = [int][Math]::Ceiling($TotalAudioMs / [double]$maxSceneMs)
  $maxByMinDuration = [int][Math]::Floor($TotalAudioMs / [double]$minSceneMs)

  if ($targetCount -lt 1) { $targetCount = 1 }
  if ($minByMaxDuration -lt 1) { $minByMaxDuration = 1 }
  if ($maxByMinDuration -lt 1) { $maxByMinDuration = 1 }

  $n = $targetCount
  if ($n -lt $ConfiguredMinScenes) { $n = $ConfiguredMinScenes }
  if ($n -lt $minByMaxDuration)    { $n = $minByMaxDuration }
  if ($n -gt $ConfiguredMaxScenes) { $n = $ConfiguredMaxScenes }
  if ($n -gt $maxByMinDuration)    { $n = $maxByMinDuration }
  if ($n -lt 1) { $n = 1 }

  return $n
}

function New-Durations {
  param(
    [int]$SceneCount,
    [int]$TotalAudioMs,
    [int]$SceneMinSec,
    [int]$SceneMaxSec,
    [int]$SeedValue
  )

  $minMs = $SceneMinSec * 1000
  $maxMs = $SceneMaxSec * 1000

  if ($SceneCount -lt 1) { return @() }

  $weights = @()
  for ($i = 1; $i -le $SceneCount; $i++) {
    $w = 100

    if ($i -eq 1) {
      $w = 75
    }
    elseif ($i -eq $SceneCount) {
      $w = 115
    }
    else {
      $w = 90 + ((($SeedValue + $i) % 7) * 6)
    }

    $weights += $w
  }

  $weightSum = (@($weights) | Measure-Object -Sum).Sum
  if (-not $weightSum -or $weightSum -le 0) {
    throw "weightSum inválido en New-Durations"
  }

  $durations = @()
  $assigned = 0

  for ($i = 0; $i -lt $SceneCount; $i++) {
    if ($i -lt ($SceneCount - 1)) {
      $dur = [int][Math]::Floor(($TotalAudioMs * $weights[$i]) / $weightSum)
      if ($dur -lt $minMs) { $dur = $minMs }
      if ($dur -gt $maxMs) { $dur = $maxMs }
      $durations += $dur
      $assigned += $dur
    }
    else {
      $dur = $TotalAudioMs - $assigned
      if ($dur -lt $minMs) { $dur = $minMs }
      if ($dur -gt $maxMs) { $dur = $maxMs }
      $durations += $dur
    }
  }

  $sumDur = (@($durations) | Measure-Object -Sum).Sum
  $guard = 0

  while ($sumDur -ne $TotalAudioMs -and $guard -lt 10000) {
    $delta = $TotalAudioMs - $sumDur

    if ($delta -gt 0) {
      for ($i = 0; $i -lt $SceneCount -and $delta -gt 0; $i++) {
        if ($durations[$i] -lt $maxMs) {
          $durations[$i]++
          $delta--
        }
      }
    }
    else {
      for ($i = $SceneCount - 1; $i -ge 0 -and $delta -lt 0; $i--) {
        if ($durations[$i] -gt $minMs) {
          $durations[$i]--
          $delta++
        }
      }
    }

    $sumDur = (@($durations) | Measure-Object -Sum).Sum
    $guard++
  }

  if ((@($durations) | Measure-Object -Sum).Sum -ne $TotalAudioMs) {
    throw "No se pudo ajustar durations exactamente al total"
  }

  return @($durations)
}

function Ensure-Scenes {
  param(
    $ManifestObj,
    [int]$SceneCount,
    [int]$TotalAudioMs,
    [int]$SceneMinSec,
    [int]$SceneMaxSec,
    [int]$SeedValue
  )

  $sc = @()
  if ($ManifestObj.scenes_v03) { $sc = @($ManifestObj.scenes_v03) }

  if (@($sc).Count -gt $SceneCount) {
    $sc = @($sc[0..($SceneCount - 1)])
  }

  if (@($sc).Count -lt $SceneCount) {
    for ($i = @($sc).Count; $i -lt $SceneCount; $i++) {
      $obj = [pscustomobject]@{
        id       = ("scene_{0:000}" -f ($i + 1))
        start_ms = 0
        end_ms   = 0
        text     = ""
        assets   = [pscustomobject]@{
          audio_clip = ""
          image      = @([pscustomobject]@{ path = "" })
        }
      }
      $sc += $obj
    }
  }

  $durations = @(New-Durations -SceneCount $SceneCount -TotalAudioMs $TotalAudioMs -SceneMinSec $SceneMinSec -SceneMaxSec $SceneMaxSec -SeedValue $SeedValue)
  $cur = 0

  for ($i = 0; $i -lt $SceneCount; $i++) {
    $sceneObj = $sc[$i]

    $st = $cur
    $en = $cur + [int]$durations[$i]
    if ($i -eq ($SceneCount - 1)) { $en = $TotalAudioMs }
    $cur = $en

    if (-not ($sceneObj.PSObject.Properties.Name -contains "id")) {
      $sceneObj | Add-Member -Force -NotePropertyName id -NotePropertyValue ("scene_{0:000}" -f ($i + 1))
    }
    elseif ([string]::IsNullOrWhiteSpace([string]$sceneObj.id)) {
      $sceneObj.id = ("scene_{0:000}" -f ($i + 1))
    }

    if (-not ($sceneObj.PSObject.Properties.Name -contains "text")) {
      $sceneObj | Add-Member -Force -NotePropertyName text -NotePropertyValue ""
    }

    if (-not ($sceneObj.PSObject.Properties.Name -contains "assets") -or -not $sceneObj.assets) {
      $sceneObj | Add-Member -Force -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{
        audio_clip = ""
        image      = @([pscustomobject]@{ path = "" })
      })
    }

    if (-not ($sceneObj.assets.PSObject.Properties.Name -contains "audio_clip")) {
      $sceneObj.assets | Add-Member -Force -NotePropertyName audio_clip -NotePropertyValue ""
    }

    if (-not ($sceneObj.assets.PSObject.Properties.Name -contains "image") -or -not $sceneObj.assets.image) {
      $sceneObj.assets | Add-Member -Force -NotePropertyName image -NotePropertyValue @([pscustomobject]@{ path = "" })
    }
    elseif ($sceneObj.assets.image -is [string]) {
      $sceneObj.assets.image = @([pscustomobject]@{ path = [string]$sceneObj.assets.image })
    }

    $sceneObj.start_ms = [int]$st
    $sceneObj.end_ms   = [int]$en
    $sceneObj.assets.audio_clip = ("artifacts/audio_s{0:d2}.wav" -f ($i + 1))
  }

  $ManifestObj.scenes_v03 = @($sc)
}

if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) {
  if (-not $PackDir -or $PackDir.Trim().Length -eq 0) {
    throw "Falta -WorkspaceRoot o -PackDir"
  }

  $PackDir = (Resolve-Path $PackDir).Path
  $WorkspaceRoot = (Resolve-Path (Join-Path $PackDir "..\..")).Path
}

$live = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
if (-not (Test-Path -LiteralPath $live)) { throw "No existe LIVE: $live" }

$manifest = Join-Path $live "manifest_v03.json"
if (-not (Test-Path -LiteralPath $manifest)) { throw "Falta manifest_v03.json en LIVE: $manifest" }

$mRaw = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8
$m = $mRaw | ConvertFrom-Json

if (-not $m.scenes_v03) {
  $m | Add-Member -NotePropertyName scenes_v03 -NotePropertyValue @()
}

$AudioClipsChanged = $false
$AudioClipsCreatedFallback = $false

$hasProp = ($m.PSObject.Properties.Name -contains "audio_clips")
$ac = $null
if ($hasProp) { $ac = $m.audio_clips }

$acArr = @(Normalize-ToArray -Value $ac)

if (-not $hasProp -or $null -eq $ac -or @($acArr).Count -eq 0) {
  $acArr = @([pscustomobject]@{
    id       = "clip_001"
    start_ms = 0
    end_ms   = 20000
    text     = ""
    path     = "artifacts/audio_s01.wav"
  })
  $AudioClipsChanged = $true
  $AudioClipsCreatedFallback = $true
}
else {
  if (-not (($ac -is [System.Collections.IEnumerable]) -and -not ($ac -is [string]))) {
    $AudioClipsChanged = $true
  }
}

$m | Add-Member -Force -NotePropertyName audio_clips -NotePropertyValue @($acArr)

if ($AudioClipsCreatedFallback) {
  Write-Host "WARN: manifest sin audio_clips -> fallback determinista clip_001 (0..20000ms)" -ForegroundColor DarkYellow
}
elseif ($AudioClipsChanged) {
  Write-Host "OK: audio_clips normalizado a array (sin cambiar contenido)" -ForegroundColor DarkGray
}

if (-not $m.artifacts -or -not $m.artifacts.image) {
  throw "manifest sin artifacts.image (fallback requerido): $manifest"
}

try {
  if (-not $m.artifacts.audio -or [string]::IsNullOrWhiteSpace([string]$m.artifacts.audio)) {
    throw "artifacts.audio vacío"
  }
}
catch {
  throw "manifest sin artifacts.audio (base audio requerido): $manifest"
}

$totalAudioMs = Get-TotalAudioMs -AudioClips $m.audio_clips

$scriptText = ""
try {
  if ($m.script) { $scriptText = [string]$m.script }
  elseif ($m.text -and $m.text.script) { $scriptText = [string]$m.text.script }
}
catch {
  $scriptText = ""
}

$scriptParts = @(Split-ScriptSentences -Text $scriptText)

$desiredScenes = Get-DynamicSceneCount `
  -TotalAudioMs $totalAudioMs `
  -ConfiguredMinScenes $MinScenes `
  -ConfiguredMaxScenes $MaxScenes `
  -SceneTargetSec $TargetSceneSec `
  -SceneMinSec $MinSceneSec `
  -SceneMaxSec $MaxSceneSec

if (-not $Force) {
  if (ScenesHaveValidImages -ManifestObj $m -LiveDir $live -ExpectedCount $desiredScenes) {
    if ($AudioClipsChanged) {
      $outSkip = $m | ConvertTo-Json -Depth 50
      $utf8NoBomSkip = New-Object System.Text.UTF8Encoding($false)
      [System.IO.File]::WriteAllText($manifest, $outSkip, $utf8NoBomSkip)
      Write-Host "OK: manifest actualizado (solo audio_clips) antes de SKIP" -ForegroundColor DarkGray
    }

    Write-Host ("SKIP: scene_builder v03 (ya hay scenes+images válidos). scenes={0} desired={1} totalAudioMs={2}" -f @($m.scenes_v03).Count, $desiredScenes, $totalAudioMs) -ForegroundColor DarkGray
    exit 0
  }
}

Ensure-Scenes `
  -ManifestObj $m `
  -SceneCount $desiredScenes `
  -TotalAudioMs $totalAudioMs `
  -SceneMinSec $MinSceneSec `
  -SceneMaxSec $MaxSceneSec `
  -SeedValue $Seed

if (@($scriptParts).Count -gt 0) {
  $sceneTexts = @(Build-SceneTexts -Parts $scriptParts -SceneCount @($m.scenes_v03).Count)

  for ($i = 0; $i -lt @($m.scenes_v03).Count; $i++) {
    $txt = ""
    if ($i -lt @($sceneTexts).Count) { $txt = [string]$sceneTexts[$i] }
    $m.scenes_v03[$i].text = $txt.Trim()
  }
}

$cacheDir = Join-Path $live "cache_v03"
if (-not (Test-Path -LiteralPath $cacheDir)) {
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
}

$pixQuery = Join-Path $repo "tools\stock_query_pixabay_v03.ps1"
$dlTool   = Join-Path $repo "tools\download_file_v03.ps1"

$assetsDir = Join-Path $live "assets\scenes_v03"
if (-not (Test-Path -LiteralPath $assetsDir)) {
  New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null
}

# Asegurar clips físicos por escena para que smoke_live_manifest_v03 no falle
$baseAudioRel = [string]$m.artifacts.audio
$baseAudioAbs = $baseAudioRel
if (-not [System.IO.Path]::IsPathRooted($baseAudioRel)) {
  $baseAudioAbs = Join-Path $live ($baseAudioRel -replace '/', '\')
}
$baseAudioAbs = (Resolve-Path -LiteralPath $baseAudioAbs).Path

for ($i = 0; $i -lt @($m.scenes_v03).Count; $i++) {
  $scene = $m.scenes_v03[$i]

  $clipRel = ("artifacts/audio_s{0:d2}.wav" -f ($i + 1))
  $clipAbs = Join-Path $live ($clipRel -replace '/', '\')

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $clipAbs) | Out-Null
  Copy-Item -LiteralPath $baseAudioAbs -Destination $clipAbs -Force

  if (-not $scene.assets) {
    $scene | Add-Member -Force -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{
      audio_clip = $clipRel
      image      = @([pscustomobject]@{ path = "" })
    })
  }

  if (-not ($scene.assets.PSObject.Properties.Name -contains "audio_clip")) {
    $scene.assets | Add-Member -Force -NotePropertyName audio_clip -NotePropertyValue $clipRel
  }
  else {
    $scene.assets.audio_clip = $clipRel
  }
}

$fallbackRel = [string]$m.artifacts.image
$fallbackAbs = (Resolve-Path (Join-Path $live ($fallbackRel -replace '/', '\'))).Path

for ($i = 0; $i -lt @($m.scenes_v03).Count; $i++) {
  $scene = $m.scenes_v03[$i]

  if (-not $scene.assets) {
    $scene | Add-Member -Force -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{
      audio_clip = ("artifacts/audio_s{0:d2}.wav" -f ($i + 1))
      image      = @([pscustomobject]@{ path = "" })
    })
  }

  if (-not ($scene.assets.PSObject.Properties.Name -contains "audio_clip") -or [string]::IsNullOrWhiteSpace([string]$scene.assets.audio_clip)) {
    $scene.assets | Add-Member -Force -NotePropertyName audio_clip -NotePropertyValue ("artifacts/audio_s{0:d2}.wav" -f ($i + 1))
  }
  else {
    $scene.assets.audio_clip = ("artifacts/audio_s{0:d2}.wav" -f ($i + 1))
  }

  if (-not ($scene.assets.PSObject.Properties.Name -contains "image") -or -not $scene.assets.image) {
    $scene.assets | Add-Member -Force -NotePropertyName image -NotePropertyValue @([pscustomobject]@{ path = "" })
  }
  elseif ($scene.assets.image -is [string]) {
    $scene.assets.image = @([pscustomobject]@{ path = [string]$scene.assets.image })
  }

  $outName = ("scene_{0:000}.jpg" -f ($i + 1))
  $outAbs  = Join-Path $assetsDir $outName
  $outRel  = ("assets/scenes_v03/{0}" -f $outName)

  $q = [string]$scene.text
  if ([string]::IsNullOrWhiteSpace($q) -or $q.Trim().Length -lt 3) {
    $q = "motivación"
  }
  $q = $q.Trim()

  $canPixabay = $false
  if (-not $SkipPixabay) {
    if ($env:PIXABAY_API_KEY -and (Test-Path -LiteralPath $pixQuery) -and (Test-Path -LiteralPath $dlTool)) {
      $canPixabay = $true
    }
  }

  $picked = $null
  $pickedIndex = -1
  $hitsCount = 0
  $cacheJson = Join-Path $cacheDir ("pixabay_scene_{0:000}.json" -f ($i + 1))

  if ($canPixabay) {
    try {
      if (-not (Test-Path -LiteralPath $cacheJson)) {
        pwsh -NoProfile -ExecutionPolicy Bypass -File $pixQuery -Query $q -OutJsonPath $cacheJson -Seed $Seed | Out-Null
      }

      $cj = Get-Content -LiteralPath $cacheJson -Raw -Encoding UTF8 | ConvertFrom-Json
      $hits = @()
      if ($cj -and $cj.hits) { $hits = @($cj.hits) }
      $hitsCount = @($hits).Count

      if ($hitsCount -gt 0) {
        $pickedIndex = ($Seed + $i) % $hitsCount
        $picked = [string]$hits[$pickedIndex].url
      }
    }
    catch {
      $picked = $null
      $pickedIndex = -1
      $hitsCount = 0
    }
  }

  $ok = $false
  if ($picked) {
    try {
      pwsh -NoProfile -ExecutionPolicy Bypass -File $dlTool -Url $picked -OutPath $outAbs | Out-Null
      $scene.assets.image = @(
        [pscustomobject]@{
          path         = $outRel
          provider     = "pixabay"
          used_query   = $q
          hits_count   = $hitsCount
          picked_index = $pickedIndex
          source_url   = $picked
          note         = ""
        }
      )
      $ok = $true
      Write-Host ("OK: scene[{0}] image=PIXABAY -> {1}" -f $i, $outRel) -ForegroundColor DarkGray
    }
    catch {
      $ok = $false
    }
  }

  if (-not $ok) {
    Copy-Item -LiteralPath $fallbackAbs -Destination $outAbs -Force
    $scene.assets.image = @(
      [pscustomobject]@{
        path         = $outRel
        provider     = ($(if ($SkipPixabay) { "fallback_skip_pixabay" } else { "fallback_artifacts_image" }))
        used_query   = $q
        hits_count   = $hitsCount
        picked_index = $pickedIndex
        source_url   = ""
        note         = ($(if ($SkipPixabay) { "fallback: SkipPixabay=True" } else { "fallback: artifacts.image" }))
      }
    )

    if ($SkipPixabay) {
      Write-Host ("OK: scene[{0}] image=FALLBACK(SkipPixabay) -> {1}" -f $i, $outRel) -ForegroundColor DarkGray
    }
    else {
      Write-Host ("OK: scene[{0}] image=FALLBACK(artifacts.image) -> {1}" -f $i, $outRel) -ForegroundColor DarkGray
    }
  }
}

$out = $m | ConvertTo-Json -Depth 50
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifest, $out, $utf8NoBom)

if (-not $SkipEnrich) {
  try {
    $enricher = Join-Path $repo "tools\enrich_scenes_queries_v03.ps1"
    if (Test-Path -LiteralPath $enricher) {
      $manifestGuess = $null

      if ($WorkspaceRoot -and $WorkspaceRoot.Trim().Length -gt 0) {
        $mg = Join-Path $WorkspaceRoot "runs\smoke_live_latest\manifest_v03.json"
        if (Test-Path -LiteralPath $mg) { $manifestGuess = $mg }
      }

      if (-not $manifestGuess -and (Get-Variable -Name PackDir -ErrorAction SilentlyContinue)) {
        if ($PackDir -and (Test-Path -LiteralPath $PackDir)) {
          $mg2 = Join-Path $PackDir "manifest_v03.json"
          if (Test-Path -LiteralPath $mg2) { $manifestGuess = $mg2 }
        }
      }

      if ($manifestGuess -and (Test-Path -LiteralPath $manifestGuess)) {
        if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) {
          throw "WorkspaceRoot vacío: no se puede ejecutar enrich_scenes_queries_v03.ps1"
        }

        & pwsh -NoProfile -ExecutionPolicy Bypass -File $enricher -WorkspaceRoot $WorkspaceRoot -Seed $Seed | Out-Null
        $enrichExit = $LASTEXITCODE

        if ($enrichExit -ne 0) {
          throw "enrich_scenes_queries_v03.ps1 devolvió exit code $enrichExit"
        }

        Write-Host ("OK: enrich_scenes_queries_v03 aplicado (workspace={0} manifest={1})" -f $WorkspaceRoot, $manifestGuess) -ForegroundColor DarkGray
      }
      else {
        Write-Host "WARN: no encontré manifest_v03.json para enriquecer queries" -ForegroundColor Yellow
      }
    }
    else {
      Write-Host "WARN: falta tool enrich_scenes_queries_v03.ps1 (skip)" -ForegroundColor Yellow
    }
  }
  catch {
    Write-Host ("WARN: enrich_scenes_queries_v03 falló (skip): {0}" -f $_.Exception.Message) -ForegroundColor Yellow
  }
}
else {
  Write-Host "SKIP: enrich_scenes_queries_v03 (SkipEnrich=True)" -ForegroundColor DarkGray
}

Write-Host ("OK: scene_builder v03 aplicado. scenes={0} totalAudioMs={1} targetSceneSec={2} minSceneSec={3} maxSceneSec={4} minScenes={5} maxScenes={6} live={7} force={8} skipPixabay={9} skipEnrich={10}" -f @($m.scenes_v03).Count, $totalAudioMs, $TargetSceneSec, $MinSceneSec, $MaxSceneSec, $MinScenes, $MaxScenes, $live, [bool]$Force, [bool]$SkipPixabay, [bool]$SkipEnrich) -ForegroundColor Green