Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cookiePath = Join-Path $ScriptDir "ablesci_cookie.txt"
$logPath = Join-Path $ScriptDir "ablesci_sign.log"
$url = "https://www.ablesci.com/user/sign"

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

if (!(Test-Path -LiteralPath $cookiePath)) {
  Log -Level "ERROR" -Message "missing cookie file: $cookiePath"
  exit 1
}

$cookieRaw = Get-Content -LiteralPath $cookiePath -Raw
if ($null -eq $cookieRaw) {
  $cookieRaw = ""
}

$cookie = $cookieRaw.Trim()
if ([string]::IsNullOrWhiteSpace($cookie)) {
  Log -Level "ERROR" -Message "cookie file is empty: $cookiePath"
  exit 1
}

try {
  $resp = & curl.exe -sS -L --max-time 20 $url `
    -H "Accept: application/json, text/javascript, */*; q=0.01" `
    -H "X-Requested-With: XMLHttpRequest" `
    -H "Referer: https://www.ablesci.com/" `
    -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36" `
    -H "Cookie: $cookie"

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
  if (($messageText -match $loginPattern) -or ($oneLine -match $loginPattern)) {
    Log -Level "ERROR" -Message "cookie expired or invalid. response=$oneLine"
    exit 3
  }

  $signedPattern = "签到成功|已签到|今天已于|\\u7b7e\\u5230\\u6210\\u529f|\\u5df2\\u7b7e\\u5230|\\u4eca\\u5929\\u5df2\\u4e8e"
  if (($messageText -match $signedPattern) -or ($oneLine -match $signedPattern)) {
    Log -Level "INFO" -Message "sign request accepted. response=$oneLine"
    exit 0
  }

  Log -Level "WARN" -Message "unexpected response. response=$oneLine"
  exit 4
} catch {
  Log -Level "ERROR" -Message $_.Exception.Message
  exit 2
}
