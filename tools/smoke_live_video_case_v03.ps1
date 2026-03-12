param(
  [Parameter(Mandatory=$false)][string]$RepoRoot = "C:\Users\vanta\Documents\STUDIO_MVP",
  [Parameter(Mandatory=$false)][string]$SourceLiveDir = "C:\Users\vanta\Documents\STUDIO_WORKSPACE\runs\smoke_live_latest",
  [Parameter(Mandatory=$false)][string]$OutputLiveDir = "C:\Users\vanta\Documents\STUDIO_WORKSPACE\runs\smoke_live_video_case"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
  throw "No existe RepoRoot: $RepoRoot"
}

if (-not (Test-Path -LiteralPath $SourceLiveDir -PathType Container)) {
  throw "No existe SourceLiveDir: $SourceLiveDir"
}

$writePack = Join-Path $RepoRoot "tools\write_pack_compat_v03.ps1"
$smoke     = Join-Path $RepoRoot "tools\smoke_live_manifest_v03.ps1"
$renderer  = Join-Path $RepoRoot "tools\render_pack_v03.py"

foreach ($p in @($writePack, $smoke, $renderer)) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
    throw "No existe requerido: $p"
  }
}

Write-Host "== Reset LIVE de prueba video ==" -ForegroundColor Cyan
if (Test-Path -LiteralPath $OutputLiveDir) {
  Remove-Item -LiteralPath $OutputLiveDir -Recurse -Force
}
Copy-Item -LiteralPath $SourceLiveDir -Destination $OutputLiveDir -Recurse -Force

$sceneDir     = Join-Path $OutputLiveDir "artifacts\scenes\scene_01"
$imagePath    = Join-Path $sceneDir "image.png"
$audioPath    = Join-Path $OutputLiveDir "assets\audio_clips\s01.wav"
$videoPath    = Join-Path $sceneDir "video.mp4"
$manifestPath = Join-Path $OutputLiveDir "manifest_v03.json"
$packPath     = Join-Path $OutputLiveDir "pack.json"
$renderOut    = Join-Path $OutputLiveDir "video_render_video_case.mp4"

foreach ($p in @($sceneDir, $imagePath, $audioPath, $manifestPath)) {
  if (-not (Test-Path -LiteralPath $p)) {
    throw "No existe requerido dentro del LIVE clonado: $p"
  }
}

if (Test-Path -LiteralPath $videoPath) {
  Remove-Item -LiteralPath $videoPath -Force
}

if (Test-Path -LiteralPath $renderOut) {
  Remove-Item -LiteralPath $renderOut -Force
}

