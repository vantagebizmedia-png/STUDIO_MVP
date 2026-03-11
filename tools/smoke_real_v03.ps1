param(
  [string]$ConfigPath = ".\config\studio_v03_real_probe.json",
  [string]$ScriptText = "Crea un video corto en español sobre 3 hábitos para tener más disciplina, con introducción fuerte, desarrollo claro y cierre accionable.",
  [string]$LiveDir = ".\_v03_real_probe\artifacts",
  [switch]$WithMusic
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Fail([string]$m) { throw "SMOKE_REAL_V03 FAIL: $m" }

$repo = (Resolve-Path ".").Path
$configAbs = (Resolve-Path $ConfigPath).Path

if (-not (Test-Path -LiteralPath $configAbs)) {
  Fail "No existe config: $configAbs"
}

if ([string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
  Fail "Falta OPENAI_API_KEY en el entorno"
}

if ([string]::IsNullOrWhiteSpace($env:PIXABAY_API_KEY)) {
  Fail "Falta PIXABAY_API_KEY en el entorno"
}

$requestedLiveAbs = [System.IO.Path]::GetFullPath((Join-Path $repo $LiveDir))
$configDefaultLiveAbs = [System.IO.Path]::GetFullPath((Join-Path $repo ".\_v03_from_config\artifacts"))

$configJson = Get-Content -LiteralPath $configAbs -Raw -Encoding UTF8 | ConvertFrom-Json

$configWorkDir = $null
$configPipeWorkDir = $null

$propWorkDir = $configJson.PSObject.Properties["work_dir"]
if ($null -ne $propWorkDir) {
  $configWorkDir = [string]$propWorkDir.Value
}

$propPipe = $configJson.PSObject.Properties["pipe"]
if ($null -ne $propPipe -and $null -ne $propPipe.Value) {
  $pipeObj = $propPipe.Value
  $propPipeWorkDir = $pipeObj.PSObject.Properties["work_dir"]
  if ($null -ne $propPipeWorkDir) {
    $configPipeWorkDir = [string]$propPipeWorkDir.Value
  }
}

$candidateLiveAbs = New-Object System.Collections.Generic.List[string]
$candidateLiveAbs.Add($requestedLiveAbs)
$candidateLiveAbs.Add($configDefaultLiveAbs)

if (-not [string]::IsNullOrWhiteSpace($configWorkDir)) {
  $candidateLiveAbs.Add([System.IO.Path]::GetFullPath((Join-Path $repo $configWorkDir)))
}

if (-not [string]::IsNullOrWhiteSpace($configPipeWorkDir)) {
  $candidateLiveAbs.Add([System.IO.Path]::GetFullPath((Join-Path $repo $configPipeWorkDir)))
}

$uniqueCandidateLiveAbs = @()
foreach ($p in $candidateLiveAbs) {
  if (-not [string]::IsNullOrWhiteSpace($p) -and ($uniqueCandidateLiveAbs -notcontains $p)) {
    $uniqueCandidateLiveAbs += $p
  }
}

Write-Host "== SMOKE REAL V0.3 ==" -ForegroundColor Cyan
Write-Host "Repo              : $repo"
Write-Host "Config            : $configAbs"
Write-Host "LiveDir(requested): $requestedLiveAbs"
Write-Host "WithMusic         : $WithMusic"
Write-Host ""
Write-Host "== CANDIDATOS LIVE DIR ==" -ForegroundColor Cyan
$uniqueCandidateLiveAbs | ForEach-Object { Write-Host $_ }

foreach ($dir in $uniqueCandidateLiveAbs) {
  if (Test-Path -LiteralPath $dir) {
    Remove-Item -LiteralPath $dir -Recurse -Force
    Write-Host "REMOVED => $dir" -ForegroundColor DarkGray
  }
}

$env:STUDIO_ALLOW_LIVE = "1"
try {
  & python -m cli.main --v03-config $configAbs --script $ScriptText
  if ($LASTEXITCODE -ne 0) {
    Fail "cli.main devolvió exit code $LASTEXITCODE"
  }
}
finally {
  Remove-Item Env:STUDIO_ALLOW_LIVE -ErrorAction SilentlyContinue
}

$liveAbs = $null
foreach ($dir in $uniqueCandidateLiveAbs) {
  $manifestProbe = Join-Path $dir "manifest_v03.json"
  if (Test-Path -LiteralPath $manifestProbe) {
    $liveAbs = $dir
    break
  }
}

if ([string]::IsNullOrWhiteSpace($liveAbs)) {
  Write-Host ""
  Write-Host "== DEBUG: MANIFEST NO ENCONTRADO EN CANDIDATOS ==" -ForegroundColor Yellow
  foreach ($dir in $uniqueCandidateLiveAbs) {
    $manifestProbe = Join-Path $dir "manifest_v03.json"
    if (Test-Path -LiteralPath $dir) {
      Write-Host "DIR EXISTS   => $dir" -ForegroundColor Yellow
      if (Test-Path -LiteralPath $manifestProbe) {
        Write-Host "MANIFEST OK  => $manifestProbe" -ForegroundColor Green
      }
      else {
        Write-Host "MANIFEST MISS=> $manifestProbe" -ForegroundColor Yellow
      }
    }
    else {
      Write-Host "DIR MISSING  => $dir" -ForegroundColor Yellow
    }
  }
  Fail "No existe manifest_v03.json en ninguno de los LiveDir candidatos"
}

Write-Host ""
Write-Host "== LIVE DIR RESUELTO ==" -ForegroundColor Cyan
Write-Host $liveAbs -ForegroundColor Green

$manifestPath = Join-Path $liveAbs "manifest_v03.json"
$packJsonPath = Join-Path $liveAbs "pack.json"
$subtitlesPath = Join-Path $liveAbs "subtitles.srt"
$captionsPath = Join-Path $liveAbs "captions_v03.srt"
$videoBase = Join-Path $liveAbs "video.mp4"
$videoSubs = Join-Path $liveAbs "video_subs.mp4"
$videoMusic = Join-Path $liveAbs "video_music_auto.mp4"
$videoFinal = Join-Path $liveAbs "video_final.mp4"
$handoffDir = Join-Path $liveAbs "handoff_v03"
$handoffZip = Join-Path $handoffDir "handoff_v03.zip"

if (-not (Test-Path -LiteralPath $manifestPath)) {
  Fail "No existe manifest_v03.json"
}

Write-Host ""
Write-Host "== PACK.JSON DESDE scenes_v03 ==" -ForegroundColor Cyan

function Get-PropSafeLocal {
  param(
    [AllowNull()]$Obj,
    [Parameter(Mandatory=$true)][string]$Name
  )

  if ($null -eq $Obj) { return $null }

  $prop = $Obj.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $null }

  return $prop.Value
}

function Normalize-RealSmokeQuery {
  param(
    [AllowNull()][string]$Text,
    [int]$MaxChars = 100
  )

  $fallback = "motivacion"
  if ([string]::IsNullOrWhiteSpace($Text)) { return $fallback }

  $q = $Text.Trim().ToLowerInvariant()
  $q = $q -replace '[\r\n\t]+', ' '
  $q = $q -replace '[^a-zA-Z0-9áéíóúüñÁÉÍÓÚÜÑ ]+', ' '
  $q = $q -replace '\s+', ' '
  $q = $q.Trim()

  if ([string]::IsNullOrWhiteSpace($q)) { return $fallback }

  if ($q.Length -gt $MaxChars) {
    $q = $q.Substring(0, $MaxChars)
    $q = $q -replace '\s+\S*$', ''
    $q = $q.Trim()
  }

  if ([string]::IsNullOrWhiteSpace($q)) { return $fallback }
  return $q
}

function Get-SceneImageRelLocal {
  param(
    [AllowNull()]$Scene
  )

  $assets = Get-PropSafeLocal -Obj $Scene -Name "assets"
  if ($null -eq $assets) { return "" }

  $img = Get-PropSafeLocal -Obj $assets -Name "image"
  if ($img -is [string]) {
    return [string]$img
  }

  if (($img -is [System.Collections.IEnumerable]) -and -not ($img -is [string])) {
    $arr = @($img)
    if ($arr.Count -gt 0) {
      $first = $arr[0]
      $p = Get-PropSafeLocal -Obj $first -Name "path"
      if (-not [string]::IsNullOrWhiteSpace([string]$p)) {
        return [string]$p
      }
    }
  }

  $p2 = Get-PropSafeLocal -Obj $img -Name "path"
  if (-not [string]::IsNullOrWhiteSpace([string]$p2)) {
    return [string]$p2
  }

  return ""
}

function Get-SceneAudioRelLocal {
  param(
    [AllowNull()]$Scene
  )

  $assets = Get-PropSafeLocal -Obj $Scene -Name "assets"
  if ($null -eq $assets) { return "" }

  $aud = Get-PropSafeLocal -Obj $assets -Name "audio_clip"
  if ([string]::IsNullOrWhiteSpace([string]$aud)) { return "" }

  return [string]$aud
}

function Find-StockCacheEntryLocal {
  param(
    [AllowNull()]$StockCache,
    [string]$ImagePath
  )

  if ($null -eq $StockCache) { return $null }
  if ([string]::IsNullOrWhiteSpace($ImagePath)) { return $null }

  foreach ($prop in $StockCache.PSObject.Properties) {
    $entry = $prop.Value
    if ($null -eq $entry) { continue }

    $entryPath = Get-PropSafeLocal -Obj $entry -Name "path"
    if ([string]$entryPath -eq $ImagePath) {
      return $entry
    }
  }

  return $null
}

$m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$scenes = @($m.scenes_v03)
if ($scenes.Count -lt 1) {
  Fail "manifest_v03.json no tiene scenes_v03"
}

$stockCache = Get-PropSafeLocal -Obj $m -Name "stock_cache"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($sc in $scenes) {
  $imageQuery = [string](Get-PropSafeLocal -Obj $sc -Name "image_query")
  $scriptText = [string](Get-PropSafeLocal -Obj $sc -Name "script_text")
  $sceneText  = [string](Get-PropSafeLocal -Obj $sc -Name "text")

  $querySource = "fallback"
  $queryInput  = "motivacion"

  if (-not [string]::IsNullOrWhiteSpace($imageQuery)) {
    $queryInput  = $imageQuery
    $querySource = "image_query"
  }
  elseif (-not [string]::IsNullOrWhiteSpace($scriptText)) {
    $queryInput  = $scriptText
    $querySource = "script_text"
  }
  elseif (-not [string]::IsNullOrWhiteSpace($sceneText)) {
    $queryInput  = $sceneText
    $querySource = "text"
  }

  $query = Normalize-RealSmokeQuery -Text $queryInput -MaxChars 100

  if (-not ($sc.PSObject.Properties.Name -contains "query")) {
    $sc | Add-Member -Force -NotePropertyName query -NotePropertyValue $query
  }
  else {
    $sc.query = $query
  }

  if (-not ($sc.PSObject.Properties.Name -contains "meta") -or -not $sc.meta) {
    $sc | Add-Member -Force -NotePropertyName meta -NotePropertyValue ([pscustomobject]@{})
  }

  $imgRel = Get-SceneImageRelLocal -Scene $sc
  $cacheEntry = Find-StockCacheEntryLocal -StockCache $stockCache -ImagePath $imgRel

  $provider  = [string](Get-PropSafeLocal -Obj $cacheEntry -Name "provider")
  $hitId     = Get-PropSafeLocal -Obj $cacheEntry -Name "hit_id"
  $sourceUrl = [string](Get-PropSafeLocal -Obj $cacheEntry -Name "source_url")

  if ([string]::IsNullOrWhiteSpace($provider) -and -not [string]::IsNullOrWhiteSpace($imgRel)) {
    if ($imgRel -like "assets/images/*") {
      $provider = "pixabay"
    }
  }

  $sc.meta | Add-Member -Force -NotePropertyName query_source -NotePropertyValue $querySource
  $sc.meta | Add-Member -Force -NotePropertyName query_input  -NotePropertyValue $queryInput
  $sc.meta | Add-Member -Force -NotePropertyName used_query   -NotePropertyValue $query
  $sc.meta | Add-Member -Force -NotePropertyName provider     -NotePropertyValue $provider
  $sc.meta | Add-Member -Force -NotePropertyName hit_id       -NotePropertyValue $hitId
  $sc.meta | Add-Member -Force -NotePropertyName source_url   -NotePropertyValue $sourceUrl
}

$outManifest = $m | ConvertTo-Json -Depth 50
[System.IO.File]::WriteAllText($manifestPath, ($outManifest -replace "`r`n","`n"), $utf8NoBom)
Write-Host "OK: manifest_v03 enriquecido desde scenes_v03 + stock_cache" -ForegroundColor DarkGray

$packScenes = @()
foreach ($sc in $scenes) {
  $imgRel = Get-SceneImageRelLocal -Scene $sc
  $audRel = Get-SceneAudioRelLocal -Scene $sc

  if ([string]::IsNullOrWhiteSpace($imgRel)) { Fail "Escena sin assets.image" }
  if ([string]::IsNullOrWhiteSpace($audRel)) { Fail "Escena sin assets.audio_clip" }

  $imgAbs = Join-Path $liveAbs ($imgRel -replace '/', '\')
  $audAbs = Join-Path $liveAbs ($audRel -replace '/', '\')

  if (-not (Test-Path -LiteralPath $imgAbs)) { Fail "No existe imagen: $imgRel" }
  if (-not (Test-Path -LiteralPath $audAbs)) { Fail "No existe audio_clip: $audRel" }

  $packScenes += [pscustomobject]@{
    id    = [string]$sc.id
    index = ([int]$sc.index + 1)
    image = $imgRel
    audio = $audRel
  }
}

$packObj = [pscustomobject]@{
  version = "v0.3"
  scenes  = $packScenes
}

$json = $packObj | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($packJsonPath, ($json -replace "`r`n","`n"), $utf8NoBom)

Write-Host "OK: pack.json creado" -ForegroundColor Green

Write-Host ""
Write-Host "== RENDER BASE ==" -ForegroundColor Cyan
& python -u .\tools\render_pack_v03.py --pack-dir $liveAbs --w 1080 --h 1920 --fps 30 --fit crop
if ($LASTEXITCODE -ne 0) { Fail "render_pack_v03.py falló" }
if (-not (Test-Path -LiteralPath $videoBase)) { Fail "No se generó video.mp4" }

Write-Host ""
Write-Host "== CAPTIONS ==" -ForegroundColor Cyan
if (Test-Path -LiteralPath $subtitlesPath) {
  Copy-Item -LiteralPath $subtitlesPath -Destination $captionsPath -Force
}
elseif (-not (Test-Path -LiteralPath $captionsPath)) {
  Fail "No existe subtitles.srt ni captions_v03.srt"
}

Write-Host ""
Write-Host "== BURN-IN SUBTITLES ==" -ForegroundColor Cyan
& pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\apply_subtitles_live_v03.ps1 -LiveDir $liveAbs
if ($LASTEXITCODE -ne 0) { Fail "apply_subtitles_live_v03.ps1 falló" }
if (-not (Test-Path -LiteralPath $videoSubs)) { Fail "No se generó video_subs.mp4" }

if ($WithMusic) {
  Write-Host ""
  Write-Host "== MUSIC OPTIONAL ==" -ForegroundColor Cyan
  $repoMusicDir = Join-Path $repo "music"
  if (Test-Path -LiteralPath $repoMusicDir) {
    $musicFile = Get-ChildItem -LiteralPath $repoMusicDir -File |
      Where-Object { $_.Extension -in @(".mp3",".wav") } |
      Sort-Object Name |
      Select-Object -First 1

    if ($musicFile) {
      $targetMusic = Join-Path $liveAbs ("music" + $musicFile.Extension.ToLowerInvariant())
      Copy-Item -LiteralPath $musicFile.FullName -Destination $targetMusic -Force
      Write-Host "OK: música copiada => $targetMusic" -ForegroundColor Green
    }
    else {
      Write-Host "WARN: carpeta music existe pero no contiene .mp3/.wav" -ForegroundColor Yellow
    }
  }
  else {
    Write-Host "WARN: no existe carpeta music/" -ForegroundColor Yellow
  }
}

Write-Host ""
Write-Host "== ENSURE OUTPUTS ==" -ForegroundColor Cyan
& pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\ensure_outputs_live_v03.ps1 -LiveDir $liveAbs
if ($LASTEXITCODE -ne 0) { Fail "ensure_outputs_live_v03.ps1 falló" }

Write-Host ""
Write-Host "== FINALIZE HANDOFF ==" -ForegroundColor Cyan
& pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\finalize_handoff_v03.ps1 -LiveDir $liveAbs -Force
if ($LASTEXITCODE -ne 0) { Fail "finalize_handoff_v03.ps1 falló" }

Write-Host ""
Write-Host "== HANDOFF PACK ==" -ForegroundColor Cyan
& pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\handoff_pack_v03.ps1 -InDir $handoffDir -OutZip $handoffZip
if ($LASTEXITCODE -ne 0) { Fail "handoff_pack_v03.ps1 falló" }

if (-not (Test-Path -LiteralPath $videoBase))    { Fail "Falta video.mp4" }
if (-not (Test-Path -LiteralPath $videoSubs))    { Fail "Falta video_subs.mp4" }
if (-not (Test-Path -LiteralPath $videoMusic))   { Fail "Falta video_music_auto.mp4" }
if (-not (Test-Path -LiteralPath $videoFinal))   { Fail "Falta video_final.mp4" }
if (-not (Test-Path -LiteralPath $captionsPath)) { Fail "Falta captions_v03.srt" }
if (-not (Test-Path -LiteralPath $handoffZip))   { Fail "Falta handoff_v03.zip" }

Write-Host ""
Write-Host "== RESUMEN FINAL ==" -ForegroundColor Green
Get-ChildItem -LiteralPath $liveAbs -File |
  Where-Object { $_.Name -in @("video.mp4","video_subs.mp4","video_music_auto.mp4","video_final.mp4","captions_v03.srt","subtitles.srt","pack.json","manifest_v03.json") } |
  Sort-Object Name |
  Select-Object Name, Length, LastWriteTime

Write-Host ""
Get-ChildItem -LiteralPath $handoffDir -File |
  Sort-Object Name |
  Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "SMOKE OK: REAL v0.3 (text + voice + pixabay + render + subtitles + outputs + handoff)" -ForegroundColor Green
