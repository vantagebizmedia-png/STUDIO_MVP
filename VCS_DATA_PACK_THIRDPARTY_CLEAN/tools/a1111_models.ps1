param(
  [string]$BaseUrl = "http://127.0.0.1:7860",
  [int]$TimeoutSec = 10
)
$ErrorActionPreference="Stop"
$u = $BaseUrl.TrimEnd("/")
try {
  $models = Invoke-RestMethod -Uri "$u/sdapi/v1/sd-models" -TimeoutSec $TimeoutSec
  $models | Select-Object title, model_name, hash, filename | Format-Table -AutoSize
} catch {
  Write-Host "FAIL: no puedo listar modelos. ¿A1111 con --api? Error: $($_.Exception.Message)"
  exit 1
}
