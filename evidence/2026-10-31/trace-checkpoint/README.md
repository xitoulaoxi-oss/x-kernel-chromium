# Trace-ring diagnostic checkpoint — 2026-10-31

01–05 have implementation and scoped test evidence: delivery receipts, a 164224-byte default-off per-CPU ring, diagnostic/closed builds, real timer/idle/IPI-receive events, and bounded frozen capture. The startup stall is unresolved; no full qualification or performance improvement is claimed.

The current code is an intermediate diagnostic checkpoint. Publication review found a full-capacity decoder off-by-one and acceptance of an entry sequence newer than the metadata cursor; see checks.json. The writer still needs IRQ/preemption/re-entry and publication-order review. IPI-send/enqueue/schedule events are not implemented. Fix and validate these before treating a missing event as causal evidence.

Published here: original result/handoff records, schema, build/address identity, a representative event chain, capture success/failure metadata, and offline check output. The original records retain their original local source paths. Immutable raw logs, VM images, ELF/bin files, full dumps and repeated screenshots remain local under experiments/FINALS-RUNS/20261031T014800Z/trace-followup/. Those local paths are provenance, not online download links.

capture.bin: 164224 bytes, SHA-256 42a607b6d87ba8ec7bf056fde5535a246a2f2f67254d0852fdfdf745f3c472ff (locally rechecked). Boot-overhead samples are two per arm at 0.1-second resolution and do not prove zero observer overhead during Chromium startup.

Re-run: python tests/ring_layout_test.py; python tests/observe_cases.py; python tests/review_regressions.py. PowerShell delivery/step/path/syntax checks are listed in checks.json. Build success is existing logged evidence, not a new kernel build in this publication turn.
