# Command completion must come from the actual marker output, never silence.
#
# The guest console interleaves prompts, CR, and partial ANSI/CSI fragments
# with command output.  A real crash session contained
#     kylin-x:~# \echo __XK7471578__rc=$?\r\n
#     ESC[__XK7471578__rc=0\r\n
# so requiring the marker at byte 0 of a line (after only complete ANSI
# sequences) rejects a valid completion.  The nonce is random per command, so
# the exact token is itself the boundary.
#
# Frame rules (iteration 01):
#   * a result frame terminates with LF/CRLF; trailing bytes after the digits
#     are only accepted if they are whitespace, otherwise malformed;
#   * a marker ending exactly at the end of the current buffer is PENDING until
#     a terminator arrives, and only becomes INCOMPLETE at the deadline;
#   * a second complete frame, or a malformed frame before a valid one, is a
#     CONFLICT; they are not silently skipped;
#   * an echoed command (`echo <token>$?`) and a wrong nonce are not results.
function Get-GuestCommandResultDetail {
    param([string]$Transcript, [string]$Nonce, [switch]$AtEnd)
    if (-not $Transcript -or -not $Nonce) {
        return [pscustomobject]@{ rc = $null; status = 'missing'; line = $null; frames = 0 }
    }
    $token = '__' + [regex]::Escape($Nonce) + '__rc='
    $complete = [regex]::new('^' + [regex]::Escape($token) + '(\d+)([ \t]*)$')
    $partial = [regex]::new('^' + [regex]::Escape($token) + '(\d*)(.*)$')
    $lines = $Transcript -split "`n"
    $valid = @()
    $bad = @()
    $pending = $false
    $unterminated = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $raw = $lines[$i]
        $terminated = ($i -lt ($lines.Count - 1))
        $line = $raw.TrimEnd("`r")
        # Ignore everything before the marker (prompt, partial ANSI, shell echo
        # noise).  Reject a line whose prefix makes it an echoed command.
        $idx = $line.IndexOf($token)
        if ($idx -lt 0) { continue }
        $prefix = $line.Substring(0, $idx)
        # The console inserts a cursor query (ESC[6n) between the prompt and the
        # typed command: `kylin-x:~# ESC[6necho __XK...`.  A \b before echo fails
        # there because `n` and `e` are both word characters, so match the literal
        # suffix instead.
        if ($prefix -match '(?i)echo\s*$') { continue }
        $candidate = $line.Substring($idx)
        if ($complete.IsMatch($candidate)) {
            if (-not $terminated) {
                # No LF yet: the diagnostic value is not final.  At the deadline
                # this is an incomplete protocol frame, not a result.
                if ($AtEnd) { $unterminated = $true } else { $pending = $true }
                continue
            }
            $m = $complete.Match($candidate)
            $valid += [pscustomobject]@{ rc = [int]$m.Groups[1].Value; line = $line.Trim() }
            continue
        }
        if ($partial.IsMatch($candidate)) {
            if (-not $terminated) {
                if ($AtEnd) { $unterminated = $true } else { $pending = $true }
            } else {
                $bad += "malformed:$candidate"
            }
            continue
        }
        $bad += "malformed:$candidate"
    }

    if ($valid.Count -gt 1) {
        return [pscustomobject]@{ rc = $null; status = 'conflict'; line = $valid[0].line; frames = $valid.Count }
    }
    if ($bad.Count -gt 0) {
        # A malformed/terminated frame followed by a valid one is a conflict:
        # refusing it prevents a 127 prefix or a 0junk tail from becoming a
        # result.  With no valid frame it is malformed.
        $status = if ($valid.Count -eq 1) { 'conflict' } else { 'malformed' }
        return [pscustomobject]@{ rc = $null; status = $status; line = ($bad -join '; '); frames = $valid.Count }
    }
    if ($valid.Count -eq 1) {
        return [pscustomobject]@{ rc = $valid[0].rc; status = 'ok'; line = $valid[0].line; frames = 1 }
    }
    if ($unterminated) {
        return [pscustomobject]@{ rc = $null; status = 'incomplete'; line = $null; frames = 0 }
    }
    if ($pending) {
        return [pscustomobject]@{ rc = $null; status = 'pending'; line = $null; frames = 0 }
    }
    return [pscustomobject]@{ rc = $null; status = 'missing'; line = $null; frames = 0 }
}

function Get-GuestCommandResult {
    param([string]$Transcript, [string]$Nonce, [switch]$AtEnd)
    $detail = Get-GuestCommandResultDetail -Transcript $Transcript -Nonce $Nonce -AtEnd:$AtEnd
    return $detail.rc
}
