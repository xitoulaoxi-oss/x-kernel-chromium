# irq-driver — Security And Reliability

## Scope

This analysis covers the entire crate: `src/lib.rs` (architecture
dispatch), `src/gic.rs`, `src/gicv2.rs`, `src/gicv3.rs` (AArch64 GIC),
`src/riscv.rs` (PLIC), and `src/x86.rs` (IO-APIC glue). No modules are
excluded; the backend crates (`arm_gic_driver`, `riscv_plic`,
`x86-apic`) encapsulate their own register access and are audited
separately — values they return are treated as hardware facts here.

## Trust Model

The device tree and platform constants select and locate the interrupt
controller; the kernel trusts those boot-time descriptions after
validation. Controller MMIO contents are hardware state programmed only
by this crate and `kirq`. There is no user-space input and no
network/file data path in this crate.

## External Boundaries

- **Device-tree controller description** (`gic.rs`): the
  `interrupt-controller` node's compatible strings and `reg` regions
  determine version and MMIO windows. Checked properties: compatible
  must match a known GIC list, and each detected version must supply
  its required regions (v2: GICD+GICC; v3: GICD+GICR). Failure:
  `None` — platform init applies its own fallback or abort policy.
- **PLIC region**: fixed platform address `0x0c00_0000` with a
  DT-confirmation pass over `sifive,plic-1.0.0` / `riscv,plic0`.
- **Controller MMIO windows**: mapped once through
  `memspace::iomap_device`; all later access stays inside the mapped
  apertures.

## Unsafe Code

Every unsafe site is in a backend wrapper with a `SAFETY:` comment; the
common precondition is that hwirq/interrupt identifiers were validated
by the caller (`kirq` dispatch or platform init):

- `gicv2.rs:25` — `Gic::new(gicd_base, gicc_base, None)`: the bases are
  the iomapped GICv2 MMIO frames from platform discovery.
- `gicv2.rs:43/52/60` — `IntId::raw(interrupt_id as u32)`: wraps a
  caller-validated hardware IRQ number into the backend's integer id.
- `gicv3.rs:25` — `Gic::new(gicd_base, gicr_base)`: bases are the
  iomapped GICv3 MMIO frames.
- `gicv3.rs:43/52/60/83/113` — `IntId::raw(..)`: same wrapping
  precondition; the `:113` site re-wraps an already-acknowledged
  interrupt id for NMI completion.
- `gicv3.rs:117` — `asm!("isb")` after NMI-window register sequences:
  instruction synchronization only.
- `gicv3.rs:136` — `asm!("mrs ICC_RPR_EL1")`: read-only system
  register read used to open the NMI window (feature `nmi-pseudo`).
- `riscv.rs:65` — `Plic::new(NonNull::new(..).unwrap())`: the mapped
  PLIC MMIO base from platform discovery (`unwrap` panics if the
  address were null, which the iomap contract excludes).
- `riscv.rs:86` — `asm!("fence rw, rw")`: orders MMIO setup before the
  hart may take external interrupts.
- `riscv.rs:100/141` — SBI timer programming (`sbiret` handling):
  forwards the supervisor timer deadline to M-mode.
- `riscv.rs:181` — `sip::clear_ssoft()`: clears this hart's software
  interrupt pending bit.

`src/x86.rs` contains no unsafe of its own: register access is
delegated to the `x86-apic` crate. There is no user-pointer access
anywhere in this crate.

## Protected Resources

- `GIC_INFO` / `ACTIVE_GIC` (`LazyInit`): the validated GIC version and
  regions; immutable after init, and re-init with a different config is
  rejected (`remember_config` assert).
- `GIC` (`LazyInit<SpinNoIrq<Gic>>`) and `TRAP_OP`: the GICv3 backend
  handle and its trap operations, installed once.
- `PLIC` (`LazyInit<SpinNoIrq<Plic>>`): the PLIC handle; access before
  init panics with a named `expect`.

## Threat Analysis

| ID | Threat | Impact | Trigger | Existing control |
|----|--------|--------|---------|------------------|
| T-01 | DTB describing a wrong GIC version or truncated regions | Medium — wrong MMIO windows mapped, later accesses fault | Malformed or hostile device tree | Version/region requirements checked per version before any mapping; missing regions yield `None` (no mapping, no access). |
| T-02 | Out-of-range hwirq reaching a backend | Medium — out-of-window register access | `kirq` or platform init passing a bad source number | PLIC and GIC backends bounds-check hwirq before register access; `x86.rs` translates but never invents numbers. |
| T-03 | Interrupt storm from a misconfigured trigger mode | Medium — CPU starvation | Wrong edge/level programming | `configure` only accepts the four known `IrqTrigger` variants and ignores `Unknown`, leaving the line at its reset behavior. |
| T-04 | Double initialization with different configuration | Medium — inconsistent controller state | Platform init calling `init` twice with diverging regions | `remember_config` asserts config equality; GIC/PLIC handles are idempotent on re-init. |
| T-05 | Spurious PLIC claim | Low — wasted IRQ cycle | Level noise on a PLIC line | Claim returns `None`/skip sentinel for timer and IPI events; completion only for genuine device lines. |

## Failure Modes

| ID | Failure mode | Local effect | System effect | Severity | Handling |
|----|--------------|--------------|---------------|----------|----------|
| F-01 | No interrupt controller in the device tree | `init_from_device_tree` returns `None` | Platform init aborts or falls back | 3 | Explicit `Option` at the boundary. |
| F-02 | GIC region MMIO mapping fails | Panic with the region name | Boot fails | 2 | Bring-up ordering bug surfaced loudly. |
| F-03 | PLIC accessed before `init` | Named-`expect` panic | Offending caller aborts | 2 | Initialization-order bug surfaced loudly. |
| F-04 | GIC config re-supplied with different values | `remember_config` assert panic | Platform init aborts | 2 | Inconsistent platform description surfaced loudly. |

## Known Limitations

- The x86 path delegates register access to `x86-apic` and supports only
  IO-APIC trigger/polarity translation; MSIs are composed by the
  `x86-apic` backend, not here.
- GICv3 `dispatch_nmi` semantics depend on the PMR-based NMI window; on
  platforms without FEAT_NMI/pseudo-NMI support the NMI path is
  inactive (`supports_hardware_nmi` reports `false`).

## Audit Checklist

- Backend hwirq bounds checks remain in place before any register
  access.
- New MMIO windows go through `memspace::iomap_device`, never manual
  address math.
- New `IntrManagerIf` methods keep the no-sleeping, no-allocation
  constraint (IRQ-context callers).
