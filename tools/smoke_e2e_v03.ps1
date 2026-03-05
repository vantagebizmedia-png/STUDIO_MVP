param(
  [Parameter(Mandatory=$true)][string]$WorkspaceRoot,
  [int]$MaxScenes = 6,
  [int]$Seed = 123,
  [switch]$DoHandoff,
  [switch]$FailFast,

  # v0.3+: modo rápido determinista (no red)
  # Afecta SOLO el PRE-HANDOFF refresh (usa fallback + no enrich)
  [switch]$Fast,
  [switch]$SkipProviderCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path ".").Path
$liveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"

# Total steps
$total = 8
if ($DoHandoff) { $total = 11 }

Write-Host "== SMOKE E2E v0.3 ==" -ForegroundColor Green
Write-Host ("Repo      : {0}" -f $repo)
Write-Host ("Workspace : {0}" -f $WorkspaceRoot)
Write-Host ("MaxScenes : {0}" -f $MaxScenes)
Write-Host ("FailFast  : {0}" -f [bool]$FailFast)
Write-Host ("DoHandoff : {0}" -f [bool]$DoHandoff)
Write-Host ("Fast      : {0}" -f [bool]$Fast)
Write-Host ""

$hadFail = $false

function Run-Step([int]$n, [int]$totalN, [string]$name, [scriptblock]$action) {
  Write-Host ("[{0}/{1}] {2}" -f $n, $totalN, $name) -ForegroundColor Cyan
  try {
    & $action
  } catch {
    $script:hadFail = $true
    Write-Host ("SMOKE FAIL: [{0}/{1}] {2} -> {3}" -f $n, $totalN, $name, $_.Exception.Message) -ForegroundColor Red
    if ($FailFast) { throw }
  }
  Write-Host ""
}

$step = 1

# [0/11] providers.json guard-rail (wiring check)
if (-not $SkipProviderCheck) {
  $check = Join-Path $PSScriptRoot "check_providers_cfg_v03.ps1"
  if (Test-Path -LiteralPath $check) {
    Write-Host "[0/11] check_providers_cfg_v03.ps1" -ForegroundColor DarkGray
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $check
  } else {
    Write-Host "WARN: falta tools/check_providers_cfg_v03.ps1 (skip)" -ForegroundColor Yellow
  }
} else {
  Write-Host "SKIP: provider check (-SkipProviderCheck)" -ForegroundColor DarkGray
}
Run-Step $step $total "smoke_live_to_workspace_v03.ps1" {
$tool = Join-Path $repo "tools\smoke_live_to_workspace_v03.ps1"
  if (-not (Test-Path -LiteralPath $tool)) { throw "Falta tool: $tool" }
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -WorkspaceRoot {1}" -f $tool, $WorkspaceRoot) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -WorkspaceRoot $WorkspaceRoot
}
$step++

Run-Step $step $total "apply_scene_builder_v03.ps1 (SKIP/OK)" {
  $tool = Join-Path $repo "tools\apply_scene_builder_v03.ps1"
  if (-not (Test-Path -LiteralPath $tool)) { throw "Falta tool: $tool" }

  $sbArgs = @(
    "-WorkspaceRoot", $WorkspaceRoot,
    "-MaxScenes", $MaxScenes,
    "-Seed", $Seed
  )

  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} {1}" -f $tool, ($sbArgs -join " ")) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool @sbArgs
}
$step++

Run-Step $step $total "normalize_scene_assets_v03.ps1" {
  $tool = Join-Path $repo "tools\normalize_scene_assets_v03.ps1"
  if (-not (Test-Path -LiteralPath $tool)) { throw "Falta tool: $tool" }
  $manifest = Join-Path $liveDir "manifest_v03.json"
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -ManifestPath {1}" -f $tool, $manifest) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -ManifestPath $manifest
}
$step++

Run-Step $step $total "smoke_live_manifest_v03.ps1" {
  $tool = Join-Path $repo "tools\smoke_live_manifest_v03.ps1"
  if (-not (Test-Path -LiteralPath $tool)) { throw "Falta tool: $tool" }
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -LiveDir {1} -MaxScenes {2}" -f $tool, $liveDir, $MaxScenes) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -LiveDir $liveDir -MaxScenes $MaxScenes
}
$step++

