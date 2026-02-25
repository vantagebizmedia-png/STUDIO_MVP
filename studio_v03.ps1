param(
  [Parameter(Position=0)]
  [string]$Prompt = "hola",

  [ValidateSet("demo","legacy-demo","legacy","smoke")]
  [string]$Mode = "legacy",

  [ValidateSet("DRY","REPLAY","LIVE")]
  [string]$ForceMode = "DRY",

  [string]$ProvidersJson = "",
  [string]$Workspace = "",
  [string]$WorkDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath ".\run.py")) { throw "Ejecuta desde la raíz (run.py)" }
if (!(Test-Path -LiteralPath ".\tools\studio.ps1")) { throw "Falta .\tools\studio.ps1" }

# Delegar a tools\studio.ps1 (sin abrir shells interactivos)
$ps = @(
  "-NoProfile","-NoLogo","-NonInteractive",
  "-ExecutionPolicy","Bypass",
  "-File",".\tools\studio.ps1",
  "-Mode",$Mode,
  "-Script",$Prompt,
  "-ForceMode",$ForceMode
)

if ($ProvidersJson) { $ps += @("-ProvidersJson",$ProvidersJson) }
if ($Workspace)     { $ps += @("-Workspace",$Workspace) }
if ($WorkDir)       { $ps += @("-WorkDir",$WorkDir) }

& powershell @ps
exit $LASTEXITCODE