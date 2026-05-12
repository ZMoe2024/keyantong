param(
  [int]$Port = 8572,
  [int]$WaitSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$userDataDir = if (![string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
  Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
} else {
  Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "Google\Chrome\User Data"
}

function Test-DebugEndpoint {
  param([string]$Url)

  try {
    $resp = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri $Url
    if (($resp.StatusCode -eq 200) -and ($resp.Content -match "webSocketDebuggerUrl")) {
      return $true
    }
  } catch {
    return $false
  }

  return $false
}

function Get-ChromeExecutable {
  $chromeCmd = Get-Command -Name "chrome.exe" -ErrorAction SilentlyContinue
  if (($null -ne $chromeCmd) -and (![string]::IsNullOrWhiteSpace($chromeCmd.Source))) {
    return $chromeCmd.Source
  }

  $candidates = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )

  foreach ($candidate in $candidates) {
    if ((![string]::IsNullOrWhiteSpace($candidate)) -and (Test-Path -LiteralPath $candidate)) {
      return $candidate
    }
  }

  return $null
}

$versionUrl = "http://127.0.0.1:{0}/json/version" -f $Port
if (Test-DebugEndpoint -Url $versionUrl) {
  Write-Output "READY debug_port=$Port user_data_dir=$userDataDir"
  exit 0
}

$chromeExe = Get-ChromeExecutable
if ([string]::IsNullOrWhiteSpace($chromeExe)) {
  Write-Output "ERROR chrome executable not found"
  exit 1
}

$chromeProcesses = @(Get-Process chrome -ErrorAction SilentlyContinue)
if ($chromeProcesses.Count -gt 0) {
  Write-Output "WARN chrome already running without active debug endpoint; launch may require next restart"
}

$chromeArgs = @(
  "--remote-debugging-port=$Port",
  "--remote-allow-origins=*",
  "--user-data-dir=`"$userDataDir`"",
  "--no-first-run",
  "--no-default-browser-check"
)

Start-Process -FilePath $chromeExe -ArgumentList $chromeArgs | Out-Null

$deadline = (Get-Date).AddSeconds($WaitSeconds)
do {
  Start-Sleep -Milliseconds 500
  if (Test-DebugEndpoint -Url $versionUrl) {
    Write-Output "READY debug_port=$Port user_data_dir=$userDataDir"
    exit 0
  }
} while ((Get-Date) -lt $deadline)

Write-Output "ERROR debug endpoint not ready on port $Port"
exit 2
