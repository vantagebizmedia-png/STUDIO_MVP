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


function Get-AssetPathString {
  param($RawValue)

  $currentPath = ""

  if ($RawValue -is [string]) {
    $currentPath = [string]$RawValue
  }
  elseif ($RawValue -is [System.Collections.IDictionary]) {
    if ($RawValue.Contains("path") -and $RawValue["path"]) {
      $currentPath = [string]$RawValue["path"]
    }
  }
  elseif ($RawValue -is [System.Collections.IEnumerable] -and -not ($RawValue -is [string])) {
    $arr = @($RawValue)
    if ($arr.Count -gt 0 -and $null -ne $arr[0]) {
      $first = $arr[0]

      if ($first -is [string]) {
        $currentPath = [string]$first
      }
      elseif ($first -is [System.Collections.IDictionary]) {
        if ($first.Contains("path") -and $first["path"]) {
          $currentPath = [string]$first["path"]
        }
      }
      elseif ($null -ne $first -and $first.PSObject.Properties.Name -contains "path") {
        try { $currentPath = [string]$first.path } catch { $currentPath = "" }
      }
    }
  }
  elseif ($null -ne $RawValue -and $RawValue.PSObject.Properties.Name -contains "path") {
    try { $currentPath = [string]$RawValue.path } catch { $currentPath = "" }
  }

  return ([string]$currentPath).Trim()
}

function Get-SceneRequestedMediaType {
  param([object]$Scene)

  if (-not $Scene) { return "image" }

  $visualCapability = ""
  if (Has-Prop $Scene "visual_capability" -and $Scene.visual_capability) {
    $visualCapability = ([string]$Scene.visual_capability).Trim().ToLowerInvariant()
  }

  $visualKind = ""
  if (Has-Prop $Scene "visual_kind" -and $Scene.visual_kind) {
    $visualKind = ([string]$Scene.visual_kind).Trim().ToLowerInvariant()
  }

  if ($visualCapability -eq "stock_video") { return "video" }
  if ($visualKind -eq "video") { return "video" }

  return "image"
}

