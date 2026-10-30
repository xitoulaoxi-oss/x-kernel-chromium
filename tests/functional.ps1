# Functional entry: real windows, keyboard echo, link navigation, renderer roles,
# JS self-check and CSS layout. Every check keeps its own QEMU evidence.
param(
    [string]$Disk = 'D:\x-kernel-dsh-bridge\delivered\agentos-disk.img',
    [string]$Kernel = 'artifacts\kernel-procfs.bin',
    [string]$OutRoot = '',
    [string]$CdpEndpoint = '',
    [string]$CheckSet = 'windows,input,js,css'
)
$ErrorActionPreference = 'Stop'
# Without an external endpoint, use the opt-in per-session guest-loopback bridge.
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$root = [System.IO.Path]::GetFullPath((Join-Path $here '..'))
Set-Location $root
if (-not $OutRoot) {
    $OutRoot = Join-Path $root ('experiments\RUNS\FUNCTIONAL-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
}
New-Item -ItemType Directory -Force $OutRoot | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$results = @()
$selected = @($CheckSet -split ',' | ForEach-Object { $_.Trim() } | Select-Object -Unique)
if ($selected.Count -eq 0 -or @($selected | Where-Object { $_ -notin @('windows', 'input', 'js', 'css') }).Count) {
    throw 'CheckSet accepts only windows,input,js,css'
}

function Run-Xkwin([string]$name, [string]$scripts, [string]$keys, [string]$launcher, [string]$upload) {
    $dir = Join-Path $OutRoot $name
    New-Item -ItemType Directory -Force $dir | Out-Null
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'host\xkwin.ps1'),
        '-Tag', ('FUNC-' + $name), '-Disk', $Disk, '-Kernel', $Kernel,
        '-ServeManifest', (Join-Path $root 'guest\serve-pages.txt'),
        '-Script', $scripts,
        '-StartupReadyColors', '300', '-StartupReadyMax', '3', '-StartupReadyWaitSec', '20', '-StartupReadyPollSec', '5',
        '-CommandTimeoutSec', '400', '-BootTimeoutSec', '420', '-AfterScriptWait', '10', '-OutDir', $dir)
    $page = if ($name -in @('js', 'input')) { 'interaction.html' } elseif ($name -eq 'css') { 'layout.html' } else { 'index.html' }
    $mode = if ($name -eq 'windows') { 'page' } elseif ($name -eq 'input') { 'css' } else { $name }
    if ($CdpEndpoint) { $args += @('-CdpEndpoint', $CdpEndpoint) } else { $args += '-EnableGuestCdp' }
    $args += @('-PageProbeMode', $mode, '-ExpectedPageUrl', ('file:///usr/share/kiosk/official/' + $page))
    if ($name -eq 'input') { $args += @('-CollectBrowserProcesses', '-ExpectedInputText', 'hello x-kernel') }
    if ($launcher) { $args += @('-StartupReadyLauncher', $launcher) }
    if ($upload) { $args += @('-Upload', $upload) }
    if ($keys) { $args += @('-Key', $keys) }
    & powershell @args *> (Join-Path $dir 'driver.log')
    return [pscustomobject]@{ dir = $dir; rc = $LASTEXITCODE }
}

function Read-Stats([string]$dir) {
    $p = Join-Path $dir 'zz-final.stats.json'
    if (-not (Test-Path $p)) { return $null }
    return Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
}

function Read-Title([string]$dir) {
    $p = Join-Path $dir 'console.log'
    if (-not (Test-Path $p)) { return '' }
    $c = Get-Content -LiteralPath $p -Raw
    $m = [regex]::Matches($c, 'WM_NAME\(UTF8_STRING\) = "([^"]+)"')
    if ($m.Count -eq 0) { return '' }
    return $m[$m.Count - 1].Groups[1].Value
}

