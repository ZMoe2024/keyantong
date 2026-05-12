param(
  [Parameter(Mandatory = $true)]
  [string]$Cookie
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cookiePath = Join-Path $scriptDir "ablesci_cookie.txt"

$cleanCookie = $Cookie.Trim()
if ([string]::IsNullOrWhiteSpace($cleanCookie)) {
  throw "Cookie is empty."
}

[System.IO.File]::WriteAllText($cookiePath, $cleanCookie, [System.Text.UTF8Encoding]::new($false))
Write-Output "Cookie saved to: $cookiePath"
