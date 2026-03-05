param(
  [Parameter(Mandatory=$true)][string]$ManifestPath,
  [Parameter(Mandatory=$true)][string]$OutSrtPath,
  [int]$MaxCharsPerLine = 42,
  [int]$MaxLines = 2,
  [switch]$AllowPlaceholderText
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

function Has-Prop($obj, [string]$name) {
  if ($null -eq $obj) { return $false }
  return ($obj.PSObject.Properties.Name -contains $name)
}
function Get-Prop($obj, [string]$name, $default) {
  if (Has-Prop $obj $name) { return $obj.$name }
  return $default
}
function Format-SrtTime([int]$ms) {
  if ($ms -lt 0) { $ms = 0 }
  $ts = [TimeSpan]::FromMilliseconds($ms)
  "{0:00}:{1:00}:{2:00},{3:000}" -f $ts.Hours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds
}
function Wrap-Text([string]$t, [int]$maxChars, [int]$maxLines) {
  $t = ($t ?? "").ToString().Trim()
  if (-not $t) { return @() }

  $t = ($t -replace "\s+", " ").Trim()
  $words = $t.Split(" ")
  $lines = New-Object System.Collections.Generic.List[string]
  $cur = ""

  foreach ($w in $words) {
    if (-not $cur) { $cur = $w; continue }
    if (($cur.Length + 1 + $w.Length) -le $maxChars) {
      $cur = "$cur $w"
    } else {
      $lines.Add($cur)
      $cur = $w
      if ($lines.Count -ge $maxLines) { break }
    }
  }

  if ($lines.Count -lt $maxLines -and $cur) { $lines.Add($cur) }
  if ($lines.Count -gt $maxLines) { $lines = $lines.GetRange(0,$maxLines) }
  return $lines.ToArray()
}
function Is-PlaceholderSceneText([string]$t) {
  $t = ($t ?? "").ToString().Trim()
  if (-not $t) { return $true }
  return ($t -match '(?i)^(escena)\s*\d+\s*$')
}

if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "No existe ManifestPath: $ManifestPath" }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $manifest.scenes_v03) { throw "manifest no tiene scenes_v03[]" }

$scenes = @($manifest.scenes_v03)
$N = $scenes.Count
if ($N -le 0) { throw "scenes_v03 vacío" }

# audio_clips (robusto): nunca accedas directo a $manifest.audio_clips en StrictMode
$clips = @()

$clipsRaw = Get-Prop $manifest "audio_clips" $null

if ($null -ne $clipsRaw) {
  if ($clipsRaw -is [System.Collections.IDictionary]) {
    $clips = @($clipsRaw.Values)
  }
  elseif ($clipsRaw -is [System.Array]) {
    $clips = @($clipsRaw)
  }
  else {
    $clips = @($clipsRaw)
  }
}

# timeline base (si hay 1 clip). Si no hay, usa total_audio_ms determinista.
$baseStart = 0
$totalMs = [int](Get-Prop $manifest "total_audio_ms" 20000)
if ($totalMs -lt 20000) { $totalMs = 20000 }
$baseEnd = $totalMs

if ($clips.Count -ge 1) {
  $baseStart = [int](Get-Prop $clips[0] "start_ms" 0)
  $baseEnd   = [int](Get-Prop $clips[0] "end_ms" $totalMs)
  if ($baseEnd -le $baseStart) { $baseEnd = $baseStart + $totalMs }
}

$outLines = New-Object System.Collections.Generic.List[string]
$idx = 1

for ($i=0; $i -lt $N; $i++) {
  $s = $scenes[$i]

  # Texto: script_text -> text -> narration
  $t = ((Get-Prop $s "script_text" "") ?? "").ToString().Trim()
  if (-not $t) { $t = ((Get-Prop $s "text" "") ?? "").ToString().Trim() }
  if (Is-PlaceholderSceneText $t) {
    $narr = ((Get-Prop $s "narration" "") ?? "").ToString().Trim()
    if ($narr) { $t = $narr }
  }

  # Si sigue vacío/placeholder y AllowPlaceholderText, fabricamos etiqueta determinista
  if ((-not $t) -and $AllowPlaceholderText) { $t = ("Escena {0:00}" -f ($i+1)) }
  if (Is-PlaceholderSceneText $t -and $AllowPlaceholderText) { $t = ("Escena {0:00}" -f ($i+1)) }

  # Si no permitimos placeholders, salta
  if ((Is-PlaceholderSceneText $t) -and (-not $AllowPlaceholderText)) { continue }
  if (-not $t) { continue }

  # Tiempos
  $startMs = 0
  $endMs   = 0

  if ($clips.Count -eq $N) {
    $startMs = [int](Get-Prop $clips[$i] "start_ms" 0)
    $endMs   = [int](Get-Prop $clips[$i] "end_ms" 0)
  }
  elseif ($clips.Count -eq 1) {
    $dur = ($baseEnd - $baseStart)
    $seg = [Math]::Max(1, [Math]::Floor($dur / $N))
    $startMs = $baseStart + ($i * $seg)
    $endMs   = if ($i -eq ($N-1)) { $baseEnd } else { $baseStart + (($i+1) * $seg) }
  }
  elseif (Has-Prop $s "start_ms" -and Has-Prop $s "end_ms") {
    $startMs = [int](Get-Prop $s "start_ms" 0)
    $endMs   = [int](Get-Prop $s "end_ms" 0)
  }
  else {
    $dur = 20000
    $seg = [Math]::Max(1, [Math]::Floor($dur / $N))
    $startMs = $i * $seg
    $endMs   = if ($i -eq ($N-1)) { 20000 } else { ($i+1) * $seg }
  }

  if ($endMs -le $startMs) { $endMs = $startMs + 1500 }

  $wrapped = @(Wrap-Text -t $t -maxChars $MaxCharsPerLine -maxLines $MaxLines)
  if ($wrapped.Length -eq 0) { continue }

  $outLines.Add("$idx")
  $outLines.Add(("{0} --> {1}" -f (Format-SrtTime $startMs), (Format-SrtTime $endMs)))
  foreach ($ln in $wrapped) { $outLines.Add($ln) }
  $outLines.Add("")
  $idx++
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($OutSrtPath, $outLines, $utf8NoBom)

Write-Host ("OK: SRT -> " + $OutSrtPath)
Write-Host ("OK: captions=" + ($idx-1))
Write-Host ("OK: scenes=" + $N + " clips=" + $clips.Count)
