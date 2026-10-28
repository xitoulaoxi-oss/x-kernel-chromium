# Process documentation audit

## Scope and provenance

This is a full documentation audit of the 15 crates listed below, based on
`origin/main` at `3f6080adb05ee39e4e7dbd31149de68fb7a5c0ce`, on branch
`debin/process-docs`. A dedicated agent retrieved and summarized the review rules
and checked four modules; the primary agent handled the other modules and final
validation. The agent also cross-checked the final kexec/kns descriptions.

The [x-review rules repository](https://gitee.com/luodeb/x-review/tree/dce1dd093c9371d0ad906d69084b7ae646a4e8f6)
was read at commit `dce1dd093c9371d0ad906d69084b7ae646a4e8f6`.
Its maintained source is `module-docs/check.xlsx`; the runtime consumes:

- [rustdoc-checks.tsv](https://gitee.com/luodeb/x-review/blob/dce1dd093c9371d0ad906d69084b7ae646a4e8f6/module-docs/rustdoc-checks.tsv): 28 rules.
- [design-doc-checks.tsv](https://gitee.com/luodeb/x-review/blob/dce1dd093c9371d0ad906d69084b7ae646a4e8f6/module-docs/design-doc-checks.tsv): 21 rules.
- [security-doc-checks.tsv](https://gitee.com/luodeb/x-review/blob/dce1dd093c9371d0ad906d69084b7ae646a4e8f6/module-docs/security-doc-checks.tsv): 22 rules.

Supplementary local sources were read from the checked-out source branch:
`docs/ai/review/{README,common,guidelines}.md`, and the shared module-docs,
code-guidelines (including comments/rustdoc and unsafe topics), and build-workflow
skills. This was a local source audit, not an invocation of the x-review service
or a PR finding pipeline.

## Rule summary

| Area | Required checks | Expected supporting material |
|---|---|---|
| Rustdoc | English prose unless explicitly exempt; nonempty crate docs on each lib/bin root; bound docs for externally reachable modules, items, fields, variants and trait associated items; current names/re-exports; concrete Safety contracts for unsafe APIs; real compiler evidence for strict checks. | Purpose and entry points, useful examples, Errors for Result paths, Panics for explicit panic paths, accurate links and code-block attributes. |
| Design | Every audited crate has nonempty `docs/design.md`; referenced source paths, modules, members, dependencies, features, states and errors exist and match the code. | Responsibilities and non-goals, interface/call directions, execution contexts, shared-state locks, actual state transitions, construction/cleanup and unsupported capabilities. |
| Security | Every audited crate has nonempty `docs/security.md`; each threat identifies an asset/boundary, trigger, impact and response; every local unsafe/FFI/asm boundary is traceable and agrees with its code/SAFETY explanation; controls and failure results are real. | Scope and external responsibilities, protected assets, inputs/checks/authorization, specific mitigations and residual risks. Local rules additionally call for FMEA, privacy and audit checklists. |

A full audit covers existing prose and APIs, not only the diff. Chinese heading
templates in the local skill are not an explicit exemption requiring Chinese
body text. The corrected module documents use English headings and prose.
MUST, SHOULD and MAY remain distinct; the text was checked against applicability,
not by adding empty template sections.

## Findings and corrections by crate

All 15 crates required documentation corrections. Runtime implementation was not
changed to conceal or fix the behavioral limitations found while documenting it.

| Crate | Path | Corrected gaps / stale facts |
|---|---|---|
| kcgroup | `process/kcgroup` | Added explicit scope, execution/lock constraints, structured threats/FMEA/privacy and API error/commit-panic contracts; clarified stable identity versus numeric uniqueness, guard lifetime and migration limits. |
| kcred | `process/kcred` | Replaced non-English/outdated module prose, completed namespace coverage and contextual policy responsibilities, documented checked errors and ID-wrap limitations, added a usable snapshot example. |
| kexec | `process/kexec` | Replaced obsolete Location descriptions with Path; documented execute checks, bootstrap fs fallback, fallible post-clear work, cache lifetime gap/invalidation, parser assertions and delegated generated self-reference safety. |
| kidentity | `process/kidentity` | Removed stale PID-2/worker assumptions; documented fixed-number non-reservation, root fallback, counter exhaustion without rollback, context and lifetime; added error/panic contracts and example. |
| kns | `process/kns` | Completed public flags/variant docs and clone/UTS errors; corrected ASCII-only safety claim, invalid flag example, unshare/setns implications, and NEWIPC identity versus global IPC-manager isolation. |
| kprocess | `process/kprocess` | Updated process/runtime ownership, publication/exit/reap states, lock order, callbacks and sole explicit unsafe boundary; completed public Result/panic contracts, removed stale private links and added publication/MM examples. |
| kresources | `process/kresources` | Added both missing module documents; covered detached-owner lifecycle, slot/limit lock order, close errors, direct public limits access and fixed-slot duplication policy; completed API contracts. |
| krlimit | `process/krlimit` | Added both missing module documents; described defaults, units, unchecked pairs/indexing panic and external enforcement; expanded crate and constructor documentation. |
| fs_context | `process/fs_context` | Expanded scope, initialization/clone/exec flag semantics, path authorization limits, FMEA and lifecycle; documented setter errors, reader/constructor panics and attachment sequence. |
| kfd | `process/kfd` | Removed deleted FileLike/file_like.rs/downcast API descriptions; documented current VfsFile ownership, snapshot/dup/close behavior and ABI zero-validity without overstating padding guarantees; completed API errors. |
| kfd_objects | `process/kfd_objects` | Documented all object implementations, unsafe tests/union boundary, actual semaphore result, timer waker retention and epoll concurrency; completed public Result contracts and example. |
| posix-process | `posix/process` | Corrected robust-futex before clear_child_tid ordering and obsolete terminal-binding panic statement; documented bootstrap, trap/exit integration and unsafe paths; added lifecycle example/contracts. |
| posix-ipc | `posix/ipc` | Expanded both managers and full unsafe/input coverage; corrected repeated same-PID shm attach, actual shmdt lock nesting, UID-zero message policy and broad IPC_SET replacement; completed public API docs. |
| cgroup-test | `uapps/cgroup-test` | Added both missing documents and bin crate docs; recorded guest prerequisites, exact PASS conditions, fork FFI and failure-path leftovers/root controller mutation. |
| mini-oci | `uapps/mini-oci` | Added both missing documents and docs for both binaries; included bundle example, all FFI sites, namespace/config subset, trusted-input requirement, retained groups and incomplete teardown. |

The resulting module set contains 30 design/security documents. All public-item
coverage results below refer to the configured compilation, not every possible
architecture or feature combination. The Rust diff consists of comments and
removal of rustdoc diagnostic-suppression attributes, with no runtime-code
changes after whitespace-normalized comparison.

## Validation and evidence boundaries

Configuration used the actual checked-out layout and toolchain:

```sh
cp platforms/kplat-aarch64/qemu_defconfig .config
make defconfig
```

The repository pins Rust `1.95.0`. Formatting followed the requested shared
workflow using `cargo +nightly-2026-03-08 fmt --all --check`; separate uapp
workspaces were checked with their own manifests. Formatting and
`git diff --check` passed.

| Check | Result | Exact boundary |
|---|---|---|
| Unrestricted `make doc_check_missing` | Blocked outside the requested scope | Existing missing-doc failures in kernel-elf-loader, rs_fdtree and firmware-handoff prevented full workspace completion. These were not masked or edited. |
| Scoped `make doc_check_missing` | Passed | Same resolved AArch64 Kconfig/target; excludes unrelated workspace packages, retains all 13 requested kernel crates plus kfeat, which must be selected for Kconfig feature activation. |
| Rustdoc diagnostics | Passed for selected kernel crates | Explicit `--force-warn` enabled broken/private intra-doc links, invalid codeblock attributes, invalid Rust codeblocks, invalid HTML tags, unescaped backticks and bare URLs. No corresponding diagnostics; only third-party future-compatibility summary warnings remained. |
| Standalone uapp docs | Passed | `cargo doc --no-deps --bins` on both manifests, with missing-docs denied and the same seven rustdoc lints explicitly enabled. Covers cgroup-test, mini-oci and oci-test-init. |
| Independent-library doctests | Passed | `cargo test --doc -p krlimit -p kidentity -p kcred --target x86_64-unknown-linux-gnu`; all three examples compiled and ran successfully. These libraries do not need the kernel runtime for these examples. |
| All 17 Rust documentation examples | Type checking passed | Extracted snippets compiled as no_std library metadata against the AArch64 dependency artifacts from the configured documentation flow. This checks types/API use; it is not linking, a standard kernel doctest run, or execution. |
| Structure/language/source integrity | Passed | All 15 crates have both nonempty documents; no CJK body text remained in target module docs/rustdoc; changed Rust code compared unchanged after removing comments/whitespace and the two documentation suppression attributes. |

`make doc` does not execute examples. Kernel-dependent examples remain unverified
for full doctest linking/execution under RD-009; the standalone type check is
additional evidence, not a substitute. Guest cgroup/OCI workloads, QEMU boot,
other architectures and unselected feature combinations were not executed by
this documentation change. No test was marked ignore merely to claim success.
The unrestricted workspace check must not be reported as passed.

The audit session retains the rule-agent summary and validation logs in its
attached evidence archive. The selected-kernel command and example type-check
script are included there for reproducibility; scripts refer to the isolated
worktree `/root/codes/x-kernel-process-docs`. The original worktree's preexisting
`xtask/Cargo.lock` modification was preserved. Build-generated lockfile drift in
the new worktree is excluded from the documentation commit.
