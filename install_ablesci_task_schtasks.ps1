param(
  [string]$TaskName = "AbleSci-AutoSign",
  [string]$DailyAt = "08:15"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$signScript = Join-Path $scriptDir "ablesci_sign.ps1"

if (!(Test-Path -LiteralPath $signScript)) {
  throw "Sign script not found: $signScript"
}

if ($DailyAt -notmatch "^\d{2}:\d{2}$") {
  throw "DailyAt must use HH:mm format, e.g. 08:15"
}

$taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$signScript`""

& schtasks.exe /Delete /TN $TaskName /F | Out-Null

& schtasks.exe /Create /TN $TaskName /SC DAILY /ST $DailyAt /TR $taskCommand /F
if ($LASTEXITCODE -ne 0) {
  throw "failed to create daily task; exit code=$LASTEXITCODE"
}

& schtasks.exe /Create /TN ($TaskName + "-AtLogon") /SC ONLOGON /TR $taskCommand /F
if ($LASTEXITCODE -ne 0) {
  throw "failed to create logon task; exit code=$LASTEXITCODE"
}

Write-Output "Scheduled tasks installed:"
Write-Output "  $TaskName (daily at $DailyAt)"
Write-Output "  $TaskName-AtLogon (at logon)"
