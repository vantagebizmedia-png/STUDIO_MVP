Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

# Patrones que NO deben existir en scripts reales
$badPatterns = @(
  "PEGA AQU",
  "contenido del script",
  "TODO:",
  "REPLACE ME",
  "<PEGA",
  "<<<",
  ">>>"
)

# Excluir paths específicos (relativos al repo o nombres de archivo)
$excludeFileNames = @(
  "guard_no_placeholders.ps1"  # se auto-contiene los patrones; no debe auto-fallar
)

$excludePathFragments = @(
  "\.tmp\",
  "\_archive\",
  "\.git\"
)

# Revisa scripts dentro de tools/
$files = Get-ChildItem -Recurse -File -Path ".\tools" -Include *.ps1

$hits = @()

foreach ($f in $files) {

  if ($excludeFileNames -contains $f.Name) { continue }

  $full = $f.FullName

  $skip = $false
  foreach ($frag in $excludePathFragments) {
    if ($full -like "*$frag*") { $skip = $true; break }
  }
  if ($skip) { continue }

  $txt = Get-Content -LiteralPath $full -Raw -ErrorAction Stop

  foreach ($p in $badPatterns) {
    if ($txt -match [regex]::Escape($p)) {
      $hits += [pscustomobject]@{ File=$full; Pattern=$p }
    }
  }
}

if ($hits.Count -gt 0) {
  Write-Host "ERROR: se detectaron placeholders/basura en scripts:" -ForegroundColor Red
  $hits | Sort-Object File,Pattern | Format-Table -AutoSize
  throw "Guard failed: placeholders detected"
}

Write-Host "OK: no placeholders detected" -ForegroundColor Green
