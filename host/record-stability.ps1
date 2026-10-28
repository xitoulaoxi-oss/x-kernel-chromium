# record-stability.ps1 -- bring up a Chromium session for manual demo and frame capture,
# with machine-checkable frame evidence running underneath.
#
# What it does, in order:
#   1. setup: committee pages, udev input metadata, Xorg, jwm (ordinary -Script steps);
#   2. fires guest/rec-ready.sh in ONE console line at t=0. That script starts
#      Chromium, watches the window TITLE, and if the document never commits
#      ("Untitled - Chromium" = the file:// load was aborted) it restarts the
#      browser, up to 3 attempts. It prints REC-READY when the page is actually up.
#   3. -FrameWatch keeps taking screendumps for -Minutes, so the session has frame
#      evidence: one PNG every -CadenceSec with timestamps, plus a per-minute
#      heartbeat the guest writes to /tmp/stab.log (catted at the end).
#
# Why the retry exists: measured on this build, roughly one launch in three ends
# with the URL in the address bar but the document never committed -- the tab sits
# on "Loading..." and the page area stays white. The browser log for such a run
# shows "Network service crashed, restarting service" followed by a storm of
# socket errors, after which that navigation never completes. For a RECORDING that
# is fatal (ten minutes of white page), so the gatekeeper makes it one retry step
# instead of a surprise.
#
# The recording (host screen capture of the QEMU window) is the DEMO; the frame
# series plus the heartbeat is the EVIDENCE. The task book says the same thing:
# functionality is judged on QEMU monitor screendumps, host video is an aid.
#
# Usage (from the repository root; needs a desktop session for the GTK window):
#     powershell -NoProfile -ExecutionPolicy Bypass -File host/record-stability.ps1
#     powershell ... -File host/record-stability.ps1 -Minutes 32       # final-round length
#     powershell ... -File host/record-stability.ps1 -DisplayMode none # headless check
#
# ASCII ONLY, deliberately: PowerShell 5.1 reads a .ps1 as ANSI when it has no BOM.

param(
    # Total capture window. The first 1-3 minutes are start-up (and possibly one
    # retry): the stability claim applies to the span AFTER REC-READY, which is
    # stamped in the heartbeat log, so allow -Minutes > 10 for a 10-minute claim.
    [int]$Minutes = 12,
    [int]$CadenceSec = 30,
    # gtk shows the guest window (that is what you record); none is for a headless
    # smoke test of the same flow, when no desktop is attached.
    [string]$DisplayMode = 'gtk'
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$pkg  = [System.IO.Path]::GetFullPath((Join-Path $here '..'))
Set-Location $pkg

$stamp  = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$outDir = Join-Path $pkg "runs\STAB-$stamp"
$watch  = "{0}x{1}" -f $CadenceSec, ($Minutes * 60)
$nFrames = [int][math]::Ceiling(($Minutes * 60) / $CadenceSec)

Write-Host '== stability recording session ==' -ForegroundColor Cyan
Write-Host "package : $pkg"
Write-Host "output  : $outDir"
Write-Host "display : $DisplayMode  (record the QEMU window)"
Write-Host ("watch   : {0}  ->  up to {1} screendumps over {2} min" -f $watch, $nFrames, $Minutes)
Write-Host ''
Write-Host 'Start your screen recording BEFORE the window appears, and do not cut' -ForegroundColor Yellow
Write-Host 'the take: an unbroken clip is the point.' -ForegroundColor Yellow
Write-Host ''

# Setup only. Nothing here starts the browser: the browser is fired by
# -FrameWatchCmd so that t=0 is a single console round trip.
$scripts = @(
    'guest\06-fetch-pages.sh',   # committee pages over HTTP + in-guest sha256 check
    'guest\x1-input.sh',         # udev metadata, else libinput finds no keyboard
    'guest\x2-xorg.sh',          # Xorg: modesetting + ShadowFB + SWcursor
    'guest\y3-jwm-stock.sh'      # jwm with the image's own config (Alt+Tab comes from it)
) -join ';'

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'xkwin.ps1') `
    -Tag 'STAB' `
    -Kernel 'artifacts\kernel-procfs.bin' `
    -ServeManifest 'guest\serve-pages.txt' `
    -Script $scripts `
    -Upload 'guest\rec-chrome.sh;guest\rec-ready.sh' `
    -FrameWatch $watch `
    -FrameWatchCmd 'sh /tmp/xk-rec-ready.sh' `
    -Key 'cmd=cat /tmp/stab.log' `
    -Display $DisplayMode `
    -Keep `
    -CommandTimeoutSec 700 `
    -BootTimeoutSec 420 `
    -AfterScriptWait 10 `
    -OutDir $outDir

Write-Host ''
Write-Host '== done ==' -ForegroundColor Green
$consoleLog = Join-Path $outDir 'console.log'
$ready = $null
if (Test-Path -LiteralPath $consoleLog) {
    $ready = Select-String -Path $consoleLog -Pattern 'REC-READY' -ErrorAction SilentlyContinue | Select-Object -First 1
}
if ($ready) {
    Write-Host ('page up: ' + $ready.Line.Trim()) -ForegroundColor Green
} else {
    Write-Host 'no REC-READY in the console -- the page never committed, do not use this take' -ForegroundColor Red
}
$fwPath = Join-Path $outDir 'frame-watch.json'
if (Test-Path -LiteralPath $fwPath) {
    $m = Get-Content -LiteralPath $fwPath -Raw | ConvertFrom-Json
    $a = $m.analysis
    if ($a -and $a.found) {
        Write-Host ("first content frame: {0} s after launch ({1} colours, saturation {2})" -f $a.first_frame_s, $a.colors_at_first_frame, $a.saturation_at_first_frame) -ForegroundColor Green
    } else {
        Write-Host 'no content frame in this take -- check the clip before submitting' -ForegroundColor Red
    }
}
Write-Host ''
Write-Host 'The QEMU window is STILL UP (-Keep): the guest keeps running while you talk.'
Write-Host '  Alt+Tab   prove the WM is alive on camera'
Write-Host '  Ctrl+N    open a second window late in the clip'
Write-Host '  stop      close the QEMU window, or:  taskkill /IM qemu-system-aarch64.exe'
Write-Host ''
Write-Host 'Evidence in this run:'
Write-Host ("  {0}\fw-*.png          one frame every {1}s" -f $outDir, $CadenceSec)
Write-Host ("  {0}\frame-watch.json  per-frame timestamps / colours / saturation" -f $outDir)
Write-Host ("  {0}\console.log       REC-READY + REC-HB heartbeat lines" -f $outDir)
