param(
  [string]$ScriptText = "texto live smoke",
  [string]$V03Config  = ".\config\studio_v03_text_live_smoke.json"
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = $RepoRoot
. "$PSScriptRoot\resolve_python.ps1"
$py = Resolve-PythonExe -RepoRoot $RepoRoot
chcp 65001 | Out-Null

if (-not $env:OPENAI_API_KEY -or $env:OPENAI_API_KEY.Trim().Length -lt 20) {
  throw "Falta OPENAI_API_KEY en esta sesión."
}

$prov = ".\config\providers.json"
$bak  = "$prov.bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item $prov $bak -Force

try {
  # SOLO texto LIVE, todo lo demás DRY
  $j = Get-Content $prov -Raw -Encoding UTF8 | ConvertFrom-Json
  $j.text.mode  = "LIVE"
  $j.image.mode = "DRY"
  $j.voice.mode = "DRY"
  ($j | ConvertTo-Json -Depth 50) | Set-Content -Encoding UTF8 $prov

  # Release v03
  & $py .\tools\release_pack_v03.py --v03-config $V03Config --script $ScriptText --overwrite

} finally {
  # Revert seguro SIEMPRE
  Copy-Item $bak $prov -Force
  Write-Host "OK: providers.json revertido." -ForegroundColor Cyan
}
