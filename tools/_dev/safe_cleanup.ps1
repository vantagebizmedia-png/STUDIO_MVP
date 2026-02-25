param(
  [string]$TrashDir = "._trash",
  [switch]$RunNow
)

$ErrorActionPreference = "Stop"

function Normalize([string]$p) {
  return (Resolve-Path -LiteralPath $p).Path.TrimEnd('\')
}

# Usamos "_trash" en la raíz del repo (tu caso real)
$trash = ".\_trash"

if ($RunNow) {
  if (Test-Path $trash) {
    Write-Host "Borrando $trash ..."
    Remove-Item -LiteralPath $trash -Recurse -Force
  }
  New-Item -ItemType Directory -Force $trash | Out-Null
  Write-Host "OK: _trash recreado limpio"
} else {
  Write-Host "OK: script creado. Para ejecutarlo:"
  Write-Host "  powershell -ExecutionPolicy Bypass -File .\tools\safe_cleanup.ps1 -RunNow"
}

# Nota: NO copiamos nada dentro de _trash desde aquí.
# Regla operativa: nunca copiar el repo completo a _trash. Solo mover archivos sueltos.
