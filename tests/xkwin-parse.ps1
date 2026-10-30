$ErrorActionPreference = 'Stop'
$text = Get-Content -Raw (Join-Path $PSScriptRoot '../host/xkwin.ps1')
$null = [scriptblock]::Create($text)
Write-Output 'XKWIN-PARSE-OK'
