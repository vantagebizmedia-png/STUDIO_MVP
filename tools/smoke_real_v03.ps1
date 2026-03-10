param(
  [string]$ConfigPath = ".\config\studio_v03_real_probe.json",
  [string]$ScriptText = "Crea un video corto en español sobre 3 hábitos para tener más disciplina, con introducción fuerte, desarrollo claro y cierre accionable.",
  [string]$LiveDir = ".\_v03_real_probe\artifacts",
  [switch]$WithMusic
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Fail([string]$m) { throw "SMOKE_REAL_V03 FAIL: $m" }

$repo = (Resolve-Path ".").Path
$configAbs = (Resolve-Path $ConfigPath).Path

if (-not (Test-Path -LiteralPath $configAbs)) {
  Fail "No existe config: $configAbs"
}

if ([string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
  Fail "Falta OPENAI_API_KEY en el entorno"
}

if ([string]::IsNullOrWhiteSpace($env:PIXABAY_API_KEY)) {
  Fail "Falta PIXABAY_API_KEY en el entorno"
}

$liveAbs = [System.IO.Path]::GetFullPath((Join-Path $repo $LiveDir))

Write-Host "== SMOKE REAL V0.3 ==" -ForegroundColor Cyan
Write-Host "Repo      : $repo"
Write-Host "Config    : $configAbs"
Write-Host "LiveDir   : $liveAbs"
Write-Host "WithMusic : $WithMusic"

if (Test-Path -LiteralPath $liveAbs) {
  Remove-Item -LiteralPath $liveAbs -Recurse -Force
}

$env:STUDIO_ALLOW_LIVE = "1"
try {
  & python -m cli.main --v03-config $configAbs --script $ScriptText
  if ($LASTEXITCODE -ne 0) {
    Fail "cli.main devolvió exit code $LASTEXITCODE"
  }
}
finally {
  Remove-Item Env:STUDIO_ALLOW_LIVE -ErrorAction SilentlyContinue
}

$manifestPath = Join-Path $liveAbs "manifest_v03.json"
$packJsonPath = Join-Path $liveAbs "pack.json"
$subtitlesPath = Join-Path $liveAbs "subtitles.srt"
$captionsPath = Join-Path $liveAbs "captions_v03.srt"
$videoBase = Join-Path $liveAbs "video.mp4"
$videoSubs = Join-Path $liveAbs "video_subs.mp4"
$videoMusic = Join-Path $liveAbs "video_music_auto.mp4"
$videoFinal = Join-Path $liveAbs "video_final.mp4"
$handoffDir = Join-Path $liveAbs "handoff_v03"
$handoffZip = Join-Path $handoffDir "handoff_v03.zip"

if (-not (Test-Path -LiteralPath $manifestPath)) {
  Fail "No existe manifest_v03.json"
}

Write-Host ""
Write-Host "== PACK.JSON DESDE scenes_v03 ==" -ForegroundColor Cyan

$m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$scenes = @($m.scenes_v03)
if ($scenes.Count -lt 1) {
  Fail "manifest_v03.json no tiene scenes_v03"
}

$packScenes = @()
foreach ($sc in $scenes) {
  $imgRel = [string]$sc.assets.image
  $audRel = [string]$sc.assets.audio_clip

  if ([string]::IsNullOrWhiteSpace($imgRel)) { Fail "Escena sin assets.image" }
  if ([string]::IsNullOrWhiteSpace($audRel)) { Fail "Escena sin assets.audio_clip" }

  $imgAbs = Join-Path $liveAbs ($imgRel -replace '/', '\')
  $audAbs = Join-Path $liveAbs ($audRel -replace '/', '\')

  if (-not (Test-Path -LiteralPath $imgAbs)) { Fail "No existe imagen: $imgAbs" }
  if (-not (Test-Path -LiteralPath $audAbs)) { Fail "No existe audio: $audAbs" }

  $packScenes += [pscustomobject]@{
    index = ([int]$sc.index + 1)
    image = $imgRel
    audio = $audRel
  }
}

$packObj = [pscustomobject]@{
  version = "v0.3"
  scenes  = $packScenes
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$json = $packObj | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($packJsonPath, ($json -replace "`r`n","`n"), $utf8NoBom)

Write-Host "OK: pack.json creado" -ForegroundColor Green

Write-Host ""
Write-Host "== RENDER BASE ==" -ForegroundColor Cyan
& python -u .\tools\render_pack_v03.py --pack-dir $liveAbs --w 1080 --h 1920 --fps 30 --fit crop
if ($LASTEXITCODE -ne 0) { Fail "render_pack_v03.py falló" }
if (-not (Test-Path -LiteralPath $videoBase)) { Fail "No se generó video.mp4" }

Write-Host ""
Write-Host "== CAPTIONS ==" -ForegroundColor Cyan
if (Test-Path -LiteralPath $subtitlesPath) {
  Copy-Item -LiteralPath $subtitlesPath -Destination $captionsPath -Force
}
elseif (-not (Test-Path -LiteralPath $captionsPath)) {
  Fail "No existe subtitles.srt ni captions_v03.srt"
}

Write-Host ""
Write-Host "== BURN-IN SUBTITLES ==" -ForegroundColor Cyan
& pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\apply_subtitles_live_v03.ps1 -LiveDir $liveAbs
if ($LASTEXITCODE -ne 0) { Fail "apply_subtitles_live_v03.ps1 falló" }
if (-not (Test-Path -LiteralPath $videoSubs)) { Fail "No se generó video_subs.mp4" }

if ($WithMusic) {
  Write-Host ""
  Write-Host "== MUSIC OPTIONAL ==" -ForegroundColor Cyan
  $repoMusicDir = Join-Path $repo "music"
  if (Test-Path -LiteralPath $repoMusicDir) {
    $musicFile = Get-ChildItem -LiteralPath $repoMusicDir -File |
      Where-Object { $_.Extension -in @(".mp3",".wav") } |
      Sort-Object Name |
      Select-Object -First 1

    if ($musicFile) {
      $targetMusic = Join-Path $liveAbs ("music" + $musicFile.Extension.ToLowerInvariant())
      Copy-Item -LiteralPath $musicFile.FullName -Destination $targetMusic -Force
      Write-Host "OK: música copiada => $targetMusic" -ForegroundColor Green
    }
    else {
      Write-Host "WARN: carpeta music existe pero no contiene .mp3/.wav" -ForegroundColor Yellow
    }
  }
  else {
    Write-Host "WARN: no existe carpeta music/" -ForegroundColor Yellow
  }
}

Write-Host ""
Write-Host "== ENSURE OUTPUTS ==" -ForegroundColor Cyan
& pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\ensure_outputs_live_v03.ps1 -LiveDir $liveAbs
if ($LASTEXITCODE -ne 0) { Fail "ensure_outputs_live_v03.ps1 falló" }

Write-Host ""
Write-Host "== FINALIZE HANDOFF ==" -ForegroundColor Cyan
& pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\finalize_handoff_v03.ps1 -LiveDir $liveAbs -Force
if ($LASTEXITCODE -ne 0) { Fail "finalize_handoff_v03.ps1 falló" }

Write-Host ""
Write-Host "== HANDOFF PACK ==" -ForegroundColor Cyan
& pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\handoff_pack_v03.ps1 -InDir $handoffDir -OutZip $handoffZip
if ($LASTEXITCODE -ne 0) { Fail "handoff_pack_v03.ps1 falló" }

if (-not (Test-Path -LiteralPath $videoBase))   { Fail "Falta video.mp4" }
if (-not (Test-Path -LiteralPath $videoSubs))   { Fail "Falta video_subs.mp4" }
if (-not (Test-Path -LiteralPath $videoMusic))  { Fail "Falta video_music_auto.mp4" }
if (-not (Test-Path -LiteralPath $videoFinal))  { Fail "Falta video_final.mp4" }
if (-not (Test-Path -LiteralPath $captionsPath)){ Fail "Falta captions_v03.srt" }
if (-not (Test-Path -LiteralPath $handoffZip))  { Fail "Falta handoff_v03.zip" }

Write-Host ""
Write-Host "== RESUMEN FINAL ==" -ForegroundColor Green
Get-ChildItem -LiteralPath $liveAbs -File |
  Where-Object { $_.Name -in @("video.mp4","video_subs.mp4","video_music_auto.mp4","video_final.mp4","captions_v03.srt","subtitles.srt","pack.json","manifest_v03.json") } |
  Sort-Object Name |
  Select-Object Name, Length, LastWriteTime

Write-Host ""
Get-ChildItem -LiteralPath $handoffDir -File |
  Sort-Object Name |
  Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "SMOKE OK: REAL v0.3 (text + voice + pixabay + render + subtitles + outputs + handoff)" -ForegroundColor Green
