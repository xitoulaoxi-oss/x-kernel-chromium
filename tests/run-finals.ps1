# Finals entry point: preflight, smoke, functional, stability, load, perf,
# diagnose, report.  One command per scenario; every mode returns a non-zero
# exit code on failure and keeps the session evidence on disk.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-finals.ps1 -Mode preflight
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-finals.ps1 -Mode smoke -Monitor
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-finals.ps1 -Mode functional
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-finals.ps1 -Mode stability -Minutes 32
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-finals.ps1 -Mode load -Runs 10 -IntervalSec 120
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-finals.ps1 -Mode perf
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-finals.ps1 -Mode diagnose -Session <dir>
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-finals.ps1 -Mode report -Session <dir>
#
# `-Disk` is passed to every QEMU mode and to host/perf_run.py.
param(
    [ValidateSet('preflight', 'smoke', 'functional', 'stability', 'load', 'perf', 'diagnose', 'report')]
    [string]$Mode = 'preflight',
    [string]$Disk = 'D:\x-kernel-dsh-bridge\delivered\agentos-disk.img',
    [string]$Kernel = 'artifacts\kernel-procfs.bin',
    [int]$Runs = 10,
    [int]$IntervalSec = 120,
    [int]$Minutes = 0,
    [string]$Session = '',
    [string]$OutDir = '',
    [string]$CdpEndpoint = '',
    [switch]$Monitor
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$root = [System.IO.Path]::GetFullPath((Join-Path $here '..'))
Set-Location $root
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:monitorProc = $null
$cdpArgs = @()
if ($CdpEndpoint) { $cdpArgs = @('-CdpEndpoint', $CdpEndpoint) }

function Write-Section([string]$s) { Write-Host ""; Write-Host "== $s ==" -ForegroundColor Cyan }
function Fail([string]$s) { Write-Host "FAIL: $s" -ForegroundColor Red; exit 1 }

function Invoke-Preflight {
    Write-Section 'preflight'
    $bad = 0
    $qemu = Get-Command qemu-system-aarch64 -ErrorAction SilentlyContinue
    if ($qemu) {
        $ver = (& $qemu.Source --version | Select-Object -First 1)
        Write-Host ("qemu   : {0} ({1})" -f $qemu.Source, $ver)
    } else { Write-Host 'qemu   : MISSING from PATH' -ForegroundColor Red; $bad++ }
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) { Write-Host ("python : {0}" -f (& python --version 2>&1)) }
    else { Write-Host 'python : MISSING from PATH' -ForegroundColor Red; $bad++ }
    foreach ($p in @($Disk, $Kernel, 'pages\index.html', 'pages\interaction.html', 'pages\layout.html',
                     'guest\serve-pages.txt', 'host\xkwin.ps1', 'host\ready-gate.ps1')) {
        if (Test-Path -LiteralPath $p) {
            $len = (Get-Item -LiteralPath $p).Length
            Write-Host ("file   : {0} ({1} bytes)" -f $p, $len)
        } else { Write-Host ("file   : MISSING {0}" -f $p) -ForegroundColor Red; $bad++ }
    }
    if (Test-Path -LiteralPath $Kernel) {
        $h = (Get-FileHash -LiteralPath $Kernel -Algorithm SHA256).Hash.ToLower()
        Write-Host ("kernel : {0}" -f $h)
    }
    if ($bad -ne 0) { Write-Host ("{0} preflight item(s) failed" -f $bad) -ForegroundColor Red; exit 2 }
    Write-Host 'preflight OK'
    return 0
}

function Start-Monitor([string]$dir, [int]$mins) {
    if (-not $Monitor) { return }
    $log = Join-Path $dir 'monitor-launch.log'
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $here '..\host\monitor-qemu.ps1') + '"'),
              '-OutDir', ('"' + $dir + '"'), '-IntervalSec', '15', '-Minutes', $mins)
    $script:monitorProc = Start-Process -FilePath 'powershell' -ArgumentList $args -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError ($log + '.err') -WindowStyle Hidden
    Write-Host ("monitor: pid {0}" -f $script:monitorProc.Id)
}

