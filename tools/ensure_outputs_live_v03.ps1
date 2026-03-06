param(
  [Parameter(Mandatory=$false)][string]$LiveDir,
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot,
  [int]$Seed = 123,
  [double]$MusicVolume = 0.18
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

if (-not $LiveDir -or $LiveDir.Trim().Length -eq 0) {
  if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) {
    throw "Falta -LiveDir o -WorkspaceRoot"
  }
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}

$live = (Resolve-Path $LiveDir).Path
if (-not (Test-Path -LiteralPath $live)) { throw "No existe LIVE: $live" }

$videoBase      = Join-Path $live "video.mp4"
$musicAuto      = Join-Path $live "video_music_auto.mp4"
$final          = Join-Path $live "video_final.mp4"
$videoSubtitles = Join-Path $live "video_subtitles.mp4"
$videoSubs      = Join-Path $live "video_subs.mp4"
$srt            = Join-Path $live "captions_v03.srt"

if (-not (Test-Path -LiteralPath $videoBase)) {
  throw "Falta video.mp4 en LIVE: $videoBase"
}
if (-not (Test-Path -LiteralPath $srt)) {
  throw "Falta captions_v03.srt en LIVE: $srt"
}
if (-not (Test-Path -LiteralPath $videoSubtitles)) {
  throw "Falta video_subtitles.mp4 en LIVE: $videoSubtitles"
}
if (-not (Test-Path -LiteralPath $videoSubs)) {
  throw "Falta video_subs.mp4 en LIVE: $videoSubs"
}

$resolveMusic = Join-Path $repo "tools\resolve_music_bed_v03.ps1"
$mixMusic     = Join-Path $repo "tools\mix_music_into_video_v03.ps1"

if (-not (Test-Path -LiteralPath $resolveMusic)) { throw "Falta tool: $resolveMusic" }
if (-not (Test-Path -LiteralPath $mixMusic))     { throw "Falta tool: $mixMusic" }

$musicInfoJson = pwsh -NoProfile -ExecutionPolicy Bypass -File $resolveMusic -LiveDir $live -Seed $Seed
$musicInfo = $musicInfoJson | ConvertFrom-Json

$didRealMusic = $false
$musicSource = ""
$musicNote = ""

if ($musicInfo.found -and $musicInfo.path -and (Test-Path -LiteralPath $musicInfo.path)) {
  $musicSource = (Resolve-Path -LiteralPath $musicInfo.path).Path
  try {
    if (Test-Path -LiteralPath $musicAuto) {
      Remove-Item -LiteralPath $musicAuto -Force -ErrorAction SilentlyContinue
    }

    pwsh -NoProfile -ExecutionPolicy Bypass -File $mixMusic `
      -InVideo $videoBase `
      -MusicBed $musicSource `
      -OutVideo $musicAuto `
      -MusicVolume $MusicVolume | Out-Null

    $mixExit = $LASTEXITCODE
    if ($mixExit -ne 0) {
      throw "mix_music_into_video_v03.ps1 devolvió exit code $mixExit"
    }

    if (-not (Test-Path -LiteralPath $musicAuto)) {
      throw "No apareció video_music_auto.mp4 tras mezclar"
    }

    $didRealMusic = $true
    $musicNote = "mixed_from_local_music_bed"
  }
  catch {
    $didRealMusic = $false
    $musicNote = ("mix_failed -> fallback_copy ({0})" -f $_.Exception.Message)
  }
}
else {
  $musicNote = "no_local_music_bed_found -> fallback_copy"
}

if (-not $didRealMusic) {
  Copy-Item -LiteralPath $videoBase -Destination $musicAuto -Force
  Write-Host "WARN: video_music_auto.mp4 quedó como copia determinista de video.mp4" -ForegroundColor DarkYellow
}

# video_final.mp4:
# por ahora debe representar la salida final más útil del smoke
Copy-Item -LiteralPath $musicAuto -Destination $final -Force

$lenBase = (Get-Item -LiteralPath $videoBase).Length
$lenMusic = (Get-Item -LiteralPath $musicAuto).Length
$lenFinal = (Get-Item -LiteralPath $final).Length
$lenSubs = (Get-Item -LiteralPath $videoSubtitles).Length
$lenSubsLegacy = (Get-Item -LiteralPath $videoSubs).Length
$lenSrt = (Get-Item -LiteralPath $srt).Length

if ($didRealMusic) {
  Write-Host ("OK: music source -> {0}" -f $musicSource) -ForegroundColor DarkGray
} else {
  Write-Host ("WARN: music source unavailable -> {0}" -f $musicNote) -ForegroundColor DarkYellow
}

Write-Host ("OK: ensure outputs live v03 -> video={0} music_auto={1} final={2} subtitles={3} subs_legacy={4} srt={5} realMusic={6}" -f $lenBase, $lenMusic, $lenFinal, $lenSubs, $lenSubsLegacy, $lenSrt, $didRealMusic) -ForegroundColor Green