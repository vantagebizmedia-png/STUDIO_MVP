param(
  [Parameter(Mandatory=$true)][string]$WorkspaceRoot,
  [int]$MaxScenes = 6,
  [switch]$FailFast,
  [switch]$DoHandoff
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function StepFail([string]$step, [string]$msg) { throw "SMOKE FAIL: [$step] $msg" }

function RunPS(
  [Parameter(Mandatory=$true)][string]$Step,
  [Parameter(Mandatory=$true)][string]$ScriptPath,
  [Parameter(Mandatory=$true)][hashtable]$ArgMap
) {
  if (-not (Test-Path -LiteralPath $ScriptPath)) { StepFail $Step "No existe script: $ScriptPath" }

  $argList = @()
  foreach ($k in $ArgMap.Keys) {
    $v = $ArgMap[$k]
    if ($v -is [switch] -or $v -is [System.Management.Automation.SwitchParameter]) {
      if ([bool]$v) { $argList += @("-$k") }
    } else {
      $argList += @("-$k", "$v")
    }
  }

  Write-Host ""
  Write-Host ("[{0}] {1}" -f $Step, (Split-Path -Leaf $ScriptPath))
  $cmd = @("pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File",$ScriptPath) + $argList
  Write-Host ("Running: {0}" -f ($cmd -join " "))

  & pwsh -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @argList
}

$repo = (Resolve-Path -LiteralPath ".").Path
$ws   = (Resolve-Path -LiteralPath $WorkspaceRoot).Path

Write-Host "== SMOKE E2E v0.3 =="
Write-Host ("Repo      : {0}" -f $repo)
Write-Host ("Workspace : {0}" -f $ws)
Write-Host ("MaxScenes : {0}" -f $MaxScenes)
Write-Host ("FailFast  : {0}" -f ([bool]$FailFast))
Write-Host ("DoHandoff : {0}" -f ([bool]$DoHandoff))

$smokeLiveToWS   = Join-Path $repo "tools\smoke_live_to_workspace_v03.ps1"
$applyScenePatch = Join-Path $repo "tools\apply_scene_builder_v03.ps1"
$smokeLiveMF     = Join-Path $repo "tools\smoke_live_manifest_v03.ps1"
$applySubsLive   = Join-Path $repo "tools\apply_subtitles_live_v03.ps1"
$smokeSubsLive   = Join-Path $repo "tools\smoke_subtitles_live_v03.ps1"

$finalizeHandoff = Join-Path $repo "tools\finalize_handoff_v03.ps1"
$handoffPack     = Join-Path $repo "tools\handoff_pack_v03.ps1"

$errors = @()

try {
  RunPS -Step "1/6" -ScriptPath $smokeLiveToWS -ArgMap @{ WorkspaceRoot = $ws }
} catch { $errors += $_.Exception.Message; if ($FailFast) { throw } }

$live = Join-Path $ws "runs\smoke_live_latest"
try {
  if (-not (Test-Path -LiteralPath $live)) { StepFail "LIVE" "No existe live dir esperado: $live" }
  Write-Host ""
  Write-Host ("LIVE dir : {0}" -f $live)
} catch { $errors += $_.Exception.Message; if ($FailFast) { throw } }

try {
  RunPS -Step "2/6"  -ScriptPath $applyScenePatch -ArgMap @{ PackDir=$live; MaxScenes=$MaxScenes }
  RunPS -Step "2b/6" -ScriptPath $smokeLiveMF     -ArgMap @{ LiveDir=$live; MaxScenes=$MaxScenes }
} catch { $errors += $_.Exception.Message; if ($FailFast) { throw } }

try {
  RunPS -Step "3/6" -ScriptPath $applySubsLive -ArgMap @{ LiveDir=$live }
  RunPS -Step "4/6" -ScriptPath $smokeSubsLive -ArgMap @{ LiveDir=$live; MaxScenes=$MaxScenes }
} catch { $errors += $_.Exception.Message; if ($FailFast) { throw } }

if ($DoHandoff) {
  try {
    $handoffOut = Join-Path $live "handoff_v03"
    RunPS -Step "5/6" -ScriptPath $finalizeHandoff -ArgMap @{ LiveDir=$live; OutDir=$handoffOut }

    foreach ($f in @("video.mp4","video_final.mp4","video_music_auto.mp4")) {
      $p = Join-Path $handoffOut $f
      if (-not (Test-Path -LiteralPath $p)) { StepFail "5/6" "Falta output: $p" }
      if ((Get-Item -LiteralPath $p).Length -lt 1000) { StepFail "5/6" "Muy pequeño: $p" }
    }

    $zip = Join-Path $handoffOut "handoff_v03.zip"
    RunPS -Step "6/6" -ScriptPath $handoffPack -ArgMap @{ InDir=$handoffOut; OutZip=$zip }

    foreach ($f in @("SHA256SUMS.txt","HANDOFF_READY.txt","handoff_v03.zip")) {
      $p = Join-Path $handoffOut $f
      if (-not (Test-Path -LiteralPath $p)) { StepFail "6/6" "Falta: $p" }
      if ((Get-Item -LiteralPath $p).Length -lt 10) { StepFail "6/6" "Muy pequeño: $p" }
    }

    $tmp = Join-Path $handoffOut "_zip_check"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    $names = Get-ChildItem -LiteralPath $tmp -File | Select-Object -ExpandProperty Name
    Remove-Item -LiteralPath $tmp -Recurse -Force

    $expected = @("video.mp4","video_final.mp4","video_music_auto.mp4","SHA256SUMS.txt","HANDOFF_READY.txt")
    foreach ($e in $expected) { if ($names -notcontains $e) { StepFail "6/6" "ZIP no contiene: $e" } }

    Write-Host ("SMOKE OK: HANDOFF v03 listo en {0}" -f $handoffOut)
  } catch { $errors += $_.Exception.Message; if ($FailFast) { throw } }
} else {
  Write-Host ""
  Write-Host "[5/6] HANDOFF: omitido (no pasaste -DoHandoff)"
}

if ($errors.Count -gt 0) {
  Write-Host ""
  Write-Host "SMOKE FAIL: E2E v0.3 (uno o más pasos fallaron). Revisa:"
  foreach ($e in $errors) { Write-Host (" - {0}" -f $e) }
  exit 1
}

Write-Host ""
Write-Host "SMOKE OK: E2E v0.3 (LIVE(workspace) + scene_builder + subtitles + optional handoff)"
exit 0
