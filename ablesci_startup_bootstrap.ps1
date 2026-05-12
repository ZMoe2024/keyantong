Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$launchScript = Join-Path $scriptDir "launch_logged_in_chrome_with_debug.ps1"
$signScript = Join-Path $scriptDir "ablesci_sign.ps1"
$debugPort = 8572

if (!(Test-Path -LiteralPath $launchScript)) {
  Write-Output "ERROR launch script not found: $launchScript"
  exit 1
}

if (!(Test-Path -LiteralPath $signScript)) {
  Write-Output "ERROR sign script not found: $signScript"
  exit 1
}

$launchOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launchScript -Port $debugPort 2>&1
$launchExit = $LASTEXITCODE
$launchText = (($launchOutput | ForEach-Object { "$_" }) -join " | ").Trim()

if ($launchExit -ne 0) {
  Write-Output "WARN chrome debug bootstrap exit=$launchExit output=$launchText"
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $signScript
exit $LASTEXITCODE
