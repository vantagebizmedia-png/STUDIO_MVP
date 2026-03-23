param(
  [Parameter(Mandatory=$false)][string]$RepoRoot = "C:\Users\vanta\Documents\STUDIO_MVP",
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot = "C:\Users\vanta\Documents\STUDIO_WORKSPACE",
  [Parameter(Mandatory=$false)][string]$LiveDir = "",
  [switch]$SkipVideoCase,
  [switch]$SkipMixedVisuals,
  [switch]$SkipReleaseHandoffContract,
  [switch]$SkipIntentImageFallback,
  [switch]$SkipIntentVideoFallback,
  [switch]$SkipNegativeSuite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$psUtf8Compat = Join-Path $PSScriptRoot "ps_utf8_compat_v03.ps1"
if (-not (Test-Path -LiteralPath $psUtf8Compat -PathType Leaf)) {
  throw ("No existe helper utf8 compat: {0}" -f $psUtf8Compat)
}

. $psUtf8Compat

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
  throw "No existe RepoRoot: $RepoRoot"
}

if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
  throw "No existe WorkspaceRoot: $WorkspaceRoot"
}

if ([string]::IsNullOrWhiteSpace($LiveDir)) {
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}

$videoCaseLiveDir             = Join-Path $WorkspaceRoot "runs\smoke_live_video_case"
$mixedVisualsLiveDir          = Join-Path $WorkspaceRoot "runs\smoke_live_mixed_visuals"
$exportPackContractRoot       = Join-Path $WorkspaceRoot "runs\smoke_export_pack_contract"
$releaseHandoffContractRoot   = Join-Path $WorkspaceRoot "runs\smoke_release_handoff_contract"
$intentImageFallbackLiveDir   = Join-Path $WorkspaceRoot "runs\smoke_live_intent_image_fallback"
$intentVideoFallbackLiveDir   = Join-Path $WorkspaceRoot "runs\smoke_live_intent_video_fallback"

$applyTool                           = Join-Path $RepoRoot "tools\apply_scene_builder_v03.ps1"
$smokeTool                           = Join-Path $RepoRoot "tools\smoke_live_manifest_v03.ps1"
$providerContractTool                = Join-Path $RepoRoot "tools\smoke_live_provider_contract_v03.ps1"
$subtitlesSmokeTool                  = Join-Path $RepoRoot "tools\smoke_subtitles_live_v03.ps1"
$voiceFallbackDurationTool           = Join-Path $RepoRoot "tools\smoke_pipeline_voice_fallback_duration_v03.ps1"
$singleSceneVoiceFallbackDurationTool = Join-Path $RepoRoot "tools\smoke_pipeline_single_scene_voice_fallback_duration_v03.ps1"
$videoCaseTool                       = Join-Path $RepoRoot "tools\smoke_live_video_case_v03.ps1"
$mixedVisualsTool                    = Join-Path $RepoRoot "tools\smoke_live_mixed_visuals_v03.ps1"
$exportPackContractTool              = Join-Path $RepoRoot "tools\smoke_export_pack_contract_v03.ps1"
$releaseHandoffContractTool          = Join-Path $RepoRoot "tools\smoke_release_handoff_contract_v03.ps1"
$intentImageFallbackTool             = Join-Path $RepoRoot "tools\smoke_live_intent_image_fallback_v03.ps1"
$intentVideoFallbackTool             = Join-Path $RepoRoot "tools\smoke_live_intent_video_fallback_v03.ps1"
$negativeSuiteTool                   = Join-Path $RepoRoot "tools\negative_live_suite_v03.ps1"

foreach ($p in @(
  $applyTool,
  $smokeTool,
  $providerContractTool,
  $subtitlesSmokeTool,
  $voiceFallbackDurationTool,
  $singleSceneVoiceFallbackDurationTool,
  $videoCaseTool,
  $mixedVisualsTool,
  $exportPackContractTool,
  $releaseHandoffContractTool,
  $intentImageFallbackTool,
  $intentVideoFallbackTool,
  $negativeSuiteTool
)) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
    throw "No existe tool requerido: $p"
  }
}

