Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$repo = (Resolve-Path ".").Path
Set-Location $repo

$py = "C:\Users\vanta\AppData\Local\Python\bin\python.exe"
if (!(Test-Path -LiteralPath $py)) { throw "No existe python wrapper: $py" }

New-Item -ItemType Directory -Force "$repo\.tmp\pytest" | Out-Null
$env:TEMP = (Resolve-Path "$repo\.tmp\pytest").Path
$env:TMP  = $env:TEMP

Write-Host "=== SMOKE v0.3 (determinista) ==="

$compileTargets = @("studio","cli","app","tools","tests")
foreach ($t in $compileTargets) {
  if (Test-Path -LiteralPath (Join-Path $repo $t)) {
    & $py -m compileall (Join-Path $repo $t) -q
  }
}

& $py -m pytest -q --basetemp $env:TEMP -p no:cacheprovider

Write-Host "OK: SMOKE PASSED"
