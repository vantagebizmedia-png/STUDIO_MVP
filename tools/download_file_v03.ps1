param(
  [Parameter(Mandatory=$true)][string]$Url,
  [Parameter(Mandatory=$true)][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$dir = Split-Path -Parent $OutPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

# Descarga determinista (sin timestamps raros)
Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing -TimeoutSec 60

if (-not (Test-Path -LiteralPath $OutPath)) { throw "No se descargó: $OutPath" }
$len = (Get-Item -LiteralPath $OutPath).Length
if ($len -lt 2000) { throw "Archivo descargado demasiado pequeño: $OutPath (bytes=$len)" }

Write-Host "OK: downloaded -> $OutPath (bytes=$len)" -ForegroundColor Green
