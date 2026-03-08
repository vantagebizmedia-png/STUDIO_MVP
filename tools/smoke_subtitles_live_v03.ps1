param(
  [Parameter(Mandatory=$true)][string]$LiveDir,
  [int]$MaxScenes = 40
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Fail([string]$msg) { throw "SMOKE FAIL: $msg" }

$live = (Resolve-Path $LiveDir).Path

$manifestPath = Join-Path $live "manifest_v03.json"
$captionsV03  = Join-Path $live "captions_v03.srt"
$legacySrt    = Join-Path $live "subtitles.srt"
$videoSubs    = Join-Path $live "video_subs.mp4"

if (-not (Test-Path -LiteralPath $manifestPath)) {
  Fail "Falta manifest_v03.json: $manifestPath"
}

if (-not (Test-Path -LiteralPath $captionsV03)) {
  Fail "Falta output LIVE requerido: $captionsV03"
}

if (-not (Test-Path -LiteralPath $videoSubs)) {
  Fail "Falta output LIVE requerido: $videoSubs"
}

$captionsItem = Get-Item -LiteralPath $captionsV03
if ($captionsItem.PSIsContainer -or $captionsItem.Length -le 0) {
  Fail "captions_v03.srt inválido o vacío: $captionsV03"
}

$videoSubsItem = Get-Item -LiteralPath $videoSubs
if ($videoSubsItem.PSIsContainer -or $videoSubsItem.Length -le 0) {
  Fail "video_subs.mp4 inválido o vacío: $videoSubs"
}

if (Test-Path -LiteralPath $legacySrt) {
  $legacyItem = Get-Item -LiteralPath $legacySrt
  if ($legacyItem.PSIsContainer -or $legacyItem.Length -le 0) {
    Fail "subtitles.srt legacy inválido o vacío: $legacySrt"
  }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

$scenes = $null
if ($null -ne $manifest.PSObject.Properties["scenes_v03"]) {
  $scenes = @($manifest.scenes_v03)
}
elseif ($null -ne $manifest.PSObject.Properties["scenes"]) {
  $scenes = @($manifest.scenes)
}
else {
  Fail "El manifest no contiene scenes_v03 ni scenes"
}

if ($scenes.Count -le 0) {
  Fail "El manifest no contiene escenas"
}

if ($scenes.Count -gt $MaxScenes) {
  Fail "Cantidad de escenas excede MaxScenes. scenes=$($scenes.Count) max=$MaxScenes"
}

$srtText = Get-Content -LiteralPath $captionsV03 -Raw -Encoding UTF8
if ([string]::IsNullOrWhiteSpace($srtText)) {
  Fail "captions_v03.srt está vacío"
}

$timeMatches = [regex]::Matches($srtText, '\d{2}:\d{2}:\d{2},\d{3}\s+-->\s+\d{2}:\d{2}:\d{2},\d{3}')
if ($timeMatches.Count -le 0) {
  Fail "captions_v03.srt no contiene timestamps válidos"
}

Write-Host ("SMOKE OK: LIVE subtitles v03 + assets (image|video). live={0} scenes={1}" -f $live, $scenes.Count) -ForegroundColor Green