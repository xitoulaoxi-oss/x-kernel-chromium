# Startup diagnosis and task execution

2026-10-30. Task book: [numbered tasks](tasks/00_taskbook.md).

## What was executed

- Preserved historical guest-wide used-memory samples (about 840 MB; raw maximum 841). The project adopts these for its Chromium budget, not as exact summed process RSS.
- Added opt-in host QMP/status/register sampling (`-DiagnosticPollSec`) and `guest/startup-probe.sh`. Rendering flags and kernel binary were unchanged. Diagnostics are not performance measurements.
- First real run reached the guest script but failed with `set: illegal option`: the local process-identity shell script contained CRLF. Corrected the local file to LF and added staging-time rejection. Five staging cases and 25 acceptance regression cases pass.
- Same diagnostic command after the correction returned 0 and verified the actual official HTML document. The failed attempt remains archived.
- A separate run with diagnostic sampling disabled passed keyboard echo, mouse link navigation, and browser-reported renderer ancestry (input subset 2/2). This is not a full functional or 20-start reliability PASS.

## Interpretation

Repeated CPU PCs alone did not establish a deadlock: guest clock samples continued advancing. The retained ELF also exports a binary with a different SHA-256 from the active kernel; its source-line mapping is provisional. No kernel scheduler/IRQ patch was made on that basis. Obtain matching symbols before deeper source-level diagnosis.

Whole-guest physical allocation was additionally sampled as `MemTotal - MemFree`, without subtracting cache. Both diagnostic runs stayed below 1.5G at all recorded samples (sampled maximum about 937 MiB). This supports the project budget rationale; it is not a continuous high-water mark or an exact per-process RSS measurement. See [memory record](../evidence/2026-10-30/memory-budget.json).

## Next actions

1. Capture actual document state before the second window is launched, comparing the single-window success with the previous two-window about:blank failure.
2. Preserve matching kernel/bin/ELF/config metadata; distinguish normal idle from lost progress using clock/serial/QMP jointly.
3. Validate a complete functional run and then twenty independent first starts for a qualified fix candidate.
4. Continue the four-metric baseline and optimization tasks in order.

Curated evidence: [finals-followup](../evidence/2026-10-30/finals-followup/manifest.json). Raw output remains in ignored local experiments/FINALS-RUNS; no browser download caches or VM images were added.
