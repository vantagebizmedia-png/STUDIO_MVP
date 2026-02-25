param(
  [string]$BaseUrl = "http://127.0.0.1:7860",
  [int]$TimeoutSec = 5
)
$ErrorActionPreference="Stop"
$u = $BaseUrl.TrimEnd("/")
Write-Host "A1111 BaseUrl: $u"
try {
  $resp = Invoke-RestMethod -Uri "$u/sdapi/v1/options" -TimeoutSec $TimeoutSec
  if ($resp.sd_model_checkpoint) {
    Write-Host "OK: A1111 responde. Modelo:" $resp.sd_model_checkpoint
  } else {
    Write-Host "OK: A1111 responde. (sin sd_model_checkpoint en options)"
  }
} catch {
  Write-Host "FAIL: no puedo conectar a A1111. ¿Está corriendo con --api? Error: $($_.Exception.Message)"
  exit 1
}
