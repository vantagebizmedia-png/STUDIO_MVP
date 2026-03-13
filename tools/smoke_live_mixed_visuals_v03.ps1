param(
  [Parameter(Mandatory=$false)][string]$RepoRoot = "C:\Users\vanta\Documents\STUDIO_MVP",
  [Parameter(Mandatory=$false)][string]$SourceLiveDir = "C:\Users\vanta\Documents\STUDIO_WORKSPACE\runs\smoke_live_latest",
  [Parameter(Mandatory=$false)][string]$OutputLiveDir = "C:\Users\vanta\Documents\STUDIO_WORKSPACE\runs\smoke_live_mixed_visuals"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Assert-SceneVisualState {
  param(
    [Parameter(Mandatory=$true)][string]$Label,
    [Parameter(Mandatory=$true)][object]$SceneObj,
    [Parameter(Mandatory=$true)][ValidateSet("image","video")][string]$ExpectedMediaType,
    [switch]$IsPack
  )

  $kind = [string]$SceneObj.visual_kind

  $imageValue = ""
  $videoValue = ""

  if ($IsPack) {
    $imageValue = [string]$SceneObj.image
    $videoValue = [string]$SceneObj.video
  }
  else {
    $imageValue = [string]$SceneObj.assets.image
    $videoValue = [string]$SceneObj.assets.video
  }

  if ($kind -ne $ExpectedMediaType) {
    throw "$Label visual_kind esperado='$ExpectedMediaType' actual='$kind'"
  }

  if ($ExpectedMediaType -eq "video") {
    if (-not [string]::IsNullOrWhiteSpace($imageValue)) {
      throw "$Label dejó image no vacío: '$imageValue'"
    }
    if ([string]::IsNullOrWhiteSpace($videoValue)) {
      throw "$Label dejó video vacío"
    }
  }
  else {
    if ([string]::IsNullOrWhiteSpace($imageValue)) {
      throw "$Label dejó image vacío"
    }
    if (-not [string]::IsNullOrWhiteSpace($videoValue)) {
      throw "$Label dejó video no vacío: '$videoValue'"
    }
  }
}

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
  throw "No existe RepoRoot: $RepoRoot"
}

if (-not (Test-Path -LiteralPath $SourceLiveDir -PathType Container)) {
  throw "No existe SourceLiveDir: $SourceLiveDir"
}

$writePack = Join-Path $RepoRoot "tools\write_pack_compat_v03.ps1"
$smoke     = Join-Path $RepoRoot "tools\smoke_live_manifest_v03.ps1"
$renderer  = Join-Path $RepoRoot "tools\render_pack_v03.py"

foreach ($p in @($writePack, $smoke, $renderer)) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
    throw "No existe requerido: $p"
  }
}

Write-Host "== Reset LIVE de prueba mixed visuals ==" -ForegroundColor Cyan
if (Test-Path -LiteralPath $OutputLiveDir) {
  Remove-Item -LiteralPath $OutputLiveDir -Recurse -Force
}
Copy-Item -LiteralPath $SourceLiveDir -Destination $OutputLiveDir -Recurse -Force

$manifestPath = Join-Path $OutputLiveDir "manifest_v03.json"
$packPath     = Join-Path $OutputLiveDir "pack.json"
$renderOut    = Join-Path $OutputLiveDir "video_render_mixed_visuals.mp4"

foreach ($p in @($manifestPath)) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
    throw "No existe requerido dentro del LIVE clonado: $p"
  }
}

if (Test-Path -LiteralPath $renderOut) {
  Remove-Item -LiteralPath $renderOut -Force
}

$sceneSpecs = @(
  [pscustomobject]@{ SceneNumber = 1; ExpectedMedia = "video" },
  [pscustomobject]@{ SceneNumber = 2; ExpectedMedia = "image" },
  [pscustomobject]@{ SceneNumber = 3; ExpectedMedia = "video" },
  [pscustomobject]@{ SceneNumber = 4; ExpectedMedia = "image" }
)

