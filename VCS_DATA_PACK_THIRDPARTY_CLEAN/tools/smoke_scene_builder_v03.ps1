param(
  [string]$PackDir = "C:\Users\vanta\Documents\STUDIO_WORKSPACE\exports\pack_v03_359ac8c6_s01",
  [int]$MaxScenes = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$pack = (Resolve-Path $PackDir).Path
$manifest = Join-Path $pack "manifest_v03.json"
if (-not (Test-Path $manifest)) { throw "Falta manifest_v03.json en: $pack" }

$m = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $m.scenes_v03) { throw "manifest no tiene scenes_v03[]" }
$sc = @($m.scenes_v03)
if ($sc.Count -lt 1) { throw "scenes_v03[] vacío" }
if ($sc.Count -gt $MaxScenes) { throw "scenes_v03.Count > MaxScenes" }

if (-not $m.scene_builder_v03) { throw "manifest no tiene scene_builder_v03" }
$total = [int]($m.scene_builder_v03.total_audio_ms)
if ($total -le 0) { throw "total_audio_ms sigue en 0 (no se leyó WAV o no es WAV válido)" }

$prevEnd = -1
$bytesAudio = 0

for ($i=0; $i -lt $sc.Count; $i++) {
  $s = $sc[$i]

  foreach ($p in @("start_ms","end_ms","duration_ms","assets")) {
    if (-not ($s.PSObject.Properties.Name -contains $p)) { throw "scenes_v03[$i] sin $p" }
  }

  $start = [int]$s.start_ms
  $end   = [int]$s.end_ms
  if ($start -lt 0) { throw "start_ms < 0 en escena $i" }
  if ($end -le $start) { throw "end_ms <= start_ms en escena $i (start=$start end=$end)" }
  if ($start -lt $prevEnd) { throw "timestamps no monotónicos en escena $i" }
  $prevEnd = $end

  # image
  $imgRel = $s.assets.image
  if (-not $imgRel) { throw "Escena $i sin assets.image" }
  $imgPath = Join-Path $pack $imgRel
  if (-not (Test-Path $imgPath)) { throw "Imagen no existe: $imgPath" }

  # audio clip
  $acRel = $s.assets.audio_clip
  if (-not $acRel) { throw "Escena $i sin assets.audio_clip" }
  $acPath = Join-Path $pack $acRel
  if (-not (Test-Path $acPath)) { throw "Audio clip no existe: $acPath" }

  $bytesAudio += (Get-Item -LiteralPath $acPath).Length
}

$lastEnd = [int]$sc[$sc.Count-1].end_ms
if ($lastEnd -ne $total) { throw "end_ms final ($lastEnd) != total_audio_ms ($total)" }
if ($bytesAudio -le 0) { throw "Suma de bytes de audio_clips es 0 (clips vacíos)" }

Write-Host "SMOKE OK: Scene Builder v03 (timestamps+img+audio_clips). pack=$pack scenes_v03=$($sc.Count) total_ms=$total audio_bytes=$bytesAudio" -ForegroundColor Green
