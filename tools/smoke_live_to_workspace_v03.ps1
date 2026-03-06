param(
  [string]$WorkspaceRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

# Promover manifest_v03 y 1 imagen+audio al ROOT
$srcManifest = Join-Path $srcArtifacts "manifest_v03.json"
if (-not (Test-Path -LiteralPath $srcManifest)) { throw ("Falta manifest_v03.json en: " + $srcArtifacts) }
Copy-Item -LiteralPath $srcManifest -Destination (Join-Path $dstRoot "manifest_v03.json") -Force

$img0 = Get-ChildItem -LiteralPath $srcArtifacts -Filter "image_*.png" -File | Select-Object -First 1
if (-not $img0) { throw ("Falta image_*.png en: " + $srcArtifacts) }
Copy-Item -LiteralPath $img0.FullName -Destination (Join-Path $dstRoot $img0.Name) -Force

$aud0 = Get-ChildItem -LiteralPath $srcArtifacts -Filter "audio_*.wav" -File | Select-Object -First 1
if (-not $aud0) { throw ("Falta audio_*.wav en: " + $srcArtifacts) }
Copy-Item -LiteralPath $aud0.FullName -Destination (Join-Path $dstRoot $aud0.Name) -Force

# 3) LIVE normalizado
$max = 6
try {
  if (-not [string]::IsNullOrWhiteSpace($env:STUDIO_SMOKE_MAXSCENES)) { $max = [int]$env:STUDIO_SMOKE_MAXSCENES }
} catch { $max = 6 }
if ($max -lt 1) { $max = 1 }

# Baseline actual
if ($max -le 4) {
  $totalMs = 120000
}
elseif ($max -le 8) {
  $totalMs = 180000
}
else {
  $totalMs = 300000
}

$baseImgAbs = (Resolve-Path -LiteralPath (Join-Path $dstRoot $img0.Name)).Path
$baseAudAbs = (Resolve-Path -LiteralPath (Join-Path $dstRoot $aud0.Name)).Path

$sceneRoot = Join-Path $dstArt "scenes"
New-Item -ItemType Directory -Force -Path $sceneRoot | Out-Null

$scenes = @()
$audioClips = @()

# Reparto no uniforme pero determinista
$weights = @()
for ($i = 1; $i -le $max; $i++) {
  $w = 100

  if ($i -eq 1) {
    $w = 70
  }
  elseif ($i -eq $max) {
    $w = 120
  }
  else {
    $w = 100 + ((($i) % 5) * 10)
  }

  $weights += $w
}

$weightSum = (@($weights) | Measure-Object -Sum).Sum
if (-not $weightSum -or $weightSum -le 0) {
  throw "weightSum inválido en smoke_live_to_workspace_v03.ps1"
}

$durations = @()
$assigned = 0

for ($i = 0; $i -lt $max; $i++) {
  if ($i -lt ($max - 1)) {
    $dur = [int][Math]::Floor(($totalMs * $weights[$i]) / $weightSum)
    if ($dur -lt 3000) { $dur = 3000 }
    $durations += $dur
    $assigned += $dur
  }
  else {
    $dur = $totalMs - $assigned
    if ($dur -lt 3000) { $dur = 3000 }
    $durations += $dur
  }
}

$sumDur = (@($durations) | Measure-Object -Sum).Sum
if ($sumDur -ne $totalMs) {
  $delta = $totalMs - $sumDur
  $durations[$durations.Count - 1] = [int]($durations[$durations.Count - 1] + $delta)
}

$cur = 0

for ($i=1; $i -le $max; $i++) {
  $dur = [int]$durations[$i - 1]
  $st = $cur
  $en = $cur + $dur
  if ($i -eq $max) { $en = $totalMs }
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
    id       = ("scene_{0:000}" -f $i)
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

# Script dummy más rico y determinista para alimentar mejor el scene builder
$scriptLines = @(
  "Inicio directo con una idea clara para captar atención desde el primer segundo.",
  "Presentamos el tema principal con una frase simple y fácil de recordar.",
  "Abrimos una promesa concreta para mantener el interés en la siguiente escena.",
  "Introducimos el contexto con lenguaje breve, claro y visual.",
  "Marcamos el problema central que el video busca resolver.",
  "Conectamos el problema con una situación cotidiana y reconocible.",
  "Mostramos una consecuencia práctica de no actuar a tiempo.",
  "Cambiamos el ritmo con una frase corta que funcione como micro hook.",
  "Explicamos el primer punto con enfoque directo y sin rodeos.",
  "Añadimos un ejemplo breve para darle más fuerza a la idea.",
  "Subimos un poco la intensidad narrativa con una afirmación concreta.",
  "Pasamos al segundo punto manteniendo continuidad visual.",
  "Aterrizamos el concepto con una imagen mental sencilla.",
  "Reforzamos el beneficio principal con una frase positiva.",
  "Introducimos una transición natural hacia la siguiente mini idea.",
  "Describimos una acción práctica que la audiencia puede imaginar fácil.",
  "Damos una razón clara para seguir viendo el contenido completo.",
  "Insertamos una línea corta pensada para un cambio visual rápido.",
  "Presentamos otro ángulo del mismo tema para evitar monotonía.",
  "Añadimos una micro conclusión parcial antes del último tramo.",
  "Hacemos una pausa conceptual con una frase breve y contundente.",
  "Volvemos al hilo principal con una explicación concreta.",
  "Resumimos lo importante en palabras simples y memorables.",
  "Empujamos la narrativa hacia el cierre con una idea útil.",
  "Reforzamos el valor práctico de todo lo mostrado hasta aquí.",
  "Introducimos el cierre con tono más concluyente.",
  "Recordamos el mensaje central con una formulación compacta.",
  "Añadimos una última imagen mental para fortalecer retención.",
  "Cerramos con una frase de impulso orientada a acción.",
  "Terminamos con un cierre limpio, directo y fácil de reutilizar en export."
)

$scriptText = ($scriptLines -join " ")

$mfOut = [pscustomobject]@{
  version = "v03"
  artifacts = [pscustomobject]@{
    image = $img0.Name
    audio = $aud0.Name
  }
  script = $scriptText
  audio_clips = $audioClips
  scene_builder_v03 = [pscustomobject]@{
    total_audio_ms = $totalMs
    note = "normalized_by_smoke_live_to_workspace_v03_dynamic_duration"
  }
  scenes_v03 = $scenes
}

$utf8NoBom = [Text.UTF8Encoding]::new($false)

# manifest_v03.json principal
$mfPath = Join-Path $dstRoot "manifest_v03.json"
[IO.File]::WriteAllText($mfPath, ($mfOut | ConvertTo-Json -Depth 50), $utf8NoBom)

# pack.json compat para render_pack_v03.py / finalize_pack_v03.ps1
$packCompatScenes = @()
foreach ($scene in $scenes) {
  $imgPath = ""
  try {
    if ($scene.assets -and $scene.assets.image) {
      if (($scene.assets.image -is [System.Collections.IEnumerable]) -and -not ($scene.assets.image -is [string])) {
        $imgPath = [string]$scene.assets.image[0].path
      }
      elseif ($scene.assets.image -is [string]) {
        $imgPath = [string]$scene.assets.image
      }
    }
  } catch { $imgPath = "" }

  $audioPath = ""
  try {
    if ($scene.assets -and $scene.assets.audio_clip) {
      $audioPath = [string]$scene.assets.audio_clip
    }
  } catch { $audioPath = "" }

  $packCompatScenes += [pscustomobject]@{
    id = [string]$scene.id
    text = [string]$scene.text
    image = $imgPath
    audio = $audioPath
    start_ms = [int]$scene.start_ms
    end_ms = [int]$scene.end_ms
  }
}

$packCompat = [pscustomobject]@{
  version = "v03"
  script = $scriptText
  scenes = $packCompatScenes
  scenes_v03 = $scenes
  audio_clips = $audioClips
  artifacts = [pscustomobject]@{
    image = $img0.Name
    audio = $aud0.Name
  }
}

$packJsonPath = Join-Path $dstRoot "pack.json"
[IO.File]::WriteAllText($packJsonPath, ($packCompat | ConvertTo-Json -Depth 50), $utf8NoBom)

Write-Host ("OK: smoke_live_to_workspace_v03 -> totalAudioMs={0} scenes={1} scriptLines={2} packJson=True" -f $totalMs, $max, @($scriptLines).Count) -ForegroundColor Green
Write-Output ("LIVE_WORKSPACE_DIR=" + $dstRoot)