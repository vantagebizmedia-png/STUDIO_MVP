param(
  [Parameter(Mandatory=$true)][string]$Script,
  [Parameter(Mandatory=$true)][string]$LogPath,
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

$out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $Script @Args 2>&1 | Out-String
[System.IO.File]::WriteAllText($LogPath, $out, [Text.UTF8Encoding]::new($false))

Write-Host "OK: log -> $LogPath" -ForegroundColor Green