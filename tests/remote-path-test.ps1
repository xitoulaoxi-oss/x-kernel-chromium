$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../host/guest-paths.ps1')
$cases = @(
    @{ path = 'guest/xk-targets.sh'; want = '/tmp/xk-xk-targets.sh' },
    @{ path = 'guest/x5c-win2.sh'; want = '/tmp/xk-x5c-win2.sh' },
    @{ path = 'guest/fault-status.sh'; want = '/tmp/xk-fault-status.sh' }
)
foreach ($c in $cases) {
    $got = Get-GuestRemotePath $c.path
    if ($got -ne $c.want) { throw ("FAIL: {0} -> {1}, want {2}" -f $c.path, $got, $c.want) }
}
if ((Get-GuestRemotePath 'guest/xk-targets.sh') -eq '/tmp/xk-targets.sh') {
    throw 'FAIL: mapping still strips the xk- prefix'
}
Write-Output 'REMOTE-PATH-TESTS-PASS'
