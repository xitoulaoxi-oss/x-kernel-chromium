<#
.SYNOPSIS
  Boot the x-kernel guest under native Windows QEMU, drive its serial console,
  push whole shell scripts into it, and take measurable screenshots.

.DESCRIPTION
  Why this exists: the project's main forensic harness
  (`guest/*.sh`) is POSIX shell, and this host has
  neither in the sandbox (WSL is refused, msys bash cannot create its signal
  pipe).  The delivered-image path is also Chinese, which Windows PowerShell
  5.1 mangles when it builds a child command line.

  So this harness covers the same ground natively:

    guest console -> -serial tcp:PORT      (bidirectional, marker-terminated)
    guest screen  -> -vnc :N               (watchable, and capturable)
    screendump    -> QMP screendump        (PNG, then measured by screen_stats.py)

  Two deliberate design points:

    1. Every command is terminated by a random marker echoed by the guest, never
       by a timeout guess.  "The command finished" and "the command is slow"
       therefore cannot be confused -- which is exactly the mistake that made
       earlier evidence unreadable.
    2. A screenshot is never treated as proof on its own.  Each capture is
       measured for colour count and dominant-colour fraction by
       `host/screen_stats.py`, and the numbers are written next to the PNG, so
       "the window appeared" is a measurement rather than an impression.

  Paths are resolved relative to the repository root (the parent of host\), so the
  defaults below work from inside the checkout with no extra arguments.

.PARAMETER Kernel
  kernel.bin to boot.  Defaults to `artifacts\kernel-procfs.bin`, then `artifacts\kernel.bin`.

.PARAMETER Script
  One or more local shell files to upload into the guest and run, in order.
  Upload is base64 in small chunks, so a script cannot be corrupted by line
  endings or console flow control.

.PARAMETER Command
  One or more single-line commands to run directly on the guest console,
  interleaved after the scripts.

.PARAMETER AfterScriptWait
  Seconds to keep reading the console after all scripts finish, so
  asynchronous guest output (a browser starting, a crash) is still captured.

.NOTES
  QEMU and Python are discovered rather than hard-coded: `$env:XK_QEMU` /
  `$env:XK_PYTHON` win, then the usual install locations, then PATH.  See README.md
  section 2 for a ready-to-paste acceptance run.

.EXAMPLE
  host\xkwin.ps1 -Script guest\x1-input.sh -Tag PROBE -OutDir runs\PROBE

.EXAMPLE
  host\xkwin.ps1 -Command 'uname -a','cat /etc/inittab' -Tag PROBE -OutDir runs\PROBE