Run-Step $step $total "apply_subtitles_live_v03.ps1" {
  $tool = Join-Path $repo "tools\apply_subtitles_live_v03.ps1"
  if (-not (Test-Path -LiteralPath $tool)) { throw "Falta tool: $tool" }
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -LiveDir {1}" -f $tool, $liveDir) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -LiveDir $liveDir
}
$step++

Run-Step $step $total "smoke_subtitles_live_v03.ps1" {
  $tool = Join-Path $repo "tools\smoke_subtitles_live_v03.ps1"
  if (-not (Test-Path -LiteralPath $tool)) { throw "Falta tool: $tool" }
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -LiveDir {1} -MaxScenes {2}" -f $tool, $liveDir, $MaxScenes) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -LiveDir $liveDir -MaxScenes $MaxScenes
}
$step++

Run-Step $step $total "smoke_quality_live_v03.ps1" {
  $tool = Join-Path $repo "tools\smoke_quality_live_v03.ps1"
  if (-not (Test-Path -LiteralPath $tool)) { throw "Falta tool: $tool" }
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -WorkspaceRoot {1}" -f $tool, $WorkspaceRoot) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -WorkspaceRoot $WorkspaceRoot
}
$step++

Run-Step $step $total "ensure_outputs_live_v03.ps1" {
  $tool = Join-Path $repo "tools\ensure_outputs_live_v03.ps1"
  if (-not (Test-Path -LiteralPath $tool)) { throw "Falta tool: $tool" }
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -LiveDir {1}" -f $tool, $liveDir) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -LiveDir $liveDir
}
$step++

if ($DoHandoff) {

  Run-Step $step $total "pre_handoff_refresh_scene_builder_v03.ps1" {
    $tool = Join-Path $repo "tools\apply_scene_builder_v03.ps1"
    if (-not (Test-Path -LiteralPath $tool)) { throw "Falta tool: $tool" }

    $sbArgs = @(
      "-WorkspaceRoot", $WorkspaceRoot,
      "-MaxScenes", $MaxScenes,
      "-Seed", $Seed,
      "-Force"
    )

    if ($Fast) {
      $sbArgs += @("-SkipPixabay", "-SkipEnrich")
      Write-Host "[PRE-HANDOFF] FAST refresh (SkipPixabay + SkipEnrich)" -ForegroundColor DarkGray
    } else {
      Write-Host "[PRE-HANDOFF] refresh apply_scene_builder_v03.ps1 (-Force)" -ForegroundColor DarkGray
    }

    Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} {1}" -f $tool, ($sbArgs -join " ")) -ForegroundColor DarkGray
    pwsh -NoProfile -ExecutionPolicy Bypass -File $tool @sbArgs
  }
  $step++

  Run-Step $step $total "finalize_handoff_v03.ps1" {
    $tool = Join-Path $repo "tools\finalize_handoff_v03.ps1"
    if (-not (Test-Path -LiteralPath $tool)) { throw "Falta tool: $tool" }
    Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -LiveDir {1}" -f $tool, $liveDir) -ForegroundColor DarkGray
    pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -LiveDir $liveDir
  }
  $step++

  Run-Step $step $total "handoff_pack_v03.ps1" {
    $tool = Join-Path $repo "tools\handoff_pack_v03.ps1"
    if (-not (Test-Path -LiteralPath $tool)) { throw "Falta tool: $tool" }
    $inDir  = Join-Path $liveDir "handoff_v03"
    $outZip = Join-Path $inDir "handoff_v03.zip"
    Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -InDir {1} -OutZip {2}" -f $tool, $inDir, $outZip) -ForegroundColor DarkGray
    pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -InDir $inDir -OutZip $outZip
  }
  $step++
}

if ($hadFail) {
  throw "SMOKE FAIL: E2E v0.3 (uno o más pasos fallaron)."
}

Write-Host "SMOKE OK: E2E v0.3 (LIVE(workspace) + scene_builder + subtitles + optional handoff)" -ForegroundColor Green