param(
  [Parameter(Mandatory=$true)][string]$WorkspaceRoot,
  [Parameter(Mandatory=$false)][string]$RepoRoot = "",
  [Parameter(Mandatory=$false)][string]$SourceLiveDir = "",
  [Parameter(Mandatory=$false)][string]$OutputLiveDir = "",
  [Parameter(Mandatory=$false)][int]$Seed = 123
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NormalizedRelativePath {
  param(
    [Parameter(Mandatory=$true)][string]$BaseDir,
    [Parameter(Mandatory=$true)][string]$Path
  )

  $baseFull = [System.IO.Path]::GetFullPath($BaseDir)
  $pathFull = [System.IO.Path]::GetFullPath($Path)

  $baseSep = [System.IO.Path]::DirectorySeparatorChar
  $altSep = [System.IO.Path]::AltDirectorySeparatorChar

  if ((-not $baseFull.EndsWith($baseSep)) -and (-not $baseFull.EndsWith($altSep))) {
    $baseFull += $baseSep
  }

  $baseUri = [System.Uri]::new($baseFull)
  $pathUri = [System.Uri]::new($pathFull)

  if ($baseUri.Scheme -ne $pathUri.Scheme) {
    return ($pathFull -replace '\\','/').Trim()
  }

  $relUri = $baseUri.MakeRelativeUri($pathUri)
  $rel = [System.Uri]::UnescapeDataString($relUri.ToString())

  return ($rel -replace '\\','/').Trim()
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = Split-Path -Parent $PSScriptRoot
}

if ([string]::IsNullOrWhiteSpace($SourceLiveDir)) {
  $SourceLiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}

if ([string]::IsNullOrWhiteSpace($OutputLiveDir)) {
  $OutputLiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_intent_video_fallback"
}

$applyBuilder = Join-Path $RepoRoot "tools\apply_scene_builder_v03.ps1"
$smokeManifest = Join-Path $RepoRoot "tools\smoke_live_manifest_v03.ps1"
$packPathName = "pack.json"
$manifestName = "manifest_v03.json"

foreach ($path in @($RepoRoot, $WorkspaceRoot, $SourceLiveDir, $applyBuilder, $smokeManifest)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "No existe ruta requerida: $path"
  }
}

Write-Host "== Reset LIVE de prueba intent->video fallback ==" -ForegroundColor Cyan
if (Test-Path -LiteralPath $OutputLiveDir) {
  Remove-Item -LiteralPath $OutputLiveDir -Recurse -Force
}
Copy-Item -LiteralPath $SourceLiveDir -Destination $OutputLiveDir -Recurse -Force

$manifestPath = Join-Path $OutputLiveDir $manifestName
$packPath = Join-Path $OutputLiveDir $packPathName

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "No existe manifest clonado: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$scenes = @($manifest.scenes_v03)

if ($scenes.Count -lt 1) {
  throw "manifest_v03.json no contiene scenes_v03 válidas"
}

$scene1 = $scenes[0]
if (-not $scene1) {
  throw "scene_001 no existe"
}

if (-not $scene1.assets) {
  $scene1 | Add-Member -Force -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{})
}

if (-not ($scene1.assets.PSObject.Properties.Name -contains "audio_clip")) {
  $scene1.assets | Add-Member -Force -NotePropertyName audio_clip -NotePropertyValue ""
}
if (-not ($scene1.assets.PSObject.Properties.Name -contains "image")) {
  $scene1.assets | Add-Member -Force -NotePropertyName image -NotePropertyValue ""
}
if (-not ($scene1.assets.PSObject.Properties.Name -contains "video")) {
  $scene1.assets | Add-Member -Force -NotePropertyName video -NotePropertyValue ""
}

$scene01Dir = Join-Path $OutputLiveDir "artifacts\scenes\scene_01"
if (-not (Test-Path -LiteralPath $scene01Dir -PathType Container)) {
  throw "No existe carpeta scene_01: $scene01Dir"
}

$imageCandidates = @(
  (Join-Path $scene01Dir "image.png"),
  (Join-Path $scene01Dir "image.jpg"),
  (Join-Path $scene01Dir "image.jpeg"),
  (Join-Path $scene01Dir "image.webp")
)

$imageAbs = ""
foreach ($candidate in $imageCandidates) {
  if (Test-Path -LiteralPath $candidate -PathType Leaf) {
    $imageAbs = (Resolve-Path -LiteralPath $candidate).Path
    break
  }
}

