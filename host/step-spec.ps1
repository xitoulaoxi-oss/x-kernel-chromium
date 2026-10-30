# Step-spec parsing for xkwin -Key.
#
# The old loop split on every ';', so `cmd=sh -c 'a; b'` became two steps and
# the guest console entered a continuation prompt (`>`).  Split only outside
# quotes, and reject an unknown action before sending anything to the guest.

function Split-StepSpec {
    param([string]$Text)
    $out = New-Object System.Collections.Generic.List[string]
    if (-not $Text) { return @() }
    $buf = New-Object System.Text.StringBuilder
    $quote = [char]0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($quote -ne [char]0) {
            [void]$buf.Append($c)
            if ($c -eq '\' -and $quote -eq [char]'"' -and ($i + 1) -lt $Text.Length) {
                $i++
                [void]$buf.Append($Text[$i])
            } elseif ($c -eq $quote) {
                $quote = [char]0
            }
            continue
        }
        if ($c -eq [char]"'" -or $c -eq [char]'"') {
            $quote = $c
            [void]$buf.Append($c)
        } elseif ($c -eq [char]';') {
            $s = $buf.ToString().Trim()
            if ($s) { $out.Add($s) }
            [void]$buf.Clear()
        } else {
            [void]$buf.Append($c)
        }
    }
    if ($quote -ne [char]0) { throw "unbalanced quote in -Key step list: $Text" }
    $s = $buf.ToString().Trim()
    if ($s) { $out.Add($s) }
    return $out.ToArray()
}

function Assert-StepSpec {
    param([string]$Spec)
    if ($Spec -match '^cmd=(.+)$') { return }
    if ($Spec -match '^expect-url=(.+)$') { return }
    if ($Spec -match '^check=(page|js|css|input)$') { return }
    if ($Spec -match '^click=(\d+),(\d+)$') { return }
    if ($Spec -match '^type=.+$') { return }
    if ($Spec -match '^wait=(\d+(\.\d+)?)$') {
        return
    }
    # A key chord such as alt+tab, ctrl+end, enter, tab.  Spaces, quotes and
    # shell-looking words are rejected, so `sleep 5` can no longer be sent as a
    # key name.  Bare names are limited to QEMU key names, so a typo such as
    # `unknownaction` is rejected instead of becoming a silent no-op key.
    $keyName = '^(enter|tab|esc|escape|space|backspace|delete|up|down|left|right|home|end|pageup|pagedown|insert|f([1-9]|1[0-2])|[A-Za-z0-9])$'
    if ($Spec -match $keyName) { return }
    $parts = $Spec -split '\+'
    if ($parts.Count -ge 2) {
        $ok = $true
        for ($pi = 0; $pi -lt ($parts.Count - 1); $pi++) {
            if ($parts[$pi] -notin @('alt', 'ctrl', 'shift', 'meta')) { $ok = $false }
        }
        if ($ok -and $parts[-1] -match $keyName) { return }
    }
    throw "unknown -Key step action: '$Spec' (expected cmd=, expect-url=, check=, click=, type=, wait=, or a key chord)"
}
