# 01 handoff: startup failure capture

- Same command run 5 times; run4 failed, run6-10 passed.
- Failure: console dies at `W2 t=15`; QMP says running; all vCPUs at `restore_irq`/idle PC for 20 samples; QEMU CPU/wall 0.215 vs ~1.0 on success.
- Boundary: kernel idle/wakeup, not rendering.
- Curated: `evidence/2026-10-30/startup-capture/`.
- Next: 02 fix idle wakeup (fallback idle tick), then 20 first starts.
