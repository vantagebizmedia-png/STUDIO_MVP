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

chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$env:PYTHONUTF8="1"
$env:PYTHONIOENCODING="utf-8"

if (!(Test-Path -LiteralPath ".\run.py")) { throw "Ejecuta desde la raíz (run.py)" }
Get-Command python -ErrorAction Stop | Out-Null

function Invoke-StudioCli([string[]]$PyArgs) {
  Write-Host ("Running: python " + ($PyArgs -join " ")) -ForegroundColor Cyan
  & python @PyArgs
  exit $LASTEXITCODE
}

if ($Mode -eq "demo") {
  $py = @("-m","cli.main","--demo","--script",$Script)
  if ($WorkDir) { $py += @("--work-dir",$WorkDir) }
  Invoke-StudioCli $py
}

if ($Mode -eq "legacy-demo") {
  $py = @("-m","cli.main","--legacy-demo","--script",$Script)
  if ($WorkDir) { $py += @("--work-dir",$WorkDir) }
  if ($Workspace) { $py += @("--workspace",$Workspace) }
  Invoke-StudioCli $py
}

if ($Mode -eq "legacy") {
  $py = @("-m","cli.main","--legacy","--script",$Script,"--force-mode",$ForceMode)
  if ($ProvidersJson) { $py += @("--providers-json",$ProvidersJson) }
  if ($Workspace) { $py += @("--workspace",$Workspace) }
  if ($WorkDir) { $py += @("--work-dir",$WorkDir) }
  Invoke-StudioCli $py
}

throw "Mode inválido: $Mode"