if ($selected -contains 'windows') {
# 1) two windows + two Alt+Tabs
$r = Run-Xkwin 'windows' 'guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1.sh;guest\x5c-win2.sh' 'cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh' '' 'guest\y6-evidence.sh'
$console = if (Test-Path (Join-Path $r.dir 'console.log')) { Get-Content (Join-Path $r.dir 'console.log') -Raw } else { '' }
$lists = [regex]::Matches($console, '_NET_CLIENT_LIST\(WINDOW\): window id # ([0-9a-fx,\s]+)')
$ids = @()
if ($lists.Count -gt 0) {
    $ids = ([regex]::Matches($lists[$lists.Count - 1].Groups[1].Value, '0x[0-9a-f]+') | ForEach-Object { $_.Value } | Sort-Object -Unique)
}
$actives = [regex]::Matches($console, '_NET_ACTIVE_WINDOW\(WINDOW\): window id # (0x[0-9a-f]+)') | ForEach-Object { $_.Groups[1].Value }
$last = @($actives | Select-Object -Last 3)
$switchOk = ($r.rc -eq 0) -and ($ids.Count -ge 2) -and ($last.Count -eq 3) -and
    ($last[0] -eq $last[2]) -and ($last[0] -ne $last[1]) -and
    ($last[0] -in $ids) -and ($last[1] -in $ids)
$hp = Join-Path $r.dir 'page-check.json'
$html = if (Test-Path $hp) { Get-Content -LiteralPath $hp -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$switchOk = $switchOk -and ($html.ok -eq $true)
$results += [pscustomobject]@{ check = 'two windows + alt-tab'; pass = $switchOk; dir = $r.dir; ids = ($ids -join ','); actives = ($actives -join ','); rc = $r.rc }

}
if ($selected -contains 'input') {
# QMP input traverses the guest input stack; DOM reads only verify its effect.
$keys = 'check=page;ctrl+end@3;click=230,531@2;type=hello x-kernel@3;check=input;click=228,691@8;expect-url=file:///usr/share/kiosk/official/layout.html;ctrl+end@3;cmd=sh /tmp/xk-process-identity.sh'
$r = Run-Xkwin 'input' 'guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x7-interaction.sh' $keys '/tmp/xk-x7-interaction.sh' 'guest\process-identity.sh'
$inputFiles = @(Get-ChildItem -LiteralPath $r.dir -Filter 'step-*-input.json')
$inputDoc = if ($inputFiles.Count -eq 1) { Get-Content -LiteralPath $inputFiles[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$fp = Join-Path $r.dir 'page-check.json'
$finalDoc = if (Test-Path $fp) { Get-Content -LiteralPath $fp -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$inputOk = ($r.rc -eq 0) -and $inputDoc -and ($inputDoc.ok -eq $true) -and $finalDoc -and ($finalDoc.ok -eq $true) -and ($finalDoc.url -eq 'file:///usr/share/kiosk/official/layout.html')
$results += [pscustomobject]@{ check = 'keyboard echo + mouse link navigation'; pass = [bool]$inputOk; dir = $r.dir; rc = $r.rc }
& python (Join-Path $root 'host\process_identity_check.py') $r.dir *> (Join-Path $r.dir 'process-identity-check.log')
$identityRc = $LASTEXITCODE
$results += [pscustomobject]@{ check = 'browser + renderer roles joined to guest procfs'; pass = (($r.rc -eq 0) -and ($identityRc -eq 0)); dir = $r.dir; rc = $identityRc }
}
if ($selected -contains 'js') {
# 2) JS self-check click (interaction page)
$r = Run-Xkwin 'js' 'guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x7-interaction.sh' 'click=164,365@8;cmd=sh /tmp/xk-y6-evidence.sh' '/tmp/xk-x7-interaction.sh' 'guest\y6-evidence.sh'
$s = Read-Stats $r.dir
$t = Read-Title $r.dir
$jp = Join-Path $r.dir 'page-check.json'
$j = if (Test-Path $jp) { Get-Content $jp -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$jsOk = ($r.rc -eq 0) -and $j -and ($j.ok -eq $true) -and ($j.mode -eq 'js')
$results += [pscustomobject]@{ check = 'JS page + self-check click'; pass = [bool]$jsOk; dir = $r.dir; colors = $(if ($s) { $s.colors } else { $null }); title = $t; rc = $r.rc }

}
if ($selected -contains 'css') {
# 3) CSS layout page
$r = Run-Xkwin 'css' 'guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x6-layout.sh' 'ctrl+end@5;cmd=sh /tmp/xk-y6-evidence.sh' '/tmp/xk-x6-layout.sh' 'guest\y6-evidence.sh'
$s = Read-Stats $r.dir
$t = Read-Title $r.dir
$cp = Join-Path $r.dir 'page-check.json'
$c = if (Test-Path $cp) { Get-Content $cp -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$cssOk = ($r.rc -eq 0) -and $c -and ($c.ok -eq $true) -and ($c.mode -eq 'css')
$results += [pscustomobject]@{ check = 'CSS layout page + conclusion'; pass = [bool]$cssOk; dir = $r.dir; colors = $(if ($s) { $s.colors } else { $null }); title = $t; rc = $r.rc }

}
$passCount = @($results | Where-Object { $_.pass }).Count
$requiredChecks = @('windows', 'input', 'js', 'css')
$doc = [pscustomobject]@{
    task = '39-functional'
    generated_at = (Get-Date).ToString('o')
    out_root = $OutRoot
    checks = $results
    passed = $passCount
    total = $results.Count
    coverage = $selected
    full_acceptance = $false
    full_functional = (@($requiredChecks | Where-Object { $_ -notin $selected }).Count -eq 0 -and $passCount -eq $results.Count)
    note = 'Functional checks only; CSS Linux comparison, stability and resource qualification are separate gates. Input coordinates require the recorded 1280x800 guest geometry.'
}
$doc | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 (Join-Path $OutRoot 'functional.json')
Write-Output ($doc | ConvertTo-Json -Depth 5)
if ($passCount -eq $results.Count) { exit 0 } else { exit 1 }
