$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../host/command-result.ps1')
$cases=@(
    @{name='success';text="__XKTEST__rc=0`r`n";want=0},
    @{name='failure';text="__XKTEST__rc=7`n";want=7},
    @{name='echo only';text="echo __XKTEST__rc=0`n";want=$null},
    @{name='no completion';text="still running`n";want=$null},
    @{name='wrong session';text="__OTHER__rc=0`n";want=$null},
    @{name='ansi';text=([char]27+"[m__XKTEST__rc=0`n");want=0}
)
foreach($case in $cases){
    $actual=Get-GuestCommandResult -Transcript $case.text -Nonce 'XKTEST'
    if($actual -ne $case.want){throw ('FAIL: '+$case.name)}
    Write-Output ('PASS: '+$case.name)
}
