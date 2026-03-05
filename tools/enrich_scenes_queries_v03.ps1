param(
  [Parameter(Mandatory=$true)][string]$WorkspaceRoot,
  [int]$Seed = 123,
  [int]$TopK = 6,
  [switch]$DownloadPixabay,
  [string]$PixabayApiKey = "",
  [int]$PerPage = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ws = (Resolve-Path -LiteralPath $WorkspaceRoot).Path

if ($TopK -lt 1) { $TopK = 1 }
if ($TopK -gt 15) { $TopK = 15 }
if ($PerPage -lt 3) { $PerPage = 3 }
if ($PerPage -gt 200) { $PerPage = 200 }

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Sha256Hex([string]$s) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($s)
  $hash = $sha.ComputeHash($bytes)
  return ($hash | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Has-Prop([object]$obj, [string]$name) {
  if ($null -eq $obj) { return $false }
  return ($obj.PSObject.Properties.Match($name).Count -gt 0)
}

function Get-PropValue([object]$obj, [string]$name) {
  if ($null -eq $obj) { return $null }
  if ($obj.PSObject.Properties.Match($name).Count -eq 0) { return $null }
  return $obj.$name
}

function Convert-ToPso([object]$value) {
  if ($null -eq $value) { return [pscustomobject]@{} }
  if ($value -is [pscustomobject]) { return $value }
  if ($value -is [System.Collections.IDictionary]) {
    $h = @{}
    foreach ($k in $value.Keys) { $h[[string]$k] = $value[$k] }
    return [pscustomobject]$h
  }
  if ($value -is [string] -or $value -is [ValueType]) { return [pscustomobject]@{} }
  return [pscustomobject]$value
}

function Ensure-Pso([object]$parent, [string]$name) {
  if ($null -eq $parent) { throw "Ensure-Pso: parent null" }
  if (-not (Has-Prop $parent $name)) {
    $parent | Add-Member -NotePropertyName $name -NotePropertyValue ([pscustomobject]@{}) -Force
    return
  }
  $parent.$name = Convert-ToPso $parent.$name
}

function Set-Note([object]$obj, [string]$name, $value) {
  if ($null -eq $obj) { throw "Set-Note: obj null" }
  if (Has-Prop $obj $name) { $obj.$name = $value }
  else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }
}

function Tokenize([string]$text) {
  if (-not $text) { return @() }
  $t = $text.ToLowerInvariant()
  $t = [regex]::Replace($t, "[^a-z0-9\u00e1\u00e9\u00ed\u00f3\u00fa\u00fc\u00f1 ]+", " ")
  $t = [regex]::Replace($t, "\s+", " ").Trim()
  if (-not $t) { return @() }
  return @($t.Split(" ") | Where-Object { $_.Length -ge 3 })
}

$STOP = @(
  "para","con","sin","por","del","las","los","una","uno","unas","unos","este","esta","estos","estas",
  "que","como","cuando","donde","porque","pero","mas","menos","muy","ya","hoy","ayer","ahora",
  "tu","tus","su","sus","mi","mis","me","te","se","nos","les","lo","la","el","y","o","u","de","a","en","al",
  "the","and","with","without","for","from","this","that","these","those","your","you","are","was","were","has","have"
) | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique

function DeriveKeywords([string]$text, [int]$Top, [int]$SceneSeed) {
  $tokens = @((Tokenize $text) | Where-Object { $STOP -notcontains $_ })
  if ($tokens.Count -eq 0) { return @() }

  $counts = @{}
  foreach ($w in $tokens) {
    if ($counts.ContainsKey($w)) { $counts[$w]++ } else { $counts[$w] = 1 }
  }

  $items = foreach ($k in $counts.Keys) {
    [pscustomobject]@{
      w = $k
      c = [int]$counts[$k]
      h = Sha256Hex("$SceneSeed|$k")
    }
  }

  return @(
    $items |
      Sort-Object @{ Expression = "c"; Descending = $true }, @{ Expression = "h"; Descending = $false } |
      Select-Object -First $Top |
      ForEach-Object { $_.w }
  )
}

function Get-SceneText([object]$scene) {
  foreach ($k in @("script_text", "image_query", "text", "caption", "narration")) {
    $v = Get-PropValue $scene $k
    if ($v -and ($v -is [string])) {
      $s = $v.Trim()
      if ($s) { return $s }
    }
  }
  return ""
}

function BuildQuery([string]$topic, [string]$imageQuery, [string[]]$kws, [int]$SceneIndex) {
  $parts = @()
  foreach ($part in @($topic, $imageQuery, ($kws -join " "))) {
    if ($part -and $part.Trim()) { $parts += $part.Trim() }
  }

  $base = ($parts -join " ").Trim()
  if (-not $base -or $base.Length -lt 3) {
    $base = "stock background scene {0:000}" -f ($SceneIndex + 1)
    if ($topic -and $topic.Trim()) {
      $base = ("{0} {1}" -f $topic.Trim(), $base).Trim()
    }
  }

  $q = [regex]::Replace(($base + " photo").Trim(), "\s+", " ")
  if ($q.Length -gt 90) { $q = $q.Substring(0, 90).Trim() }
  return $q
}

function Resolve-Manifest([string]$Root) {
  $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
  $candidates = @(
    (Join-Path $resolvedRoot "runs\smoke_live_latest\manifest_v03.json"),
    (Join-Path $resolvedRoot "runs\smoke_live_latest\artifacts\manifest_v03.json"),
    (Join-Path $resolvedRoot "artifacts\manifest_v03.json"),
    (Join-Path $resolvedRoot "manifest_v03.json"),
    (Join-Path $resolvedRoot "runs\smoke_live_latest\handoff_v03\manifest_v03.json")
  )

  $existing = @()
  foreach ($p in $candidates) {
    if ($p -and (Test-Path -LiteralPath $p)) { $existing += $p }
  }

  if ($existing.Count -gt 0) {
    $best = $existing |
      ForEach-Object { Get-Item -LiteralPath $_ } |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    return $best.FullName
  }

  $found = Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Filter "manifest_v03.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if ($found) { return $found.FullName }
  throw "No encuentro manifest_v03.json en: $Root"
}

function Try-GetTopic($json) {
  try {
    $tg = Get-PropValue $json "text_generation"
    if (-not $tg) { return "" }

    $topics = Get-PropValue $tg "topics"
    if ($topics -is [string]) {
      $t = $topics.Trim()
      if ($t) { return $t }
      return ""
    }

    if ($topics) {
      $arr = @($topics)
      if ($arr.Count -gt 0 -and $arr[0]) { return [string]$arr[0] }
    }
  }
  catch { }
  return ""
}

function Pick-DeterministicIndex([int]$GlobalSeed, [int]$SceneIndex, [string]$Query, [int]$Count) {
  if ($Count -le 1) { return 0 }
  $h = Sha256Hex("$GlobalSeed|$SceneIndex|$Query")
  $x = [Convert]::ToUInt32($h.Substring(0, 8), 16)
  return [int]($x % [uint32]$Count)
}

$manifest = Resolve-Manifest -Root $WorkspaceRoot
$json = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not (Has-Prop $json "scenes_v03")) {
  throw "manifest no tiene scenes_v03. Corre apply_scene_builder_v03.ps1 primero."
}