function Stop-Monitor {
    if ($script:monitorProc -and -not $script:monitorProc.HasExited) {
        Stop-Process -Id $script:monitorProc.Id -Force -ErrorAction SilentlyContinue
        Write-Host 'monitor: stopped'
    }
}

function Invoke-Smoke {
    $dir = if ($OutDir) { $OutDir } else { Join-Path $root ("experiments\RUNS\SMOKE-$stamp\run") }
    New-Item -ItemType Directory -Force $dir | Out-Null
    Start-Monitor $dir 8
    $semanticArgs = @('-PageProbeMode', 'page')
    if ($CdpEndpoint) { $semanticArgs += @('-CdpEndpoint', $CdpEndpoint) } else { $semanticArgs += '-EnableGuestCdp' }
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'host\xkwin.ps1') `
            -Tag "SMOKE-$stamp" -Disk $Disk -Kernel $Kernel `
            -ServeManifest (Join-Path $root 'guest\serve-pages.txt') `
            -Script 'guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1.sh' `
            -StartupReadyColors 300 -StartupReadyMax 3 -StartupReadyWaitSec 20 -StartupReadyPollSec 5 `
            -Upload 'guest\y6-evidence.sh' -Key 'cmd=sh /tmp/xk-y6-evidence.sh' `
            @semanticArgs `
            -CommandTimeoutSec 300 -BootTimeoutSec 420 -AfterScriptWait 10 -OutDir $dir
        $rc = $LASTEXITCODE
    } finally { Stop-Monitor }
    if ($rc -ne 0) { Fail "xkwin exit $rc (evidence $dir)" }
    $readyPath = Join-Path $dir 'startup-ready.json'
    $statsPath = Join-Path $dir 'zz-final.stats.json'
    if (-not (Test-Path $readyPath)) { Fail "no startup-ready.json (evidence $dir)" }
    if (-not (Test-Path $statsPath)) { Fail "no zz-final.stats.json (evidence $dir)" }
    $ready = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
    $stats = Get-Content -LiteralPath $statsPath -Raw | ConvertFrom-Json
    $pagePath = Join-Path $dir 'page-check.json'
    if (-not (Test-Path -LiteralPath $pagePath)) { Fail 'no semantic page evidence' }
    $page = Get-Content -LiteralPath $pagePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $console = Get-Content -LiteralPath (Join-Path $dir 'console.log') -Raw
    $title = ''
    $m = [regex]::Matches($console, 'WM_NAME\(UTF8_STRING\) = "([^"]+)"')
    if ($m.Count -gt 0) { $title = $m[$m.Count - 1].Groups[1].Value }
    Write-Section 'smoke verdict'
    Write-Host ("ready  : {0} (attempts {1})" -f $ready.ready, @($ready.attempts).Count)
    Write-Host ("colors : {0} blank={1}" -f $stats.colors, $stats.blank)
    Write-Host ("title  : {0}" -f $title)
    if (-not $ready.ready) { Fail 'startup gate did not reach ready' }
    if ($page.ok -ne $true -or $page.url -ne 'file:///usr/share/kiosk/official/index.html') { Fail 'official page did not complete' }
    if ([int]$stats.colors -lt 300 -or $stats.blank) { Fail 'final frame has no page content' }
    if (-not $title -or $title -notmatch 'x-kernel' -or $title -match 'Untitled') { Fail 'window title never committed' }
    Write-Host 'smoke PASS'
    return 0
}

function Invoke-Diagnose {
    if (-not $Session) { Fail '-Mode diagnose requires -Session <dir>' }
    $out = Join-Path $Session 'observe.json'
    $extra = @()
    if ($Minutes -gt 0) { $extra += @('--expected-minutes', [string]$Minutes) }
    & python (Join-Path $root 'host\observe.py') $Session --strict --out $out @extra
    exit $LASTEXITCODE
}

function Invoke-Report {
    if (-not $Session) { Fail '-Mode report requires -Session <dir>' }
    $ready = Get-Content -LiteralPath (Join-Path $Session 'startup-ready.json') -Raw -ErrorAction SilentlyContinue
    $stats = Get-Content -LiteralPath (Join-Path $Session 'zz-final.stats.json') -Raw -ErrorAction SilentlyContinue
    $metrics = Get-Content -LiteralPath (Join-Path $Session 'qemu-metrics.json') -Raw -ErrorAction SilentlyContinue
    $r = if ($ready) { $ready | ConvertFrom-Json } else { $null }
    $s = if ($stats) { $stats | ConvertFrom-Json } else { $null }
    $q = if ($metrics) { $metrics | ConvertFrom-Json } else { $null }
    $lines = @()
    $lines += "# Session report: $Session"
    $lines += ""
    $lines += "| item | value |"
    $lines += "|---|---|"
    $lines += ("| ready | {0} |" -f ($(if ($r) { $r.ready } else { 'n/a' })))
    $lines += ("| final colors | {0} |" -f ($(if ($s) { $s.colors } else { 'n/a' })))
    $lines += ("| final blank | {0} |" -f ($(if ($s) { $s.blank } else { 'n/a' })))
    $lines += ("| qemu peak ws MB | {0} |" -f ($(if ($q) { [math]::Round($q.peak_working_set_b / 1MB, 1) } else { 'n/a' })))
    $text = ($lines -join "`n") + "`n"
    $outFile = Join-Path $Session 'report.md'
    [System.IO.File]::WriteAllText($outFile, $text, $utf8)
    Write-Host $text
    Write-Host ("wrote {0}" -f $outFile)
    return 0
}

switch ($Mode) {
    'preflight' { exit (Invoke-Preflight) }
    'smoke' { exit (Invoke-Smoke) }
    'functional' {
        $f = Join-Path $here 'functional.ps1'
        if (-not (Test-Path -LiteralPath $f)) { Fail 'tests\functional.ps1 not present' }
        & powershell -NoProfile -ExecutionPolicy Bypass -File $f -Disk $Disk -Kernel $Kernel @cdpArgs -OutRoot $(if ($OutDir) { $OutDir } else { Join-Path $root ('experiments/RUNS/FUNCTIONAL-' + $stamp) })
        exit $LASTEXITCODE
    }
    'stability' {
        $d = if ($OutDir) { $OutDir } else { Join-Path $root ("experiments\RUNS\STAB-$stamp\run") }
        New-Item -ItemType Directory -Force $d | Out-Null
        $mon = if ($Minutes -gt 0) { $Minutes } else { 35 }
        Start-Monitor $d ($mon + 5)
        try {
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'load-loop.ps1') -Disk $Disk -Kernel $Kernel -OutDir $d @cdpArgs -HoldSec ([Math]::Max(1800, $mon * 60))
            $rc = $LASTEXITCODE
        } finally { Stop-Monitor }
        exit $rc
    }
    'load' {
        $d = if ($OutDir) { $OutDir } else { Join-Path $root ("experiments\RUNS\LOAD-$stamp\run") }
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'load-loop.ps1') -Disk $Disk -Kernel $Kernel -Runs $Runs -IntervalSec $IntervalSec -OutDir $d @cdpArgs
        exit $LASTEXITCODE
    }
    'perf' {
        & python (Join-Path $root 'host\perf_run.py') --repeats 5 --tag ('finals-' + $stamp) --disk $Disk --kernel $Kernel --out (Join-Path $root ('evidence\reports\perf-report-' + $stamp + '.json'))
        exit $LASTEXITCODE
    }
    'diagnose' { Invoke-Diagnose }
    'report' { exit (Invoke-Report) }
}
