param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $PackDir,

  # preset A/B/C/D
  [ValidateSet("A","B","C","D")]
  [string] $Preset = "B",

  # Si quieres incluir también el FAST (además del CINE final)
  [switch] $IncludeFast = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

# Repo root (tools/..)
$Repo = Split-Path $PSScriptRoot -Parent

# Validar PackDir
if (!(Test-Path $PackDir -PathType Container)) {
  throw "PackDir no existe o no es directorio: $PackDir"
}
$PackDir = (Resolve-Path $PackDir).Path

# Derivar RunDir y RunId: ...\runs\<RunId>\content_pack
$runDir = Split-Path $PackDir -Parent
$runId  = Split-Path $runDir -Leaf

# Archivos/paths esperados
$videoCine = Join-Path $Repo ("workspace\output\video_FINAL_CINE_MUSIC_DYNAMIC_{0}.mp4" -f $Preset)
$videoPro  = Join-Path $Repo ("workspace\output\video_FINAL_CINE_MUSIC_DYNAMIC_{0}_PRO.mp4" -f $Preset)
$videoEdit    = Join-Path $Repo ("workspace\output\video_FINAL_CINE_MUSIC_DYNAMIC_{0}_EDIT.mp4" -f $Preset)
$videoProEdit = Join-Path $Repo ("workspace\output\video_FINAL_CINE_MUSIC_DYNAMIC_{0}_PRO_EDIT.mp4" -f $Preset)
$videoFast = Join-Path $Repo ("workspace\output\video_FINAL_FAST_{0}.mp4" -f $Preset)

$renderManifest = Join-Path $runDir "render\render_manifest.json"
$packManifest   = Join-Path $PackDir "manifest.json"
$storyboard     = Join-Path $PackDir "storyboard.json"

# Validaciones fuertes (no copiar si falta lo canonical)
if (!(Test-Path $videoCine)) { throw "Falta video canonical CINE_MUSIC_DYNAMIC: $videoCine" }
if ($IncludeFast -and !(Test-Path $videoFast)) { throw "Pediste -IncludeFast pero falta: $videoFast" }

if (!(Test-Path $renderManifest)) { throw "Falta render_manifest.json: $renderManifest" }
if (!(Test-Path $packManifest))   { throw "Falta content_pack\manifest.json: $packManifest" }
if (!(Test-Path $storyboard))     { throw "Falta content_pack\storyboard.json: $storyboard" }

# Release dir
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$relRoot = Join-Path $Repo "workspace\release"
New-Item -ItemType Directory -Force -Path $relRoot | Out-Null

$relDir = Join-Path $relRoot ("STUDIO_RELEASE_{0}_{1}_{2}" -f $runId, $Preset, $stamp)
New-Item -ItemType Directory -Force -Path $relDir | Out-Null

# Subdirs
$relVideo = Join-Path $relDir "video"
$relMeta  = Join-Path $relDir "meta"
$relPack  = Join-Path $relDir "content_pack"
New-Item -ItemType Directory -Force -Path $relVideo,$relMeta,$relPack | Out-Null

# Copiar outputs
Copy-Item $videoCine (Join-Path $relVideo (Split-Path $videoCine -Leaf)) -Force
# COPY_EDIT_V1
if (Test-Path $videoProEdit) {
  Copy-Item $videoProEdit (Join-Path $relVideo (Split-Path $videoProEdit -Leaf)) -Force
  Write-Host ("OK: EDIT PRO incluido -> {0}" -f (Split-Path $videoProEdit -Leaf)) -ForegroundColor Green
} else {
  Write-Host ("INFO: no existe EDIT PRO (skip): {0}" -f $videoProEdit) -ForegroundColor DarkGray
}

