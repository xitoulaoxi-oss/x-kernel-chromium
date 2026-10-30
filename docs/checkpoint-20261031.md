# 2026-10-31 diagnostic checkpoint

This branch saves the accumulated harness corrections, candidate idle-tick change, default-off ring implementation, frozen-capture tools and selected evidence. It is not a stable-release claim. The 100ms idle fallback has not eliminated random startup stalls.

Evidence and current limitations: [trace checkpoint](../evidence/2026-10-31/trace-checkpoint/README.md). Next: repair decoder/writer integrity and fill missing wakeup boundaries, then capture a same-version success/stall pair. Timing/identity metrics, observer controls and final acceptance follow.

Raw experiment folders and duplicate submission packages remain local. Only representative baseline JSON and source/config/test files are included. Binary builds are not published by this push. Historical task plans are retained for provenance; their experiments/ paths refer to local archives.
