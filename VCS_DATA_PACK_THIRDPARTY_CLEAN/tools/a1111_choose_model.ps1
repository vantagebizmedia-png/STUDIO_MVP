param(
  [string]$BaseUrl = "http://127.0.0.1:7860",
  [int]$TimeoutSec = 10
)
$ErrorActionPreference="Stop"
$u = $BaseUrl.TrimEnd("/")

try {
  $models = Invoke-RestMethod -Uri "$u/sdapi/v1/sd-models" -TimeoutSec $TimeoutSec
} catch {
  Write-Host "FAIL: no puedo leer sd-models. A1111 con --api? Error: $($_.Exception.Message)"
  exit 1
}

if (-not $models -or $models.Count -eq 0) {
  Write-Host "No hay modelos disponibles."
  exit 1
}

for ($i=0; $i -lt $models.Count; $i++) {
  "{0,3}) {1}" -f ($i+1), $models[$i].title
}

$sel = Read-Host "Elige numero de modelo (enter=cancelar, 0=cancelar)"
if ([string]::IsNullOrWhiteSpace($sel) -or $sel -eq "0") {
  Write-Host "Cancelado."
  exit 0
}

$n = 0
if (-not [int]::TryParse($sel, [ref]$n)) {
  Write-Host "Entrada invalida: $sel (cancelando)"
  exit 0
}
if ($n -lt 1 -or $n -gt $models.Count) {
  Write-Host "Fuera de rango: $n (1..$($models.Count)) (cancelando)"
  exit 0
}

$title = $models[$n-1].title
Write-Host "Seleccionado:" $title

$body = @{ sd_model_checkpoint = $title } | ConvertTo-Json
try {
  Invoke-RestMethod -Method Post -Uri "$u/sdapi/v1/options" -ContentType "application/json" -Body $body -TimeoutSec 30 | Out-Null
  Start-Sleep -Seconds 1
  $opts = Invoke-RestMethod -Uri "$u/sdapi/v1/options" -TimeoutSec 10
  Write-Host "Modelo actual:" $opts.sd_model_checkpoint
} catch {
  Write-Host "FAIL: no pude setear modelo. Error: $($_.Exception.Message)"
  exit 1
}
