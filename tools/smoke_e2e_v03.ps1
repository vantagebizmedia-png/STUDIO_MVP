param(
  [Parameter(Mandatory=$true)][string]$WorkspaceRoot,
  [int]$MaxScenes = 6,
  [switch]$FailFast,
  [switch]$DoHandoff
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path
$live = Join-Path $WorkspaceRoot "runs\smoke_live_latest"

Write-Host "== SMOKE E2E v0.3 ==" -ForegroundColor Cyan
Write-Host ("Repo      : {0}" -f $repo)
Write-Host ("Workspace : {0}" -f $WorkspaceRoot)
Write-Host ("MaxScenes : {0}" -f $MaxScenes)
Write-Host ("FailFast  : {0}" -f [bool]$FailFast)
Write-Host ("DoHandoff : {0}" -f [bool]$DoHandoff)
Write-Host ""

function Run-Step([int]$n, [int]$total, [string]$name, [scriptblock]$action) {
  Write-Host ("[{0}/{1}] {2}" -f $n,$total,$name) -ForegroundColor Cyan
  try {
    & $action
    if ($LASTEXITCODE -ne 0) { throw "ExitCode=$LASTEXITCODE" }
  } catch {
    Write-Host ("SMOKE FAIL: [{0}/{1}] {2} -> {3}" -f $n,$total,$name,$_.Exception.Message) -ForegroundColor Red
    if ($FailFast) { throw }
    else { $script:hadFail = $true }
  }
  Write-Host ""
}

$hadFail = $false

# 9 pasos sin handoff, 11 con handoff
$total = $(if ($DoHandoff) { 11 } else { 9 })
$step = 1

Run-Step $step $total "smoke_live_to_workspace_v03.ps1" {
  $tool = Join-Path $repo "tools\smoke_live_to_workspace_v03.ps1"
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -WorkspaceRoot {1}" -f $tool,$WorkspaceRoot) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -WorkspaceRoot $WorkspaceRoot
}
$step++

Run-Step $step $total "apply_scene_builder_v03.ps1 (SKIP/OK)" {
  $tool = Join-Path $repo "tools\apply_scene_builder_v03.ps1"
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -WorkspaceRoot {1} -MaxScenes {2}" -f $tool,$WorkspaceRoot,$MaxScenes) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -WorkspaceRoot $WorkspaceRoot -MaxScenes $MaxScenes
}
$step++

# NUEVO: normaliza assets.image/video a canon array[{path=...}]
Run-Step $step $total "normalize_scene_assets_v03.ps1" {
  $tool = Join-Path $repo "tools\normalize_scene_assets_v03.ps1"
  $man  = Join-Path $live "manifest_v03.json"
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -ManifestPath {1}" -f $tool,$man) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -ManifestPath $man
}
$step++

Run-Step $step $total "smoke_live_manifest_v03.ps1" {
  $tool = Join-Path $repo "tools\smoke_live_manifest_v03.ps1"
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -LiveDir {1} -MaxScenes {2}" -f $tool,$live,$MaxScenes) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -LiveDir $live -MaxScenes $MaxScenes
}
$step++

Run-Step $step $total "apply_subtitles_live_v03.ps1" {
  $tool = Join-Path $repo "tools\apply_subtitles_live_v03.ps1"
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -LiveDir {1}" -f $tool,$live) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -LiveDir $live
}
$step++

Run-Step $step $total "smoke_subtitles_live_v03.ps1" {
  $tool = Join-Path $repo "tools\smoke_subtitles_live_v03.ps1"
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -LiveDir {1} -MaxScenes {2}" -f $tool,$live,$MaxScenes) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -LiveDir $live -MaxScenes $MaxScenes
}
$step++

Run-Step $step $total "smoke_quality_live_v03.ps1" {
  $tool = Join-Path $repo "tools\smoke_quality_live_v03.ps1"
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -WorkspaceRoot {1}" -f $tool,$WorkspaceRoot) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -WorkspaceRoot $WorkspaceRoot
}
$step++

Run-Step $step $total "ensure_outputs_live_v03.ps1" {
  $tool = Join-Path $repo "tools\ensure_outputs_live_v03.ps1"
  Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -LiveDir {1}" -f $tool,$live) -ForegroundColor DarkGray
  pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -LiveDir $live
}
$step++
if ($DoHandoff) {
  Run-Step $step $total "pre_handoff_refresh_scene_builder_v03.ps1" {
    if (-not $DoHandoff) {
      Write-Host "SKIP: pre_handoff_refresh (DoHandoff=False)" -ForegroundColor DarkGray
      return
    }
  
    $toolSb = Join-Path $repo "tools\apply_scene_builder_v03.ps1"
    $sbArgs = @(
      "-WorkspaceRoot", $WorkspaceRoot,
      "-MaxScenes", $MaxScenes,
      "-Seed", $Seed,
      "-Force"
    )
  
    Write-Host "[PRE-HANDOFF] refresh apply_scene_builder_v03.ps1 (-Force)" -ForegroundColor DarkGray
    Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} {1}" -f $toolSb, ($sbArgs -join " ")) -ForegroundColor DarkGray
    pwsh -NoProfile -ExecutionPolicy Bypass -File $toolSb @sbArgs
  }
    Run-Step $step $total "finalize_handoff_v03.ps1" {
    $tool = Join-Path $repo "tools\finalize_handoff_v03.ps1"
    if (-not (Test-Path -LiteralPath $tool)) { throw "Falta tool: $tool" }

    Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -LiveDir {1}" -f $tool,$live) -ForegroundColor DarkGray
    pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -LiveDir $live | Out-Null
  }
  $step++

  Run-Step $step $total "handoff_pack_v03.ps1" {
    $tool = Join-Path $repo "tools\handoff_pack_v03.ps1"
    if (-not (Test-Path -LiteralPath $tool)) { throw "Falta tool: $tool" }

    $in   = Join-Path $live "handoff_v03"
    $zip  = Join-Path $in "handoff_v03.zip"
    Write-Host ("Running: pwsh -NoProfile -ExecutionPolicy Bypass -File {0} -InDir {1} -OutZip {2}" -f $tool,$in,$zip) -ForegroundColor DarkGray
    pwsh -NoProfile -ExecutionPolicy Bypass -File $tool -InDir $in -OutZip $zip | Out-Null
  }
  $step++
}if ($hadFail) { throw "SMOKE FAIL: E2E v0.3 (uno o más pasos fallaron)." }

if ($DoHandoff) {
  Write-Host ("SMOKE OK: HANDOFF v03 listo en {0}" -f (Join-Path $live "handoff_v03")) -ForegroundColor Green
  Write-Host ""
}

Write-Host "SMOKE OK: E2E v0.3 (LIVE(workspace) + scene_builder + subtitles + optional handoff)" -ForegroundColor Green
