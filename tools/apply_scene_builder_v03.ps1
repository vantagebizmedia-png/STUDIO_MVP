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

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Normalize-ToArray {
  param($Value)

  if ($null -eq $Value) { return @() }

  if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
    return @($Value)
  }

  return @($Value)
}

function Resolve-CanonicalPath {
  param(
    [string]$PathValue,
    [string]$Label
  )

  if ([string]::IsNullOrWhiteSpace($PathValue)) { return "" }

  if (-not (Test-Path -LiteralPath $PathValue)) {
    throw ("No existe {0}: {1}" -f $Label, $PathValue)
  }

  return (Resolve-Path -LiteralPath $PathValue).Path
}

function Test-IsLivePackDir {
  param([string]$DirPath)

  if ([string]::IsNullOrWhiteSpace($DirPath)) { return $false }

  $manifestCandidate = Join-Path $DirPath "manifest_v03.json"
  return (Test-Path -LiteralPath $manifestCandidate)
}

function Get-WorkspaceRootFromLiveDir {
  param([string]$LiveDir)

  if ([string]::IsNullOrWhiteSpace($LiveDir)) { return "" }

  try {
    $livePath = (Resolve-Path -LiteralPath $LiveDir).Path
    $parentDir = Split-Path $livePath -Parent
    if ([string]::IsNullOrWhiteSpace($parentDir)) { return "" }

    $parentLeaf = Split-Path $parentDir -Leaf
    if ($parentLeaf -ine "runs") { return "" }

    $workspaceDir = Split-Path $parentDir -Parent
    if ([string]::IsNullOrWhiteSpace($workspaceDir)) { return "" }
    if (-not (Test-Path -LiteralPath $workspaceDir)) { return "" }

    return (Resolve-Path -LiteralPath $workspaceDir).Path
  }
  catch {
    return ""
  }
}

