param(
  [Parameter(Mandatory=$true)][string]$ManifestPath,
  [int]$Seed = 123
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

function Has-Prop($obj, [string]$name) {
  if ($null -eq $obj) { return $false }
  return ($obj.PSObject.Properties.Name -contains $name)
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "No existe manifest: $ManifestPath"
}

$json = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not (Has-Prop $json "scenes_v03") -or -not $json.scenes_v03) {
  throw "manifest sin scenes_v03"
}

$rand = [System.Random]::new($Seed)

foreach ($scene in $json.scenes_v03) {

  # Si ya tiene stock_query, no tocar
  if (Has-Prop $scene "stock_query") {
    if ($scene.stock_query -and ($scene.stock_query.ToString().Trim().Length -gt 0)) { continue }
  }

  $base = $null
  if (Has-Prop $scene "text") { $base = $scene.text }
  if (-not $base -or ($base.ToString().Trim().Length -eq 0)) { $base = "motivational concept" }

  $tokens = $base.ToString().Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries) |
    Where-Object { $_.Length -gt 3 }

  if ($tokens.Count -gt 3) { $tokens = $tokens[0..2] }

  $query = ($tokens -join " ")
  if (-not $query -or $query.Trim().Length -eq 0) { $query = "motivational concept" }

  $style = @(
    "cinematic lighting",
    "dramatic composition",
    "soft depth of field",
    "high contrast"
  )

  $q = "{0}, {1}" -f $query, $style[$rand.Next(0,$style.Count)]

  if (Has-Prop $scene "stock_query") {
    $scene.stock_query = $q
  } else {
    $scene | Add-Member -NotePropertyName stock_query -NotePropertyValue $q
  }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText(
  $ManifestPath,
  ($json | ConvertTo-Json -Depth 50),
  $utf8NoBom
)

Write-Host "OK: scene queries enriquecidas -> $ManifestPath" -ForegroundColor Green