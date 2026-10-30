# Acceptance commands

Run from the repository root on Windows PowerShell 5.1 with Python 3.11+ and QEMU 8.0+. Pass the supplied image explicitly with `-Disk "<image-path>"` and kernel with `-Kernel artifacts/kernel-procfs.bin`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-finals.ps1 -Mode preflight -Disk "<image-path>"
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-finals.ps1 -Mode smoke -Disk "<image-path>"
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-finals.ps1 -Mode functional -Disk "<image-path>"
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-finals.ps1 -Mode load -Disk "<image-path>" -Runs 10 -IntervalSec 120
python tests/review_regressions.py
```

Functional subsets: `tests/functional.ps1 -CheckSet windows,input,js,css`. Smoke checks actual official-page DOM completion. Local CDP automatically uses the snapshot-only guest policy adjustment; `-Writable` is rejected with it. Host forwarding binds loopback only.

Load/stability verify a full 1800 seconds with ten real new navigations at absolute 120-second intervals, continuous heartbeats and a final frame. Failure returns nonzero. Missing evidence never means success. Only processes started by the current harness are cleaned up.

`perf` remains an incomplete collector and returns failure for official qualification. `python host/perf_run.py --collect-only --repeats 5` collects diagnostic values only. Guest Chromium memory, host QEMU memory and guest overall memory have distinct meanings.

Linux CSS reference: `tests/linux_css_reference.py`, using an explicitly supplied same-version browser and font configuration. It records actual viewport and source hashes. See [current evidence](../evidence/README.md).
