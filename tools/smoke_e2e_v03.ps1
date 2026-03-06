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
chcp 65001 | Out-Null

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
Write-Host ("FailFast  : {0}" -f [bool]$FailFast)
Write-Host ("DoHandoff : {0}" -f [bool]$DoHandoff)
Write-Host ("Fast      : {0}" -f [bool]$Fast)
Write-Host ""

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
    Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    if ($FailFast) { throw }
  }
}

$checkProviders = Join-Path $repo "tools\check_providers_cfg_v03.ps1"
$smokeLive      = Join-Path $repo "tools\smoke_live_to_workspace_v03.ps1"
$sceneBuilder   = Join-Path $repo "tools\apply_scene_builder_v03.ps1"
$normalize      = Join-Path $repo "tools\normalize_scene_assets_v03.ps1"
$smokeManifest  = Join-Path $repo "tools\smoke_live_manifest_v03.ps1"
$subsApply      = Join-Path $repo "tools\apply_subtitles_live_v03.ps1"
$subsSmoke      = Join-Path $repo "tools\smoke_subtitles_live_v03.ps1"
$qualitySmoke   = Join-Path $repo "tools\smoke_quality_live_v03.ps1"
$ensureOutputs  = Join-Path $repo "tools\ensure_outputs_live_v03.ps1"
$finalize       = Join-Path $repo "tools\finalize_handoff_v03.ps1"
$handoffPack    = Join-Path $repo "tools\handoff_pack_v03.ps1"

$liveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
$manifest = Join-Path $liveDir "manifest_v03.json"

$sceneBuilderMax = [Math]::Max(40, ($MaxScenes * 6))

Invoke-StepSafe -Label "[0/12] check_providers_cfg_v03.ps1" -FilePath $checkProviders

Invoke-StepSafe -Label "[1/12] smoke_live_to_workspace_v03.ps1" -FilePath $smokeLive -Arguments @(
  "-WorkspaceRoot", $WorkspaceRoot
)

Invoke-StepSafe -Label "[2/12] apply_scene_builder_v03.ps1 (SKIP/OK)" -FilePath $sceneBuilder -Arguments @(
  "-WorkspaceRoot", $WorkspaceRoot,
  "-MinScenes", "8",
  "-MaxScenes", "$sceneBuilderMax",
  "-TargetSceneSec", "6",
  "-MinSceneSec", "4",
  "-MaxSceneSec", "8",
  "-Seed", "$Seed"
)

Invoke-StepSafe -Label "[3/12] normalize_scene_assets_v03.ps1" -FilePath $normalize -Arguments @(
  "-ManifestPath", $manifest
)

Invoke-StepSafe -Label "[4/12] smoke_live_manifest_v03.ps1" -FilePath $smokeManifest -Arguments @(
  "-LiveDir", $liveDir,
  "-MaxScenes", "$sceneBuilderMax"
)

Invoke-StepSafe -Label "[5/12] apply_subtitles_live_v03.ps1" -FilePath $subsApply -Arguments @(
  "-LiveDir", $liveDir
)

Invoke-StepSafe -Label "[6/12] smoke_subtitles_live_v03.ps1" -FilePath $subsSmoke -Arguments @(
  "-LiveDir", $liveDir,
  "-MaxScenes", "$sceneBuilderMax"
)

Invoke-StepSafe -Label "[7/12] smoke_quality_live_v03.ps1" -FilePath $qualitySmoke -Arguments @(
  "-WorkspaceRoot", $WorkspaceRoot
)

Invoke-StepSafe -Label "[8/12] ensure_outputs_live_v03.ps1" -FilePath $ensureOutputs -Arguments @(
  "-LiveDir", $liveDir,
  "-Seed", "$Seed"
)

if ($DoHandoff) {
  Write-Host "[9/12] pre_handoff_refresh_scene_builder_v03.ps1" -ForegroundColor Yellow
  Write-Host "[PRE-HANDOFF] refresh apply_scene_builder_v03.ps1 (-Force)" -ForegroundColor DarkGray

  Invoke-StepSafe -Label "Running pre-handoff refresh" -FilePath $sceneBuilder -Arguments @(
    "-WorkspaceRoot", $WorkspaceRoot,
    "-MinScenes", "8",
    "-MaxScenes", "$sceneBuilderMax",
    "-TargetSceneSec", "6",
    "-MinSceneSec", "4",
    "-MaxSceneSec", "8",
    "-Seed", "$Seed",
    "-Force"
  )

  Invoke-StepSafe -Label "[10/12] finalize_handoff_v03.ps1" -FilePath $finalize -Arguments @(
    "-LiveDir", $liveDir
  )

  Invoke-StepSafe -Label "[11/12] handoff_pack_v03.ps1" -FilePath $handoffPack -Arguments @(
    "-InDir", (Join-Path $liveDir "handoff_v03"),
    "-OutZip", (Join-Path $liveDir "handoff_v03\handoff_v03.zip")
  )
}

Write-Host ""
Write-Host "SMOKE OK: E2E v0.3 (LIVE(workspace) + scene_builder + subtitles + optional handoff)" -ForegroundColor Green