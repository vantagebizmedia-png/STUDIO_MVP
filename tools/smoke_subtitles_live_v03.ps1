param(
  [string]$LiveDir = "",
  [int]$MaxScenes = 6,
  [string]$SrtName = "captions_v03.srt"
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

# 0) Descubre LiveDir si no lo pasas
if (-not $LiveDir -or $LiveDir.Trim().Length -lt 3) {
  $cand = Join-Path $repo "_v03_smoke_cfg\artifacts"
  if (Test-Path $cand) {
    $LiveDir = $cand
  } else {
    throw "No pasaste -LiveDir y no existe _v03_smoke_cfg\artifacts"
  }
}

$live = (Resolve-Path $LiveDir).Path

# manifest puede estar en root LIVE o en LIVE\artifacts (compat)
$manifest = Join-Path $live "manifest_v03.json"
$baseDir = $live
if (-not (Test-Path -LiteralPath $manifest)) {
  $altLive = Join-Path $live "artifacts"
  $altMan  = Join-Path $altLive "manifest_v03.json"
  if (Test-Path -LiteralPath $altMan) {
    $baseDir = (Resolve-Path $altLive).Path
    $manifest = $altMan
  } else {
    throw "Falta manifest_v03.json en LIVE: $live"
  }
}# outputs esperados
$videoBase = Join-Path $live "video.mp4"
$videoSubs = Join-Path $live "video_subtitles.mp4"
$srt       = Join-Path $live $SrtName

if (-not (Test-Path $videoBase)) { throw "Falta video.mp4 en LIVE: $videoBase (corre apply_subtitles_live_v03.ps1)" }
if (-not (Test-Path $srt))       { throw "Falta SRT en LIVE: $srt (corre apply_subtitles_live_v03.ps1)" }
if (-not (Test-Path $videoSubs)) { throw "Falta video_subtitles.mp4 en LIVE: $videoSubs (corre apply_subtitles_live_v03.ps1)" }

# LIVE puede ser corto => tamaños pequeños son OK pero no 0
$vb = (Get-Item -LiteralPath $videoBase).Length
$sb = (Get-Item -LiteralPath $srt).Length
$vs = (Get-Item -LiteralPath $videoSubs).Length

if ($vb -lt 5000) { throw "video.mp4 demasiado pequeño (posible fallo): $videoBase (bytes=$vb)" }
if ($sb -le 10)   { throw "SRT vacío: $srt (bytes=$sb)" }
if ($vs -lt 5000) { throw "video_subtitles.mp4 demasiado pequeño (posible fallo): $videoSubs (bytes=$vs)" }

# 1) Validar manifest: scene_builder_v03 + scenes_v03 y timestamps/paths
$m = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not ($m.PSObject.Properties.Name -contains "scene_builder_v03")) { throw "manifest LIVE no tiene scene_builder_v03" }
if (-not ($m.PSObject.Properties.Name -contains "scenes_v03")) { throw "manifest LIVE no tiene scenes_v03[]" }

$sc = @($m.scenes_v03)
if ($sc.Count -lt 1) { throw "scenes_v03[] vacío en LIVE" }
if ($sc.Count -gt $MaxScenes) { throw "scenes_v03.Count > MaxScenes en LIVE (Count=$($sc.Count) MaxScenes=$MaxScenes)" }

$total = 0
try { $total = [int]($m.scene_builder_v03.total_audio_ms) } catch { $total = 0 }
if ($total -le 0) { throw "scene_builder_v03.total_audio_ms <= 0 en LIVE" }

$prevEnd = -1
for ($i=0; $i -lt $sc.Count; $i++) {
  $s = $sc[$i]

  foreach ($p in @("start_ms","end_ms","duration_ms","assets")) {
    if (-not ($s.PSObject.Properties.Name -contains $p)) { throw "scenes_v03[$i] sin $p (LIVE)" }
  }

  $start = [int]$s.start_ms
  $end   = [int]$s.end_ms

  if ($start -lt 0) { throw "start_ms < 0 en escena $i (LIVE)" }
  if ($end -le $start) { throw "end_ms <= start_ms en escena $i (LIVE) (start=$start end=$end)" }
  if ($start -lt $prevEnd) { throw "timestamps no monotónicos en escena $i (LIVE) prevEnd=$prevEnd start=$start" }
  $prevEnd = $end

  $imgRel = $s.assets.image
  if (-not $imgRel) { throw "Escena $i sin assets.image (LIVE)" }
  $imgRel = ([string]$imgRel).Replace("/", "\")
  $imgAbs = Join-Path $baseDir $imgRel
  if (-not (Test-Path $imgAbs)) { throw "Imagen no existe (LIVE): $imgAbs" }

  $acRel = $s.assets.audio_clip
  if (-not $acRel) { throw "Escena $i sin assets.audio_clip (LIVE)" }
  $acRel = ([string]$acRel).Replace("/", "\")
  $acAbs = Join-Path $baseDir $acRel
  if (-not (Test-Path $acAbs)) { throw "Audio clip no existe (LIVE): $acAbs" }
}

$lastEnd = [int]$sc[$sc.Count-1].end_ms
if ($lastEnd -ne $total) {
  throw "end_ms final ($lastEnd) != total_audio_ms ($total) en LIVE"
}

Write-Host "SMOKE OK: LIVE subtitles v03. live=$live scenes=$($sc.Count) total_ms=$total video_bytes=$vb subs_bytes=$vs srt_bytes=$sb" -ForegroundColor Green



