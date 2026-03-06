param(
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot,
  [Parameter(Mandatory=$false)][string]$PackDir,

  [int]$MinScenes = 4,
  [int]$MaxScenes = 24,
  [int]$TargetSceneSec = 12,

  [int]$Seed = 123,
  [switch]$Force,

  [switch]$SkipPixabay,
  [switch]$SkipEnrich
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
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
    } catch { }
  }

  if ($lastEnd -le 0) { $lastEnd = 20000 }
  return $lastEnd
}

function Get-EffectiveMinScenes {
  param(
    [int]$TotalAudioMs,
    [int]$ConfiguredMinScenes
  )

  if ($TotalAudioMs -lt 45000) { return 2 }
  if ($TotalAudioMs -lt 90000) { return [Math]::Max(3, [Math]::Min($ConfiguredMinScenes, 3)) }
  return [Math]::Max(2, $ConfiguredMinScenes)
}

function Get-DynamicSceneCount {
  param(
    [int]$TotalAudioMs,
    [int]$ConfiguredMinScenes,
    [int]$ConfiguredMaxScenes,
    [int]$SceneTargetSec
  )

  $targetMs = [Math]::Max(5000, ($SceneTargetSec * 1000))
  $raw = [int][Math]::Round($TotalAudioMs / [double]$targetMs)
  if ($raw -lt 1) { $raw = 1 }

  $effectiveMin = Get-EffectiveMinScenes -TotalAudioMs $TotalAudioMs -ConfiguredMinScenes $ConfiguredMinScenes

  $n = $raw
  if ($n -lt $effectiveMin) { $n = $effectiveMin }
  if ($n -gt $ConfiguredMaxScenes) { $n = $ConfiguredMaxScenes }
  if ($n -lt 2) { $n = 2 }

  return $n
}

function Split-ScriptSentences {
  param([string]$Text)

  if (-not $Text) { return @() }

  $t = ($Text -replace "`r`n", "`n" -replace "`r", "`n").Trim()
  if (-not $t) { return @() }

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

function Join-TextParts {
  param([object[]]$Parts)

  $clean = @(
    $Parts |
    ForEach-Object { [string]$_ } |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $_.Length -gt 0 }
  )

  if (@($clean).Count -eq 0) { return "" }
  return (($clean -join " ") -replace '\s+', ' ').Trim()
}

function Build-SceneTexts {
  param(
    [object[]]$Parts,
    [int]$SceneCount
  )

  $partsArr = @(Normalize-ToArray -Value $Parts)
  if ($SceneCount -lt 1) { return @() }
  if (@($partsArr).Count -eq 0) { return @() }

  $out = New-Object System.Collections.Generic.List[string]
  $cursor = 0
  $pCount = @($partsArr).Count

  for ($i = 0; $i -lt $SceneCount; $i++) {
    $remainingScenes = $SceneCount - $i
    $remainingParts = $pCount - $cursor

    if ($remainingParts -le 0) {
      $out.Add("")
      continue
    }

    $take = 1

    if ($i -eq ($SceneCount - 1)) {
      $take = $remainingParts
    }
    elseif ($i -eq 0 -and $remainingParts -ge ($remainingScenes + 1)) {
      $take = 1
    }
    else {
      $take = [int][Math]::Ceiling($remainingParts / [double]$remainingScenes)
      if ($take -lt 1) { $take = 1 }
    }

    if ($take -gt $remainingParts) { $take = $remainingParts }

    $end = $cursor + $take - 1
    $chunk = @($partsArr[$cursor..$end])
    $out.Add((Join-TextParts -Parts $chunk))
    $cursor += $take
  }

  return @($out.ToArray())
}

