$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../host/command-result.ps1')

function Detail([string]$text, [switch]$atEnd, [string]$nonce = 'XKT') {
    return Get-GuestCommandResultDetail -Transcript $text -Nonce $nonce -AtEnd:$atEnd
}
function Expect([string]$name, $detail, [string]$status, $rc) {
    if ($detail.status -ne $status -or $detail.rc -ne $rc) {
        throw ("FAIL: {0}: got status={1} rc={2}, want status={3} rc={4}" -f $name, $detail.status, $detail.rc, $status, $rc)
    }
    Write-Output ('PASS: ' + $name)
}

# 1. An unterminated value is pending while streaming and incomplete at deadline.
Expect 'unterminated rc=12 is pending' (Detail '__XKT__rc=12') 'pending' $null
Expect 'unterminated rc=12 at deadline is incomplete' (Detail '__XKT__rc=12' -atEnd) 'incomplete' $null

# 2. Trailing junk and empty rc are malformed, never 0/12.
Expect 'rc=0junk is malformed' (Detail "__XKT__rc=0junk`r`n") 'malformed' $null
Expect 'empty rc with terminator is malformed' (Detail "__XKT__rc=`r`n") 'malformed' $null

# 3. A complete frame, including a partial-ANSI prefix, is accepted.
Expect 'complete 127 is ok' (Detail "__XKT__rc=127`r`n") 'ok' 127
Expect 'partial ANSI prefix is ok' (Detail ("kylin-x:~# " + [char]27 + "[__XKT__rc=0`r`n")) 'ok' 0
$ansiEcho = "kylin-x:~# " + [char]27 + "[6necho __XKT__rc=`$?`r`n__XKT__rc=0`r`n"
Expect 'ANSI before echoed command is ignored' (Detail $ansiEcho) 'ok' 0

# 4. Duplicate or malformed-then-valid frames conflict, not silently skipped.
Expect 'two valid frames conflict' (Detail "__XKT__rc=0`r`n__XKT__rc=0`r`n") 'conflict' $null
Expect 'malformed then valid conflicts' (Detail "__XKT__rc=`r`n__XKT__rc=0`r`n") 'conflict' $null

# 5. Echo and wrong nonce are not results.
Expect 'echo only is missing' (Detail "echo __XKT__rc=0`r`n") 'missing' $null
Expect 'wrong nonce is missing' (Detail "__OTHER__rc=0`r`n") 'missing' $null

# 6. Every byte boundary of rc=127: no early ok, final value must be 127.
$full = "__XKT__rc=127`r`n"
for ($n = 0; $n -lt $full.Length; $n++) {
    $d = Detail $full.Substring(0, $n)
    if ($d.status -eq 'ok') {
        throw ("FAIL: byte boundary {0} returned ok={1} before the frame terminator" -f $n, $d.rc)
    }
}
$last = Detail $full
Expect 'byte boundary final frame is 127' $last 'ok' 127
$deadline = Detail "__XKT__rc=127" -atEnd
Expect 'byte boundary without terminator at deadline is incomplete' $deadline 'incomplete' $null

Write-Output 'COMMAND-FRAME-TESTS-PASS'
