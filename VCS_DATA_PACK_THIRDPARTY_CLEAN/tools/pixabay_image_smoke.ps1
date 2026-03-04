param(
    [string]$Query = "persona disciplinada trabajando en escritorio",
    [string]$OutDir = ".\_pixabay_smoke"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = $RepoRoot
. "$PSScriptRoot\resolve_python.ps1"
$py = Resolve-PythonExe -RepoRoot $RepoRoot

if ([string]::IsNullOrWhiteSpace($env:PIXABAY_API_KEY)) {
    throw "Falta la variable de entorno PIXABAY_API_KEY"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $py .\tools\pixabay_fetch_image.py `
  --query $Query `
  --out-dir $OutDir

Write-Host ""
Write-Host "=== PIXABAY SMOKE OUTPUT ==="
Get-ChildItem $OutDir -File | Select-Object FullName, Length | Format-Table -AutoSize
