# Monitor the QEMU process while a harness run is active.
#
# Usage (start it before xkwin, in a separate PowerShell window/job):
#   powershell -NoProfile -ExecutionPolicy Bypass -File host\monitor-qemu.ps1 ^
#     -OutDir "experiments\E002-stability30\run" -IntervalSec 15 -Minutes 35
#
# It finds the newest qemu-system-aarch64 process and appends one JSON line
# every IntervalSec to <OutDir>\observe.jsonl.  host/observe.py reads that file
# to quantify leak trend.  It never writes to the guest image.
param(
    [Parameter(Mandatory = $true)][string]$OutDir,
    [int]$IntervalSec = 15,
    [int]$Minutes = 40,
    [int]$QemuPid = 0,
    [int]$WaitForQemuSec = 120
)
$ErrorActionPreference = 'Stop'
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$jsonl = Join-Path $OutDir 'observe.jsonl'
$log = Join-Path $OutDir 'monitor.log'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-Log([string]$s) {
    try { [System.IO.File]::AppendAllText($log, $s + "`n", $utf8) } catch { }
}

$deadline = (Get-Date).AddSeconds($WaitForQemuSec)
$proc = $null
while (-not $proc -and (Get-Date) -lt $deadline) {
    if ($QemuPid -ne 0) {
        $proc = Get-Process -Id $QemuPid -ErrorAction SilentlyContinue
    } else {
        $proc = Get-Process qemu-system-aarch64 -ErrorAction SilentlyContinue |
            Sort-Object StartTime -Descending | Select-Object -First 1
    }
    if (-not $proc) { Start-Sleep -Seconds 2 }
}
if (-not $proc) {
    Write-Log ("{0:o} no qemu process found" -f (Get-Date))
    exit 2
}

Write-Log ("{0:o} monitor start pid={1}" -f (Get-Date), $proc.Id)
$start = Get-Date
$end = $start.AddMinutes($Minutes)
$samples = 0
while ((Get-Date) -lt $end) {
    try { $proc.Refresh() } catch { break }
    if ($proc.HasExited) { break }
    $now = Get-Date
    $row = [ordered]@{}
    $row['t_iso'] = $now.ToString('o')
    $row['elapsed_s'] = [math]::Round(($now - $start).TotalSeconds, 1)
    $row['ws_mb'] = [math]::Round($proc.WorkingSet64 / 1MB, 1)
    $row['peak_ws_mb'] = [math]::Round($proc.PeakWorkingSet64 / 1MB, 1)
    $row['cpu_s'] = [math]::Round($proc.TotalProcessorTime.TotalSeconds, 2)
    $row['threads'] = $proc.Threads.Count
    $line = ($row | ConvertTo-Json -Compress)
    try { [System.IO.File]::AppendAllText($jsonl, $line + "`n", $utf8); $samples++ } catch { }
    Start-Sleep -Seconds $IntervalSec
}
Write-Log ("{0:o} monitor stop samples={1}" -f (Get-Date), $samples)