#>
[CmdletBinding()]
param(
    # Positional binding is disabled on purpose.  With `powershell.exe -File`,
    # a [string[]] parameter that receives several values lets the surplus land
    # on whatever positional parameter comes next -- passing two -Script values
    # silently rebound -Disk to the second script, so QEMU was asked to boot a
    # shell script as its kernel and produced an empty console with no error.
    # Every parameter here must be named explicitly.
    [Parameter(Mandatory = $false, Position = 100)][string]$Kernel,
    [Parameter(Mandatory = $false, Position = 101)][string]$Disk,
    # One or MORE scripts, separated by ';'.  Each must stay under the console's
    # reliable heredoc size (see $script:HeredocLimit), which is why several small
    # scripts are the supported way to do more rather than one big one.
    #
    # A ';'-joined SCALAR, not a [string[]]: with `powershell.exe -File` an array
    # parameter that receives several values lets the surplus land on whatever
    # positional parameter comes next -- passing two -Script values silently
    # rebound -Disk to the second script, so QEMU was asked to boot a shell script
    # as its kernel and produced an empty console with no error at all.
    [Parameter(Mandatory = $false, Position = 102)][string]$Script,
    [string[]]$Command = @(),
    # Local files copied into the guest BEFORE the script runs, as
    # "local>remote" pairs (one entry per -Inject).  The '>' separator is used
    # instead of '=' because PowerShell's -File parameter binding treats an '='
    # value as its own stray argument.
    #
    # Files larger than the console's reliable payload are split into chunks and
    # reassembled inside the guest; see Send-GuestLargeFile for why.
    [string[]]$Inject = @(),
    # Skip the in-guest byte-count check for -Inject.  Only for diagnosing the
    # transfer itself; a real run must keep the check, because a truncated page
    # would otherwise render as a plausible but wrong screenshot.
    [switch]$NoInjectVerify,
    [string]$ServeManifest,
    [string]$Display = 'none',
    [string]$Vnc = ':0',
    [string]$Mem = '4G',
    [int]$Smp = 4,
    # Experimental: set TCG translation-block cache size in MiB (QEMU default is RAM-dependent).
    [string]$TbSize = '',
    [int]$BootTimeoutSec = 240,
    [int]$CommandTimeoutSec = 120,
    [int]$AfterScriptWait = 20,
    [string]$SessionStopFile = '',
    [int]$TransferAttempts = 6,
    # Steps sent to the guest AFTER the scripts have finished, one screenshot
    # each, in the order given.  A ';'-joined SCALAR for the same reason -Script
    # is (see above): with `powershell.exe -File` a [string[]] that receives
    # several values arrives as ONE comma-joined string, which is exactly how the
    # first attempt at this sent 'cmd=a,alt+tab@6,cmd=b' to the guest as a
    # single filename.
    #
    # Each entry is either
    #   'name[+name...][@seconds]'  -- a key chord, e.g. 'alt+tab@5', or
    #   'cmd=<guest command>'       -- a guest command, e.g. 'cmd=sh /tmp/x.sh'.
    #
    # Why keys are injected from the host at all: window SWITCHING is an input
    # action, and this guest has no xdotool/wmctrl, so the keystroke has to come
    # from outside.  QMP is already connected (screendump uses it) and send-key
    # goes through the virtio keyboard the X server grabs, so what gets measured
    # is the same chord a human would press.  Interleaving cmd= with keys is what
    # makes the switch observable: a reading has to be taken BETWEEN keystrokes.
    [string]$Key = '',
    # Scripts to put IN the guest WITHOUT running them, ';'-joined.  A latency
    # measurement has to start the browser at a known instant, so the launcher
    # cannot be paid for (upload + verify) inside the measured window: stage it
    # here, fire it from -FrameWatchCmd below.
    [string]$Upload = '',
    # Protocol test switch: force the console-heredoc transport even though the
    # staging HTTP server is running.  Production runs leave this off.
    [switch]$NoHttpUpload,
    # Frame watch, as 'interval_seconds x duration_seconds' (e.g. '2x100').
    # While it runs a screendump is taken every interval and BOTH the request and
    # the completion instant are recorded, so page-load latency is measured off
    # the framebuffer -- the channel the task book prescribes for evidence --
    # instead of inferred from a log line.
    [string]$FrameWatch = '',
    # Guest command dispatched at t=0 of the frame watch and deliberately NOT
    # awaited: the browser has to be starting while frames are being captured.
    [string]$FrameWatchCmd = '',
    # QEMU -d mask for interrupt/timer tracing (e.g. 'int').  Diagnostic runs
    # only: the log is written next to the session and its tail is preserved on
    # failure.
    [string]$QemuDebug = '',
    # Diagnostic memory-export probe: copy a small record to a space-free temp
    # path and have QEMU's loader place it at an explicit guest physical
    # address.  Host reads it through QMP, never through the guest shell.
    [string]$LoadRecordFile = '',
    [string]$LoadRecordAddr = '',
    # Colour-count sanity floor handed to frame_stats.py.  It is NOT the paint
    # test on its own: a blank white page with a "Loading..." spinner has 264
    # colours from the tab bar and toolbar, while the rendered committee page has
    # 835.  The paint test is the saturation floor inside frame_stats.py; this is
    # the second, weaker condition.
    [int]$FrameThreshold = 300,
    # Startup readiness gate (off by default: -StartupReadyColors 300 turns it on).
    # After the scripts, poll the framebuffer; if it has no content, send a real
    # Ctrl+R and poll again, up to -StartupReadyMax navigation attempts.  Every
    # attempt, the FIRST failure and the total wait go to startup-ready.json, so
    # the retry is visible instead of hidden.  The predicate lives in
    # host/ready-gate.ps1 and has its own regression test.
    [int]$StartupReadyColors = 0,
    [int]$StartupReadyMax = 3,
    [int]$StartupReadyWaitSec = 20,
    [int]$StartupReadyPollSec = 5,
    # Guest launcher re-run when the restart retry fires (no window at all).
    [string]$StartupReadyLauncher = '/tmp/xk-x4-win1.sh',
    # Absolute-schedule load loop: "<count>x<interval>@<start>" in seconds, e.g.
    # "10x120@60".  Each trigger is a real Ctrl+R at its planned monotonic time;
    # the frame is then polled until it is ready again, so "the reload happened"
    # is not confused with "the page came back".  Writes load-schedule.json.
    [switch]$EnableGuestCdp,
    [switch]$CdpTrace,
    # Read-only host-side traces, even when guest sleep/serial progress stops.
    [ValidateRange(0, 3600)][int]$DiagnosticPollSec = 0,
    [string]$CdpEndpoint = '',
    [string]$ExpectedPageUrl = 'file:///usr/share/kiosk/official/index.html',
    [ValidateSet('', 'page', 'js', 'css', 'input')][string]$PageProbeMode = '',
    [string]$ExpectedInputText = 'hello x-kernel',
    [switch]$CollectBrowserProcesses,
    [string]$LoadSchedule = '',
    # Keep the session alive until this many seconds from the schedule start
    # (used by the 30-minute run after the last load).
    [int]$LoadHoldSec = 0,
    [int]$LoadReadyColors = 300,
    [string]$Tag = 'xkwin',
    [string]$OutDir,
    [switch]$Writable,
    # Leave the guest running when the harness exits, so the session can be driven
    # and recorded by hand.  This suppresses the QMP `quit` as well as the process
    # kill: sending quit is what actually stops the guest, so a -Keep that only
    # skipped the kill still closed the window a few minutes into a session.
    [switch]$Keep,
    # Delivery tests need 0 and non-zero command results in one session.  This
    # only suppresses the throw for cmd= steps; the rc is still recorded.
    [switch]$TolerantCommands,
    [string[]]$ExtraArg = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:harnessExitCode = 0
$script:diagnosticTraceSeq = 0
$script:uploadedRemotes = @{}
if ($EnableGuestCdp -and $Writable) { throw 'CDP policy adjustment requires a QEMU snapshot; Writable is not allowed.' }
if (($LoadSchedule -or $PageProbeMode) -and -not $CdpEndpoint -and -not $EnableGuestCdp) {
    throw 'Semantic verification requires an explicitly configured local -CdpEndpoint; color count cannot prove success.'
}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$ws = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..'))
. (Join-Path $scriptDir 'ready-gate.ps1')
. (Join-Path $scriptDir 'command-result.ps1')
. (Join-Path $scriptDir 'step-spec.ps1')
. (Join-Path $scriptDir 'guest-paths.ps1')
. (Join-Path $scriptDir 'staging.ps1')

# All paths below are ASCII on purpose: PowerShell 5.1 encodes a child process
# command line with the system ANSI code page, so a non-ASCII path would reach
# QEMU as mojibake.  The packaged kernels live in artifacts/, which is ASCII.
if (-not $Kernel) {
    $kernelCandidates = @(
        (Join-Path $ws 'artifacts\kernel-procfs.bin'),
        (Join-Path $ws 'artifacts\kernel-keepalive.bin'),
        (Join-Path $ws 'artifacts\kernel.bin')
    )
    $Kernel = $kernelCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Disk) {
    # The delivered image is LOOKED UP rather than assumed.  In the packaged
    # layout it sits in a sibling directory whose name is non-ASCII, and that
    # name must not be embedded here: PowerShell 5.1 reads a .ps1 file as ANSI
    # when it has no BOM, so a Chinese literal would arrive as mojibake.
    $diskCandidates = @(
        (Join-Path $ws 'disk\agentos-disk.img'),
        (Join-Path $ws 'artifacts\agentos-disk.img'),
        (Join-Path $ws '..\delivered\agentos-disk.img')
    )
    $parent = Split-Path -Parent $ws
    if (Test-Path -LiteralPath $parent) {
        $diskCandidates += @(
            Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName 'agentos-disk.img' }
        )
    }
    $Disk = $diskCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $OutDir) { $OutDir = Join-Path $ws ("runs\{0}-{1}" -f $Tag, (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')) }

$Kernel = [System.IO.Path]::GetFullPath($Kernel)
$Disk   = [System.IO.Path]::GetFullPath($Disk)
$OutDir = [System.IO.Path]::GetFullPath($OutDir)

# QEMU on Windows fails to open a -kernel path containing spaces even when the
# argument is quoted: it receives only the tail after the space.  Copy the
# kernel to a space-free temp path before launching QEMU.
if ($Kernel -match ' ') {
    $tmpRoot = Join-Path $env:TEMP 'xk-kernel'
    if ($tmpRoot -match ' ') {
        throw "temporary path contains a space: $tmpRoot; set TEMP to a space-free directory"
    }
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    $tmpKernel = Join-Path $tmpRoot ([System.IO.Path]::GetFileName($Kernel))
    Copy-Item -LiteralPath $Kernel -Destination $tmpKernel -Force
    $Kernel = $tmpKernel
}

# Guard against the parameter-binding trap described above: if a script or other
# stray argument ever lands in -Kernel again, fail here with a clear message
# instead of letting QEMU boot it and print nothing at all.
if ($Kernel -match '\.(sh|ps1|txt|md)$') {
    throw "refusing to boot '$Kernel' as a kernel: it looks like a script/text file, not kernel.bin (a mis-bound argument?)"
}

# --- external prerequisites, discovered rather than assumed -------------------
#
# Both of these used to be single hard-coded paths (this machine's QEMU install
# and this machine's bundled Python).  On any other machine that is an immediate
# dead end, so each is now looked up in order of preference and the failure message
# says exactly what was tried and what to set.

function Resolve-FirstExisting {
    param([string[]]$Candidates, [string]$What)
    foreach ($c in $Candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

# Both are declared here so the checks below cannot hit an unset variable: under
# $ErrorActionPreference='Stop' a bare `if (-not $Qemu)` on an undefined name is a
# terminating error, not a falsy test.
#
# An explicit $env:XK_QEMU is authoritative: if it is set but wrong, say so rather
# than quietly booting some other QEMU the caller did not ask for.
$Qemu = $null
if ($env:XK_QEMU) {
    if (-not (Test-Path -LiteralPath $env:XK_QEMU)) {
        throw "XK_QEMU is set to '$env:XK_QEMU' but that file does not exist."
    }
    $Qemu = $env:XK_QEMU
} else {
    $Qemu = Resolve-FirstExisting -What 'QEMU' -Candidates @(
        (Join-Path $env:ProgramFiles 'qemu\qemu-system-aarch64.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'qemu\qemu-system-aarch64.exe'),
        (Join-Path $ws 'tools\qemu\qemu-system-aarch64.exe')
    )
}
if (-not $Qemu) {
    $onPath = Get-Command qemu-system-aarch64.exe -ErrorAction SilentlyContinue
    if ($onPath) { $Qemu = $onPath.Source }
}
if (-not $Qemu) {
    throw ("QEMU not found. Tried:`n" +
           "  `$env:XK_QEMU`n" +
           "  $env:ProgramFiles\qemu\qemu-system-aarch64.exe`n" +
           "  ${env:ProgramFiles(x86)}\qemu\qemu-system-aarch64.exe`n" +
           "  $ws\tools\qemu\qemu-system-aarch64.exe`n" +
           "  PATH`n" +
           "Install QEMU (>= 8.0, aarch64) or set `$env:XK_QEMU to the executable.")
}

# Python runs screen_stats.py and the upload server.  Order: explicit env var, the
# bundled runtime this project used, then anything named python on PATH.  Like QEMU,
# a set-but-wrong XK_PYTHON is an error rather than something to route around.
$py = $null
if ($env:XK_PYTHON) {
    if (-not (Test-Path -LiteralPath $env:XK_PYTHON)) {
        throw "XK_PYTHON is set to '$env:XK_PYTHON' but that file does not exist."
    }
    $py = $env:XK_PYTHON
} else {
    $py = Resolve-FirstExisting -What 'Python' -Candidates @(
        (Join-Path $env:USERPROFILE '.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'),
        (Join-Path $ws 'tools\python\python.exe')
    )
}
if (-not $py) {
    foreach ($name in @('python.exe', 'python3.exe')) {
        $onPath = Get-Command $name -ErrorAction SilentlyContinue
        if ($onPath) { $py = $onPath.Source; break }
    }
}
if (-not $py) {
    throw ("Python 3 not found (needed for screen_stats.py). Tried:`n" +
           "  `$env:XK_PYTHON`n" +
           "  $env:USERPROFILE\.dsh\dsh-runtimes\...\python.exe`n" +
           "  PATH (python.exe, python3.exe)`n" +
           "Set `$env:XK_PYTHON to a python.exe.")
}

$statsTool = Join-Path $scriptDir 'screen_stats.py'
$frameTool = Join-Path $scriptDir 'frame_stats.py'

# Host physical memory, asked of kernel32 rather than of WMI/CIM.
#
# Why a P/Invoke: on this host Get-CimInstance answers "access denied" and wmic
# does not exist at all (both recorded in docs/verification.md), so the only probe that
# actually returns is GlobalMemoryStatusEx.  The number is needed because the
# task book also asks for a "QEMU memory occupancy rate": a rate needs a
# denominator, and a measured numerator over an assumed denominator is not a
# measurement.  A failed probe leaves $null, and the report then says
# "not measured" rather than inventing a ratio.
$script:hostRamBytes = $null
try {
    if (-not ('XKMemProbe' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct XKMEMSTATUSEX {
    public uint dwLength; public uint dwMemoryLoad;
    public ulong ullTotalPhys; public ulong ullAvailPhys;
    public ulong ullTotalPageFile; public ulong ullAvailPageFile;
    public ulong ullTotalVirtual; public ulong ullAvailVirtual;
    public ulong ullAvailExtendedVirtual;
}
public static class XKMemProbe {
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GlobalMemoryStatusEx(ref XKMEMSTATUSEX lpBuffer);
    public static ulong TotalPhys() {
        XKMEMSTATUSEX m = new XKMEMSTATUSEX();
        m.dwLength = (uint)Marshal.SizeOf(typeof(XKMEMSTATUSEX));
        if (!GlobalMemoryStatusEx(ref m)) { return 0; }
        return m.ullTotalPhys;
    }
}
'@ -ErrorAction Stop
    }
    $b = [XKMemProbe]::TotalPhys()
    if ($b -gt 0) { $script:hostRamBytes = [int64]$b }
} catch {
    Write-Host ("  !! host physical memory unavailable: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
}

if (-not (Test-Path -LiteralPath $Kernel)) { throw "kernel not found: $Kernel (pass -Kernel <path>; e.g. artifacts\kernel-procfs.bin)" }
if (-not (Test-Path -LiteralPath $Disk)) { throw "disk not found: $Disk (pass -Disk <path>, or place agentos-disk.img in disk\ or next to this package)" }
if (-not (Test-Path -LiteralPath $statsTool)) { throw "screen_stats.py not found next to this script: $statsTool" }
if ($FrameWatch -and -not (Test-Path -LiteralPath $frameTool)) { throw "frame_stats.py not found next to this script: $frameTool" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# Guest RAM in MB, parsed from the same -Mem string QEMU is handed.  This is the
# second denominator a memory-occupancy rate needs (share of the VM's own
# memory); it is recorded in the run's sidecar so the ratio can be recomputed
# from the evidence without re-reading this command line.
$guestMemMb = $null
if ($Mem -match '^\s*(\d+)\s*([KMG]?)\s*$') {
    $memVal = [double]$Matches[1]
    switch ($Matches[2].ToUpperInvariant()) {
        'K' { $guestMemMb = $memVal / 1024 }
        'M' { $guestMemMb = $memVal }
        'G' { $guestMemMb = $memVal * 1024 }
        default { $guestMemMb = $memVal / (1024 * 1024) }
    }
    $guestMemMb = [math]::Round($guestMemMb, 1)
}

$consoleLog = Join-Path $OutDir 'console.log'
$qemuLog    = Join-Path $OutDir 'qemu.stdout.log'
$qemuErr    = Join-Path $OutDir 'qemu.stderr.log'
$cmdFile    = Join-Path $OutDir 'qemu-cmd.txt'
$script:txSeq = 0
$script:txTracePath = Join-Path $OutDir 'tx-trace.jsonl'

function Write-TxEvent {
    param($Event)
    try {
        ($Event | ConvertTo-Json -Compress -Depth 4) | Add-Content -LiteralPath $script:txTracePath -Encoding utf8
    } catch { }
}

function Get-FreePort {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $l.Start(); $p = ([System.Net.IPEndPoint]$l.LocalEndpoint).Port; $l.Stop()
    return $p
}

$serialPort = Get-FreePort
$qmpPort    = Get-FreePort

$netConfig = 'user,id=net0'
if ($EnableGuestCdp) {
    $cdpPort = Get-FreePort
    $netConfig += ',hostfwd=tcp:127.0.0.1:' + $cdpPort + '-:9223'
    $CdpEndpoint = 'http://127.0.0.1:' + $cdpPort
}
$accel = if ($TbSize) { "tcg,tb-size=$TbSize" } else { 'tcg' }
$argv = @(
    '-M', 'virt', '-cpu', 'cortex-a72', '-m', $Mem, '-smp', "$Smp", '-accel', $accel,
    '-kernel', $Kernel,
    '-drive', "id=disk0,if=none,format=raw,file=$Disk",
    '-device', 'virtio-blk-pci,drive=disk0',
    '-device', 'virtio-gpu-pci', '-vga', 'none',
    '-device', 'virtio-keyboard-pci', '-device', 'virtio-mouse-pci',
    '-netdev', $netConfig, '-device', 'virtio-net-pci,netdev=net0',
    '-serial', "tcp:127.0.0.1:$serialPort,server=on,wait=off",
    '-qmp', "tcp:127.0.0.1:$qmpPort,server=on,wait=off",
    '-monitor', 'none',
    '-display', $Display,
    '-no-reboot'
)
if ($LoadRecordFile) {
    if (-not $LoadRecordAddr) { throw '-LoadRecordFile requires -LoadRecordAddr' }
    if (-not (Test-Path -LiteralPath $LoadRecordFile)) { throw "record not found: $LoadRecordFile" }
    $recordTemp = Join-Path $env:TEMP ("xk-record-{0}.bin" -f $Tag)
    Copy-Item -LiteralPath $LoadRecordFile -Destination $recordTemp -Force
    $argv += @('-device', ("loader,file=$recordTemp,addr=$LoadRecordAddr,force-raw=on"))
}
if ($QemuDebug) {
    $dbgPath = Join-Path $OutDir 'qemu-debug.log'
    if (-not [IO.Path]::IsPathRooted($dbgPath)) { $dbgPath = Join-Path (Get-Location).Path $dbgPath }
    $dbgPath = [IO.Path]::GetFullPath($dbgPath)
    # Start-Process joins ArgumentList with spaces, so a path containing a space
    # must carry its own quotes or QEMU sees only the first token.
    $argv += @('-d', $QemuDebug, '-D', ('"' + $dbgPath + '"'))
}
if (-not $Writable) { $argv += '-snapshot' }
if ($Vnc) { $argv += @('-vnc', $Vnc) }
$argv += $ExtraArg

# Keep the exact command line in the evidence directory: it is a deliverable in
# its own right ("运行命令" is explicitly required by the task book).
($argv | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ' |
    Set-Content -LiteralPath $cmdFile -Encoding ascii

Write-Host '== xkwin (Windows-native guest harness) ==' -ForegroundColor Cyan
Write-Host "  kernel  : $Kernel"
Write-Host "  disk    : $Disk$(if ($Writable) { ' (WRITABLE)' } else { ' (-snapshot)' })"
Write-Host "  display : $Display$(if ($Vnc) { "  +  vnc $Vnc (port $((5900 + [int]($Vnc -replace ':', ''))))" })"
Write-Host "  console : tcp 127.0.0.1:$serialPort"
Write-Host "  qmp     : tcp 127.0.0.1:$qmpPort"
Write-Host "  output  : $OutDir"
Write-Host ''

$proc = Start-Process -FilePath $Qemu -ArgumentList $argv -PassThru -NoNewWindow `
    -RedirectStandardOutput $qemuLog -RedirectStandardError $qemuErr

$utf8 = [System.Text.UTF8Encoding]::new($false)
$owner = [pscustomobject]@{
    pid = $proc.Id
    started_utc = $proc.StartTime.ToUniversalTime().ToString('o')
    executable = $Qemu
}
[System.IO.File]::WriteAllText((Join-Path $OutDir 'qemu-owner.json'), ($owner | ConvertTo-Json), $utf8)
$script:buf = [System.Text.StringBuilder]::new()
# The log is a byte stream, not a text stream: the guest's raw bytes are kept
# exactly as received, including anything that is not valid UTF-8.
$script:logRaw = [System.IO.FileStream]::new($consoleLog, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
# Set-StrictMode rejects reading an undefined variable, and QMP capabilities
# must be negotiated exactly once per connection, so this is pre-declared.
$script:qmpReady = $false
$script:guestHttp = ''
# Ceiling for a single-heredoc script transfer.
#
# Measured on this console, repeatedly: 704 B and ~1.6 KB arrive byte-exact, while
# 2.1 KB and up leave the console answering nothing, and a 2-4 KB heredoc whose
# body contains quotes and `$` gets its tail spliced into the following command
# (observed: `head -c 2093 .../x.xtmp > .../xk-91-verbosre-x.sh`, filename changed
# and redirection targets merged).  The limit is therefore set at the top of what
# has been proven rather than at what would be convenient, and exceeding it is a
# hard error -- the right response is to split the script, not to raise this.
$script:HeredocLimit = 1792
$client = $null
$qmp = $null
$uploadServer = $null

function Write-GuestText {
    <#  Record guest output, decoded lossily.

        The guest emits raw bytes, not text: kernel log lines carry ANSI colour
        escapes and a crashing process can put arbitrary bytes on the console.
        `UTF8Encoding` throws on those by default, and an exception thrown inside
        the read loop aborts it silently -- which is exactly how an entire
        script's output disappeared with no error.  Decoding with replacement
        characters keeps the read loop alive, and the raw bytes still go to the
        log file so nothing is actually lost. #>
    param([byte[]]$Bytes)
    $text = [System.Text.Encoding]::UTF8.GetString($Bytes)
    [void]$script:buf.Append($text)
    $script:logRaw.Write($Bytes, 0, $Bytes.Length)
    $script:logRaw.Flush()
    Write-Host -NoNewline $text
}

function Read-Available {
    param([int]$QuietMs = 700, [int]$MaxMs = 8000)
    if (-not $client) { return }
    $stream = $client.GetStream()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastData = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalMilliseconds -lt $MaxMs) {
        if ($stream.DataAvailable) {
            $tmp = New-Object byte[] 65536
            $n = $stream.Read($tmp, 0, $tmp.Length)
            if ($n -gt 0) {
                $slice = New-Object byte[] $n
                [Array]::Copy($tmp, $slice, $n)
                Write-GuestText -Bytes $slice
                $lastData.Restart()
            }
        } else {
            if ($lastData.Elapsed.TotalMilliseconds -ge $QuietMs) { break }
            Start-Sleep -Milliseconds 100
        }
    }
}

function Wait-Console {
    param([string]$Pattern, [int]$TimeoutSec = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($proc.HasExited) { return $false }
        Read-Available -QuietMs 700 -MaxMs 2000
        if ($script:buf.ToString() -match $Pattern) { return $true }
    }
    return $false
}

function Send-Guest {
    param([string]$Text)
    $bytes = $utf8.GetBytes($Text)
    $client.GetStream().Write($bytes, 0, $bytes.Length)
    $client.GetStream().Flush()
}

function Wait-Port {
    <#  Connect to a chardev listening port.  A failed connect is expected while
        QEMU is still starting, so this retries; QEMU dying is not, so that is
        reported with its stderr instead of being retried into a timeout. #>
    param([int]$Port, [int]$TimeoutSec = 30, [System.Diagnostics.Process]$Proc)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($Proc -and $Proc.HasExited) {
            $why = ''
            if (Test-Path -LiteralPath $qemuErr) { $why = Get-Content -LiteralPath $qemuErr -Raw }
            throw "QEMU exited before port $Port opened. stderr: $why"
        }
        try {
            $c = [System.Net.Sockets.TcpClient]::new()
            $c.Connect('127.0.0.1', $Port)
            return $c
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    throw "timed out waiting for QEMU port $Port"
}

function Invoke-GuestCommand {
    <#  Run one line on the guest console and wait for ITS end marker.

        The marker is not a decoration.  A console read has no framing of its
        own, so "the guest went quiet" cannot distinguish a finished command
        from a slow one -- and an earlier version of this function used exactly
        that test, stopping after a 2.5 s quiet window.  A command that then ran
        for minutes had all of its output read as if it belonged to the *next*
        step (or to nothing at all), which is how a whole diagnostic script
        produced an empty result file with no error anywhere.

        So: keep reading until the marker line appears, and only then return.
        The overall timeout is the backstop, not the primary condition. #>
    param([string]$Text, [int]$TimeoutSec = 120, [string]$Label, [switch]$Quiet, [switch]$AllowFailure)
    if (-not $Label) { $Label = $Text }
    $nonce = 'XK{0}' -f (Get-Random -Minimum 1000000 -Maximum 9999999)
    if (-not $Quiet) { Write-Host "`n--- guest$ $Label" -ForegroundColor Yellow }
    # Drain any pending prompt/echo before writing, so the target line starts at
    # a command boundary.  The 25 ms target/marker gap was too short: a real B3
    # run received the marker as `eecho`, not because the target command failed.
    [void](Read-Available -QuietMs 80 -MaxMs 400)
    $before = $script:buf.Length
    $script:txSeq++
    $txSeq = $script:txSeq
    $txStart = [System.Diagnostics.Stopwatch]::StartNew()
    $marker = "__xk_rc=`$?; echo `$__xk_rc > /tmp/xk-rc-$nonce; echo __${nonce}__rc=`$__xk_rc"
    Send-Guest ("$Text`n")
    Start-Sleep -Milliseconds 100
    Send-Guest ("$marker`n")
    Write-TxEvent @{
        seq = $txSeq; direction = 'tx'; nonce = $nonce; label = $Label
        text_bytes = $utf8.GetByteCount($Text); marker_bytes = $utf8.GetByteCount($marker)
        text = $Text; marker = $marker
        at_utc = (Get-Date).ToUniversalTime().ToString('o')
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $found = $false
    $detail = $null
    $nextDiagnostic = (Get-Date).AddSeconds($DiagnosticPollSec)
    while ((Get-Date) -lt $deadline) {
        Read-Available -QuietMs 400 -MaxMs 1500
        if ($DiagnosticPollSec -gt 0 -and (Get-Date) -ge $nextDiagnostic) {
            $script:diagnosticTraceSeq++
            $requests = @{
                status = @{ execute = 'query-status' }
                registers = @{ execute = 'human-monitor-command'; arguments = @{ 'command-line' = 'info registers -a' } }
            }
            foreach ($traceName in @('status', 'registers')) {
                $traceReply = Invoke-Qmp -Command ($requests[$traceName] | ConvertTo-Json -Depth 4 -Compress) -TimeoutMs 1500
                $trace = @{ observed_utc = (Get-Date).ToUniversalTime().ToString('o'); guest_command = $Label; raw_qmp_reply = $traceReply }
                Save-Evidence ('diagnostic-{0:d3}-{1}.json' -f $script:diagnosticTraceSeq, $traceName) ($trace | ConvertTo-Json -Depth 4) | Out-Null
            }
            $nextDiagnostic = (Get-Date).AddSeconds($DiagnosticPollSec)
        }
        $tail = $script:buf.ToString($before, $script:buf.Length - $before)
        $detail = Get-GuestCommandResultDetail -Transcript $tail -Nonce $nonce
        if ($detail.status -in @('ok', 'malformed', 'conflict')) { $found = $true; break }
        if ($proc.HasExited) { break }
    }
    $tail = $script:buf.ToString($before, $script:buf.Length - $before)
    $detail = Get-GuestCommandResultDetail -Transcript $tail -Nonce $nonce -AtEnd
    $txStart.Stop()
    Write-TxEvent @{
        seq = $txSeq; direction = 'rx'; nonce = $nonce; label = $Label
        status = $detail.status; rc = $detail.rc; elapsed_ms = [math]::Round($txStart.Elapsed.TotalMilliseconds, 1)
        raw_line = $detail.line
    }
    if ($detail.status -eq 'malformed' -or $detail.status -eq 'conflict') {
        throw "Guest command completion frame is invalid ($($detail.status)): $Label; raw=$($detail.line)"
    }
    if ($detail.status -eq 'pending') {
        throw "Guest command completion frame did not terminate before timeout (protocol incomplete): $Label"
    }
    if ($detail.status -ne 'ok') {
        throw "Guest command did not complete: $Label (timeout ${TimeoutSec}s)"
    }
    $commandRc = $detail.rc
    if ($commandRc -ne 0 -and -not $AllowFailure) { throw "Guest command failed with exit ${commandRc}: $Label" }
    if ($Quiet) { return $tail }
    Write-Host ("    [rc={0}]" -f $commandRc) -ForegroundColor DarkGray
    return $tail
}

function Save-Evidence {
    param([string]$Name, [string]$Text)
    $p = Join-Path $OutDir $Name
    [System.IO.File]::WriteAllText($p, $Text, $utf8)
    return $p
}

function Invoke-Qmp {
    <#  Send one QMP command and read its reply.

        The reply MUST be consumed before the next command is written.  Sending
        `qmp_capabilities` and `screendump` back to back without reading in
        between silently loses the screendump: QMP answers the first command and
        the second is rejected while capabilities are still un-negotiated, which
        looks exactly like "screendump is unsupported". #>
    param([string]$Command, [int]$TimeoutMs = 8000)
    if (-not $qmp) { return $null }
    $s = $qmp.GetStream()
    $s.ReadTimeout = $TimeoutMs
    $b = $utf8.GetBytes($Command + "`n")
    $s.Write($b, 0, $b.Length); $s.Flush()
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    $text = ''
    $buf = New-Object byte[] 65536
    while ((Get-Date) -lt $deadline) {
        try {
            if ($s.DataAvailable) {
                $n = $s.Read($buf, 0, $buf.Length)
                if ($n -gt 0) { $text += $utf8.GetString($buf, 0, $n) }
                # One complete reply line is enough for every command used here.
                if ($text -match '\}\s*\r?\n') { break }
            } else {
                Start-Sleep -Milliseconds 50
            }
        } catch { break }
    }
    return $text
}

function Send-QmpKey {
    <#  Press a key combination in the guest through QMP.

        send-key takes QKeyCode names, not X keysyms, so the names are passed
        through almost verbatim; only the handful that differ between the two
        vocabularies are translated here.  All keys in one call are held
        together and released together, which is what makes 'alt+tab' a real
        modifier+key chord rather than two unrelated presses. #>
    param([string]$Spec, [int]$HoldMs = 120)
    $keys = @()
    foreach ($n in ($Spec -split '\+')) {
        $q = $n.Trim().ToLowerInvariant()
        if (-not $q) { continue }
        switch ($q) {
            'win'     { $q = 'meta_l' }
            'super'   { $q = 'meta_l' }
            'enter'   { $q = 'ret' }
            'return'  { $q = 'ret' }
            'space'   { $q = 'spc' }
            'escape'  { $q = 'esc' }
            'delete'  { $q = 'delete' }
        }
        $keys += ('{"type":"qcode","data":"' + $q + '"}')
    }
    if ($keys.Count -eq 0) { return $null }
    $json = '{"execute":"send-key","arguments":{"keys":[' + ($keys -join ',') +
            '],"hold-time":' + $HoldMs + '}}'
    return Invoke-Qmp -Command $json
}

function Read-PageEvidence([string]$Name, [string]$Mode = 'page') {
    $out = Join-Path $OutDir ($Name + '.json')
    & $py (Join-Path $scriptDir 'page_probe.py') --endpoint $CdpEndpoint --expected-url $ExpectedPageUrl --mode $Mode --expected-text $ExpectedInputText --out $out | Out-Null
    if (-not (Test-Path -LiteralPath $out)) { return $null }
    return Get-Content -LiteralPath $out -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Send-QmpMouseRel {
    <#  Move the RELATIVE pointer by (Dx,Dy) in guest pixels.

        The guest only has virtio-mouse-pci (the x-kernel virtio-input driver has
        no EV_ABS support, so a tablet would be ignored).  Absolute screen
        positions are therefore built by clamping the pointer at the top-left
        with a large negative move and then walking to the target in small
        steps -- a large single jump would be scaled by libinput's pointer
        acceleration and miss the target. #>
    param([int]$Dx, [int]$Dy)
    $events = @()
    if ($Dx -ne 0) { $events += ('{"type":"rel","data":{"axis":"x","value":' + $Dx + '}}') }
    if ($Dy -ne 0) { $events += ('{"type":"rel","data":{"axis":"y","value":' + $Dy + '}}') }
    if ($events.Count -eq 0) { return $null }
    return Invoke-Qmp -Command ('{"execute":"input-send-event","arguments":{"events":[' + ($events -join ',') + ']}}')
}

function Send-QmpMouseButton {
    param([bool]$Down)
    $d = if ($Down) { 'true' } else { 'false' }
    return Invoke-Qmp -Command ('{"execute":"input-send-event","arguments":{"events":[{"type":"btn","data":{"down":' + $d + ',"button":"left"}}]}}')
}

function Send-QmpMouseClick {
    param([int]$X, [int]$Y, [int]$Step = 4, [int]$StepMs = 12)
    [void](Send-QmpMouseRel -Dx -4000 -Dy -4000)
    Start-Sleep -Milliseconds 150
    $left = [Math]::Max(0, $X)
    $top = [Math]::Max(0, $Y)
    while ($left -gt 0 -or $top -gt 0) {
        $sx = [Math]::Min($Step, $left)
        $sy = [Math]::Min($Step, $top)
        [void](Send-QmpMouseRel -Dx $sx -Dy $sy)
        $left -= $sx
        $top -= $sy
        Start-Sleep -Milliseconds $StepMs
    }
    Start-Sleep -Milliseconds 120
    [void](Send-QmpMouseButton -Down $true)
    Start-Sleep -Milliseconds 90
    [void](Send-QmpMouseButton -Down $false)
}

function Send-QmpText {
    <#  Type printable ASCII through the virtio keyboard, one real key at a time. #>
    param([string]$Text, [int]$HoldMs = 40)
    $map = @{
        ' ' = 'spc'; '-' = 'minus'; '.' = 'dot'; ',' = 'comma'; '/' = 'slash';
        '_' = 'shift+minus'; ':' = 'shift+semicolon'; '=' = 'equal';
        '!' = 'shift+1'; '?' = 'shift+slash'; '@' = 'shift+2'
    }
    foreach ($ch in $Text.ToCharArray()) {
        $s = [string]$ch
        if ($s -cmatch '^[a-z0-9]$') { $spec = $s }
        elseif ($s -cmatch '^[A-Z]$') { $spec = 'shift+' + $s.ToLowerInvariant() }
        elseif ($map.ContainsKey($s)) { $spec = $map[$s] }
        else { continue }
        [void](Send-QmpKey -Spec $spec -HoldMs $HoldMs)
        Start-Sleep -Milliseconds 40
    }
}

function Start-UploadServer {
    <#  Serve the run's staging directory over HTTP for the guest to pull from.

        Why not push the bytes down the console: base64 chunking needs a round
        trip per ~45 bytes, and every chunk's echo competes with the console's
        command markers -- which is how an earlier version managed to corrupt a
        transfer silently.  QEMU's user-mode network gives the guest a host
        address at 10.0.2.2, so the guest pulling is both faster and verifiable.

        Why Start-Process with file redirection rather than Start-Job: a
        PowerShell job captures its output through a pipe, and this sandbox
        refuses named pipes.  A job therefore dies the moment the server tries
        to log a request, the port stops answering, and the guest's wget comes
        back with zero bytes -- with no error anywhere on the host.  Redirecting
        to files avoids pipes entirely. #>
    param([string]$Root, [string]$StageDir)
    New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
    # Python's http.server is launched through Start-Process, which joins the
    # argument list with spaces; a staging path containing spaces therefore
    # arrives split.  Serve from a space-free temp copy instead.
    $serveDir = $StageDir
    if ($StageDir -match ' ') {
        $serveDir = Join-Path $env:TEMP ('xk-stage-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $serveDir | Out-Null
        Copy-Item -Path (Join-Path $StageDir '*') -Destination $serveDir -Recurse -Force
    }
    if ($serveDir -match ' ') { throw "upload stage path contains a space: $serveDir" }
    $stdout = Join-Path $Root 'uploadserver.log'
    $stderr = Join-Path $Root 'uploadserver.err.log'
    # Bound only for this run, and on all interfaces because slirp reaches the
    # host through its gateway address rather than loopback.
    $port = Get-FreePort
    $proc = Start-Process -FilePath $py `
        -ArgumentList @('-m', 'http.server', "$port", '--bind', '0.0.0.0', '--directory', $serveDir) `
        -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Start-Sleep -Milliseconds 1500
    if ($proc.HasExited) {
        $why = ''
        if (Test-Path -LiteralPath $stderr) { $why = Get-Content -LiteralPath $stderr -Raw }
        throw "upload server exited immediately: $why"
    }
    # Prove it answers before any guest depends on it: a server that is merely
    # *started* is not the same as a server that *serves*, and that difference is
    # invisible from the guest's side.  The canary file makes this check run even
    # when nothing has been staged yet -- otherwise the one case where the server
    # is broken is also the case where nothing verifies it.
    $canary = Join-Path $serveDir '_server-canary.txt'
    Set-Content -LiteralPath $canary -Value 'canary-ok' -Encoding ascii
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$port/_server-canary.txt" -UseBasicParsing -TimeoutSec 10
        if ($resp.Content -notmatch 'canary-ok') { throw "unexpected body: $($resp.Content)" }
        Write-Host "  upload server verified: http://10.0.2.2:$port/ (guest view)" -ForegroundColor Green
    } catch {
        $why = ''
        if (Test-Path -LiteralPath $stderr) { $why = (Get-Content -LiteralPath $stderr -Raw) }
        throw "upload server did not answer on 127.0.0.1:$port : $_  stderr=$why"
    }
    Remove-Item -LiteralPath $canary -Force -ErrorAction SilentlyContinue
    $files = @(Get-ChildItem -LiteralPath $serveDir -File -ErrorAction SilentlyContinue)
    Write-Host "  staged for the guest ($($files.Count)): $(($files | Select-Object -ExpandProperty Name) -join ', ')" -ForegroundColor DarkGray
    return [pscustomobject]@{ Proc = $proc; Port = $port; StageDir = $StageDir; ServeDir = $serveDir }
}

function Stop-UploadServer {
    param($Server)
    if (-not $Server) { return }
    try { if ($Server.Proc -and -not $Server.Proc.HasExited) { $Server.Proc.Kill() } } catch { }
}

function Send-GuestScriptFile {
    <#  Put a local shell script INTO the guest (heredoc, verified) and stop there.

        Split out of Send-GuestScriptInline because a latency measurement has to
        fire the browser at a known instant: paying for the upload and its
        verification inside the measured window would add console time to the
        number.  -Upload stages a file with this function, and -FrameWatchCmd
        later runs it with a single console line.

        Why this transport exists at all: the obvious ones are both unavailable
        here.

        Why this exists at all: the obvious transports are both unavailable here.
        Transport order, decided by measurement rather than by preference:

          1. HTTP from the run's own staging server, verified by SHA-256.  The
             guest CAN reach it -- guest/06-fetch-pages.sh pulls three pages the
             same way every run -- and a hash comparison is exact.  A batch run
             once delivered a 1,534-byte script as 0 bytes three times in a row,
             and another delivered an 840-byte script with the right LENGTH and
             spliced content; neither failure can survive a hash check.
          2. The console heredoc below, kept as the fallback for runs that have
             no -ServeManifest (and the only path that needs no network).

        What does work is what the console is actually good at: one command.
        A quoted heredoc is a single shell command that happens to contain
        newlines, so the whole script crosses the wire as one piece, arrives
        byte-exact (no expansion, no line-ending translation), and needs no
        helper on either side.

        The delimiter is quoted ('XKEOF') precisely so the guest shell does not
        expand $, ` or \ inside the script -- without it every variable and
        command substitution in the payload would be evaluated as it was
        written. #>
    param([string]$Path)
    $p = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $p)) { throw "script not found: $p" }
    $name = Split-Path -Leaf $p
    $remote = Get-GuestRemotePath $p
    $script:uploadedRemotes[$remote] = $true

    # The bytes are read (not the text) so the size check is against exactly what
    # the guest should end up holding.
    $raw = [System.IO.File]::ReadAllBytes($p)
    $body = [System.Text.Encoding]::UTF8.GetString($raw)

    # HTTP first (see the transport-order note above).  The served copy is the
    # exact file this function was handed, and the guest reports its own
    # sha256sum, so "verified" means the same bytes, not the same length.
    if ($uploadServer -and $script:guestHttp) {
        $sha = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
        Copy-Item -LiteralPath $p -Destination (Join-Path $uploadServer.StageDir $name) -Force
        $url = "$($script:guestHttp)/$name"
        for ($httpTry = 1; $httpTry -le 2; $httpTry++) {
            $probe = "wget -q -O $remote '$url' && sha256sum $remote"
            $out = Invoke-GuestCommand -Text $probe -Label "fetch $name" -TimeoutSec 120
            if ($out -notmatch [regex]::Escape($sha)) {
                Write-Host ("    !! HTTP transfer of {0} did not verify (attempt {1}); falling back to the console heredoc" -f $name, $httpTry) -ForegroundColor DarkYellow
                break
            }
            Write-Host ("    {0}: {1} bytes, sha256 verified over HTTP" -f $name, $raw.Length) -ForegroundColor Green
            # chmod is a separate console command and can fail if the transfer
            # vanished between the hash check and this line.  Do not continue to
            # run a script that is not there: retry the transfer once, then fail.
            $chmod = Invoke-GuestCommand -Text "chmod +x $remote; test -f $remote && echo FILE_OK" -Label "chmod $name" -TimeoutSec 30 -AllowFailure
            if ($chmod -match 'FILE_OK') {
                return $remote
            }
            Write-Host ("    !! chmod/fingerprint failed for {0} (attempt {1}); retrying transfer" -f $name, $httpTry) -ForegroundColor DarkYellow
        }
        throw "HTTP transfer of $name verified but the file was not usable after chmod; refusing to run it"
    }
    # A single heredoc, sent whole, with the trim joined to it.
    #
    # Two alternatives were tried and both are worse:
    #   * base64 in chunks -- the chunk echo floods the console and the guest then
    #     answers nothing at all (three attempts, "no fingerprint" each time);
    #   * a heredoc whose body contains quotes and `$` at 2 KB and up -- its
    #     trailing lines get spliced into whatever command follows.
    # What is left is the original shape, which transfers byte-exact at the sizes
    # this project's scripts use, plus the verify/retry loop below.
    if ($raw.Length -gt $script:HeredocLimit) {
        throw ("$name is $($raw.Length) bytes, above the $($script:HeredocLimit)-byte ceiling measured for this " +
               "console. Split it into smaller scripts and pass several with -Script 'a.sh;b.sh'; do NOT raise " +
               "the limit, because a larger heredoc arrives with its tail spliced into the next command.")
    }
    Write-Host ("`n=== script {0}: {1} bytes (heredoc) ===" -f $name, $raw.Length) -ForegroundColor Cyan
    $ok = Send-Heredoc -Remote $remote -Body $body -TimeoutSec 180 -ExpectedBytes $raw.Length
    if (-not $ok) { Write-Host '    !! no marker after the heredoc; will verify and retry' -ForegroundColor DarkYellow }

    Invoke-GuestCommand -Text "chmod +x $remote; wc -l < $remote" -Label "chmod $name" -TimeoutSec 30 -Quiet | Out-Null

    # Verify the transfer EXACTLY: the guest must report the host's byte count
    # and the host's POSIX cksum.
    #
    # Byte count alone is not enough, and that is not theory: a batch run of this
    # measurement delivered c1-perf-harvest.sh with the right SIZE and a syntax
    # error at line 10, because the heredoc tail had been spliced.  The previous
    # check (same cksum over two reads of the same file) cannot see that -- both
    # reads agree with each other, not with the host.
    #
    # So the host now computes the same POSIX cksum busybox computes and compares
    # values.  Get-PosixCksum is pinned to two reference points (see its comment),
    # and the two-reads-agree test is kept only as a secondary signal, because a
    # cksum taken from a corrupted file is still self-consistent.
    $wantCksum = Get-PosixCksum -Data $raw
    for ($attempt = 1; $attempt -le $TransferAttempts; $attempt++) {
        $fp1 = Get-GuestFileFingerprint -Remote $remote
        if ($fp1) { $fp2 = Get-GuestFileFingerprint -Remote $remote } else { $fp2 = $null }
        $stable = $fp1 -and $fp2 -and $fp1.Cksum -eq $fp2.Cksum
        $exact = $fp1 -and ($fp1.Bytes -eq $raw.Length) -and ($fp1.Cksum -eq $wantCksum)
        if ($exact) {
            Write-Host ("    transfer verified: {0} bytes, cksum {1} = host cksum" -f $fp1.Bytes, $fp1.Cksum) -ForegroundColor Green
            break
        }
        $seen = if (-not $fp1) { 'no fingerprint' }
                elseif ($fp1.Bytes -ne $raw.Length) { "$($fp1.Bytes) bytes (host has $($raw.Length))" }
                else { "$($fp1.Bytes) bytes, cksum $($fp1.Cksum) but host cksum is $wantCksum" }
        Write-Host ("    transfer MISMATCH on attempt {0}: guest has {1}" -f $attempt, $seen) -ForegroundColor DarkYellow
        if ($attempt -eq $TransferAttempts) { throw "could not transfer $name faithfully after $TransferAttempts attempts (guest: $seen)" }
        Send-Heredoc -Remote $remote -Body $body -TimeoutSec 180 -ExpectedBytes $raw.Length | Out-Null
    }

    return $remote
}

function Send-GuestScriptInline {
    <#  Put a local script in the guest (see Send-GuestScriptFile), then run it. #>
    param([string]$Path, [string]$Argument = '', [int]$TimeoutSec = 600)
    $name = Split-Path -Leaf ([System.IO.Path]::GetFullPath($Path))
    $remote = Send-GuestScriptFile -Path $Path
    Write-Host "=== run $name ===" -ForegroundColor Cyan
    $run = if ($Argument) { "sh $remote $Argument" } else { "sh $remote" }
    $out = Invoke-GuestCommand -Text "$run 2>&1" -Label "sh $name" -TimeoutSec $TimeoutSec
    Save-Evidence ("run-{0}.txt" -f $name) $out | Out-Null
    return $out
}

function Get-GuestFileFingerprint {
    <#  Byte count and POSIX `cksum` of a file inside the guest, both computed BY
        the guest.

        Computing the checksum on the host as well was abandoned: it meant
        reimplementing POSIX cksum in PowerShell, and two attempts produced
        plausible-looking numbers that never matched busybox.  A re-implementation
        that is subtly wrong is worse than no check at all, because it reports
        faithful transfers as corrupt.  What the host actually needs is
        reproducible evidence that the bytes did not change between two reads --
        the guest's own cksum over its own file gives exactly that, and it is the
        same tool that will be quoted in the report.

        `cksum` is used rather than sha256sum because busybox is the only toolkit
        in this image and `cksum` is the one it always has. #>
    param([string]$Remote, [int]$TimeoutSec = 60)
    # A here-string with no host-side `$( )`: the guest command substitution would
    # otherwise be parsed by PowerShell 5.1, which is how an earlier probe reported
    # "no fingerprint" for a file that was present and readable.
    $probe = @"
echo FPSTART
wc -c "$Remote" 2>/dev/null
cksum "$Remote" 2>/dev/null
echo FPEND
"@
    $out = Invoke-GuestCommand -Text $probe -Label "fingerprint $Remote" -TimeoutSec $TimeoutSec -Quiet
    # Parsed loosely, and anchored for the FIRST LINE of `wc -c` output.  The
    # console interleaves the shell prompt with command output
    # (`FPSTART\r\nkylin-x:~# wc -c ...`), so an anchor on "FPSTART immediately
    # followed by digits" never matched.  Requiring the path on the wc line is what
    # keeps this from latching onto a number inside the echoed command text.
    $m = [regex]::Match($out, '(?m)^(?<b>\d+)\s+\S+\s*$')
    if (-not $m.Success) { return $null }
    $c = [regex]::Match($out, "(?m)^(?<c>\d+)\s+(?<l>$($m.Groups['b'].Value))\s+\S+\s*$")
    return [pscustomobject]@{
        Bytes = [int64]$m.Groups['b'].Value
        # The guest's own cksum; compared against a SECOND reading of the same
        # file, never against a host-side value.
        Cksum = if ($c.Success) { [int64]$c.Groups['c'].Value } else { [int64]0 }
    }
}

function Get-PosixCksum {
    <#  POSIX cksum of a byte array.

        Implemented here because .NET has no POSIX cksum and the guest only has
        busybox, so the host must compute the SAME algorithm the guest will or the
        comparison is meaningless.

        Two things this version gets right that the first two did not:
          * everything is [long].  A [uint32] cast in PowerShell THROWS on a
            negative value ("Cannot convert value -1 to UInt32") instead of
            wrapping.
          * the CRC is folded over the byte, then the length, then complemented --
            which is the POSIX order used by the reference implementation and by
            busybox.  Getting this order wrong produced a plausible-looking number
            that never matched the guest (verified by comparing against a
            bit-by-bit reference on the same 704-byte file). #>
    param([byte[]]$Data)
    # MSB-first CRC with polynomial 0x04C11DB7, then the length folded in the
    # same way, then complemented -- that is POSIX cksum.
    #
    # The previous version used the REFLECTED polynomial 0xEDB88320 (LSB-first),
    # which reproduces zlib CRC-32 and is wrong here.  It had never been called,
    # so the error was invisible; it is called now to prove a transfer byte-exact,
    # and two independent reference points pin the algorithm down:
    #   * the published vector "123456789" -> 930766865;
    #   * guest/c2-perf-prep.sh (425 B) -> 1483927866, read off the guest itself
    #     in session evidence/perf/vt31-20261018T170516Z/console.log.
    # The masks are [long] on purpose: PowerShell parses the literal 0xFFFFFFFF
    # as an Int32 -1, so `-band 0xFFFFFFFF` is a no-op and `-bxor 0xFFFFFFFF`
    # inverts the sign -- the first attempt at this produced numbers like
    # -3978992981662174062 while looking perfectly reasonable to write.
    # Decimal literals, not hex: PowerShell parses 0x80000000 and 0xFFFFFFFF as
    # Int32 -2147483648 and -1 (verified on this host), so a [long] cast of the
    # literal keeps the SIGN.  That is how the first two attempts at this
    # produced -3978992981662174062 with code that reads correctly.
    [long]$TOP = 2147483648      # 0x80000000
    [long]$POLY = 79764919       # 0x04C11DB7
    [long]$MASK = 4294967295     # 0xFFFFFFFF
    [long]$crc = 0
    foreach ($b in $Data) {
        $crc = $crc -bxor ([long]$b -shl 24)
        for ($k = 0; $k -lt 8; $k++) {
            if ($crc -band $TOP) { $crc = (($crc -shl 1) -bxor $POLY) -band $MASK }
            else { $crc = ($crc -shl 1) -band $MASK }
        }
    }
    [long]$len = $Data.Length
    while ($len -ne 0) {
        $crc = $crc -bxor ((($len -band 0xFF)) -shl 24)
        for ($k = 0; $k -lt 8; $k++) {
            if ($crc -band $TOP) { $crc = (($crc -shl 1) -bxor $POLY) -band $MASK }
            else { $crc = ($crc -shl 1) -band $MASK }
        }
        $len = $len -shr 8
    }
    return [long](($crc -bxor $MASK) -band $MASK)
}

function Send-GuestLargeFile {
    <#  Copy a file of ANY size into the guest over the serial console alone.

        Why chunked: this console carries a small heredoc reliably and a large
        one unreliably.  Measured behaviour -- a 34-byte script and a 4 KB script
        both arrived byte-exact, while a 7 KB page install and a 30 KB bundle
        arrived with their contents visibly interleaved (HTML fragments spliced
        into unrelated lines).  The limit is payload size, not content.

        So the file is cut into chunks small enough to stay inside what has been
        proven, each chunk is written by its own heredoc, and the chunks are
        concatenated inside the guest afterwards.  Each command is finished and
        drained before the next is written, so the guest's input buffer never
        accumulates a backlog -- which is the mechanism that corrupts a single
        long write.

        The result is verified by BYTE COUNT inside the guest against the host's
        own size.  A transfer that silently truncated must not look like success,
        because a truncated HTML page would render as a plausible-looking but
        wrong screen and quietly invalidate the screenshot evidence. #>
    param([string]$Local, [string]$Remote, [int]$ChunkBytes = 3000, [int]$TimeoutSec = 120, [switch]$NoVerify)
    if (-not (Test-Path -LiteralPath $Local)) { throw "inject source not found: $Local" }
    $want = (Get-Item -LiteralPath $Local).Length
    $stem = "$Remote.transfer"
    Send-GuestChunkedTransfer -Local $Local -Stem $stem -ChunkBytes $ChunkBytes -TimeoutSec $TimeoutSec

    if ($NoVerify) {
        Invoke-GuestCommand -Text "mv -f $stem.part $Remote; echo MOVED" -Label "accept $Remote (unverified)" -TimeoutSec 40 | Out-Null
        Write-Host "    !! accepted WITHOUT verification (-NoInjectVerify)" -ForegroundColor DarkYellow
        return
    }

    # Verify with a script that is itself transferred, then run.
    #
    # Not built as a PowerShell string literal: the guest text needs `$( )` and
    # `<`, and PowerShell 5.1 parses both as its own syntax, so a literal here is
    # rejected before it is ever sent.  Not sent as a heredoc either -- the
    # chunk echo above floods the console enough to swallow the end-marker.  A
    # transferred file has neither problem.
    $D = [char]36
    $v = "n=$D(cat $stem.part | wc -c)" + "`n" +
         "if [ ""$D" + "n"" = ""$want"" ]; then" + "`n" +
         "  mv -f $stem.part $Remote" + "`n" +
         "  echo INJECT-OK $D" + "n" + "`n" +
         "else" + "`n" +
         "  echo INJECT-MISMATCH got=$D" + "n want=$want" + "`n" +
         "fi"
    $tmp = Join-Path $env:TEMP ("xk-verify-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".sh")
    [System.IO.File]::WriteAllText($tmp, $v)
    try {
        Send-GuestChunkedTransfer -Local $tmp -Stem "$stem.verify" -ChunkBytes $ChunkBytes -TimeoutSec $TimeoutSec
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    $res = Invoke-GuestCommand -Text "sh $stem.verify.part" -Label "verify $([System.IO.Path]::GetFileName($Local))" -TimeoutSec 60
    if ($res -match 'INJECT-OK\s+(\d+)') {
        Write-Host "    verified in guest: $($Matches[1]) bytes" -ForegroundColor Green
    } else {
        $m = [regex]::Match($res, 'INJECT-MISMATCH got=(\d+) want=(\d+)')
        $got = if ($m.Success) { $m.Groups[1].Value } else { 'no answer' }
        throw "inject of $Local failed: guest reports $got, host has $want"
    }
}

function Send-GuestChunkedTransfer {
    <#  Move a file to the guest as <Stem>.part, with no verification.

        Split out from Send-GuestLargeFile so the verification script can be
        transported by exactly the same mechanism it is checking -- one code
        path, so a bug in the transfer cannot hide behind a different one. #>
    param([string]$Local, [string]$Stem, [int]$ChunkBytes = 3000, [int]$TimeoutSec = 120)
    $data = [System.IO.File]::ReadAllBytes($Local)
    # The file is shipped as base64 because arbitrary bytes (a PNG, a .img) are
    # not safe to paste into a shell as text.
    $b64 = [Convert]::ToBase64String($data)
    $dir = $Stem.Substring(0, $Stem.LastIndexOf('/'))
    Invoke-GuestCommand -Text "mkdir -p $dir; rm -f $Stem.part*" -Label "prepare $Stem" -TimeoutSec 30 | Out-Null

    $perChunk = [Math]::Floor($ChunkBytes / 4) * 4   # whole 4-char groups
    $parts = [Math]::Ceiling($b64.Length / $perChunk)
    Write-Host "    $([System.IO.Path]::GetFileName($Local)): $($data.Length) bytes -> $parts chunk(s)" -ForegroundColor DarkGray

    for ($k = 0; $k -lt $parts; $k++) {
        $off = $k * $perChunk
        $len = [Math]::Min($perChunk, $b64.Length - $off)
        $slice = $b64.Substring($off, $len)
        # The base64 rides as the heredoc BODY and is piped straight into
        # `base64 -d`.  Nothing is quoted, which matters: base64's alphabet
        # includes `'`, and wrapping a slice in single quotes produced
        # "unterminated quoted string" on the guest.
        Send-Heredoc -Remote "$Stem.chunk$k.sh" -Body "base64 -d >> $Stem.part" -PipedBody $slice -Quiet | Out-Null
        Invoke-GuestCommand -Text "sh $Stem.chunk$k.sh" -Label "chunk $($k+1)/$parts" -TimeoutSec $TimeoutSec | Out-Null
        Invoke-GuestCommand -Text "rm -f $Stem.chunk$k.sh" -Label "" -TimeoutSec 20 -Quiet | Out-Null
    }
}

function Send-Heredoc {
    <#  Write a payload into a guest file via a quoted heredoc, atomically.

        Everything -- the heredoc AND the follow-up trim -- is sent as ONE command,
        because two commands are not safe here: measured on this console, the
        heredoc's last lines bled into the next command's line (`head -c 3573
        /tmp/x.xtmp > /tmp/x; rm -f /tmp/x.xtmp` arrived as `... /tmp/x-disable-
        features=Vulkan --kiosk --n; rm -f ...`, so `head` reported
        "--kiosk: No such file or directory").  Joining them with `;` inside a
        single heredoc-driven command removes the boundary the bleed crossed.

        The payload is written to a scratch file and trimmed to the host's exact
        size: `cat <<EOF` adds nothing, but the body as transmitted ends with a
        newline the host file may not have -- measured as a 704-byte script
        arriving as 705, which made byte-exact comparison impossible.  The length
        is a literal the host computed, so no `$( )` appears for PowerShell to
        mis-parse.

        Shared by the chunked injector and the script loader because it is the
        only transfer shape that has proven reliable on this console: one shell
        command, sent raw, followed by a marker.  The delimiter is quoted so the
        guest shell performs no expansion on the body.

        With -PipedBody the file is written as a COMMAND that reads standard
        input, and the body is then fed to it by `sh <file> <<'DELIM' ... DELIM`.
        That is what lets a base64 blob cross the wire with no quoting anywhere:
        base64's alphabet contains `'`, so wrapping a slice in single quotes
        produced "unterminated quoted string" on the guest.  A heredoc body
        cannot be terminated by any character inside it. #>
    param([string]$Remote, [string]$Body, [string]$PipedBody, [int]$TimeoutSec = 60,
          [int]$ExpectedBytes = 0, [switch]$Quiet)
    $delim = 'XK_H_EOF_' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
    if ($Body -match "(?m)^$delim$") { throw "payload contains the heredoc delimiter $delim" }
    $before = $script:buf.Length

    # NOTE: `stty -echo` was tried here to stop the console echoing a whole
    # base64 chunk back, and it BROKE the session -- the console went quiet
    # (console.log stopped at the boot banner) and every later command timed out.
    # Turning the tty echo off also suppresses the shell's prompt handling that
    # this harness keys on.  Pacing the writes is the fix that does work.
    #
    # Why paced: a heredoc sent in one burst arrives with lines spliced together.
    # A 6,307-byte script came through as ">ins." and a truncated `if`; a
    # 2,530-byte one turned `chromium` into `chromiu-disable-features=Vulkan: not
    # found`.  The console's input buffer is the limit, not the line discipline,
    # so the payload is written in small blocks with a short pause between them.
    $PaceBlock = 12          # lines per block
    $PaceMs = 60             # pause between blocks

    function Wait-HeredocMarker([string]$nonce, [int]$timeout) {
        $deadline = (Get-Date).AddSeconds($timeout)
        while ((Get-Date) -lt $deadline) {
            Read-Available -QuietMs 300 -MaxMs 1200
            $tail = $script:buf.ToString($before, $script:buf.Length - $before)
            $d = Get-GuestCommandResultDetail -Transcript $tail -Nonce $nonce
            if ($d.status -in @('ok', 'malformed', 'conflict')) { return $d }
            if ($proc.HasExited) { break }
        }
        $tail = $script:buf.ToString($before, $script:buf.Length - $before)
        return (Get-GuestCommandResultDetail -Transcript $tail -Nonce $nonce -AtEnd)
    }

    if ($PSBoundParameters.ContainsKey('PipedBody')) {
        $delim2 = 'XK_H_EOF_' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
        if ($PipedBody -match "(?m)^$delim2$") { throw "payload contains the heredoc delimiter $delim2" }
        Send-Guest ("cat > $Remote <<'$delim'`n")
        foreach ($line in ($Body -split "`n")) { Send-Guest ($line + "`n") }
        Start-Sleep -Milliseconds 250
        Send-Guest ("$delim`n")
        Start-Sleep -Milliseconds 250
        $n1 = 'XK{0}' -f (Get-Random -Minimum 1000000 -Maximum 9999999)
        Send-Guest ("echo __${n1}__rc=`$?`n")
        $d1 = Wait-HeredocMarker $n1 $TimeoutSec
        if ($d1.status -ne 'ok' -or $d1.rc -ne 0) { return $false }

        Start-Sleep -Milliseconds 100
        Send-Guest ("sh $Remote <<'$delim2'`n")
        foreach ($line in ($PipedBody -split "`n")) { Send-Guest ($line + "`n") }
        Start-Sleep -Milliseconds 250
        Send-Guest ("$delim2`n")
        Start-Sleep -Milliseconds 250
        $n2 = 'XK{0}' -f (Get-Random -Minimum 1000000 -Maximum 9999999)
        Send-Guest ("echo __${n2}__rc=`$?`n")
        $d2 = Wait-HeredocMarker $n2 $TimeoutSec
        return ($d2.status -eq 'ok' -and $d2.rc -eq 0)
    }

    # Separate commands are mandatory here.  The old code sent the delimiter and
    # the trim line back to back; a real run lost the delimiter's newline and the
    # trim's first character was consumed by the prompt (`hkylin-x:~# ead -c ...`),
    # so the file was never created.  Wait for the heredoc's own marker first.
    $target = if ($ExpectedBytes -gt 0) { "$Remote.xtmp" } else { $Remote }
    Send-Guest ("cat > $target <<'$delim'`n")
    $bodyLines = $Body -split "`n"
    for ($li = 0; $li -lt $bodyLines.Count; $li++) {
        Send-Guest ($bodyLines[$li] + "`n")
        if ((($li + 1) % $PaceBlock) -eq 0) { Start-Sleep -Milliseconds $PaceMs }
    }
    Start-Sleep -Milliseconds 250
    Send-Guest ("$delim`n")
    Start-Sleep -Milliseconds 350
    $ncat = 'XK{0}' -f (Get-Random -Minimum 1000000 -Maximum 9999999)
    Send-Guest ("echo __${ncat}__rc=`$?`n")
    $dcat = Wait-HeredocMarker $ncat $TimeoutSec
    if ($dcat.status -ne 'ok') { return $false }
    if ($dcat.rc -ne 0) { return $false }

    if ($ExpectedBytes -gt 0) {
        Start-Sleep -Milliseconds 120
        $tail = "head -c $ExpectedBytes $Remote.xtmp > $Remote; rm -f $Remote.xtmp"
        Send-Guest ("$tail`n")
        Start-Sleep -Milliseconds 25
        $ntail = 'XK{0}' -f (Get-Random -Minimum 1000000 -Maximum 9999999)
        Send-Guest ("echo __${ntail}__rc=`$?`n")
        $dtail = Wait-HeredocMarker $ntail $TimeoutSec
        return ($dtail.status -eq 'ok' -and $dtail.rc -eq 0)
    }
    return $true
}

function Send-GuestLocalFile {
    <#  Copy one host file into the guest over HTTP, and verify it by byte count.

        There is deliberately NO console fallback here.  A fallback that reuses
        the console would have to push base64 in chunks, and a chunked push is
        what silently corrupted the transport before: the guest echoes every
        chunk, the echo competes with the command markers, and the caller's
        result comes back empty with no error.  Failing loudly is strictly
        better than failing invisibly -- if the HTTP path is unavailable, the
        run stops and says so.

        Verification is by byte count rather than by "wget printed no error":
        `wget -q` prints nothing on success OR on a truncated transfer, so
        absence of an error message cannot tell a complete file from a partial
        one. #>
    param([string]$Local, [string]$Remote, $Server, [int]$TimeoutSec = 120)
    if (-not (Test-Path -LiteralPath $Local)) { throw "file not found: $Local" }
    if (-not $Server) { throw "no HTTP server for this run; cannot send $Local" }

    $dir = $Remote.Substring(0, $Remote.LastIndexOf('/'))
    Invoke-GuestCommand -Text "mkdir -p $dir" -Label "mkdir $dir" -TimeoutSec 30 | Out-Null

    $name = Split-Path -Leaf $Local
    $want = (Get-Item -LiteralPath $Local).Length
    Copy-Item -LiteralPath $Local -Destination (Join-Path $Server.StageDir $name) -Force
    $url = "http://10.0.2.2:$($Server.Port)/$name"
    # No `$` and no `<` in the guest command: PowerShell 5.1 would try to
    # expand or parse both on this side of the wire.
    $probe = 'wget -q -O {0} "{1}" && echo got=`cat {0} `| wc -c` || echo got=0' -f $Remote, $url
    $out = Invoke-GuestCommand -Text $probe -Label "fetch $name" -TimeoutSec $TimeoutSec
    $m = [regex]::Match($out, 'got=(\d+)')
    if (-not $m.Success) {
        throw "no byte count came back for $name; the guest console did not answer"
    }
    if ([int]$m.Groups[1].Value -ne $want) {
        throw "$name arrived as $($m.Groups[1].Value) bytes, expected $want"
    }
    Write-Host ("    {0}: {1} bytes verified" -f $name, $want) -ForegroundColor DarkGray
    return $out
}

function Invoke-GuestScript {
    <#  Fetch a local script into the guest, run it, and return its output.

        The served copy is what the guest fetches, so the script is on the HTTP
        server too -- no host path ever crosses the console string. #>
    param([string]$Path, $Server, [string]$Argument = '', [int]$TimeoutSec = 600)
    $p = [System.IO.Path]::GetFullPath($Path)
    $name = Split-Path -Leaf $p
    $remote = Get-GuestRemotePath $p
    $script:uploadedRemotes[$remote] = $true
    Write-Host "`n=== upload+run $name ===" -ForegroundColor Cyan
    Send-GuestLocalFile -Local $p -Remote $remote -Server $Server -TimeoutSec 120 | Out-Null
    Invoke-GuestCommand -Text "chmod +x $remote" -Label "chmod $name" -TimeoutSec 30 | Out-Null
    Write-Host "=== run $name ===" -ForegroundColor Cyan
    $run = if ($Argument) { "sh $remote $Argument" } else { "sh $remote" }
    $out = Invoke-GuestCommand -Text "$run 2>&1" -Label "sh $name" -TimeoutSec $TimeoutSec
    Save-Evidence ("run-{0}.txt" -f $name) $out | Out-Null
    return $out
}

function Invoke-ScreenDump {
    <#  Capture the guest framebuffer to a PNG and return both capture instants.

        Split out of Get-ScreenShot for one reason: the frame watch has to
        capture at a fixed cadence, and running the Python statistics pass per
        frame costs ~0.4 s of host CPU each time -- that competes with the very
        vCPU whose latency is being measured, so it is deferred and done in one
        batch afterwards (host/frame_stats.py).

        The two instants are kept because they bound the content: the framebuffer
        is read somewhere between the request and the file landing, so a consumer
        that reports only one of them is hiding its own error bar. #>
    param([string]$Name = 'screen', [int]$TimeoutSec = 30)
    if (-not $qmp) { return $null }
    $png = Join-Path $OutDir "$Name.png"
    if (Test-Path -LiteralPath $png) { Remove-Item -LiteralPath $png -Force }
    $tReq = [DateTime]::UtcNow
    try {
        # Negotiate once, then screenshot.  QEMU does not accept screendump
        # before qmp_capabilities, so the order here is load-bearing.
        if (-not $script:qmpReady) {
            [void](Invoke-Qmp -Command '{"execute":"qmp_capabilities"}')
            $script:qmpReady = $true
        }
        # The filename goes into a JSON string, so backslashes must be escaped
        # (an unescaped `D:\x-...` is exactly the "stray 'D'" QMP reports) and
        # any double quote must not terminate the string early.
        $jsonPath = ($png -replace '\\', '\\') -replace '"', '\"'
        $reply = Invoke-Qmp -Command ('{"execute":"screendump","arguments":{"filename":"' +
                                      $jsonPath + '","format":"png"}}')
        # The command is asynchronous: QMP answers {"return":{}} and only then
        # writes the file, so poll for the file rather than trusting the reply.
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $png)) {
            Start-Sleep -Milliseconds 50
        }
        if (-not (Test-Path -LiteralPath $png)) {
            Write-Host ("    !! screendump produced no file; QMP said: {0}" -f ($reply -replace '\s+', ' ')) -ForegroundColor Red
            return $null
        }
        # The file's own timestamp is the better "content was readable" instant:
        # it is set when QEMU closes the PNG, whereas polling can only bracket
        # that moment with a sleep interval.
        $tDone = (Get-Item -LiteralPath $png).LastWriteTimeUtc
    } catch {
        Write-Host "    !! screendump failed: $_" -ForegroundColor Red
        return $null
    }
    return [pscustomobject]@{ name = $Name; png = $png; t_req = $tReq; t_done = $tDone }
}

function Get-ScreenShot {
    <#  Capture the guest framebuffer as PNG and MEASURE it.

        Two facts are recorded per capture: the PNG itself, and the pixel
        statistics that decide whether anything was actually drawn.  Without the
        second, "the screenshot was produced" silently becomes "the screen had a
        picture", which is the failure mode this whole task turns on. #>
    param([string]$Name = 'screen')
    $shot = Invoke-ScreenDump -Name $Name
    if (-not $shot) { return $null }
    $png = $shot.png
    $json = & $py $statsTool $png 2>&1 | Out-String
    $jsonPath = Join-Path $OutDir "$Name.stats.json"
    [System.IO.File]::WriteAllText($jsonPath, $json, $utf8)
    $stats = $null
    try { $stats = $json | ConvertFrom-Json } catch { }

    if ($stats) {
        Write-Host ("    shot {0}: {1}x{2} colors={3} dominant={4} blank={5}" -f `
            $Name, $stats.width, $stats.height, $stats.colors, $stats.dominant_fraction, $stats.blank) `
            -ForegroundColor $(if ($stats.blank) { 'DarkYellow' } else { 'Green' })
    } else {
        Write-Host "    shot $Name written, but stats could not be parsed" -ForegroundColor DarkYellow
    }
    return $stats
}

function Invoke-FrameWatch {
    <#  Capture the framebuffer on a fixed cadence while the browser starts.

        Why this is not a guest-side counter: a browser log line proves the
        process was alive, not that a pixel changed.  The task book's evidence
        channel is the QEMU monitor screendump, so page-load latency is decided
        the way a reviewer would decide it -- by looking at frames.

        Two instants per frame (requested / landed) are recorded and every PNG is
        kept, so the verdict can be re-derived at another colour threshold
        instead of being taken on trust. #>
    param([double]$Interval = 2.0, [int]$Duration = 120, [string]$LaunchCmd = '')
    $t0 = [DateTime]::UtcNow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host ''
    if ($LaunchCmd) {
        Write-Host ("=== frame watch: dispatch '{0}' at t=0, then {1}s cadence for {2}s ===" -f $LaunchCmd, $Interval, $Duration) -ForegroundColor Cyan
        # Sent, not awaited: the launcher hands the browser to a background child
        # and returns, and frames must already be running while it starts.
        Send-Guest ("$LaunchCmd" + [Environment]::NewLine)
    } else {
        Write-Host ("=== frame watch: {0}s cadence for {1}s ===" -f $Interval, $Duration) -ForegroundColor Cyan
    }
    $frames = New-Object System.Collections.Generic.List[object]
    $n = 0
    while (-not $proc.HasExited) {
        $waitMs = [int](((($n * $Interval) - $sw.Elapsed.TotalSeconds)) * 1000)
        if ($waitMs -gt 0) { Start-Sleep -Milliseconds $waitMs }
        if ($sw.Elapsed.TotalSeconds -ge $Duration) { break }
        $n++
        $shot = Invoke-ScreenDump -Name ('fw-{0:d3}' -f $n) -TimeoutSec 20
        if ($shot) {
            # CPU seconds are sampled WITH each frame, not just at the end:
            # that turns the capture window into a CPU timeline, so the share
            # of CPU burned while the page was loading can be computed over
            # exactly that interval instead of over the whole process life.
            $cpuS = $null
            try { $proc.Refresh(); $cpuS = [math]::Round($proc.TotalProcessorTime.TotalSeconds, 3) } catch { }
            $frames.Add([pscustomobject]@{
                n        = $n
                t_req_s  = [math]::Round(($shot.t_req - $t0).TotalSeconds, 3)
                t_done_s = [math]::Round(($shot.t_done - $t0).TotalSeconds, 3)
                cpu_s    = $cpuS
                png      = (Split-Path -Leaf $shot.png)
            })
            if ($n -le 3 -or ($n % 10) -eq 0) {
                Write-Host ("    fw {0:d3}  t={1,7:N2}s" -f $n, ($shot.t_done - $t0).TotalSeconds) -ForegroundColor DarkGray
            }
        }
        # The console must keep being drained: the guest's kernel log plus the
        # browser's stderr would otherwise fill the serial buffer and stall the
        # very process whose latency is being measured.
        Read-Available -QuietMs 40 -MaxMs 200 | Out-Null
    }
    [System.IO.File]::WriteAllText((Join-Path $OutDir 'frame-watch.json'),
        ([pscustomobject]@{
            interval_s = $Interval
            duration_s = $Duration
            t0_utc     = $t0.ToString('o')
            launch_cmd = $LaunchCmd
            frames     = $frames
        } | ConvertTo-Json -Depth 6), $utf8)
    Write-Host ('  frame watch: {0} frames over {1:N1}s' -f $frames.Count, $sw.Elapsed.TotalSeconds) -ForegroundColor Green
    if ($frames.Count -gt 0) {
        # The PNGs are already on disk, so a failure here must not abort the run:
        # the measurement can be redone offline from the frames.  PowerShell 5.1
        # also turns a native command's stderr into a terminating error while
        # $ErrorActionPreference is Stop, which is exactly how an earlier version
        # lost the rest of a session because a stats script had a KeyError.
        $eap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $fr = & $py $frameTool $OutDir --threshold $FrameThreshold 2>&1 | Out-String
            if ($fr.Trim()) { Write-Host ('  ' + $fr.Trim()) -ForegroundColor DarkGray }
        } catch {
            Write-Host '  !! frame analysis failed; the PNGs are kept, rerun host/frame_stats.py' -ForegroundColor DarkYellow
        } finally {
            $ErrorActionPreference = $eap
        }
    }
    return $frames
}

try {
    $client = Wait-Port -Port $serialPort -TimeoutSec 30 -Proc $proc
    $client.NoDelay = $true
    $qmp = Wait-Port -Port $qmpPort -TimeoutSec 30 -Proc $proc
    Write-Host '  connected to guest console and QMP.' -ForegroundColor Green

    if (-not (Wait-Console -Pattern 'kylin-x:.*[#$]' -TimeoutSec $BootTimeoutSec)) {
        Read-Available -QuietMs 1000 -MaxMs 3000
        throw "guest shell prompt not reached in ${BootTimeoutSec}s; see $consoleLog"
    }
    Write-Host '  guest shell prompt reached.' -ForegroundColor Green
    Send-Guest "`n"; Read-Available -QuietMs 400 -MaxMs 1200 | Out-Null

    if ($EnableGuestCdp) {
        Send-GuestScriptInline -Path (Join-Path $ws 'guest/cdp-policy.sh') -TimeoutSec 30 | Out-Null
        # Chrome binds its debug listener to guest loopback. BusyBox nc -lk/-e
        # bridges it to 9223; the host forward is bound only to 127.0.0.1.
        $relay = "printf '#!/bin/sh\nexec nc -w 10 127.0.0.1 9222\n' > /tmp/xk-cdp-forward.sh; chmod +x /tmp/xk-cdp-forward.sh; setsid nc -lk -p 9223 -e /tmp/xk-cdp-forward.sh </dev/null >/tmp/xk-cdp-relay.log 2>&1 &"
        if ($CdpTrace) { $relay = $relay.Replace('exec nc -w 10', 'exec nc -o /tmp/xk-cdp-wire.log -w 10') }
        Invoke-GuestCommand -Text $relay -TimeoutSec 30 | Out-Null
        Invoke-GuestCommand -Text "export XK_CDP_ARGS='--remote-debugging-port=9222'; echo CDP_ENABLED" -TimeoutSec 30 | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $OutDir 'cdp-endpoint.txt'), $CdpEndpoint, $utf8)
    }

    # Baseline capture before anything is started: this is the "before" half of
    # every later claim, and it costs one screendump to be honest about it.
    Get-ScreenShot -Name '00-before' | Out-Null

    # One upload server for the whole run: the served files and the -Script
    # files are both fetched through it, so it must outlive each step.  It is
    # started before the scripts run and its address is advertised to the guest
    # as XK_HTTP, so a guest script never needs a host path.
    $serveList = @()
    if ($ServeManifest) {
        if (-not (Test-Path -LiteralPath $ServeManifest)) { throw "serve manifest not found: $ServeManifest" }
        $serveList = Get-Content -LiteralPath $ServeManifest |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') }
    }
    $serveList = @(Resolve-StagingInputs -Root $ws -ManifestPaths $serveList -Scripts $Script -Uploads $Upload)
    if (@($serveList).Count -gt 0 -or $Script) {
        $stage = Join-Path $OutDir 'stage'
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        foreach ($s in $serveList) {
            $sp = if ([System.IO.Path]::IsPathRooted($s)) { [System.IO.Path]::GetFullPath($s) } else { [System.IO.Path]::GetFullPath((Join-Path $ws $s)) }
            if (-not (Test-Path -LiteralPath $sp)) {
                # Also try it as an absolute/relative path from here, so a
                # manifest can name either form.
                $sp = [System.IO.Path]::GetFullPath($s)
            }
            if (-not (Test-Path -LiteralPath $sp)) { Write-Host "  !! serve path not found: $s" -ForegroundColor Red; continue }
            if ((Get-Item -LiteralPath $sp).PSIsContainer) {
                Copy-Item -LiteralPath $sp -Destination $stage -Recurse -Force
            } else {
                Copy-Item -LiteralPath $sp -Destination $stage -Force
            }
        }
        $stagedNames = @(Get-ChildItem -LiteralPath $stage -File | Select-Object -ExpandProperty Name)
        Write-Host "  staged for the guest ($($stagedNames.Count)): $($stagedNames -join ', ')" -ForegroundColor DarkGray
        $uploadServer = Start-UploadServer -Root $OutDir -StageDir $stage
        # Advertise the address to the guest once.  Every later command inherits
        # it through the shell's environment.
        $script:guestHttp = "http://10.0.2.2:$($uploadServer.Port)"
    if ($NoHttpUpload) { $script:guestHttp = '' }
        Invoke-GuestCommand -Text "export XK_HTTP=$($script:guestHttp); echo XK_HTTP=$($script:guestHttp)" `
            -Label 'export XK_HTTP' -TimeoutSec 40 | Out-Null
    }

    $i = 0
    # Files first, scripts second: a script usually operates on what was just
    # injected (the committee's HTML, for instance).
    foreach ($pair in $Inject) {
        $parts = $pair -split '>', 2
        if ($parts.Count -ne 2) { Write-Host "  !! bad -Inject (want 'local>remote'): $pair" -ForegroundColor Red; continue }
        $src = [System.IO.Path]::GetFullPath((Join-Path $ws $parts[0]))
        if (-not (Test-Path -LiteralPath $src)) { $src = [System.IO.Path]::GetFullPath($parts[0]) }
        Write-Host "`n=== inject $($parts[0]) -> $($parts[1]) ===" -ForegroundColor Cyan
        Send-GuestLargeFile -Local $src -Remote $parts[1] -NoVerify:$NoInjectVerify | Out-Null
    }

    # Stage-only scripts: uploaded and verified now, run later by -FrameWatchCmd
    # (or by a cmd= step).  The point is that no console upload happens inside
    # the measured window -- the launch line must cost one round trip, not a
    # heredoc transfer plus two checksum reads.
    if ($Upload) {
        foreach ($one in ($Upload -split ';')) {
            $one = $one.Trim()
            if (-not $one) { continue }
            [void](Send-GuestScriptFile -Path $one)
        }
    }

    if ($Script) {
        $i = 0
        foreach ($one in ($Script -split ';')) {
            $one = $one.Trim()
            if (-not $one) { continue }
            $i++
            $p = [System.IO.Path]::GetFullPath($one)
            if (-not (Test-Path -LiteralPath $p)) { Write-Host "  !! script not found: $p" -ForegroundColor Red; continue }
            # Default transport is the heredoc: it needs no network and no helper
            # on either side, which is what this environment permits.
            Send-GuestScriptInline -Path $p -TimeoutSec $CommandTimeoutSec | Out-Null
            Get-ScreenShot -Name ("{0:d2}-after-{1}" -f $i, [System.IO.Path]::GetFileNameWithoutExtension($p)) | Out-Null
        }
    }

    # Startup readiness gate.  The failure this exists for: the first file://
    # navigation is sometimes lost (network-service restart), leaving a window
    # titled "Untitled - Chromium" at 262-267 colours forever.  A real Ctrl+R
    # commits the page (D3, 2026-10-29: 267 -> 808 colours).  Retrying a
    # NAVIGATION is bounded and recorded; the alternative -- a fixed sleep -- has
    # no evidence and hides the first failure.
    if ($StartupReadyColors -gt 0) {
        $readyFile = Join-Path $OutDir 'startup-ready.json'
        $attempts = @()
        $actions = @()
        $readyAt = $null
        $firstFailure = $null
        $lastColors = 0
        $gateStart = Get-Date
        $max = [Math]::Max(1, $StartupReadyMax)
        $isReady = $false
        $pollIndex = 0
        for ($attempt = 1; $attempt -le $max; $attempt++) {
            $deadline = (Get-Date).AddSeconds([Math]::Max(1, $StartupReadyWaitSec))
            do {
                $pollIndex++
                $stats = Get-ScreenShot -Name ("ready-{0:d2}-p{1}" -f $attempt, $pollIndex)
                $colors = 0
                if ($stats -and $null -ne $stats.PSObject.Properties['colors']) { $colors = [int]$stats.colors }
                if ($colors -gt 0) { $lastColors = $colors }
                $ok = Test-StartupReady -Stats $stats -MinColors $StartupReadyColors
                $entry = [pscustomobject]@{
                    attempt = $attempt
                    at = (Get-Date).ToString('o')
                    colors = $colors
                    ok = $ok
                }
                $attempts += $entry
                if ($null -eq $firstFailure -and -not $ok) { $firstFailure = $entry }
                if ($ok) { $isReady = $true; $readyAt = (Get-Date).ToString('o'); break }
                if ((Get-Date) -lt $deadline) { Start-Sleep -Seconds ([Math]::Max(1, $StartupReadyPollSec)) }
            } while ((Get-Date) -lt $deadline)
            if ($isReady) { break }
            if ($attempt -lt $max) {
                # Two different failures need two different retries.  A desktop
                # with no Chromium window cannot be reloaded (Ctrl+R would go to
                # the JWM root), so the browser is killed and relaunched.  A
                # window shell at 262-270 colours is a lost navigation, so a real
                # Ctrl+R is enough.
                if ($lastColors -lt 60) {
                    Write-Host ("    startup gate: no window (colors={0}); restarting the browser" -f $lastColors) -ForegroundColor Yellow
                    Invoke-GuestCommand -Text 'killall -9 chromium 2>/dev/null || true' -TimeoutSec 60 | Out-Null
                    Start-Sleep -Seconds 2
                    $launcher = $StartupReadyLauncher
                    Invoke-GuestCommand -Text ("sh " + $launcher) -TimeoutSec 300 | Out-Null
                    $action = 'restart'
                } else {
                    Write-Host ("    startup gate: blank shell (colors={0}); sending Ctrl+R" -f $lastColors) -ForegroundColor Yellow
                    [void](Send-QmpKey -Spec 'ctrl+r')
                    $action = 'reload'
                }
                $actions += [pscustomobject]@{
                    before_attempt = $attempt + 1
                    action = $action
                    colors = $lastColors
                    at = (Get-Date).ToString('o')
                }
            }
        }
        $total = [math]::Round(((Get-Date) - $gateStart).TotalSeconds, 1)
        $doc = [pscustomobject]@{
            enabled = $true
            min_colors = $StartupReadyColors
            max_attempts = $max
            wait_sec = $StartupReadyWaitSec
            poll_sec = $StartupReadyPollSec
            ready = $isReady
            ready_at = $readyAt
            first_failure = $firstFailure
            total_s = $total
            attempts = $attempts
            actions = $actions
        }
        [System.IO.File]::WriteAllText($readyFile, ($doc | ConvertTo-Json -Depth 5), $utf8)
        if ($isReady) {
            Write-Host ("    startup gate: READY after {0} attempt(s), {1}s total" -f $attempts.Count, $total) -ForegroundColor Green
        } else {
            $script:harnessExitCode = 1
            Write-Host ("    startup gate: NOT READY after {0} attempt(s), {1}s total" -f $attempts.Count, $total) -ForegroundColor Red
        }
    }

    # Absolute-schedule load loop (task 21/22).
    if ($LoadSchedule) {
        if ($LoadSchedule -notmatch '^\s*(\d+)\s*x\s*(\d+)\s*@\s*(\d+)\s*$') {
            throw "bad -LoadSchedule (want <count>x<interval>@<start>, e.g. 10x120@60): $LoadSchedule"
        }
        $loadCount = [int]$Matches[1]
        $loadInterval = [int]$Matches[2]
        $loadStart = [int]$Matches[3]
        if ($loadCount -lt 1 -or $loadInterval -lt 1) { throw 'Load count/interval must be positive' }
        $loadRows = @()
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        for ($n = 0; $n -lt $loadCount; $n++) {
            $planned = $loadStart + $n * $loadInterval
            # Read the old document before its planned trigger, so diagnostic
            # HTTP/WebSocket latency does not become deliberate trigger drift.
            while ($sw.Elapsed.TotalSeconds -lt ($planned - 2)) { Start-Sleep -Milliseconds 100 }
            $before = Read-PageEvidence ('load-{0:d2}-before' -f ($n + 1))
            while ($sw.Elapsed.TotalSeconds -lt $planned) { Start-Sleep -Milliseconds 100 }
            # Capture the actual trigger time after the pre-navigation probe.
            $sent = [math]::Round($sw.Elapsed.TotalSeconds, 2)
            [void](Send-QmpKey -Spec 'ctrl+r')
            $done = $null
            $colors = 0
            $ok = $false
            $deadline = (Get-Date).AddSeconds(20)
            $probe = $null
            $loadPoll = 0
            do {
                Start-Sleep -Seconds 3
                $loadPoll++
                $stats = Get-ScreenShot -Name ("load-{0:d2}-p{1}" -f ($n + 1), $loadPoll)
                if ($stats -and $null -ne $stats.PSObject.Properties['colors']) { $colors = [int]$stats.colors }
                $probe = Read-PageEvidence ('load-{0:d2}-after-p{1}' -f ($n + 1), $loadPoll)
                $ok = $false
                if ($before -and $probe -and $before.ok -and $probe.ok) {
                    $ok = (Test-StartupReady -Stats $stats -MinColors $LoadReadyColors) -and
                        ($before.target_id -eq $probe.target_id) -and
                        ($before.navigation_id -ne $probe.navigation_id)
                }
                if ($ok) { $done = [math]::Round($sw.Elapsed.TotalSeconds, 2); break }
            } while ((Get-Date) -lt $deadline)
            $loadRows += [pscustomobject]@{
                round = $n + 1
                planned_s = $planned
                sent_s = $sent
                drift_s = [math]::Round($sent - $planned, 2)
                completed_s = $done
                navigation_id = $(if ($probe -and $probe.ok) { $probe.navigation_id } else { $null })
                before_navigation_id = $(if ($before -and $before.ok) { $before.navigation_id } else { $null })
                semantic_ok = [bool]$ok
                colors = $colors
                ok = $ok
            }
            Write-Host ("    load {0}/{1}: planned {2}s sent {3}s drift {4}s ok={5} colors={6}" -f `
                ($n + 1), $loadCount, $planned, $sent, [math]::Round($sent - $planned, 2), $ok, $colors) `
                -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
        }
        if ($LoadHoldSec -gt 0) {
            Write-Host ("    holding session until {0}s from schedule start" -f $LoadHoldSec) -ForegroundColor DarkGray
            while ($sw.Elapsed.TotalSeconds -lt $LoadHoldSec) { Start-Sleep -Seconds 1 }
        }
        $loadDoc = [pscustomobject]@{
            schedule = $LoadSchedule
            count = $loadCount
            interval_s = $loadInterval
            start_s = $loadStart
            hold_s = $LoadHoldSec
            completed = @($loadRows | Where-Object { $_.ok }).Count
            total_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
            rows = $loadRows
        }
        [System.IO.File]::WriteAllText((Join-Path $OutDir 'load-schedule.json'),
            ($loadDoc | ConvertTo-Json -Depth 5), $utf8)
        if ($loadDoc.completed -ne $loadCount) { $script:harnessExitCode = 1 }
        Write-Host ("    load schedule: {0}/{1} completed" -f $loadDoc.completed, $loadCount) `
            -ForegroundColor $(if ($loadDoc.completed -eq $loadCount) { 'Green' } else { 'Red' })
    }

    # Frame watch: the one measurement that reads the page off the framebuffer.
    # It sits after the setup scripts and before the -Key steps on purpose --
    # the launch has to happen inside the capture window, and the harvesting
    # command comes afterwards as a cmd= step.
    if ($FrameWatch) {
        $fwInterval = 2.0
        $fwDuration = 120
        if ($FrameWatch -match '^\s*([\d.]+)\s*x\s*(\d+)\s*$') {
            $fwInterval = [double]$Matches[1]
            $fwDuration = [int]$Matches[2]
        } else {
            throw "bad -FrameWatch spec (want <interval>x<duration>, e.g. 2x100): $FrameWatch"
        }
        $launchPath = [regex]::Match($FrameWatchCmd, '^\s*sh\s+(/tmp/\S+)')
        if ($launchPath.Success -and -not $script:uploadedRemotes.ContainsKey($launchPath.Groups[1].Value)) {
            throw ("-FrameWatchCmd references an unuploaded guest script path: {0}" -f $launchPath.Groups[1].Value)
        }
        [void](Invoke-FrameWatch -Interval $fwInterval -Duration $fwDuration -LaunchCmd $FrameWatchCmd)
    }

    # Interleaved input/inspection steps, in the order given on the command line.
    #
    # An entry is either a key chord ('alt+tab@5') or a guest command
    # ('cmd=sh /tmp/xk-x5-evidence.sh').  Interleaving is the whole point: a
    # window switch is only observable if a reading is taken BETWEEN the
    # keystroke and the next one, and a single before/after pair cannot show
    # which window became active.
    $specs = Split-StepSpec $Key
    foreach ($k in $specs) {
        $spec = $k.Trim()
        if (-not $spec) { continue }
        $wait = 4
        if ($spec -match '@(\d+)$') { $wait = [int]$Matches[1]; $spec = $spec -replace '@\d+$', '' }
        Assert-StepSpec $spec
        $i++
        if ($spec -match '^wait=(\d+(\.\d+)?)$') {
            $seconds = [double]$Matches[1]
            Write-Host "`n=== wait $seconds s ===" -ForegroundColor Cyan
            $end = (Get-Date).AddSeconds($seconds)
            while ((Get-Date) -lt $end) { Read-Available -QuietMs 500 -MaxMs 2000 }
            Get-ScreenShot -Name ("{0:d2}-after-wait" -f $i) | Out-Null
            continue
        }
        if ($spec.StartsWith('cmd=')) {
            $text = $spec.Substring(4)
            $pathMatch = [regex]::Match($text, '^\s*(?:sh|exec\s+sh)\s+(/tmp/\S+)')
            if ($pathMatch.Success -and -not $script:uploadedRemotes.ContainsKey($pathMatch.Groups[1].Value)) {
                throw ("cmd= references an unuploaded guest script path: {0}; upload it with -Upload or use the mapped /tmp/xk-<name>" -f $pathMatch.Groups[1].Value)
            }
            Write-Host "`n=== guest cmd: $text ===" -ForegroundColor Cyan
            Invoke-GuestCommand -Text $text -TimeoutSec $CommandTimeoutSec -AllowFailure:$TolerantCommands | Out-Null
            Get-ScreenShot -Name ("{0:d2}-after-step-cmd" -f $i) | Out-Null
            continue
        }
        if ($spec.StartsWith('expect-url=')) {
            $ExpectedPageUrl = $spec.Substring(11)
            if (-not $ExpectedPageUrl) { throw 'Expected page URL must not be empty' }
            continue
        }
        if ($spec.StartsWith('check=')) {
            $mode = $spec.Substring(6)
            if ($mode -notin @('page', 'js', 'css', 'input')) { throw 'Unknown semantic check mode' }
            $evidence = Read-PageEvidence ('step-{0:d2}-{1}' -f $i, $mode) $mode
            if (-not $evidence -or -not $evidence.ok) { throw ('Semantic step failed: ' + $mode) }
            continue
        }
        if ($spec.StartsWith('click=')) {
            $coord = $spec.Substring(6) -split ','
            if ($coord.Count -ne 2) { Write-Host "  !! bad click spec (want click=x,y): $spec" -ForegroundColor Red; continue }
            $cx = [int]$coord[0]
            $cy = [int]$coord[1]
            Write-Host "`n=== click $cx,$cy (then ${wait}s) ===" -ForegroundColor Cyan
            Send-QmpMouseClick -X $cx -Y $cy
            Start-Sleep -Seconds $wait
            Get-ScreenShot -Name ("{0:d2}-after-click-{1}x{2}" -f $i, $cx, $cy) | Out-Null
            continue
        }
        if ($spec.StartsWith('type=')) {
            $text = $spec.Substring(5)
            Write-Host "`n=== type '$text' ===" -ForegroundColor Cyan
            Send-QmpText -Text $text
            Start-Sleep -Seconds $wait
            Get-ScreenShot -Name ("{0:d2}-after-type" -f $i) | Out-Null
            continue
        }
        $tag = $spec -replace '[^A-Za-z0-9]', ''
        Write-Host "`n=== key: $spec  (then ${wait}s) ===" -ForegroundColor Cyan
        $reply = Send-QmpKey -Spec $spec
        Save-Evidence ("run-key-{0:d2}-{1}.txt" -f $i, $tag) ($reply + "`n") | Out-Null
        $end = (Get-Date).AddSeconds($wait)
        while ((Get-Date) -lt $end) { Read-Available -QuietMs 500 -MaxMs 2000 }
        Get-ScreenShot -Name ("{0:d2}-after-key-{1}" -f $i, $tag) | Out-Null
    }

    foreach ($c in $Command) {
        $i++
        Invoke-GuestCommand -Text $c -TimeoutSec $CommandTimeoutSec | Out-Null
        Get-ScreenShot -Name ("{0:d2}-after-cmd" -f $i) | Out-Null
    }

    if ($AfterScriptWait -gt 0) {
        Write-Host "`n--- reading the console for ${AfterScriptWait}s more (async guest output) ---" -ForegroundColor DarkGray
        $end = (Get-Date).AddSeconds($AfterScriptWait)
        while ((Get-Date) -lt $end) {
            if ($SessionStopFile -and (Test-Path -LiteralPath $SessionStopFile)) { break }
            Read-Available -QuietMs 500 -MaxMs 2000
        }
        Get-ScreenShot -Name 'zz-final' | Out-Null
    }
    if ($CollectBrowserProcesses) {
        & $py (Join-Path $scriptDir 'browser_probe.py') --endpoint $CdpEndpoint --out (Join-Path $OutDir 'browser-processes.json') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Browser process-role collection failed' }
    }
    if ($PageProbeMode) {
        $pageCheck = Read-PageEvidence 'page-check' $PageProbeMode
        if (-not $pageCheck -or -not $pageCheck.ok) { throw 'Semantic page check failed; see page-check.json' }
        if ($PageProbeMode -eq 'css') {
            & $py (Join-Path $scriptDir 'css_layout_probe.py') --endpoint $CdpEndpoint --expected-url $ExpectedPageUrl --page-file (Join-Path $ws 'pages\layout.html') --out (Join-Path $OutDir 'css-layout.json') | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'CSS geometry collection failed; see css-layout.json' }
        }
    }
} catch {
    $script:harnessExitCode = 1
    Write-Host "`n!! $_" -ForegroundColor Red
    Save-Evidence 'harness-error.txt' "$_" | Out-Null
    foreach ($diagnosticName in @('query-status', 'query-cpus-fast')) {
        try {
            $diagnosticReply = Invoke-Qmp -Command (@{ execute = $diagnosticName } | ConvertTo-Json -Compress) -TimeoutMs 2000
            Save-Evidence ('failure-' + $diagnosticName + '.json') $diagnosticReply | Out-Null
        } catch { Save-Evidence ('failure-' + $diagnosticName + '.txt') "$_" | Out-Null }
    }
    # Interrupt-controller state at the failure instant.  This is read-only and
    # is what distinguishes "all CPUs idle with IRQs masked" from "timer lost".
    foreach ($monitorCommand in @('info irq', 'info pic')) {
        try {
            $reply = Invoke-Qmp -Command (@{ execute = 'human-monitor-command'; arguments = @{ 'command-line' = $monitorCommand } } | ConvertTo-Json -Compress) -TimeoutMs 3000
            Save-Evidence ('failure-' + ($monitorCommand -replace ' ', '-') + '.txt') $reply | Out-Null
        } catch { Save-Evidence ('failure-' + ($monitorCommand -replace ' ', '-') + '-error.txt') "$_" | Out-Null }
    }
    if ($QemuDebug) {
        $dbg = Join-Path $OutDir 'qemu-debug.log'
        if (Test-Path -LiteralPath $dbg) {
            try {
                $lines = Get-Content -LiteralPath $dbg -Tail 300 -ErrorAction Stop
                Save-Evidence 'failure-qemu-debug-tail.txt' (($lines -join "`n") + "`n") | Out-Null
            } catch { Save-Evidence 'failure-qemu-debug-tail-error.txt' "$_" | Out-Null }
        }
    }
    # Preserve the failing snapshot's browser/Xorg logs before QEMU exits.
    # Diagnostic collection is bounded and must not replace the original error.
    try {
        $failureDetail = Invoke-GuestCommand -Text 'echo FAILURE_DIAGNOSTICS_BEGIN; ps w; for f in /tmp/w.log /tmp/w2.log /tmp/w3.log /tmp/int.log /tmp/lay.log /tmp/xo3.log /tmp/xk-cdp-relay.log; do if [ -r "$f" ]; then echo "LOG_FILE=$f"; tail -n 120 "$f"; fi; done; echo FAILURE_DIAGNOSTICS_END' -TimeoutSec 10 -AllowFailure
        Save-Evidence 'failure-diagnostics.txt' ($failureDetail | Out-String) | Out-Null
    } catch {
        Save-Evidence 'failure-diagnostics-error.txt' "$_" | Out-Null
    }
} finally {
    Write-Host "`n== shutting down ==" -ForegroundColor Cyan
    if ($uploadServer) { Stop-UploadServer -Server $uploadServer }
    # Capture what the QEMU process cost, taken while it is definitely alive.
    #
    # PeakWorkingSet64 is the OS's own high-water mark and TotalProcessorTime is
    # cumulative, so one reading is complete -- no sampler thread is needed, and
    # polling from outside would need a tool this host does not have (the first
    # attempt used wmic, which does not exist here, and reported 0).  These are
    # HOST measurements, which is what the task book prescribes.
    #
    # Placement matters: this runs before the QMP quit below, because after QEMU
    # exits the Process object stops reporting PeakWorkingSet64 -- an earlier
    # placement wrote no file at all, which the report then read as "0 MB".
    if ($proc) {
        try {
            $proc.Refresh()
            $qm = [pscustomobject]@{
                qemu_pid           = $proc.Id
                peak_working_set_b = [int64]$proc.PeakWorkingSet64
                cpu_seconds        = [math]::Round($proc.TotalProcessorTime.TotalSeconds, 2)
                has_exited         = $proc.HasExited
                # Both resource RATES the task book names need a denominator, so
                # each one is captured here rather than assumed later:
                #   cpu usage rate   = cpu_seconds / wall_seconds
                #   memory occupancy = peak_working_set_b / host_ram_b,
                #                      and / (guest_mem_mb * 1 MiB)
                # Reading them at capture time is what makes the ratio a
                # measurement of THIS run instead of of a remembered command line.
                wall_seconds       = $(try { [math]::Round(((Get-Date) - $proc.StartTime).TotalSeconds, 2) } catch { $null })
                smp_cpus           = $Smp
                guest_mem_mb       = $guestMemMb
                host_ram_b         = $script:hostRamBytes
                host_logical_cpus  = [Environment]::ProcessorCount
                qemu_threads       = $(try { $proc.Threads.Count } catch { $null })
            }
            [System.IO.File]::WriteAllText((Join-Path $OutDir 'qemu-metrics.json'),
                ($qm | ConvertTo-Json), $utf8)
            Write-Host ("  qemu metrics      : peak_ws={0:N0} B  cpu={1:N2} s" -f `
                $qm.peak_working_set_b, $qm.cpu_seconds)
        } catch {
            Write-Host "  !! qemu metrics unavailable: $_" -ForegroundColor DarkYellow
        }
    }
    # The QMP `quit` is what actually stops the guest, so -Keep has to suppress it:
    # killing the process afterwards is only the second half of the shutdown.
    # Before this guard, "-Keep" left the user with a window that closed anyway a
    # few minutes into a session, because the quit had already been delivered --
    # the switch looked broken while doing exactly what it was written to do.
    #
    # With -Keep the guest now stays up after the harness exits, so the session can
    # be driven and recorded by hand.  Stop it by closing the QEMU window, or with
    #   taskkill /IM qemu-system-aarch64.exe
    try {
        if ($qmp -and -not $Keep) {
            [void](Invoke-Qmp -Command '{"execute":"quit"}' -TimeoutMs 2000)
            Start-Sleep -Milliseconds 800
        } elseif ($qmp) {
            Write-Host '  -Keep: leaving the guest running; close the QEMU window when done.' -ForegroundColor Yellow
        }
    } catch { }
    # Record what the QEMU process cost, taken while it is still alive.
    #
    # Why here and not in a sampler thread on the Python side: PeakWorkingSet64 is
    # the OS's own high-water mark and TotalProcessorTime is cumulative, so one
    # reading is complete -- and polling the process from outside needs a tool
    # this host does not have.  These are HOST measurements, which is what the
    # task book prescribes for performance numbers.
    #
    # Fallback only: skipped once the pre-quit capture above has written the
    # sidecar, because after QEMU exits this read cannot succeed anyway.
    if ($proc -and -not (Test-Path -LiteralPath (Join-Path $OutDir 'qemu-metrics.json'))) {
        try {
            $proc.Refresh()
            $qm = [pscustomobject]@{
                qemu_pid           = $proc.Id
                peak_working_set_b = [int64]$proc.PeakWorkingSet64
                cpu_seconds        = [math]::Round($proc.TotalProcessorTime.TotalSeconds, 2)
                has_exited         = $proc.HasExited
                # Both resource RATES the task book names need a denominator, so
                # each one is captured here rather than assumed later:
                #   cpu usage rate   = cpu_seconds / wall_seconds
                #   memory occupancy = peak_working_set_b / host_ram_b,
                #                      and / (guest_mem_mb * 1 MiB)
                # Reading them at capture time is what makes the ratio a
                # measurement of THIS run instead of of a remembered command line.
                wall_seconds       = $(try { [math]::Round(((Get-Date) - $proc.StartTime).TotalSeconds, 2) } catch { $null })
                smp_cpus           = $Smp
                guest_mem_mb       = $guestMemMb
                host_ram_b         = $script:hostRamBytes
                host_logical_cpus  = [Environment]::ProcessorCount
                qemu_threads       = $(try { $proc.Threads.Count } catch { $null })
            }
            [System.IO.File]::WriteAllText((Join-Path $OutDir 'qemu-metrics.json'),
                ($qm | ConvertTo-Json), $utf8)
            Write-Host ("  qemu metrics      : peak_ws={0:N0} B  cpu={1:N2} s" -f `
                $qm.peak_working_set_b, $qm.cpu_seconds)
        } catch {
            Write-Host "  !! qemu metrics unavailable: $_" -ForegroundColor DarkYellow
        }
    }
    if ($proc -and -not $proc.HasExited -and -not $Keep) { $proc.Kill() }
    if ($proc) { $proc.WaitForExit(5000) | Out-Null }
    if ($client) { $client.Close() }
    if ($qmp) { $qmp.Close() }
    $script:logRaw.Close()
    Write-Host "  console transcript : $consoleLog"
    Write-Host "  evidence directory : $OutDir"
    if (Test-Path -LiteralPath $qemuErr) {
        $errText = Get-Content -LiteralPath $qemuErr -Raw -ErrorAction SilentlyContinue
        if ($errText) { Write-Host "  qemu stderr       : $qemuErr" }
    }
}

exit $script:harnessExitCode
