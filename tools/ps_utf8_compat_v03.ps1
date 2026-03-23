function Initialize-PowerShellUtf8CompatV03 {
  [CmdletBinding()]
  param()

  $utf8NoBom = $null
  try {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  }
  catch {
    $utf8NoBom = [System.Text.Encoding]::UTF8
  }

  try { [Console]::InputEncoding  = $utf8NoBom } catch { }
  try { [Console]::OutputEncoding = $utf8NoBom } catch { }
  try { $global:OutputEncoding    = $utf8NoBom } catch { }

  $isWindowsHost = $false
  try {
    $isWindowsHost = [bool]$IsWindows
  }
  catch {
    $isWindowsHost = ($env:OS -eq "Windows_NT")
  }

  if (-not $isWindowsHost) {
    return
  }

  $chcpCmd = $null
  try {
    $chcpCmd = Get-Command chcp -ErrorAction SilentlyContinue
  }
  catch {
    $chcpCmd = $null
  }

  if ($null -eq $chcpCmd) {
    return
  }

  try {
    & $chcpCmd.Source 65001 | Out-Null
  }
  catch {
  }
}

Initialize-PowerShellUtf8CompatV03