Write-Host "== VALIDATE SUITE V03 ==" -ForegroundColor Magenta
Write-Host ("RepoRoot                   : {0}" -f $RepoRoot) -ForegroundColor DarkGray
Write-Host ("WorkspaceRoot              : {0}" -f $WorkspaceRoot) -ForegroundColor DarkGray
Write-Host ("LiveDir                    : {0}" -f $LiveDir) -ForegroundColor DarkGray
Write-Host ("SkipVideoCase              : {0}" -f [bool]$SkipVideoCase) -ForegroundColor DarkGray
Write-Host ("SkipMixedVisuals           : {0}" -f [bool]$SkipMixedVisuals) -ForegroundColor DarkGray
Write-Host ("SkipReleaseHandoffContract : {0}" -f [bool]$SkipReleaseHandoffContract) -ForegroundColor DarkGray
Write-Host ("SkipIntentImageFallback    : {0}" -f [bool]$SkipIntentImageFallback) -ForegroundColor DarkGray
Write-Host ("SkipIntentVideoFallback    : {0}" -f [bool]$SkipIntentVideoFallback) -ForegroundColor DarkGray
Write-Host ("SkipNegative               : {0}" -f [bool]$SkipNegativeSuite) -ForegroundColor DarkGray

Write-Host ""
Write-Host "== Paso 1: apply_scene_builder_v03 ==" -ForegroundColor Cyan
& $applyTool -WorkspaceRoot $WorkspaceRoot
if ($LASTEXITCODE -ne 0) {
  throw "apply_scene_builder_v03.ps1 devolvió exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $LiveDir -PathType Container)) {
  throw "No existe LIVE esperado después de apply: $LiveDir"
}

