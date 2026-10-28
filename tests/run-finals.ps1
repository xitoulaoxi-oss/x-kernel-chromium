# Finals dispatcher.  Monitor is started separately when needed:
#   host/monitor-qemu.ps1 -OutDir <run> -IntervalSec 15 -Minutes 35
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-finals.ps1 -Mode smoke
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-finals.ps1 -Mode stability
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-finals.ps1 -Mode load
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-finals.ps1 -Mode observe -Session experiments\E000-baseline\run3
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-finals.ps1 -Mode perf
param(
    [ValidateSet('smoke', 'stability', 'load', 'observe', 'perf')][string]$Mode = 'smoke',
    [string]$Disk = 'D:\x-kernel-dsh-bridge\delivered\agentos-disk.img',
    [string]$Kernel = 'artifacts\kernel-procfs.bin',
    [int]$Runs = 10,
    [int]$IntervalSec = 120,
    [string]$Session = '',
    [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$root = [System.IO.Path]::GetFullPath((Join-Path $here '..'))
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')

switch ($Mode) {
    'observe' {
        if (-not $Session) { throw '-Mode observe requires -Session <session-dir>' }
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'observe.ps1') -Session $Session
        exit $LASTEXITCODE
    }
    'perf' {
        & python (Join-Path $root 'host\perf_run.py') --repeats 5 --tag ('finals-' + $stamp) --kernel $Kernel --out (Join-Path $root ('evidence\reports\perf-report-' + $stamp + '.json'))
        exit $LASTEXITCODE
    }
    'stability' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'stability30.ps1') -Disk $Disk -Kernel $Kernel -OutDir $OutDir
        exit $LASTEXITCODE
    }
    'load' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'load-loop.ps1') -Disk $Disk -Kernel $Kernel -Runs $Runs -IntervalSec $IntervalSec -OutDir $OutDir
        exit $LASTEXITCODE
    }
    'smoke' {
        if (-not $OutDir) { $OutDir = Join-Path $root ('experiments\SMOKE-' + $stamp + '\run') }
        $scripts = 'guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1.sh;guest\y6-evidence.sh;guest\x5c-win2.sh'
        $keys = 'cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh'
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'host\xkwin.ps1') -Tag SMOKE -Disk $Disk -Kernel $Kernel -ServeManifest (Join-Path $root 'guest\serve-pages.txt') -Script $scripts -Key $keys -CommandTimeoutSec 300 -BootTimeoutSec 420 -AfterScriptWait 20 -OutDir $OutDir
        exit $LASTEXITCODE
    }
}
