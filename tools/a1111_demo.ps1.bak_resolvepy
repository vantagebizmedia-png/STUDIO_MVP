param(
  [switch]$Check,
  [switch]$Run,

  [string]$Script = "hola",
  [string]$OutRoot = "_v03_a1111_run",
  [string]$BaseUrl = "http://127.0.0.1:7860",

  [int]$W = 512,
  [int]$H = 512,
  [int]$Steps = 20,
  [double]$Cfg = 7.0,
  [string]$Sampler = "DPM++ 2M Karras",
  [int]$Seed = -1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath ".\run.py")) { throw "Ejecuta desde la raíz (run.py)" }

$py = @("-m","cli.a1111_demo")
if ($Run) { $py += @("--run") } else { $py += @("--check") }

$py += @(
  "--script",$Script,
  "--out-root",$OutRoot,
  "--base-url",$BaseUrl,
  "--w",$W,
  "--h",$H,
  "--steps",$Steps,
  "--cfg",$Cfg,
  "--sampler",$Sampler,
  "--seed",$Seed
)

& python @py
exit $LASTEXITCODE