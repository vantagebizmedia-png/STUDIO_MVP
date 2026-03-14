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

  $rel = [System.IO.Path]::GetRelativePath($BaseDir, $Path)
  return ($rel -replace '\\','/').Trim()
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = Split-Path -Parent $PSScriptRoot
}

if ([string]::IsNullOrWhiteSpace($SourceLiveDir)) {
  $SourceLiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}

if ([string]::IsNullOrWhiteSpace($OutputLiveDir)) {
  $OutputLiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_intent_image_fallback"
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

Write-Host "== Reset LIVE de prueba intent->image fallback ==" -ForegroundColor Cyan
if (Test-Path -LiteralPath $OutputLiveDir) {
  Remove-Item -LiteralPath $OutputLiveDir -Recurse -Force
}
Copy-Item -LiteralPath $SourceLiveDir -Destination $OutputLiveDir -Recurse -Force

$manifestPath = Join-Path $OutputLiveDir $manifestName
$packPath = Join-Path $OutputLiveDir $packPathName

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "No existe manifest clonado: $manifestPath"
}

Write-Host "== Preparando scene_001 con intención video pero sin video resoluble ==" -ForegroundColor Cyan
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

Get-ChildItem -LiteralPath $scene01Dir -File -ErrorAction Stop |
  Where-Object { $_.BaseName -eq "video" -and $_.Extension -in @(".mp4",".mov",".webm") } |
  Remove-Item -Force

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
  throw "scene_001 no tiene imagen resoluble en: $scene01Dir"
}

$imageRel = Get-NormalizedRelativePath -BaseDir $OutputLiveDir -Path $imageAbs

$scene1.requested_media_type = "video"
$scene1.visual_request_kind = "video"
$scene1.visual_kind = ""
$scene1.visual_source_kind = ""
$scene1.visual_capability = ""
$scene1.assets.image = $imageRel
$scene1.assets.video = ""

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
  image                = [string]$m1.assets.image
  video                = [string]$m1.assets.video
  audio                = [string]$m1.assets.audio_clip
},
[pscustomobject]@{
  source               = "pack_json"
  id                   = [string]$p1.id
  requested_media_type = ""
  visual_request_kind  = ""
  visual_kind          = [string]$p1.visual_kind
  visual_source_kind   = ""
  visual_capability    = ""
  image                = [string]$p1.image
  video                = [string]$p1.video
  audio                = [string]$p1.audio
} | Format-Table -AutoSize

if ([string]$m1.requested_media_type -ne "video") {
  throw "manifest_v03 scene_001 no preservó requested_media_type=video"
}
if ([string]$m1.visual_request_kind -ne "video") {
  throw "manifest_v03 scene_001 no preservó visual_request_kind=video"
}
if ([string]$m1.visual_kind -ne "image") {
  throw "manifest_v03 scene_001 no resolvió visual_kind=image"
}
if ([string]$m1.visual_source_kind -ne "stock_image") {
  throw "manifest_v03 scene_001 no resolvió visual_source_kind=stock_image"
}
if ([string]$m1.visual_capability -ne "stock_image") {
  throw "manifest_v03 scene_001 no resolvió visual_capability=stock_image"
}
if ([string]::IsNullOrWhiteSpace([string]$m1.assets.image)) {
  throw "manifest_v03 scene_001 dejó image vacío"
}
if (-not [string]::IsNullOrWhiteSpace([string]$m1.assets.video)) {
  throw "manifest_v03 scene_001 dejó video no vacío"
}

if ([string]$p1.visual_kind -ne "image") {
  throw "pack.json scene_001 no quedó en visual_kind=image"
}
if ([string]::IsNullOrWhiteSpace([string]$p1.image)) {
  throw "pack.json scene_001 dejó image vacío"
}
if (-not [string]::IsNullOrWhiteSpace([string]$p1.video)) {
  throw "pack.json scene_001 dejó video no vacío"
}

Write-Host "== Smoke sobre LIVE intent->image fallback ==" -ForegroundColor Cyan
& $smokeManifest -LiveDir $OutputLiveDir
if ($LASTEXITCODE -ne 0) {
  throw "smoke_live_manifest_v03.ps1 falló sobre LIVE intent->image fallback"
}

Write-Host "OK: intención video preservada con fallback efectivo a image" -ForegroundColor Green
Write-Host ("LIVE={0}" -f $OutputLiveDir) -ForegroundColor Cyan
Write-Host ("MANIFEST={0}" -f $manifestPath) -ForegroundColor Cyan
Write-Host ("PACK={0}" -f $packPath) -ForegroundColor Cyan