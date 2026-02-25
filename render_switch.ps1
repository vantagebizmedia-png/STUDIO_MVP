param(
  [Parameter(Position=0, Mandatory=$true)]
  [string]$Prompt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$useV03 = ($env:STUDIO_USE_V03 -eq "1")

if ($useV03) {
  Write-Host "STUDIO_USE_V03=1 -> usando render_v03.ps1 (legacy + DRY)" -ForegroundColor Cyan
  & powershell -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File .\render_v03.ps1 $Prompt
  exit $LASTEXITCODE
}

Write-Host "STUDIO_USE_V03!=1 -> usando render.ps1 (actual)" -ForegroundColor Yellow
& powershell -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File .\render.ps1 $Prompt
exit $LASTEXITCODE