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
  throw "validate_live_suite_v03.ps1 devolvió exit code $LASTEXITCODE"
}

if ($ShowGitStatus) {
  Write-Host ""
  Write-Host "== Git status ==" -ForegroundColor Cyan
  Push-Location $RepoRoot
  try {
    git status --short

    Write-Host ""
    Write-Host "== HEAD reciente ==" -ForegroundColor Cyan
    git log --oneline -8
  }
  finally {
    Pop-Location
  }
}

Write-Host ""
Write-Host "OK: run_validation_stack_v03 completado" -ForegroundColor Green
Write-Host ("MODE={0}" -f $mode) -ForegroundColor DarkGray
Write-Host ("LIVE_MAIN={0}" -f $LiveDir) -ForegroundColor DarkGray