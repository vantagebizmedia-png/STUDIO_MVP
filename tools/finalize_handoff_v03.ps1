param(
    [Parameter(Mandatory = $true)]
    [string]$PackDir,
    [switch]$AutoMusic,
    [string]$MusicDir = ".\music"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = $RepoRoot
. "$PSScriptRoot\resolve_python.ps1"
$py = Resolve-PythonExe -RepoRoot $RepoRoot

if (!(Test-Path -LiteralPath ".\tools\finalize_handoff_v03.py")) {
    throw "Falta tools/finalize_handoff_v03.py"
}

$argsPy = @("tools/finalize_handoff_v03.py", "--pack-dir", $PackDir, "--music-dir", $MusicDir)
if ($AutoMusic) { $argsPy += "--auto-music" }

& $py @argsPy
exit $LASTEXITCODE
