# 05 handoff: baseline

- Six plain-x4 rounds under 10 s frame watch; 4 valid, 2 failed (one early
  boot, one startup stall).  Four-metric n>=5 is not met.
- first frame: n=4, median 60.046 s, spread 0.013 s (10 s sampling).
- page load: n=4, median 51.454 s, spread 3.774 s (browser clock).
- renderer timing: 0 samples; the 1 Hz monitor before launch perturbed startup
  (5/5 failed), so its numbers were not used.
- guest peak memory: 0 samples; host QEMU peak: n=6, median 2058 MB.
- The source/bin/ELF/config chain is same-build for this candidate.
- Next: startup stability first; baseline remains **FAIL**.
