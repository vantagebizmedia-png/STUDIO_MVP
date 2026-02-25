param(
  [string]$RunId = "",
  [int]$Seed = 21,
  [string]$MusicTag = "seguridad auto",
  [string]$SubsFont = "C:\Windows\Fonts\arial.ttf",
  [int]$SubsSize = 34,
  [double]$VoicePacing = 1.25
)

$ErrorActionPreference="Stop"
chcp 65001 | Out-Null
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"


$ws = $env:STUDIO_WORKSPACE
if (-not $ws) { $ws = "$env:USERPROFILE\STUDIO_WORKSPACE" }
$runs = Join-Path $ws "runs"
if (!(Test-Path $runs)) { throw "No existe: $runs" }

if ($RunId) {
  $runDir = Join-Path $runs $RunId
  if (!(Test-Path $runDir)) { throw "No existe run: $runDir" }
} else {
  $runDir = (Get-ChildItem $runs -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

$pack = Join-Path $runDir "content_pack"
if (!(Test-Path $pack)) { throw "No existe content_pack: $pack" }

# 0) run.py debe soportar --pack_dir
$help = (python run.py -h 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "run.py -h falló (no puedo validar reuso). Revisa last_run_help.log" }
if ($help -notmatch '--pack_dir') { throw "run.py NO soporta --pack_dir. Smoke inválido." }

# Contar assets existentes
$audioDir = Join-Path $runDir "render\audio"
$imgDir   = Join-Path $runDir "render\images"

$a = 0; $i = 0
if (Test-Path $audioDir) { $a = (Get-ChildItem $audioDir -File -Filter "scene_*.wav" -ErrorAction SilentlyContinue).Count }
if (Test-Path $imgDir)   { $i = (Get-ChildItem $imgDir -File -Filter "scene_*.png" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_sub\.png$' }).Count }

$max = [Math]::Max(1, [Math]::Min($a, $i))

Write-Host "RUN=$runDir"
Write-Host "PACK=$pack"
Write-Host "AUDIO=$a  IMAGES=$i  -> MAX_SCENES=$max"
Write-Host ""

# 1) Ejecutar run.py (SI FALLA => FAIL)
python run.py "IGNORED" --seed $Seed --max_scenes $max --pack_dir "$pack" `
  --subs --subs_font "$SubsFont" --subs_size $SubsSize `
  --voice_pacing $VoicePacing `
  --music_mode topic --music_tag "$MusicTag"

if ($LASTEXITCODE -ne 0) { throw "SMOKE_REUSE FAIL: run.py falló (no valido reuso)." }

# 2) Validar manifest del MISMO run
$rm = Join-Path $runDir "render\render_manifest.json"
if (!(Test-Path $rm)) { throw "No existe render_manifest.json: $rm" }

$m = Get-Content $rm -Raw | ConvertFrom-Json

function All-Reuse($items) {
  foreach ($x in $items) {
    if (-not $x) { return $false }
    if ($x.provider -ne "REUSE_RENDER") { return $false }
    if ($x.mode -ne "REUSE") { return $false }
    if ($x.cache_hit -ne $true) { return $false }
  }
  return $true
}

"=== AUDIO META ==="
$m.audio.meta | Format-Table -AutoSize
"=== IMAGES META ==="
$m.images.meta | Format-Table -AutoSize

$okA = All-Reuse $m.audio.meta
$okI = All-Reuse $m.images.meta

if (-not $okA -or -not $okI) { throw "SMOKE_REUSE FAIL: NO todo fue REUSE_RENDER." }

Write-Host ""
Write-Host "SMOKE_REUSE PASS (0 gasto de API)"

