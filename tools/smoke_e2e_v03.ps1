param(
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot,
  [int]$MaxScenes = 6,
  [int]$Seed = 123,
  [switch]$FailFast,
  [switch]$DoHandoff,
  [switch]$Fast
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$psUtf8Compat = Join-Path $PSScriptRoot "ps_utf8_compat_v03.ps1"
if (-not (Test-Path -LiteralPath $psUtf8Compat -PathType Leaf)) {
  throw ("No existe helper utf8 compat: {0}" -f $psUtf8Compat)
}

. $psUtf8Compat

$repo = (Resolve-Path ".").Path

if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) {
  if (-not $env:STUDIO_WORKSPACE -or $env:STUDIO_WORKSPACE.Trim().Length -eq 0) {
    throw "Falta -WorkspaceRoot o env:STUDIO_WORKSPACE"
  }
  $WorkspaceRoot = $env:STUDIO_WORKSPACE
}

$WorkspaceRoot = (Resolve-Path $WorkspaceRoot).Path

Write-Host "== SMOKE E2E v0.3 ==" -ForegroundColor Cyan
Write-Host ("Repo      : {0}" -f $repo)
Write-Host ("Workspace : {0}" -f $WorkspaceRoot)
Write-Host ("MaxScenes : {0}" -f $MaxScenes)
Write-Host ("Seed      : {0}" -f $Seed)
Write-Host ("FailFast  : {0}" -f [bool]$FailFast)
Write-Host ("DoHandoff : {0}" -f [bool]$DoHandoff)
Write-Host ("Fast      : {0}" -f [bool]$Fast)
Write-Host ""

$script:StepErrors = New-Object System.Collections.Generic.List[string]

function Invoke-Step {
  param(
    [Parameter(Mandatory=$true)][string]$Label,
    [Parameter(Mandatory=$true)][string]$FilePath,
    [string[]]$Arguments = @()
  )

  if (-not (Test-Path -LiteralPath $FilePath)) {
    throw "Falta tool: $FilePath"
  }

  Write-Host $Label -ForegroundColor Yellow
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} {1}" -f $FilePath, ($Arguments -join " ")) -ForegroundColor DarkGray

  & pwsh -NoProfile -ExecutionPolicy Bypass -File $FilePath @Arguments
  $exitCode = $LASTEXITCODE

  if ($exitCode -ne 0) {
    throw ("Falló step: {0} (exit={1})" -f $Label, $exitCode)
  }
}

function Invoke-StepSafe {
  param(
    [Parameter(Mandatory=$true)][string]$Label,
    [Parameter(Mandatory=$true)][string]$FilePath,
    [string[]]$Arguments = @()
  )

  try {
    Invoke-Step -Label $Label -FilePath $FilePath -Arguments $Arguments
  }
  catch {
    $msg = ("{0} :: {1}" -f $Label, $_.Exception.Message)
    $script:StepErrors.Add($msg) | Out-Null
    Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    if ($FailFast) { throw }
  }
}

function Assert-FileExists {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Label
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw ("Falta output requerido: {0} -> {1}" -f $Label, $Path)
  }

  $item = Get-Item -LiteralPath $Path
  if ($item.PSIsContainer) {
    throw ("Se esperaba archivo y se encontró directorio: {0} -> {1}" -f $Label, $Path)
  }

  if ($item.Length -le 0) {
    throw ("Archivo vacío: {0} -> {1}" -f $Label, $Path)
  }

  Write-Host ("OK output: {0} -> {1} bytes" -f $Label, $item.Length) -ForegroundColor Green
}

$checkProviders = Join-Path $repo "tools\check_providers_cfg_v03.ps1"
$smokeLive      = Join-Path $repo "tools\smoke_live_to_workspace_v03.ps1"
$sceneBuilder   = Join-Path $repo "tools\apply_scene_builder_v03.ps1"
$normalize      = Join-Path $repo "tools\normalize_scene_assets_v03.ps1"
$smokeManifest  = Join-Path $repo "tools\smoke_live_manifest_v03.ps1"
$finalizePack   = Join-Path $repo "tools\finalize_pack_v03.ps1"
$subsApply      = Join-Path $repo "tools\apply_subtitles_live_v03.ps1"
$subsSmoke      = Join-Path $repo "tools\smoke_subtitles_live_v03.ps1"
$qualitySmoke   = Join-Path $repo "tools\smoke_quality_live_v03.ps1"
$ensureOutputs  = Join-Path $repo "tools\ensure_outputs_live_v03.ps1"
$refreshAudio   = Join-Path $repo "tools\refresh_live_audio_clips_v03.ps1"
$finalize       = Join-Path $repo "tools\finalize_handoff_v03.ps1"
$handoffPack    = Join-Path $repo "tools\handoff_pack_v03.ps1"

$liveDir         = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
$manifest        = Join-Path $liveDir "manifest_v03.json"
$videoBase       = Join-Path $liveDir "video.mp4"
$videoFinal      = Join-Path $liveDir "video_final.mp4"
$captionsFile    = Join-Path $liveDir "captions_v03.srt"
$handoffZip      = Join-Path $liveDir "handoff_v03\handoff_v03.zip"

