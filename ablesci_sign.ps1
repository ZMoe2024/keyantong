# ablesci_sign.ps1  (curl.exe °æ±¾£¬×îÎÈ)
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$cookiePath = Join-Path $ScriptDir "ablesci_cookie.txt"
$logPath    = Join-Path $ScriptDir "ablesci_sign.log"
$url        = "https://www.ablesci.com/user/sign"

function Log([string]$msg) {
  Add-Content -Path $logPath -Value ("{0} {1}" -f (Get-Date).ToString("s"), $msg)
}

if (!(Test-Path $cookiePath)) { Log "ERROR missing cookie file: $cookiePath"; exit 1 }
$cookie = (Get-Content $cookiePath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($cookie)) { Log "ERROR cookie file is empty"; exit 1 }

try {
  $resp = & curl.exe -sS -L $url `
    -H "Accept: application/json, text/javascript, */*; q=0.01" `
    -H "X-Requested-With: XMLHttpRequest" `
    -H "Referer: https://www.ablesci.com/" `
    -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36" `
    -H "Cookie: $cookie"

  $oneLine = ($resp -replace "\r?\n", " ").Trim()
  Log ("OK {0}" -f $oneLine)
} catch {
  Log ("ERROR {0}" -f $_.Exception.Message)
  exit 2
}
