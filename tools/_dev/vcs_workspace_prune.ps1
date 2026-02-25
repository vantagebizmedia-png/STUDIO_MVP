[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()]
  [string] $VcsRoot,

  # También vacía workspace\render si existe
  [switch] $WipeRender,

  # Si lo pones, intenta BORRAR la carpeta workspace completa,
  # pero SOLO si dentro hay únicamente output/release/(render opcional).
  [switch] $RemoveWorkspaceFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FolderBytes([string]$p) {
  if (!(Test-Path $p)) { return 0L }
  try {
    $sum = (Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($null -eq $sum) { return 0L }
    return [int64]$sum
  } catch { return 0L }
}

function Show-Size([string]$label, [string]$path) {
  if (Test-Path $path) {
    $b = Get-FolderBytes $path
    $mb = [math]::Round(($b/1MB), 2)
    "{0,-24} {1,12:N0} bytes  ({2,8} MB)  {3}" -f $label, $b, $mb, $path
  } else {
    "{0,-24} (no existe)  {1}" -f $label, $path
  }
}

function Wipe-Folder([string]$p) {
  if (!(Test-Path $p)) { return }
  if ($PSCmdlet.ShouldProcess($p, "Remove-Item (contents)")) {
    Remove-Item (Join-Path $p "*") -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# ---- Validación de root ----
if (!(Test-Path $VcsRoot -PathType Container)) { throw "No existe VcsRoot: $VcsRoot" }
$VcsRoot = (Resolve-Path $VcsRoot).Path

$ws = Join-Path $VcsRoot "workspace"
$out = Join-Path $ws "output"
$rel = Join-Path $ws "release"
$ren = Join-Path $ws "render"

Write-Host "VCS ROOT : $VcsRoot" -ForegroundColor Cyan
Write-Host "workspace : $ws" -ForegroundColor DarkGray
Write-Host ""

Write-Host "== PREVIEW SIZES (workspace dentro de VCS) ==" -ForegroundColor Cyan
Show-Size "workspace"        $ws
Show-Size "workspace\output" $out
Show-Size "workspace\release"$rel
if ($WipeRender) { Show-Size "workspace\render" $ren }

Write-Host ""

# ---- Modo: borrar workspace completo (con guard rail) ----
if ($RemoveWorkspaceFolder) {
  if (!(Test-Path $ws)) {
    Write-Host "INFO: no existe workspace, nada que borrar." -ForegroundColor DarkGray
    exit 0
  }

  $allowed = @("output","release")
  if ($WipeRender) { $allowed += "render" }

  $others = @(Get-ChildItem $ws -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $allowed })
  if ($others.Count -gt 0) {
    Write-Host "STOP: workspace tiene items NO esperados; NO voy a borrar workspace completo." -ForegroundColor Red
    $others | ForEach-Object { Write-Host (" - {0}" -f $_.FullName) -ForegroundColor Yellow }
    Write-Host "Acción segura: corre sin -RemoveWorkspaceFolder (solo vacía output/release)." -ForegroundColor Yellow
    exit 1
  }

  Write-Host "== REMOVE workspace COMPLETO (permitido por guard rail) ==" -ForegroundColor Yellow
  if ($PSCmdlet.ShouldProcess($ws, "Remove-Item (workspace directory)")) {
    Remove-Item $ws -Recurse -Force -ErrorAction SilentlyContinue
  }

  Write-Host "OK: workspace eliminado completamente." -ForegroundColor Green
  exit 0
}

# ---- Modo seguro: vaciar output/release (y render opcional) ----
Write-Host "== CLEAN SAFE: vaciando output/release (y render opcional) ==" -ForegroundColor Yellow
Wipe-Folder $out
Wipe-Folder $rel
if ($WipeRender) { Wipe-Folder $ren }

# Re-crea estructura vacía (por claridad para terceros)
New-Item -ItemType Directory -Force $out | Out-Null
New-Item -ItemType Directory -Force $rel | Out-Null
if ($WipeRender) { New-Item -ItemType Directory -Force $ren | Out-Null }

Write-Host "OK: workspace en VCS quedó vacío (solo estructura)." -ForegroundColor Green