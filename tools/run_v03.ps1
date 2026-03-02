param(
  [ValidateSet("demo","legacy-demo","legacy")]
  [string]$Mode = "demo",

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

chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$env:PYTHONUTF8="1"
$env:PYTHONIOENCODING="utf-8"

if (!(Test-Path -LiteralPath ".\run.py")) { throw "Ejecuta desde la raíz (run.py)" }

function Invoke-StudioCli([string[]]$PyArgs) {
  Write-Host ("Running: $py " + ($PyArgs -join " ")) -ForegroundColor Cyan
  & $py @PyArgs
  exit $LASTEXITCODE
}

if ($Mode -eq "demo") {
  $pyArgs = @("-m","cli.main","--demo","--script",$Script)
  if ($WorkDir) { $pyArgs += @("--work-dir",$WorkDir) }
  Invoke-StudioCli $pyArgs
}

if ($Mode -eq "legacy-demo") {
  $pyArgs = @("-m","cli.main","--legacy-demo","--script",$Script)
  if ($WorkDir) { $pyArgs += @("--work-dir",$WorkDir) }
  if ($Workspace) { $pyArgs += @("--workspace",$Workspace) }
  Invoke-StudioCli $pyArgs
}

if ($Mode -eq "legacy") {
  $pyArgs = @("-m","cli.main","--legacy","--script",$Script,"--force-mode",$ForceMode)
  if ($ProvidersJson) { $pyArgs += @("--providers-json",$ProvidersJson) }
  if ($Workspace) { $pyArgs += @("--workspace",$Workspace) }
  if ($WorkDir) { $pyArgs += @("--work-dir",$WorkDir) }
  Invoke-StudioCli $pyArgs
}

throw "Mode inválido: $Mode"
