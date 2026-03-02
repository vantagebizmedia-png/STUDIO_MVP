Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$repo = (Resolve-Path ".").Path
Set-Location $repo

# Python bueno (wrapper estable)
$py = "C:\Users\vanta\AppData\Local\Python\bin\python.exe"
if (!(Test-Path -LiteralPath $py)) { throw "No existe python wrapper: $py" }

# Temp local para evitar permisos raros en %TEMP%
New-Item -ItemType Directory -Force "$repo\.tmp\pytest" | Out-Null
$env:TEMP = (Resolve-Path "$repo\.tmp\pytest").Path
$env:TMP  = $env:TEMP

Write-Host "=== SMOKE v0.3 (determinista) ==="

# Compila SOLO carpetas relevantes (evita _archive con cosas rotas)
& $py -c "import compileall, sys, os; ok=True;
ok = ok and compileall.compile_dir('studio', quiet=1) if os.path.isdir('studio') else ok;
ok = ok and compileall.compile_dir('cli', quiet=1) if os.path.isdir('cli') else ok;
ok = ok and compileall.compile_dir('tools', quiet=1) if os.path.isdir('tools') else ok;
ok = ok and compileall.compile_dir('tests', quiet=1) if os.path.isdir('tests') else ok;
sys.exit(0 if ok else 1)"

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
