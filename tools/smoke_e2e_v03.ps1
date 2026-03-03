param(
  [string]$WorkspaceRoot = "",
  [string]$PackDir = "",
  [int]$MaxScenes = 6,
  [string]$SrtName = "captions_v03.srt",
  [int]$FontSize = 52,
  [int]$MarginV  = 120,
  [int]$Outline  = 3,
  [string]$MusicFile = "",
  [double]$MusicVolume = 0.22,
  [double]$DuckingRatio = 8.0,
  [switch]$ExpectMusic,

  # NUEVO: si está presente, detiene en el primer fallo y sale con ExitCode=1
  [switch]$FailFast
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

function Require-File {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Falta: $Path" }
}

$script:hadError = $false

function Run-StepPwsh {
  param(
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string[]]$Args
  )
  try {
    & pwsh @Args
    if ($LASTEXITCODE -ne 0) {
      throw ($Title + " falló (ExitCode=" + $LASTEXITCODE + ")")
    }
  }
  catch {
    $script:hadError = $true
    Write-Host "Exception:" -ForegroundColor Red
    Write-Host $Title -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    if ($FailFast) {
      Write-Host "FAIL-FAST: deteniendo en el primer error." -ForegroundColor Red
      exit 1
    }
  }
}

function Run-StepPy {
  param(
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string[]]$Args
  )
  try {
    & python @Args
    if ($LASTEXITCODE -ne 0) {
      throw ($Title + " falló (ExitCode=" + $LASTEXITCODE + ")")
    }
  }
  catch {
    $script:hadError = $true
    Write-Host "Exception:" -ForegroundColor Red
    Write-Host $Title -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    if ($FailFast) {
      Write-Host "FAIL-FAST: deteniendo en el primer error." -ForegroundColor Red
      exit 1
    }
  }
}

if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -lt 3) {
  $WorkspaceRoot = $env:STUDIO_WORKSPACE
}
if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -lt 3) {
  throw "Falta WorkspaceRoot y env:STUDIO_WORKSPACE no está seteado."
}

$smToWs       = Join-Path $repo "tools\smoke_live_to_workspace_v03.ps1"
$smLiveMan    = Join-Path $repo "tools\smoke_live_manifest_v03.ps1"
$apSubsLive   = Join-Path $repo "tools\apply_subtitles_live_v03.ps1"
$smSubsLive   = Join-Path $repo "tools\smoke_subtitles_live_v03.ps1"
$patchScene   = Join-Path $repo "tools\patch_manifest_scene_builder_v03.py"

Require-File $smToWs
Require-File $smLiveMan
Require-File $apSubsLive
Require-File $smSubsLive
Require-File $patchScene

$smFinalizeFull = Join-Path $repo "tools\smoke_finalize_full_v03.ps1"
if ($PackDir -and $PackDir.Trim().Length -ge 3) { Require-File $smFinalizeFull }

Write-Host "== SMOKE E2E v0.3 ==" -ForegroundColor Cyan
Write-Host ("Repo      : " + $repo) -ForegroundColor DarkGray
Write-Host ("Workspace : " + $WorkspaceRoot) -ForegroundColor DarkGray
Write-Host ("MaxScenes : " + $MaxScenes) -ForegroundColor DarkGray
Write-Host ("FailFast  : " + [bool]$FailFast) -ForegroundColor DarkGray

Write-Host "`n[1/5] LIVE: smoke -> workspace (stable live dir)" -ForegroundColor Yellow

$logsDir = Join-Path $WorkspaceRoot "runs\_logs"
New-Item -ItemType Directory -Force $logsDir | Out-Null
$ts     = Get-Date -Format "yyyyMMdd_HHmmss"
$logOut = Join-Path $logsDir ("smoke_live_to_workspace_" + $ts + ".out.log")
$logErr = Join-Path $logsDir ("smoke_live_to_workspace_" + $ts + ".err.log")
if (Test-Path $logOut) { Remove-Item -Force $logOut }
if (Test-Path $logErr) { Remove-Item -Force $logErr }

$psiArgs = @(
  "-NoProfile",
  "-ExecutionPolicy","Bypass",
  "-File", $smToWs,
  "-WorkspaceRoot", $WorkspaceRoot,
  "-CleanRepoOutputs"
)

$p = Start-Process -FilePath "pwsh" -ArgumentList $psiArgs -NoNewWindow -Wait -PassThru `
  -RedirectStandardOutput $logOut -RedirectStandardError $logErr

if ($p.ExitCode -ne 0) {
  throw ("smoke_live_to_workspace_v03.ps1 falló (ExitCode=" + $p.ExitCode + "). Revisa logs: OUT=" + $logOut + " ; ERR=" + $logErr)
}

$hit = Select-String -LiteralPath $logOut -Pattern "^LIVE_WORKSPACE_DIR=" | Select-Object -Last 1
if (-not $hit) { throw ("No pude leer LIVE_WORKSPACE_DIR. Revisa OUT log: " + $logOut) }

$live = ($hit.Line -replace "^LIVE_WORKSPACE_DIR=", "").Trim()
if (-not (Test-Path -LiteralPath $live)) { throw ("LIVE_WORKSPACE_DIR no existe: " + $live) }

Write-Host ("`n[2/5] LIVE: scene_builder patch (pack-dir=" + $live + ", max_scenes=" + $MaxScenes + ")") -ForegroundColor Yellow
Run-StepPy -Title "[2/5] patch_manifest_scene_builder_v03" -Args @(
  "-B",
  $patchScene,
  "--pack-dir", $live,
  "--max-scenes", ([string]$MaxScenes)
)

Write-Host ("`n[2/5] LIVE: smoke_live_manifest_v03 (live=" + $live + ")") -ForegroundColor Yellow
Run-StepPwsh -Title "[2/5] smoke_live_manifest_v03" -Args @(
  "-NoProfile","-ExecutionPolicy","Bypass",
  "-File",$smLiveMan,
  "-LiveDir",$live,
  "-MaxScenes",$MaxScenes
)

Write-Host "`n[3/5] LIVE: apply_subtitles_live_v03 (burn-in + SRT)" -ForegroundColor Yellow
Run-StepPwsh -Title "[3/5] apply_subtitles_live_v03" -Args @(
  "-NoProfile","-ExecutionPolicy","Bypass",
  "-File",$apSubsLive,
  "-LiveDir",$live,
  "-SrtName",$SrtName,
  "-FontSize",$FontSize,
  "-MarginV",$MarginV,
  "-Outline",$Outline
)

Write-Host "`n[4/5] LIVE: smoke_subtitles_live_v03" -ForegroundColor Yellow
Run-StepPwsh -Title "[4/5] smoke_subtitles_live_v03" -Args @(
  "-NoProfile","-ExecutionPolicy","Bypass",
  "-File",$smSubsLive,
  "-LiveDir",$live,
  "-MaxScenes",$MaxScenes,
  "-SrtName",$SrtName
)

if ($PackDir -and $PackDir.Trim().Length -ge 3) {
  $pack = (Resolve-Path $PackDir).Path
  Write-Host ("`n[5/5] PACK: smoke_finalize_full_v03 (pack=" + $pack + ")") -ForegroundColor Yellow

  $args = @(
    "-NoProfile","-ExecutionPolicy","Bypass",
    "-File",$smFinalizeFull,
    "-PackDir",$pack,
    "-MaxScenes",$MaxScenes,
    "-SrtName",$SrtName,
    "-FontSize",$FontSize,
    "-MarginV",$MarginV,
    "-Outline",$Outline
  )

  if ($MusicFile -and $MusicFile.Trim().Length -gt 0) {
    $args += @("-MusicFile",$MusicFile,"-MusicVolume",$MusicVolume,"-DuckingRatio",$DuckingRatio)
  }
  if ($ExpectMusic) { $args += "-ExpectMusic" }

  Run-StepPwsh -Title "[5/5] smoke_finalize_full_v03" -Args $args
} else {
  Write-Host "`n[5/5] PACK: (omitido) No pasaste -PackDir" -ForegroundColor DarkYellow
}

if ($script:hadError) {
  Write-Host "`nSMOKE FAIL: E2E v0.3 (uno o más pasos fallaron). Revisa output arriba." -ForegroundColor Red
  exit 1
}

Write-Host "`nSMOKE OK: E2E v0.3 (LIVE(workspace) + optional PACK)" -ForegroundColor Green
exit 0
