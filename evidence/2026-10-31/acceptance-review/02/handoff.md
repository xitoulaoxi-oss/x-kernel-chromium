# convergence/02 handoff: reliable terminal states

- `host/attempt_runner.py` now requires exit 0 + metrics + zz-final + owned
  QEMU PID, and checks the owner image is qemu-system-aarch64.
- Real records: short2 SUCCESS (exit 0, owner alive), controlled boot timeout
  TIMEOUT (exit 2, outer terminated, QEMU left for evidence then explicitly
  cleaned).
- Seven offline negatives pass; fake metrics or a foreign QEMU cannot PASS.
- Status **PASS**.
