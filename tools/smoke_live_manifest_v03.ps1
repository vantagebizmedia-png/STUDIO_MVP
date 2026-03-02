param(
  # smoke estándar genera aquí
  [string]$LiveDir = "",
  [int]$MaxScenes = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

# 0) Corre SMOKE LIVE (no asumimos que ya corrió)
$smoke = Join-Path $repo "tools\studio.ps1"
if (-not (Test-Path $smoke)) { throw "No existe: $smoke" }

pwsh -NoProfile -ExecutionPolicy Bypass -File $smoke -Mode smoke

# 1) Descubre LiveDir si no lo pasas (preferimos _v03_smoke_cfg\artifacts)
if (-not $LiveDir -or $LiveDir.Trim().Length -lt 3) {
  $cand = Join-Path $repo "_v03_smoke_cfg\artifacts"
  if (Test-Path $cand) {
    $LiveDir = $cand
  } else {
    # fallback: busca manifest_v03.json más reciente fuera de exports/_freeze
    $man = Get-ChildItem -LiteralPath $repo -Recurse -File -Filter manifest_v03.json |
      Where-Object { $_.FullName -notmatch '\\exports\\|\\_freeze_|\\__pycache__\\|\\.venv\\' } |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if (-not $man) { throw "No encontré manifest_v03.json LIVE dentro del repo." }
    $LiveDir = Split-Path $man.FullName -Parent
  }
}

$live = (Resolve-Path $LiveDir).Path
$manifest = Join-Path $live "manifest_v03.json"
if (-not (Test-Path $manifest)) { throw "Falta manifest_v03.json en LIVE dir: $live" }

$m = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json

# 2) Validaciones mínimas
if (-not ($m.PSObject.Properties.Name -contains "scene_builder_v03")) { throw "manifest LIVE no tiene scene_builder_v03" }
if (-not ($m.PSObject.Properties.Name -contains "scenes_v03")) { throw "manifest LIVE no tiene scenes_v03[]" }

$sc = @($m.scenes_v03)
if ($sc.Count -lt 1) { throw "scenes_v03[] vacío en LIVE" }
if ($sc.Count -gt $MaxScenes) { throw "scenes_v03.Count > MaxScenes en LIVE" }

$total = 0
try { $total = [int]($m.scene_builder_v03.total_audio_ms) } catch { $total = 0 }
if ($total -le 0) { throw "scene_builder_v03.total_audio_ms <= 0 en LIVE" }

# 3) paths existen (image + audio_clip) y timestamps monotónicos
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
  if ($start -lt $prevEnd) { throw "timestamps no monotónicos en escena $i (LIVE)" }
  $prevEnd = $end

  $imgRel = $s.assets.image
  if (-not $imgRel) { throw "Escena $i sin assets.image (LIVE)" }

  $imgRel = [string]$imgRel
  $imgRel = $imgRel.Replace("/", "\")  # tolera json con /
  $imgPath = Join-Path $live $imgRel
  if (-not (Test-Path $imgPath)) { throw "Imagen no existe (LIVE): $imgPath" }

  $acRel = $s.assets.audio_clip
  if (-not $acRel) { throw "Escena $i sin assets.audio_clip (LIVE)" }

  $acRel = [string]$acRel
  $acRel = $acRel.Replace("/", "\")
  $acPath = Join-Path $live $acRel
  if (-not (Test-Path $acPath)) { throw "Audio clip no existe (LIVE): $acPath" }
}

$lastEnd = [int]$sc[$sc.Count-1].end_ms
if ($lastEnd -le 0) { throw "end_ms final <= 0 en LIVE" }

Write-Host "SMOKE OK: LIVE manifest v03 (scene_builder_v03 + scenes_v03). live=$live scenes=$($sc.Count) total_ms=$total last_end=$lastEnd" -ForegroundColor Green
