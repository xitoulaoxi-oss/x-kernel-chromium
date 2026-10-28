# kidentity design

## Purpose and background

`kidentity` owns the process domain's PID/TID number-space model. `kns` re-exports
its namespace type; task/process creation and cgroup membership consume stable
`Arc<PidHandle>` identities. Lookup tables, process publication, scheduling,
permissions, and complete PID-namespace syscall semantics belong to upper
layers. Keeping number allocation separate lets those owners share identity
without introducing a catch-all process crate dependency.

## Scope and architecture

`src/lib.rs` contains all types, allocation functions, and kernel unit tests.

```text
PidNamespace { parent: Option<Arc<_>>, level: u32, next_nr: AtomicU32 }
       ^
       | Arc ownership
PidHandle { numbers: Vec<Upid> } -> Upid { nr: u32, ns: Arc<PidNamespace> }
```

The namespace parent chain is immutable. Each root/child allocator starts at
one. `root_pid_namespace` lazily publishes a shared root with `LazyInit`.
`PidHandle` stores number projections from the active namespace to the root.

## Execution context

The crate has no current-task, scheduler, address-space, or CPU-local dependency.
Allocation requires a working heap. It does not intentionally sleep, although
lazy initialization may wait for another initializer and allocation follows the
allocator's context contract. Pure accessors are usable wherever a valid handle
can be borrowed; do not assume allocating APIs are interrupt-safe merely because
the number counter is atomic. Early process initialization can use them once
allocation is available.

## Allocation and lookup algorithms

`allocate_in` first collects the ancestor chain, then increments each namespace's
counter with checked `fetch_update` (AcqRel success, Acquire failure). Exhaustion
returns `WouldBlock` without wrapping. Already consumed numbers in descendant
namespaces are not rolled back if a later ancestor allocation fails. There is no
reuse on drop; `u32::MAX` itself is not returned because incrementing it fails.

`root_nr` finds the root projection and expects one to exist. `nr_in` first
compares namespace `Arc` identity; a missing non-root namespace yields `None`.
A different root namespace deliberately falls back to the root projection.
`fixed_root(nr)` creates a root-only projection without reserving or checking the
counter, so trusted callers must prevent conflicting numeric registrations.

## Concurrency and design decisions

Only `next_nr` is mutable and atomic. Immutable handles and ancestor references
can be shared without locks. A vector and linear lookup keep the representation
simple for shallow namespace trees; no depth cap or number reclamation is
implemented. Stable allocation is distinct from publication: callers must finish
identity registration before making tasks runnable.

The first ordinary root allocation is expected to serve PID 1 during boot.
Boot/idle/ordinary kernel workers use PID-less identities in their owners; this
crate does not reserve special roles or cache an init-only handle.

## Drop and limitations

Dropping a handle frees its vector and namespace references once the final `Arc`
is gone. Children retain their ancestors, but ancestors do not retain children,
so this graph has no ownership cycle. Counters never decrement. Namespace depth
addition is not checked, and fixed projections need external uniqueness policy.
This module alone does not provide Linux PID namespace isolation or lifecycle
transactions.
