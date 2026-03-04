param(
  [int]$Crf = 28,
  [ValidateSet("ultrafast","superfast","veryfast","faster","fast","medium","slow","slower","veryslow")]
  [string]$Preset = "veryfast",
  [int]$AudioKbps = 128,
  [int]$Width = 1080,
  [int]$Height = 1920,
  [string]$Input = "",
  [string]$Output = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Resolve-Abs([string]$p) {
  if (-not $p) { return $null }
  try { return (Resolve-Path -LiteralPath $p).Path } catch { return $p }
}

function Same-Path([string]$a, [string]$b) {
  if (-not $a -or -not $b) { return $false }
  return ([string]::Equals((Resolve-Abs $a), (Resolve-Abs $b), [StringComparison]::OrdinalIgnoreCase))
}

function Pick-FirstExisting([string[]]$paths) {
  foreach ($p in $paths) {
    if ($p -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path }
  }
  return $null
}

function Pick-From-LatestArchive([string]$archDir) {
  if (!(Test-Path -LiteralPath $archDir)) { return $null }
  $latestFolder = Get-ChildItem -LiteralPath $archDir -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $latestFolder) { return $null }

  $mp4s = Get-ChildItem -LiteralPath $latestFolder.FullName -File -Filter "*.mp4" -ErrorAction SilentlyContinue
  if (-not $mp4s) { return $null }

  # Preferir masters (no social) si existen
  $preferred = $mp4s | Where-Object { $_.Name -notmatch '_social' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($preferred) { return (Resolve-Path -LiteralPath $preferred.FullName).Path }

  # Si solo hay social, devolver el más reciente
  $any = $mp4s | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($any) { return (Resolve-Path -LiteralPath $any.FullName).Path }

  return $null
}

$ws = $env:STUDIO_WORKSPACE
if (-not $ws) { throw "STUDIO_WORKSPACE no esta seteado." }
if (-not [IO.Path]::IsPathRooted($ws)) { throw "STUDIO_WORKSPACE debe ser absoluto: $ws" }

$outDir  = Join-Path $ws "output"
$runsDir = Join-Path $ws "runs"
$archDir = Join-Path $outDir "_archive"

if (!(Test-Path -LiteralPath $outDir)) { throw "No existe output dir: $outDir" }

if (-not $Output) { $Output = Join-Path $outDir "video_final_latest_social.mp4" }
$OutputAbs = Resolve-Abs $Output

# ---- Resolver Input automáticamente si no fue dado ----
$resolvedInput = $null
$warnSecondGen = $false

if ($Input) {
  if (!(Test-Path -LiteralPath $Input)) { throw "No existe input: $Input" }
  $resolvedInput = (Resolve-Path -LiteralPath $Input).Path
} else {
  $masterLatest = Join-Path $outDir "video_final_latest.mp4"
  $socialLatest = Join-Path $outDir "video_final_latest_social.mp4"

  # 1) Preferido: master latest en output
  $resolvedInput = Pick-FirstExisting @($masterLatest)

  # 2) Si no hay master, preferir último _archive (idealmente master)
  if (-not $resolvedInput) {
    $resolvedInput = Pick-From-LatestArchive $archDir
  }

  # 3) Si no hay archive útil, usar render del último run
  if (-not $resolvedInput -and (Test-Path -LiteralPath $runsDir)) {
    $run = Get-ChildItem -LiteralPath $runsDir -Directory -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if ($run) {
      $renderVid = Join-Path $run.FullName "render\video_final.mp4"
      if (Test-Path -LiteralPath $renderVid) { $resolvedInput = (Resolve-Path -LiteralPath $renderVid).Path }
    }
  }

  # 4) Fallback: cualquier mp4 reciente en output (pero evita el mismo archivo que Output)
  if (-not $resolvedInput) {
    $recent = Get-ChildItem -LiteralPath $outDir -File -Filter "*.mp4" -ErrorAction SilentlyContinue |
      Where-Object { -not (Same-Path $_.FullName $OutputAbs) } |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if ($recent) { $resolvedInput = (Resolve-Path -LiteralPath $recent.FullName).Path }
  }

  # 5) Último fallback: social latest (segunda generación)
  if (-not $resolvedInput -and (Test-Path -LiteralPath $socialLatest)) {
    $resolvedInput = (Resolve-Path -LiteralPath $socialLatest).Path
    $warnSecondGen = $true
  }
}

if (-not $resolvedInput) {
  throw "No pude resolver input. Busqué en output (master), _archive, runs\<latest>\render, y mp4s del output. Puedes pasar -Input manual."
}

if ($warnSecondGen) {
  Write-Host "WARN: No se encontro master. Usare SOCIAL como input (segunda generacion). Recomendado: usa un mp4 del _archive o regenera master con .\studio.ps1 final" -ForegroundColor Yellow
}

$ff = (Get-Command ffmpeg -ErrorAction Stop).Source
Write-Host "ffmpeg : $ff" -ForegroundColor Green
Write-Host "Input  : $resolvedInput" -ForegroundColor Cyan
Write-Host "Output : $OutputAbs" -ForegroundColor Cyan
Write-Host ("Params : crf={0} preset={1} audio={2}k {3}x{4}" -f $Crf,$Preset,$AudioKbps,$Width,$Height) -ForegroundColor DarkGray

# Si input == output, encode a temp y luego reemplaza
$tmpOut = $OutputAbs
$useTemp = $false
if (Same-Path $resolvedInput $OutputAbs) {
  $useTemp = $true
  $tmpOut = ($OutputAbs -replace '\.mp4$', '') + ".__tmp__.mp4"
  if (Test-Path -LiteralPath $tmpOut) { Remove-Item -LiteralPath $tmpOut -Force }
  Write-Host "INFO: Input=Output. Usare temp -> $tmpOut" -ForegroundColor Yellow
}

& ffmpeg -y -i $resolvedInput `
  -vf ("scale={0}:{1}:force_original_aspect_ratio=decrease,pad={0}:{1}:(ow-iw)/2:(oh-ih)/2" -f $Width,$Height) `
  -c:v libx264 -preset $Preset -crf $Crf -pix_fmt yuv420p -movflags +faststart `
  -c:a aac -b:a ("{0}k" -f $AudioKbps) `
  $tmpOut

if ($LASTEXITCODE -ne 0) { throw "ffmpeg fallo (exit=$LASTEXITCODE)" }

if ($useTemp) {
  Move-Item -LiteralPath $tmpOut -Destination $OutputAbs -Force
}

Write-Host "OK: social -> $OutputAbs" -ForegroundColor Green
Get-Item -LiteralPath $resolvedInput, $OutputAbs | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize
