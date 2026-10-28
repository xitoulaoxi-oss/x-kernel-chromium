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
    [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$root = [System.IO.Path]::GetFullPath((Join-Path $here '..'))
if (-not $OutDir) {
    $OutDir = Join-Path $root ('experiments\LOAD-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '\run')
}
$keys = (1..$Runs | ForEach-Object { 'ctrl+r@' + $IntervalSec }) -join ';'
$scripts = 'guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1.sh;guest\x5c-win2.sh'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'host\xkwin.ps1') `
    -Tag LOAD -Disk $Disk -Kernel $Kernel -ServeManifest (Join-Path $root 'guest\serve-pages.txt') `
    -Script $scripts -Key $keys -CommandTimeoutSec 300 -BootTimeoutSec 420 -AfterScriptWait 60 -OutDir $OutDir
exit $LASTEXITCODE
