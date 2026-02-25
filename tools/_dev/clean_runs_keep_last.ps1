param([int]$Keep = 50, [switch]$WhatIf)

$ws = $env:STUDIO_WORKSPACE
if (-not $ws) { $ws = "$env:USERPROFILE\STUDIO_WORKSPACE" }
$runs = Join-Path $ws "runs"
if (!(Test-Path $runs)) { Write-Host "No existe: $runs"; exit 0 }

$dirs = Get-ChildItem $runs -Directory | Sort-Object LastWriteTime -Descending
$toDelete = $dirs | Select-Object -Skip $Keep

Write-Host "Runs total: $($dirs.Count) | Keep: $Keep | Delete: $($toDelete.Count)"

foreach ($d in $toDelete) {
  if ($WhatIf) { Write-Host "[WhatIf] Delete $($d.FullName)"; continue }
  Remove-Item -LiteralPath $d.FullName -Recurse -Force
  Write-Host "Deleted $($d.FullName)"
}
