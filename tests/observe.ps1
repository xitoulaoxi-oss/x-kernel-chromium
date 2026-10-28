# One-click wrapper around host/observe.py.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\observe.ps1 ^
#     -Session experiments\E000-baseline\run3 -ExpectedMinutes 0
#
# Use -Strict to exit 1 when crash/hang/leak is detected.
param(
    [Parameter(Mandatory = $true)][string]$Session,
    [int]$ExpectedMinutes = 0,
    [switch]$Strict
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$root = [System.IO.Path]::GetFullPath((Join-Path $here '..'))
$argsList = @((Join-Path $root 'host\observe.py'), $Session)
if ($ExpectedMinutes -gt 0) { $argsList += @('--expected-minutes', $ExpectedMinutes) }
if ($Strict) { $argsList += '--strict' }
& python @argsList
exit $LASTEXITCODE
