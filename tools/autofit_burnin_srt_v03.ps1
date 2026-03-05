param(
  [Parameter(Mandatory=$true)][string]$InVideo,
  [Parameter(Mandatory=$true)][string]$InSrt,
  [Parameter(Mandatory=$true)][string]$OutVideo,

  [double]$MarginVFrac = 0.08,
  [int]$FontSizeMax = 54,
  [int]$FontSizeMin = 28,
  [double]$MaxLineCharsTarget = 28
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Get-LongestSrtLineLen([string]$Path) {
  $lines = Get-Content -LiteralPath $Path -Encoding UTF8
  $max = 0
  foreach ($l in $lines) {
    $t = $l.Trim()
    if (-not $t) { continue }
    if ($t -match '^\d+$') { continue }
    if ($t -match '^\d{2}:\d{2}:\d{2},\d{3}\s-->\s') { continue }
    if ($t.Length -gt $max) { $max = $t.Length }
  }
  return $max
}

function Resolve-Srt([string]$Path) {
  if (Test-Path -LiteralPath $Path) { return (Resolve-Path -LiteralPath $Path).Path }

  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) {
    throw "No existe InSrt ni su carpeta: $Path"
  }

  $try = @("captions.srt","subtitles.srt","subs.srt","captions_v03.srt")
  foreach ($n in $try) {
    $p = Join-Path $dir $n
    if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
  }

  $cand = Get-ChildItem -LiteralPath $dir -File -Filter *.srt -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending |
          Select-Object -First 1
  if ($cand) { return $cand.FullName }

  throw "No existe InSrt: $Path (ni encontré ningún .srt en $dir)"
}

function Escape-ForFfmpegSubtitlesFilename([string]$p) {
  # ffmpeg filtergraph: escape backslash, single quote, and colon after drive letter (C:)
  # 1) normaliza a / para evitar \ como escape raro
  $x = $p -replace '\\','/'
  # 2) escapa : (importante por C:)
  $x = $x -replace ':','\:'   # C:/... -> C\:/...
  # 3) escapa comillas simples para filename='...'
  $x = $x -replace "'","\'"
  return $x
}

if (-not (Test-Path -LiteralPath $InVideo)) { throw "No existe InVideo: $InVideo" }
$InSrt = Resolve-Srt -Path $InSrt

$maxLen = Get-LongestSrtLineLen $InSrt
if ($maxLen -lt 1) { $maxLen = 1 }

$ratio = [math]::Sqrt($MaxLineCharsTarget / [double]$maxLen)
$fs = [int][math]::Round($FontSizeMax * $ratio)
if ($fs -gt $FontSizeMax) { $fs = $FontSizeMax }
if ($fs -lt $FontSizeMin) { $fs = $FontSizeMin }

$h = 1920
try {
  $probe = & ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$InVideo"
  if ($LASTEXITCODE -eq 0 -and $probe) { $h = [int]($probe.Trim()) }
} catch { }

$mv = [int][math]::Round($h * $MarginVFrac)

$force = "Fontsize=$fs,MarginV=$mv,MarginL=80,MarginR=80,Alignment=2,WrapStyle=2,Outline=2,Shadow=0"

Write-Host ("Using SRT: {0}" -f $InSrt)
Write-Host ("SRT longest line = {0} chars | font={1} | marginV={2}px" -f $maxLen, $fs, $mv)

$inV = (Resolve-Path -LiteralPath $InVideo).Path
$inS = (Resolve-Path -LiteralPath $InSrt).Path
$inS_esc = Escape-ForFfmpegSubtitlesFilename $inS

# CLAVE: usar filename=... para evitar que el ':' del path se interprete como separador de opciones
$vf = "subtitles=filename='$inS_esc':force_style='$force'"

& ffmpeg -y -v error -i "$inV" -vf "$vf" -c:a copy "$OutVideo"
if ($LASTEXITCODE -ne 0) { throw "ffmpeg burn-in falló" }

Write-Host "OK burn-in -> $OutVideo" -ForegroundColor Green
