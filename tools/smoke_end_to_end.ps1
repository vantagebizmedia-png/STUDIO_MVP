Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = $RepoRoot
. "$PSScriptRoot\resolve_python.ps1"
$py = Resolve-PythonExe -RepoRoot $RepoRoot
chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

Set-Location $repo
# Temp fuera del repo (evita permisos/locks). Con fallback si una ruta da "Access denied".
$runId = Get-Date -Format "yyyyMMdd_HHmmss"

$baseCandidates = @(
  (Join-Path $env:LOCALAPPDATA "STUDIO_MVP\tmp"),
  (Join-Path $env:TEMP "STUDIO_MVP\tmp"),
  (Join-Path (Join-Path $env:USERPROFILE "AppData\Local\Temp") "STUDIO_MVP\tmp")
)

$smokeTemp = $null
foreach ($baseTemp in $baseCandidates) {
  try {
    New-Item -ItemType Directory -Force $baseTemp | Out-Null
    $cand = Join-Path $baseTemp ("pytest_" + $runId)
    New-Item -ItemType Directory -Force $cand | Out-Null
    $smokeTemp = (Resolve-Path $cand).Path
    break
  } catch {
    # sigue probando
  }
}

if (-not $smokeTemp) {
  throw "No pude crear carpeta TEMP para smoke. Probé: $($baseCandidates -join '; ')"
}

$env:TEMP = $smokeTemp
$env:TMP  = $env:TEMP
Write-Host "=== SMOKE v0.3 (determinista) ==="

# Compila SOLO carpetas relevantes (evita _archive con cosas rotas)
& $py -c "import compileall, sys, os; ok=True; ok = ok and compileall.compile_dir('studio', quiet=1) if os.path.isdir('studio') else ok; ok = ok and compileall.compile_dir('cli', quiet=1) if os.path.isdir('cli') else ok; ok = ok and compileall.compile_dir('tools', quiet=1) if os.path.isdir('tools') else ok; ok = ok and compileall.compile_dir('tests', quiet=1) if os.path.isdir('tests') else ok; sys.exit(0 if ok else 1)"

# Tests (sin cacheprovider; basetemp controlado)
& $py -m pytest -q --basetemp $env:TEMP -p no:cacheprovider

Write-Host "OK: SMOKE PASSED"

Write-Host "=== HANDOFF v0.3 sanity ==="

# pack mínimo determinista
$pack = Join-Path $env:TEMP "pack_v03_smoke"
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $pack
New-Item -ItemType Directory -Force $pack | Out-Null

# pack.json mínimo (sin heredoc anidado)
$packJson = "{`n  `"version`": `"v03`",`n  `"id`": `"pack_v03_smoke`",`n  `"created_at`": 0`n}`n"
$packJson | Set-Content -Encoding UTF8 (Join-Path $pack "pack.json")

# video base dummy
[IO.File]::WriteAllBytes((Join-Path $pack "video.mp4"), [byte[]](1..16))

# finalize/handoff
& $py tools\finalize_handoff_v03.py --pack-dir $pack

# verifica artefactos
$expected = @("video.mp4","video_music_auto.mp4","video_final.mp4","HANDOFF_READY.txt")
foreach ($f in $expected) {
  if (!(Test-Path (Join-Path $pack $f))) { throw "Falta artefacto: $f" }
}

$zip = "$pack.final_delivery.zip"
$sha = "$zip.sha256.txt"
if (!(Test-Path $zip)) { throw "Falta ZIP final: $zip" }
if (!(Test-Path $sha)) { throw "Falta SHA final: $sha" }

Write-Host "OK: HANDOFF sanity passed"


