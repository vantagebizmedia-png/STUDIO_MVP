param(
  [Parameter(Mandatory=$true)][string]$LiveDir,
  [int]$MaxScenes = 6,
  [int]$AudioDurationToleranceMs = 250
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg) {
  throw "SMOKE FAIL: $msg"
}

function Get-IntOrZero {
  param($Value)

  try { return [int]$Value }
  catch { return 0 }
}

function Get-StringOrEmpty {
  param($Value)

  if ($null -eq $Value) { return "" }

  try { return ([string]$Value).Trim() }
  catch { return "" }
}

function Resolve-AssetValue {
  param($Value)

  if ($null -eq $Value) { return "" }

  if ($Value -is [string]) {
    return ([string]$Value).Trim()
  }

  if ($Value -is [System.Collections.IDictionary]) {
    try {
      if ($Value.Contains("path") -and $Value["path"]) {
        return ([string]$Value["path"]).Trim()
      }
    }
    catch { }

    return ""
  }

  try {
    if ($Value.PSObject.Properties["path"] -and $Value.path) {
      return ([string]$Value.path).Trim()
    }
  }
  catch { }

  if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
    $arr = @($Value)
    if ($arr.Count -gt 0) {
      return (Resolve-AssetValue -Value $arr[0])
    }
  }

  return ""
}

function Get-AssetPathValue {
  param(
    $AssetsObj,
    [string]$Key
  )

  if (-not $AssetsObj) { return "" }
  if ([string]::IsNullOrWhiteSpace($Key)) { return "" }

  $prop = $null
  try { $prop = $AssetsObj.PSObject.Properties[$Key] }
  catch { $prop = $null }

  if (-not $prop) { return "" }

  return (Resolve-AssetValue -Value $prop.Value)
}

function Resolve-LivePath {
  param(
    [Parameter(Mandatory=$true)][string]$BaseDir,
    [string]$Value
  )

  $p = Get-StringOrEmpty -Value $Value
  if ([string]::IsNullOrWhiteSpace($p)) { return "" }

  try {
    if ([System.IO.Path]::IsPathRooted($p)) {
      return $p
    }
  }
  catch { }

  return (Join-Path $BaseDir $p)
}

function Get-FFprobeDurationMs {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Label
  )

  $ffprobeOut = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $Path 2>$null
  if ($LASTEXITCODE -ne 0) {
    Fail "$Label ffprobe no pudo leer duración: $Path"
  }

  $ffprobeText = (($ffprobeOut | ForEach-Object { "$_" }) -join "").Trim()
  if ([string]::IsNullOrWhiteSpace($ffprobeText)) {
    Fail "$Label ffprobe devolvió duración vacía: $Path"
  }

  $durationSec = 0.0
  if (-not [double]::TryParse($ffprobeText, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$durationSec)) {
    Fail "$Label no pudo parsear duración ffprobe='$ffprobeText'"
  }

  return [Math]::Max(1, [int][Math]::Round($durationSec * 1000.0))
}

$live = (Resolve-Path -LiteralPath $LiveDir).Path

$mfPath = Join-Path $live "manifest_v03.json"
if (-not (Test-Path -LiteralPath $mfPath -PathType Leaf)) {
  Fail "No existe manifest_v03.json en LIVE: $live"
}

$pkPath = Join-Path $live "pack.json"
if (-not (Test-Path -LiteralPath $pkPath -PathType Leaf)) {
  Fail "No existe pack.json en LIVE: $live"
}

$mf = Get-Content -LiteralPath $mfPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pk = Get-Content -LiteralPath $pkPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not ($mf.PSObject.Properties.Name -contains "scenes_v03") -or -not $mf.scenes_v03) {
  Fail "manifest_v03.json no tiene scenes_v03"
}

if (-not ($pk.PSObject.Properties.Name -contains "scenes") -or -not $pk.scenes) {
  Fail "pack.json no tiene scenes"
}

$scenes = @($mf.scenes_v03)
$pkScenes = @($pk.scenes)

$scCount = $scenes.Count
if ($scCount -lt 1) { Fail "scenes_v03 vacío" }
if ($scCount -gt $MaxScenes) { Fail "scenes_v03=$scCount supera MaxScenes=$MaxScenes" }

