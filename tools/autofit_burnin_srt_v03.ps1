param(
  [Parameter(Mandatory=$true)][string]$InVideo,
  [Parameter(Mandatory=$true)][string]$InSrt,
  [Parameter(Mandatory=$true)][string]$OutVideo,

  [double]$MarginVFrac = 0.08,
  [double]$MarginHFrac = 0.08,
  [int]$FontSizeMax = 48,
  [int]$FontSizeMin = 24,
  [double]$MaxLineCharsTarget = 26,
  [int]$Outline = 2,
  [int]$Shadow = 0,
  [int]$Alignment = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Get-MaxLinesPerBlock([string]$Path) {
  $lines = Get-Content -LiteralPath $Path -Encoding UTF8
  $cur = 0
  $max = 0

  foreach ($l in $lines) {
    $t = $l.Trim()

    if (-not $t) {
      if ($cur -gt $max) { $max = $cur }
      $cur = 0
      continue
    }

    if ($t -match '^\d+$') { continue }
    if ($t -match '^\d{2}:\d{2}:\d{2},\d{3}\s-->\s') { continue }

    $cur++
  }

  if ($cur -gt $max) { $max = $cur }
  if ($max -lt 1) { $max = 1 }
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
  $x = $p -replace '\\','/'
  $x = $x -replace ':','\:'
  $x = $x -replace "'","\'"
  return $x
}

function Get-VideoSize([string]$VideoPath) {
  $w = 1080
  $h = 1920

  try {
    $probe = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$VideoPath"
    if ($LASTEXITCODE -eq 0 -and $probe) {
      $parts = @(($probe.Trim()) -split 'x')
      if ($parts.Count -eq 2) {
        $pw = 0
        $ph = 0
        [void][int]::TryParse($parts[0], [ref]$pw)
        [void][int]::TryParse($parts[1], [ref]$ph)
        if ($pw -gt 0) { $w = $pw }
        if ($ph -gt 0) { $h = $ph }
      }
    }
  } catch { }

  return [pscustomobject]@{
    Width = $w
    Height = $h
  }
}

if (-not (Test-Path -LiteralPath $InVideo)) { throw "No existe InVideo: $InVideo" }
$InSrt = Resolve-Srt -Path $InSrt

$maxLen = Get-LongestSrtLineLen $InSrt
if ($maxLen -lt 1) { $maxLen = 1 }

$maxLines = Get-MaxLinesPerBlock $InSrt
if ($maxLines -lt 1) { $maxLines = 1 }

$videoSize = Get-VideoSize $InVideo
$w = [int]$videoSize.Width
$h = [int]$videoSize.Height

if ($w -lt 320) { $w = 1080 }
if ($h -lt 320) { $h = 1920 }

$marginV = [int][math]::Round($h * $MarginVFrac)
$marginH = [int][math]::Round($w * $MarginHFrac)

if ($marginV -lt 60) { $marginV = 60 }
if ($marginH -lt 60) { $marginH = 60 }

$usableWidth = $w - (2 * $marginH)
if ($usableWidth -lt 200) { $usableWidth = [int][math]::Max(200, $w - 120) }

$charRatio = [math]::Sqrt($MaxLineCharsTarget / [double]$maxLen)
$linePenalty = 1.0
if ($maxLines -ge 3) { $linePenalty = 0.86 }
elseif ($maxLines -eq 2) { $linePenalty = 0.93 }

$widthPenalty = [math]::Sqrt($usableWidth / 920.0)
if ($widthPenalty -gt 1.0) { $widthPenalty = 1.0 }
if ($widthPenalty -lt 0.72) { $widthPenalty = 0.72 }

$fs = [int][math]::Round($FontSizeMax * $charRatio * $linePenalty * $widthPenalty)

if ($fs -gt $FontSizeMax) { $fs = $FontSizeMax }
if ($fs -lt $FontSizeMin) { $fs = $FontSizeMin }

$force = "Fontsize=$fs,MarginV=$marginV,MarginL=$marginH,MarginR=$marginH,Alignment=$Alignment,WrapStyle=2,Outline=$Outline,Shadow=$Shadow"

Write-Host ("Using SRT: {0}" -f $InSrt)
Write-Host ("Video size = {0}x{1}" -f $w, $h)
Write-Host ("SRT longest line = {0} chars | max lines block = {1}" -f $maxLen, $maxLines)
Write-Host ("Autofit font={0} marginH={1}px marginV={2}px usableWidth={3}px" -f $fs, $marginH, $marginV, $usableWidth)

$inV = (Resolve-Path -LiteralPath $InVideo).Path
$inS = (Resolve-Path -LiteralPath $InSrt).Path
$inS_esc = Escape-ForFfmpegSubtitlesFilename $inS

$vf = "subtitles=filename='$inS_esc':force_style='$force'"

& ffmpeg -y -v error -i "$inV" -vf "$vf" -c:a copy "$OutVideo"
if ($LASTEXITCODE -ne 0) { throw "ffmpeg burn-in falló" }

if (-not (Test-Path -LiteralPath $OutVideo)) { throw "No se generó OutVideo: $OutVideo" }

$len = (Get-Item -LiteralPath $OutVideo).Length
Write-Host ("OK burn-in autofit -> {0} ({1} bytes)" -f $OutVideo, $len) -ForegroundColor Green