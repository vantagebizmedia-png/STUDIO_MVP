param(
  [string]$LiveDir = "",
  [string]$SrtName = "captions_v03.srt",
  [int]$FontSize = 52,
  [int]$MarginV  = 120,
  [int]$Outline  = 3,

  # Render base video from (image+audio)
  [int]$W = 1080,
  [int]$H = 1920,
  [int]$Fps = 30
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
}

# ffmpeg requerido
$ff = "ffmpeg"
if (-not (Get-Command $ff -ErrorAction SilentlyContinue)) { throw "ffmpeg no está disponible en PATH." }

# 1) Lee manifest y resuelve artifacts.image / artifacts.audio
$m = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $m.artifacts) { throw "manifest sin artifacts (LIVE): $manifest" }

$imgRel = [string]($m.artifacts.image)
$audRel = [string]($m.artifacts.audio)

if (-not $imgRel) { throw "manifest.artifacts.image vacío (LIVE)" }
if (-not $audRel) { throw "manifest.artifacts.audio vacío (LIVE)" }

# tolera / y \
$imgRel = $imgRel.Replace("/", "\")
$audRel = $audRel.Replace("/", "\")

# artifacts paths son relativos al baseDir (root o artifacts según donde esté el manifest)
$imgAbs = (Resolve-Path (Join-Path $baseDir $imgRel)).Path
$audAbs = (Resolve-Path (Join-Path $baseDir $audRel)).Path

if (-not (Test-Path -LiteralPath $imgAbs)) { throw "No existe image (LIVE): $imgAbs" }
if (-not (Test-Path -LiteralPath $audAbs)) { throw "No existe audio (LIVE): $audAbs" }function Get-VideoDurationSec {
  param([Parameter(Mandatory=$true)][string]$VideoPath)
  $ffp = "ffprobe"
  if (-not (Get-Command $ffp -ErrorAction SilentlyContinue)) { return -1 }
  try {
    $s = & $ffp -v error -show_entries format=duration -of default=nw=1:nk=1 $VideoPath
    if (-not $s) { return -1 }
    $d = 0.0
    if ([double]::TryParse(($s | Select-Object -First 1), [ref]$d)) { return $d }
    return -1
  } catch {
    return -1
  }
}

# 2) Si no existe video.mp4 en LIVE, lo creamos determinista desde (img+audio)
$videoIn = Join-Path $live "video.mp4"
if (-not (Test-Path $videoIn)) {

  # IMPORTANTE: usar ${W}/${H} para evitar parse "$W:" por el ':'
  $vf = "scale=w=${W}:h=${H}:force_original_aspect_ratio=decrease,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2"

  & $ff -y -hide_banner -loglevel error `
    -loop 1 -framerate ${Fps} -i $imgAbs `
    -i $audAbs `
    -vf $vf `
    -c:v libx264 -crf 20 -preset veryfast -pix_fmt yuv420p `
    -c:a aac -b:a 192k `
    -shortest -movflags +faststart `
    $videoIn

  if (-not (Test-Path $videoIn)) { throw "No se pudo crear video.mp4 (LIVE): $videoIn" }

  # OJO: LIVE puede ser 1s => archivo pequeño es normal
  $len = (Get-Item -LiteralPath $videoIn).Length
  if ($len -lt 5000) { throw "video.mp4 demasiado pequeño (posible fallo): $videoIn (bytes=$len)" }

  $dur = Get-VideoDurationSec -VideoPath $videoIn
  if ($dur -ge 0 -and $dur -lt 0.2) { throw "video.mp4 duración demasiado baja (posible fallo): $videoIn (dur=${dur}s)" }
}

# 3) Reusa tu apply_subtitles_v03.ps1 (burn-in + SRT)
$applySubs = Join-Path $repo "tools\apply_subtitles_v03.ps1"
if (-not (Test-Path $applySubs)) { throw "Falta: $applySubs" }

pwsh -NoProfile -ExecutionPolicy Bypass -File $applySubs `
  -PackDir $live `
  -SrtName $SrtName `
  -FontSize $FontSize -MarginV $MarginV -Outline $Outline

$vidOut = Join-Path $live "video_subtitles.mp4"
if (-not (Test-Path $vidOut)) { throw "No se generó video_subtitles.mp4 en LIVE: $vidOut" }

Write-Host "OK: LIVE subtitles aplicados. live=$live base=$videoIn out=$vidOut" -ForegroundColor Green