if ($pkScenes.Count -ne $scCount) {
  Fail "pack scenes=$($pkScenes.Count) != manifest scenes_v03=$scCount"
}

$total = $null
if ($mf.PSObject.Properties.Name -contains "total_audio_ms") {
  $total = [int]$mf.total_audio_ms
}
elseif ($mf.scene_builder_v03 -and ($mf.scene_builder_v03.PSObject.Properties.Name -contains "total_audio_ms")) {
  $total = [int]$mf.scene_builder_v03.total_audio_ms
}
else {
  Fail "No existe total_audio_ms ni scene_builder_v03.total_audio_ms"
}

if ([int]$total -le 0) {
  Fail "total_audio_ms inválido: $total"
}

if ($pk.PSObject.Properties.Name -contains "total_audio_ms") {
  $packTotal = Get-IntOrZero -Value $pk.total_audio_ms
  if ($packTotal -gt 0 -and $packTotal -ne [int]$total) {
    Fail "pack total_audio_ms=$packTotal != manifest total_audio_ms=$total"
  }
}

$topAudioClips = @()
try {
  if ($mf.PSObject.Properties.Name -contains "audio_clips" -and $mf.audio_clips) {
    $topAudioClips = @($mf.audio_clips)
  }
}
catch {
  $topAudioClips = @()
}

if ($topAudioClips.Count -gt 0 -and $topAudioClips.Count -ne $scCount) {
  Fail "audio_clips.count=$($topAudioClips.Count) != scenes_v03=$scCount"
}

$lastEnd = 0

