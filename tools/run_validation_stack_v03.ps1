param(
  [Parameter(Mandatory=$false)][string]$RepoRoot = "C:\Users\vanta\Documents\STUDIO_MVP",
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot = "C:\Users\vanta\Documents\STUDIO_WORKSPACE",
  [Parameter(Mandatory=$false)][string]$LiveDir = "",
  [switch]$Quick,
  [switch]$SkipVideoCase,
  [switch]$SkipMixedVisuals,
  [switch]$SkipReleaseHandoffContract,
  [switch]$SkipIntentImageFallback,
  [switch]$SkipIntentVideoFallback,
  [switch]$SkipNegativeSuite,
  [switch]$ShowGitStatus
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
  throw "No existe RepoRoot: $RepoRoot"
}

if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
  throw "No existe WorkspaceRoot: $WorkspaceRoot"
}

$validateSuiteTool = Join-Path $RepoRoot "tools\validate_live_suite_v03.ps1"
if (-not (Test-Path -LiteralPath $validateSuiteTool -PathType Leaf)) {
  throw "No existe validate suite tool: $validateSuiteTool"
}

if ([string]::IsNullOrWhiteSpace($LiveDir)) {
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}

$effectiveSkipVideoCase              = [bool]$SkipVideoCase
$effectiveSkipMixedVisuals           = [bool]$SkipMixedVisuals
$effectiveSkipReleaseHandoffContract = [bool]$SkipReleaseHandoffContract
$effectiveSkipIntentImageFallback    = [bool]$SkipIntentImageFallback
$effectiveSkipIntentVideoFallback    = [bool]$SkipIntentVideoFallback
$effectiveSkipNegativeSuite          = [bool]$SkipNegativeSuite

if ($Quick) {
  $effectiveSkipVideoCase = $true
  $effectiveSkipMixedVisuals = $true
  $effectiveSkipReleaseHandoffContract = $true
  $effectiveSkipIntentImageFallback = $true
  $effectiveSkipIntentVideoFallback = $true
  $effectiveSkipNegativeSuite = $true
}

$mode = "FULL"
if ($Quick) {
  $mode = "QUICK"
}

$statusValidate = "PENDING"
$statusMainSmoke = "PENDING"
$statusProviderContract = "PENDING"
$statusSubtitlesSmoke = "PENDING"
$statusVoiceFallbackDuration = "PENDING"
$statusSingleSceneVoiceFallbackDuration = "PENDING"
$statusVideoCase = "SKIPPED"
$statusMixedVisuals = "SKIPPED"
$statusExportPackContract = "SKIPPED"
$statusReleaseHandoffContract = "SKIPPED"
$statusIntentImageFallback = "SKIPPED"
$statusIntentVideoFallback = "SKIPPED"
$statusNegative = "SKIPPED"
$statusGit = "SKIPPED"

Write-Host "== RUN VALIDATION STACK V03 ==" -ForegroundColor Magenta
Write-Host ("MODE                       : {0}" -f $mode) -ForegroundColor DarkGray
Write-Host ("RepoRoot                   : {0}" -f $RepoRoot) -ForegroundColor DarkGray
Write-Host ("WorkspaceRoot              : {0}" -f $WorkspaceRoot) -ForegroundColor DarkGray
Write-Host ("LiveDir                    : {0}" -f $LiveDir) -ForegroundColor DarkGray
Write-Host ("SkipVideoCase              : {0}" -f $effectiveSkipVideoCase) -ForegroundColor DarkGray
Write-Host ("SkipMixedVisuals           : {0}" -f $effectiveSkipMixedVisuals) -ForegroundColor DarkGray
Write-Host ("SkipReleaseHandoffContract : {0}" -f $effectiveSkipReleaseHandoffContract) -ForegroundColor DarkGray
Write-Host ("SkipIntentImageFallback    : {0}" -f $effectiveSkipIntentImageFallback) -ForegroundColor DarkGray
Write-Host ("SkipIntentVideoFallback    : {0}" -f $effectiveSkipIntentVideoFallback) -ForegroundColor DarkGray
Write-Host ("SkipNegativeSuite          : {0}" -f $effectiveSkipNegativeSuite) -ForegroundColor DarkGray
Write-Host ("ShowGitStatus              : {0}" -f [bool]$ShowGitStatus) -ForegroundColor DarkGray

