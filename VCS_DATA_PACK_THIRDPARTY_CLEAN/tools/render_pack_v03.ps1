param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = $RepoRoot
. "$PSScriptRoot\resolve_python.ps1"
$py = Resolve-PythonExe -RepoRoot $RepoRoot

# Normaliza: si el primer arg NO empieza con '-', lo tratamos como pack_dir
if ($Args.Count -gt 0 -and -not ($Args[0] -like "-*")) {
  $pack = $Args[0]
  $rest = @()
  if ($Args.Count -gt 1) { $rest = $Args[1..($Args.Count-1)] }
  $Args = @("--pack-dir", $pack) + $rest
}

Write-Host "== render_pack_v03.ps1 ==" -ForegroundColor Cyan
Write-Host ("python: {0}" -f $py)
Write-Host ("args  : {0}" -f ($Args -join " "))

& $py -u "tools/render_pack_v03.py" @Args
exit $LASTEXITCODE



