# linux_sysno — Security and reliability

## Scope and trust model

This analysis covers all sources and the build script listed in `design.md`,
including feature-gated tables and `cfg(unittest)` tests. Trusted table data
crosses into adapters that receive untrusted register numbers; the crate itself
neither reads user memory nor authorizes syscalls. Its protected internal asset
is the live-value/slot correspondence in `SysnoMap<T>`. Downstream policies must
not treat membership in a syscall table as an authorization decision.

## Inputs and validation

| Entry | Input / direction | Check and outcome |
|---|---|---|
| `Sysno::new` | Caller-provided register number into typed key | Match against compiled table; gaps/unknown numbers produce `None`. |
| Numeric `From` and name parsing | Integer or exact name into enum | `From` panics on invalid numbers; parsing returns `Err(())` for unknown names. Use `new` at an untrusted boundary. |
| `SyscallArgs`, `syscall_args!` | Raw argument words into a value | Packing only; no address, length, flag or permission validation. |
| `Errno::new` | Signed integer into error carrier | No validation. `is_valid` alone also accepts non-positive values. |
| `Errno::from_ret` | Linux return-register word into result | Only encodings of -4095..-1 are errors; other values are returned unchanged. |
| Optional serde | Serialized carriers/table discriminants | Derives provide representation conversion, not syscall authorization; deserialized raw arguments/errno still need boundary validation. |

There is no authentication, direct device/FFI input, inline assembly or syscall
trap instruction in this crate. Macro invocation backends are absent.

## Unsafe inventory and invariants

All explicit production unsafe operations are in `src/map.rs`:

| Site | Operation | Required invariant |
|---|---|---|
| `SysnoMap::clear` | `assume_init_drop` | Every set bit identifies one initialized live `T`; values must not unwind during destruction. |
| `insert` / `remove` | `assume_init` on replaced storage | Existing membership proves initialization; ownership is transferred once, with no subsequent read/drop of the old slot. |
| `get` / `get_mut` | `assume_init_ref` / `assume_init_mut` | Membership proves initialization; receiver borrow supplies lifetime and exclusivity. |
| `SysnoMapIter::next` / `SysnoMapValues::next` | `assume_init_ref` | Set iteration yields only initialized slots; immutable array borrow outlives returned references. |

`DataArray<T>` stays private and numeric indices come from valid native `Sysno`
values. Empty slots remain `MaybeUninit`; the membership set is the validity
witness. There are no hand-written unsafe traits, unsafe impls, FFI or assembly.
Tests use atomics to count drops; this does not add synchronization to the map.

## Thread safety and failure model

No mutable global state exists. Rust borrows and `T`'s auto traits constrain
sharing; callers must synchronize a shared mutable collection. A callback's
resource use and panic behavior remain external obligations. No lock order or
scheduler readiness is established by this crate.

| ID | Threat / trigger / affected asset | Response and residual risk |
|---|---|---|
| T1 | Hostile number passed through panicking `From` terminates a kernel path | Use `Sysno::new`; dispatch's unknown-number policy belongs to `ksyscall`. |
| T2 | Incorrect slot membership reads/drops uninitialized memory | Private fields, typed indices and membership checks guard every unsafe site; preserve all of them when editing the map. |
| T3 | `T::drop` panics during `clear`, leaving already-dropped slots marked live | Require non-panicking destructors. Catching the panic and reusing/dropping the map is not supported; kernel panic policy is external. |
| T4 | Large `T` or extension span exhausts stack | Size map storage explicitly using the selected table; use appropriately placed storage. No dynamic size limit is enforced. |
| T5 | Unchecked errno misclassified downstream or negation of `i32::MIN` overflows during display | Validate positive errno and use checked `kerrno` decoding at serialized boundaries; `Errno::new` intentionally stays unchecked. |

## FMEA

Severity: 1 fatal, 2 serious, 3 moderate, 4 minor.

| ID | Failure / cause | Local effect | System effect | Severity | Handling |
|---|---|---|---|---|---|
| F1 | Unknown numeric syscall | `None`, or panic through `From` | Request rejection or fatal caller path | 2 | Prefer fallible lookup. |
| F2 | Missing map key indexed | Panic | Caller terminates under panic policy | 2 | Use `get` / `contains_key`. |
| F3 | Destructor unwinds | Stale initialized-slot bitmap | Possible repeated drop if unwinding is caught | 1 | Non-panicking `Drop` obligation. |
| F4 | Legacy invocation macro expanded | Unresolved symbol | Build fails; no syscall occurs | 3 | Use runtime/architecture dispatch; compile-fail examples cover limitation. |

## Privacy and verification

The crate stores caller-provided values and does not log or persist them.
Map/errno formatting can expose values to a caller-controlled sink; policies for
sensitive arguments or values belong to that sink. Clearing the map drops `T`
but does not promise byte zeroization of former slots.

Audit `map.rs` occupancy before every `assume_init*`, and preserve drop/replace
ownership tests in its `cfg(unittest)` module. `set.rs` tests cover membership
and iteration; `lib.rs` tests cover numeric lookup. Run configured rustdoc checks
for native coverage and host doctests for executable collection/errno examples.
Use the Cargo `all` feature to check foreign table documentation too. These
checks do not prove unwind safety or runtime architecture dispatch correctness.
