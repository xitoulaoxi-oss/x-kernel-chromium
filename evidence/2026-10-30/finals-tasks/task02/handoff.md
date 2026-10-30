# 02 handoff: startup fix (partial, honest)

- Code: `rearm_local_timer()` now arms a 100 ms fallback idle tick instead of
  disarming when no deadline exists.  This removes one "no wake source" state.
- Candidate: `kernel-final.bin` c50075b6..., ELF 1b0c758d..., same build/config.
- Regression: 25/25.
- But 11/13 first starts passed; C06 and C07 still stalled.  The random
  blank/stall is **not eliminated**.  Readiness-gated launch, in-process GPU,
  no-zygote and GIC EOI mode 0 were tested and were not reliable enough to adopt.
- No reload/restart was used anywhere.  Failed sessions are kept.
- Next: 03 stays FAIL until a 20/20 run exists.
