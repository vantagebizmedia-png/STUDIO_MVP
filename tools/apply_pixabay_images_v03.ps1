param(
  [Parameter(Mandatory=$true)][string]$ManifestPath,
  [int]$Seed = 123,
  [int]$PerPage = 50,
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

function Warn([string]$m){ Write-Host ("WARN: {0}" -f $m) -ForegroundColor Yellow }
function Info([string]$m){ Write-Host ("INFO: {0}" -f $m) -ForegroundColor DarkGray }
function Fail([string]$m){ throw ("APPLY_PIXABAY FAIL: {0}" -f $m) }

if (-not (Test-Path -LiteralPath $ManifestPath)) { Fail "No existe manifest: $ManifestPath" }

# Si no hay API key, NO falla (para smoke/offline determinista)
$apiKey = $env:PIXABAY_API_KEY
if (-not $apiKey -or $apiKey.Trim().Length -lt 8) {
  Info "PIXABAY_API_KEY no está seteada (o muy corta) -> skip (determinista/offline)"
  exit 0
}

$repo = (Resolve-Path ".").Path
$pix  = Join-Path $repo "tools\stock_query_pixabay_v03.ps1"
$dl   = Join-Path $repo "tools\download_file_v03.ps1"
if (-not (Test-Path -LiteralPath $pix)) { Fail "Falta tool: $pix" }
if (-not (Test-Path -LiteralPath $dl))  { Fail "Falta tool: $dl"  }

$manifestAbs = (Resolve-Path -LiteralPath $ManifestPath).Path
$liveDir = Split-Path -Parent $manifestAbs
$assets  = Join-Path $liveDir "assets\scenes_v03"
if (-not (Test-Path -LiteralPath $assets)) {
  Warn "No existe assets\scenes_v03 en liveDir=$liveDir -> skip"
  exit 0
}

$json = Get-Content -LiteralPath $manifestAbs -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $json.scenes_v03) { Fail "manifest sin scenes_v03" }

$scenes = @($json.scenes_v03)

# cache de queries: 1 request por query exacta (determinista + rápido)
$cache = @{}  # query -> parsed json (provider payload)

$ok = 0
$sk = 0

for ($i=0; $i -lt $scenes.Count; $i++) {
  $scene = $scenes[$i]

  $q = $null
  if ($scene.PSObject.Properties.Name -contains "stock_query") { $q = $scene.stock_query }
  if (-not $q -or $q.ToString().Trim().Length -eq 0) { $sk++; continue }
  $q = $q.ToString().Trim()

  $idx = $i + 1
  $target = Join-Path $assets ("scene_{0:000}.jpg" -f $idx)

  if ((-not $Force) -and (Test-Path -LiteralPath $target) -and ((Get-Item $target).Length -gt 2000)) {
    $sk++; continue
  }

  # obtiene (o cachea) respuesta pixabay para esta query
  $payload = $null
  if ($cache.ContainsKey($q)) {
    $payload = $cache[$q]
  } else {
    $tmpJson = Join-Path $assets (".tmp_pixabay_q_{0:000}.json" -f $idx)
    if (Test-Path -LiteralPath $tmpJson) { Remove-Item -LiteralPath $tmpJson -Force }

    # este script escribe JSON a OutJsonPath y usa $env:PIXABAY_API_KEY
    pwsh -NoProfile -ExecutionPolicy Bypass -File $pix -Query $q -OutJsonPath $tmpJson -Seed $Seed -PerPage $PerPage | Out-Null

    if (-not (Test-Path -LiteralPath $tmpJson)) { Warn "No se generó OutJsonPath (scene=$idx)"; $sk++; continue }

    try { $payload = Get-Content -LiteralPath $tmpJson -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Warn "OutJsonPath no es JSON válido (scene=$idx)"; $sk++; continue }

    # limpia tmp (no queremos basura)
    try { Remove-Item -LiteralPath $tmpJson -Force } catch { }

    $cache[$q] = $payload
  }

  if (-not $payload -or -not $payload.hits -or $payload.hits.Count -lt 1) {
    Warn "Pixabay sin hits (scene=$idx) q='$q'"
    $sk++; continue
  }

  # selección determinista del hit:
  # - mezcla Seed con idx escena para evitar que todas las escenas elijan hits[0]
  $n = [int]$payload.hits.Count
  $pickSeed = ($Seed * 1000) + $idx
  $r = [System.Random]::new($pickSeed)
  $k = $r.Next(0, $n)

  $url = $payload.hits[$k].url
  if (-not $url -or $url.ToString().Trim().Length -lt 8) {
    Warn "Hit sin url (scene=$idx) k=$k"
    $sk++; continue
  }

  # descarga (sobrescribe)
  pwsh -NoProfile -ExecutionPolicy Bypass -File $dl -Url $url -OutPath $target | Out-Null

  if (-not (Test-Path -LiteralPath $target)) { Warn "Descarga falló (scene=$idx)"; $sk++; continue }
  if ((Get-Item -LiteralPath $target).Length -lt 500) { Warn "JPG muy pequeño (scene=$idx)"; $sk++; continue }

  $ok++
  Info ("scene={0:000} pixabay(k={1}/{2}) -> {3}" -f $idx,$k,$n,$target)
}

Write-Host ("OK: apply_pixabay_images_v03 ok={0} skip={1} assets={2}" -f $ok,$sk,$assets) -ForegroundColor Green