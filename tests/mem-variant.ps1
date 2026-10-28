# Run one E004 memory variant (disk profile / Chromium flags / combined).
# Start host/monitor-qemu.ps1 separately for the memory curve.
param(
    [ValidateSet('disk', 'flags', 'combined')][string]$Variant = 'combined',
    [string]$Disk = 'D:\x-kernel-dsh-bridge\delivered\agentos-disk.img',
    [string]$Kernel = 'artifacts\kernel-procfs.bin',
    [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$root = [System.IO.Path]::GetFullPath((Join-Path $here '..'))
if (-not $OutDir) {
    $OutDir = Join-Path $root ('experiments\E004-' + $Variant + '-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '\run')
}
switch ($Variant) {
    'disk' { $win1 = 'guest\x4-win1-disk.sh'; $win2 = 'guest\x5c-win2-disk.sh' }
    'flags' { $win1 = 'guest\x4-win1-memflags.sh'; $win2 = 'guest\x5c-win2-memflags.sh' }
    default { $win1 = 'guest\x4-win1-lowmem.sh'; $win2 = 'guest\x5c-win2-lowmem.sh' }
}
$scripts = "guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;$win1;$win2;guest\y6-evidence.sh"
$keys = 'cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'host\xkwin.ps1') `
    -Tag ('E004-' + $Variant) -Disk $Disk -Kernel $Kernel -ServeManifest (Join-Path $root 'guest\serve-pages.txt') `
    -Script $scripts -Key $keys -CommandTimeoutSec 400 -BootTimeoutSec 420 -AfterScriptWait 20 -OutDir $OutDir
exit $LASTEXITCODE
