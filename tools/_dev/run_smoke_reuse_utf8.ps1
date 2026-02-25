param(
  [Parameter(Mandatory=$true)][string]$RunId,
  [string]$LogPath = ".\last_smoke_reuse_utf8.log"
)

$ErrorActionPreference="Stop"
chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$smoke = Join-Path $PSScriptRoot "smoke_reuse_pack.ps1"
if (-not (Test-Path $smoke)) { throw "No existe: $smoke" }

Write-Host "RunId: $RunId"
Write-Host "Log  : $LogPath"
Write-Host ""

$out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $smoke -RunId $RunId 2>&1 | Out-String
[System.IO.File]::WriteAllText($LogPath, $out, [Text.UTF8Encoding]::new($false))

Write-Host "OK: log -> $LogPath" -ForegroundColor Green
Write-Host ""
Get-Content $LogPath -Encoding utf8