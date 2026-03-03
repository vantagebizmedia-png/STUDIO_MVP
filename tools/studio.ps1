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
$repo = $RepoRoot
. "$PSScriptRoot\resolve_python.ps1"
$py = Resolve-PythonExe -RepoRoot $RepoRoot

if (!(Test-Path -LiteralPath ".\run.py")) { throw "Ejecuta desde la raíz (run.py)" }
if (!(Test-Path -LiteralPath ".\tools\run_v03.ps1")) { throw "Falta tools\run_v03.ps1" }
if (!(Test-Path -LiteralPath ".\tools\smoke_v03.ps1")) { throw "Falta tools\smoke_v03.ps1" }

# =========================
# MODE: smoke (workspace-native)
# =========================
if ($Mode -eq "smoke") {

  if (-not $env:STUDIO_WORKSPACE -or $env:STUDIO_WORKSPACE.Trim().Length -lt 3) {
    throw "Falta env:STUDIO_WORKSPACE. Ejemplo: `$env:STUDIO_WORKSPACE='C:\Users\vanta\Documents\STUDIO_WORKSPACE'"
  }

  $repo = (Resolve-Path ".").Path

  $smToWs = Join-Path $repo "tools\smoke_live_to_workspace_v03.ps1"
  if (-not (Test-Path -LiteralPath $smToWs)) {
    throw "Falta: $smToWs (debe existir en tools/)"
  }

  Write-Host "== SMOKE v0.3 (workspace) ==" -ForegroundColor Cyan
  Write-Host ("Repo      : " + $repo) -ForegroundColor DarkGray
  Write-Host ("Workspace : " + $env:STUDIO_WORKSPACE) -ForegroundColor DarkGray

  $outLines = & pwsh -NoProfile -ExecutionPolicy Bypass -File $smToWs -WorkspaceRoot $env:STUDIO_WORKSPACE -CleanRepoOutputs

  $line = ($outLines | Where-Object { param(
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
$repo = $RepoRoot
. "$PSScriptRoot\resolve_python.ps1"
$py = Resolve-PythonExe -RepoRoot $RepoRoot

if (!(Test-Path -LiteralPath ".\run.py")) { throw "Ejecuta desde la raíz (run.py)" }
if (!(Test-Path -LiteralPath ".\tools\run_v03.ps1")) { throw "Falta tools\run_v03.ps1" }
if (!(Test-Path -LiteralPath ".\tools\smoke_v03.ps1")) { throw "Falta tools\smoke_v03.ps1" }

if ($Mode -eq "smoke") {
  & powershell -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File .\tools\smoke_v03.ps1
  exit $LASTEXITCODE
}

if ($Mode -eq "smoke-multiscene") {
  & powershell -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File .\tools\smoke_v03.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
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

  & $py -m cli.main --v03-config ".\config\studio_v03_multiscene_smoke.json" --script $scriptMultiscene
  exit $LASTEXITCODE
}

if ($Mode -eq "smoke-e2e") {
  & powershell -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File .\tools\smoke_v03_end_to_end.ps1
  exit $LASTEXITCODE
}

$psArgs = @("-NoProfile","-NoLogo","-NonInteractive","-ExecutionPolicy","Bypass","-File",".\tools\run_v03.ps1","-Mode",$Mode,"-Script",$Script,"-ForceMode",$ForceMode)
if ($ProvidersJson) { $psArgs += @("-ProvidersJson",$ProvidersJson) }
if ($Workspace)     { $psArgs += @("-Workspace",$Workspace) }
if ($WorkDir)       { $psArgs += @("-WorkDir",$WorkDir) }

& powershell @psArgs
exit $LASTEXITCODE
 -match '^LIVE_WORKSPACE_DIR=' } | Select-Object -Last 1)
  if ($line) {
    Write-Host $line -ForegroundColor Green
  }

  Write-Host "OK SMOKE v0.3 (workspace)" -ForegroundColor Green
  return
}

if ($Mode -eq "smoke-multiscene") {
  & powershell -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File .\tools\smoke_v03.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
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

  & $py -m cli.main --v03-config ".\config\studio_v03_multiscene_smoke.json" --script $scriptMultiscene
  exit $LASTEXITCODE
}

if ($Mode -eq "smoke-e2e") {
  & powershell -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File .\tools\smoke_v03_end_to_end.ps1
  exit $LASTEXITCODE
}

$psArgs = @("-NoProfile","-NoLogo","-NonInteractive","-ExecutionPolicy","Bypass","-File",".\tools\run_v03.ps1","-Mode",$Mode,"-Script",$Script,"-ForceMode",$ForceMode)
if ($ProvidersJson) { $psArgs += @("-ProvidersJson",$ProvidersJson) }
if ($Workspace)     { $psArgs += @("-Workspace",$Workspace) }
if ($WorkDir)       { $psArgs += @("-WorkDir",$WorkDir) }

& powershell @psArgs
exit $LASTEXITCODE