$sceneBuilderMax = [Math]::Max(40, ($MaxScenes * 6))

Invoke-StepSafe -Label "[0/13] check_providers_cfg_v03.ps1" -FilePath $checkProviders

Invoke-StepSafe -Label "[1/13] smoke_live_to_workspace_v03.ps1" -FilePath $smokeLive -Arguments @(
  "-WorkspaceRoot", $WorkspaceRoot
)

Invoke-StepSafe -Label "[2/13] apply_scene_builder_v03.ps1 (SKIP/OK)" -FilePath $sceneBuilder -Arguments @(
  "-WorkspaceRoot", $WorkspaceRoot,
  "-MinScenes", "$MaxScenes",
  "-MaxScenes", "$MaxScenes",
  "-TargetSceneSec", "3",
  "-MinSceneSec", "2",
  "-MaxSceneSec", "5",
  "-Seed", "$Seed"
)

Invoke-StepSafe -Label "[2.1/13] refresh_live_audio_clips_v03.ps1" -FilePath $refreshAudio -Arguments @(
  "-LiveDir", $liveDir
)

Invoke-StepSafe -Label "[3/13] normalize_scene_assets_v03.ps1" -FilePath $normalize -Arguments @(
  "-ManifestPath", $manifest
)

Invoke-StepSafe -Label "[4/13] smoke_live_manifest_v03.ps1" -FilePath $smokeManifest -Arguments @(
  "-LiveDir", $liveDir,
  "-MaxScenes", "$sceneBuilderMax"
)

Invoke-StepSafe -Label "[5/13] finalize_pack_v03.ps1" -FilePath $finalizePack -Arguments @(
  "-PackDir", $liveDir,
  "-Fit", "crop"
)

Invoke-StepSafe -Label "[6/13] apply_subtitles_live_v03.ps1" -FilePath $subsApply -Arguments @(
  "-LiveDir", $liveDir
)

Invoke-StepSafe -Label "[7/13] smoke_subtitles_live_v03.ps1" -FilePath $subsSmoke -Arguments @(
  "-LiveDir", $liveDir,
  "-MaxScenes", "$sceneBuilderMax"
)

Invoke-StepSafe -Label "[8/13] smoke_quality_live_v03.ps1" -FilePath $qualitySmoke -Arguments @(
  "-WorkspaceRoot", $WorkspaceRoot
)

Invoke-StepSafe -Label "[9/13] ensure_outputs_live_v03.ps1" -FilePath $ensureOutputs -Arguments @(
  "-LiveDir", $liveDir
)

if ($DoHandoff) {
  Write-Host "[10/13] pre_handoff_refresh_scene_builder_v03.ps1" -ForegroundColor Yellow
  Write-Host "[PRE-HANDOFF] refresh apply_scene_builder_v03.ps1 (-Force)" -ForegroundColor DarkGray

  Invoke-StepSafe -Label "Running pre-handoff refresh" -FilePath $sceneBuilder -Arguments @(
    "-WorkspaceRoot", $WorkspaceRoot,
    "-MinScenes", "$MaxScenes",
    "-MaxScenes", "$MaxScenes",
    "-TargetSceneSec", "3",
    "-MinSceneSec", "2",
    "-MaxSceneSec", "5",
    "-Seed", "$Seed",
    "-Force"
  )

  Invoke-StepSafe -Label "Running pre-handoff audio refresh" -FilePath $refreshAudio -Arguments @(
    "-LiveDir", $liveDir
  )

  Invoke-StepSafe -Label "[11/13] finalize_handoff_v03.ps1" -FilePath $finalize -Arguments @(
    "-LiveDir", $liveDir
  )

  Invoke-StepSafe -Label "[12/13] handoff_pack_v03.ps1" -FilePath $handoffPack -Arguments @(
    "-InDir", (Join-Path $liveDir "handoff_v03"),
    "-OutZip", $handoffZip
  )
}

Write-Host ""
Write-Host "== VALIDACIÓN OUTPUTS ==" -ForegroundColor Cyan

try {
  Assert-FileExists -Path $videoBase    -Label "video.mp4"
  Assert-FileExists -Path $videoFinal   -Label "video_final.mp4"
  Assert-FileExists -Path $captionsFile -Label "captions_v03.srt"

  if ($DoHandoff) {
    Assert-FileExists -Path $handoffZip -Label "handoff_v03.zip"
  }
}
catch {
  $msg = ("VALIDACIÓN OUTPUTS :: {0}" -f $_.Exception.Message)
  $script:StepErrors.Add($msg) | Out-Null
  Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
  if ($FailFast) { throw }
}

Write-Host ""

if ($script:StepErrors.Count -gt 0) {
  Write-Host "SMOKE FAIL: hubo errores en el pipeline." -ForegroundColor Red
  Write-Host ""
  Write-Host "===== ERRORES =====" -ForegroundColor Yellow
  $script:StepErrors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
  throw ("SMOKE FAIL: total errores = {0}" -f $script:StepErrors.Count)
}

Write-Host "SMOKE OK: E2E v0.3 limpio (video.mp4 + video_final.mp4 + captions + optional handoff)" -ForegroundColor Green
