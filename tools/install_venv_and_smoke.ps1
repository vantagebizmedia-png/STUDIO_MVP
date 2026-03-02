param(
  [string]$VenvDir = ".venv"
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = $RepoRoot
. "$PSScriptRoot\resolve_python.ps1"
$py = Resolve-PythonExe -RepoRoot $RepoRoot

if (!(Test-Path ".\requirements.txt")) { throw "No existe requirements.txt" }
if (!(Test-Path ".\tools\smoke_end_to_end.ps1")) { throw "No existe tools\smoke_end_to_end.ps1" }

Write-Host "== STUDIO_MVP install + smoke =="
Write-Host "VenvDir: $VenvDir"

# 1) Crear venv si no existe
if (!(Test-Path $VenvDir)) {
  & $py -m venv $VenvDir
  Write-Host "OK: venv creado"
} else {
  Write-Host "OK: venv ya existe"
}

# 2) Activar venv (PowerShell)
$activate = Join-Path $VenvDir "Scripts\Activate.ps1"
if (!(Test-Path $activate)) { throw "No encuentro activador: $activate" }
. $activate
Write-Host "OK: venv activado"
$py = (Resolve-Path -LiteralPath (Join-Path $VenvDir "Scripts\python.exe")).Path

# 3) Upgrade pip
& $py -m pip install --upgrade pip

# 4) Instalar dependencias
& $py -m pip install -r .\requirements.txt

# 5) Smoke
powershell -ExecutionPolicy Bypass -File .\tools\smoke_end_to_end.ps1

Write-Host ""
Write-Host "DONE: install + smoke OK"
