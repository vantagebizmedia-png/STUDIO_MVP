param(
  [Parameter(Mandatory=$true)][string]$LiveDir,
  [int]$MaxScenes = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg) {
  throw "SMOKE FAIL: $msg"
}

$live = (Resolve-Path -LiteralPath $LiveDir).Path
$mfPath = Join-Path $live "manifest_v03.json"
if (-not (Test-Path -LiteralPath $mfPath)) { Fail "No existe manifest_v03.json en LIVE: $live" }

$mf = Get-Content -LiteralPath $mfPath -Raw | ConvertFrom-Json
if (-not $mf.scenes_v03) { Fail "manifest_v03.json no tiene scenes_v03" }

$scenes = @($mf.scenes_v03)
$scCount = $scenes.Count
if ($scCount -lt 1) { Fail "scenes_v03 vacío" }
if ($scCount -gt $MaxScenes) { Fail "scenes_v03=$scCount supera MaxScenes=$MaxScenes" }

# --- total_ms (compat): prefer top-level total_audio_ms, fallback a scene_builder_v03.total_audio_ms ---
$total = $null
if ($mf.PSObject.Properties.Name -contains "total_audio_ms") {
  $total = [int]$mf.total_audio_ms
} elseif ($mf.scene_builder_v03 -and ($mf.scene_builder_v03.PSObject.Properties.Name -contains "total_audio_ms")) {
  $total = [int]$mf.scene_builder_v03.total_audio_ms
} else {
  Fail "No existe total_audio_ms ni scene_builder_v03.total_audio_ms"
}

if ($total -le 0) { Fail "total_audio_ms inválido: $total" }

# --- Check coherencia de timings ---
$lastEnd = 0
for ($i=0; $i -lt $scCount; $i++) {
  $s = $scenes[$i]
  $st = [int]($s.start_ms)
  $en = [int]($s.end_ms)

  if ($st -lt 0 -or $en -lt 0) { Fail "timing negativo en escena i=${i}: ${st}..${en}" }
  if ($en -lt $st) { Fail "end_ms < start_ms en escena i=${i}: ${st}..${en}" }
  if ($st -lt $lastEnd) { Fail "start_ms no monótono en escena i=${i}: prevEnd=$lastEnd start=${st}" }

  $lastEnd = $en
}

if ($lastEnd -ne $total) { Fail "last_end=$lastEnd != total_audio_ms=$total" }

# --- Check audio clips por escena ---
$artDir = Join-Path $live "artifacts"
if (-not (Test-Path -LiteralPath $artDir)) { Fail "No existe artifacts/ en LIVE: $live" }

for ($i=1; $i -le $scCount; $i++) {
  $s = $scenes[$i-1]
  $clip = $null
  if ($s.assets -and $s.assets.audio_clip) { $clip = [string]$s.assets.audio_clip }
  if (-not $clip) { Fail "Falta assets.audio_clip en escena index=$($s.index)" }

  $expectedLegacy = ("artifacts/audio_s{0:d2}.wav" -f $i)
  $expectedV03    = ("assets/audio_clips/s{0:d2}.wav" -f $i)
  if (($clip -ne $expectedLegacy) -and ($clip -ne $expectedV03)) {
    Fail "audio_clip inesperado en escena ${i}: '$clip' != legacy='$expectedLegacy' ni v03='$expectedV03'"
  }

  $clipAbs = Join-Path $live $clip
  if (-not (Test-Path -LiteralPath $clipAbs)) {
    Fail "No existe clip: $clipAbs"
  }

  $len = (Get-Item -LiteralPath $clipAbs).Length
  if ($len -lt 1000) {
    Fail "Clip demasiado pequeño ($len bytes): $clipAbs"
  }
}

Write-Host ("SMOKE OK: LIVE manifest v03 (scenes_v03 + audio_clips). live={0} scenes={1} total_ms={2} last_end={3}" -f $live,$scCount,$total,$lastEnd)
