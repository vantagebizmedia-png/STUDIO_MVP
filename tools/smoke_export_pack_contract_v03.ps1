param(
  [Parameter(Mandatory=$false)][string]$RepoRoot = "C:\Users\vanta\Documents\STUDIO_MVP",
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot = "C:\Users\vanta\Documents\STUDIO_WORKSPACE",
  [Parameter(Mandatory=$false)][string]$SourceLiveDir = "",
  [Parameter(Mandatory=$false)][string]$OutputRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$psUtf8Compat = Join-Path $PSScriptRoot "ps_utf8_compat_v03.ps1"
if (-not (Test-Path -LiteralPath $psUtf8Compat -PathType Leaf)) {
  throw ("No existe helper utf8 compat: {0}" -f $psUtf8Compat)
}

. $psUtf8Compat

function Fail {
  param([Parameter(Mandatory=$true)][string]$Message)
  throw "SMOKE FAIL: $Message"
}

$resolvePython = Join-Path $PSScriptRoot "resolve_python.ps1"
if (-not (Test-Path -LiteralPath $resolvePython -PathType Leaf)) {
  Fail "No existe helper resolve_python: $resolvePython"
}

. $resolvePython
$pythonExe = Resolve-PythonExe -RepoRoot $RepoRoot

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
  Fail "No existe RepoRoot: $RepoRoot"
}

if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
  Fail "No existe WorkspaceRoot: $WorkspaceRoot"
}

if ([string]::IsNullOrWhiteSpace($SourceLiveDir)) {
  $SourceLiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_mixed_visuals"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $WorkspaceRoot "runs\smoke_export_pack_contract"
}

if (-not (Test-Path -LiteralPath $SourceLiveDir -PathType Container)) {
  Fail "No existe SourceLiveDir: $SourceLiveDir"
}

$manifestPath = Join-Path $SourceLiveDir "manifest_v03.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  Fail "No existe manifest_v03.json en SourceLiveDir: $manifestPath"
}

$exportRoot = Join-Path $OutputRoot "exports"
$negativeRoot = Join-Path $OutputRoot "negative"

