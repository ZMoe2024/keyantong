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

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$signScript`""
$triggerDaily = New-ScheduledTaskTrigger -Daily -At $DailyAt
$triggerLogon = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -ne $existing) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $action `
  -Trigger @($triggerDaily, $triggerLogon) `
  -Settings $settings `
  -Description "Auto sign on https://www.ablesci.com/ using cookie script." | Out-Null

Write-Output "Scheduled task installed: $TaskName"
Write-Output "Triggers: daily at $DailyAt + at logon"
