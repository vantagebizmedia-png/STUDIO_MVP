param(
  [Parameter(Mandatory=$true)][string]$TargetPath,
  [Parameter(Mandatory=$true)][string]$Pattern,
  [Parameter(Mandatory=$true)][string]$Replacement
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

if (-not (Test-Path -LiteralPath $TargetPath)) { throw "No existe TargetPath: $TargetPath" }

$raw = Get-Content -LiteralPath $TargetPath -Raw -Encoding UTF8

$rx = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
$m = $rx.Match($raw)
if (-not $m.Success) { throw "Pattern no matcheó en: $TargetPath" }

# Reemplazo literal (NO interpreta $1, $2, etc.)
$eval = New-Object System.Text.RegularExpressions.MatchEvaluator([Func[System.Text.RegularExpressions.Match,string]]{
  param($match)
  return $Replacement
})

$raw2 = $rx.Replace($raw, $eval, 1)

# Guardar UTF-8 sin BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path $TargetPath).Path, $raw2, $utf8NoBom)

Write-Host "OK patched -> $TargetPath" -ForegroundColor Green
