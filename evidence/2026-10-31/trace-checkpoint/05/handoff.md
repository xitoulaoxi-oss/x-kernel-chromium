# trace-followup/05 handoff: frozen export

- `host/ring_capture.py` freezes the VM, validates the header and 1 MiB cap
  before reading, reads 164224 B in 4096 B chunks with per-chunk length checks,
  saves the raw dump and sha256, and only resumes with explicit `--resume`.
- Success: 4092 events, dump sha256 42a607b6…, paused before read, resumed and
  timestamped afterwards.
- Wrong symbol: header rejected, 128 B partial + sha256 saved, VM left paused,
  no auto-cont; a separate manual resume recorded paused→running.
- Active ring is not compared normal-vs-paused; that comparison belongs only to
  the old 128 B channel test.
- Status **PASS**. Next: 06 first-missing-event search.
