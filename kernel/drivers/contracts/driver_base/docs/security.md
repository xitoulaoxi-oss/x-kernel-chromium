# driver_base — Security And Reliability

## Scope

This analysis covers the entire crate — the single `src/lib.rs`
(`DeviceKind`, `DriverError`, `DriverResult`, `Device`). The crate is
pure type definitions with no state and no unsafe code; nothing is
excluded.


## Trust Model

```
Driver sub-crates (block, net, display, input, vsock, virtio, kdriver)
   │
   │ safe API: DeviceKind, DriverError, DriverResult, Device
   │
   v
┌──────────────────────────┐
│  driver_base             │
│                          │
│  ┌── unsafe boundary ──┐ │
│  │  (no unsafe code)   │ │
│  └─────────────────────┘ │
└──────────────────────────┘
```

- **Safe-API callers**: the module provides only pure safe type
  definitions and traits; callers need no extra safety proof.
- **Unsafe-API callers**: none — there is no unsafe API.

## Unsafe Code Inventory

The module contains no `unsafe` blocks, `unsafe fn`s, or `unsafe impl`s.

## Memory-Safety Invariants

With no unsafe code, no additional memory-safety invariants need
maintaining. All types are `Copy` or pure trait definitions; there is no
heap allocation and no raw-pointer manipulation.

## Thread Safety

| Type | `Send` condition | `Sync` condition |
|------|-------------|-------------|
| `DeviceKind` | auto `Send` (`u8` enum, `Copy`) | auto `Sync` (`u8` enum, `Copy`) |
| `DriverError` | auto `Send` (`Copy` enum) | auto `Sync` (`Copy` enum) |
| `DriverResult<T>` | `Send` when `T: Send` | `Sync` when `T: Sync` |
| `Device` | trait requires `Send + Sync` | trait requires `Send + Sync` |

## Threat Analysis

| ID | Threat | Impact | Trigger | Existing control |
|------|----------|----------|----------|----------|
| T-01 | A `Device` implementer returns an inconsistent `DeviceKind`, so the device is managed by the wrong subsystem | Medium | Driver bug: `device_kind()` disagrees with the actual device type | Sub-crates validate `DeviceKind` against their trait at registration; flagged in code review |
| T-02 | `Device::name()` returns an empty string or invalid UTF-8 reference | Low | Driver implementation bug | `name()` returns `&str`, so Rust guarantees UTF-8 validity; an empty string affects only log readability, not safety |
| T-03 | A new `DriverError` variant is not exhaustively handled by callers | Low | `DriverError` extended without updating all `match`es | Compiler-enforced match exhaustiveness; `should_retry()` and `message()` are the centralized update points |

## Failure Modes And Effects Analysis (FMEA)

| ID | Failure mode | Cause | Local effect | System effect | Severity | Handling |
|------|----------|----------|--------|------|----------|----------|
| F-01 | A `Device` impl returns the wrong `DeviceKind` | Implementer mistypes the `device_kind()` return value | Device routed to the wrong subsystem | Device unavailable; no memory-safety impact | 3 | Subsystem registration validation; code review |
| F-02 | `irq()` returns the wrong interrupt number | Implementer mistypes the IRQ number | Interrupt routed to the wrong handler | Device interrupts lost or mishandled | 2 | The interrupt registration framework should validate IRQ numbers |
| F-03 | `should_retry()` returns false for a new error variant | `DriverError` extended without updating `should_retry()` | Retryable error treated as permanent | Non-blocking operations fail early | 4 | Compiler-enforced match exhaustiveness forces the update |
| F-04 | `message()` returns a wrong description for a new variant | `DriverError` extended without updating `message()` | Inaccurate logs | Harder debugging; no safety impact | 4 | Compiler-enforced match exhaustiveness forces the update |

## Failure Management

- **Error codes**: the `DriverError` enum covers common driver failure
  scenarios with clearly separated variants.
- **Panic policy**: the module has no panic paths.
- **Recovery**: `should_retry()` gives callers a retry signal; the actual
  recovery policy belongs to the caller.

## Privacy Analysis

The module processes no user data; no privacy concerns apply.

## Known Limitations

1. `DriverError` is a fixed enum and cannot carry additional context
   (underlying error codes, offsets, ...); callers needing detailed error
   information must pass it through other mechanisms.
2. `Device::irq()` returns `Option<usize>` and cannot express devices
   with multiple interrupts (multi-queue NICs); a slice-returning
   extension may be needed later.

## Audit Checklist

When modifying this module, verify:

- [ ] Every `unsafe` block has a `SAFETY:` comment (currently none
  exist).
- [ ] Adding a `DeviceKind` variant updated all exhaustive `match`es.
- [ ] Adding a `DriverError` variant updated `should_retry()` and
  `message()`.
- [ ] `Device` trait changes are breaking changes — all implementers are
  updated in the same change.
- [ ] New panic paths have a PanicGuard or equivalent protection
  (currently no panic paths exist).