Write-Host ""
Write-Host "== Paso 2: smoke_live_manifest_v03 ==" -ForegroundColor Cyan
& $smokeTool -LiveDir $LiveDir
if ($LASTEXITCODE -ne 0) {
  throw "smoke_live_manifest_v03.ps1 devolvió exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "== Paso 3: smoke_live_provider_contract_v03 ==" -ForegroundColor Cyan
& $providerContractTool -LiveDir $LiveDir
if ($LASTEXITCODE -ne 0) {
  throw "smoke_live_provider_contract_v03.ps1 devolvió exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "== Paso 4: smoke_subtitles_live_v03 ==" -ForegroundColor Cyan
& $subtitlesSmokeTool -LiveDir $LiveDir
if ($LASTEXITCODE -ne 0) {
  throw "smoke_subtitles_live_v03.ps1 devolvió exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "== Paso 5: smoke_pipeline_voice_fallback_duration_v03 ==" -ForegroundColor Cyan
& $voiceFallbackDurationTool `
  -RepoRoot $RepoRoot `
  -WorkspaceRoot $WorkspaceRoot
if ($LASTEXITCODE -ne 0) {
  throw "smoke_pipeline_voice_fallback_duration_v03.ps1 devolvió exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "== Paso 6: smoke_pipeline_single_scene_voice_fallback_duration_v03 ==" -ForegroundColor Cyan
& $singleSceneVoiceFallbackDurationTool `
  -RepoRoot $RepoRoot `
  -WorkspaceRoot $WorkspaceRoot
if ($LASTEXITCODE -ne 0) {
  throw "smoke_pipeline_single_scene_voice_fallback_duration_v03.ps1 devolvió exit code $LASTEXITCODE"
}

if (-not $SkipVideoCase) {
  Write-Host ""
  Write-Host "== Paso 7: smoke_live_video_case_v03 ==" -ForegroundColor Cyan
  & $videoCaseTool `
    -RepoRoot $RepoRoot `
    -SourceLiveDir $LiveDir `
    -OutputLiveDir $videoCaseLiveDir

  if ($LASTEXITCODE -ne 0) {
    throw "smoke_live_video_case_v03.ps1 devolvió exit code $LASTEXITCODE"
  }
}
else {
  Write-Host ""
  Write-Host "== Paso 7: video-case omitido por flag ==" -ForegroundColor Yellow
}

if (-not $SkipMixedVisuals) {
  Write-Host ""
  Write-Host "== Paso 8: smoke_live_mixed_visuals_v03 ==" -ForegroundColor Cyan
  & $mixedVisualsTool `
    -RepoRoot $RepoRoot `
    -SourceLiveDir $LiveDir `
    -OutputLiveDir $mixedVisualsLiveDir

  if ($LASTEXITCODE -ne 0) {
    throw "smoke_live_mixed_visuals_v03.ps1 devolvió exit code $LASTEXITCODE"
  }

  Write-Host ""
  Write-Host "== Paso 9: smoke_export_pack_contract_v03 ==" -ForegroundColor Cyan
  & $exportPackContractTool `
    -RepoRoot $RepoRoot `
    -WorkspaceRoot $WorkspaceRoot `
    -SourceLiveDir $mixedVisualsLiveDir `
    -OutputRoot $exportPackContractRoot

  if ($LASTEXITCODE -ne 0) {
    throw "smoke_export_pack_contract_v03.ps1 devolvió exit code $LASTEXITCODE"
  }
}
else {
  Write-Host ""
  Write-Host "== Paso 8: mixed visuals omitido por flag ==" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "== Paso 9: export-pack contract omitido porque mixed visuals fue omitido ==" -ForegroundColor Yellow
}

if (-not $SkipReleaseHandoffContract) {
  Write-Host ""
  Write-Host "== Paso 10: smoke_release_handoff_contract_v03 ==" -ForegroundColor Cyan
  & $releaseHandoffContractTool `
    -RepoRoot $RepoRoot `
    -WorkspaceRoot $WorkspaceRoot `
    -OutputRoot $releaseHandoffContractRoot

  if ($LASTEXITCODE -ne 0) {
    throw "smoke_release_handoff_contract_v03.ps1 devolvió exit code $LASTEXITCODE"
  }
}
else {
  Write-Host ""
  Write-Host "== Paso 10: release/handoff contract omitido por flag ==" -ForegroundColor Yellow
}

if (-not $SkipIntentImageFallback) {
  Write-Host ""
  Write-Host "== Paso 11: smoke_live_intent_image_fallback_v03 ==" -ForegroundColor Cyan
  & $intentImageFallbackTool `
    -RepoRoot $RepoRoot `
    -WorkspaceRoot $WorkspaceRoot `
    -SourceLiveDir $LiveDir `
    -OutputLiveDir $intentImageFallbackLiveDir

  if ($LASTEXITCODE -ne 0) {
    throw "smoke_live_intent_image_fallback_v03.ps1 devolvió exit code $LASTEXITCODE"
  }
}
else {
  Write-Host ""
  Write-Host "== Paso 11: intent->image fallback omitido por flag ==" -ForegroundColor Yellow
}

if (-not $SkipIntentVideoFallback) {
  Write-Host ""
  Write-Host "== Paso 12: smoke_live_intent_video_fallback_v03 ==" -ForegroundColor Cyan
  & $intentVideoFallbackTool `
    -RepoRoot $RepoRoot `
    -WorkspaceRoot $WorkspaceRoot `
    -SourceLiveDir $LiveDir `
    -OutputLiveDir $intentVideoFallbackLiveDir

  if ($LASTEXITCODE -ne 0) {
    throw "smoke_live_intent_video_fallback_v03.ps1 devolvió exit code $LASTEXITCODE"
  }
}
else {
  Write-Host ""
  Write-Host "== Paso 12: intent->video fallback omitido por flag ==" -ForegroundColor Yellow
}

if (-not $SkipNegativeSuite) {
  Write-Host ""
  Write-Host "== Paso 13: negative_live_suite_v03 ==" -ForegroundColor Cyan
  & $negativeSuiteTool `
    -RepoRoot $RepoRoot `
    -WorkspaceRoot $WorkspaceRoot `
    -SourceLiveDir $LiveDir

  if ($LASTEXITCODE -ne 0) {
    throw "negative_live_suite_v03.ps1 devolvió exit code $LASTEXITCODE"
  }
}
else {
  Write-Host ""
  Write-Host "== Paso 13: negative suite omitida por flag ==" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "OK: validate_live_suite_v03 completado" -ForegroundColor Green
Write-Host ("LIVE_MAIN={0}" -f $LiveDir) -ForegroundColor DarkGray

if (-not $SkipVideoCase) {
  Write-Host ("LIVE_VIDEO_CASE={0}" -f $videoCaseLiveDir) -ForegroundColor DarkGray
}

if (-not $SkipMixedVisuals) {
  Write-Host ("LIVE_MIXED_VISUALS={0}" -f $mixedVisualsLiveDir) -ForegroundColor DarkGray
  Write-Host ("EXPORT_PACK_CONTRACT_ROOT={0}" -f $exportPackContractRoot) -ForegroundColor DarkGray
}

if (-not $SkipReleaseHandoffContract) {
  Write-Host ("RELEASE_HANDOFF_CONTRACT_ROOT={0}" -f $releaseHandoffContractRoot) -ForegroundColor DarkGray
}

if (-not $SkipIntentImageFallback) {
  Write-Host ("LIVE_INTENT_IMAGE_FALLBACK={0}" -f $intentImageFallbackLiveDir) -ForegroundColor DarkGray
}

if (-not $SkipIntentVideoFallback) {
  Write-Host ("LIVE_INTENT_VIDEO_FALLBACK={0}" -f $intentVideoFallbackLiveDir) -ForegroundColor DarkGray
}
