param(
  [switch]$Check,
  [switch]$Run,

  [string]$Script = "hola",
  [string]$OutRoot = "_v03_free_run",

  [string]$EdgeVoice = "en-US-JennyNeural",

  [string]$HfModel = "black-forest-labs/FLUX.1-schnell",
  [string]$HfTokenEnv = "HF_TOKEN",
  [string]$HfProvider = "hf-inference"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = $RepoRoot
. "$PSScriptRoot\resolve_python.ps1"
$py = Resolve-PythonExe -RepoRoot $RepoRoot

if (!(Test-Path -LiteralPath ".\run.py")) { throw "Ejecuta desde la raíz (run.py)" }

$pyArgs = @("-m","cli.free_demo")

if ($Run) { $pyArgs += @("--run") } else { $pyArgs += @("--check") }

$pyArgs += @(
  "--script", $Script,
  "--out-root", $OutRoot,
  "--edge-voice", $EdgeVoice,
  "--hf-model", $HfModel,
  "--hf-token-env", $HfTokenEnv,
  "--hf-provider", $HfProvider
)

& $py @pyArgs
exit $LASTEXITCODE
