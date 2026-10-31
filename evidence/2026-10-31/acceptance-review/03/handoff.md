# convergence/03 handoff: matched candidates

- Frozen the current trace6 source as a matched pair:
  trace-off `dc69d5cd…` (no ring symbol) and trace-on `23b4237d…`
  (`XK_TRACE_RING ffff80000092eec0`), both built from the same diff and config
  pair, exit 0.
- Both short boots SUCCESS under the new terminal runner. Trace-on capture:
  4096 valid, 0 writer violations / half / corrupt.
- Ring calibration: CPU coverage 0.99/16.79/12.95/14.45 s; CPU0 retained under
  1 s, so freeze timing matters.
- `candidate-lock.json` is the only allowed identity for 04/05/07; no more
  switching trace3/4/5/6.
- Status **PASS**.
