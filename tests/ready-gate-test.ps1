# Regression test for host/ready-gate.ps1 (task 08).
# Pure predicate: no QEMU, no guest.  Run from the repo root:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\ready-gate-test.ps1
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$root = [System.IO.Path]::GetFullPath((Join-Path $here '..'))
. (Join-Path $root 'host\ready-gate.ps1')

$fail = 0
function Check([string]$Name, $Stats, [int]$Min, [bool]$Want) {
    $got = Test-StartupReady -Stats $Stats -MinColors $Min
    if ($got -eq $Want) {
        Write-Host ("PASS {0} (got {1})" -f $Name, $got)
    } else {
        Write-Host ("FAIL {0} (want {1}, got {2})" -f $Name, $Want, $got) -ForegroundColor Red
        $script:fail = 1
    }
}

Check 'null stats are not ready' $null 300 $false
Check 'blank frame is not ready even with 900 colours' ([pscustomobject]@{ colors = 900; blank = $true }) 300 $false
Check 'blank page with spinner (262) is not ready' ([pscustomobject]@{ colors = 262; blank = $false }) 300 $false
Check 'rendered index page (835) is ready' ([pscustomobject]@{ colors = 835; blank = $false }) 300 $true
Check 'boundary 300 is ready' ([pscustomobject]@{ colors = 300; blank = $false }) 300 $true
Check '299 is not ready' ([pscustomobject]@{ colors = 299; blank = $false }) 300 $false
Check 'missing colors property is not ready' ([pscustomobject]@{ blank = $false }) 300 $false

if ($fail -ne 0) { exit 1 }
Write-Host 'all ready-gate checks passed'
