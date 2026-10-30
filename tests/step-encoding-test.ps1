$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../host/step-spec.ps1')

function Expect-Count([string]$text, [int]$want) {
    $got = @(Split-StepSpec $text)
    if ($got.Count -ne $want) { throw ("FAIL: count {0} != {1} for '{2}': {3}" -f $got.Count, $want, $text, ($got -join '|')) }
}
function Expect-Throw([string]$text, [string]$label) {
    $threw = $false
    try { $null = Split-StepSpec $text; Assert-StepSpec $text } catch { $threw = $true }
    if (-not $threw) { throw ("FAIL: expected rejection: " + $label) }
}

Expect-Count "cmd=sh -c 'a;b';wait=2;alt+tab" 3
$parts = @(Split-StepSpec "cmd=sh -c 'a;b';wait=2;alt+tab")
if ($parts[0] -ne "cmd=sh -c 'a;b'") { throw ("FAIL: quoted semicolon split: " + $parts[0]) }
Expect-Count 'cmd=sh -c "x;y";check=page' 2
Expect-Count 'type=hello world;alt+tab' 2
Expect-Count 'cmd=sh /tmp/x.sh;wait=1.5;check=js' 3

Assert-StepSpec 'cmd=sh /tmp/x.sh'
Assert-StepSpec 'wait=2'
Assert-StepSpec 'alt+tab'
Assert-StepSpec 'ctrl+end'
Assert-StepSpec 'check=input'
Assert-StepSpec 'click=10,20'
Assert-StepSpec 'type=hello x-kernel'
Expect-Throw 'sleep 5' 'space-separated key is not a chord'
Expect-Throw "cmd=sh -c 'a;b" 'unbalanced quote'
Expect-Throw 'unknownaction' 'unknown action'
Expect-Throw 'check=bogus' 'bad check mode'

Write-Output 'STEP-ENCODING-TESTS-PASS'
