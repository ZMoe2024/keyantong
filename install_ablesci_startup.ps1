param(
  [string]$ShortcutName = "AbleSci Auto Sign"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$signScript = Join-Path $scriptDir "ablesci_sign.ps1"

if (!(Test-Path -LiteralPath $signScript)) {
  throw "Sign script not found: $signScript"
}

$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir ($ShortcutName + ".lnk")

$wshShell = New-Object -ComObject WScript.Shell
$shortcut = $wshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$signScript`""
$shortcut.WorkingDirectory = $scriptDir
$shortcut.WindowStyle = 7
$shortcut.Description = "Auto sign on https://www.ablesci.com/ at Windows logon."
$shortcut.Save()

Write-Output "Startup shortcut installed: $shortcutPath"
