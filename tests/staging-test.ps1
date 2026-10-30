$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../host/staging.ps1')
$root=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tempRoot=Join-Path $root ('experiments/REVIEW-FIX/staging-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $tempRoot 'a'),(Join-Path $tempRoot 'b') -Force | Out-Null
foreach($name in @('index.html','x6-layout.sh','x7-interaction.sh','hb.sh')){[System.IO.File]::WriteAllText((Join-Path $tempRoot ('a/'+$name)), "fixture`n")}
Set-Content -LiteralPath (Join-Path $tempRoot 'b/index.html') -Value 'different fixture'
$files=@(Resolve-StagingInputs -Root $tempRoot -ManifestPaths @('a/index.html') -Scripts 'a/x6-layout.sh;a/x7-interaction.sh' -Uploads 'a/hb.sh')
if($files.Count -ne 4){throw 'Missing implicit script/upload staging'}
Write-Output 'PASS: manifest + script + upload inputs'
$files=@(Resolve-StagingInputs -Root $tempRoot -ManifestPaths @('a/hb.sh') -Uploads 'a/hb.sh')
if($files.Count -ne 1){throw 'Duplicate path was not deduplicated'}
Write-Output 'PASS: duplicate source deduplication'
$rejected=$false
try{Resolve-StagingInputs -Root $tempRoot -Scripts 'missing.sh' | Out-Null}catch{$rejected=$true}
if(-not $rejected){throw 'Missing staging input accepted'}
Write-Output 'PASS: missing input rejected'
$rejected=$false
try{Resolve-StagingInputs -Root $tempRoot -ManifestPaths @('a/index.html','b/index.html') | Out-Null}catch{$rejected=$true}
if(-not $rejected){throw 'Basename collision accepted'}
Write-Output 'PASS: basename collision rejected'
[System.IO.File]::WriteAllText((Join-Path $tempRoot 'a/crlf.sh'), "#!/bin/sh`r`nset -u`r`n")
$rejected=$false
try{Resolve-StagingInputs -Root $tempRoot -Uploads 'a/crlf.sh' | Out-Null}catch{$rejected=$_.Exception.Message -match 'LF line endings'}
if(-not $rejected){throw 'CRLF guest shell script accepted'}
Write-Output 'PASS: CRLF shell script rejected before guest upload'
# Deliberately retain fixtures within the authorized project for audit.
Write-Output ('Fixtures retained: '+$tempRoot)