if (Test-Path -LiteralPath $OutputRoot) {
  Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null
New-Item -ItemType Directory -Path $negativeRoot -Force | Out-Null

Push-Location $RepoRoot
try {
  Write-Host "== SMOKE EXPORT PACK CONTRACT V03 ==" -ForegroundColor Magenta
  Write-Host ("RepoRoot     : {0}" -f $RepoRoot) -ForegroundColor DarkGray
  Write-Host ("WorkspaceRoot: {0}" -f $WorkspaceRoot) -ForegroundColor DarkGray
  Write-Host ("SourceLiveDir: {0}" -f $SourceLiveDir) -ForegroundColor DarkGray
  Write-Host ("OutputRoot   : {0}" -f $OutputRoot) -ForegroundColor DarkGray

  Write-Host ""
  Write-Host "== PY COMPILE ==" -ForegroundColor Cyan
  $pyTargets = @(
    (Join-Path $RepoRoot "tools\export_v03_pack.py"),
    (Join-Path $RepoRoot "tools\validate_pack.py"),
    (Join-Path $RepoRoot "tools\render_pack_v03.py"),
    (Join-Path $RepoRoot "tools\make_subtitles_from_pack_v03.py"),
    (Join-Path $RepoRoot "tools\release_pack_v03.py"),
    (Join-Path $RepoRoot "tools\finalize_handoff_v03.py")
  )

  foreach ($t in $pyTargets) {
    & $pythonExe -m py_compile $t
    if ($LASTEXITCODE -ne 0) {
      Fail "py_compile falló: $t"
    }
    Write-Host ("OK: {0}" -f $t) -ForegroundColor Green
  }

  $exportPy = Join-Path $RepoRoot "tools\export_v03_pack.py"
  $validatePackPy = Join-Path $RepoRoot "tools\validate_pack.py"
  $renderPackPy = Join-Path $RepoRoot "tools\render_pack_v03.py"

  Write-Host ""
  Write-Host "== EXPORT PACK ==" -ForegroundColor Cyan
  $exportOut = & $pythonExe -u $exportPy `
    --manifest $manifestPath `
    --out-root $exportRoot `
    --overwrite 2>&1

  $exportOut | ForEach-Object { $_.ToString() }

  if ($LASTEXITCODE -ne 0) {
    Fail "export_v03_pack.py devolvió exit code $LASTEXITCODE"
  }

  $packDirLine = $exportOut | Where-Object { $_.ToString() -match '^PACK_DIR:\s*(.+)$' } | Select-Object -Last 1
  if (-not $packDirLine) {
    Fail "No pude extraer PACK_DIR desde export_v03_pack.py"
  }

  $packDir = ([regex]::Match($packDirLine.ToString(), '^PACK_DIR:\s*(.+)$')).Groups[1].Value.Trim()
  if ([string]::IsNullOrWhiteSpace($packDir)) {
    Fail "PACK_DIR quedó vacío"
  }
  if (-not (Test-Path -LiteralPath $packDir -PathType Container)) {
    Fail "PACK_DIR no existe: $packDir"
  }

  $packJsonPath = Join-Path $packDir "pack.json"
  if (-not (Test-Path -LiteralPath $packJsonPath -PathType Leaf)) {
    Fail "No existe pack.json en export: $packJsonPath"
  }

  $packObj = Get-Content -LiteralPath $packJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $packScenes = @($packObj.scenes)
  if ($packScenes.Count -lt 1) {
    Fail "pack.json no tiene scenes[]"
  }

  $videoScenes = @($packScenes | Where-Object { [string]$_.visual_kind -eq "video" })
  $imageScenes = @($packScenes | Where-Object { [string]$_.visual_kind -eq "image" })

  if ($videoScenes.Count -lt 1) {
    Fail "El pack exportado no preservó ninguna escena video"
  }
  if ($imageScenes.Count -lt 1) {
    Fail "El pack exportado no preservó ninguna escena image"
  }

  Write-Host ""
  Write-Host "== INSPECCION RAPIDA ==" -ForegroundColor Cyan
  [pscustomobject]@{
    pack_dir        = $packDir
    scenes_count    = $packScenes.Count
    video_scenes    = $videoScenes.Count
    image_scenes    = $imageScenes.Count
    total_audio_ms  = [int]($packObj.total_audio_ms)
  } | Format-List

  $packScenes |
    Select-Object -First 6 id,index,visual_kind,visual_source_kind,visual_capability,image,video,audio,start_ms,end_ms,duration_ms |
    Format-Table -AutoSize

  Write-Host ""
  Write-Host "== VALIDATE (--fix) ==" -ForegroundColor Cyan
  & $pythonExe -u $validatePackPy --pack-dir $packDir --fix 2>&1 | ForEach-Object { $_.ToString() }
  if ($LASTEXITCODE -ne 0) {
    Fail "validate_pack.py --fix falló con exit code $LASTEXITCODE"
  }

  Write-Host ""
  Write-Host "== RENDER ==" -ForegroundColor Cyan
  & $pythonExe -u $renderPackPy --pack-dir $packDir 2>&1 | ForEach-Object { $_.ToString() }
  if ($LASTEXITCODE -ne 0) {
    Fail "render_pack_v03.py falló con exit code $LASTEXITCODE"
  }

  $videoPath = Join-Path $packDir "video.mp4"
  if (-not (Test-Path -LiteralPath $videoPath -PathType Leaf)) {
    Fail "No se generó video.mp4"
  }

  Write-Host ""
  Write-Host "== FINALIZE ==" -ForegroundColor Cyan
  & .\tools\finalize_pack_v03.ps1 -PackDir $packDir
  if ($LASTEXITCODE -ne 0) {
    Fail "finalize_pack_v03.ps1 falló con exit code $LASTEXITCODE"
  }

  Write-Host ""
  Write-Host "== VALIDATE FINAL ==" -ForegroundColor Cyan
  & $pythonExe -u $validatePackPy --pack-dir $packDir 2>&1 | ForEach-Object { $_.ToString() }
  if ($LASTEXITCODE -ne 0) {
    Fail "validate_pack.py final falló con exit code $LASTEXITCODE"
  }

  $exportManifestPath = Join-Path $packDir "manifest_v03.json"
  $exportManifestObj = Get-Content -LiteralPath $exportManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $exportManifestScenes = @($exportManifestObj.scenes_v03)
  if ($exportManifestScenes.Count -ne $packScenes.Count) {
    Fail "manifest_v03 exportado no preservó el mismo número de scenes_v03 que pack.json"
  }

  for ($i = 0; $i -lt $packScenes.Count; $i++) {
    $p = $packScenes[$i]
    $m = $exportManifestScenes[$i]
    $sceneLabel = [string]($p.id)
    if ([string]::IsNullOrWhiteSpace($sceneLabel)) {
      $sceneLabel = "scene_$($i + 1)"
    }

    $pkVisualSourceKind = ([string]$p.visual_source_kind).Trim().ToLowerInvariant()
    $pkVisualCapability = ([string]$p.visual_capability).Trim().ToLowerInvariant()
    $mfVisualSourceKind = ([string]$m.visual_source_kind).Trim().ToLowerInvariant()
    $mfVisualCapability = ([string]$m.visual_capability).Trim().ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($pkVisualSourceKind)) {
      Fail "$sceneLabel visual_source_kind vacío en pack exportado"
    }
    if ([string]::IsNullOrWhiteSpace($pkVisualCapability)) {
      Fail "$sceneLabel visual_capability vacío en pack exportado"
    }
    if ([string]::IsNullOrWhiteSpace($mfVisualSourceKind)) {
      Fail "$sceneLabel visual_source_kind vacío en manifest exportado"
    }
    if ([string]::IsNullOrWhiteSpace($mfVisualCapability)) {
      Fail "$sceneLabel visual_capability vacío en manifest exportado"
    }
    if ($pkVisualSourceKind -ne $mfVisualSourceKind) {
      Fail "$sceneLabel visual_source_kind pack/manifest export mismatch: pack='$pkVisualSourceKind' manifest='$mfVisualSourceKind'"
    }
    if ($pkVisualCapability -ne $mfVisualCapability) {
      Fail "$sceneLabel visual_capability pack/manifest export mismatch: pack='$pkVisualCapability' manifest='$mfVisualCapability'"
    }
  }

  foreach ($mustExist in @(
    (Join-Path $packDir "pack.json"),
    (Join-Path $packDir "manifest_v03.json"),
    (Join-Path $packDir "video.mp4"),
    (Join-Path $packDir "captions_v03.srt"),
    (Join-Path $packDir "subtitles.srt")
  )) {
    if (-not (Test-Path -LiteralPath $mustExist -PathType Leaf)) {
      Fail "Artefacto faltante tras finalize: $mustExist"
    }
  }

  Write-Host ""
  Write-Host "== NEGATIVE: PATH DESALINEADO ==" -ForegroundColor Cyan
  $brokenPack = Join-Path $negativeRoot "pack_broken_path"
  Copy-Item -LiteralPath $packDir -Destination $brokenPack -Recurse -Force

  $brokenPackJsonPath = Join-Path $brokenPack "pack.json"
  if (-not (Test-Path -LiteralPath $brokenPackJsonPath -PathType Leaf)) {
    Fail "No existe pack.json en copia negativa: $brokenPackJsonPath"
  }

  $brokenPackObj = Get-Content -LiteralPath $brokenPackJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $brokenScenes = @($brokenPackObj.scenes)
  if ($brokenScenes.Count -lt 2) {
    Fail "La copia negativa no tiene suficientes escenas"
  }

  $targetImageScene = $brokenScenes | Where-Object { [string]$_.visual_kind -eq "image" -and [int]$_.index -gt 1 } | Select-Object -First 1
  if (-not $targetImageScene) {
    Fail "No encontré escena image > 1 para el negativo"
  }

  $targetImageScene.image = "artifacts/scenes/scene_01/image.png"

  $brokenJson = $brokenPackObj | ConvertTo-Json -Depth 100
  $brokenJson = $brokenJson -replace "`r`n", "`n"
  $brokenJson = $brokenJson -replace "`r", "`n"
  if (-not $brokenJson.EndsWith("`n")) {
    $brokenJson += "`n"
  }

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($brokenPackJsonPath, $brokenJson, $utf8NoBom)

  $negativeOut = & $pythonExe -u $validatePackPy --pack-dir $brokenPack 2>&1
  $negativeExit = $LASTEXITCODE
  $negativeOut | ForEach-Object { $_.ToString() }

  if ($negativeExit -eq 0) {
    Fail "validate_pack.py NO detectó el path desalineado en la copia negativa"
  }

  $negativeJoined = ($negativeOut | ForEach-Object { $_.ToString() }) -join "`n"
  if (
    ($negativeJoined -notmatch "path desalineado") -and
    ($negativeJoined -notmatch "pack/manifest mismatch") -and
    ($negativeJoined -notmatch "RESULT:\s*FAIL")
  ) {
    Fail "El negativo falló, pero no mostró la señal contractual esperada"
  }

  $global:LASTEXITCODE = 0

  Write-Host ""
  Write-Host "OK: smoke_export_pack_contract_v03 completado" -ForegroundColor Green
  Write-Host ("PACK_DIR={0}" -f $packDir) -ForegroundColor DarkGray
  Write-Host ("BROKEN_PACK={0}" -f $brokenPack) -ForegroundColor DarkGray
}
finally {
  Pop-Location
}
