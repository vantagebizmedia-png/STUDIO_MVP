param(
  [string]$WorkspaceRoot = "",
  [switch]$CleanRepoOutputs
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

Write-Host "== SMOKE v0.3 (live->workspace copier) ==" -ForegroundColor Cyan

$repo = (Resolve-Path ".").Path

# 0) WorkspaceRoot obligatorio (y absoluto)
$WS = $WorkspaceRoot
if ([string]::IsNullOrWhiteSpace($WS)) { $WS = $env:STUDIO_WORKSPACE }
if ([string]::IsNullOrWhiteSpace($WS)) { throw "Falta -WorkspaceRoot o env:STUDIO_WORKSPACE" }
if (-not [IO.Path]::IsPathRooted($WS)) { throw "WorkspaceRoot debe ser absoluto: $WS" }
$WS = (Resolve-Path $WS).Path

New-Item -ItemType Directory -Force -Path (Join-Path $WS "runs"),(Join-Path $WS "tmp"),(Join-Path $WS "cache") | Out-Null

Write-Host ("Repo      : " + $repo)
Write-Host ("Workspace : " + $WS)

# 1) Ejecuta smoke como PROCESO SEPARADO con OUT/ERR a disco + timeout
$logsDir = Join-Path $WS "runs\_logs"
New-Item -ItemType Directory -Force $logsDir | Out-Null
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$smokeOut = Join-Path $logsDir ("smoke_v03_inner_" + $ts + ".out.log")
$smokeErr = Join-Path $logsDir ("smoke_v03_inner_" + $ts + ".err.log")
if (Test-Path $smokeOut) { Remove-Item -Force $smokeOut }
if (Test-Path $smokeErr) { Remove-Item -Force $smokeErr }

# destino que el caller espera
$dstRoot = Join-Path $WS "runs\smoke_live_latest"
$dstArt  = Join-Path $dstRoot "artifacts"

$smokeTimeoutSec = 1800  # 30 min

try {
  $env:STUDIO_WORKSPACE = $WS
  $env:TEMP = (Join-Path $WS "tmp")
  $env:TMP  = (Join-Path $WS "tmp")

  $smokeScript = Join-Path $repo "tools\smoke_v03.ps1"
  if (-not (Test-Path -LiteralPath $smokeScript)) { throw ("No existe: " + $smokeScript) }

  $p = Start-Process -FilePath "pwsh" -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy","Bypass",
    "-File", $smokeScript
  ) -WorkingDirectory $repo -NoNewWindow -PassThru `
    -RedirectStandardOutput $smokeOut -RedirectStandardError $smokeErr

  $null = Wait-Process -Id $p.Id -Timeout $smokeTimeoutSec -ErrorAction SilentlyContinue
  if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    throw ("smoke_v03.ps1 TIMEOUT (" + $smokeTimeoutSec + " s). Logs: OUT=" + $smokeOut + " ; ERR=" + $smokeErr)
  }
  if ($p.ExitCode -ne 0) {
    throw ("smoke_v03.ps1 falló (ExitCode=" + $p.ExitCode + "). Logs: OUT=" + $smokeOut + " ; ERR=" + $smokeErr)
  }

  # 2) Fuente REAL de artifacts (confirmado por log): .\_v03_smoke_cfg\artifacts
  $srcArtifacts = Join-Path $repo "_v03_smoke_cfg\artifacts"
  if (-not (Test-Path -LiteralPath $srcArtifacts)) {
    throw ("No existe artifacts esperado: " + $srcArtifacts + ". Revisa logs: OUT=" + $smokeOut + " ; ERR=" + $smokeErr)
  }

  # 2.1) Evitar el wildcard '*' (si no hay matches, PS lo trata como ruta inexistente)
  $items = Get-ChildItem -LiteralPath $srcArtifacts -Force -File -ErrorAction Stop
  if (-not $items -or $items.Count -lt 1) {
    throw ("Artifacts vacío: " + $srcArtifacts + ". Revisa logs: OUT=" + $smokeOut + " ; ERR=" + $smokeErr)
  }

  # 3) Copia artifacts al live estable en workspace
New-Item -ItemType Directory -Force -Path $dstArt | Out-Null
foreach ($it in $items) {
  Copy-Item -LiteralPath $it.FullName -Destination $dstArt -Force -ErrorAction Stop
}

# 3.1) Promover archivos clave al ROOT live (compat con smoke_live_manifest_v03/apply_subtitles/smoke_subtitles)
$srcManifest = Join-Path $srcArtifacts "manifest_v03.json"
if (-not (Test-Path -LiteralPath $srcManifest)) {
  throw ("Falta manifest_v03.json en SRC artifacts: " + $srcArtifacts)
}
Copy-Item -LiteralPath $srcManifest -Destination (Join-Path $dstRoot "manifest_v03.json") -Force -ErrorAction Stop

# Imagen principal (1 por escena en smoke actual)
$srcImg = Get-ChildItem -LiteralPath $srcArtifacts -Filter "image_*.png" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $srcImg) { throw ("Falta image_*.png en SRC artifacts: " + $srcArtifacts) }
Copy-Item -LiteralPath $srcImg.FullName -Destination (Join-Path $dstRoot $srcImg.Name) -Force -ErrorAction Stop

# Audio principal
$srcAud = Get-ChildItem -LiteralPath $srcArtifacts -Filter "audio_*.wav" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $srcAud) { throw ("Falta audio_*.wav en SRC artifacts: " + $srcArtifacts) }
Copy-Item -LiteralPath $srcAud.FullName -Destination (Join-Path $dstRoot $srcAud.Name) -Force -ErrorAction Stop

# (Opcional) Copiar script_*.txt al root live si existe
$srcScript = Get-ChildItem -LiteralPath $srcArtifacts -Filter "script_*.txt" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($srcScript) {
  Copy-Item -LiteralPath $srcScript.FullName -Destination (Join-Path $dstRoot $srcScript.Name) -Force -ErrorAction Stop
}

# 4) Limpieza opcional (NO exports)
  if ($CleanRepoOutputs) {
    $candidates = @(
      (Join-Path $repo "_demo_out"),
      (Join-Path $repo "_demo_out_legacy"),
      (Join-Path $repo "_v03_legacy_run"),
      (Join-Path $repo "_v03_smoke_cfg")
    )
    foreach ($p2 in $candidates) {
      if (Test-Path -LiteralPath $p2) { Remove-Item -LiteralPath $p2 -Recurse -Force -ErrorAction SilentlyContinue }
    }
  }

  # OK: el caller debe leer el DIR RAÍZ live (no \artifacts)
  Write-Output ("LIVE_WORKSPACE_DIR=" + $dstRoot)
  exit 0
}
catch {
  # Siempre dejamos marcador para diagnóstico, pero fallamos (caller lo verá)
  Write-Output ("LIVE_WORKSPACE_DIR=" + $dstRoot)
  throw
}



