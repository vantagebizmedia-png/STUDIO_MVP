[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
param(
  [ValidateSet("safe","runs","all","vcs")]
  [string] $Mode = "safe",

  # Root del repo STUDIO_MVP (auto por defecto)
  [string] $StudioRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,

  # Root del workspace externo
  [string] $WorkspaceRoot = (Join-Path $env:USERPROFILE "Documents\STUDIO_WORKSPACE"),

  # Mantener últimos N runs (para Mode=runs/all)
  [int] $KeepLastRuns = 3,

  # Si está ON, limpia render\ de los runs que se quedan (no toca content_pack)
  [switch] $WipeRender,

  # VCS repo opcional
  [string] $VcsRoot = (Join-Path $env:USERPROFILE "Documents\VCS_STUDIO"),

  # Si está ON y Mode=all, también limpia VCS
  [switch] $CleanVcs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FolderBytes([string]$p) {
  if (!(Test-Path $p)) { return 0 }
  try { return (Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
  catch { return 0 }
}

function Show-Size([string]$label, [string]$path) {
  if (Test-Path $path) {
    $b = Get-FolderBytes $path
    "{0,-28} {1,14:N0} bytes  {2}" -f $label, $b, $path
  } else {
    "{0,-28} {1}" -f $label, "(no existe)  $path"
  }
}

function Remove-FolderContents([string]$path) {
  if (!(Test-Path $path)) { return }
  if ($PSCmdlet.ShouldProcess($path, "Remove-Item (contents)")) {
    Remove-Item (Join-Path $path "*") -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Remove-Directory([string]$path) {
  if (!(Test-Path $path)) { return }
  if ($PSCmdlet.ShouldProcess($path, "Remove-Item (directory)")) {
    Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Clean-StudioSafe([string]$root) {
  $out = Join-Path $root "workspace\output"
  $rel = Join-Path $root "workspace\release"

  Write-Host "== PREVIEW (STUDIO safe) ==" -ForegroundColor Cyan
  Show-Size "workspace\output"  $out
  Show-Size "workspace\release" $rel

  Write-Host "`n== CLEAN (STUDIO safe) ==" -ForegroundColor Yellow
  Remove-FolderContents $out
  Remove-FolderContents $rel

  Write-Host "OK: safe cleanup completado (output/release)." -ForegroundColor Green
}

function Clean-Runs([string]$wsRoot, [int]$keep, [switch]$wipeRenderOnly) {
  $runsDir = Join-Path $wsRoot "runs"
  if (!(Test-Path $runsDir)) { throw "No existe runsDir: $runsDir" }

  $runs = Get-ChildItem $runsDir -Directory | Sort-Object LastWriteTime -Descending
  Write-Host "Total runs: $($runs.Count). Manteniendo: $keep" -ForegroundColor Cyan

  if ($wipeRenderOnly) {
    Write-Host "== WIPE render/ (solo en runs que quedan) ==" -ForegroundColor Yellow
    $runs | Select-Object -First $keep | ForEach-Object {
      $render = Join-Path $_.FullName "render"
      if (Test-Path $render) {
        Remove-FolderContents $render
        Write-Host "OK: limpiado render -> $render" -ForegroundColor Green
      }
    }
    return
  }

  $toDelete = @()
  if ($runs.Count -gt $keep) { $toDelete = $runs | Select-Object -Skip $keep }

  if ($toDelete.Count -eq 0) {
    Write-Host "Nada que borrar (ya tienes <= $keep runs)." -ForegroundColor Green
    return
  }

  Write-Host "== BORRANDO runs viejos (ESTO BORRA content_pack de esos runs) ==" -ForegroundColor Red
  $toDelete | ForEach-Object { Write-Host " - $($_.FullName)" -ForegroundColor DarkGray }

  $toDelete | ForEach-Object { Remove-Directory $_.FullName }

  Write-Host "OK: runs viejos eliminados." -ForegroundColor Green
}

function Clean-Vcs([string]$root) {
  if (!(Test-Path $root)) {
    Write-Host "INFO: VcsRoot no existe, skip -> $root" -ForegroundColor DarkGray
    return
  }

  Write-Host "== PREVIEW (VCS cleanup) ==" -ForegroundColor Cyan
  Show-Size "VCS root" $root

  $dirs = @("__pycache__", ".pytest_cache", ".ruff_cache", ".mypy_cache", ".cache", "cache", "tmp", "temp", "logs", "log")

  Write-Host "`n== CLEAN (VCS caches/logs/tmp) ==" -ForegroundColor Yellow
  foreach ($d in $dirs) {
    Get-ChildItem $root -Recurse -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -ieq $d } |
      ForEach-Object { Remove-Directory $_.FullName }
  }

  Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '\.(log|tmp|bak)$' -or $_.Name -match '^last_.*\.log$' } |
    ForEach-Object {
      if ($PSCmdlet.ShouldProcess($_.FullName, "Remove-Item (file)")) {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
      }
    }

  Write-Host "OK: VCS cleanup completado." -ForegroundColor Green
}

Write-Host "CLEANUP Mode=$Mode" -ForegroundColor Cyan
Write-Host "StudioRoot   : $StudioRoot" -ForegroundColor DarkGray
Write-Host "WorkspaceRoot: $WorkspaceRoot" -ForegroundColor DarkGray
Write-Host "KeepLastRuns : $KeepLastRuns" -ForegroundColor DarkGray
Write-Host "WipeRender   : $WipeRender" -ForegroundColor DarkGray
Write-Host "VcsRoot      : $VcsRoot" -ForegroundColor DarkGray
Write-Host "CleanVcs     : $CleanVcs" -ForegroundColor DarkGray
Write-Host ""

switch ($Mode) {
  "safe" { Clean-StudioSafe $StudioRoot }
  "runs" {
    if ($WipeRender) { Clean-Runs -wsRoot $WorkspaceRoot -keep $KeepLastRuns -wipeRenderOnly:$true }
    else { Clean-Runs -wsRoot $WorkspaceRoot -keep $KeepLastRuns }
  }
  "all" {
    Clean-StudioSafe $StudioRoot
    if ($WipeRender) { Clean-Runs -wsRoot $WorkspaceRoot -keep $KeepLastRuns -wipeRenderOnly:$true }
    else { Clean-Runs -wsRoot $WorkspaceRoot -keep $KeepLastRuns }
    if ($CleanVcs) { Clean-Vcs $VcsRoot }
  }
  "vcs" { Clean-Vcs $VcsRoot }
}

Write-Host "`nLISTO." -ForegroundColor Green
