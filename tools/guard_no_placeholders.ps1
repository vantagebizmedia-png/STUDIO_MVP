Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$badPatterns = @(
  "PEGA AQU",
  "contenido del script",
  "TODO:",
  "REPLACE ME",
  "<PEGA",
  "<<<",
  ">>>"
)

# revisa solo scripts de tools (puedes ampliar si quieres)
$files = Get-ChildItem -Recurse -File -Path ".\tools" -Include *.ps1

$hits = @()

foreach ($f in $files) {
  $txt = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop
  foreach ($p in $badPatterns) {
    if ($txt -match [regex]::Escape($p)) {
      $hits += [pscustomobject]@{ File=$f.FullName; Pattern=$p }
    }
  }
}

if ($hits.Count -gt 0) {
  Write-Host "ERROR: se detectaron placeholders/basura en scripts:" -ForegroundColor Red
  $hits | Sort-Object File,Pattern | Format-Table -AutoSize
  throw "Guard failed: placeholders detected"
}

Write-Host "OK: no placeholders detected" -ForegroundColor Green
