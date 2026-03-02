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

Write-Host "Compileall (solo dirs reales)..." -ForegroundColor Cyan
$targets = @(".\studio", ".\cli", ".\tests")
if (Test-Path -LiteralPath ".\app") { $targets += ".\app" }

& $py -m compileall -q @targets
if ($LASTEXITCODE -ne 0) { throw "compileall falló (exit=$LASTEXITCODE)" }

Write-Host "Unittest..." -ForegroundColor Cyan
& $py -m unittest -q
if ($LASTEXITCODE -ne 0) { throw "unittest falló (exit=$LASTEXITCODE)" }

Write-Host "Demo (core)..." -ForegroundColor Cyan
& $py -m cli.main --demo --script "hola"
if ($LASTEXITCODE -ne 0) { throw "demo falló (exit=$LASTEXITCODE)" }

Write-Host "OK smoke_core_v03" -ForegroundColor Green
