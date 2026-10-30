# Run the finals load loop: reload the test page every IntervalSec, Runs times.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\load-loop.ps1 -Runs 10 -IntervalSec 120
#
# The page is already open (x4-win1.sh); Ctrl+R forces a real reload.  The
# harness takes a screendump after each key and records the console.
param(
    [string]$Disk = 'D:\x-kernel-dsh-bridge\delivered\agentos-disk.img',
    [string]$Kernel = 'artifacts\kernel-procfs.bin',
    [int]$Runs = 10,
    [int]$IntervalSec = 120,
    [string]$OutDir = '',
    [string]$CdpEndpoint = '',
    [int]$HoldSec = 1800
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$root = [System.IO.Path]::GetFullPath((Join-Path $here '..'))
if (-not $OutDir) {
    $OutDir = Join-Path $root ('experiments\LOAD-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '\run')
}
# Keep a real array even when there is only one switch: splatting a scalar
# string enumerates its characters in Windows PowerShell 5.1.
$cdpArgs = @(if ($CdpEndpoint) { '-CdpEndpoint'; $CdpEndpoint } else { '-EnableGuestCdp' })
$scripts = 'guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1.sh;guest\hb-start.sh'
$plan = '{0}x{1}@60' -f $Runs, $IntervalSec
$hold = [Math]::Max([Math]::Max(1800, $HoldSec), 60 + ($Runs - 1) * $IntervalSec + 60)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'host\xkwin.ps1') `
    -Tag LOAD -Disk $Disk -Kernel $Kernel -ServeManifest (Join-Path $root 'guest\serve-pages.txt') `
    -Script $scripts -LoadSchedule $plan -LoadHoldSec $hold @cdpArgs `
    -StartupReadyColors 300 -StartupReadyMax 3 -StartupReadyWaitSec 20 `
    -Upload 'guest\hb.sh;guest\hb-dump.sh' -Key 'cmd=sh /tmp/xk-hb-dump.sh' `
    -CommandTimeoutSec 2000 -BootTimeoutSec 420 -AfterScriptWait 10 -OutDir $OutDir
$harnessRc = $LASTEXITCODE
if ($harnessRc -ne 0) { exit $harnessRc }
& python (Join-Path $root 'host\acceptance\summarize_stability.py') $OutDir --expect-minutes 30
exit $LASTEXITCODE
