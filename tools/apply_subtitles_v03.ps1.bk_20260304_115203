param(
  [Parameter(Mandatory=$true)][string]$PackDir,
  [string]$SrtName = "captions_v03.srt",
  [int]$FontSize = 52,
  [int]$MarginV  = 120,
  [int]$Outline  = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path
$pack = (Resolve-Path $PackDir).Path

$manifest = Join-Path $pack "manifest_v03.json"
if (-not (Test-Path $manifest)) { throw "Falta manifest_v03.json en: $pack" }

# Heurística determinista: LIVE dir (artifacts) suele NO tener ZIP final.
# Pack normal: suele tener pack.final_delivery.zip (o al menos se usa para export/finalize).
$zipFinal = Join-Path $pack "pack.final_delivery.zip"
$isLive = (-not (Test-Path $zipFinal))

# Umbral mínimo de tamaño para outputs
$minBytesVideoSubs = if ($isLive) { 5000 } else { 50000 }

# 1) Genera SRT desde scenes_v03
$py = Join-Path $repo "tools\patch_manifest_subtitles_v03.py"
if (-not (Test-Path $py)) { throw "Falta patcher: $py" }

python -u $py --pack-dir $pack --out $SrtName

$srt = Join-Path $pack $SrtName
if (-not (Test-Path $srt)) { throw "No se generó SRT: $srt" }
if ( (Get-Item -LiteralPath $srt).Length -le 10 ) { throw "SRT muy pequeño/vacío: $srt" }

# 2) Video fuente (preferir video.mp4)
$videoIn = Join-Path $pack "video.mp4"
if (-not (Test-Path $videoIn)) {
  $cand = Get-ChildItem -LiteralPath $pack -Filter *.mp4 -File | Sort-Object FullName | Select-Object -First 1
  if (-not $cand) { throw "No encuentro video fuente .mp4 en pack: $pack" }
  $videoIn = $cand.FullName
}

$videoOut = Join-Path $pack "video_subtitles.mp4"

# 3) Burn-in con ffmpeg (force_style para safe margins)
$absSrt = (Resolve-Path $srt).Path
$absSrtEsc = $absSrt.Replace("\", "/").Replace(":", "\:")

# ASS force_style (determinista)
# Alignment=2 bottom-center
# WrapStyle=2 smart
$style = "Alignment=2,MarginV=$MarginV,Fontsize=$FontSize,Outline=$Outline,Shadow=0,WrapStyle=2,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000"
$vf = "subtitles='$absSrtEsc':force_style='$style'"

$ff = "ffmpeg"
if (-not (Get-Command $ff -ErrorAction SilentlyContinue)) { throw "ffmpeg no está disponible en PATH." }

& $ff -y -hide_banner -loglevel error `
  -i $videoIn `
  -vf $vf `
  -c:v libx264 -crf 20 -preset veryfast -pix_fmt yuv420p `
  -c:a aac -b:a 192k `
  -movflags +faststart `
  $videoOut

if (-not (Test-Path $videoOut)) { throw "No se generó video_subtitles.mp4" }

$lenOut = (Get-Item -LiteralPath $videoOut).Length
if ($lenOut -lt $minBytesVideoSubs) {
  throw "video_subtitles.mp4 demasiado pequeño (posible fallo): $videoOut (bytes=$lenOut min=$minBytesVideoSubs isLive=$isLive)"
}

Write-Host "OK: Subtitles v03 aplicados. SRT=$srt OUT=$videoOut FontSize=$FontSize MarginV=$MarginV Outline=$Outline isLive=$isLive" -ForegroundColor Green
