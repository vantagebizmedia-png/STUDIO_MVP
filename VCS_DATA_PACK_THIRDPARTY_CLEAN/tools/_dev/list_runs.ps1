param([int]$N = 20)

$ws = $env:STUDIO_WORKSPACE
if (-not $ws) { $ws = "$env:USERPROFILE\STUDIO_WORKSPACE" }
$runs = Join-Path $ws "runs"
if (!(Test-Path $runs)) { Write-Host "No existe: $runs"; exit 0 }

Get-ChildItem $runs -Directory |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First $N Name,LastWriteTime,FullName |
  Format-Table -AutoSize