if (Test-Path $videoEdit) {
  Copy-Item $videoEdit (Join-Path $relVideo (Split-Path $videoEdit -Leaf)) -Force
  Write-Host ("OK: EDIT incluido -> {0}" -f (Split-Path $videoEdit -Leaf)) -ForegroundColor Green
} else {
  Write-Host ("INFO: no existe EDIT (skip): {0}" -f $videoEdit) -ForegroundColor DarkGray
}
if (Test-Path $videoPro) {
  Copy-Item $videoPro (Join-Path $relVideo (Split-Path $videoPro -Leaf)) -Force
  Write-Host ("OK: PRO incluido -> {0}" -f (Split-Path $videoPro -Leaf)) -ForegroundColor Green
} else {
  Write-Host ("WARN: no existe PRO (skip): {0}" -f $videoPro) -ForegroundColor Yellow
}
if ($IncludeFast) {
  Copy-Item $videoFast (Join-Path $relVideo (Split-Path $videoFast -Leaf)) -Force
}

# Copiar metadata clave
Copy-Item $renderManifest (Join-Path $relMeta "render_manifest.json") -Force
Copy-Item $packManifest   (Join-Path $relMeta "manifest.json") -Force
Copy-Item $storyboard     (Join-Path $relMeta "storyboard.json") -Force

# Copiar TODO el content_pack (JSONs/prompts/etc) para reproducibilidad
# (si quieres hacerlo mínimo, dime y lo reducimos)
Copy-Item $PackDir (Join-Path $relDir "content_pack_full") -Recurse -Force

# Nota release
$note = @"
STUDIO_MVP RELEASE
RunId:   $runId
Preset:  $Preset
Date:    $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

Canonical outputs:
- $(Split-Path $videoCine -Leaf)
$(if ($IncludeFast) { "- $(Split-Path $videoFast -Leaf)" } else { "" })

Reproduce:
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\final.ps1 -PackDir "$PackDir" -MaxScenes 4 -Preset $Preset -Mode FAST
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\final.ps1 -PackDir "$PackDir" -MaxScenes 4 -Preset $Preset -Mode CINE -MusicMode fixed -DuckingMode dynamic
"@
[System.IO.File]::WriteAllText((Join-Path $relDir "RELEASE.txt"), $note, [Text.UTF8Encoding]::new($false))

# ZIP (rápido)
$zip = Join-Path $relRoot ("STUDIO_RELEASE_{0}_{1}_{2}.zip" -f $runId, $Preset, $stamp)
if (Test-Path $zip) { Remove-Item $zip -Force }
# LATEST_ALIAS_V1
# Crea release/video/video_latest.mp4 (prioridad: PRO_EDIT > PRO > EDIT > no-FAST)
$latestDst = Join-Path $relVideo "video_latest.mp4"
$latestSrc = $null

$pick = @(Get-ChildItem $relVideo -File -Filter "*_PRO_EDIT.mp4" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1)
if (-not $pick) { $pick = @(Get-ChildItem $relVideo -File -Filter "*_PRO.mp4" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1) }
if (-not $pick) { $pick = @(Get-ChildItem $relVideo -File -Filter "*_EDIT.mp4" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1) }
if (-not $pick) {
  $pick = @(Get-ChildItem $relVideo -File -Filter "*.mp4" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch 'FAST' } |
    Sort-Object Name | Select-Object -First 1)
}

if ($pick) { $latestSrc = $pick[0].FullName }

if ($latestSrc) {
  Copy-Item $latestSrc $latestDst -Force
  Write-Host ("OK: latest alias -> {0} (from {1})" -f (Split-Path $latestDst -Leaf), (Split-Path $latestSrc -Leaf)) -ForegroundColor Green
} else {
  Write-Host "WARN: no pude crear video_latest.mp4 (no encontré candidatos en relVideo)" -ForegroundColor Yellow
}
Compress-Archive -Path (Join-Path $relDir "*") -DestinationPath $zip -Force

Write-Host ""
Write-Host "OK: RELEASE dir -> $relDir" -ForegroundColor Green
Write-Host "OK: ZIP         -> $zip" -ForegroundColor Green
Write-Host ""
Write-Host "Contenido (video):" -ForegroundColor Cyan
Get-ChildItem $relVideo -File | Sort-Object Length -Descending | Format-Table Name,Length,LastWriteTime -AutoSize