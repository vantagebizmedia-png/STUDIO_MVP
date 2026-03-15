param(
  [ValidateSet("demo","legacy-demo","legacy","smoke","smoke-e2e","smoke-multiscene")]
  [string]$Mode = "smoke",

  [string]$Script = "hola",

  [ValidateSet("DRY","REPLAY","LIVE")]
  [string]$ForceMode = "DRY",

  [string]$ProvidersJson = "",
  [string]$Workspace = "",
  [string]$WorkDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $RepoRoot

. (Join-Path $PSScriptRoot "resolve_python.ps1")
$py = Resolve-PythonExe -RepoRoot $RepoRoot

$runPy            = Join-Path $RepoRoot "run.py"
$runV03           = Join-Path $RepoRoot "tools\run_v03.ps1"
$smokeV03         = Join-Path $RepoRoot "tools\smoke_v03.ps1"
$smokeE2E         = Join-Path $RepoRoot "tools\smoke_v03_end_to_end.ps1"
$smokeToWorkspace = Join-Path $RepoRoot "tools\smoke_live_to_workspace_v03.ps1"
$v03MultiConfig   = Join-Path $RepoRoot "config\studio_v03_multiscene_smoke.json"

if (!(Test-Path -LiteralPath $runPy -PathType Leaf)) {
  throw "Ejecuta desde la raíz (run.py)"
}
if (!(Test-Path -LiteralPath $runV03 -PathType Leaf)) {
  throw "Falta tools\run_v03.ps1"
}
if (!(Test-Path -LiteralPath $smokeV03 -PathType Leaf)) {
  throw "Falta tools\smoke_v03.ps1"
}

if ($Mode -eq "smoke") {
  if (-not $env:STUDIO_WORKSPACE -or $env:STUDIO_WORKSPACE.Trim().Length -lt 3) {
    throw "Falta env:STUDIO_WORKSPACE. Ejemplo: `$env:STUDIO_WORKSPACE='C:\Users\vanta\Documents\STUDIO_WORKSPACE'"
  }

  if (-not (Test-Path -LiteralPath $smokeToWorkspace -PathType Leaf)) {
    throw "Falta: $smokeToWorkspace (debe existir en tools/)"
  }

  Write-Host "== SMOKE v0.3 (workspace) ==" -ForegroundColor Cyan
  Write-Host ("Repo      : " + $RepoRoot) -ForegroundColor DarkGray
  Write-Host ("Workspace : " + $env:STUDIO_WORKSPACE) -ForegroundColor DarkGray

  $outLines = & pwsh -NoProfile -ExecutionPolicy Bypass -File $smokeToWorkspace -WorkspaceRoot $env:STUDIO_WORKSPACE -CleanRepoOutputs
  $line = @($outLines | Where-Object { $_ -match '^LIVE_WORKSPACE_DIR=' }) | Select-Object -Last 1

  if ($line) {
    Write-Host $line -ForegroundColor Green
  }

  Write-Host "OK SMOKE v0.3 (workspace)" -ForegroundColor Green
  return
}

if ($Mode -eq "smoke-multiscene") {
  & powershell -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File $smokeV03
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  if (!(Test-Path -LiteralPath $v03MultiConfig -PathType Leaf)) {
    throw "Falta config multiscene: $v03MultiConfig"
  }

  $scriptMultiscene = @"
ESCENA 01
NARRACION: prueba uno.
ONSCREEN: prueba
STOCK_QUERY: persona estudio
---
ESCENA 02
NARRACION: prueba dos.
ONSCREEN: prueba
STOCK_QUERY: cuaderno notas
"@

  & $py -m cli.main --v03-config $v03MultiConfig --script $scriptMultiscene
  exit $LASTEXITCODE
}

if ($Mode -eq "smoke-e2e") {
  if (!(Test-Path -LiteralPath $smokeE2E -PathType Leaf)) {
    throw "Falta tools\smoke_v03_end_to_end.ps1"
  }

  & powershell -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File $smokeE2E
  exit $LASTEXITCODE
}

$psArgs = @(
  "-NoProfile",
  "-NoLogo",
  "-NonInteractive",
  "-ExecutionPolicy", "Bypass",
  "-File", $runV03,
  "-Mode", $Mode,
  "-Script", $Script,
  "-ForceMode", $ForceMode
)

if ($ProvidersJson) { $psArgs += @("-ProvidersJson", $ProvidersJson) }
if ($Workspace)     { $psArgs += @("-Workspace", $Workspace) }
if ($WorkDir)       { $psArgs += @("-WorkDir", $WorkDir) }

& powershell @psArgs
exit $LASTEXITCODE