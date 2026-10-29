# Stop QEMU processes started by this overnight session at the hard deadline.
# Backstop only; scheduled reminders also ask the agent to stop.
$deadline = [datetime]'2026-10-30T09:00:00+08:00'
$cut = [datetime]'2026-10-29T18:00:00+08:00'
$log = Join-Path $PSScriptRoot 'DEADLINE-STOP.txt'
while ((Get-Date) -lt $deadline) { Start-Sleep -Seconds 30 }
$killed = @()
Get-Process qemu-system-aarch64 -ErrorAction SilentlyContinue |
  Where-Object { $_.StartTime -ge $cut } |
  ForEach-Object { $killed += $_.Id; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
$line = "{0:o} deadline reached; killed qemu pids: {1}" -f (Get-Date), ($(if ($killed.Count) { $killed -join ',' } else { 'none' }))
$line | Out-File -FilePath $log -Encoding utf8 -Append
Write-Output $line
