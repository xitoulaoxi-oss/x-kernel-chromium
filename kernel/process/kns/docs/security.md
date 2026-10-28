# kns security and reliability

## Scope, assets, and boundaries

All modules under `src/` are covered. Assets are namespace references, mount
view selection, and UTS name arrays. Kernel callers pass decoded flags,
namespace handles, filesystem contexts, and copied UTS bytes. Syscall adapters
own user-pointer copying and authorization. KVFS owns mount-tree visibility and
lifetime; `fs_context` owns process path references; other namespace owners
retain their respective policy responsibilities.

No direct user-pointer, MMIO, DMA, firmware, device/network packet, FFI, or
assembly input is consumed. UTS setters receive user-controlled byte content
through safe slices. Clone exchanges resolved paths with KVFS and updates the
caller's private filesystem context.

## Unsafe inventory

The sole local unsafe boundary is `src/uts.rs::bytes_from_uts`, which calls
`slice::from_raw_parts` to borrow a `c_char` array prefix as `u8`.

Its private callers pass 65-element `UtsInner` arrays. The length is the first
NUL index or 65, hence within the same allocation. `c_char` is `i8` or `u8`, each
one byte and aligned like `u8`; every stored bit pattern is a valid `u8`.
The output lifetime borrows the original immutable slice, preventing mutation
or release while it is used. `UtsNamespace` callers hold the appropriate lock
while borrowing/copying. No ASCII premise is required: setters only check length.
There is no local unsafe trait impl or FFI/assembly operation.

## Memory invariants and thread safety

`Arc`s keep namespace objects alive. NEWNS requires private root/pwd state and
retargets both paths before returning the bundle. Initial construction reuses
the canonical cgroup namespace. `UtsInner` setters preserve a zero terminator by
reserving the final array byte; embedded NUL is accepted and shortens slice views.

UTS mutable data is protected by its `RwLock`; bundle mutation/publication locks
are owned by process runtime. Mount copy delegates locking to KVFS. Callers
should prepare the new bundle without holding locks that reentrant VFS work
could need, then publish the completed pointer through their runtime protocol.

## Threat analysis

| ID | Threat and asset | Severity | Trigger | Response and residual risk |
|---|---|---|---|---|
| T-01 | False namespace isolation | High | Caller requests unsupported NEW flags | `clone_for_child` returns `Unimplemented`; ID-only types do not prove manager isolation. Syscall policy and consumer state must be audited separately. |
| T-02 | Wrong root/pwd after mount copy | High | NEWNS is combined with shared filesystem state or paths are not retargeted | Shared state returns `InvalidFlagCombination`; private copy uses KVFS retargeting and paired `replace_root_and_pwd`. Caller must supply initialized paths. |
| T-03 | UTS buffer overrun | High | Name length is 65 or greater | Setters return `NameTooLong` before mutation; safe copying and zero-filled arrays retain termination. |
| T-04 | Unauthorized hostname/namespace changes | High | Unprivileged request reaches trusted APIs | Authorization is external; these APIs check data/flag consistency, not caller credentials. |
| T-05 | Misinterpreted hostname text | Low | Name contains NUL or non-UTF-8 bytes | Stored bytes are preserved and slice reads stop at NUL; consumers must handle bytes rather than assume ASCII or full-string round trips. |
| T-06 | Namespace ID collision | Medium | External `NamespaceId` counter wraps | No local wrap prevention; IDs are metadata, not a substitute for live object identity and authorization. |

## Failure modes and effects (FMEA)

| ID | Failure mode | Cause | Local effect | System effect | Severity (1-4) | Handling |
|---|---|---|---|---|---|---|
| F-01 | Unsupported clone | Unimplemented namespace bit | Typed error | Child creation rejected | 3 | Caller translates `Unimplemented` to its ABI. |
| F-02 | Mount clone fails | KVFS copy/retarget error | `CloneNsError::Mount` | No successful child bundle | 3 | Preserve underlying `VfsError`. |
| F-03 | Premature initial construction | VFS mount namespace absent | `expect` panic | Process boot fails | 2 | Initialize VFS before `new_initial`. |
| F-04 | Private paths absent | NEWNS on uninitialized `FsStruct` | Root/pwd reader panic | Clone fails fatally | 2 | Construct a mounted private context first. |
| F-05 | Name too long | More than 64 input bytes | `NameTooLong`, no change | UTS update rejected | 3 | Report typed error. |

## Failure handling, privacy, and limitations

This crate chooses typed errors, not errno. It has no retry/rollback manager
beyond ownership cleanup of partially constructed values. Allocation follows the
kernel allocator policy. Hostname/domainname and namespace IDs may reveal system
identity to consumers; this crate does not log them or handle other user payload.
Only selected namespace clone behaviors are implemented; user/capability and
namespace-FD policy is external, and IPC/net/time payloads are not owned here.

## Audit checklist

- Reject unsupported flags before constructing a child bundle.
- Preserve private, initialized filesystem context for NEWNS.
- Keep UTS bounds, one-allocation borrowing, and byte semantics aligned.
- Preserve the single initial cgroup hierarchy reference.
- Define owner, locks, authorization, and cleanup when adding namespace state.
