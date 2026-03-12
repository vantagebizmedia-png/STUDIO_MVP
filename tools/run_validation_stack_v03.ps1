param(
  [Parameter(Mandatory=$false)][string]$RepoRoot = "C:\Users\vanta\Documents\STUDIO_MVP",
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot = "C:\Users\vanta\Documents\STUDIO_WORKSPACE",
  [Parameter(Mandatory=$false)][string]$LiveDir = "",
  [switch]$Quick,
  [switch]$SkipVideoCase,
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

$validateTool = Join-Path $RepoRoot "tools\validate_live_suite_v03.ps1"
if (-not (Test-Path -LiteralPath $validateTool -PathType Leaf)) {
  throw "No existe validate_live_suite_v03.ps1: $validateTool"
}

if ([string]::IsNullOrWhiteSpace($LiveDir)) {
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}

$effectiveSkipVideoCase = [bool]$SkipVideoCase
$effectiveSkipNegativeSuite = [bool]$SkipNegativeSuite

if ($Quick) {
  $effectiveSkipVideoCase = $true
  $effectiveSkipNegativeSuite = $true
}

$mode = "FULL"
if ($Quick) {
  $mode = "QUICK"
}

$statusValidate = "PENDING"
$statusMainSmoke = "PENDING"
$statusVideoCase = "SKIPPED"
$statusNegative = "SKIPPED"
$statusGit = "SKIPPED"

if (-not $effectiveSkipVideoCase) {
  $statusVideoCase = "PENDING"
}

if (-not $effectiveSkipNegativeSuite) {
  $statusNegative = "PENDING"
}

Write-Host "== RUN VALIDATION STACK V03 ==" -ForegroundColor Magenta
Write-Host ("Mode             : {0}" -f $mode) -ForegroundColor DarkGray
Write-Host ("RepoRoot         : {0}" -f $RepoRoot) -ForegroundColor DarkGray
Write-Host ("WorkspaceRoot    : {0}" -f $WorkspaceRoot) -ForegroundColor DarkGray
Write-Host ("LiveDir          : {0}" -f $LiveDir) -ForegroundColor DarkGray
Write-Host ("SkipVideoCase    : {0}" -f $effectiveSkipVideoCase) -ForegroundColor DarkGray
Write-Host ("SkipNegative     : {0}" -f $effectiveSkipNegativeSuite) -ForegroundColor DarkGray
Write-Host ("ShowGitStatus    : {0}" -f [bool]$ShowGitStatus) -ForegroundColor DarkGray

$invokeArgs = @{
  RepoRoot      = $RepoRoot
  WorkspaceRoot = $WorkspaceRoot
  LiveDir       = $LiveDir
}

if ($effectiveSkipVideoCase) {
  $invokeArgs.SkipVideoCase = $true
}

if ($effectiveSkipNegativeSuite) {
  $invokeArgs.SkipNegativeSuite = $true
}

Write-Host ""
Write-Host "== Ejecutando validate_live_suite_v03 ==" -ForegroundColor Cyan
& $validateTool @invokeArgs

if ($LASTEXITCODE -ne 0) {
  throw "validate_live_suite_v03.ps1 devolvio exit code $LASTEXITCODE"
}

$statusValidate = "PASS"
$statusMainSmoke = "PASS"

if ($effectiveSkipVideoCase) {
  $statusVideoCase = "SKIPPED"
}
else {
  $statusVideoCase = "PASS"
}

if ($effectiveSkipNegativeSuite) {
  $statusNegative = "SKIPPED"
}
else {
  $statusNegative = "PASS"
}

if ($ShowGitStatus) {
  Write-Host ""
  Write-Host "== Git status ==" -ForegroundColor Cyan

  Push-Location $RepoRoot
  try {
    $gitStatusOutput = (& git --no-pager status --short 2>&1 | Out-String).TrimEnd()
    $gitStatusExit = $LASTEXITCODE
    if ($gitStatusExit -ne 0) {
      throw "git status fallo con exit code $gitStatusExit"
    }

    if ([string]::IsNullOrWhiteSpace($gitStatusOutput)) {
      Write-Host "(working tree clean)" -ForegroundColor DarkGray
    }
    else {
      Write-Host $gitStatusOutput
    }

    Write-Host ""
    Write-Host "== HEAD reciente ==" -ForegroundColor Cyan

    $gitLogOutput = (& git --no-pager log --oneline -8 2>&1 | Out-String).TrimEnd()
    $gitLogExit = $LASTEXITCODE
    if ($gitLogExit -ne 0) {
      throw "git log fallo con exit code $gitLogExit"
    }

    if ([string]::IsNullOrWhiteSpace($gitLogOutput)) {
      throw "git log devolvio salida vacia"
    }

    Write-Host $gitLogOutput
  }
  finally {
    Pop-Location
  }

  $statusGit = "PASS"
}

Write-Host ""
Write-Host "== SUMMARY ==" -ForegroundColor Cyan
Write-Host ("VALIDATE_SUITE={0}" -f $statusValidate) -ForegroundColor DarkGray
Write-Host ("MAIN_SMOKE={0}" -f $statusMainSmoke) -ForegroundColor DarkGray
Write-Host ("VIDEO_CASE={0}" -f $statusVideoCase) -ForegroundColor DarkGray
Write-Host ("NEGATIVE_SUITE={0}" -f $statusNegative) -ForegroundColor DarkGray
Write-Host ("GIT_STATUS={0}" -f $statusGit) -ForegroundColor DarkGray

Write-Host ""
Write-Host "OK: run_validation_stack_v03 completado" -ForegroundColor Green
Write-Host ("MODE={0}" -f $mode) -ForegroundColor DarkGray
Write-Host ("LIVE_MAIN={0}" -f $LiveDir) -ForegroundColor DarkGray