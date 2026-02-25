param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DirSizeMB([string]$Path) {
  if (!(Test-Path -LiteralPath $Path)) { return 0.0 }
  $m = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
       Measure-Object -Property Length -Sum
  $sum = 0
  if ($null -ne $m -and ($m.PSObject.Properties.Name -contains "Sum") -and $m.Sum) {
    $sum = [double]$m.Sum
  }
  return [Math]::Round(($sum / 1MB), 2)
}

Write-Host "== WORKSPACES (diagnóstico) ==" -ForegroundColor Cyan
Write-Host ("ENV STUDIO_WORKSPACE = " + ($env:STUDIO_WORKSPACE ?? "<not set>")) -ForegroundColor Yellow

# 1) workspace dentro del repo
$repoWs = Join-Path (Get-Location) "workspace"

# 2) workspaces típicos de v0.3 dentro del repo
$legacyWs = Join-Path (Get-Location) "_v03_legacy_run\workspace"
$configWs = $null
if (Test-Path -LiteralPath ".\config\studio_v03.json") {
  try {
    $obj = Get-Content -LiteralPath ".\config\studio_v03.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($obj.workspace) { $configWs = Join-Path (Get-Location) $obj.workspace }
  } catch { }
}

# 3) workspace externo que tú mencionas
$extWs = "C:\Users\vanta\Documents\STUDIO_WORKSPACE"

$items = @(
  @{Name="repo workspace"; Path=$repoWs},
  @{Name="v0.3 legacy workspace"; Path=$legacyWs},
  @{Name="v0.3 config workspace"; Path=($configWs ?? "<no config/studio_v03.json o sin campo workspace>")},
  @{Name="EXTERNO (tu carpeta)"; Path=$extWs}
)

foreach ($it in $items) {
  $p = $it.Path
  if ($p -is [string] -and $p.StartsWith("<")) {
    Write-Host ("- {0}: {1}" -f $it.Name, $p) -ForegroundColor Yellow
    continue
  }
  $exists = Test-Path -LiteralPath $p
  $mb = if ($exists) { Get-DirSizeMB $p } else { 0 }
  Write-Host ("- {0}: {1} | exists={2} | size={3} MB" -f $it.Name, $p, $exists, $mb) -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Regla: STUDIO v0.3 usa el workspace que diga ENV STUDIO_WORKSPACE o el JSON v0.3 (si usas --v03-config)." -ForegroundColor Green