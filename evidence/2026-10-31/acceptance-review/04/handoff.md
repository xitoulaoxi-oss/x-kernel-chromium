# convergence/04 handoff: bounded reproduction

- Four interleaved rounds, fixed candidate-lock:
  trace-off single SUCCESS, trace-on single SUCCESS, trace-off double SUCCESS,
  trace-on double SUCCESS.
- Single-window rounds reached W5/wins=1; double-window rounds reached
  N6/N7/wins=2. No W2 stop and no about:blank failure was reproduced.
- Trace-on captures: 4096 valid records each, 0 writer violations.
- Conclusion: **this candidate did not reproduce the historical failure**; the
  root cause is not claimed fixed. Proceed to 05 qualification.
- Scope limit: these rounds checked script/window completion, not the full
  DOM/interaction suite.
