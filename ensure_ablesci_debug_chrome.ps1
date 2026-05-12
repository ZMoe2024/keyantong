param(
  [string]$ProfileDir = "",
  [int]$Port = 9333,
  [string]$StartUrl = "https://www.ablesci.com/",
  [int]$WaitSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProfileDir)) {
  $ProfileDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "chrome-debug-profile"
}

function Test-DebugEndpoint {
  param([string]$Url)

  try {
    $resp = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri $Url
    if ($resp.StatusCode -eq 200 -and $resp.Content -match "Browser|webSocketDebuggerUrl") {
      return $true
    }
  } catch {
    return $false
  }

  return $false
}

function Get-ChromeExecutable {
  $chromeCmd = Get-Command -Name "chrome.exe" -ErrorAction SilentlyContinue
  if ($null -ne $chromeCmd -and ![string]::IsNullOrWhiteSpace($chromeCmd.Source)) {
    return $chromeCmd.Source
  }

  $candidates = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )

  foreach ($candidate in $candidates) {
    if (![string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
      return $candidate
    }
  }

  return $null
}

$versionUrl = "http://127.0.0.1:{0}/json/version" -f $Port
if (Test-DebugEndpoint -Url $versionUrl) {
  Write-Output "READY debug_port=$Port profile_dir=$ProfileDir"
  exit 0
}

New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null

$chromeExe = Get-ChromeExecutable
if ([string]::IsNullOrWhiteSpace($chromeExe)) {
  Write-Output "ERROR chrome executable not found"
  exit 1
}

$chromeArgs = @(
  "--remote-debugging-port=$Port",
  "--remote-allow-origins=*",
  "--user-data-dir=$ProfileDir",
  "--no-first-run",
  "--no-default-browser-check",
  "--new-window",
  $StartUrl
)

Start-Process -FilePath $chromeExe -ArgumentList $chromeArgs | Out-Null

$deadline = (Get-Date).AddSeconds($WaitSeconds)
do {
  Start-Sleep -Milliseconds 500
  if (Test-DebugEndpoint -Url $versionUrl) {
    Write-Output "READY debug_port=$Port profile_dir=$ProfileDir"
    exit 0
  }
} while ((Get-Date) -lt $deadline)

Write-Output "ERROR debug chrome did not become ready within $WaitSeconds seconds"
exit 2
