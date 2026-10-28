# 30-minute stability wrapper.  Start host/monitor-qemu.ps1 separately if you
# want the memory trend; this wrapper only runs the guest scenario.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\stability30.ps1
param(
    [string]$Disk = 'D:\x-kernel-dsh-bridge\delivered\agentos-disk.img',
    [string]$Kernel = 'artifacts\kernel-procfs.bin',
    [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$root = [System.IO.Path]::GetFullPath((Join-Path $here '..'))
if (-not $OutDir) {
    $OutDir = Join-Path $root ('experiments\STAB30-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '\run')
}
$scripts = 'guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1.sh;guest\x5c-win2.sh;guest\s10-stability30.sh'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'host\xkwin.ps1') `
    -Tag STAB30 -Disk $Disk -Kernel $Kernel -ServeManifest (Join-Path $root 'guest\serve-pages.txt') `
    -Script $scripts -CommandTimeoutSec 2000 -BootTimeoutSec 420 -AfterScriptWait 20 -OutDir $OutDir
exit $LASTEXITCODE