for ($i = 0; $i -lt $scCount; $i++) {
  $ord = $i + 1
  $expectedId = ("scene_{0:000}" -f $ord)
  $sceneLabel = ("scene_{0:d2}" -f $ord)

  $s = $scenes[$i]
  $p = $pkScenes[$i]

  $sceneId = Get-StringOrEmpty -Value $s.id
  $packId  = Get-StringOrEmpty -Value $p.id

  if ($sceneId -ne $expectedId) {
    Fail "$sceneLabel manifest id inválido: '$sceneId' != '$expectedId'"
  }

  if ($packId -ne $expectedId) {
    Fail "$sceneLabel pack id inválido: '$packId' != '$expectedId'"
  }

  $manifestIndex = Get-IntOrZero -Value $s.index
  $packIndex = Get-IntOrZero -Value $p.index

  if ($manifestIndex -ne ($ord - 1)) {
    Fail "$sceneLabel manifest index inválido: $manifestIndex != $(($ord - 1))"
  }

  if ($packIndex -ne $ord) {
    Fail "$sceneLabel pack index inválido: $packIndex != $ord"
  }

  $st = Get-IntOrZero -Value $s.start_ms
  $en = Get-IntOrZero -Value $s.end_ms
  $du = Get-IntOrZero -Value $s.duration_ms

  if ($st -lt 0 -or $en -lt 0) {
    Fail "$sceneLabel timing negativo: ${st}..${en}"
  }

  if ($en -lt $st) {
    Fail "$sceneLabel end_ms < start_ms: ${st}..${en}"
  }

  if ($st -lt $lastEnd) {
    Fail "$sceneLabel start_ms no monótono: prevEnd=$lastEnd start=${st}"
  }

  if ($du -le 0) {
    Fail "$sceneLabel duration_ms inválido: $du"
  }

  if ($du -ne ($en - $st)) {
    Fail "$sceneLabel duration_ms mismatch: duration_ms=$du end-start=$($en - $st)"
  }

  $pkStart = Get-IntOrZero -Value $p.start_ms
  $pkEnd   = Get-IntOrZero -Value $p.end_ms
  $pkDu    = Get-IntOrZero -Value $p.duration_ms

  if ($pkStart -ne $st -or $pkEnd -ne $en) {
    Fail "$sceneLabel pack timing mismatch: manifest=${st}..${en} pack=${pkStart}..${pkEnd}"
  }

  if ($pkDu -ne $du) {
    Fail "$sceneLabel pack duration mismatch: manifest=$du pack=$pkDu"
  }

  $lastEnd = $en

  $clip = Get-AssetPathValue -AssetsObj $s.assets -Key "audio_clip"
  if ([string]::IsNullOrWhiteSpace($clip)) {
    Fail "$sceneLabel falta assets.audio_clip"
  }

  $expectedV03 = ("assets/audio_clips/s{0:d2}.wav" -f $ord)

  if ($clip -ne $expectedV03) {
    Fail "$sceneLabel audio_clip inesperado: '$clip' != v03='$expectedV03'"
  }

  $clipAbs = Resolve-LivePath -BaseDir $live -Value $clip
  if (-not (Test-Path -LiteralPath $clipAbs -PathType Leaf)) {
    Fail "$sceneLabel no existe clip: $clipAbs"
  }

  $clipLen = (Get-Item -LiteralPath $clipAbs).Length
  if ($clipLen -lt 1000) {
    Fail "$sceneLabel clip demasiado pequeño ($clipLen bytes): $clipAbs"
  }

  $clipDurationMs = Get-FFprobeDurationMs -Path $clipAbs -Label $sceneLabel
  $clipDeltaMs = [Math]::Abs($clipDurationMs - $du)

  if ($clipDeltaMs -gt $AudioDurationToleranceMs) {
    Fail "$sceneLabel duration/audio mismatch: duration_ms=$du audio_ms=$clipDurationMs delta_ms=$clipDeltaMs tolerance_ms=$AudioDurationToleranceMs"
  }

  $pkAudio = Get-StringOrEmpty -Value $p.audio
  if ($pkAudio -ne $clip) {
    Fail "$sceneLabel pack audio mismatch: manifest='$clip' pack='$pkAudio'"
  }

  $manifestImageQuery = ""
  if ($s.PSObject.Properties.Name -contains "image_query") {
    $manifestImageQuery = Get-StringOrEmpty -Value $s.image_query
  }
  if ([string]::IsNullOrWhiteSpace($manifestImageQuery)) {
    Fail "$sceneLabel image_query vacío en manifest"
  }

  $packImageQuery = ""
  if ($p.PSObject.Properties.Name -contains "image_query") {
    $packImageQuery = Get-StringOrEmpty -Value $p.image_query
  }
  if ([string]::IsNullOrWhiteSpace($packImageQuery)) {
    Fail "$sceneLabel image_query vacío en pack"
  }

  if ($packImageQuery -ne $manifestImageQuery) {
    Fail "$sceneLabel pack image_query mismatch: manifest='$manifestImageQuery' pack='$packImageQuery'"
  }

  $visualKind = (Get-StringOrEmpty -Value $s.visual_kind).ToLowerInvariant()
  if (($visualKind -ne "image") -and ($visualKind -ne "video")) {
    Fail "$sceneLabel visual_kind inválido en manifest: '$visualKind'"
  }

  $requestedMediaType = ""
  if ($s.PSObject.Properties.Name -contains "requested_media_type") {
    $requestedMediaType = (Get-StringOrEmpty -Value $s.requested_media_type).ToLowerInvariant()
  }

  if (($requestedMediaType -ne "") -and ($requestedMediaType -ne "image") -and ($requestedMediaType -ne "video")) {
    Fail "$sceneLabel requested_media_type inválido en manifest: '$requestedMediaType'"
  }

  $visualRequestKind = ""
  if ($s.PSObject.Properties.Name -contains "visual_request_kind") {
    $visualRequestKind = (Get-StringOrEmpty -Value $s.visual_request_kind).ToLowerInvariant()
  }

  if (($visualRequestKind -ne "") -and ($visualRequestKind -ne "image") -and ($visualRequestKind -ne "video")) {
    Fail "$sceneLabel visual_request_kind inválido en manifest: '$visualRequestKind'"
  }

  if ([string]::IsNullOrWhiteSpace($requestedMediaType) -xor [string]::IsNullOrWhiteSpace($visualRequestKind)) {
    Fail "$sceneLabel intent fields desalineados: requested_media_type='$requestedMediaType' visual_request_kind='$visualRequestKind'"
  }

  if (($requestedMediaType -ne "") -and ($visualRequestKind -ne "") -and ($requestedMediaType -ne $visualRequestKind)) {
    Fail "$sceneLabel intent fields conflictivos: requested_media_type='$requestedMediaType' visual_request_kind='$visualRequestKind'"
  }

  $visualSourceKind = ""
  if ($s.PSObject.Properties.Name -contains "visual_source_kind") {
    $visualSourceKind = (Get-StringOrEmpty -Value $s.visual_source_kind).ToLowerInvariant()
  }

  if ([string]::IsNullOrWhiteSpace($visualSourceKind)) {
    Fail "$sceneLabel visual_source_kind vacío en manifest"
  }

  if ($visualSourceKind -notmatch "(^|_)(image|video)$") {
    Fail "$sceneLabel visual_source_kind inválido en manifest: '$visualSourceKind'"
  }

  if (($visualKind -eq "image") -and ($visualSourceKind -notmatch "(^|_)image$")) {
    Fail "$sceneLabel visual_source_kind incompatible con visual_kind=image: '$visualSourceKind'"
  }

  if (($visualKind -eq "video") -and ($visualSourceKind -notmatch "(^|_)video$")) {
    Fail "$sceneLabel visual_source_kind incompatible con visual_kind=video: '$visualSourceKind'"
  }

  $pkRequestedMediaType = (Get-StringOrEmpty -Value $p.requested_media_type).ToLowerInvariant()
  $pkVisualRequestKind  = (Get-StringOrEmpty -Value $p.visual_request_kind).ToLowerInvariant()
  $pkVisualSourceKind   = (Get-StringOrEmpty -Value $p.visual_source_kind).ToLowerInvariant()

  if ($pkRequestedMediaType -ne $requestedMediaType) {
    Fail "$sceneLabel pack requested_media_type mismatch: manifest='$requestedMediaType' pack='$pkRequestedMediaType'"
  }

  if ($pkVisualRequestKind -ne $visualRequestKind) {
    Fail "$sceneLabel pack visual_request_kind mismatch: manifest='$visualRequestKind' pack='$pkVisualRequestKind'"
  }

  if ($pkVisualSourceKind -ne $visualSourceKind) {
    Fail "$sceneLabel pack visual_source_kind mismatch: manifest='$visualSourceKind' pack='$pkVisualSourceKind'"
  }
  $imgPath = Get-AssetPathValue -AssetsObj $s.assets -Key "image"
  $vidPath = Get-AssetPathValue -AssetsObj $s.assets -Key "video"

  $pkKind  = (Get-StringOrEmpty -Value $p.visual_kind).ToLowerInvariant()
  $pkImage = Get-StringOrEmpty -Value $p.image
  $pkVideo = Get-StringOrEmpty -Value $p.video

  if ($pkKind -ne $visualKind) {
    Fail "$sceneLabel pack visual_kind mismatch: manifest='$visualKind' pack='$pkKind'"
  }

  if ($pkImage -ne $imgPath) {
    Fail "$sceneLabel pack image mismatch: manifest='$imgPath' pack='$pkImage'"
  }

  if ($pkVideo -ne $vidPath) {
    Fail "$sceneLabel pack video mismatch: manifest='$vidPath' pack='$pkVideo'"
  }

  if ($visualKind -eq "image") {
    if ([string]::IsNullOrWhiteSpace($imgPath)) {
      Fail "$sceneLabel visual_kind=image pero assets.image vacío"
    }

    if (-not [string]::IsNullOrWhiteSpace($vidPath)) {
      Fail "$sceneLabel visual_kind=image pero assets.video no vacío: '$vidPath'"
    }

    $imgAbs = Resolve-LivePath -BaseDir $live -Value $imgPath
    if (-not (Test-Path -LiteralPath $imgAbs -PathType Leaf)) {
      Fail "$sceneLabel no existe image activo: $imgAbs"
    }
  }
  else {
    if ([string]::IsNullOrWhiteSpace($vidPath)) {
      Fail "$sceneLabel visual_kind=video pero assets.video vacío"
    }

    if (-not [string]::IsNullOrWhiteSpace($imgPath)) {
      Fail "$sceneLabel visual_kind=video pero assets.image no vacío: '$imgPath'"
    }

    $vidAbs = Resolve-LivePath -BaseDir $live -Value $vidPath
    if (-not (Test-Path -LiteralPath $vidAbs -PathType Leaf)) {
      Fail "$sceneLabel no existe video activo: $vidAbs"
    }
  }
}

if ($lastEnd -ne [int]$total) {
  Fail "last_end=$lastEnd != total_audio_ms=$total"
}

Write-Host ("SMOKE OK: LIVE manifest v03 + pack compat. live={0} scenes={1} total_ms={2} last_end={3}" -f $live,$scCount,$total,$lastEnd)