param(
  [string]$WS = "C:\Users\vanta\Documents\STUDIO_WORKSPACE"
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

New-Item -ItemType Directory -Force $WS | Out-Null
New-Item -ItemType Directory -Force (Join-Path $WS "runs") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $WS "exports") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $WS "cache") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $WS "tmp") | Out-Null

$env:STUDIO_WORKSPACE = $WS
$env:TEMP = Join-Path $WS "tmp"
$env:TMP  = $env:TEMP

Write-Host "STUDIO_WORKSPACE=$env:STUDIO_WORKSPACE" -ForegroundColor Green
Write-Host "TEMP=$env:TEMP" -ForegroundColor DarkGray
Write-Host "TMP=$env:TMP" -ForegroundColor DarkGray