function Get-AssetPathValue($assetsObj, [string]$key) {
  if (-not $assetsObj) { return "" }

  $prop = $assetsObj.PSObject.Properties[$key]
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

  for ($i=0; $i -lt $ExpectedCount; $i++) {
    $scene = $sc[$i]
    if (-not $scene.assets) { return $false }

    $imgRel = Get-AssetPathValue $scene.assets "image"
    $vidRel = Get-AssetPathValue $scene.assets "video"

    $cand = ""
    if ($imgRel) { $cand = $imgRel } elseif ($vidRel) { $cand = $vidRel }
    if (-not $cand) { return $false }

    $full = $cand
    if (-not [System.IO.Path]::IsPathRooted($cand)) {
      $full = Join-Path $LiveDir ($cand -replace '/', '\')
    }

    if (-not (Test-Path -LiteralPath $full)) { return $false }
  }

  return $true
}

function Ensure-Scenes {
  param(
    $ManifestObj,
    [int]$SceneCount,
    [int]$TotalAudioMs
  )

  $sc = @()
  if ($ManifestObj.scenes_v03) { $sc = @($ManifestObj.scenes_v03) }

  if (@($sc).Count -gt $SceneCount) {
    $sc = @($sc[0..($SceneCount-1)])
  }

  if (@($sc).Count -lt $SceneCount) {
    $slice = [int][Math]::Floor($TotalAudioMs / $SceneCount)
    if ($slice -lt 1000) { $slice = 1000 }

    for ($i = @($sc).Count; $i -lt $SceneCount; $i++) {
      $start = $i * $slice
      $end   = [Math]::Min($TotalAudioMs, (($i + 1) * $slice))
      if ($i -eq ($SceneCount - 1)) { $end = $TotalAudioMs }

      $obj = [pscustomobject]@{
        id       = ("scene_{0:000}" -f ($i+1))
        start_ms = [int]$start
        end_ms   = [int]$end
        text     = ""
        assets   = [pscustomobject]@{
          image = @([pscustomobject]@{ path = "" })
        }
      }

      $sc += $obj
    }
  }

  $slice2 = [int][Math]::Floor($TotalAudioMs / $SceneCount)
  if ($slice2 -lt 1000) { $slice2 = 1000 }

  for ($i = 0; $i -lt $SceneCount; $i++) {
    $start = $i * $slice2
    $end   = [Math]::Min($TotalAudioMs, (($i + 1) * $slice2))
    if ($i -eq ($SceneCount - 1)) { $end = $TotalAudioMs }

    $sceneObj = $sc[$i]

    $sceneObj.start_ms = [int]$start
    $sceneObj.end_ms   = [int]$end

    $hasIdProp = ($sceneObj.PSObject.Properties.Name -contains "id")
    if (-not $hasIdProp) {
      $sceneObj | Add-Member -Force -NotePropertyName id -NotePropertyValue ("scene_{0:000}" -f ($i+1))
    }
    else {
      $idValue = ""
      try { $idValue = [string]$sceneObj.id } catch { $idValue = "" }

      if ([string]::IsNullOrWhiteSpace($idValue)) {
        $sceneObj.id = ("scene_{0:000}" -f ($i+1))
      }
    }

    $hasTextProp = ($sceneObj.PSObject.Properties.Name -contains "text")
    if (-not $hasTextProp) {
      $sceneObj | Add-Member -Force -NotePropertyName text -NotePropertyValue ""
    }

    $hasAssetsProp = ($sceneObj.PSObject.Properties.Name -contains "assets")
    if (-not $hasAssetsProp -or -not $sceneObj.assets) {
      $sceneObj | Add-Member -Force -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{
        image = @([pscustomobject]@{ path = "" })
      })
    }

    $imgCur = $sceneObj.assets.PSObject.Properties["image"]
    if (-not $imgCur -or -not $imgCur.Value) {
      $sceneObj.assets | Add-Member -Force -NotePropertyName "image" -NotePropertyValue @([pscustomobject]@{ path = "" })
    }
    elseif ($imgCur.Value -is [string]) {
      $sceneObj.assets.image = @([pscustomobject]@{ path = [string]$imgCur.Value })
    }
  }

  $ManifestObj.scenes_v03 = @($sc)
}

if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) {
  if (-not $PackDir -or $PackDir.Trim().Length -eq 0) { throw "Falta -WorkspaceRoot o -PackDir" }
  $PackDir = (Resolve-Path $PackDir).Path
  $WorkspaceRoot = (Resolve-Path (Join-Path $PackDir "..\..")).Path
}

$live = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
if (-not (Test-Path -LiteralPath $live)) { throw "No existe LIVE: $live" }

$manifest = Join-Path $live "manifest_v03.json"
if (-not (Test-Path -LiteralPath $manifest)) { throw "Falta manifest_v03.json en LIVE: $manifest" }

$mRaw = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8
$m = $mRaw | ConvertFrom-Json

if (-not $m.scenes_v03) { $m | Add-Member -NotePropertyName scenes_v03 -NotePropertyValue @() }

$AudioClipsChanged = $false
$AudioClipsCreatedFallback = $false

$hasProp = ($m.PSObject.Properties.Name -contains "audio_clips")
$ac = $null
if ($hasProp) { $ac = $m.audio_clips }

$acArr = @(Normalize-ToArray -Value $ac)

if (-not $hasProp -or $null -eq $ac -or @($acArr).Count -eq 0) {
  $acArr = @([pscustomobject]@{ id="clip_001"; start_ms=0; end_ms=20000; text="" })
  $AudioClipsChanged = $true
  $AudioClipsCreatedFallback = $true
} else {
  if (-not (($ac -is [System.Collections.IEnumerable]) -and -not ($ac -is [string]))) {
    $AudioClipsChanged = $true
  }
}

$m | Add-Member -Force -NotePropertyName audio_clips -NotePropertyValue @($acArr)

if ($AudioClipsCreatedFallback) {
  Write-Host "WARN: manifest sin audio_clips -> fallback determinista clip_001 (0..20000ms)" -ForegroundColor DarkYellow
} elseif ($AudioClipsChanged) {
  Write-Host "OK: audio_clips normalizado a array (sin cambiar contenido)" -ForegroundColor DarkGray
}

if (-not $m.artifacts -or -not $m.artifacts.image) {
  throw "manifest sin artifacts.image (fallback requerido): $manifest"
}

$totalAudioMs = Get-TotalAudioMs -AudioClips $m.audio_clips

$scriptText = ""
try {
  if ($m.script) { $scriptText = [string]$m.script }
  elseif ($m.text -and $m.text.script) { $scriptText = [string]$m.text.script }
} catch { $scriptText = "" }