if ([string]::IsNullOrWhiteSpace($imageAbs)) {
  throw "scene_001 no tiene imagen base para fabricar video en: $scene01Dir"
}

$audioCandidates = New-Object System.Collections.Generic.List[string]

if (-not [string]::IsNullOrWhiteSpace([string]$scene1.assets.audio_clip)) {
  $audioCandidates.Add((Join-Path $OutputLiveDir (([string]$scene1.assets.audio_clip) -replace '/', '\')))
}

$audioCandidates.Add((Join-Path $OutputLiveDir "assets\audio_clips\s01.wav"))

$audioAbs = ""
foreach ($candidate in $audioCandidates) {
  if (Test-Path -LiteralPath $candidate -PathType Leaf) {
    $audioAbs = (Resolve-Path -LiteralPath $candidate).Path
    break
  }
}

if ([string]::IsNullOrWhiteSpace($audioAbs)) {
  throw "scene_001 no tiene audio resoluble para fabricar video de fallback"
}

$videoPath = Join-Path $scene01Dir "video.mp4"
if (Test-Path -LiteralPath $videoPath -PathType Leaf) {
  Remove-Item -LiteralPath $videoPath -Force
}

Write-Host "== Creando video real para scene_001 ==" -ForegroundColor Cyan
& ffmpeg `
  -hide_banner `
  -loglevel error `
  -y `
  -loop 1 `
  -i $imageAbs `
  -i $audioAbs `
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
  throw "ffmpeg falló creando el video de fallback"
}

if (-not (Test-Path -LiteralPath $videoPath -PathType Leaf)) {
  throw "No se creó video.mp4 de fallback: $videoPath"
}

$videoItem = Get-Item -LiteralPath $videoPath
if ($videoItem.Length -lt 10000) {
  throw "video.mp4 de fallback demasiado pequeño: $($videoItem.Length) bytes"
}

Get-ChildItem -LiteralPath $scene01Dir -File -ErrorAction Stop |
  Where-Object { $_.BaseName -eq "image" -and $_.Extension -in @(".png",".jpg",".jpeg",".webp") } |
  Remove-Item -Force

$imageStillExists = Get-ChildItem -LiteralPath $scene01Dir -File -ErrorAction Stop |
  Where-Object { $_.BaseName -eq "image" -and $_.Extension -in @(".png",".jpg",".jpeg",".webp") }

if (@($imageStillExists).Count -gt 0) {
  throw "scene_001 aún conserva imagen resoluble después del reset de fallback"
}

$videoRel = Get-NormalizedRelativePath -BaseDir $OutputLiveDir -Path $videoPath

Write-Host "== Preparando scene_001 con intención image pero sin image resoluble ==" -ForegroundColor Cyan
$scene1.requested_media_type = "image"
$scene1.visual_request_kind = "image"
$scene1.visual_kind = ""
$scene1.visual_source_kind = ""
$scene1.visual_capability = ""
$scene1.assets.image = ""
$scene1.assets.video = $videoRel

if (-not ($scene1.PSObject.Properties.Name -contains "meta") -or -not $scene1.meta) {
  $scene1 | Add-Member -Force -NotePropertyName meta -NotePropertyValue ([pscustomobject]@{})
}
if ($scene1.meta.PSObject.Properties.Name -contains "visual_enrich") {
  $scene1.meta.visual_enrich = [pscustomobject]@{}
}

$manifest.scenes_v03 = @($scenes)

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
  $manifestPath,
  ($manifest | ConvertTo-Json -Depth 99),
  $utf8NoBom
)

Write-Host "== Ejecutando apply_scene_builder_v03 sobre LIVE clonado ==" -ForegroundColor Cyan
& $applyBuilder -PackDir $OutputLiveDir -Seed $Seed
if ($LASTEXITCODE -ne 0) {
  throw "apply_scene_builder_v03.ps1 devolvió exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "No existe manifest luego de apply_scene_builder_v03: $manifestPath"
}
if (-not (Test-Path -LiteralPath $packPath -PathType Leaf)) {
  throw "No existe pack.json luego de apply_scene_builder_v03: $packPath"
}

$manifestCheck = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$packCheck = Get-Content -LiteralPath $packPath -Raw -Encoding UTF8 | ConvertFrom-Json

$m1 = @($manifestCheck.scenes_v03)[0]
$p1 = @($packCheck.scenes)[0]

Write-Host "== Inspección scene_001 manifest + pack ==" -ForegroundColor Cyan
[pscustomobject]@{
  source               = "manifest_v03"
  id                   = [string]$m1.id
  requested_media_type = [string]$m1.requested_media_type
  visual_request_kind  = [string]$m1.visual_request_kind
  visual_kind          = [string]$m1.visual_kind
  visual_source_kind   = [string]$m1.visual_source_kind
  visual_capability    = [string]$m1.visual_capability
  start_ms             = [int]$m1.start_ms
  end_ms               = [int]$m1.end_ms
  duration_ms          = [int]$m1.duration_ms
  image                = [string]$m1.assets.image
  video                = [string]$m1.assets.video
  audio                = [string]$m1.assets.audio_clip
},
[pscustomobject]@{
  source               = "pack_json"
  id                   = [string]$p1.id
  requested_media_type = [string]$p1.requested_media_type
  visual_request_kind  = [string]$p1.visual_request_kind
  visual_kind          = [string]$p1.visual_kind
  visual_source_kind   = [string]$p1.visual_source_kind
  visual_capability    = [string]$p1.visual_capability
  start_ms             = [int]$p1.start_ms
  end_ms               = [int]$p1.end_ms
  duration_ms          = [int]$p1.duration_ms
  image                = [string]$p1.image
  video                = [string]$p1.video
  audio                = [string]$p1.audio
} | Format-Table -AutoSize

if ([string]$m1.requested_media_type -ne "image") {
  throw "manifest_v03 scene_001 no preservó requested_media_type=image"
}
if ([string]$m1.visual_request_kind -ne "image") {
  throw "manifest_v03 scene_001 no preservó visual_request_kind=image"
}
if ([string]$m1.visual_kind -ne "video") {
  throw "manifest_v03 scene_001 no resolvió visual_kind=video"
}
if ([string]$m1.visual_source_kind -ne "stock_video") {
  throw "manifest_v03 scene_001 no resolvió visual_source_kind=stock_video"
}
if ([string]$m1.visual_capability -ne "stock_video") {
  throw "manifest_v03 scene_001 no resolvió visual_capability=stock_video"
}
if ([int]$m1.duration_ms -ne ([int]$m1.end_ms - [int]$m1.start_ms)) {
  throw "manifest_v03 scene_001 dejó duration_ms inconsistente"
}
if (-not [string]::IsNullOrWhiteSpace([string]$m1.assets.image)) {
  throw "manifest_v03 scene_001 dejó image no vacío"
}
if ([string]::IsNullOrWhiteSpace([string]$m1.assets.video)) {
  throw "manifest_v03 scene_001 dejó video vacío"
}

if ([string]$p1.requested_media_type -ne "image") {
  throw "pack.json scene_001 no preservó requested_media_type=image"
}
if ([string]$p1.visual_request_kind -ne "image") {
  throw "pack.json scene_001 no preservó visual_request_kind=image"
}
if ([string]$p1.visual_kind -ne "video") {
  throw "pack.json scene_001 no quedó en visual_kind=video"
}
if ([string]$p1.visual_source_kind -ne "stock_video") {
  throw "pack.json scene_001 no resolvió visual_source_kind=stock_video"
}
if ([string]$p1.visual_capability -ne "stock_video") {
  throw "pack.json scene_001 no resolvió visual_capability=stock_video"
}
if ([string]$p1.visual_capability -ne [string]$m1.visual_capability) {
  throw "pack.json scene_001 dejó visual_capability desalineado respecto a manifest_v03"
}
if ([int]$p1.duration_ms -ne ([int]$p1.end_ms - [int]$p1.start_ms)) {
  throw "pack.json scene_001 dejó duration_ms inconsistente"
}
if (-not [string]::IsNullOrWhiteSpace([string]$p1.image)) {
  throw "pack.json scene_001 dejó image no vacío"
}
if ([string]::IsNullOrWhiteSpace([string]$p1.video)) {
  throw "pack.json scene_001 dejó video vacío"
}
Write-Host "== Smoke sobre LIVE intent->video fallback ==" -ForegroundColor Cyan
& $smokeManifest -LiveDir $OutputLiveDir
if ($LASTEXITCODE -ne 0) {
  throw "smoke_live_manifest_v03.ps1 falló sobre LIVE intent->video fallback"
}

Write-Host "OK: intención image preservada con fallback efectivo a video" -ForegroundColor Green
Write-Host ("LIVE={0}" -f $OutputLiveDir) -ForegroundColor Cyan
Write-Host ("MANIFEST={0}" -f $manifestPath) -ForegroundColor Cyan
Write-Host ("PACK={0}" -f $packPath) -ForegroundColor Cyan