function Resolve-LiveContext {
  param(
    [string]$WorkspaceRootValue,
    [string]$PackDirValue
  )

  if ([string]::IsNullOrWhiteSpace($WorkspaceRootValue) -and [string]::IsNullOrWhiteSpace($PackDirValue)) {
    throw "Falta -WorkspaceRoot o -PackDir"
  }

  $resolvedWorkspace = ""
  $resolvedPack = ""
  $resolvedLive = ""

  if (-not [string]::IsNullOrWhiteSpace($PackDirValue)) {
    $packCandidate = Resolve-CanonicalPath -PathValue $PackDirValue -Label "PackDir"

    if (Test-IsLivePackDir -DirPath $packCandidate) {
      $resolvedPack = $packCandidate
      $resolvedLive = $packCandidate
    }
    else {
      $packCandidateLive = Join-Path $packCandidate "runs\smoke_live_latest"
      if (Test-IsLivePackDir -DirPath $packCandidateLive) {
        $resolvedWorkspace = $packCandidate
        $resolvedPack = (Resolve-Path -LiteralPath $packCandidateLive).Path
        $resolvedLive = $resolvedPack
      }
      else {
        throw ("PackDir no apunta a un LIVE valido ni a un workspace con runs\smoke_live_latest: {0}" -f $packCandidate)
      }
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($WorkspaceRootValue)) {
    $workspaceCandidate = Resolve-CanonicalPath -PathValue $WorkspaceRootValue -Label "WorkspaceRoot"
    $workspaceProvidedLive = ""

    if (Test-IsLivePackDir -DirPath $workspaceCandidate) {
      $workspaceProvidedLive = $workspaceCandidate
    }
    else {
      $workspaceCandidateLive = Join-Path $workspaceCandidate "runs\smoke_live_latest"
      if (Test-IsLivePackDir -DirPath $workspaceCandidateLive) {
        $workspaceProvidedLive = (Resolve-Path -LiteralPath $workspaceCandidateLive).Path
      }
      else {
        throw ("WorkspaceRoot no contiene un LIVE valido: {0}" -f $workspaceCandidate)
      }
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedLive)) {
      if (-not $resolvedLive.Equals($workspaceProvidedLive, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("WorkspaceRoot y PackDir apuntan a LIVE distintos. WorkspaceRoot='{0}' PackDir='{1}'" -f $workspaceProvidedLive, $resolvedLive)
      }
    }
    else {
      $resolvedLive = $workspaceProvidedLive
      if ([string]::IsNullOrWhiteSpace($resolvedPack)) {
        $resolvedPack = $workspaceProvidedLive
      }
    }

    if (-not (Test-IsLivePackDir -DirPath $workspaceCandidate)) {
      $resolvedWorkspace = $workspaceCandidate
    }
    elseif ([string]::IsNullOrWhiteSpace($resolvedWorkspace)) {
      $resolvedWorkspace = Get-WorkspaceRootFromLiveDir -LiveDir $workspaceProvidedLive
    }
  }

  if ([string]::IsNullOrWhiteSpace($resolvedLive)) {
    throw "No se pudo resolver LiveDir"
  }

  if ([string]::IsNullOrWhiteSpace($resolvedPack)) {
    $resolvedPack = $resolvedLive
  }

  if ([string]::IsNullOrWhiteSpace($resolvedWorkspace)) {
    $resolvedWorkspace = Get-WorkspaceRootFromLiveDir -LiveDir $resolvedLive
  }

  return [pscustomobject]@{
    WorkspaceRoot = $resolvedWorkspace
    PackDir       = $resolvedPack
    LiveDir       = $resolvedLive
  }
}

function Get-PixabaySafeQuery {
  param(
    [string]$Text,
    [int]$MaxChars = 100
  )

  $fallback = "motivacion"
  if ([string]::IsNullOrWhiteSpace($Text)) { return $fallback }

  $q = $Text.Trim().ToLowerInvariant()
  $q = $q -replace '[\r\n\t]+', ' '
  $q = $q -replace '[^a-zA-Z0-9áéíóúüñÁÉÍÓÚÜÑ ]+', ' '
  $q = $q -replace '\s+', ' '
  $q = $q.Trim()

  if ([string]::IsNullOrWhiteSpace($q)) { return $fallback }

  $stop = @(
    "el","la","los","las","un","una","unos","unas",
    "de","del","al","y","o","u","que","se","su","sus",
    "por","para","con","sin","en","a","desde","hasta",
    "como","más","mas","muy","ya","no","sí","si",
    "the","a","an","and","or","of","to","for","with","in","on"
  )

  $words = @(
    $q -split '\s+' |
    Where-Object { $_ -and $_.Length -ge 3 -and ($stop -notcontains $_) }
  )

  if (@($words).Count -eq 0) { return $fallback }

  $selected = New-Object System.Collections.Generic.List[string]
  foreach ($w in $words) {
    if ($selected.Count -ge 8) { break }
    if (-not $selected.Contains($w)) {
      $selected.Add($w)
    }
  }

  $short = ($selected -join ' ').Trim()
  if ([string]::IsNullOrWhiteSpace($short)) { $short = $fallback }

  if ($short.Length -gt $MaxChars) {
    $short = $short.Substring(0, $MaxChars)
    $short = $short -replace '\s+\S*$', ''
    $short = $short.Trim()
  }

  if ([string]::IsNullOrWhiteSpace($short)) { return $fallback }
  return $short
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
        id                 = ("scene_{0:000}" -f ($i + 1))
        start_ms           = 0
        end_ms             = 0
        duration_ms        = 0
        text               = ""
        script_text        = ""
        image_query        = ""
        visual_kind        = "image"
        visual_source_kind = "fallback_image"
        visual_capability  = "stock_image"
        assets             = [pscustomobject]@{
          audio_clip = ""
          image      = ""
          video      = ""
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

    $sceneObj | Add-Member -Force -NotePropertyName id -NotePropertyValue ("scene_{0:000}" -f ($i + 1))

    if (-not ($sceneObj.PSObject.Properties.Name -contains "text")) {
      $sceneObj | Add-Member -Force -NotePropertyName text -NotePropertyValue ""
    }

    if (-not ($sceneObj.PSObject.Properties.Name -contains "script_text")) {
      $sceneObj | Add-Member -Force -NotePropertyName script_text -NotePropertyValue ""
    }

    if (-not ($sceneObj.PSObject.Properties.Name -contains "image_query")) {
      $sceneObj | Add-Member -Force -NotePropertyName image_query -NotePropertyValue ""
    }

    if (-not ($sceneObj.PSObject.Properties.Name -contains "assets") -or -not $sceneObj.assets) {
      $sceneObj | Add-Member -Force -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{
        audio_clip = ""
        image      = ""
        video      = ""
      })
    }

    if (-not ($sceneObj.assets.PSObject.Properties.Name -contains "audio_clip")) {
      $sceneObj.assets | Add-Member -Force -NotePropertyName audio_clip -NotePropertyValue ""
    }

    if (-not ($sceneObj.assets.PSObject.Properties.Name -contains "image")) {
      $sceneObj.assets | Add-Member -Force -NotePropertyName image -NotePropertyValue ""
    }
    elseif ($sceneObj.assets.image -isnot [string]) {
      $sceneObj.assets.image = [string](Get-AssetPathValue -AssetsObj $sceneObj.assets -Key "image")
    }

    if (-not ($sceneObj.assets.PSObject.Properties.Name -contains "video")) {
      $sceneObj.assets | Add-Member -Force -NotePropertyName video -NotePropertyValue ""
    }
    elseif ($sceneObj.assets.video -isnot [string]) {
      $sceneObj.assets.video = [string](Get-AssetPathValue -AssetsObj $sceneObj.assets -Key "video")
    }

    $vk = "image"
    if (-not [string]::IsNullOrWhiteSpace([string]$sceneObj.assets.video) -and [string]::IsNullOrWhiteSpace([string]$sceneObj.assets.image)) {
      $vk = "video"
    }

    $sceneObj | Add-Member -Force -NotePropertyName visual_kind -NotePropertyValue $vk
    $sceneObj | Add-Member -Force -NotePropertyName visual_source_kind -NotePropertyValue $(if ($vk -eq "video") { "stock_video" } else { "stock_image" })
    $sceneObj | Add-Member -Force -NotePropertyName visual_capability -NotePropertyValue $(if ($vk -eq "video") { "stock_video" } else { "stock_image" })

    $sceneObj | Add-Member -Force -NotePropertyName start_ms -NotePropertyValue ([int]$st)
    $sceneObj | Add-Member -Force -NotePropertyName end_ms -NotePropertyValue ([int]$en)
    $sceneObj | Add-Member -Force -NotePropertyName duration_ms -NotePropertyValue ([int]($en - $st))

    $sceneObj.assets.audio_clip = ("artifacts/audio_s{0:d2}.wav" -f ($i + 1))
  }

  $ManifestObj.scenes_v03 = @($sc)
}