Write-Host "== Creando video real para scene_01 ==" -ForegroundColor Cyan
& ffmpeg `
  -hide_banner `
  -loglevel error `
  -y `
  -loop 1 `
  -i $imagePath `
  -i $audioPath `
  -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,format=yuv420p" `
  -r 30 `
  -map 0:v:0 `
  -map 1:a:0 `
  -c:v libx264 `
  -pix_fmt yuv420p `
  -preset medium `
  -crf 18 `
  -c:a aac `
  -b:a 192k `
  -ar 44100 `
  -ac 2 `
  -shortest `
  -movflags +faststart `
  -map_metadata -1 `
  -map_chapters -1 `
  $videoPath

if ($LASTEXITCODE -ne 0) {
  throw "ffmpeg falló creando el video de prueba"
}

if (-not (Test-Path -LiteralPath $videoPath -PathType Leaf)) {
  throw "No se creó video.mp4 de prueba: $videoPath"
}

$videoItem = Get-Item -LiteralPath $videoPath
if ($videoItem.Length -lt 10000) {
  throw "video.mp4 de prueba demasiado pequeño: $($videoItem.Length) bytes"
}

Write-Host "== Parcheando manifest_v03 del LIVE clonado a visual_kind=video ==" -ForegroundColor Cyan
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $manifest.scenes_v03 -or @($manifest.scenes_v03).Count -lt 1) {
  throw "manifest_v03.json no contiene scenes_v03 válidas"
}

$scene1 = @($manifest.scenes_v03)[0]
if (-not $scene1.assets) {
  throw "scene_001 no tiene assets"
}

$scene1.assets.image = ""
$scene1.assets.video = "artifacts/scenes/scene_01/video.mp4"
$scene1.visual_kind = "video"
$scene1.visual_source_kind = "stock_video"
$scene1.visual_capability = "stock_video"

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
  $manifestPath,
  ($manifest | ConvertTo-Json -Depth 50),
  $utf8NoBom
)

Write-Host "== Reescribiendo pack compat ==" -ForegroundColor Cyan
& $writePack -LiveDir $OutputLiveDir
if ($LASTEXITCODE -ne 0) {
  throw "write_pack_compat_v03.ps1 devolvió exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $packPath -PathType Leaf)) {
  throw "No se generó pack.json: $packPath"
}

Write-Host "== Inspección rápida scene_001 manifest + pack ==" -ForegroundColor Cyan
$manifestCheck = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$packCheck     = Get-Content -LiteralPath $packPath -Raw -Encoding UTF8 | ConvertFrom-Json

$m1 = @($manifestCheck.scenes_v03)[0]
$p1 = @($packCheck.scenes)[0]

[pscustomobject]@{
  source      = "manifest_v03"
  id          = [string]$m1.id
  visual_kind = [string]$m1.visual_kind
  image       = [string]$m1.assets.image
  video       = [string]$m1.assets.video
  audio       = [string]$m1.assets.audio_clip
},
[pscustomobject]@{
  source      = "pack_json"
  id          = [string]$p1.id
  visual_kind = [string]$p1.visual_kind
  image       = [string]$p1.image
  video       = [string]$p1.video
  audio       = [string]$p1.audio
} | Format-Table -AutoSize

if ([string]$m1.visual_kind -ne "video") {
  throw "manifest_v03 scene_001 no quedó en visual_kind=video"
}
if (-not [string]::IsNullOrWhiteSpace([string]$m1.assets.image)) {
  throw "manifest_v03 scene_001 dejó image no vacío"
}
if ([string]::IsNullOrWhiteSpace([string]$m1.assets.video)) {
  throw "manifest_v03 scene_001 dejó video vacío"
}
if ([string]$p1.visual_kind -ne "video") {
  throw "pack.json scene_001 no quedó en visual_kind=video"
}
if (-not [string]::IsNullOrWhiteSpace([string]$p1.image)) {
  throw "pack.json scene_001 dejó image no vacío"
}
if ([string]::IsNullOrWhiteSpace([string]$p1.video)) {
  throw "pack.json scene_001 dejó video vacío"
}

Write-Host "== Smoke sobre LIVE video-case ==" -ForegroundColor Cyan
& $smoke -LiveDir $OutputLiveDir
if ($LASTEXITCODE -ne 0) {
  throw "smoke_live_manifest_v03.ps1 falló sobre LIVE video-case"
}

Write-Host "== Render real sobre LIVE video-case ==" -ForegroundColor Cyan

$renderStdOut = Join-Path $OutputLiveDir "video_render_video_case.stdout.log"
$renderStdErr = Join-Path $OutputLiveDir "video_render_video_case.stderr.log"

foreach ($logPath in @($renderStdOut, $renderStdErr)) {
  if (Test-Path -LiteralPath $logPath) {
    Remove-Item -LiteralPath $logPath -Force
  }
}

$prevPythonUnbuffered = $null
$hadPythonUnbuffered = Test-Path Env:PYTHONUNBUFFERED
if ($hadPythonUnbuffered) {
  $prevPythonUnbuffered = $env:PYTHONUNBUFFERED
}

$rendererExit = 0
try {
  $env:PYTHONUNBUFFERED = "1"

  $proc = Start-Process `
    -FilePath "py" `
    -ArgumentList @(
      "-u",
      $renderer,
      "--pack-dir", $OutputLiveDir,
      "--out", $renderOut
    ) `
    -NoNewWindow `
    -Wait `
    -PassThru `
    -RedirectStandardOutput $renderStdOut `
    -RedirectStandardError $renderStdErr

  $rendererExit = [int]$proc.ExitCode
}
finally {
  if ($hadPythonUnbuffered) {
    $env:PYTHONUNBUFFERED = $prevPythonUnbuffered
  }
  else {
    Remove-Item Env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue
  }
}

Write-Host "== Renderer stdout log ==" -ForegroundColor DarkCyan
if (Test-Path -LiteralPath $renderStdOut -PathType Leaf) {
  Get-Content -LiteralPath $renderStdOut -Encoding UTF8
}
else {
  Write-Host "(stdout vacío)" -ForegroundColor DarkGray
}

Write-Host "== Renderer stderr log ==" -ForegroundColor DarkCyan
if ((Test-Path -LiteralPath $renderStdErr -PathType Leaf) -and ((Get-Item -LiteralPath $renderStdErr).Length -gt 0)) {
  Get-Content -LiteralPath $renderStdErr -Encoding UTF8
}
else {
  Write-Host "(stderr vacío)" -ForegroundColor DarkGray
}

if ($rendererExit -ne 0) {
  throw "render_pack_v03.py falló sobre LIVE video-case con exit code $rendererExit"
}

if (-not (Test-Path -LiteralPath $renderOut -PathType Leaf)) {
  throw "Renderer no generó salida: $renderOut"
}

$renderItem = Get-Item -LiteralPath $renderOut
if ($renderItem.Length -lt 10000) {
  throw "Render de video-case demasiado pequeño: $($renderItem.Length) bytes"
}

Write-Host "OK: smoke video-case v03 completado" -ForegroundColor Green
Write-Host ("LIVE={0}" -f $OutputLiveDir) -ForegroundColor DarkGray
Write-Host ("VIDEO_ASSET={0}" -f $videoPath) -ForegroundColor DarkGray
Write-Host ("RENDER_OUT={0}" -f $renderOut) -ForegroundColor DarkGray
Write-Host ("VIDEO_ASSET_BYTES={0}" -f $videoItem.Length) -ForegroundColor DarkGray
Write-Host ("RENDER_OUT_BYTES={0}" -f $renderItem.Length) -ForegroundColor DarkGray