foreach ($spec in $sceneSpecs) {
  $n = [int]$spec.SceneNumber
  $sceneDir = Join-Path $OutputLiveDir ("artifacts\scenes\scene_{0:00}" -f $n)
  $imagePath = Join-Path $sceneDir "image.png"
  $audioPath = Join-Path $OutputLiveDir ("assets\audio_clips\s{0:00}.wav" -f $n)
  $videoPath = Join-Path $sceneDir "video.mp4"

  foreach ($p in @($sceneDir, $imagePath, $audioPath)) {
    if (-not (Test-Path -LiteralPath $p)) {
      throw "No existe requerido para scene_$('{0:00}' -f $n): $p"
    }
  }

  if ($spec.ExpectedMedia -eq "video") {
    Write-Host ("== Creando video real para scene_{0:00} ==" -f $n) -ForegroundColor Cyan

    if (Test-Path -LiteralPath $videoPath) {
      Remove-Item -LiteralPath $videoPath -Force
    }

    & ffmpeg `
      -hide_banner `
      -loglevel error `
      -y `
      -loop 1 `
      -i $imagePath `
      -i $audioPath `
      -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,format=yuv420p" `
      -r 30 `
      -map 0:v:0 `
      -map 1:a:0 `
      -c:v libx264 `
      -pix_fmt yuv420p `
      -preset medium `
      -crf 18 `
      -c:a aac `
      -b:a 192k `
      -ar 44100 `
      -ac 2 `
      -shortest `
      -movflags +faststart `
      -map_metadata -1 `
      -map_chapters -1 `
      $videoPath

    if ($LASTEXITCODE -ne 0) {
      throw "ffmpeg falló creando video de prueba para scene_$('{0:00}' -f $n)"
    }

    if (-not (Test-Path -LiteralPath $videoPath -PathType Leaf)) {
      throw "No se creó video.mp4 de prueba para scene_$('{0:00}' -f $n): $videoPath"
    }

    $videoItem = Get-Item -LiteralPath $videoPath
    if ($videoItem.Length -lt 10000) {
      throw "video.mp4 de prueba demasiado pequeño para scene_$('{0:00}' -f $n): $($videoItem.Length) bytes"
    }
  }
}

Write-Host "== Parcheando manifest_v03 del LIVE clonado a mixed visuals ==" -ForegroundColor Cyan
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $manifest.scenes_v03 -or @($manifest.scenes_v03).Count -lt 4) {
  throw "manifest_v03.json no contiene al menos 4 scenes_v03 válidas"
}

foreach ($spec in $sceneSpecs) {
  $n = [int]$spec.SceneNumber
  $sceneId = "scene_{0:000}" -f $n
  $sceneFolderRel = "artifacts/scenes/scene_{0:00}" -f $n
  $scene = @($manifest.scenes_v03)[$n - 1]

  if (-not $scene.assets) {
    throw "$sceneId no tiene assets"
  }

  if ($spec.ExpectedMedia -eq "video") {
    $scene.assets.image = ""
    $scene.assets.video = "$sceneFolderRel/video.mp4"
    $scene.visual_kind = "video"
    $scene.visual_source_kind = "stock_video"
    $scene.visual_capability = "stock_video"
  }
  else {
    $scene.assets.image = "$sceneFolderRel/image.png"
    $scene.assets.video = ""
    $scene.visual_kind = "image"
    $scene.visual_source_kind = "stock_image"
    $scene.visual_capability = "stock_image"
  }
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
  $manifestPath,
  ($manifest | ConvertTo-Json -Depth 50),
  $utf8NoBom
)

Write-Host "== Reescribiendo pack compat ==" -ForegroundColor Cyan
& $writePack -LiveDir $OutputLiveDir
if ($LASTEXITCODE -ne 0) {
  throw "write_pack_compat_v03.ps1 devolvió exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $packPath -PathType Leaf)) {
  throw "No se generó pack.json: $packPath"
}

Write-Host "== Inspección rápida scenes 001..004 manifest + pack ==" -ForegroundColor Cyan
$manifestCheck = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$packCheck     = Get-Content -LiteralPath $packPath -Raw -Encoding UTF8 | ConvertFrom-Json

$inspectRows = @()
foreach ($spec in $sceneSpecs) {
  $n = [int]$spec.SceneNumber
  $m = @($manifestCheck.scenes_v03)[$n - 1]
  $p = @($packCheck.scenes)[$n - 1]

  $inspectRows += [pscustomobject]@{
    source      = "manifest_v03"
    id          = [string]$m.id
    visual_kind = [string]$m.visual_kind
    image       = [string]$m.assets.image
    video       = [string]$m.assets.video
    audio       = [string]$m.assets.audio_clip
  }

  $inspectRows += [pscustomobject]@{
    source      = "pack_json"
    id          = [string]$p.id
    visual_kind = [string]$p.visual_kind
    image       = [string]$p.image
    video       = [string]$p.video
    audio       = [string]$p.audio
  }
}

$inspectRows | Format-Table -AutoSize

foreach ($spec in $sceneSpecs) {
  $n = [int]$spec.SceneNumber
  $sceneId = "scene_{0:000}" -f $n
  $expected = [string]$spec.ExpectedMedia

  $m = @($manifestCheck.scenes_v03)[$n - 1]
  $p = @($packCheck.scenes)[$n - 1]

  Assert-SceneVisualState -Label ("manifest_v03 {0}" -f $sceneId) -SceneObj $m -ExpectedMediaType $expected
  Assert-SceneVisualState -Label ("pack_json {0}" -f $sceneId) -SceneObj $p -ExpectedMediaType $expected -IsPack
}

Write-Host "== Smoke sobre LIVE mixed visuals ==" -ForegroundColor Cyan
& $smoke -LiveDir $OutputLiveDir
if ($LASTEXITCODE -ne 0) {
  throw "smoke_live_manifest_v03.ps1 falló sobre LIVE mixed visuals"
}

Write-Host "== Render real sobre LIVE mixed visuals ==" -ForegroundColor Cyan

$renderStdOut = Join-Path $OutputLiveDir "video_render_mixed_visuals.stdout.log"
$renderStdErr = Join-Path $OutputLiveDir "video_render_mixed_visuals.stderr.log"

foreach ($logPath in @($renderStdOut, $renderStdErr)) {
  if (Test-Path -LiteralPath $logPath) {
    Remove-Item -LiteralPath $logPath -Force
  }
}

$prevPythonUnbuffered = $null
$hadPythonUnbuffered = Test-Path Env:PYTHONUNBUFFERED
if ($hadPythonUnbuffered) {
  $prevPythonUnbuffered = $env:PYTHONUNBUFFERED
}

$rendererExit = 0
try {
  $env:PYTHONUNBUFFERED = "1"

  $proc = Start-Process `
    -FilePath "py" `
    -ArgumentList @(
      "-u",
      $renderer,
      "--pack-dir", $OutputLiveDir,
      "--out", $renderOut
    ) `
    -NoNewWindow `
    -Wait `
    -PassThru `
    -RedirectStandardOutput $renderStdOut `
    -RedirectStandardError $renderStdErr

  $rendererExit = [int]$proc.ExitCode
}
finally {
  if ($hadPythonUnbuffered) {
    $env:PYTHONUNBUFFERED = $prevPythonUnbuffered
  }
  else {
    Remove-Item Env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue
  }
}

Write-Host "== Renderer stdout log ==" -ForegroundColor DarkCyan
if (Test-Path -LiteralPath $renderStdOut -PathType Leaf) {
  Get-Content -LiteralPath $renderStdOut -Encoding UTF8
}
else {
  Write-Host "(stdout vacío)" -ForegroundColor DarkGray
}

Write-Host "== Renderer stderr log ==" -ForegroundColor DarkCyan
if ((Test-Path -LiteralPath $renderStdErr -PathType Leaf) -and ((Get-Item -LiteralPath $renderStdErr).Length -gt 0)) {
  Get-Content -LiteralPath $renderStdErr -Encoding UTF8
}
else {
  Write-Host "(stderr vacío)" -ForegroundColor DarkGray
}

if ($rendererExit -ne 0) {
  throw "render_pack_v03.py falló sobre LIVE mixed visuals con exit code $rendererExit"
}

if (-not (Test-Path -LiteralPath $renderOut -PathType Leaf)) {
  throw "Renderer no generó salida: $renderOut"
}

$renderItem = Get-Item -LiteralPath $renderOut
if ($renderItem.Length -lt 20000) {
  throw "Render mixed visuals demasiado pequeño: $($renderItem.Length) bytes"
}

if (-not (Test-Path -LiteralPath $renderStdOut -PathType Leaf)) {
  throw "No existe stdout log del renderer: $renderStdOut"
}

$stdoutText = [System.IO.File]::ReadAllText($renderStdOut)

if ([string]::IsNullOrWhiteSpace($stdoutText)) {
  throw "stdout log del renderer quedó vacío"
}

$mustContain = @(
  (Join-Path $OutputLiveDir "artifacts\scenes\scene_01\video.mp4"),
  (Join-Path $OutputLiveDir "artifacts\scenes\scene_02\image.png"),
  (Join-Path $OutputLiveDir "artifacts\scenes\scene_03\video.mp4"),
  (Join-Path $OutputLiveDir "artifacts\scenes\scene_04\image.png")
)

foreach ($expectedPath in $mustContain) {
  if ($stdoutText.IndexOf($expectedPath, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
    throw "stdout log no muestra uso esperado de asset activo: $expectedPath"
  }
}

$mustNotContain = @(
  (Join-Path $OutputLiveDir "artifacts\scenes\scene_01\image.png"),
  (Join-Path $OutputLiveDir "artifacts\scenes\scene_03\image.png")
)

foreach ($unexpectedPath in $mustNotContain) {
  if ($stdoutText.IndexOf($unexpectedPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw "stdout log muestra asset inesperado cuando debía usar video activo: $unexpectedPath"
  }
}

Write-Host "OK: smoke mixed visuals v03 completado" -ForegroundColor Green
Write-Host ("LIVE={0}" -f $OutputLiveDir) -ForegroundColor DarkGray
Write-Host ("RENDER_OUT={0}" -f $renderOut) -ForegroundColor DarkGray
Write-Host ("RENDER_OUT_BYTES={0}" -f $renderItem.Length) -ForegroundColor DarkGray