param(
  [ValidateSet("demo","legacy-demo","legacy","smoke","smoke-e2e")]
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

if (!(Test-Path -LiteralPath ".\run.py")) { throw "Ejecuta desde la raíz (run.py)" }
if (!(Test-Path -LiteralPath ".\tools\run_v03.ps1")) { throw "Falta tools\run_v03.ps1" }
if (!(Test-Path -LiteralPath ".\tools\smoke_v03.ps1")) { throw "Falta tools\smoke_v03.ps1" }

if ($Mode -eq "smoke") {
  & powershell -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File .\tools\smoke_v03.ps1
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