$scenes = @()
if ($json.scenes_v03 -is [System.Array]) { $scenes = @($json.scenes_v03) }
elseif ($json.scenes_v03 -is [System.Collections.IDictionary]) { $scenes = @($json.scenes_v03.Values) }
else { $scenes = @($json.scenes_v03) }

if ($scenes.Count -lt 1) { throw "scenes_v03 esta vacio" }

$topic = Try-GetTopic $json
$manifestDir = Split-Path -Parent $manifest

$stock = Join-Path $repo "tools\stock_query_pixabay_v03.ps1"
$dl = Join-Path $repo "tools\download_file_v03.ps1"
if ($DownloadPixabay) {
  if (-not (Test-Path -LiteralPath $stock)) { throw "Falta: $stock" }
  if (-not (Test-Path -LiteralPath $dl)) { throw "Falta: $dl" }
}

$downloaded = 0
$withoutHits = 0
$withErrors = 0

for ($i = 0; $i -lt $scenes.Count; $i++) {
  $scene = $scenes[$i]

  $sceneText = Get-SceneText $scene
  $kws = @(DeriveKeywords -text $sceneText -Top $TopK -SceneSeed ($Seed + $i))

  Ensure-Pso -parent $scene -name "meta"
  Set-Note -obj $scene.meta -name "keywords" -value $kws

  $imgq = ""
  $imgRaw = Get-PropValue $scene "image_query"
  if ($imgRaw -and ($imgRaw -is [string])) { $imgq = $imgRaw.Trim() }

  $q = BuildQuery -topic $topic -imageQuery $imgq -kws $kws -SceneIndex $i

  Ensure-Pso -parent $scene -name "assets"
  Ensure-Pso -parent $scene.assets -name "image"
  Set-Note -obj $scene.assets.image -name "query" -value $q

  if (-not $DownloadPixabay) { continue }

  $prev = $env:PIXABAY_API_KEY
  try {
    if ($PixabayApiKey -and $PixabayApiKey.Trim().Length -ge 8) {
      $env:PIXABAY_API_KEY = $PixabayApiKey
    }

    $cacheDir = Join-Path $manifestDir "pixabay_cache_v03"
    if (-not (Test-Path -LiteralPath $cacheDir)) {
      New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    }
    $cacheJson = Join-Path $cacheDir ("scene_{0:000}.json" -f ($i + 1))

    & $stock -Query $q -OutJsonPath $cacheJson -Seed ($Seed + $i) -PerPage $PerPage | Out-Null

    $pj = Get-Content -LiteralPath $cacheJson -Raw -Encoding UTF8 | ConvertFrom-Json
    $hits = @()
    if ($pj -and (Has-Prop $pj "hits") -and $pj.hits) { $hits = @($pj.hits) }

    Set-Note -obj $scene.assets.image -name "provider" -value "pixabay"
    Set-Note -obj $scene.assets.image -name "hits_count" -value $hits.Count

    if ($hits.Count -lt 1) {
      Set-Note -obj $scene.assets.image -name "note" -value "pixabay: 0 hits"
      $withoutHits++
      continue
    }

    $idx = Pick-DeterministicIndex -GlobalSeed $Seed -SceneIndex $i -Query $q -Count $hits.Count
    $hit = $hits[$idx]

    $url = ""
    if ($hit -and (Has-Prop $hit "url") -and $hit.url) {
      $url = [string]$hit.url
    }
    if (-not $url) {
      Set-Note -obj $scene.assets.image -name "note" -value "pixabay: hit sin .url"
      $withErrors++
      continue
    }

    $outDir = Join-Path $ws "assets\scenes_v03"
    if (-not (Test-Path -LiteralPath $outDir)) {
      New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }

    $outPath = Join-Path $outDir ("scene_{0:000}.jpg" -f ($i + 1))
    & $dl -Url $url -OutPath $outPath | Out-Null

    Set-Note -obj $scene.assets.image -name "path" -value (Resolve-Path -LiteralPath $outPath).Path
    Set-Note -obj $scene.assets.image -name "picked_index" -value $idx
    Set-Note -obj $scene.assets.image -name "source_url" -value $url
    $downloaded++
  }
  catch {
    Set-Note -obj $scene.assets.image -name "provider" -value "pixabay"
    Set-Note -obj $scene.assets.image -name "note" -value ("pixabay error: " + $_.Exception.Message)
    $withErrors++
  }
  finally {
    $env:PIXABAY_API_KEY = $prev
  }
}

$json.scenes_v03 = $scenes

$outJson = $json | ConvertTo-Json -Depth 99
$outJson = $outJson -replace "`r`n", "`n"
Write-Utf8NoBom -Path $manifest -Text $outJson

if ($DownloadPixabay) {
  Write-Host ("OK enrich scenes queries -> {0} (downloaded={1}, no_hits={2}, errors={3})" -f $manifest, $downloaded, $withoutHits, $withErrors) -ForegroundColor Green
}
else {
  Write-Host "OK enrich scenes queries -> $manifest" -ForegroundColor Green
}