function Ensure-VisualCapabilityFields {
  param(
    [Parameter(Mandatory=$true)]$ManifestObj
  )

  $scenes = @($ManifestObj.scenes_v03)
  foreach ($scene in $scenes) {
    if (-not $scene) { continue }

    if (-not ($scene.PSObject.Properties.Name -contains "assets") -or -not $scene.assets) {
      $scene | Add-Member -Force -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{
        audio_clip = ""
        image      = ""
        video      = ""
      })
    }

    if (-not ($scene.assets.PSObject.Properties.Name -contains "video")) {
      $scene.assets | Add-Member -Force -NotePropertyName video -NotePropertyValue ""
    }
    elseif ($scene.assets.video -isnot [string]) {
      try {
        $scene.assets.video = [string]$scene.assets.video
      }
      catch {
        $scene.assets.video = ""
      }
    }

    if (-not ($scene.assets.PSObject.Properties.Name -contains "image")) {
      $scene.assets | Add-Member -Force -NotePropertyName image -NotePropertyValue ""
    }
    elseif ($scene.assets.image -isnot [string]) {
      try {
        $scene.assets.image = [string]$scene.assets.image
      }
      catch {
        $scene.assets.image = ""
      }
    }

    $vk = ""
    if ($scene.PSObject.Properties.Name -contains "visual_kind") {
      try { $vk = ([string]$scene.visual_kind).Trim().ToLowerInvariant() } catch { $vk = "" }
    }

    if ($vk -notin @("image","video")) {
      if (-not [string]::IsNullOrWhiteSpace([string]$scene.assets.video) -and [string]::IsNullOrWhiteSpace([string]$scene.assets.image)) {
        $vk = "video"
      }
      else {
        $vk = "image"
      }
    }

    $scene | Add-Member -Force -NotePropertyName visual_kind -NotePropertyValue $vk
    $scene | Add-Member -Force -NotePropertyName visual_source_kind -NotePropertyValue $(if ($vk -eq "video") { "stock_video" } else { "stock_image" })
    $scene | Add-Member -Force -NotePropertyName visual_capability -NotePropertyValue $(if ($vk -eq "video") { "stock_video" } else { "stock_image" })
  }

  $ManifestObj.scenes_v03 = @($scenes)
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
          if ($firstImg -is [string]) {
            $imgPath = [string]$firstImg
          }
          elseif ($firstImg -and $firstImg.PSObject.Properties["path"] -and $firstImg.path) {
            $imgPath = [string]$firstImg.path
          }
        }
        elseif ($scene.assets.image -is [string]) {
          $imgPath = [string]$scene.assets.image
        }
        else {
          $imgPath = [string](Get-AssetPathValue -AssetsObj $scene.assets -Key "image")
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

    $sceneId = ""
    try { $sceneId = [string]$scene.id } catch { $sceneId = "" }

    $sceneText = ""
    try { $sceneText = [string]$scene.text } catch { $sceneText = "" }

    $sceneStart = 0
    try { $sceneStart = [int]$scene.start_ms } catch { $sceneStart = 0 }

    $sceneEnd = 0
    try { $sceneEnd = [int]$scene.end_ms } catch { $sceneEnd = 0 }

    $packCompatScenes += [pscustomobject]@{
      id         = $sceneId
      index      = [int](($sceneId -replace '[^\d]',''))
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
    if ($ManifestObj.PSObject.Properties["script"] -and $ManifestObj.script) {
      $manifestScript = [string]$ManifestObj.script
    }
    elseif ($ManifestObj.PSObject.Properties["text"] -and $ManifestObj.text) {
      if ($ManifestObj.text -is [string]) {
        $manifestScript = [string]$ManifestObj.text
      }
      elseif ($ManifestObj.text.PSObject.Properties["script"] -and $ManifestObj.text.script) {
        $manifestScript = [string]$ManifestObj.text.script
      }
    }

    if ([string]::IsNullOrWhiteSpace($manifestScript)) {
      $parts = @()
      foreach ($scene in @($ManifestObj.scenes_v03)) {
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
    if ($ManifestObj.PSObject.Properties["artifacts"] -and $ManifestObj.artifacts) {
      if ($ManifestObj.artifacts.PSObject.Properties["image"] -and $ManifestObj.artifacts.image) {
        $artifactImage = [string]$ManifestObj.artifacts.image
      }

      if ($ManifestObj.artifacts.PSObject.Properties["audio"] -and $ManifestObj.artifacts.audio) {
        $artifactAudio = [string]$ManifestObj.artifacts.audio
      }
    }
  }
  catch {
    $artifactImage = ""
    $artifactAudio = ""
  }

  $totalAudioMs = 0
  $sceneBuilderMaxScenes = @($ManifestObj.scenes_v03).Count
  $sceneBuilderNote = "synced_by_apply_scene_builder_v03_packcompat"

  try {
    if ($ManifestObj.PSObject.Properties["scene_builder_v03"] -and $ManifestObj.scene_builder_v03) {
      $sb = $ManifestObj.scene_builder_v03

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
      if ($ManifestObj.PSObject.Properties["total_audio_ms"] -and $null -ne $ManifestObj.total_audio_ms) {
        $totalAudioMs = [int]$ManifestObj.total_audio_ms
      }
    }
    catch { $totalAudioMs = 0 }
  }

  if ($totalAudioMs -le 0) {
    foreach ($scene in @($ManifestObj.scenes_v03)) {
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

  $packCompat = [pscustomobject]@{
    version = "v03"
    total_audio_ms = [int]$totalAudioMs
    script = $manifestScript
    scenes = $packCompatScenes
    scenes_v03 = $ManifestObj.scenes_v03
    audio_clips = $ManifestObj.audio_clips
    artifacts = [pscustomobject]@{
      image = $artifactImage
      audio = $artifactAudio
    }
    scene_builder_v03 = $sceneBuilderMeta
  }

  $packJsonPath = Join-Path $LiveDir "pack.json"
  $utf8BomPack = [System.Text.UTF8Encoding]::new($true)
  [System.IO.File]::WriteAllText($packJsonPath, ($packCompat | ConvertTo-Json -Depth 50), $utf8BomPack)
}
$liveForCompat = ""

try {
  if (Get-Variable -Name live -ErrorAction SilentlyContinue) {
    $liveForCompat = [string]$live
  }
}
catch { $liveForCompat = "" }

if ([string]::IsNullOrWhiteSpace($liveForCompat)) {
  try {
    if (Get-Variable -Name PackDir -ErrorAction SilentlyContinue) {
      if (-not [string]::IsNullOrWhiteSpace([string]$PackDir)) {
        $liveForCompat = [string]$PackDir
      }
    }
  }
  catch { $liveForCompat = "" }
}

if ([string]::IsNullOrWhiteSpace($liveForCompat)) {
  try {
    if (Get-Variable -Name WorkspaceRoot -ErrorAction SilentlyContinue) {
      if (-not [string]::IsNullOrWhiteSpace([string]$WorkspaceRoot)) {
        $liveForCompat = Join-Path ([string]$WorkspaceRoot) "runs\smoke_live_latest"
      }
    }
  }
  catch { $liveForCompat = "" }
}

if (-not [string]::IsNullOrWhiteSpace($liveForCompat)) {
  $manifestCompatPath = Join-Path $liveForCompat "manifest_v03.json"
  if (Test-Path -LiteralPath $manifestCompatPath) {
    $manifestCompatObj = Get-Content -LiteralPath $manifestCompatPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Ensure-VisualCapabilityFields -ManifestObj $manifestCompatObj

    $utf8NoBomManifest = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($manifestCompatPath, ($manifestCompatObj | ConvertTo-Json -Depth 50), $utf8NoBomManifest)

    Sync-PackCompat -ManifestObj $manifestCompatObj -LiveDir $liveForCompat
  }
}

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

$liveForLog = ""

try {
  if (Get-Variable -Name live -ErrorAction SilentlyContinue) {
    $liveForLog = [string]$live
  }
}
catch { $liveForLog = "" }

if ([string]::IsNullOrWhiteSpace($liveForLog)) {
  try {
    if (Get-Variable -Name PackDir -ErrorAction SilentlyContinue) {
      if (-not [string]::IsNullOrWhiteSpace([string]$PackDir)) {
        $liveForLog = [string]$PackDir
      }
    }
  }
  catch { $liveForLog = "" }
}

if ([string]::IsNullOrWhiteSpace($liveForLog)) {
  try {
    if (Get-Variable -Name WorkspaceRoot -ErrorAction SilentlyContinue) {
      if (-not [string]::IsNullOrWhiteSpace([string]$WorkspaceRoot)) {
        $liveForLog = Join-Path ([string]$WorkspaceRoot) "runs\smoke_live_latest"
      }
    }
  }
  catch { $liveForLog = "" }
}

$finalSceneCount = 0
try {
  if (-not [string]::IsNullOrWhiteSpace($liveForLog)) {
    $manifestFinalPath = Join-Path $liveForLog "manifest_v03.json"
    if (Test-Path -LiteralPath $manifestFinalPath) {
      $manifestFinalObj = Get-Content -LiteralPath $manifestFinalPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $finalSceneCount = @($manifestFinalObj.scenes_v03).Count
    }
  }
}
catch {
  $finalSceneCount = 0
}

Write-Host ("OK: scene_builder v03 aplicado. scenes={0} live={1}" -f $finalSceneCount, $liveForLog) -ForegroundColor Green

