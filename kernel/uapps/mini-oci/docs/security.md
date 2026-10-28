# mini-oci security and reliability

## Scope, assets, and trust boundaries

Both binaries (`src/main.rs` and `src/test_init.rs`) are in scope. Assets include
guest filesystem mounts, the selected rootfs, cgroup membership, child identity,
pipe endpoints, and the executed program/environment. The launcher trusts its
operator, bundle, and kernel. Treat the bundle as privileged input: it is not a
safe boundary for hostile container specifications.

CLI values select bundle and cgroup paths; JSON supplies mount paths, hostname,
credentials, and executable data. `serde_json` checks JSON types, `cstring`
rejects embedded NUL in paths, and mount destinations must be absolute.
Capabilities/seccomp fields are rejected when present at their modeled process
locations. Unknown JSON fields and mount options are otherwise not rejected.
Mount, chroot, credential, and namespace permissions are enforced by the kernel,
not independently authorized by this launcher. No MMIO, DMA, firmware, network
I/O, or inline assembly is used directly.

## Unsafe and FFI inventory

All entries below are in `src/main.rs`; `src/test_init.rs` has no unsafe code.
They use the platform libc ABI, not a manually declared assembly/register ABI.

| Function / operation | Inputs and outputs | Required invariant and guard |
|---|---|---|
| `mount`: `libc::mount` | Optional source/type strings, target, flags; null data | Non-null pointers reference live NUL-terminated `CString`s for the syscall. The type strings at callers are fixed `proc`/`tmpfs`; path conversion rejects NUL. |
| `enter_container`: `libc::read` | Live read pipe FD, one writable byte | Parent/child setup supplies the endpoint; the stack array covers the requested byte and remains live. A non-one result aborts setup. |
| `enter_container`: `libc::sethostname` | String pointer and byte length | Borrowed hostname bytes remain readable for the complete call. |
| `enter_container`: `libc::prctl` | Scalar `PR_SET_NO_NEW_PRIVS` and arguments | No pointer dereference; kernel validates operation and permission. |
| `enter_container`: `libc::chroot` | Root path pointer | Local `CString` remains live and NUL-terminated. |
| `enter_container`: `libc::setgroups` | Length and group slice | Nonempty `Vec<u32>` remains live for the full group count on the supported libc ABI. |
| `enter_container`: `libc::setresgid` / `libc::setresuid` | Scalar real/effective/saved IDs | No raw pointers; each failing return stops setup. |
| `run`: `libc::pipe2` | Writable storage for two FDs, `O_CLOEXEC` | The local two-element array is live and correctly sized. |
| `run`: `libc::syscall(SYS_clone, ...)` | Fork-like flags, null child stack/TID/TLS arguments; PID result | No memory-sharing flag is set, so address spaces are separate. The launcher is single-threaded and relies on the target kernel's raw clone ABI. |
| `run`: `libc::close` (parent and child) | Each process's unused endpoint | Endpoint came from successful `pipe2`; each branch closes its unused copy. |
| `run`: `libc::_exit` | Scalar status 127 | Child failure exits without inherited Rust destructors. |
| `run`: `libc::write` | Live write endpoint and one readable byte | Temporary byte storage survives the syscall; non-one result fails. |
| `run`: `libc::waitpid` | Child PID and writable status integer | PID came from successful clone; status storage remains valid throughout the call. |

## Memory and thread safety

Rust owns JSON, path, argument, and environment storage. FFI borrows buffers only
for synchronous calls. No unsafe `Send`/`Sync` is implemented. Parent and child
share kernel pipe state but no Rust heap writes. Introducing threads invalidates
the assumption that post-clone allocation and library operations can proceed
without locks inherited from other threads.

## Threat analysis

| ID | Threat and asset | Severity | Trigger | Response and residual risk |
|---|---|---|---|---|
| T-01 | Host/guest path escape and unwanted mounts | High | Hostile ID, root, bind source, destination `..`, or symlink | Canonical root and absolute-destination checks are partial only. Require trusted bundles in disposable guests; no path-confinement guarantee exists. |
| T-02 | Excess inherited privileges | High | Empty group list, ignored policy fields, or assumed full namespace isolation | Nonempty groups and UID/GID setters run before exec; modeled capability/seccomp requests fail. Empty groups persist and unsupported/unknown fields may be ignored. Do not use as a hardened runtime. |
| T-03 | Child runs before cgroup assignment | Medium | Parent and child execute concurrently | Child blocks on pipe read; parent writes only after successful migration. Parent failure lacks managed child teardown. |
| T-04 | Resource leakage or stuck execution | Medium | Setup fails, child never exits, or descendants retain the cgroup | Early errors propagate; normal removal retries are bounded, but `waitpid` is unbounded and there is no rollback/supervisor. Use a guest harness timeout. |
| T-05 | Incorrect raw-clone ABI assumptions | High | Build/run on an incompatible platform or after adding threads | Restrict execution to validated guest targets; null stack/no shared memory and single-thread assumptions must be rechecked for a new port. |

## Failure modes and effects (FMEA)

| ID | Failure mode | Cause | Local effect | System effect | Severity (1-4) | Handling |
|---|---|---|---|---|---|---|
| F-01 | Configuration rejected | Missing args, invalid JSON/env, unsupported modeled fields | `io::Error` | No successful workload launch | 3 | Propagate error; child failures print and exit 127. |
| F-02 | Setup syscall fails | Permissions or missing kernel feature | Partial setup remains | Guest resources may require cleanup | 2 | Return errno; no rollback guarantee. |
| F-03 | Removal stays busy | Descendant/process still owns cgroup state | Exhaust 100 retries | Command returns error | 3 | Record last `EBUSY`; environment cleans leftovers. |
| F-04 | Payload assertion fails | Wrong membership, cwd, or environment | `oci-test-init` panics | Smoke test fails | 3 | Preserve assertion diagnostics. |
| F-05 | Child wait interrupted or hangs | Signal or nonterminating child | Error or indefinite wait | Launcher unavailable | 2 | No EINTR retry or internal timeout; harness must bound execution. |

## Failure handling, privacy, and audit checklist

The parent reports the child's status only after cgroup cleanup succeeds.
Diagnostics expose bundle/cgroup paths and smoke-test PID; child environment
may contain secrets and is intentionally replaced using the configured entries.
The launcher does not redact inherited child stderr and does not promise secure
erasure of configuration buffers.

- Verify every FFI pointer lifetime and target ABI when changing calls.
- Keep cgroup migration before the ready-byte release.
- Preserve capability/seccomp rejection for fields actually modeled.
- Do not mistake absolute paths, chroot, or the namespace subset for confinement.
- Account for retained groups, raw endpoints, and failure-path children.
- Treat payload assertions as smoke-test checks, not an isolation proof.
