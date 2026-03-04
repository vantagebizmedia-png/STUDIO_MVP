param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $InVideo,
  [string] $OutVideo = "",

  # Cut/Trim
  [double] $TrimStartSec = 0.0,   # recorta al inicio (seg)
  [double] $TrimEndSec   = 0.0,   # recorta al final (seg)

  # Timing FX
  [double] $Speed = 1.0,          # 1.0 = normal (video+audio)
  [double] $FadeInSec  = 0.0,     # fade-in video+audio (seg)
  [double] $FadeOutSec = 0.0,     # fade-out video+audio (seg)

  # Audio FX
  [double] $GainDb = 0.0,         # +dB / -dB
  [switch] $Loudnorm,             # loudnorm I=-16 TP=-1.5 LRA=11

  # Text overlay (opcional)
  [string] $Text = "",
  [ValidateSet("top","center","bottom")]
  [string] $TextPos = "bottom",
  [int] $TextSize = 44,
  [int] $TextMarginV = 80,
  [string] $TextColor = "white",
  [int] $TextBox = 1,
  [string] $TextBoxColor = "black@0.35",
  [string] $Font = "Arial",
  [string] $FontFile = "",        # opcional .ttf

  # Watermark (opcional)
  [string] $Watermark = "",       # ruta PNG (ideal con alpha)
  [int] $WmW = 220,
  [int] $WmMargin = 40,
  [ValidateSet("tl","tr","bl","br")]
  [string] $WmPos = "tr",

  # Encode
  [int] $Crf = 24,
  [ValidateSet("ultrafast","superfast","veryfast","faster","fast","medium","slow","slower","veryslow")]
  [string] $Preset = "veryfast"
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

function Must-File([string]$p) { if (!(Test-Path $p -PathType Leaf)) { throw "FALTA archivo: $p" } }
function Must-Cmd([string]$name) { if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "No encuentro $name en PATH" } }

Must-Cmd ffmpeg
Must-Cmd ffprobe

Must-File $InVideo
$InVideo = (Resolve-Path $InVideo).Path

if (-not $OutVideo) {
  $dir  = Split-Path $InVideo -Parent
  $base = [IO.Path]::GetFileNameWithoutExtension($InVideo)
  $OutVideo = Join-Path $dir ($base + "_EDIT.mp4")
}

$outDir = Split-Path $OutVideo -Parent
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$OutVideo = (Resolve-Path $outDir).Path + "\" + (Split-Path $OutVideo -Leaf)

function Get-Dur([string]$p) {
  $out = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$p"
  if (-not $out) { return 0.0 }
  try { return [double]::Parse(($out | Select-Object -First 1), [Globalization.CultureInfo]::InvariantCulture) } catch { return 0.0 }
}
$dur = Get-Dur $InVideo
if ($dur -le 0) { $dur = 0.0 }

$needVideoFx = ($TrimStartSec -gt 0) -or ($TrimEndSec -gt 0) -or ([math]::Abs($Speed - 1.0) -gt 1e-9) -or ($FadeInSec -gt 0) -or ($FadeOutSec -gt 0) -or ($Text) -or ($Watermark)
$needAudioFx = ($TrimStartSec -gt 0) -or ($TrimEndSec -gt 0) -or ([math]::Abs($Speed - 1.0) -gt 1e-9) -or ($FadeInSec -gt 0) -or ($FadeOutSec -gt 0) -or ([math]::Abs($GainDb) -gt 1e-9) -or $Loudnorm
$needReencode = $needVideoFx -or $needAudioFx

$start = [math]::Max(0.0, [double]$TrimStartSec)
$end = 0.0
if ($TrimEndSec -gt 0 -and $dur -gt 0) {
  $end = [math]::Max(0.0, $dur - [double]$TrimEndSec)
  if ($end -lt $start + 0.05) { throw "Trim invalido: end <= start (dur=$dur start=$start end=$end)" }
}

