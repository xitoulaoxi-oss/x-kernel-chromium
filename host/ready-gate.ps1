# ready-gate.ps1 -- the startup-readiness predicate used by xkwin.ps1.
#
# Why this is a separate file: the retry decision is the part that needs a
# regression test.  Keeping it a pure function of the measured stats means the
# test can feed synthetic {colors, blank} objects without starting QEMU.
#
# The predicate is deliberately narrow: "the framebuffer has at least N colours
# and is not blank".  It decides whether to retry a navigation; it is NOT the
# acceptance test.  Acceptance additionally checks the window title / page
# content, because a colourful error page is not a rendered page.

function Test-StartupReady {
    param(
        $Stats,
        [int]$MinColors = 300
    )
    if ($null -eq $Stats) { return $false }
    $blank = $false
    if ($null -ne $Stats.PSObject.Properties['blank']) { $blank = [bool]$Stats.blank }
    if ($blank) { return $false }
    if ($null -eq $Stats.PSObject.Properties['colors']) { return $false }
    return ([int]$Stats.colors -ge $MinColors)
}
