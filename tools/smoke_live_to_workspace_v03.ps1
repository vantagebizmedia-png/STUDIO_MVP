param(
  [string]$WorkspaceRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

Write-Host "== SMOKE v0.3 (live->workspace copier) ==" -ForegroundColor Cyan

$repo = (Resolve-Path -LiteralPath ".").Path

# WorkspaceRoot obligatorio (absoluto)
$WS = $WorkspaceRoot
if ([string]::IsNullOrWhiteSpace($WS)) { $WS = $env:STUDIO_WORKSPACE }
if ([string]::IsNullOrWhiteSpace($WS)) { throw "Falta -WorkspaceRoot o env:STUDIO_WORKSPACE" }
if (-not [IO.Path]::IsPathRooted($WS)) { throw "WorkspaceRoot debe ser absoluto: $WS" }
$WS = (Resolve-Path -LiteralPath $WS).Path

New-Item -ItemType Directory -Force -Path (Join-Path $WS "runs"),(Join-Path $WS "tmp"),(Join-Path $WS "cache") | Out-Null

Write-Host ("Repo      : " + $repo)
Write-Host ("Workspace : " + $WS)

# Destino estable
$dstRoot = Join-Path $WS "runs\smoke_live_latest"
$dstArt  = Join-Path $dstRoot "artifacts"
New-Item -ItemType Directory -Force -Path $dstRoot,$dstArt | Out-Null

# 1) Ejecuta smoke_v03.ps1 (produce _v03_smoke_cfg/artifacts)
$logsDir = Join-Path $WS "runs\_logs"
New-Item -ItemType Directory -Force $logsDir | Out-Null
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$smokeOut = Join-Path $logsDir ("smoke_v03_inner_" + $ts + ".out.log")
$smokeErr = Join-Path $logsDir ("smoke_v03_inner_" + $ts + ".err.log")
if (Test-Path $smokeOut) { Remove-Item -Force $smokeOut }
if (Test-Path $smokeErr) { Remove-Item -Force $smokeErr }

$smokeTimeoutSec = 1800

$env:STUDIO_WORKSPACE = $WS
$env:TEMP = (Join-Path $WS "tmp")
$env:TMP  = (Join-Path $WS "tmp")

$smokeScript = Join-Path $repo "tools\smoke_v03.ps1"
if (-not (Test-Path -LiteralPath $smokeScript)) { throw ("No existe: " + $smokeScript) }

$p2 = Start-Process -FilePath "pwsh" -ArgumentList @(
  "-NoProfile",
  "-ExecutionPolicy","Bypass",
  "-File", $smokeScript
) -WorkingDirectory $repo -NoNewWindow -PassThru `
  -RedirectStandardOutput $smokeOut -RedirectStandardError $smokeErr

$null = Wait-Process -Id $p2.Id -Timeout $smokeTimeoutSec -ErrorAction SilentlyContinue
if (-not $p2.HasExited) {
  Stop-Process -Id $p2.Id -Force -ErrorAction SilentlyContinue
  throw ("smoke_v03.ps1 TIMEOUT (" + $smokeTimeoutSec + " s). Logs: OUT=" + $smokeOut + " ; ERR=" + $smokeErr)
}
if ($p2.ExitCode -ne 0) {
  throw ("smoke_v03.ps1 falló (ExitCode=" + $p2.ExitCode + "). Logs: OUT=" + $smokeOut + " ; ERR=" + $smokeErr)
}

$srcArtifacts = Join-Path $repo "_v03_smoke_cfg\artifacts"
if (-not (Test-Path -LiteralPath $srcArtifacts)) {
  throw ("No existe artifacts esperado: " + $srcArtifacts + ". Logs: OUT=" + $smokeOut + " ; ERR=" + $smokeErr)
}

# 2) Copia artifacts al LIVE (solo archivos top-level)
$items = Get-ChildItem -LiteralPath $srcArtifacts -Force -File -ErrorAction Stop
if (-not $items -or $items.Count -lt 1) { throw ("Artifacts vacío: " + $srcArtifacts) }

foreach ($it in $items) {
  Copy-Item -LiteralPath $it.FullName -Destination $dstArt -Force -ErrorAction Stop
}

# Promover manifest_v03 y 1 imagen+audio al ROOT (compat con herramientas viejas)
$srcManifest = Join-Path $srcArtifacts "manifest_v03.json"
if (-not (Test-Path -LiteralPath $srcManifest)) { throw ("Falta manifest_v03.json en: " + $srcArtifacts) }
Copy-Item -LiteralPath $srcManifest -Destination (Join-Path $dstRoot "manifest_v03.json") -Force

$img0 = Get-ChildItem -LiteralPath $srcArtifacts -Filter "image_*.png" -File | Select-Object -First 1
if (-not $img0) { throw ("Falta image_*.png en: " + $srcArtifacts) }
Copy-Item -LiteralPath $img0.FullName -Destination (Join-Path $dstRoot $img0.Name) -Force

$aud0 = Get-ChildItem -LiteralPath $srcArtifacts -Filter "audio_*.wav" -File | Select-Object -First 1
if (-not $aud0) { throw ("Falta audio_*.wav en: " + $srcArtifacts) }
Copy-Item -LiteralPath $aud0.FullName -Destination (Join-Path $dstRoot $aud0.Name) -Force

# 3) Normaliza manifest_v03.json a schema LIVE v03 esperado por tools:
#    - artifacts.image / artifacts.audio (NECESARIO para apply_subtitles_live_v03.ps1)
#    - scenes_v03[i].assets.audio_clip = artifacts/audio_sXX.wav
#    - scenes_v03[i].assets.image = [{path: <ABSOLUTE_PATH_EXISTING>}]
$max = 6
try {
  if (-not [string]::IsNullOrWhiteSpace($env:STUDIO_SMOKE_MAXSCENES)) { $max = [int]$env:STUDIO_SMOKE_MAXSCENES }
} catch { $max = 6 }
if ($max -lt 1) { $max = 1 }

# Total determinista (compat con smoke_live_manifest_v03)
$totalMs = 20000
$seg = [int]([Math]::Floor($totalMs / $max))
$rem = $totalMs - ($seg * $max)

# Base assets (promovidos al root)
$baseImgAbs = (Resolve-Path -LiteralPath (Join-Path $dstRoot $img0.Name)).Path
$baseAudAbs = (Resolve-Path -LiteralPath (Join-Path $dstRoot $aud0.Name)).Path

# Crear escenas visuales (artifacts/scenes/scene_XX/image.png) y audio_clips (artifacts/audio_sXX.wav)
$sceneRoot = Join-Path $dstArt "scenes"
New-Item -ItemType Directory -Force -Path $sceneRoot | Out-Null

$scenes = @()
$audioClips = @()
$cur = 0

for ($i=1; $i -le $max; $i++) {
  $dur = $seg + ($(if ($i -le $rem) { 1 } else { 0 }))
  $st = $cur
  $en = $cur + $dur
  $cur = $en

  $clipRel = ("artifacts/audio_s{0:d2}.wav" -f $i)
  $clipAbs = Join-Path $dstRoot $clipRel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $clipAbs) | Out-Null
  Copy-Item -LiteralPath $baseAudAbs -Destination $clipAbs -Force

  $sd = Join-Path $sceneRoot ("scene_{0:d2}" -f $i)
  New-Item -ItemType Directory -Force -Path $sd | Out-Null
  $imgAbs = Join-Path $sd "image.png"
  Copy-Item -LiteralPath $baseImgAbs -Destination $imgAbs -Force

  $audioClips += [pscustomobject]@{
    id       = ("clip_{0:d3}" -f $i)
    start_ms = $st
    end_ms   = $en
    text     = ""
    path     = $clipRel
  }

  $scenes += [pscustomobject]@{
    index    = $i
    start_ms = $st
    end_ms   = $en
    text     = ("Escena {0:d2}" -f $i)
    assets   = [pscustomobject]@{
      audio_clip = $clipRel
      image      = @([pscustomobject]@{ path = $imgAbs })
    }
  }
}

# artifacts.* para apply_subtitles_live_v03.ps1 (relativos al root LIVE)
$mfOut = [pscustomobject]@{
  version = "v03"
  artifacts = [pscustomobject]@{
    image = $img0.Name
    audio = $aud0.Name
  }
  audio_clips = $audioClips
  scene_builder_v03 = [pscustomobject]@{
    total_audio_ms = $totalMs
    note = "normalized_by_smoke_live_to_workspace_v03"
  }
  scenes_v03 = $scenes
}

$mfPath = Join-Path $dstRoot "manifest_v03.json"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($mfPath, ($mfOut | ConvertTo-Json -Depth 50), $utf8NoBom)

Write-Output ("LIVE_WORKSPACE_DIR=" + $dstRoot)
exit 0
