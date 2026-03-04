Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-PythonExe {
  param([string]$RepoRoot = "")

  if (-not $RepoRoot -or $RepoRoot.Trim().Length -eq 0) {
    $RepoRoot = (Get-Location).Path
  }

  # 1) Override explícito
  if ($env:STUDIO_PYTHON -and (Test-Path -LiteralPath $env:STUDIO_PYTHON)) {
    return (Resolve-Path -LiteralPath $env:STUDIO_PYTHON).Path
  }

  $candidates = @()

  # 2) venv local
  $candidates += (Join-Path $RepoRoot ".venv\Scripts\python.exe")

  # 3) Wrapper estable (si existe)
  $candidates += "C:\Users\vanta\AppData\Local\Python\bin\python.exe"

  # 4) Python launcher
  $candidates += "py.exe"

  # 5) PATH
  $candidates += "python.exe"
  $candidates += "python"

  foreach ($c in $candidates) {
    try {
      $exe = $null

      if ($c -match '^(py\.exe|python(\.exe)?)$') {
        $cmd = Get-Command $c -ErrorAction Stop
        $exe = $cmd.Source
      } else {
        if (!(Test-Path -LiteralPath $c)) { continue }
        $exe = (Resolve-Path -LiteralPath $c).Path
      }

      # Smoke check
      if ([IO.Path]::GetFileName($exe).ToLower() -eq "py.exe") {
        & $exe -3 -c "import sys" *> $null
        if ($LASTEXITCODE -eq 0) { return $exe }
      } else {
        & $exe -c "import sys" *> $null
        if ($LASTEXITCODE -eq 0) { return $exe }
      }
    } catch { }
  }

  throw "No se pudo resolver un Python funcional. Usa `$env:STUDIO_PYTHON, o instala Python/py launcher."
}
