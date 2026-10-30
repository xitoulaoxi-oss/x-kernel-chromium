# trace-followup/01 handoff: command delivery

- Fixed the B3-class failure: 100 ms gap, drain before send, rc saved to a file
  before the marker line, bounded seq and tx/rx trace.
- 20/20 short commands with expected 0/non-zero rc; two new sessions 6/6
  markers and the upload hash verified.
- Attempt ledger has all 12 A/B attempts: pre 6 channel failures, post 5/6,
  B3 channel; no browser-stage failure in either arm.
- No target command is rerun to recover a lost rc; corrupt frames remain
  delivery failures. Status **PASS**.