function Get-SceneVisualMetaTarget {
  param([object]$Scene)

  if (-not $Scene) { return $null }

  Ensure-Pso -parent $Scene -name "assets"
  Ensure-Pso -parent $Scene -name "meta"

  if (-not ($Scene.assets.PSObject.Properties.Name -contains "audio_clip")) {
    $Scene.assets | Add-Member -NotePropertyName audio_clip -NotePropertyValue "" -Force
  }

  $currentImagePath = ""
  if ($Scene.assets.PSObject.Properties.Name -contains "image") {
    $currentImagePath = Get-AssetPathString -RawValue $Scene.assets.image
  }

  if (-not ($Scene.assets.PSObject.Properties.Name -contains "image")) {
    $Scene.assets | Add-Member -NotePropertyName image -NotePropertyValue $currentImagePath -Force
  }
  else {
    $Scene.assets.image = $currentImagePath
  }

  $currentVideoPath = ""
  if ($Scene.assets.PSObject.Properties.Name -contains "video") {
    $currentVideoPath = Get-AssetPathString -RawValue $Scene.assets.video
  }

  if (-not ($Scene.assets.PSObject.Properties.Name -contains "video")) {
    $Scene.assets | Add-Member -NotePropertyName video -NotePropertyValue $currentVideoPath -Force
  }
  else {
    $Scene.assets.video = $currentVideoPath
  }

  if (-not (Has-Prop $Scene.meta "visual_enrich")) {
    $Scene.meta | Add-Member -NotePropertyName visual_enrich -NotePropertyValue ([pscustomobject]@{}) -Force
  }
  else {
    $Scene.meta.visual_enrich = Convert-ToPso $Scene.meta.visual_enrich
  }

  return $Scene.meta.visual_enrich
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
  "caminar","manos","mano","camara","cámara","rostro","cara","ojos","sonrisa","trabajo","estudio","escuela","clase","doctor",
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
  $sharedPath = Join-Path $PSScriptRoot "scene_narrative_shared_v03.ps1"
  if (-not (Test-Path -LiteralPath $sharedPath -PathType Leaf)) {
    throw ("No existe helper narrative compartido: {0}" -f $sharedPath)
  }

  . $sharedPath
  return (Get-SceneTextShared -Scene $scene)
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
  $anchors = New-Object System.Collections.Generic.List[string]
  $t = @($terms | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant().Trim() } | Where-Object { $_ } | Select-Object -Unique)

  function Add-Anchor([string]$value) {
    if ($value -and $value.Trim()) {
      [void]$anchors.Add($value.Trim().ToLowerInvariant())
    }
  }

  if (@($t | Where-Object { $_ -in @("disciplina","habito","habitos","rutina","constancia","orden","consistencia","recordar","agenda","cuaderno") }).Count -gt 0) {
    Add-Anchor "persona escritorio agenda"
    Add-Anchor "manos cuaderno escritorio"
    Add-Anchor "laptop cafe escritorio"
  }

  if (@($t | Where-Object { $_ -in @("productividad","enfoque","plan","planes","prioridad","prioridades","trabajo","organizacion","organizar","objetivo","objetivos") }).Count -gt 0) {
    Add-Anchor "persona trabajando laptop"
    Add-Anchor "escritorio computadora oficina"
    Add-Anchor "reunion oficina equipo"
  }

  if (@($t | Where-Object { $_ -in @("finanzas","dinero","ahorro","gastos","banco","tarjeta","inversion","inversiones","deuda","presupuesto") }).Count -gt 0) {
    Add-Anchor "manos dinero laptop"
    Add-Anchor "calculadora billetes mesa"
    Add-Anchor "tarjeta banco pago"
  }

  if (@($t | Where-Object { $_ -in @("ansiedad","estres","calma","bienestar","emociones","mentalidad","mindset","respirar","respiracion") }).Count -gt 0) {
    Add-Anchor "persona sola ventana"
    Add-Anchor "mujer sofa mirando ventana"
    Add-Anchor "manos taza cafe"
  }

  if (@($t | Where-Object { $_ -in @("salud","bienestar","energia","ejercicio","gym","gimnasio","entrenamiento","peso","pesas") }).Count -gt 0) {
    Add-Anchor "persona gym pesas"
    Add-Anchor "correr parque amanecer"
    Add-Anchor "botella agua gimnasio"
  }

  if (@($t | Where-Object { $_ -in @("estudio","aprender","aprendizaje","escuela","clase","libro","lectura","universidad") }).Count -gt 0) {
    Add-Anchor "estudiante escritorio libro"
    Add-Anchor "laptop cuaderno estudio"
    Add-Anchor "biblioteca libro mesa"
  }

  if (@($t | Where-Object { $_ -in @("viaje","viajar","aeropuerto","maleta","turismo","vacaciones") }).Count -gt 0) {
    Add-Anchor "aeropuerto maleta persona"
    Add-Anchor "persona caminando ciudad"
    Add-Anchor "mapa maleta mesa"
  }

  if (@($t | Where-Object { $_ -in @("cocina","comida","nutricion","desayuno","almuerzo","cena","receta") }).Count -gt 0) {
    Add-Anchor "cocina comida saludable"
    Add-Anchor "manos preparando comida"
    Add-Anchor "mesa desayuno cafe"
  }

  if (@($t | Where-Object { $_ -in @("familia","pareja","amigos","equipo","reunion","hogar") }).Count -gt 0) {
    Add-Anchor "familia hogar sonrisa"
    Add-Anchor "pareja caminando parque"
    Add-Anchor "equipo reunion oficina"
  }

  if (@($t | Where-Object { $_ -in @("problema","situacion","cotidiana","cotidiano","resolver","solucion","atencion","interes") }).Count -gt 0) {
    Add-Anchor "persona pensando escritorio"
    Add-Anchor "persona mirando laptop"
    Add-Anchor "situacion cotidiana hogar"
  }

  if (@($t | Where-Object { $_ -in @("frase","mensaje","idea","concepto","explicacion","contexto","lenguaje","claro","simple") }).Count -gt 0) {
    Add-Anchor "persona hablando camara"
    Add-Anchor "persona oficina fondo neutro"
    Add-Anchor "manos cuaderno mesa"
  }

  if ($anchors.Count -eq 0) {
    if (@($t | Where-Object { $VISUAL -contains $_ }).Count -gt 0) {
      Add-Anchor "persona lifestyle"
      Add-Anchor "real life scene"
    }
  }

  if ($anchors.Count -eq 0) {
    Add-Anchor "persona escritorio"
    Add-Anchor "person lifestyle"
  }

  return @($anchors | Select-Object -Unique)
}
function Get-ConcreteSceneTerms([string[]]$terms, [int]$Top = 4) {
  $items = New-Object System.Collections.Generic.List[object]

  foreach ($term in @($terms | Where-Object { $_ })) {
    $w = $term.ToLowerInvariant().Trim()
    if (-not $w) { continue }
    if ($STOP -contains $w) { continue }

    if ($w.Length -lt 4) { continue }
    if ($w.Length -gt 18) { continue }
    if ($w -match '\d') { continue }
    if ($w -match '^(photo|scene|video|visual|lifestyle|real|life|persona|person)$') { continue }

    if ($w -match '^(inicio|directo|idea|clara|frase|simple|facil|fácil|mantener|interes|interés|contexto|lenguaje|breve|visual|problema|central|video|busca|resolver|cotidiana|cotidiano|reconocible|presentamos|introducimos|conectamos|marcamos|abrimos|segundo|tema|principal|escena|siguiente|claro|situacion|situación|rec|visu|atencion|atención|captar|recordar|promesa|concreta|mensaje|explicacion|explicación|concepto)$') {
      continue
    }

    $score = 0.0

    if ($VISUAL -contains $w)   { $score += 5.0 } else { $score += 0.5 }
    if ($ABSTRACT -contains $w) { $score -= 4.0 }

    if ($w -match '(ando|iendo|ados|adas|able|ibles|mente|cion|ción|sion|dad|ez)$') {
      $score -= 2.5
    }

    if ($w.Length -ge 5 -and $w.Length -le 12) { $score += 0.5 }

    $items.Add([pscustomobject]@{
      term  = $w
      score = $score
      hash  = Sha256Hex("concrete|$w")
    }) | Out-Null
  }

  return @(
    $items |
      Where-Object { $_.score -ge 4.5 } |
      Sort-Object `
        @{ Expression = "score"; Descending = $true }, `
        @{ Expression = "hash";  Descending = $false } |
      Select-Object -ExpandProperty term -Unique |
      Select-Object -First $Top
  )
}
function BuildQueryCandidates([string]$topic, [string]$imageQuery, [string]$sceneText, [string[]]$kws, [int]$SceneIndex) {
  $topicN = Normalize-QueryText $topic 40
  $imgqN  = Normalize-QueryText $imageQuery 56
  $textN  = Normalize-QueryText $sceneText 56
  $residualPattern = '^(inicio|directo|idea|clara|frase|simple|facil|fácil|mantener|interes|interés|contexto|lenguaje|breve|visual|problema|central|video|busca|resolver|cotidiana|cotidiano|reconocible|presentamos|introducimos|conectamos|marcamos|abrimos|segundo|tema|principal|escena|siguiente|claro|situacion|situación|rec|visu|atencion|atención|captar|recordar|promesa|concreta|concreto|mensaje|explicacion|explicación|concepto|facilmente|fácilmente|interesar|interesa|resolverlo|resuelve|narrativa|cierre|micro|util|útil|mostramos|cambiamos|pasamos|reforzamos|insertamos|hacemos|evitar|mostrado|reutilizar|limpio|importante)$'
  $verbPattern = '^(mostramos|cambiamos|pasamos|reforzamos|insertamos|hacemos|evitar|mostrado|reutilizar)$|((ar|er|ir|ando|iendo|ado|ido|amos|emos|imos))$'
  $hardDrop = @(
    "darle","punto","sencilla","audiencia","pensada","hacia","importante","ultima","última","ejemplo","pausa",
    "siguiente","principal","problema","idea","mensaje","narrativa","cierre","micro","visual","claro","breve","simple","util","útil","directo","concreta","concreto"
  )

  $kwArr = @()
  foreach ($k in @($kws)) {
    $kn = Normalize-QueryText $k 24
    if ($kn -and $kn.Length -ge 3) { $kwArr += $kn }
  }
  $kwArr = @($kwArr | Select-Object -Unique)
  $discursiveTerms = @(
    "promesa","mensaje","cierre","recordar","explicacion","explicación","explicar",
    "directa","directo","atencion","atención","frase","contundente","camara","cámara"
  )
  $discursiveTokens = @(
    (Tokenize $topicN) +
    (Tokenize $imgqN) +
    (Tokenize $textN) +
    @($kwArr)
  ) | Where-Object { $_ } | Select-Object -Unique
  $hasDiscursiveSignal = @($discursiveTokens | Where-Object { $discursiveTerms -contains $_ }).Count -gt 0

  $anchorTerms = @()
  $anchorTerms += @(Tokenize $topicN)
  $anchorTerms += @(Tokenize $imgqN)
  $anchorTerms += @(Tokenize $textN)
  $anchorTerms += @($kwArr)
  $anchorTerms = @($anchorTerms | Where-Object { $_ } | Select-Object -Unique)
  $anchorVisualCount = @($anchorTerms | Where-Object { $VISUAL -contains $_ }).Count

  $anchors = @(Get-VisualAnchorTerms -terms $anchorTerms)
  $concreteTerms = @(Get-ConcreteSceneTerms -terms $anchorTerms -Top 4)
  $concreteTop2 = @($concreteTerms | Select-Object -First 2)

  $kwUseful = @(
    $kwArr |
      Where-Object {
        $_ -and
        $_.Length -ge 4 -and
        $_ -notmatch '^(inicio|directo|idea|clara|frase|simple|facil|fácil|mantener|interes|interés|contexto|lenguaje|breve|visual|problema|central|video|busca|resolver|cotidiana|cotidiano|reconocible|presentamos|introducimos|conectamos|marcamos|abrimos|segundo|tema|principal|escena|siguiente|claro|situacion|situación|rec|visu|atencion|atención|captar|recordar|promesa|concreta|mensaje|explicacion|explicación|concepto|facilmente|fácilmente|interesar|interesa|resolverlo|resuelve)$'
      } |
      Select-Object -First 2
  )

  $subjectTerms = @()
  if ($concreteTop2.Count -gt 0) {
    $subjectTerms = @($concreteTop2)
  }
  elseif ($kwUseful.Count -gt 0) {
    $subjectTerms = @($kwUseful)
  }

  $candidates = New-Object System.Collections.Generic.List[string]
  $anchorVisualPool = @(
    @($anchorTerms | Where-Object { $VISUAL -contains $_ }) +
    @((@($anchors | ForEach-Object { Tokenize ([string]$_) }) | ForEach-Object { $_ }) | Where-Object { $VISUAL -contains $_ })
  ) | Select-Object -Unique

  function Add-Candidate([string]$value) {
    $q = Normalize-QueryText $value 90
    $filtered = @(
      (Tokenize $q) |
      Where-Object {
        $_ -and
        ($_ -ne "photo") -and
        ($_.Length -ge 3) -and
        ($STOP -notcontains $_) -and
        ($ABSTRACT -notcontains $_) -and
        ($_ -notmatch $verbPattern) -and
        ($_ -notmatch $residualPattern)
      } |
      Select-Object -Unique
    )

    if ($filtered.Count -eq 0) { return }

    $visualTokens = @($filtered | Where-Object { $VISUAL -contains $_ } | Select-Object -Unique)
    $otherTokens  = @($filtered | Where-Object { $VISUAL -notcontains $_ } | Select-Object -Unique)

    $tokens = @($visualTokens + $otherTokens | Select-Object -Unique)

    if ($visualTokens.Count -eq 0) {
      if ($anchorVisualCount -gt 0) { return }
      $tokens = @("persona") + $tokens
      $tokens = @($tokens | Select-Object -Unique)
    }

    $tokens = @($tokens | Select-Object -First 24)
    if ($tokens.Count -eq 0) { return }

    $q = (($tokens -join " ") + " photo").Trim()
    if ($q -and $q.Trim().Length -ge 3) {
      $candidates.Add($q) | Out-Null
    }
  }

  function Get-FallbackCompactQuery([string[]]$visualPool) {
    $vp = @($visualPool | Where-Object { $_ } | Select-Object -Unique)
    if (@($vp | Where-Object { $_ -in @("manos","mano","cuaderno") }).Count -gt 0) { return "manos cuaderno photo" }
    if (@($vp | Where-Object { $_ -in @("camara","cámara","rostro","cara") }).Count -gt 0) { return "persona camara photo" }
    if (@($vp | Where-Object { $_ -in @("escritorio","oficina","computadora","laptop") }).Count -gt 0) { return "persona escritorio photo" }
    return "persona escritorio photo"
  }

  function Compact-VisualQuery([string]$query, [string[]]$visualPool) {
    $qt = @(
      (Tokenize $query) |
      Where-Object {
        $_ -and
        ($_ -ne "photo") -and
        ($VISUAL -contains $_) -and
        ($ABSTRACT -notcontains $_) -and
        ($STOP -notcontains $_) -and
        ($hardDrop -notcontains $_) -and
        ($_ -notmatch $verbPattern) -and
        ($_ -notmatch $residualPattern)
      } |
      Select-Object -Unique
    )

    if ($qt.Count -lt 2) {
      return (Get-FallbackCompactQuery -visualPool $visualPool)
    }

    $maxTokens = 3
    if ($qt.Count -ge 4) {
      $first4 = @($qt | Select-Object -First 4)
      if ($first4.Count -eq 4 -and @($first4 | Where-Object { $VISUAL -contains $_ }).Count -eq 4) {
        $maxTokens = 4
      }
    }

    $picked = @($qt | Select-Object -First $maxTokens)
    if ($picked.Count -gt 3 -and @($picked | Where-Object { $VISUAL -contains $_ }).Count -lt $picked.Count) {
      $picked = @($picked | Select-Object -First 3)
    }

    if ($picked.Count -lt 2) {
      return (Get-FallbackCompactQuery -visualPool $visualPool)
    }

    return ((@($picked | Select-Object -Unique) -join " ") + " photo").Trim()
  }

  function Get-QueryCategory([string]$query) {
    $qt = @((Tokenize $query) | Where-Object { $_ -and $_ -ne "photo" } | Select-Object -Unique)
    if (@($qt | Where-Object { $_ -in @("manos","mano","cuaderno","mesa") }).Count -gt 0) { return "hands" }
    if (@($qt | Where-Object { $_ -in @("camara","cámara","rostro","cara") }).Count -gt 0) { return "camera" }
    if (@($qt | Where-Object { $_ -in @("reunion","reunión","equipo","oficina") }).Count -gt 0) { return "team" }
    if (@($qt | Where-Object { $_ -in @("laptop","computadora","escritorio","oficina") }).Count -gt 0) { return "desk" }
    return "other"
  }

  foreach ($anchor in $anchors) {
    if ($subjectTerms.Count -gt 0) {
      Add-Candidate "$anchor $($subjectTerms -join ' ') photo"
    }
    Add-Candidate "$anchor photo"
    if ($topicN) {
      Add-Candidate "$topicN $anchor photo"
    }
  }

  if ($imgqN) {
    Add-Candidate "$imgqN photo"
    if ($subjectTerms.Count -gt 0) {
      Add-Candidate "$imgqN $($subjectTerms -join ' ') photo"
    }
  }

  if ($topicN -and $subjectTerms.Count -gt 0) {
    Add-Candidate "$topicN $($subjectTerms -join ' ') photo"
  }

  if ($topicN) {
    Add-Candidate "$topicN photo"
  }

  function Get-RotatedTokens([string[]]$tokens, [int]$take) {
    $arr = @($tokens | Where-Object { $_ } | Select-Object -Unique)
    if ($arr.Count -eq 0) { return @() }
    if ($arr.Count -le $take) { return $arr }
    $offset = (($SceneIndex % $arr.Count) + $arr.Count) % $arr.Count
    $rot = @()
    for ($i = 0; $i -lt $arr.Count; $i++) {
      $rot += $arr[(($offset + $i) % $arr.Count)]
    }
    return @($rot | Select-Object -First $take)
  }

  $visualSource = @(
    @($anchorVisualPool) +
    @($concreteTerms | Where-Object { $_ -and ($VISUAL -contains $_) }) +
    @($subjectTerms | Where-Object { $_ -and ($VISUAL -contains $_) })
  ) | Select-Object -Unique

  $familyHands  = @($visualSource | Where-Object { $_ -in @("manos","mano","cuaderno","mesa") } | Select-Object -Unique)
  $familyDesk   = @($visualSource | Where-Object { $_ -in @("persona","laptop","computadora","escritorio","oficina") } | Select-Object -Unique)
  $familyTeam   = @($visualSource | Where-Object { $_ -in @("reunion","reunión","equipo","oficina") } | Select-Object -Unique)
  $familyCamera = @($visualSource | Where-Object { $_ -in @("persona","camara","cámara","rostro","cara") } | Select-Object -Unique)

  $families = @(
    [pscustomobject]@{ name = "hands";  tokens = $familyHands  },
    [pscustomobject]@{ name = "desk";   tokens = $familyDesk   },
    [pscustomobject]@{ name = "team";   tokens = $familyTeam   },
    [pscustomobject]@{ name = "camera"; tokens = $familyCamera }
  )
  $familyOrder = @("hands","desk","team","camera")
  $familyOffset = (($SceneIndex % $familyOrder.Count) + $familyOrder.Count) % $familyOrder.Count
  for ($f = 0; $f -lt $familyOrder.Count; $f++) {
    $fname = $familyOrder[(($familyOffset + $f) % $familyOrder.Count)]
    $pool = @(($families | Where-Object { $_.name -eq $fname } | Select-Object -First 1).tokens)
    if ($pool.Count -lt 2) { continue }
    $short2 = @(Get-RotatedTokens -tokens $pool -take 2)
    $short3 = @(Get-RotatedTokens -tokens $pool -take 3)
    $short4 = @(Get-RotatedTokens -tokens $pool -take 4)
    if ($short2.Count -ge 2) { Add-Candidate (($short2 -join " ") + " photo") }
    if ($short3.Count -ge 3) { Add-Candidate (($short3 -join " ") + " photo") }
    if ($short4.Count -ge 4) { Add-Candidate (($short4 -join " ") + " photo") }
  }

  $candidateTexts = @($candidates | Select-Object -Unique)
  $hasCameraCandidate = @(
    $candidateTexts |
      Where-Object { (Get-QueryCategory -query $_) -eq "camera" }
  ).Count -gt 0

  $cameraCycleHit = ((($SceneIndex % 4) + 4) % 4) -eq 1

  if (-not $hasCameraCandidate -and ($hasDiscursiveSignal -or $cameraCycleHit)) {
    Add-Candidate "persona camara photo"
  }

  if ($candidates.Count -eq 0) {
    Add-Candidate ("persona escritorio scene {0:000} photo" -f ($SceneIndex + 1))
  }

  $uniq = @($candidates | Select-Object -Unique)
  if ($uniq.Count -le 1) { return $uniq }

  $compacted = @(
    $uniq |
      ForEach-Object { Compact-VisualQuery -query $_ -visualPool $anchorVisualPool } |
      Where-Object { $_ -and $_.Trim().Length -ge 3 } |
      Select-Object -Unique
  )

  if ($compacted.Count -eq 0) {
    return @((Get-FallbackCompactQuery -visualPool $anchorVisualPool))
  }

  $annotated = @(
    $compacted |
      ForEach-Object -Begin { $idx = 0 } -Process {
        [pscustomobject]@{
          q   = $_
          cat = Get-QueryCategory -query $_
          idx = [int]$idx
        }
        $idx++
      }
  )

  $byCategory = @{
    "camera" = @($annotated | Where-Object { $_.cat -eq "camera" })
    "team"   = @($annotated | Where-Object { $_.cat -eq "team" })
    "hands"  = @($annotated | Where-Object { $_.cat -eq "hands" })
    "desk"   = @($annotated | Where-Object { $_.cat -eq "desk" })
    "other"  = @($annotated | Where-Object { $_.cat -eq "other" })
  }

  $preferredOrder = @("hands","team","camera","desk","other")

  $finalCandidates = New-Object System.Collections.Generic.List[string]
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

  foreach ($cat in $preferredOrder) {
    foreach ($row in $byCategory[$cat]) {
      if ($seen.Add($row.q)) {
        $finalCandidates.Add($row.q) | Out-Null
        break
      }
    }
  }

  foreach ($row in $annotated) {
    if ($seen.Add($row.q)) {
      $finalCandidates.Add($row.q) | Out-Null
    }
    if ($finalCandidates.Count -ge 8) { break }
  }

  if ($finalCandidates.Count -eq 0) {
    return @((Get-FallbackCompactQuery -visualPool $anchorVisualPool))
  }

  return @($finalCandidates | Select-Object -First 8)
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
  $requestedMediaType = Get-SceneRequestedMediaType -Scene $scene
  $visualMeta = Get-SceneVisualMetaTarget -Scene $scene
  Set-Note -obj $visualMeta -name "query" -value $q
  Set-Note -obj $visualMeta -name "query_candidates" -value $queryCandidates
  Set-Note -obj $visualMeta -name "requested_media_type" -value $requestedMediaType

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

      $safeName = ("scene_{0:000}_{1}_{2}" -f ($i + 1), $requestedMediaType, (Sha256Hex $candidate).Substring(0,12))
      $cacheJson = Join-Path $cacheDir ($safeName + ".json")

      & $stock -Query $candidate -OutJsonPath $cacheJson -Seed ($Seed + $i) -PerPage $PerPage -MediaType $requestedMediaType | Out-Null

      $pj = Get-Content -LiteralPath $cacheJson -Raw -Encoding UTF8 | ConvertFrom-Json
      $candidateHits = @()
      if ($pj -and (Has-Prop $pj "hits") -and $pj.hits) { $candidateHits = @($pj.hits) }

      if ($candidateHits.Count -gt 0) {
        $hits = $candidateHits
        $usedQuery = [string]$candidate
        break
      }
    }

    Set-Note -obj $visualMeta -name "provider" -value "pixabay"
    Set-Note -obj $visualMeta -name "media_type" -value $requestedMediaType
    Set-Note -obj $visualMeta -name "used_query" -value $usedQuery
    Set-Note -obj $visualMeta -name "hits_count" -value $hits.Count

    if ($hits.Count -lt 1) {
      Set-Note -obj $visualMeta -name "note" -value ("pixabay: 0 hits ({0})" -f $requestedMediaType)
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
      Set-Note -obj $visualMeta -name "note" -value ("pixabay: hit sin .url ({0})" -f $requestedMediaType)
      $withErrors++
      continue
    }

    $outDir = Join-Path $ws "assets\scenes_v03"
    if (-not (Test-Path -LiteralPath $outDir)) {
      New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }

    $fileName = ""
    if ($requestedMediaType -eq "video") {
      $fileName = ("scene_{0:000}.mp4" -f ($i + 1))
    }
    else {
      $fileName = ("scene_{0:000}.jpg" -f ($i + 1))
    }

    $outPath = Join-Path $outDir $fileName
    & $dl -Url $url -OutPath $outPath | Out-Null

    $resolvedOutPath = (Resolve-Path -LiteralPath $outPath).Path

    if ($requestedMediaType -eq "video") {
      $scene.assets.video = [string]$resolvedOutPath
      $scene.assets.image = ""
      Set-Note -obj $scene -name "visual_kind" -value "video"
      Set-Note -obj $scene -name "visual_capability" -value "stock_video"
      Set-Note -obj $scene -name "visual_source_kind" -value "pixabay_video"
    }
    else {
      $scene.assets.image = [string]$resolvedOutPath
      $scene.assets.video = ""
      Set-Note -obj $scene -name "visual_kind" -value "image"
      Set-Note -obj $scene -name "visual_capability" -value "stock_image"
      Set-Note -obj $scene -name "visual_source_kind" -value "pixabay_image"
    }

    Set-Note -obj $visualMeta -name "path" -value $resolvedOutPath
    Set-Note -obj $visualMeta -name "picked_index" -value $idx
    Set-Note -obj $visualMeta -name "source_url" -value $url

    if ($hit -and (Has-Prop $hit "thumb_url") -and $hit.thumb_url) {
      Set-Note -obj $visualMeta -name "thumb_url" -value ([string]$hit.thumb_url)
    }

    $downloaded++
  }
  catch {
    Set-Note -obj $visualMeta -name "provider" -value "pixabay"
    Set-Note -obj $visualMeta -name "media_type" -value $requestedMediaType
    Set-Note -obj $visualMeta -name "note" -value (("pixabay error ({0}): " -f $requestedMediaType) + $_.Exception.Message)
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