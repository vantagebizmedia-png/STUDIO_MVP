param(
  # Si lo dejas vacío, intenta autodetectar en el repo
  [string] $SourceDir = "",

  # Nombre del folder destino
  [string] $OutName = "VCS_DATA_PACK_THIRDPARTY",

  # Si lo pones, crea zip en workspace\release
  [switch] $Zip
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$Repo = Split-Path $PSScriptRoot -Parent

function Ensure-Dir([string]$p) {
  if (!(Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function Touch([string]$p) {
  if (!(Test-Path $p)) { [System.IO.File]::WriteAllText($p, "", [Text.UTF8Encoding]::new($false)) }
}

function Find-CandidateSource([string]$root) {
  $nameHits = Get-ChildItem -Path $root -Directory -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Name -match '(?i)^(vcs(_|-)?data(_|-)?pack|vcs(_|-)?pack|vcs(_|-)?data|data(_|-)?pack|vcs)$'
    } |
    Select-Object -First 1

  if ($nameHits) { return $nameHits.FullName }

  # Fallback: buscar archivos típicos (si existen)
  $fileHits = Get-ChildItem -Path $root -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Name -match '(?i)^(vcs_.*\.json|registry\.json|master_block\.txt|vcs_master.*|vcs_data_pack.*)$'
    } |
    Select-Object -First 1

  if ($fileHits) { return (Split-Path $fileHits.FullName -Parent) }

  return ""
}

# ----------------------------------------------------
# 1) Resolver SourceDir (auto si no lo das)
# ----------------------------------------------------
if (-not $SourceDir) {
  $default = Join-Path $Repo "VCS_DATA_PACK"
  if (Test-Path $default -PathType Container) {
    Write-Host "INFO: SourceDir no provisto. Usando default: $default" -ForegroundColor Yellow
    $SourceDir = $default
  } else {
    Write-Host "INFO: SourceDir no provisto y no existe $default. Se creará skeleton desde cero. (tip: pasa -SourceDir ...)" -ForegroundColor Yellow
    $SourceDir = ""
  }
}



if ($SourceDir) {
  if (!(Test-Path $SourceDir -PathType Container)) {
    throw "SourceDir no existe o no es directorio: $SourceDir"
  }
  $SourceDir = (Resolve-Path $SourceDir).Path
  Write-Host "OK: SourceDir = $SourceDir" -ForegroundColor Green
} else {
  Write-Host "WARN: No encontré ningún VCS_DATA_PACK existente. Se creará skeleton desde cero." -ForegroundColor Yellow
}

# ----------------------------------------------------
# 2) Crear destino
# ----------------------------------------------------
$outDir = Join-Path $Repo $OutName
if (Test-Path $outDir) {
  $ts = Get-Date -Format "yyyyMMdd_HHmmss"
  $bak = "$outDir.bak_$ts"
  Rename-Item -Path $outDir -NewName (Split-Path $bak -Leaf)
  Write-Host "BACKUP: destino previo renombrado -> $bak" -ForegroundColor DarkGray
}

Ensure-Dir $outDir

# ----------------------------------------------------
# 3) Copiar (si hay source) excluyendo proyectos/temas + basura
# ----------------------------------------------------
$excl = @("projects","project","themes","theme",".git","__pycache__","cache","tmp","temp","node_modules","dist","build","workspace")
if ($SourceDir) {
  Write-Host ""
  Write-Host "Copiando source -> $OutName (excluyendo: $($excl -join ', '))" -ForegroundColor Cyan

  # Robocopy es robusto y rápido. /MIR para espejo, /XD para excluir dirs.
  $xd = @()
  foreach ($d in $excl) { $xd += @("/XD",$d) }

  $cmd = @("robocopy", $SourceDir, $outDir, "/MIR", "/R:1", "/W:1") + $xd
  Write-Host ("RUN: " + ($cmd -join " ")) -ForegroundColor DarkGray

  $p = Start-Process -FilePath $cmd[0] -ArgumentList ($cmd[1..($cmd.Count-1)]) -NoNewWindow -PassThru -Wait
  # robocopy retorna códigos especiales; 0-7 = OK (incluye "copió", "extra", etc.)
  if ($p.ExitCode -gt 7) {
    throw "robocopy falló con ExitCode=$($p.ExitCode)"
  }
}

# ----------------------------------------------------
# 4) Forzar estructura third-party rígida (vacía projects/themes)
# ----------------------------------------------------
$mustDirs = @(
  "schemas",
  "config",
  "templates",
  "rules",
  "logs",
  "data",
  "data\projects",
  "data\themes"
)

foreach ($d in $mustDirs) {
  Ensure-Dir (Join-Path $outDir $d)
}

# Vaciar projects/themes SI existían del source (hard reset)
$proj = Join-Path $outDir "data\projects"
$them = Join-Path $outDir "data\themes"

Get-ChildItem $proj -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem $them -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Ensure-Dir $proj
Ensure-Dir $them

# Gitkeep
Touch (Join-Path $proj ".gitkeep")
Touch (Join-Path $them ".gitkeep")
Touch (Join-Path (Join-Path $outDir "logs") ".gitkeep")

# ----------------------------------------------------
# 5) README_THIRDPARTY.md + PACK_INFO.json
# ----------------------------------------------------
$readme = Join-Path $outDir "README_THIRDPARTY.md"
$info   = Join-Path $outDir "PACK_INFO.json"

$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$readmeTxt = @"
# VCS_DATA_PACK_THIRDPARTY

Este paquete está diseñado para **terceros**:
- Estructura **rígida** y **determinista**
- **Sin proyectos/temas** (vacíos intencionalmente)
- Cualquier cambio debe ocurrir mediante **parches explícitos** (no auto-aprendizaje)

Generado: $stamp
Source (si existió): $SourceDir

Carpetas clave:
- data/projects  (VACÍO intencionalmente)
- data/themes    (VACÍO intencionalmente)
- logs/          (vacío; para auditoría manual)
"@

[System.IO.File]::WriteAllText($readme, $readmeTxt, [Text.UTF8Encoding]::new($false))

$infoObj = @{
  schema = "VCS_DATA_PACK_THIRDPARTY_V1"
  generated_at = $stamp
  source_dir = $SourceDir
  notes = @(
    "projects/themes vacíos intencionalmente",
    "no auto-mutar; solo parches explícitos",
    "estructura rígida para third-party"
  )
}
$json = ($infoObj | ConvertTo-Json -Depth 20)
[System.IO.File]::WriteAllText($info, $json + "`r`n", [Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "OK: Third-party pack listo -> $outDir" -ForegroundColor Green

# ----------------------------------------------------
# 6) ZIP opcional
# ----------------------------------------------------
if ($Zip) {
  $rel = Join-Path $Repo "workspace\release"
  Ensure-Dir $rel
  $zipPath = Join-Path $rel ("{0}_{1}.zip" -f $OutName, (Get-Date -Format "yyyyMMdd_HHmmss"))
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Compress-Archive -Path (Join-Path $outDir "*") -DestinationPath $zipPath -Force
  Write-Host "OK: ZIP -> $zipPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "Contenido:" -ForegroundColor Cyan
Get-ChildItem $outDir -Force | Sort-Object Name | Format-Table Name,Mode,LastWriteTime -AutoSize