param(
  [Parameter(Position=0, Mandatory=$true)]
  [string]$Prompt,

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

if (!(Test-Path -LiteralPath ".\studio_v03.ps1")) { throw "Falta .\studio_v03.ps1" }

$ps = @(
  "-NoProfile","-NoLogo","-NonInteractive",
  "-ExecutionPolicy","Bypass",
  "-File",".\studio_v03.ps1",
  $Prompt,
  "-Mode",$Mode,
  "-ForceMode",$ForceMode
)

if ($ProvidersJson) { $ps += @("-ProvidersJson",$ProvidersJson) }
if ($Workspace)     { $ps += @("-Workspace",$Workspace) }
if ($WorkDir)       { $ps += @("-WorkDir",$WorkDir) }

& powershell @ps
exit $LASTEXITCODE