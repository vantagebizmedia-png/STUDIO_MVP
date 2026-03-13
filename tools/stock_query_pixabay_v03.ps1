param(
  [Parameter(Mandatory=$true)][string]$Query,
  [Parameter(Mandatory=$true)][string]$OutJsonPath,
  [int]$Seed = 123,
  [int]$PerPage = 50,
  [ValidateSet("image","video")][string]$MediaType = "image",
  [ValidateSet("all","horizontal","vertical")][string]$PreferredOrientation = "vertical",
  [int]$MinWidth = 1080
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$apiKey = $env:PIXABAY_API_KEY
if (-not $apiKey -or $apiKey.Trim().Length -lt 8) {
  throw "Falta PIXABAY_API_KEY en el environment."
}

if ($PerPage -lt 3) { $PerPage = 3 }
if ($PerPage -gt 200) { $PerPage = 200 }
if ($MinWidth -lt 0) { $MinWidth = 0 }

function Has-Prop([object]$Obj, [string]$Name) {
  if ($null -eq $Obj) { return $false }
  return ($Obj.PSObject.Properties.Match($Name).Count -gt 0)
}

function Get-StringProp([object]$Obj, [string]$Name) {
  if (-not (Has-Prop $Obj $Name)) { return "" }
  $value = $Obj.$Name
  if ($null -eq $value) { return "" }
  return [string]$value
}

function Get-IntProp([object]$Obj, [string]$Name) {
  $raw = Get-StringProp -Obj $Obj -Name $Name
  if ([string]::IsNullOrWhiteSpace($raw)) { return 0 }

  $parsed = 0
  if ([int]::TryParse($raw, [ref]$parsed)) { return $parsed }
  return 0
}

function Select-PixabayVideoStream {
  param(
    [Parameter(Mandatory=$true)][object]$Hit,
    [ValidateSet("all","horizontal","vertical")][string]$PreferredOrientation = "vertical",
    [int]$MinWidth = 1080
  )

  if ($null -eq $Hit) { return $null }
  if (-not (Has-Prop $Hit "videos")) { return $null }

  $videos = $Hit.videos
  if ($null -eq $videos) { return $null }

  $sizeRank = @{
    medium = 0
    large  = 1
    small  = 2
    tiny   = 3
  }

  $candidates = New-Object System.Collections.Generic.List[object]

  foreach ($key in @("medium","large","small","tiny")) {
    if (-not (Has-Prop $videos $key)) { continue }

    $item = $videos.$key
    if ($null -eq $item) { continue }

    $url = Get-StringProp -Obj $item -Name "url"
    if ([string]::IsNullOrWhiteSpace($url)) { continue }

    $thumb = Get-StringProp -Obj $item -Name "thumbnail"
    $width = Get-IntProp -Obj $item -Name "width"
    $height = Get-IntProp -Obj $item -Name "height"

    $orientationPenalty = 0
    if ($PreferredOrientation -eq "vertical" -and $width -gt 0 -and $height -gt 0 -and $height -lt $width) {
      $orientationPenalty = 1
    }
    elseif ($PreferredOrientation -eq "horizontal" -and $width -gt 0 -and $height -gt 0 -and $width -lt $height) {
      $orientationPenalty = 1
    }

    $widthPenalty = 0
    if ($MinWidth -gt 0 -and $width -lt $MinWidth) {
      $widthPenalty = 1
    }

    $rank = 99
    if ($sizeRank.ContainsKey($key)) {
      $rank = [int]$sizeRank[$key]
    }

    $candidates.Add([pscustomobject]@{
      url                = $url
      thumbnail          = $thumb
      width              = $width
      height             = $height
      orientationPenalty = $orientationPenalty
      widthPenalty       = $widthPenalty
      sizeRank           = $rank
      negWidth           = (-1 * $width)
      negHeight          = (-1 * $height)
    }) | Out-Null
  }

  if ($candidates.Count -lt 1) { return $null }

  $selected = $candidates |
    Sort-Object orientationPenalty, widthPenalty, sizeRank, negWidth, negHeight |
    Select-Object -First 1

  return $selected
}

# Determinismo: orden estable del proveedor; el consumidor decide el índice con Seed.
# Cache: el consumidor decide (guardando OutJsonPath en pack o cache global).

$q = $Query.Trim()
if ($q.Length -lt 2) { throw "Query muy corta." }

$media = $MediaType.Trim().ToLowerInvariant()
$encQ = [uri]::EscapeDataString($q)

if ($media -eq "video") {
  $url = "https://pixabay.com/api/videos/?key=$apiKey&q=$encQ&video_type=all&safesearch=true&per_page=$PerPage&min_width=$MinWidth"
}
else {
  $url = "https://pixabay.com/api/?key=$apiKey&q=$encQ&image_type=photo&safesearch=true&per_page=$PerPage"
}

$resp = Invoke-RestMethod -Method GET -Uri $url -TimeoutSec 30

$rawHits = @()
if ($null -ne $resp -and (Has-Prop $resp "hits") -and $resp.hits) {
  $rawHits = @($resp.hits)
}

$hits = @()
foreach ($h in $rawHits) {
  if ($media -eq "video") {
    $picked = Select-PixabayVideoStream -Hit $h -PreferredOrientation $PreferredOrientation -MinWidth $MinWidth
    if ($null -eq $picked) { continue }

    $hits += [pscustomobject]@{
      url        = [string]$picked.url
      page_url   = Get-StringProp -Obj $h -Name "pageURL"
      tags       = Get-StringProp -Obj $h -Name "tags"
      id         = Get-StringProp -Obj $h -Name "id"
      media_kind = "video"
      width      = [int]$picked.width
      height     = [int]$picked.height
      thumb_url  = [string]$picked.thumbnail
    }
  }
  else {
    $u = Get-StringProp -Obj $h -Name "largeImageURL"
    if ([string]::IsNullOrWhiteSpace($u)) {
      $u = Get-StringProp -Obj $h -Name "webformatURL"
    }

    if ([string]::IsNullOrWhiteSpace($u)) { continue }

    $hits += [pscustomobject]@{
      url        = $u
      page_url   = Get-StringProp -Obj $h -Name "pageURL"
      tags       = Get-StringProp -Obj $h -Name "tags"
      id         = Get-StringProp -Obj $h -Name "id"
      media_kind = "image"
      width      = Get-IntProp -Obj $h -Name "imageWidth"
      height     = Get-IntProp -Obj $h -Name "imageHeight"
      thumb_url  = Get-StringProp -Obj $h -Name "previewURL"
    }
  }
}

$totalHits = 0
if ($null -ne $resp -and (Has-Prop $resp "totalHits")) {
  try { $totalHits = [int]$resp.totalHits } catch { $totalHits = 0 }
}

$out = [pscustomobject]@{
  provider    = "pixabay"
  query       = $q
  seed        = $Seed
  per_page    = $PerPage
  media_type  = $media
  min_width   = $MinWidth
  orientation = $PreferredOrientation
  total       = $totalHits
  hits        = $hits
} | ConvertTo-Json -Depth 6

$dir = Split-Path -Parent $OutJsonPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

Set-Content -LiteralPath $OutJsonPath -Value $out -Encoding UTF8
Write-Host "OK: pixabay query saved -> $OutJsonPath (media=$media hits=$($hits.Count))" -ForegroundColor Green