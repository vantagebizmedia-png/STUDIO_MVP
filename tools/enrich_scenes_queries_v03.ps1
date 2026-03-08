param(
  [Parameter(Mandatory=$true)][string]$WorkspaceRoot,
  [int]$Seed = 123,
  [int]$MinScenes = 8,
  [int]$MaxScenes = 40,
  [switch]$Force,
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

$ABSTRACT = @(
  "exito","progreso","motivacion","disciplina","cambio","mejora","proceso","resultado","objetivo","meta",
  "crecimiento","avance","aprendizaje","habito","habitos","rutina","constancia","enfoque","claridad",
  "energia","bienestar","balance","equilibrio","productividad","mentalidad","mindset","vision","valor",
  "idea","ideas","estrategia","estrategias","sistema","sistemas","metodo","metodos","plan","planes",
  "decision","decisiones","prioridad","prioridades","proposito","intencion","intenciones","accion","acciones"
) | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique

$VISUAL = @(
  "persona","personas","hombre","mujer","mujeres","niño","niña","familia","pareja","amigos","equipo","reunion",
  "oficina","escritorio","computadora","laptop","teclado","pantalla","telefono","movil","celular","libro","cuaderno",
  "lapiz","cafe","cocina","comida","agua","botella","casa","hogar","habitacion","cama","sofa","mesa","silla",
  "ventana","puerta","calle","ciudad","parque","auto","coche","bicicleta","gym","gimnasio","pesas","correr",
  "caminar","manos","mano","rostro","cara","ojos","sonrisa","trabajo","estudio","escuela","clase","doctor",
  "hospital","dinero","billetes","monedas","banco","tarjeta","compra","mercado","playa","montaña","naturaleza",
  "arbol","bosque","atardecer","amanecer","noche","lluvia","sol","viaje","maleta","aeropuerto",
  "person","people","man","woman","family","team","office","desk","computer","laptop","phone","book","kitchen",
  "home","room","street","city","park","car","bike","gym","hands","face","smile","work","study","school",
  "money","bank","beach","mountain","nature","tree","forest","sunset","sunrise","travel","airport"
) | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique

function Get-KeywordScore([string]$word, [int]$count) {
  $score = [double]$count

  if ($VISUAL -contains $word)   { $score += 3.0 }
  if ($ABSTRACT -contains $word) { $score -= 2.5 }

  if ($word.Length -ge 5 -and $word.Length -le 12) { $score += 0.35 }
  if ($word.Length -gt 16) { $score -= 0.50 }

  return $score
}

function DeriveKeywords([string]$text, [int]$Top, [int]$SceneSeed) {
  $tokens = @((Tokenize $text) | Where-Object { ($STOP -notcontains $_) -and ($_.Length -ge 3) })
  if ($tokens.Count -eq 0) { return @() }

  $counts = @{}
  foreach ($w in $tokens) {
    if ($counts.ContainsKey($w)) { $counts[$w]++ } else { $counts[$w] = 1 }
  }

  $items = foreach ($k in $counts.Keys) {
    [pscustomobject]@{
      w = $k
      c = [int]$counts[$k]
      s = [double](Get-KeywordScore -word $k -count ([int]$counts[$k]))
      h = Sha256Hex("$SceneSeed|$k")
    }
  }

  return @(
    $items |
      Sort-Object `
        @{ Expression = "s"; Descending = $true }, `
        @{ Expression = "c"; Descending = $true }, `
        @{ Expression = "h"; Descending = $false } |
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

function Normalize-QueryText([string]$text, [int]$MaxLen = 90) {
  if (-not $text) { return "" }

  $t = $text.Trim().ToLowerInvariant()
  $t = [regex]::Replace($t, '[^\p{L}\p{Nd}\s\-]', ' ')
  $t = [regex]::Replace($t, '\s+', ' ').Trim()

  if ($t.Length -gt $MaxLen) {
    $t = $t.Substring(0, $MaxLen).Trim()
  }
  return $t
}

function Get-VisualAnchorTerms([string[]]$terms) {
  $anchors = @()
  $t = @($terms | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)

  function Add-Anchor([string]$value) {
    if ($value -and $value.Trim()) { $script:anchors += $value.Trim().ToLowerInvariant() }
  }

  if (@($t | Where-Object { $_ -in @("disciplina","habito","habitos","rutina","constancia") }).Count -gt 0) {
    Add-Anchor "persona escritorio agenda"
    Add-Anchor "manos cuaderno escritorio"
    Add-Anchor "laptop cafe escritorio"
  }

  if (@($t | Where-Object { $_ -in @("productividad","enfoque","plan","planes","prioridad","prioridades","trabajo") }).Count -gt 0) {
    Add-Anchor "persona trabajando laptop"
    Add-Anchor "escritorio computadora oficina"
    Add-Anchor "reunion oficina equipo"
  }

  if (@($t | Where-Object { $_ -in @("finanzas","dinero","ahorro","gastos","banco","tarjeta","inversion","inversiones") }).Count -gt 0) {
    Add-Anchor "manos dinero laptop"
    Add-Anchor "calculadora billetes mesa"
    Add-Anchor "tarjeta banco pago"
  }

  if (@($t | Where-Object { $_ -in @("ansiedad","estres","calma","bienestar","emociones","mentalidad","mindset") }).Count -gt 0) {
    Add-Anchor "persona sola ventana"
    Add-Anchor "mujer sofa mirando ventana"
    Add-Anchor "manos taza cafe"
  }

  if (@($t | Where-Object { $_ -in @("salud","bienestar","energia","ejercicio","gym","gimnasio") }).Count -gt 0) {
    Add-Anchor "persona gym pesas"
    Add-Anchor "correr parque amanecer"
    Add-Anchor "botella agua gimnasio"
  }

  if (@($t | Where-Object { $_ -in @("estudio","aprender","aprendizaje","escuela","clase","libro","lectura") }).Count -gt 0) {
    Add-Anchor "estudiante escritorio libro"
    Add-Anchor "laptop cuaderno estudio"
    Add-Anchor "biblioteca libro mesa"
  }

  if (@($t | Where-Object { $_ -in @("viaje","viajar","aeropuerto","maleta","turismo") }).Count -gt 0) {
    Add-Anchor "aeropuerto maleta persona"
    Add-Anchor "persona caminando ciudad"
    Add-Anchor "mapa maleta mesa"
  }

  if (@($t | Where-Object { $_ -in @("cocina","comida","nutricion","desayuno","almuerzo","cena") }).Count -gt 0) {
    Add-Anchor "cocina comida saludable"
    Add-Anchor "manos preparando comida"
    Add-Anchor "mesa desayuno cafe"
  }

  if (@($t | Where-Object { $_ -in @("familia","pareja","amigos","equipo","reunion") }).Count -gt 0) {
    Add-Anchor "familia hogar sonrisa"
    Add-Anchor "pareja caminando parque"
    Add-Anchor "equipo reunion oficina"
  }

  return @($anchors | Select-Object -Unique)
}

function BuildQueryCandidates([string]$topic, [string]$imageQuery, [string]$sceneText, [string[]]$kws, [int]$SceneIndex) {
  $topicN = Normalize-QueryText $topic 48
  $imgqN  = Normalize-QueryText $imageQuery 64
  $textN  = Normalize-QueryText $sceneText 64

  $kwArr = @()
  foreach ($k in @($kws)) {
    $kn = Normalize-QueryText $k 24
    if ($kn -and $kn.Length -ge 3) { $kwArr += $kn }
  }
  $kwArr = @($kwArr | Select-Object -Unique)
  $kwTop2 = @($kwArr | Select-Object -First 2)
  $kwTop4 = @($kwArr | Select-Object -First 4)

  $anchorTerms = @()
  $anchorTerms += @(Tokenize $topicN)
  $anchorTerms += @(Tokenize $imgqN)
  $anchorTerms += @(Tokenize $textN)
  $anchorTerms += @($kwTop4)
  $anchorTerms = @($anchorTerms | Where-Object { $_ } | Select-Object -Unique)

  $anchors = @(Get-VisualAnchorTerms -terms $anchorTerms)

  $candidates = @()

  foreach ($anchor in $anchors) {
    $candidates += (Normalize-QueryText ("$anchor photo") 90)
    if ($topicN) {
      $candidates += (Normalize-QueryText ("$topicN $anchor photo") 90)
    }
  }

  if ($imgqN) {
    $candidates += (Normalize-QueryText ("$imgqN photo") 90)
    if ($topicN) {
      $candidates += (Normalize-QueryText ("$topicN $imgqN photo") 90)
    }
  }

  if ($textN) {
    $candidates += (Normalize-QueryText ("$textN photo") 90)
    if ($topicN) {
      $candidates += (Normalize-QueryText ("$topicN $textN photo") 90)
    }
  }

  if ($kwTop4.Count -gt 0) {
    $kwText = ($kwTop4 -join " ")
    $candidates += (Normalize-QueryText ("$kwText photo") 90)
    if ($topicN) {
      $candidates += (Normalize-QueryText ("$topicN $kwText photo") 90)
    }
  }

  if ($topicN -and $kwTop2.Count -gt 0) {
    $candidates += (Normalize-QueryText ("$topicN $($kwTop2 -join ' ') photo") 90)
  }

  if ($topicN) {
    $candidates += (Normalize-QueryText ("$topicN photo") 90)
  }

  if ($anchors.Count -eq 0 -and $candidates.Count -eq 0) {
    $fallback = ("stock background scene {0:000} photo" -f ($SceneIndex + 1))
    if ($topicN) {
      $fallback = "$topicN $fallback"
    }
    $candidates += (Normalize-QueryText $fallback 90)
  }

  return @(
    $candidates |
      Where-Object { $_ -and $_.Trim().Length -ge 3 } |
      Select-Object -Unique
  )
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

if ($scenes.Count -lt $MinScenes) {
  Write-Host ("WARN: scenes_v03 por debajo de MinScenes. scenes={0} min={1}" -f $scenes.Count, $MinScenes) -ForegroundColor Yellow
}
if ($scenes.Count -gt $MaxScenes) {
  Write-Host ("WARN: scenes_v03 por encima de MaxScenes. scenes={0} max={1}" -f $scenes.Count, $MaxScenes) -ForegroundColor Yellow
}

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

  $queryCandidates = @(BuildQueryCandidates -topic $topic -imageQuery $imgq -sceneText $sceneText -kws $kws -SceneIndex $i)
  $q = ""
  if ($queryCandidates.Count -gt 0) { $q = [string]$queryCandidates[0] }

  Ensure-Pso -parent $scene -name "assets"
  Ensure-Pso -parent $scene.assets -name "image"
  Set-Note -obj $scene.assets.image -name "query" -value $q
  Set-Note -obj $scene.assets.image -name "query_candidates" -value $queryCandidates

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

    $hits = @()
    $usedQuery = ""
    $cacheJson = ""

    foreach ($candidate in $queryCandidates) {
      if (-not $candidate) { continue }

      $safeName = ("scene_{0:000}_{1}" -f ($i + 1), (Sha256Hex $candidate).Substring(0,12))
      $cacheJson = Join-Path $cacheDir ($safeName + ".json")

      & $stock -Query $candidate -OutJsonPath $cacheJson -Seed ($Seed + $i) -PerPage $PerPage | Out-Null

      $pj = Get-Content -LiteralPath $cacheJson -Raw -Encoding UTF8 | ConvertFrom-Json
      $candidateHits = @()
      if ($pj -and (Has-Prop $pj "hits") -and $pj.hits) { $candidateHits = @($pj.hits) }

      if ($candidateHits.Count -gt 0) {
        $hits = $candidateHits
        $usedQuery = [string]$candidate
        break
      }
    }

    Set-Note -obj $scene.assets.image -name "provider" -value "pixabay"
    Set-Note -obj $scene.assets.image -name "used_query" -value $usedQuery
    Set-Note -obj $scene.assets.image -name "hits_count" -value $hits.Count

    if ($hits.Count -lt 1) {
      Set-Note -obj $scene.assets.image -name "note" -value "pixabay: 0 hits"
      $withoutHits++
      continue
    }

    $idx = Pick-DeterministicIndex -GlobalSeed $Seed -SceneIndex $i -Query $usedQuery -Count $hits.Count
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