$scriptParts = @(Split-ScriptSentences -Text $scriptText)
$desiredScenes = Get-DynamicSceneCount -TotalAudioMs $totalAudioMs -ConfiguredMinScenes $MinScenes -ConfiguredMaxScenes $MaxScenes -SceneTargetSec $TargetSceneSec

if (-not $Force) {
  if (ScenesHaveValidImages -ManifestObj $m -LiveDir $live -ExpectedCount $desiredScenes) {

    if ($AudioClipsChanged) {
      $out = $m | ConvertTo-Json -Depth 50
      $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
      [System.IO.File]::WriteAllText($manifest, $out, $utf8NoBom)
      Write-Host "OK: manifest actualizado (solo audio_clips) antes de SKIP" -ForegroundColor DarkGray
    }

    Write-Host "SKIP: scene_builder v03 (ya hay scenes+images válidos). scenes=$(@($m.scenes_v03).Count) desired=$desiredScenes totalAudioMs=$totalAudioMs" -ForegroundColor DarkGray
    exit 0
  }
}

Ensure-Scenes -ManifestObj $m -SceneCount $desiredScenes -TotalAudioMs $totalAudioMs

if (@($scriptParts).Count -gt 0) {
  $sceneTexts = @(Build-SceneTexts -Parts $scriptParts -SceneCount @($m.scenes_v03).Count)

  for ($i = 0; $i -lt @($m.scenes_v03).Count; $i++) {
    $txt = ""
    if ($i -lt @($sceneTexts).Count) { $txt = [string]$sceneTexts[$i] }
    $m.scenes_v03[$i].text = $txt.Trim()
  }
}

$cacheDir = Join-Path $live "cache_v03"
if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }

$pixQuery = Join-Path $repo "tools\stock_query_pixabay_v03.ps1"
$dlTool   = Join-Path $repo "tools\download_file_v03.ps1"

$assetsDir = Join-Path $live "assets\scenes_v03"
if (-not (Test-Path -LiteralPath $assetsDir)) { New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null }

$fallbackRel = [string]$m.artifacts.image
$fallbackAbs = (Resolve-Path (Join-Path $live ($fallbackRel -replace '/', '\'))).Path

for ($i=0; $i -lt @($m.scenes_v03).Count; $i++) {
  $scene = $m.scenes_v03[$i]

  if (-not $scene.assets) {
    $scene | Add-Member -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{
      image = @([pscustomobject]@{ path = "" })
    }) -Force
  }

  $imgCur = $scene.assets.PSObject.Properties["image"]
  if (-not $imgCur -or -not $imgCur.Value) {
    $scene.assets | Add-Member -Force -NotePropertyName "image" -NotePropertyValue @([pscustomobject]@{ path = "" })
  }
  elseif ($imgCur.Value -is [string]) {
    $scene.assets.image = @([pscustomobject]@{ path = [string]$imgCur.Value })
  }

  $outName = ("scene_{0:000}.jpg" -f ($i+1))
  $outAbs  = Join-Path $assetsDir $outName
  $outRel  = ("assets/scenes_v03/{0}" -f $outName)

  $q = [string]$scene.text
  if (-not $q -or $q.Trim().Length -lt 3) { $q = "motivación" }
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
  $cacheJson = Join-Path $cacheDir ("pixabay_scene_{0:000}.json" -f ($i+1))

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
    } catch {
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
      Write-Host "OK: scene[$i] image=PIXABAY -> $outRel" -ForegroundColor DarkGray
    } catch {
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
      Write-Host "OK: scene[$i] image=FALLBACK(SkipPixabay) -> $outRel" -ForegroundColor DarkGray
    } else {
      Write-Host "OK: scene[$i] image=FALLBACK(artifacts.image) -> $outRel" -ForegroundColor DarkGray
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

        Write-Host "OK: enrich_scenes_queries_v03 aplicado (workspace=$WorkspaceRoot manifest=$manifestGuess)" -ForegroundColor DarkGray
      }
      else {
        Write-Host "WARN: no encontré manifest_v03.json para enriquecer queries" -ForegroundColor Yellow
      }
    }
    else {
      Write-Host "WARN: falta tool enrich_scenes_queries_v03.ps1 (skip)" -ForegroundColor Yellow
    }
  } catch {
    Write-Host ("WARN: enrich_scenes_queries_v03 falló (skip): {0}" -f $_.Exception.Message) -ForegroundColor Yellow
  }
}
else {
  Write-Host "SKIP: enrich_scenes_queries_v03 (SkipEnrich=True)" -ForegroundColor DarkGray
}

Write-Host ("OK: scene_builder v03 aplicado. scenes={0} totalAudioMs={1} targetSceneSec={2} minScenes={3} maxScenes={4} live={5} force={6} skipPixabay={7} skipEnrich={8}" -f @($m.scenes_v03).Count, $totalAudioMs, $TargetSceneSec, $MinScenes, $MaxScenes, $live, [bool]$Force, [bool]$SkipPixabay, [bool]$SkipEnrich) -ForegroundColor Green