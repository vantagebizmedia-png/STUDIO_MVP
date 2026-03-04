param(
  [Parameter(Mandatory=$true, Position=0)]
  [ValidateSet("DRY","LIVE","REPLAY")]
  [string]$Mode,

  [Parameter(Position=1)]
  [ValidateSet("all","text","image","voice")]
  [string]$Section = "all",

  [string]$ProvidersPath = ".\config\providers.json",

  [switch]$NoBackup
)

$ErrorActionPreference="Stop"

if (-not (Test-Path $ProvidersPath)) {
  throw "No existe: $ProvidersPath"
}

$bak = $null
if (-not $NoBackup) {
  $bak = "$ProvidersPath.bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
  Copy-Item $ProvidersPath $bak -Force
}

$j = Get-Content $ProvidersPath -Raw -Encoding UTF8 | ConvertFrom-Json

# leer estado actual (si existe)
$before = [ordered]@{}
foreach ($k in @("text","image","voice")) {
  if ($j.PSObject.Properties.Name -contains $k) {
    $before[$k] = $j.$k.mode
  }
}

# aplicar
$targets = @()
if ($Section -eq "all") { $targets = @("text","image","voice") } else { $targets = @($Section) }

foreach ($t in $targets) {
  if (-not ($j.PSObject.Properties.Name -contains $t)) {
    throw "Sección no existe en providers.json: $t"
  }
  $j.$t.mode = $Mode
}

($j | ConvertTo-Json -Depth 50) | Set-Content -Encoding UTF8 $ProvidersPath

# leer estado final
$after = [ordered]@{}
foreach ($k in @("text","image","voice")) {
  if ($j.PSObject.Properties.Name -contains $k) {
    $after[$k] = $j.$k.mode
  }
}

Write-Host "OK switch_mode" -ForegroundColor Green
if ($bak) { Write-Host "Backup: $bak" -ForegroundColor Yellow }

Write-Host "Before:" -ForegroundColor Cyan
$before.GetEnumerator() | ForEach-Object { Write-Host ("  {0}: {1}" -f $_.Key, $_.Value) }

Write-Host "After:" -ForegroundColor Cyan
$after.GetEnumerator() | ForEach-Object { Write-Host ("  {0}: {1}" -f $_.Key, $_.Value) }