function Build-Atempo([double]$spd) {
  if ($spd -le 0) { $spd = 1.0 }
  $filters = New-Object System.Collections.Generic.List[string]
  $x = [double]$spd
  while ($x -gt 2.0) { $filters.Add("atempo=2.0"); $x = $x / 2.0 }
  while ($x -lt 0.5) { $filters.Add("atempo=0.5"); $x = $x / 0.5 }
  $filters.Add(("atempo={0}" -f ([math]::Round($x, 6).ToString([Globalization.CultureInfo]::InvariantCulture))))
  return ($filters -join ",")
}

$vf = New-Object System.Collections.Generic.List[string]
if ([math]::Abs($Speed - 1.0) -gt 1e-9) {
  $inv = 1.0 / [double]$Speed
  $vf.Add(("setpts={0}*PTS" -f ([math]::Round($inv, 9).ToString([Globalization.CultureInfo]::InvariantCulture))))
}

$dur2 = 0.0
if ($dur -gt 0) {
  $dur2 = $dur
  if ($start -gt 0) { $dur2 = $dur2 - $start }
  if ($end -gt 0)   { $dur2 = $end - $start }
  if ([math]::Abs($Speed - 1.0) -gt 1e-9 -and $dur2 -gt 0) { $dur2 = $dur2 / [double]$Speed }
}

if ($FadeInSec -gt 0) {
  $vf.Add(("fade=t=in:st=0:d={0}" -f ([math]::Round([double]$FadeInSec,3).ToString([Globalization.CultureInfo]::InvariantCulture))))
}
if ($FadeOutSec -gt 0 -and $dur2 -gt 0) {
  $st = [math]::Max(0.0, $dur2 - [double]$FadeOutSec)
  $vf.Add(("fade=t=out:st={0}:d={1}" -f
    ([math]::Round($st,3).ToString([Globalization.CultureInfo]::InvariantCulture)),
    ([math]::Round([double]$FadeOutSec,3).ToString([Globalization.CultureInfo]::InvariantCulture))
  ))
}

if ($Text) {
  $xExpr = "(w-text_w)/2"
  $yExpr = "h-text_h-{0}" -f [int]$TextMarginV
  if ($TextPos -eq "top")    { $yExpr = "{0}" -f [int]$TextMarginV }
  if ($TextPos -eq "center") { $yExpr = "(h-text_h)/2" }

  $t = ($Text -as [string]) -replace "'", "\'"
  $dt = "drawtext=text='{0}':x={1}:y={2}:fontsize={3}:fontcolor={4}:box={5}:boxcolor={6}" -f `
    $t, $xExpr, $yExpr, [int]$TextSize, $TextColor, ([int]$TextBox), $TextBoxColor

  if ($FontFile) {
    $ff = (Resolve-Path $FontFile).Path -replace "\\","/"
    $dt = "drawtext=fontfile='{0}':text='{1}':x={2}:y={3}:fontsize={4}:fontcolor={5}:box={6}:boxcolor={7}" -f `
      $ff, $t, $xExpr, $yExpr, [int]$TextSize, $TextColor, ([int]$TextBox), $TextBoxColor
  } else {
    $dt = $dt + (":font='{0}'" -f ($Font -replace "'", "\'"))
  }
  $vf.Add($dt)
}

