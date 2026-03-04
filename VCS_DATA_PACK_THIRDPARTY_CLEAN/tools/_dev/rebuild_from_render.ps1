[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$RunId,

  [int]   $FontSize = 34,
  [int]   $MarginV  = 80,

  [int]   $Crf      = 21,
  [ValidateSet("veryfast","faster","fast","medium","slow")][string]$X264Preset = "medium",

  [double]$TrimEndSec = 0.15,
  [double]$FadeOutSec = 0.12,
  [double]$GainDb     = 1.5
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$Repo = Split-Path $PSScriptRoot -Parent

$ws = $env:STUDIO_WORKSPACE
if (-not $ws) { $ws = "$env:USERPROFILE\STUDIO_WORKSPACE" }
$runsDir = Join-Path $ws "runs"
$RunDir = Join-Path $runsDir $RunId
if (Test-Path $RunDir) { $RunDir = (Resolve-Path $RunDir).Path }
$Pack   = Join-Path $RunDir "content_pack"
$renderVid = Join-Path $RunDir "render\video_final.mp4"

if(!(Test-Path $renderVid -PathType Leaf)){ throw "No existe render video: $renderVid" }
if(!(Test-Path $Pack -PathType Container)){ throw "No existe PackDir: $Pack" }

$outDir = Join-Path $Repo "workspace\output"
New-Item -ItemType Directory -Force $outDir | Out-Null

$base   = Join-Path $outDir "video_FINAL_FROM_RENDER_$RunId.mp4"
$pro    = Join-Path $outDir "video_FINAL_PRO_$RunId.mp4"
$edit   = Join-Path $outDir "video_FINAL_PRO_EDIT_$RunId.mp4"
$latest = Join-Path $outDir "video_latest.mp4"

Write-Host "REBUILD (0$) RunId=$RunId" -ForegroundColor Cyan
Write-Host " renderVid: $renderVid" -ForegroundColor DarkGray
Write-Host " outDir   : $outDir" -ForegroundColor DarkGray
Write-Host ""

# 1) Copiar base
Copy-Item $renderVid $base -Force
Write-Host "OK: base -> $base" -ForegroundColor Green

# 2) captions -> SRT (split por cantidad de líneas)
$cap = Join-Path $Pack "captions.txt"
if(!(Test-Path $cap -PathType Leaf)){ throw "No existe captions.txt: $cap" }
$lines = @(Get-Content $cap -Encoding utf8 | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if($lines.Count -eq 0){ throw "captions.txt está vacío" }

$dur = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$base"
if(-not $dur){ throw "ffprobe no devolvió duración (¿ffprobe en PATH?)" }
$durSec = [double]$dur
if($durSec -le 0){ throw "Duración inválida: $durSec" }

function TS([double]$s){
  if($s -lt 0){ $s = 0 }
  $h = [int]($s/3600); $s -= 3600*$h
  $m = [int]($s/60);   $s -= 60*$m
  $sec = [int]$s
  $ms = [int](([math]::Round(($s-$sec)*1000)))
  "{0:00}:{1:00}:{2:00},{3:000}" -f $h,$m,$sec,$ms
}

$srt = Join-Path $outDir "subtitles_auto.srt"
$chunk = $durSec / [double]$lines.Count
$srtOut = New-Object System.Collections.Generic.List[string]
for($i=0; $i -lt $lines.Count; $i++){
  $st = $i*$chunk
  $en = [math]::Min(($i+1)*$chunk, $durSec-0.05)
  $srtOut.Add(($i+1).ToString())
  $srtOut.Add(("{0} --> {1}" -f (TS $st),(TS $en)))
  $srtOut.Add($lines[$i])
  $srtOut.Add("")
}
$srtOut | Set-Content -Path $srt -Encoding utf8
Write-Host "OK: SRT -> $srt" -ForegroundColor Green

# ffmpeg subtitles necesita ruta con / y el ":" escapado: C\:/...
$srtFF = ($srt -replace '\\','/')
$srtFF = ($srtFF -replace '^([A-Za-z]):','${1}\:')

# 3) PRO: menos grano (NO unsharp), denoise suave, mejor compresión (CRF + preset)
$vf = "eq=contrast=1.05:saturation=1.05:brightness=0.01,hqdn3d=1.6:1.6:6:6,subtitles='$srtFF':force_style='Fontname=Arial,Fontsize=$FontSize,Outline=2,Shadow=0,MarginV=$MarginV'"
$af = "afftdn,highpass=f=80,lowpass=f=12000,acompressor=threshold=-18dB:ratio=3:attack=10:release=150,alimiter=limit=-1.0dB,loudnorm=I=-16:TP=-1.5:LRA=11"

Write-Host "`nRUN: ffmpeg PRO (CRF=$Crf preset=$X264Preset)..." -ForegroundColor Cyan
ffmpeg -nostdin -y -i "$base" -vf $vf -c:v libx264 -crf $Crf -preset $X264Preset -pix_fmt yuv420p -movflags +faststart `
  -af $af -c:a aac -b:a 192k -ac 2 -ar 48000 "$pro"
if($LASTEXITCODE -ne 0){ throw "ffmpeg PRO falló (exit=$LASTEXITCODE)." }
Write-Host "OK: PRO -> $pro" -ForegroundColor Green

# 4) PRO_EDIT: trim + fade out
$to = [math]::Max(0.1, $durSec - $TrimEndSec)
$stFade = [math]::Max(0.0, $to - $FadeOutSec)

Write-Host "`nRUN: ffmpeg PRO_EDIT ..." -ForegroundColor Cyan
ffmpeg -nostdin -y -i "$pro" -to ("{0:0.00}" -f $to) `
  -vf ("fade=t=out:st={0:0.00}:d={1:0.00}" -f $stFade,$FadeOutSec) `
  -af ("volume={0}dB,afade=t=out:st={1:0.00}:d={2:0.00}" -f $GainDb,$stFade,$FadeOutSec) `
  -c:v libx264 -crf $Crf -preset $X264Preset -pix_fmt yuv420p -movflags +faststart `
  -c:a aac -b:a 192k -ac 2 -ar 48000 `
  -map_metadata -1 -map_chapters -1 -metadata creation_time=1980-01-01T00:00:00Z -metadata comment=STUDIO_MVP `
  "$edit"
if($LASTEXITCODE -ne 0){ throw "ffmpeg PRO_EDIT falló (exit=$LASTEXITCODE)." }
Write-Host "OK: PRO_EDIT -> $edit" -ForegroundColor Green

Copy-Item $edit $latest -Force
Write-Host "OK: latest -> $latest" -ForegroundColor Green

Write-Host "`nLISTO. (Esto NO usa API: solo ffmpeg/ffprobe + archivos existentes)" -ForegroundColor Green