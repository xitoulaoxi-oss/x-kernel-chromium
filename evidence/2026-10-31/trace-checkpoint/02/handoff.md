# trace-followup/02 handoff: ring layout

- 40-byte entries now carry ticks/kind/cpu/flags; 4x1024 entries + header +
  per-CPU metadata = 164224 B, under the 192 KiB budget.
- Commit, half-write, wrap, retained range and cross-CPU order rules are
  explicit in `ring-layout.json`.
- Decoder and 12 tests pass, including wrong schema/length/cpu/checksum/magic,
  duplicate seq and a short buffer.
- No kernel object or writer yet; task 03 builds that. Status **PASS**.
