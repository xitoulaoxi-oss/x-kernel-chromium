# Low-memory smoke: same three-page/two-window flow, E004 Chromium variants.
# Start host/monitor-qemu.ps1 separately for the memory trend.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\lowmem-smoke.ps1
param(
    [string]$Disk = 'D:\x-kernel-dsh-bridge\delivered\agentos-disk.img',
    [string]$Kernel = 'artifacts\kernel-procfs.bin',
    [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$root = [System.IO.Path]::GetFullPath((Join-Path $here '..'))
if (-not $OutDir) {
    $OutDir = Join-Path $root ('experiments\LOWMEM-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '\run')
}
$scripts = 'guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1-lowmem.sh;guest\x5c-win2-lowmem.sh;guest\y6-evidence.sh'
$keys = 'cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'host\xkwin.ps1') `
    -Tag LOWMEM -Disk $Disk -Kernel $Kernel -ServeManifest (Join-Path $root 'guest\serve-pages.txt') `
    -Script $scripts -Key $keys -CommandTimeoutSec 400 -BootTimeoutSec 420 -AfterScriptWait 20 -OutDir $OutDir
exit $LASTEXITCODE
