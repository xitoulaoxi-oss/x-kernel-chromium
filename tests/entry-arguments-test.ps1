# Exercise the real entry scripts without launching QEMU. In particular, a
# one-element CDP switch array must survive PowerShell 5.1 argument splatting.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$global:XkEntryCaptured = @()
function powershell {
    $global:XkEntryCaptured = @($args)
    throw 'CAPTURE_ONLY'
}
function Capture-Entry([string]$path, [hashtable]$parameters) {
    $global:XkEntryCaptured = @()
    try { & $path @parameters; throw 'entry did not call harness' }
    catch { if ($_.Exception.Message -ne 'CAPTURE_ONLY') { throw } }
    if (-not $global:XkEntryCaptured.Count) { throw 'no arguments captured' }
}
$cases = 0
foreach ($endpoint in @('', 'http://127.0.0.1:12345')) {
    Capture-Entry (Join-Path $root 'tests\load-loop.ps1') @{ CdpEndpoint=$endpoint; OutDir='experiments\REVIEW-FIX\entry-test' }
    if ($endpoint) {
        $i = [array]::IndexOf($global:XkEntryCaptured, '-CdpEndpoint')
        if ($i -lt 0 -or $global:XkEntryCaptured[$i + 1] -ne $endpoint) { throw 'external endpoint was not preserved' }
    } elseif (@($global:XkEntryCaptured | Where-Object { $_ -eq '-EnableGuestCdp' }).Count -ne 1) {
        throw 'single switch was split or lost'
    }
    if ($global:XkEntryCaptured -contains 'E' -or $global:XkEntryCaptured -contains '-') { throw 'scalar string was split into characters' }
    $cases++
    foreach ($mode in @('smoke', 'functional', 'stability', 'load')) {
        Capture-Entry (Join-Path $root 'tests\run-finals.ps1') @{Mode=$mode;CdpEndpoint=$endpoint;OutDir='experiments\REVIEW-FIX\entry-test'}
        $i = [array]::IndexOf($global:XkEntryCaptured, '-CdpEndpoint')
        if ($endpoint) {
            if ($i -lt 0 -or $global:XkEntryCaptured[$i + 1] -ne $endpoint) { throw "$mode lost external endpoint" }
        } elseif ($i -ge 0) { throw "$mode passed an empty native argument" }
        if ($mode -eq 'smoke' -and $global:XkEntryCaptured -notcontains '-PageProbeMode') { throw 'smoke omitted page validation' }
        $cases++
    }
}
Write-Output "PASS $cases entry argument cases (no QEMU launched)"
