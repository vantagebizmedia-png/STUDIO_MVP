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

  $cleanParts = @(
    $partsArr |
    ForEach-Object { [string]$_ } |
    ForEach-Object { ($_ -replace "\s+", " ").Trim() } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )

  if (@($cleanParts).Count -eq 0) { return @() }

  $totalParts = @($cleanParts).Count
  $effectiveSceneCount = [Math]::Max(1, [Math]::Min($SceneCount, $totalParts))
  $partMeta = New-Object System.Collections.Generic.List[pscustomobject]
  $totalWords = 0
  $totalStrongPunct = 0

  foreach ($p in $cleanParts) {
    $txt = [string]$p
    $wc = @([regex]::Matches($txt, '\S+')).Count
    if ($wc -lt 1) { $wc = 1 }
    $pc = @([regex]::Matches($txt, '[\.\!\?\:\;]')).Count
    $partMeta.Add([pscustomobject]@{
      text = $txt
      words = $wc
      punct = $pc
      endsStrong = [bool]($txt -match '[\.\!\?\:\;]\s*$')
    }) | Out-Null
    $totalWords += $wc
    $totalStrongPunct += $pc
  }

  $targetWordsPerScene = [Math]::Max(6, [int][Math]::Round($totalWords / [double]$effectiveSceneCount))
  $targetPunctPerScene = [int][Math]::Round($totalStrongPunct / [double]$effectiveSceneCount)

  $result = New-Object System.Collections.Generic.List[string]
  $cursor = 0

  for ($i = 0; $i -lt $effectiveSceneCount; $i++) {
    $remainingScenes = $effectiveSceneCount - $i
    $remainingParts = $totalParts - $cursor

    if ($remainingScenes -le 1) {
      $tail = ($partMeta[$cursor..($totalParts - 1)] | ForEach-Object { [string]$_.text }) -join " "
      $tail = ($tail -replace "\s+", " ").Trim()
      $result.Add(($tail -replace "\s+", " ")) | Out-Null
      $cursor = $totalParts
      continue
    }

    $maxTake = $remainingParts - ($remainingScenes - 1)
    if ($maxTake -lt 1) { $maxTake = 1 }

    $take = 0
    $accWords = 0
    $accPunct = 0

    while ($take -lt $maxTake) {
      $m = $partMeta[$cursor + $take]
      $accWords += [int]$m.words
      $accPunct += [int]$m.punct
      $take++

      if ($take -lt 1) { continue }

      $reachedWordBalance = ($accWords -ge $targetWordsPerScene)
      $reachedPunctBalance = ($targetPunctPerScene -le 0) -or ($accPunct -ge [Math]::Max(1, [int][Math]::Floor($targetPunctPerScene * 0.6)))
      $isStrongBoundary = [bool]$m.endsStrong
      $enoughContext = ($accWords -ge [int][Math]::Floor($targetWordsPerScene * 0.75))
      $tooLong = ($accWords -ge [int][Math]::Ceiling($targetWordsPerScene * 1.8))

      if ($reachedWordBalance -and $reachedPunctBalance) { break }
      if ($isStrongBoundary -and $enoughContext) { break }
      if ($tooLong) { break }
    }

    if ($take -lt 1) { $take = 1 }

    $chunk = @($partMeta[$cursor..($cursor + $take - 1)] | ForEach-Object { [string]$_.text })
    $text = (($chunk -join " ") -replace "\s+", " ").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
      $text = [string]$partMeta[$cursor].text
    }

    $result.Add($text) | Out-Null
    $cursor += $take
  }

  while ($result.Count -lt $SceneCount) {
    $last = [string]$result[[Math]::Max(0, $result.Count - 1)]
    $result.Add($last) | Out-Null
  }

  return @($result)
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
    [object[]]$ScriptParts,
    [int]$TotalAudioMs,
    [int]$ConfiguredMinScenes,
    [int]$ConfiguredMaxScenes,
    [int]$SceneTargetSec,
    [int]$SceneMinSec,
    [int]$SceneMaxSec
  )

  $partsArr = @(Normalize-ToArray -Value $ScriptParts)

  $targetMs   = [Math]::Max(1000, ($SceneTargetSec * 1000))
  $minSceneMs = [Math]::Max(1000, ($SceneMinSec * 1000))
  $maxSceneMs = [Math]::Max($minSceneMs, ($SceneMaxSec * 1000))

  $scriptCount = @($partsArr).Count

  if ($scriptCount -gt 0) {
    $n = [int][Math]::Ceiling($scriptCount / 2.0)
    if ($scriptCount -le 3) { $n = $scriptCount }
    if ($n -lt 1) { $n = 1 }

    if ($ConfiguredMinScenes -gt 0 -and $scriptCount -ge $ConfiguredMinScenes -and $n -lt $ConfiguredMinScenes) {
      $n = $ConfiguredMinScenes
    }

    $softMinMs = [int][Math]::Round($minSceneMs * 0.60)
    $softMaxMs = [int][Math]::Round($maxSceneMs * 1.60)
    if ($softMinMs -lt 1000) { $softMinMs = 1000 }
    if ($softMaxMs -lt $softMinMs) { $softMaxMs = $softMinMs }

    $avgMs = [int][Math]::Round($TotalAudioMs / [double][Math]::Max(1, $n))

    if ($avgMs -gt $softMaxMs) {
      $add = [int][Math]::Ceiling(($avgMs - $softMaxMs) / [double]$softMaxMs)
      if ($add -lt 1) { $add = 1 }
      if ($add -gt 3) { $add = 3 }
      $n += $add
    }
    elseif ($avgMs -lt $softMinMs -and $n -gt 1) {
      $sub = [int][Math]::Ceiling(($softMinMs - $avgMs) / [double]$softMinMs)
      if ($sub -lt 1) { $sub = 1 }
      if ($sub -gt 2) { $sub = 2 }
      $n -= $sub
    }

    if ($n -gt $scriptCount) { $n = $scriptCount }
    if ($ConfiguredMaxScenes -gt 0 -and $n -gt $ConfiguredMaxScenes) { $n = $ConfiguredMaxScenes }
    if ($n -lt 1) { $n = 1 }
    return $n
  }

  $audioTargetCount = [int][Math]::Round($TotalAudioMs / [double]$targetMs)
  $audioMinByMax    = [int][Math]::Ceiling($TotalAudioMs / [double]$maxSceneMs)
  $audioMaxByMin    = [int][Math]::Floor($TotalAudioMs / [double]$minSceneMs)
  if ($audioTargetCount -lt 1) { $audioTargetCount = 1 }
  if ($audioMinByMax -lt 1)    { $audioMinByMax = 1 }
  if ($audioMaxByMin -lt 1)    { $audioMaxByMin = 1 }

  $n = $audioTargetCount
  if ($ConfiguredMinScenes -gt 0 -and $n -lt $ConfiguredMinScenes) { $n = $ConfiguredMinScenes }
  if ($n -lt $audioMinByMax)       { $n = $audioMinByMax }
  if ($ConfiguredMaxScenes -gt 0 -and $n -gt $ConfiguredMaxScenes) { $n = $ConfiguredMaxScenes }
  if ($n -gt $audioMaxByMin)       { $n = $audioMaxByMin }
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

  if ($SceneCount -lt 1) { return @() }
  $minMs = [Math]::Max(1000, ($SceneMinSec * 1000))
  $maxMs = [Math]::Max($minMs, ($SceneMaxSec * 1000))
  $softMinMs = [Math]::Max(1000, [int][Math]::Round($minMs * 0.50))
  $softMaxMs = [Math]::Max($softMinMs, [int][Math]::Round($maxMs * 2.40))

  # Prefer narrative cues from existing scene texts (kept by Ensure-Scenes when reusing scenes).
  $sceneTexts = @()
  $callerScenes = Get-Variable -Scope 1 -Name sc -ErrorAction SilentlyContinue
  if ($callerScenes -and $callerScenes.Value) {
    $tmpScenes = @($callerScenes.Value)
    for ($i = 0; $i -lt [Math]::Min($SceneCount, @($tmpScenes).Count); $i++) {
      $t = ""
      try { if ($tmpScenes[$i].text) { $t = [string]$tmpScenes[$i].text } } catch { $t = "" }
      $sceneTexts += $t
    }
  }

  while (@($sceneTexts).Count -lt $SceneCount) { $sceneTexts += "" }

  $weights = New-Object System.Collections.Generic.List[double]
  $hasNarrativeSignal = $false

  for ($i = 0; $i -lt $SceneCount; $i++) {
    $text = [string]$sceneTexts[$i]
    $textNorm = ($text -replace "\s+", " ").Trim()

    $words = 0
    $strongPunct = 0
    $chars = 0

    if (-not [string]::IsNullOrWhiteSpace($textNorm)) {
      $words = @([regex]::Matches($textNorm, '\S+')).Count
      $strongPunct = @([regex]::Matches($textNorm, '[\.\!\?\:\;]')).Count
      $chars = $textNorm.Length
      if ($words -gt 0 -or $strongPunct -gt 0 -or $chars -gt 0) { $hasNarrativeSignal = $true }
    }

    if ($words -lt 1) { $words = 1 }
    $seedJitter = 0.92 + (((($SeedValue + (($i + 1) * 17)) % 19) / 100.0))

    $w = 1.0 + ($words * 1.0) + ($strongPunct * 3.1) + ([Math]::Sqrt([Math]::Max(1, $chars)) * 0.50)
    $weights.Add([Math]::Max(0.25, ($w * $seedJitter))) | Out-Null
  }

  if (-not $hasNarrativeSignal) {
    $weights.Clear()
    for ($i = 0; $i -lt $SceneCount; $i++) {
      $wFallback = 0.65 + (((($SeedValue + (($i + 1) * 13)) % 23) / 14.0))
      if ($i -eq 0) { $wFallback *= 0.85 }
      if ($i -eq ($SceneCount - 1)) { $wFallback *= 1.15 }
      $weights.Add([Math]::Max(0.25, $wFallback)) | Out-Null
    }
  }
  else {
    # Increase separation between dense and light narrative blocks without losing determinism.
    for ($i = 0; $i -lt $weights.Count; $i++) {
      $weights[$i] = [Math]::Pow([double]$weights[$i], 1.28)
    }
  }

  $weightSum = (@($weights) | Measure-Object -Sum).Sum
  if (-not $weightSum -or $weightSum -le 0) { throw "weightSum inválido en New-Durations" }

  $durations = New-Object System.Collections.Generic.List[int]
  $remainders = New-Object System.Collections.Generic.List[pscustomobject]
  $assigned = 0

  for ($i = 0; $i -lt $SceneCount; $i++) {
    $raw = ($TotalAudioMs * [double]$weights[$i]) / [double]$weightSum
    $base = [int][Math]::Floor($raw)
    if ($base -lt 1) { $base = 1 }
    $durations.Add($base) | Out-Null
    $assigned += $base
    $remainders.Add([pscustomobject]@{ idx = $i; rem = ($raw - $base) }) | Out-Null
  }

  $delta0 = $TotalAudioMs - $assigned
  if ($delta0 -gt 0) {
    $order = @($remainders | Sort-Object -Property rem -Descending)
    $k = 0
    while ($delta0 -gt 0) {
      $idx = [int]$order[$k % @($order).Count].idx
      $durations[$idx] = [int]$durations[$idx] + 1
      $delta0--
      $k++
    }
  }
  elseif ($delta0 -lt 0) {
    $need = -$delta0
    $orderDown = @(0..($SceneCount - 1) | Sort-Object { $durations[$_] } -Descending)
    $k = 0
    while ($need -gt 0 -and $k -lt 200000) {
      $idx = [int]$orderDown[$k % @($orderDown).Count]
      if ($durations[$idx] -gt 1) {
        $durations[$idx] = [int]$durations[$idx] - 1
        $need--
      }
      $k++
    }
  }

  $guard = 0
  while ($guard -lt 10000) {
    $changed = $false

    for ($i = 0; $i -lt $SceneCount; $i++) {
      if ($durations[$i] -lt $softMinMs) {
        $need = $softMinMs - $durations[$i]
        $donors = @(0..($SceneCount - 1) | Where-Object { $_ -ne $i -and $durations[$_] -gt $softMinMs } | Sort-Object { $durations[$_] } -Descending)
        foreach ($d in $donors) {
          if ($need -le 0) { break }
          $canGive = $durations[$d] - $softMinMs
          if ($canGive -le 0) { continue }
          $take = [Math]::Min($need, $canGive)
          $durations[$d] = [int]$durations[$d] - $take
          $durations[$i] = [int]$durations[$i] + $take
          $need -= $take
          $changed = $true
        }
      }
      elseif ($durations[$i] -gt $softMaxMs) {
        $extra = $durations[$i] - $softMaxMs
        $receivers = @(0..($SceneCount - 1) | Where-Object { $_ -ne $i -and $durations[$_] -lt $softMaxMs } | Sort-Object { $durations[$_] })
        foreach ($r in $receivers) {
          if ($extra -le 0) { break }
          $cap = $softMaxMs - $durations[$r]
          if ($cap -le 0) { continue }
          $move = [Math]::Min($extra, $cap)
          $durations[$r] = [int]$durations[$r] + $move
          $durations[$i] = [int]$durations[$i] - $move
          $extra -= $move
          $changed = $true
        }
      }
    }

    if (-not $changed) { break }
    $guard++
  }

  $sumDur = (@($durations) | Measure-Object -Sum).Sum
  $delta = $TotalAudioMs - $sumDur
  if ($delta -gt 0) {
    $orderUp = @(0..($SceneCount - 1) | Sort-Object { $weights[$_] } -Descending)
    $k = 0
    while ($delta -gt 0) {
      $idx = [int]$orderUp[$k % @($orderUp).Count]
      $durations[$idx] = [int]$durations[$idx] + 1
      $delta--
      $k++
    }
  }
  elseif ($delta -lt 0) {
    $need = -$delta
    $orderDown = @(0..($SceneCount - 1) | Sort-Object { $weights[$_] })
    $k = 0
    while ($need -gt 0 -and $k -lt 300000) {
      $idx = [int]$orderDown[$k % @($orderDown).Count]
      if ($durations[$idx] -gt 1000) {
        $durations[$idx] = [int]$durations[$idx] - 1
        $need--
      }
      $k++
    }
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

function Sync-PackCompat {
  param(
    [Parameter(Mandatory=$true)]$ManifestObj,
    [Parameter(Mandatory=$true)][string]$LiveDir
  )

  $packCompatScenes = @()

  foreach ($scene in @($ManifestObj.scenes_v03)) {
    $imgPath = ""
    try {
      if ($scene.assets -and $scene.assets.image) {
        if (($scene.assets.image -is [System.Collections.IEnumerable]) -and -not ($scene.assets.image -is [string])) {
          $firstImg = @($scene.assets.image)[0]
          if ($firstImg) {
            if ($firstImg -is [string]) {
              $imgPath = [string]$firstImg
            }
            elseif ($firstImg.PSObject.Properties["path"] -and $firstImg.path) {
              $imgPath = [string]$firstImg.path
            }
          }
        }
        elseif ($scene.assets.image -is [string]) {
          $imgPath = [string]$scene.assets.image
        }
      }
    }
    catch { $imgPath = "" }

    $audioPath = ""
    try {
      if ($scene.assets -and $scene.assets.audio_clip) {
        $audioPath = [string]$scene.assets.audio_clip
      }
    }
    catch { $audioPath = "" }

    $packCompatScenes += [pscustomobject]@{
      id         = [string]$scene.id
      index      = [int](([string]$scene.id -replace '[^\d]',''))
      text       = [string]$scene.text
      narration  = [string]$scene.text
      onscreen   = [string]$scene.text
      audio_text = [string]$scene.text
      image      = $imgPath
      audio      = $audioPath
      start_ms   = [int]$scene.start_ms
      end_ms     = [int]$scene.end_ms
    }
  }

  $packCompat = [pscustomobject]@{
    version = "v03"
    script = [string]$ManifestObj.script
    scenes = $packCompatScenes
    scenes_v03 = $ManifestObj.scenes_v03
    audio_clips = $ManifestObj.audio_clips
    artifacts = [pscustomobject]@{
      image = [string]$ManifestObj.artifacts.image
      audio = [string]$ManifestObj.artifacts.audio
    }
  }

  $packJsonPath = Join-Path $LiveDir "pack.json"
  $utf8NoBomPack = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($packJsonPath, ($packCompat | ConvertTo-Json -Depth 50), $utf8NoBomPack)
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
  -ScriptParts $scriptParts `
  -TotalAudioMs $totalAudioMs `
  -ConfiguredMinScenes $MinScenes `
  -ConfiguredMaxScenes $MaxScenes `
  -SceneTargetSec $TargetSceneSec `
  -SceneMinSec $MinSceneSec `
  -SceneMaxSec $MaxSceneSec

$sceneMode = "audio_fallback"
if (@($scriptParts).Count -gt 0) {
  $sceneMode = "script_driven"
}

$effectiveMinSceneSec = $MinSceneSec
$effectiveMaxSceneSec = $MaxSceneSec

if ($sceneMode -eq "script_driven" -and $desiredScenes -gt 0) {
  $avgSceneSec = [int][Math]::Ceiling($totalAudioMs / [double](1000 * $desiredScenes))
  $scriptAdaptiveMax = [Math]::Max($MaxSceneSec, ($avgSceneSec + 2))

  if ($scriptAdaptiveMax -lt $effectiveMinSceneSec) {
    $scriptAdaptiveMax = $effectiveMinSceneSec
  }

  $effectiveMaxSceneSec = $scriptAdaptiveMax
}
if (-not $Force) {
  if (ScenesHaveValidImages -ManifestObj $m -LiveDir $live -ExpectedCount $desiredScenes) {
    $outSkip = $m | ConvertTo-Json -Depth 50
    $utf8NoBomSkip = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($manifest, $outSkip, $utf8NoBomSkip)

    Sync-PackCompat -ManifestObj $m -LiveDir $live

    if ($AudioClipsChanged) {
      Write-Host "OK: manifest actualizado (audio_clips) antes de SKIP" -ForegroundColor DarkGray
    }
    else {
      Write-Host "OK: manifest preservado antes de SKIP" -ForegroundColor DarkGray
    }

    Write-Host ("OK: pack.json resincronizado desde scenes_v03 antes de SKIP. scenes={0}" -f @($m.scenes_v03).Count) -ForegroundColor DarkGray
    Write-Host ("SKIP: scene_builder v03 (ya hay scenes+images válidos). scenes={0} desired={1} totalAudioMs={2}" -f @($m.scenes_v03).Count, $desiredScenes, $totalAudioMs) -ForegroundColor DarkGray
    exit 0
  }
}

Ensure-Scenes `
  -ManifestObj $m `
  -SceneCount $desiredScenes `
  -TotalAudioMs $totalAudioMs `
  -SceneMinSec $effectiveMinSceneSec `
  -SceneMaxSec $effectiveMaxSceneSec `
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

# Compat legacy para finalize_pack_v03.ps1 / render_pack_v03.py
$legacyScenesDir = Join-Path $live "artifacts\scenes"
if (-not (Test-Path -LiteralPath $legacyScenesDir)) {
  New-Item -ItemType Directory -Force -Path $legacyScenesDir | Out-Null
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

  $legacySceneDir = Join-Path $legacyScenesDir ("scene_{0:d2}" -f ($i + 1))
  if (-not (Test-Path -LiteralPath $legacySceneDir)) {
    New-Item -ItemType Directory -Force -Path $legacySceneDir | Out-Null
  }
  $legacyImgAbs = Join-Path $legacySceneDir "image.png"

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
      Copy-Item -LiteralPath $outAbs -Destination $legacyImgAbs -Force
      $ok = $true
      Write-Host ("OK: scene[{0}] image=PIXABAY -> {1} | legacy={2}" -f $i, $outRel, $legacyImgAbs) -ForegroundColor DarkGray
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

    Copy-Item -LiteralPath $outAbs -Destination $legacyImgAbs -Force

    if ($SkipPixabay) {
      Write-Host ("OK: scene[{0}] image=FALLBACK(SkipPixabay) -> {1} | legacy={2}" -f $i, $outRel, $legacyImgAbs) -ForegroundColor DarkGray
    }
    else {
      Write-Host ("OK: scene[{0}] image=FALLBACK(artifacts.image) -> {1} | legacy={2}" -f $i, $outRel, $legacyImgAbs) -ForegroundColor DarkGray
    }
  }
}

$out = $m | ConvertTo-Json -Depth 50
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifest, $out, $utf8NoBom)

Sync-PackCompat -ManifestObj $m -LiveDir $live
Write-Host ("OK: pack.json resincronizado desde scenes_v03. scenes={0}" -f @($m.scenes_v03).Count) -ForegroundColor DarkGray

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

Write-Host ("OK: scene_builder v03 aplicado. scenes={0} totalAudioMs={1} targetSceneSec={2} minSceneSec={3} maxSceneSec={4} minScenes={5} maxScenes={6} live={7} force={8} skipPixabay={9} skipEnrich={10} mode={11} scriptParts={12} effectiveMinSceneSec={13} effectiveMaxSceneSec={14}" -f @($m.scenes_v03).Count, $totalAudioMs, $TargetSceneSec, $MinSceneSec, $MaxSceneSec, $MinScenes, $MaxScenes, $live, [bool]$Force, [bool]$SkipPixabay, [bool]$SkipEnrich, $sceneMode, @($scriptParts).Count, $effectiveMinSceneSec, $effectiveMaxSceneSec) -ForegroundColor Green