$af = New-Object System.Collections.Generic.List[string]
if ([math]::Abs($Speed - 1.0) -gt 1e-9) {
  $af.Add((Build-Atempo ([double]$Speed)))
}
if ([math]::Abs($GainDb) -gt 1e-9) {
  $af.Add(("volume={0}dB" -f ([math]::Round([double]$GainDb,3).ToString([Globalization.CultureInfo]::InvariantCulture))))
}
if ($FadeInSec -gt 0) {
  $af.Add(("afade=t=in:st=0:d={0}" -f ([math]::Round([double]$FadeInSec,3).ToString([Globalization.CultureInfo]::InvariantCulture))))
}
if ($FadeOutSec -gt 0 -and $dur2 -gt 0) {
  $st = [math]::Max(0.0, $dur2 - [double]$FadeOutSec)
  $af.Add(("afade=t=out:st={0}:d={1}" -f
    ([math]::Round($st,3).ToString([Globalization.CultureInfo]::InvariantCulture)),
    ([math]::Round([double]$FadeOutSec,3).ToString([Globalization.CultureInfo]::InvariantCulture))
  ))
}
if ($Loudnorm) {
  $af.Add("loudnorm=I=-16:TP=-1.5:LRA=11")
}

$vfStr = ($vf -join ",")
$afStr = ($af -join ",")

$useComplex = $false
if ($Watermark) {
  Must-File $Watermark
  $Watermark = (Resolve-Path $Watermark).Path
  $useComplex = $true
}

Write-Host ""
Write-Host "EDIT -> needReencode=$needReencode complex=$useComplex" -ForegroundColor Cyan
Write-Host "IN : $InVideo" -ForegroundColor DarkGray
Write-Host "OUT: $OutVideo" -ForegroundColor DarkGray

$args = @("-nostdin","-y")
if ($start -gt 0) { $args += @("-ss", ([math]::Round($start,3).ToString([Globalization.CultureInfo]::InvariantCulture))) }
$args += @("-i", $InVideo)
if ($useComplex) { $args += @("-i", $Watermark) }
if ($end -gt 0)  { $args += @("-to", ([math]::Round($end,3).ToString([Globalization.CultureInfo]::InvariantCulture))) }

if ($useComplex) {
  $fc = New-Object System.Collections.Generic.List[string]
  if ($vfStr) { $fc.Add("[0:v]$vfStr[v0]"); $vSrc = "[v0]" } else { $vSrc = "[0:v]" }

  $fc.Add(("[1:v]scale={0}:-1[wm]" -f [int]$WmW))

  $x = "$WmMargin"; $y = "$WmMargin"
  if ($WmPos -eq "tr") { $x = "W-w-$WmMargin"; $y = "$WmMargin" }
  if ($WmPos -eq "bl") { $x = "$WmMargin"; $y = "H-h-$WmMargin" }
  if ($WmPos -eq "br") { $x = "W-w-$WmMargin"; $y = "H-h-$WmMargin" }

  $fc.Add(("{0}[wm]overlay=x={1}:y={2}[v]" -f $vSrc, $x, $y))
  if ($afStr) { $fc.Add(("[0:a]{0}[a]" -f $afStr)) }

  $args += @("-filter_complex", ($fc -join ";"))
  $args += @("-map","[v]")
  if ($afStr) { $args += @("-map","[a]") } else { $args += @("-map","0:a?") }
} else {
  if ($vfStr) { $args += @("-vf", $vfStr) }
  if ($afStr) { $args += @("-af", $afStr) }
}

if ($needReencode -or $useComplex -or $vfStr -or $afStr -or $start -gt 0 -or $end -gt 0) {
  $args += @(
    "-c:v","libx264","-crf",[string]$Crf,"-preset",$Preset,
    "-pix_fmt","yuv420p","-movflags","+faststart",
    "-c:a","aac","-b:a","192k","-ac","2","-ar","48000",
    "-map_metadata","-1","-map_chapters","-1",
    "-metadata","creation_time=1980-01-01T00:00:00Z",
    "-metadata","comment=STUDIO_MVP"
  )
} else {
  $args += @("-c","copy")
}

$args += @($OutVideo)

Write-Host ("RUN: ffmpeg " + ($args -join " ")) -ForegroundColor DarkGray
& ffmpeg @args
if ($LASTEXITCODE -ne 0) { throw "ffmpeg falló (exit=$LASTEXITCODE)" }

Write-Host "OK: generado -> $OutVideo" -ForegroundColor Green