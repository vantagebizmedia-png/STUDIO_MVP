param(
  [Parameter(Mandatory=$true)][string]$LiveDir,
  [int]$MaxScenes = 40,
  [int]$TimeToleranceMs = 350
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$psUtf8Compat = Join-Path $PSScriptRoot "ps_utf8_compat_v03.ps1"
if (-not (Test-Path -LiteralPath $psUtf8Compat -PathType Leaf)) {
  throw ("No existe helper utf8 compat: {0}" -f $psUtf8Compat)
}

. $psUtf8Compat

function Fail([string]$msg) { throw "SMOKE FAIL: $msg" }

function Has-Prop {
  param(
    [Parameter(Mandatory=$false)]$Obj,
    [Parameter(Mandatory=$true)][string]$Name
  )

  if ($null -eq $Obj) { return $false }
  return ($Obj.PSObject.Properties.Name -contains $Name)
}

function Get-PropValue {
  param(
    [Parameter(Mandatory=$false)]$Obj,
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$false)]$Default = $null
  )

  if ($null -eq $Obj) { return $Default }
  if (Has-Prop -Obj $Obj -Name $Name) { return $Obj.$Name }
  return $Default
}

function Get-IntOrDefault {
  param(
    [Parameter(Mandatory=$false)]$Value,
    [Parameter(Mandatory=$false)][int]$Default = 0
  )

  try { return [int]$Value } catch { return $Default }
}

function Get-StringOrEmpty {
  param([Parameter(Mandatory=$false)]$Value)

  try {
    if ($null -eq $Value) { return "" }
    return [string]$Value
  }
  catch {
    return ""
  }
}

function Normalize-TextForCompare {
  param([Parameter(Mandatory=$true)][string]$Text)

  return (($Text -replace "`r`n", "`n") -replace "`r", "`n").Trim()
}

function Convert-SrtTimeToMs {
  param([Parameter(Mandatory=$true)][string]$Value)

  if ($Value -notmatch '^(?<hh>\d{2}):(?<mm>\d{2}):(?<ss>\d{2}),(?<ms>\d{3})$') {
    Fail "timestamp SRT inválido: '$Value'"
  }

  return (
    ([int]$Matches.hh * 3600000) +
    ([int]$Matches.mm * 60000) +
    ([int]$Matches.ss * 1000) +
    ([int]$Matches.ms)
  )
}

function Parse-SrtEntries {
  param([Parameter(Mandatory=$true)][string]$Text)

  $normalized = Normalize-TextForCompare -Text $Text
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    Fail "captions_v03.srt está vacío"
  }

  $blocks = [regex]::Split($normalized, "\n{2,}") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  $entries = @()

  foreach ($block in $blocks) {
    $lines = @(($block -split "`n"))
    if ($lines.Count -lt 2) {
      Fail "bloque SRT inválido: '$block'"
    }

    $timeLine = ([string]$lines[1]).Trim()
    if ($timeLine -notmatch '^(?<start>\d{2}:\d{2}:\d{2},\d{3})\s+-->\s+(?<end>\d{2}:\d{2}:\d{2},\d{3})$') {
      Fail "línea de tiempo SRT inválida: '$timeLine'"
    }

    $startMs = Convert-SrtTimeToMs -Value $Matches.start
    $endMs   = Convert-SrtTimeToMs -Value $Matches.end
    $body    = (($lines | Select-Object -Skip 2) -join "`n").Trim()

    if ($endMs -le $startMs) {
      Fail "bloque SRT con end <= start: '$timeLine'"
    }

    $entries += [pscustomobject]@{
      ordinal  = [int]($entries.Count + 1)
      start_ms = [int]$startMs
      end_ms   = [int]$endMs
      text     = [string]$body
    }
  }

  return @($entries)
}

function Get-ExpectedSceneTimeline {
  param([Parameter(Mandatory=$true)][object[]]$Scenes)

  $rows = @()
  $cursorMs = 0

  for ($i = 0; $i -lt $Scenes.Count; $i++) {
    $scene = $Scenes[$i]
    $ord = $i + 1

    $sceneId = Get-StringOrEmpty -Value (Get-PropValue -Obj $scene -Name "id" -Default ("scene_{0:000}" -f $ord))
    if ([string]::IsNullOrWhiteSpace($sceneId)) {
      $sceneId = ("scene_{0:000}" -f $ord)
    }

    $hasStart = Has-Prop -Obj $scene -Name "start_ms"
    $hasEnd   = Has-Prop -Obj $scene -Name "end_ms"
    $hasDur   = Has-Prop -Obj $scene -Name "duration_ms"

    $startMs = Get-IntOrDefault -Value (Get-PropValue -Obj $scene -Name "start_ms" -Default 0) -Default 0
    $endMs   = Get-IntOrDefault -Value (Get-PropValue -Obj $scene -Name "end_ms" -Default 0) -Default 0
    $durMs   = Get-IntOrDefault -Value (Get-PropValue -Obj $scene -Name "duration_ms" -Default 0) -Default 0

    if ($hasStart -and $hasEnd -and ($endMs -gt $startMs)) {
      if ($startMs -lt $cursorMs) {
        Fail "$sceneId tiene timing no monótono: start_ms=$startMs cursor_ms=$cursorMs"
      }
    }
    elseif ($hasDur -and ($durMs -gt 0)) {
      $startMs = [int]$cursorMs
      $endMs   = [int]($startMs + $durMs)
    }
    else {
      Fail "$sceneId no tiene timing utilizable para contrastar SRT"
    }

    if ($endMs -le $startMs) {
      Fail "$sceneId tiene timing inválido: ${startMs}..${endMs}"
    }

    $rows += [pscustomobject]@{
      ordinal  = [int]$ord
      id       = [string]$sceneId
      start_ms = [int]$startMs
      end_ms   = [int]$endMs
    }

    $cursorMs = [int]$endMs
  }

  return @($rows)
}

