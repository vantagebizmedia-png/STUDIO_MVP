param(
  [string]$RepoRoot = ".",
  [string]$OutDir = ".\VCS_DATA_PACK_THIRDPARTY_CLEAN"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg) { throw "THIRDPARTY FAIL: $msg" }

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$out  = (Resolve-Path -LiteralPath (New-Item -ItemType Directory -Force -Path $OutDir)).Path

Write-Host "== VCS THIRDPARTY PACK v03 =="
Write-Host "Repo : $repo"
Write-Host "Out  : $out"

$staging = Join-Path $out "_staging"
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null

$include = @(
  "app","cli","studio","tools","config","templates","tests","models",
  "README.md","README_RELEASE.md","LICENSE","pytest.ini","requirements.lock.txt",
  "run.py","studio.py","render.ps1","studio.ps1",
  "CHECKLIST_NEXT_V03.txt","STUDIO_CORE_STABLE.md","CONTRATO_V1.md","CONTRATO_V2.md"
)

$excludeDirs = @(".git",".venv","STUDIO_WORKSPACE","runs","_logs","__pycache__",".cache","_zip_check","_scene_provider_routing_smoke")
$excludeFiles = @(
  "*.mp4","*.wav","*.png","*.srt","*.zip",
  "*.log","*_last.log","*_debug_*.log",
  "*.bak","*.bk","*.bk*","*.bak_*","*.bk_*",
  "SHA256SUMS.txt","HANDOFF_READY.txt",
  ".env","*.key","*.pem"
)

foreach ($item in $include) {
  $src = Join-Path $repo $item
  if (-not (Test-Path -LiteralPath $src)) { continue }

  $dst = Join-Path $staging $item
  $parent = Split-Path -Parent $dst
  if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }

  if ((Get-Item -LiteralPath $src).PSIsContainer) {
    $xd = @(); foreach ($d in $excludeDirs) { $xd += @("/XD", (Join-Path $src $d)) }
    $xf = @(); foreach ($f in $excludeFiles) { $xf += @("/XF", $f) }

    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    & robocopy $src $dst /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 @xd @xf | Out-Null
  } else {
    Copy-Item -LiteralPath $src -Destination $dst -Force
  }
}

$kill = @("projects","project","topics","temas","themes")
foreach ($k in $kill) {
  $p = Join-Path $staging $k
  if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
}

$packInfo = Join-Path $staging "PACK_INFO.json"
if (-not (Test-Path -LiteralPath $packInfo)) {
  $obj = [ordered]@{
    name = "VCS_DATA_PACK_THIRDPARTY_CLEAN"
    version = "v03"
    clean = $true
    note = "Clean thirdparty pack: no projects/topics/themes. Structure only."
    created_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  }
  ($obj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $packInfo -Encoding UTF8
}

Get-ChildItem -LiteralPath $out -Force | Where-Object { $_.Name -ne "_staging" } | ForEach-Object {
  Remove-Item -LiteralPath $_.FullName -Recurse -Force
}

Get-ChildItem -LiteralPath $staging -Force | ForEach-Object {
  Move-Item -LiteralPath $_.FullName -Destination $out -Force
}
Remove-Item -LiteralPath $staging -Recurse -Force

Write-Host "OK thirdparty pack generado en: $out"
Write-Host "Contenido top-level:"
Get-ChildItem -LiteralPath $out | Sort-Object Name | Select-Object Name,Mode,Length | Format-Table -AutoSize
