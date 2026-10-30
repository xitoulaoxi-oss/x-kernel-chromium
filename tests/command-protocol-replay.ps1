$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../host/command-result.ps1')

$fixtures = Join-Path $PSScriptRoot 'fixtures/command-protocol'
$cases = @(
    @{ name = 'real crash marker behind partial ANSI'; file = 'crash-ansi-marker.txt'; nonce = 'XK7471578'; rc = 0; status = 'ok' },
    @{ name = 'real single2 spliced upload, nonzero rc'; file = 'single2-spliced-upload.txt'; nonce = 'XK1706920'; rc = 127; status = 'ok' },
    @{ name = 'real stop continuation, no marker'; file = 'stop-continuation-no-marker.txt'; nonce = 'XK9999999'; rc = $null; status = 'missing' },
    @{ name = 'terminated empty rc is malformed'; file = 'incomplete-marker.txt'; nonce = 'XK1234567'; rc = $null; status = 'malformed' },
    @{ name = 'echoed marker with digits is not a result'; file = 'echo-only-marker.txt'; nonce = 'XK1234567'; rc = $null; status = 'missing' },
    @{ name = 'wrong nonce'; file = 'crash-ansi-marker.txt'; nonce = 'XK0000000'; rc = $null; status = 'missing' }
)
foreach ($case in $cases) {
    $text = [IO.File]::ReadAllText((Join-Path $fixtures $case.file), [Text.Encoding]::UTF8)
    $d = Get-GuestCommandResultDetail -Transcript $text -Nonce $case.nonce
    if ($d.status -ne $case.status -or $d.rc -ne $case.rc) {
        throw ("FAIL: {0}: got status={1} rc={2}, want status={3} rc={4}" -f $case.name, $d.status, $d.rc, $case.status, $case.rc)
    }
    Write-Output ('PASS: ' + $case.name)
}
