Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cookiePath = Join-Path $ScriptDir "ablesci_cookie.txt"
$logPath = Join-Path $ScriptDir "ablesci_sign.log"
$url = "https://www.ablesci.com/user/sign"
$syncScriptPath = Join-Path $ScriptDir "sync_ablesci_cookie_from_debug.py"
$ensureDebugChromeScriptPath = Join-Path $ScriptDir "ensure_ablesci_debug_chrome.ps1"
$approvePromptScriptPath = Join-Path $ScriptDir "approve_remote_debug_prompt.py"
$managedDebugProfileDir = Join-Path $ScriptDir "chrome-debug-profile"
$managedDebugPortDefault = 9333
$cookieSyncModeDefault = "always"
$ablesciHomeUrl = "https://www.ablesci.com/"
$defaultVisitWaitSeconds = 6
$defaultChromeUserDataDir = if (![string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
  Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
} else {
  Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "Google\Chrome\User Data"
}
$defaultSessionActivePortFile = Join-Path $defaultChromeUserDataDir "DevToolsActivePort"

function Log {
  param(
    [ValidateSet("INFO", "WARN", "ERROR")]
    [string]$Level,
    [string]$Message
  )

  $line = "{0} [{1}] {2}" -f (Get-Date).ToString("s"), $Level, $Message
  Add-Content -Path $logPath -Value $line -Encoding UTF8
  Write-Output $line
}

function Get-PythonLauncher {
  $python = Get-Command -Name "python" -ErrorAction SilentlyContinue
  if ($null -ne $python) {
    return @("python")
  }

  $py = Get-Command -Name "py" -ErrorAction SilentlyContinue
  if ($null -ne $py) {
    return @("py", "-3")
  }

  return $null
}

function Get-CookieValue {
  if (!(Test-Path -LiteralPath $cookiePath)) {
    return $null
  }

  $cookieRaw = Get-Content -LiteralPath $cookiePath -Raw
  if ($null -eq $cookieRaw) {
    $cookieRaw = ""
  }

  $cookie = $cookieRaw.Trim()
  if ([string]::IsNullOrWhiteSpace($cookie)) {
    return $null
  }

  return $cookie
}

function Invoke-CookieSync {
  param([string]$Reason)

  if ($env:ABLESCI_COOKIE_SYNC -match "^(?i:0|false|off|no)$") {
    Log -Level "INFO" -Message "cookie sync skipped by ABLESCI_COOKIE_SYNC=$($env:ABLESCI_COOKIE_SYNC)"
    return $false
  }

  if (!(Test-Path -LiteralPath $syncScriptPath)) {
    Log -Level "WARN" -Message "cookie sync script not found: $syncScriptPath"
    return $false
  }

  $launcher = @(Get-PythonLauncher)
  if ($launcher.Count -eq 0) {
    Log -Level "WARN" -Message "python launcher not found; skip cookie sync"
    return $false
  }

  $command = $launcher[0]
  $args = @()
  if ($launcher.Count -gt 1) {
    $args += $launcher[1..($launcher.Count - 1)]
  }
  $args += @(
    $syncScriptPath,
    "--output", $cookiePath,
    "--visit-url", $ablesciHomeUrl,
    "--visit-wait-seconds", $defaultVisitWaitSeconds
  )

  $debugSourceMode = Get-DebugSourceMode
  if ($debugSourceMode -eq "off") {
    Log -Level "WARN" -Message "debug source disabled by ABLESCI_DEBUG_SOURCE_MODE=off"
    return $false
  }

  if ($debugSourceMode -eq "managed-chrome") {
    [void](Ensure-ManagedDebugChrome)
    $args += @("--debug-port", (Get-ManagedDebugPort))
  } else {
    Start-RemoteDebugPromptApprover
    $activePortFile = Get-SessionActivePortFile
    if (![string]::IsNullOrWhiteSpace($activePortFile)) {
      $args += @("--active-port-file", $activePortFile)
    }
  }

  $syncOutput = @()
  $syncExitCode = 0
  $nativeErrorPrefVar = Get-Variable -Name "PSNativeCommandUseErrorActionPreference" -ErrorAction SilentlyContinue
  $prevNativeErrorPref = $null

  try {
    if ($null -ne $nativeErrorPrefVar) {
      $prevNativeErrorPref = $PSNativeCommandUseErrorActionPreference
      $PSNativeCommandUseErrorActionPreference = $false
    }

    $syncOutput = & $command @args 2>&1
    $syncExitCode = $LASTEXITCODE
  } catch {
    if ($null -ne $nativeErrorPrefVar) {
      $PSNativeCommandUseErrorActionPreference = $prevNativeErrorPref
    }
    Log -Level "WARN" -Message "cookie sync invocation failed ($Reason): $($_.Exception.Message)"
    return $false
  } finally {
    if ($null -ne $nativeErrorPrefVar) {
      $PSNativeCommandUseErrorActionPreference = $prevNativeErrorPref
    }
  }
  $syncText = (($syncOutput | ForEach-Object { "$_" }) -join " | ").Trim()

  if ($syncExitCode -eq 0) {
    if (Test-Path -LiteralPath $cookiePath) {
      $cookieLen = (Get-Item -LiteralPath $cookiePath).Length
      if ($cookieLen -gt 0) {
        Log -Level "INFO" -Message "cookie sync OK ($Reason); cookie_len=$cookieLen"
      } else {
        Log -Level "WARN" -Message "cookie sync OK but cookie file is empty ($Reason)"
      }
    } else {
      Log -Level "WARN" -Message "cookie sync OK but cookie file not found ($Reason)"
    }
    return $true
  }

  Log -Level "WARN" -Message "cookie sync failed ($Reason), exit=$syncExitCode, output=$syncText"
  return $false
}

function Get-CookieSyncMode {
  $modeRaw = $env:ABLESCI_COOKIE_SYNC_MODE
  if ([string]::IsNullOrWhiteSpace($modeRaw)) {
    return $cookieSyncModeDefault
  }

  switch ($modeRaw.Trim().ToLowerInvariant()) {
    "always" { return "always" }
    "on-demand" { return "on-demand" }
    "off" { return "off" }
    default {
      Log -Level "WARN" -Message "unknown ABLESCI_COOKIE_SYNC_MODE=$modeRaw; fallback to $cookieSyncModeDefault"
      return $cookieSyncModeDefault
    }
  }
}

function Get-DebugSourceMode {
  $modeRaw = $env:ABLESCI_DEBUG_SOURCE_MODE
  if ([string]::IsNullOrWhiteSpace($modeRaw)) {
    return "session-setting"
  }

  switch ($modeRaw.Trim().ToLowerInvariant()) {
    "managed-chrome" { return "managed-chrome" }
    "session-setting" { return "session-setting" }
    "off" { return "off" }
    default {
      Log -Level "WARN" -Message "unknown ABLESCI_DEBUG_SOURCE_MODE=$modeRaw; fallback to session-setting"
      return "session-setting"
    }
  }
}

function Get-SessionActivePortFile {
  if (![string]::IsNullOrWhiteSpace($env:ABLESCI_DEVTOOLS_ACTIVE_PORT)) {
    return $env:ABLESCI_DEVTOOLS_ACTIVE_PORT
  }

  return $defaultSessionActivePortFile
}

function Should-AutoApproveRemoteDebugPrompt {
  if ($env:ABLESCI_AUTO_APPROVE_REMOTE_DEBUG -match "^(?i:0|false|off|no)$") {
    return $false
  }

  return $true
}

function Start-RemoteDebugPromptApprover {
  if (!(Should-AutoApproveRemoteDebugPrompt)) {
    return
  }

  if (!(Test-Path -LiteralPath $approvePromptScriptPath)) {
    Log -Level "WARN" -Message "remote debug approver script not found: $approvePromptScriptPath"
    return
  }

  $launcher = @(Get-PythonLauncher)
  if ($launcher.Count -eq 0) {
    Log -Level "WARN" -Message "python launcher not found; skip remote debug auto-approve"
    return
  }

  $command = $launcher[0]
  $args = @()
  if ($launcher.Count -gt 1) {
    $args += $launcher[1..($launcher.Count - 1)]
  }
  $args += @($approvePromptScriptPath, "--timeout-seconds", "20", "--poll-seconds", "0.2")

  try {
    Start-Process -FilePath $command -ArgumentList $args -WindowStyle Hidden | Out-Null
  } catch {
    Log -Level "WARN" -Message "failed to start remote debug auto-approve helper: $($_.Exception.Message)"
  }
}

function Get-ManagedDebugPort {
  if ($env:ABLESCI_MANAGED_DEBUG_PORT -match "^\d+$") {
    return [int]$env:ABLESCI_MANAGED_DEBUG_PORT
  }

  return $managedDebugPortDefault
}

function Ensure-ManagedDebugChrome {
  if (!(Test-Path -LiteralPath $ensureDebugChromeScriptPath)) {
    Log -Level "WARN" -Message "managed debug script not found: $ensureDebugChromeScriptPath"
    return $false
  }

  $managedDebugPort = Get-ManagedDebugPort
  $ensureOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensureDebugChromeScriptPath `
    -ProfileDir $managedDebugProfileDir `
    -Port $managedDebugPort `
    -StartUrl "https://www.ablesci.com/" 2>&1
  $ensureExit = $LASTEXITCODE
  $ensureText = (($ensureOutput | ForEach-Object { "$_" }) -join " | ").Trim()

  if ($ensureExit -eq 0) {
    Log -Level "INFO" -Message "managed debug chrome ready. $ensureText"
    return $true
  }

  Log -Level "WARN" -Message "managed debug chrome not ready. exit=$ensureExit output=$ensureText"
  return $false
}

function Invoke-SignRequest {
  param([string]$CookieHeader)

  $resp = & curl.exe -sS -L --max-time 20 $url `
    -H "Accept: application/json, text/javascript, */*; q=0.01" `
    -H "X-Requested-With: XMLHttpRequest" `
    -H "Referer: https://www.ablesci.com/" `
    -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36" `
    -H "Cookie: $CookieHeader"

  if ($LASTEXITCODE -ne 0) {
    throw "curl exit code: $LASTEXITCODE"
  }

  $oneLine = ($resp -replace "\r?\n", " ").Trim()
  if ([string]::IsNullOrWhiteSpace($oneLine)) {
    throw "empty response body"
  }

  $messageText = $oneLine
  try {
    $json = $oneLine | ConvertFrom-Json -ErrorAction Stop
    if ($null -ne $json.msg) {
      $messageText = [string]$json.msg
    }
  } catch {
    Log -Level "WARN" -Message "response is not valid json; raw=$oneLine"
  }

  $loginPattern = "需要登录|点击登录|login|need-login-tips|\\u9700\\u8981\\u767b\\u5f55|\\u70b9\\u51fb\\u767b\\u5f55"
  $signedPattern = "签到成功|已签到|今天已于|\\u7b7e\\u5230\\u6210\\u529f|\\u5df2\\u7b7e\\u5230|\\u4eca\\u5929\\u5df2\\u4e8e"

  return @{
    Raw = $oneLine
    Message = $messageText
    IsLoginRequired = (($messageText -match $loginPattern) -or ($oneLine -match $loginPattern))
    IsSignedAccepted = (($messageText -match $signedPattern) -or ($oneLine -match $signedPattern))
  }
}

try {
  $syncMode = Get-CookieSyncMode
  $cookie = Get-CookieValue

  if ($syncMode -eq "always") {
    [void](Invoke-CookieSync -Reason "pre-sign(mode=always)")
    $cookie = Get-CookieValue
  } elseif (($syncMode -eq "on-demand") -and [string]::IsNullOrWhiteSpace($cookie)) {
    [void](Invoke-CookieSync -Reason "pre-sign(mode=on-demand-empty-cookie)")
    $cookie = Get-CookieValue
  } elseif ($syncMode -eq "off") {
    Log -Level "INFO" -Message "cookie sync disabled by ABLESCI_COOKIE_SYNC_MODE=off"
  }

  if ([string]::IsNullOrWhiteSpace($cookie)) {
    Log -Level "ERROR" -Message "cookie file is empty: $cookiePath"
    exit 1
  }

  $result = Invoke-SignRequest -CookieHeader $cookie
  if ($result.IsLoginRequired) {
    Log -Level "WARN" -Message "login required on first attempt; trying cookie refresh + retry"
    [void](Invoke-CookieSync -Reason "retry-after-login-required")

    $cookieRetry = Get-CookieValue
    if ([string]::IsNullOrWhiteSpace($cookieRetry)) {
      Log -Level "ERROR" -Message "cookie refresh retry failed; cookie file is empty: $cookiePath"
      exit 3
    }

    $result = Invoke-SignRequest -CookieHeader $cookieRetry
  }

  if ($result.IsLoginRequired) {
    Log -Level "ERROR" -Message "cookie expired or invalid. response=$($result.Raw)"
    exit 3
  }

  if ($result.IsSignedAccepted) {
    Log -Level "INFO" -Message "sign request accepted. response=$($result.Raw)"
    exit 0
  }

  Log -Level "WARN" -Message "unexpected response. response=$($result.Raw)"
  exit 4
} catch {
  Log -Level "ERROR" -Message $_.Exception.Message
  exit 2
}
