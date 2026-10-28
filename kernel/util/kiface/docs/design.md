# kiface Design

`kiface` provides procedural macros for explicit kernel interface wiring.  The
first supported interface shape is an exactly-one provider boundary for
stateless, associated-function-style calls across crate layers.

## Responsibilities

- Define the `#[kiface::interface]` attribute macro: it parses the
  trait-shaped contract (`src/interface.rs`), generates the uninhabited
  facade type plus a hidden `unsafe extern "Rust"` declaration module,
  and emits the direct inherent methods callers use.
- Define the `#[kiface::provide]` attribute macro: it turns an
  inherent-impl-shaped block into exported Rust-ABI symbols
  (`src/provide.rs`) and type-checks each provider method against the
  interface facade at provider compile time.
- Own symbol naming (`src/naming.rs`) and attribute-argument parsing
  (`src/args.rs`); both sides must agree on the namespace.

Everything the generated code does at runtime is owned by the two sides
the macros wire together: the interface crate owns the contract, the
provider crate owns the behavior. This crate ships no runtime component.

## Dependencies

Build-time only: `proc-macro2`, `quote`, and `syn`. The crate is a
`proc-macro` library, so none of these reach the final kernel image; the
generated code depends on nothing beyond `core`.

## Interface Model

The definition side writes a trait-shaped contract:

```rust
#[kiface::interface]
pub trait KernelEntry {
    fn primary(boot_info: usize) -> !;
}
```

The macro expands this into an uninhabited facade type with direct inherent
methods, so callers use:

```rust
KernelEntry::primary(boot_info)
```

The provider side writes an inherent-impl-shaped block:

```rust
#[kiface::provide]
impl KernelEntry {
    fn primary(boot_info: usize) -> ! {
        rust_main(boot_info)
    }
}
```

The provider macro exports one Rust-ABI symbol per interface method and checks
the provider method signature against the generated facade method. The interface
macro declares the matching extern symbols and wraps each call in the facade
method.

Generated calls run in whatever context the caller runs in: the facade
method is a plain inline call through a function symbol with no runtime
component of its own, imposes no locking, allocation, or scheduling
assumptions, and is valid wherever both the caller and the provider body
are valid. The provider side rejects `unsafe` methods, receivers,
generics, `async`, `extern`, variadic signatures, and default bodies at
macro-expansion time (see the Current Restrictions section of
`docs/security.md`).

## Scope

The current `interface` implementation is for exactly-one, stateless wiring
points. It is intended for single-implementation cross-crate interfaces and to
avoid accidental `linkme` registries where the real contract is not one-to-many.

`#[kiface::interface(optional)]` is reserved for a future explicit optional
provider mode. The attribute argument is parsed (`src/args.rs`) but any use
today is rejected with a compile error (`src/interface.rs`); it never
silently degrades to the required-interface path. The intended user-facing
shape is to generate `try_*` methods that return `Option<R>` rather than
silently falling back to defaults. It is not implemented yet; `kiface`
should wait for stable weak-symbol support such as `extern_weak` rather
than adding a registry dependency for this single-provider case.

It intentionally does not model:

- one-to-many static registration;
- stateful opaque objects;
- dynamic runtime dispatch;
- default implementations.

Stateful object support should extend `interface` later, while registry support
should remain a separate `kiface` concept because it is one-to-many.
