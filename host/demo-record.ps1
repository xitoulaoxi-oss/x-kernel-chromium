# demo-record.ps1 -- bring up a Chromium graphics session that can be driven and
# recorded by hand.
#
# What it does: installs the committee's three pages into the guest, starts
# Xorg + jwm, opens two Chromium windows, and then LEAVES THE WINDOW OPEN
# (-Keep suppresses the QMP quit; killing only the process would still let the
# guest stop a few minutes into a session, which is the trap this avoids).
#
# Usage (from the repository root):
#     powershell -NoProfile -ExecutionPolicy Bypass -File host\demo-record.ps1
#
# This only brings the session up.  For the automated acceptance run that leaves
# screendump evidence, use the command in README section 2 -- the two do not
# replace each other: a host screen recording is a demo aid, while the acceptance
# evidence is the QEMU monitor screendump.
#
# ASCII ONLY, deliberately: PowerShell 5.1 reads a .ps1 as ANSI when it has no
# BOM, so a non-ASCII literal here would arrive as mojibake and can even break
# parsing (a full-width quote looks like a terminator).  Same reason xkwin.ps1
# keeps its own strings ASCII.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$pkg  = [System.IO.Path]::GetFullPath((Join-Path $here '..'))
Set-Location $pkg

$stamp  = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$outDir = Join-Path $pkg "runs\REC-$stamp"

Write-Host "== bring up the demo session ==" -ForegroundColor Cyan
Write-Host "package : $pkg"
Write-Host "output  : $outDir"
Write-Host "display : QEMU GTK window (not VNC)"
Write-Host ""

# Guest script order: pages -> udev input metadata -> Xorg -> jwm -> window 1 -> window 2.
# The harness takes a screendump after every step, so this run leaves evidence too;
# after it finishes the window stays open for manual driving.
$scripts = @(
    'guest\06-fetch-pages.sh',   # fetch the three pages over HTTP, verify sha256 in-guest
    'guest\x1-input.sh',         # write /run/udev/data/c13:64|65, else libinput sees no input
    'guest\x2-xorg.sh',          # Xorg: modesetting + AccelMethod none + ShadowFB + SWcursor
    'guest\y3-jwm-stock.sh',     # jwm with the image's own /etc/system.jwmrc (Alt+Tab lives there)
    'guest\x4-win1.sh',          # Chromium window 1: index.html
    'guest\x5c-win2.sh'          # window 2: interaction.html via --new-window hand-off
) -join ';'

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'xkwin.ps1') `
    -Tag 'REC' `
    -Kernel 'artifacts\kernel-procfs.bin' `
    -ServeManifest 'guest\serve-pages.txt' `
    -Script $scripts `
    -Display gtk `
    -Keep `
    -CommandTimeoutSec 300 `
    -BootTimeoutSec 420 `
    -AfterScriptWait 30 `
    -OutDir $outDir

Write-Host ""
Write-Host "== session left running on the desktop ==" -ForegroundColor Green
Write-Host "Guest scripts finished: pages installed, Xorg + jwm + two Chromium windows up."
Write-Host ""
Write-Host "Manual control (click the QEMU window once, then use these):"
Write-Host "  Alt+Tab   switch between the two windows"
Write-Host "  Ctrl+N    new window"
Write-Host "  Ctrl+L    type a URL"
Write-Host "  Alt+F1    jwm root menu"
Write-Host ""
Write-Host "To finish: close the QEMU window, or  taskkill /IM qemu-system-aarch64.exe"
Write-Host ""
Write-Host "Screendumps produced by this run (the acceptance evidence):"
Get-ChildItem $outDir -Filter '*.png' -ErrorAction SilentlyContinue |
    Sort-Object Name | ForEach-Object { Write-Host ("  " + $_.Name) }
