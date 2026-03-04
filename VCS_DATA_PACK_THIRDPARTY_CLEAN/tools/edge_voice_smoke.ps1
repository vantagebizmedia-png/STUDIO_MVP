param(
  [string]$ScriptText = "mi prueba live",
  [int]$W = 540,
  [int]$H = 960,
  [int]$FPS = 15,
  [ValidateSet("crop","contain")]
  [string]$Fit = "crop"
)

$ErrorActionPreference="Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = $RepoRoot
. "$PSScriptRoot\resolve_python.ps1"
$py = Resolve-PythonExe -RepoRoot $RepoRoot
chcp 65001 | Out-Null

$V03Config = ".\config\studio_v03_edge_voice_smoke.json"
if (-not (Test-Path $V03Config)) {
@'
{
  "work_dir": "_v03_edge_voice_smoke/artifacts",
  "workspace": "_v03_edge_voice_smoke/workspace",
  "voice": { "provider": "edge_voice", "config": {} },
  "image": { "provider": "demo_image", "config": {} },
  "text":  { "provider": "openai_text", "config": {} }
}
'@ | Set-Content -Encoding UTF8 $V03Config
}

$prov = ".\config\providers.json"
$bak  = "$prov.bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item $prov $bak -Force

try {
  $j = Get-Content $prov -Raw -Encoding UTF8 | ConvertFrom-Json
  $j.text.mode  = "REPLAY"
  $j.image.mode = "DRY"
  $j.voice.mode = "DRY"
  ($j | ConvertTo-Json -Depth 50) | Set-Content -Encoding UTF8 $prov

  $out = & $py .\tools\release_pack_v03.py --v03-config $V03Config --script $ScriptText --overwrite 2>&1
  $out | Out-Host

  $packLine = ($out | Select-String -Pattern "^PACK_DIR:\s*" | Select-Object -Last 1).Line
  if (-not $packLine) { throw "No encontré PACK_DIR en output" }
  $packDir = ($packLine -replace "^PACK_DIR:\s*","").Trim()
  Write-Host "PACK_DIR => $packDir" -ForegroundColor Green

  & $py .\tools\render_pack_v03.py --pack-dir "$packDir" --w $W --h $H --fps $FPS --fit $Fit --keep-tmp
}
finally {
  Copy-Item $bak $prov -Force
  Write-Host "OK: providers.json revertido." -ForegroundColor Cyan
}
