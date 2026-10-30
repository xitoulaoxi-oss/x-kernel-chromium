# trace-followup/03 handoff: static trace storage

- Added `XK_TRACE_RING` (164224 B, .bss), Kconfig `KFEAT_TRACE_RING` default n,
  kfeat/ktask features, and one boot init + self-test record.
- Built both configurations: open `kernel-trace.bin 182e5b…`, closed
  `kernel-notrace.bin 4b6321…`; closed ELF has no symbol and the config feature
  is absent.
- Open short boot: host read at physical 0x40b2dd80 (symbol ffff80000092dd80 -
  kimage_voffset) got magic XKRING02/schema 2/4 CPUs/nonce 16137862 and a
  committed kind-1 self-test; normal and stopped reads were identical.
- Formatting of the modified files passes. Full-tree fmt has unrelated
  pre-existing diffs.
- Status **PASS**. Next: 04 real timer/wakeup events.
