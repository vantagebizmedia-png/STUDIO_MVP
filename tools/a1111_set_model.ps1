param(
  [Parameter(Mandatory=$true)][string]$Checkpoint,
  [string]$BaseUrl = "http://127.0.0.1:7860",
  [int]$TimeoutSec = 30
)
$ErrorActionPreference="Stop"
$u = $BaseUrl.TrimEnd("/")

Write-Host "BaseUrl:" $u
Write-Host "Setting checkpoint:" $Checkpoint

$body = @{ sd_model_checkpoint = $Checkpoint } | ConvertTo-Json

try {
  Invoke-RestMethod -Method Post -Uri "$u/sdapi/v1/options" -ContentType "application/json" -Body $body -TimeoutSec $TimeoutSec | Out-Null
  Start-Sleep -Seconds 1
  $opts = Invoke-RestMethod -Uri "$u/sdapi/v1/options" -TimeoutSec $TimeoutSec
  Write-Host "OK: modelo actual:" $opts.sd_model_checkpoint
} catch {
  Write-Host "FAIL: no pude setear modelo. Error: $($_.Exception.Message)"
  exit 1
}