$live = (Resolve-Path $LiveDir).Path

$manifestPath = Join-Path $live "manifest_v03.json"
$captionsV03  = Join-Path $live "captions_v03.srt"
$legacySrt    = Join-Path $live "subtitles.srt"
$videoSubs    = Join-Path $live "video_subs.mp4"

if (-not (Test-Path -LiteralPath $manifestPath)) {
  Fail "Falta manifest_v03.json: $manifestPath"
}

if (-not (Test-Path -LiteralPath $captionsV03)) {
  Fail "Falta output LIVE requerido: $captionsV03"
}

if (-not (Test-Path -LiteralPath $videoSubs)) {
  Fail "Falta output LIVE requerido: $videoSubs"
}

$captionsItem = Get-Item -LiteralPath $captionsV03
if ($captionsItem.PSIsContainer -or $captionsItem.Length -le 0) {
  Fail "captions_v03.srt inválido o vacío: $captionsV03"
}

$videoSubsItem = Get-Item -LiteralPath $videoSubs
if ($videoSubsItem.PSIsContainer -or $videoSubsItem.Length -le 0) {
  Fail "video_subs.mp4 inválido o vacío: $videoSubs"
}

if (Test-Path -LiteralPath $legacySrt) {
  $legacyItem = Get-Item -LiteralPath $legacySrt
  if ($legacyItem.PSIsContainer -or $legacyItem.Length -le 0) {
    Fail "subtitles.srt legacy inválido o vacío: $legacySrt"
  }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

$sceneSource = ""
$scenes = @()

if ((Has-Prop -Obj $manifest -Name "scenes_v03") -and $manifest.scenes_v03) {
  $sceneSource = "scenes_v03"
  $scenes = @($manifest.scenes_v03)
}
elseif ((Has-Prop -Obj $manifest -Name "scenes") -and $manifest.scenes) {
  $sceneSource = "scenes"
  $scenes = @($manifest.scenes)
}
else {
  Fail "El manifest no contiene scenes_v03 ni scenes"
}

if ($scenes.Count -le 0) {
  Fail "El manifest no contiene escenas"
}

if ($scenes.Count -gt $MaxScenes) {
  Fail "Cantidad de escenas excede MaxScenes. scenes=$($scenes.Count) max=$MaxScenes"
}

$captionsText = Get-Content -LiteralPath $captionsV03 -Raw -Encoding UTF8
$srtEntries   = @(Parse-SrtEntries -Text $captionsText)

if ($srtEntries.Count -ne $scenes.Count) {
  Fail "captions_v03.srt blocks=$($srtEntries.Count) != $sceneSource=$($scenes.Count)"
}

$expectedTimeline = @(Get-ExpectedSceneTimeline -Scenes $scenes)

if ($expectedTimeline.Count -ne $scenes.Count) {
  Fail "timeline esperado=$($expectedTimeline.Count) != escenas=$($scenes.Count)"
}

for ($i = 0; $i -lt $expectedTimeline.Count; $i++) {
  $expected = $expectedTimeline[$i]
  $actual   = $srtEntries[$i]

  $startDelta = [Math]::Abs(([int]$actual.start_ms) - ([int]$expected.start_ms))
  $endDelta   = [Math]::Abs(([int]$actual.end_ms) - ([int]$expected.end_ms))

  if ($startDelta -gt $TimeToleranceMs) {
    Fail "$($expected.id) start mismatch: srt=$($actual.start_ms) manifest=$($expected.start_ms) delta=$startDelta tolerance=$TimeToleranceMs"
  }

  if ($endDelta -gt $TimeToleranceMs) {
    Fail "$($expected.id) end mismatch: srt=$($actual.end_ms) manifest=$($expected.end_ms) delta=$endDelta tolerance=$TimeToleranceMs"
  }

  if ([string]::IsNullOrWhiteSpace([string]$actual.text)) {
    Fail "$($expected.id) bloque SRT vacío"
  }
}

if (Test-Path -LiteralPath $legacySrt) {
  $legacyText = Get-Content -LiteralPath $legacySrt -Raw -Encoding UTF8
  if ((Normalize-TextForCompare -Text $legacyText) -ne (Normalize-TextForCompare -Text $captionsText)) {
    Fail "subtitles.srt no está sincronizado exactamente con captions_v03.srt"
  }
}

Write-Host ("SMOKE OK: LIVE subtitles alineados con {0}. live={1} scenes={2} tolerance_ms={3}" -f $sceneSource, $live, $scenes.Count, $TimeToleranceMs) -ForegroundColor Green