Push-Location $RepoRoot
try {
  if ($ShowGitStatus) {
    Write-Host ""
    Write-Host "== GIT STATUS ==" -ForegroundColor Cyan
    git status --short
    git rev-parse --short HEAD
    $statusGit = "PASS"
  }

  Write-Host ""
  Write-Host "== VALIDATE SUITE ==" -ForegroundColor Cyan
  & $validateSuiteTool `
    -RepoRoot $RepoRoot `
    -WorkspaceRoot $WorkspaceRoot `
    -LiveDir $LiveDir `
    -SkipVideoCase:$effectiveSkipVideoCase `
    -SkipMixedVisuals:$effectiveSkipMixedVisuals `
    -SkipReleaseHandoffContract:$effectiveSkipReleaseHandoffContract `
    -SkipIntentImageFallback:$effectiveSkipIntentImageFallback `
    -SkipIntentVideoFallback:$effectiveSkipIntentVideoFallback `
    -SkipNegativeSuite:$effectiveSkipNegativeSuite

  if ($LASTEXITCODE -ne 0) {
    throw "validate_live_suite_v03.ps1 devolvió exit code $LASTEXITCODE"
  }

  $statusValidate = "PASS"
  $statusMainSmoke = "PASS"
  $statusProviderContract = "PASS"
  $statusSubtitlesSmoke = "PASS"
  $statusVoiceFallbackDuration = "PASS"
  $statusSingleSceneVoiceFallbackDuration = "PASS"

  if (-not $effectiveSkipVideoCase) {
    $statusVideoCase = "PASS"
  }

  if (-not $effectiveSkipMixedVisuals) {
    $statusMixedVisuals = "PASS"
    $statusExportPackContract = "PASS"
  }

  if (-not $effectiveSkipReleaseHandoffContract) {
    $statusReleaseHandoffContract = "PASS"
  }

  if (-not $effectiveSkipIntentImageFallback) {
    $statusIntentImageFallback = "PASS"
  }

  if (-not $effectiveSkipIntentVideoFallback) {
    $statusIntentVideoFallback = "PASS"
  }

  if (-not $effectiveSkipNegativeSuite) {
    $statusNegative = "PASS"
  }
}
finally {
  Pop-Location
}

Write-Host ""
Write-Host "== SUMMARY ==" -ForegroundColor Cyan
Write-Host ("VALIDATE_SUITE={0}" -f $statusValidate) -ForegroundColor DarkGray
Write-Host ("MAIN_SMOKE={0}" -f $statusMainSmoke) -ForegroundColor DarkGray
Write-Host ("PROVIDER_CONTRACT={0}" -f $statusProviderContract) -ForegroundColor DarkGray
Write-Host ("SUBTITLES_SMOKE={0}" -f $statusSubtitlesSmoke) -ForegroundColor DarkGray
Write-Host ("VOICE_FALLBACK_DURATION={0}" -f $statusVoiceFallbackDuration) -ForegroundColor DarkGray
Write-Host ("SINGLE_SCENE_VOICE_FALLBACK_DURATION={0}" -f $statusSingleSceneVoiceFallbackDuration) -ForegroundColor DarkGray
Write-Host ("VIDEO_CASE={0}" -f $statusVideoCase) -ForegroundColor DarkGray
Write-Host ("MIXED_VISUALS={0}" -f $statusMixedVisuals) -ForegroundColor DarkGray
Write-Host ("EXPORT_PACK_CONTRACT={0}" -f $statusExportPackContract) -ForegroundColor DarkGray
Write-Host ("RELEASE_HANDOFF_CONTRACT={0}" -f $statusReleaseHandoffContract) -ForegroundColor DarkGray
Write-Host ("INTENT_IMAGE_FALLBACK={0}" -f $statusIntentImageFallback) -ForegroundColor DarkGray
Write-Host ("INTENT_VIDEO_FALLBACK={0}" -f $statusIntentVideoFallback) -ForegroundColor DarkGray
Write-Host ("NEGATIVE_SUITE={0}" -f $statusNegative) -ForegroundColor DarkGray
Write-Host ("GIT_STATUS={0}" -f $statusGit) -ForegroundColor DarkGray

Write-Host ""
Write-Host "OK: run_validation_stack_v03 completado" -ForegroundColor Green
Write-Host ("MODE={0}" -f $mode) -ForegroundColor DarkGray
Write-Host ("LIVE_MAIN={0}" -f $LiveDir) -ForegroundColor DarkGray
