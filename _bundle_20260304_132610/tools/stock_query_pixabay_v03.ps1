param(
  [Parameter(Mandatory=$true)][string]$Query,
  [Parameter(Mandatory=$true)][string]$OutJsonPath,
  [int]$Seed = 123,
  [int]$PerPage = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$apiKey = $env:PIXABAY_API_KEY
if (-not $apiKey -or $apiKey.Trim().Length -lt 8) {
  throw "Falta PIXABAY_API_KEY en el environment."
}

# Determinismo: orden estable (pixabay devuelve orden por defecto; nosotros elegimos índice determinista con Seed)
# Cache: el consumidor decide (guardando OutJsonPath en pack o cache global)

$q = $Query.Trim()
if ($q.Length -lt 2) { throw "Query muy corta." }

# Endpoint
$encQ = [uri]::EscapeDataString($q)
$url = "https://pixabay.com/api/?key=$apiKey&q=$encQ&image_type=photo&safesearch=true&per_page=$PerPage"

# Fetch
$resp = Invoke-RestMethod -Method GET -Uri $url -TimeoutSec 30

# Normaliza salida mínima
$hits = @()
if ($resp -and $resp.hits) {
  foreach ($h in $resp.hits) {
    # Preferimos largeImageURL si existe
    $u = $null
    if ($h.largeImageURL) { $u = [string]$h.largeImageURL }
    elseif ($h.webformatURL) { $u = [string]$h.webformatURL }

    if ($u) {
      $hits += [pscustomobject]@{
        url = $u
        page_url = [string]$h.pageURL
        tags = [string]$h.tags
        id = [string]$h.id
      }
    }
  }
}

$out = [pscustomobject]@{
  provider = "pixabay"
  query = $q
  seed = $Seed
  per_page = $PerPage
  total = [int]($resp.totalHits)
  hits = $hits
} | ConvertTo-Json -Depth 6

$dir = Split-Path -Parent $OutJsonPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

Set-Content -LiteralPath $OutJsonPath -Value $out -Encoding UTF8
Write-Host "OK: pixabay query saved -> $OutJsonPath (hits=$($hits.Count))" -ForegroundColor Green
