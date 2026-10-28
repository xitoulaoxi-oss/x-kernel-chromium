# char — Security And Reliability

## Scope

This analysis covers the entire crate — `src/lib.rs`, the `CharDevice`
trait plus the `driver_base` re-exports. The crate defines no other
modules and holds no state; obligations placed on implementers are
recorded because this contract layer cannot enforce them itself.


## Trust Model

This crate is a pure contract layer: one trait, no state, no I/O. There
is nothing to attack here directly; the security-relevant decisions are
the obligations the contract places on implementers and callers, recorded
below so reviewers can check driver conformance.

## External Boundaries

None of its own. Character devices implementing `CharDevice` own the real
boundaries (device registers, user byte streams); this crate defines
neither. If a `char` device ever consumes user memory directly, the
boundary lives in the driver's `read`/`write` implementation and must be
documented there.

## Unsafe Code

None. The crate contains no `unsafe`, no FFI, and no inline assembly.

## Invariants

- `read` returns at most `buf.len()` bytes; `Ok(0)` is reserved for
  end-of-stream on finite sources.
- `write` reports only bytes actually accepted; drivers must not spin
  waiting for progress (`WouldBlock` instead).
- Neither method takes user pointers: buffers are kernel-provided slices.

## Threat Analysis

| ID | Threat | Impact | Trigger | Existing control |
|----|--------|--------|---------|------------------|
| T-01 | Driver overfills the caller's buffer | High — kernel buffer overflow | Misbehaving `read` implementation | The `CharDevice::read` doc contract (src/lib.rs) states the `n <= buf.len()` bound; enforcement is by driver review against that documented obligation, since a trait cannot constrain an arbitrary implementation. Accepted at the driver trust level. |
| T-02 | Blocking inside a driver | Medium — scheduler stall | `read`/`write` spinning on hardware | Contract mandates `WouldBlock` instead of spinning; verified by review. |
| T-03 | Stale data leaks into user-visible streams | Medium — kernel data disclosure | Device returns unzeroed buffers | Out of scope for the contract; drivers own buffer initialization. Recorded as a driver-side audit item. |

## Failure Modes

| ID | Failure mode | Local effect | System effect | Severity | Handling |
|----|--------------|--------------|---------------|----------|----------|
| F-01 | Hardware error during read/write | `DriverError` variants returned | Caller retries or reports | 3 | Error propagation via `DriverResult`. |
| F-02 | No data available | `DriverError::WouldBlock` | Caller decides to wait or drop | 3 | Explicit non-blocking contract. |

## Known Limitations

- Trait-level review is the only defense against a misbehaving
  implementation; Rust cannot check driver conformance statically here.

## Audit Checklist

- New trait methods must state their non-blocking and buffer-bound
  obligations explicitly.
- Any default method added must be side-effect free unless documented.
