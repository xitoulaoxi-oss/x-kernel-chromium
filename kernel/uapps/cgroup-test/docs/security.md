# cgroup-test security and reliability

## Scope and trust model

The whole binary (`src/main.rs`) is in scope. Assets are the guest's root cgroup
configuration, task membership, and regression result. The test trusts the guest
filesystem mounts and kernel. It writes privileged control files and reads
procfs text; it is not suitable for an arbitrary host session. There is no
network, device-memory, DMA, firmware, or inline-assembly interface.

## FFI and unsafe inventory

| Location | Boundary | Preconditions and enforcement |
|---|---|---|
| `main`, `src/main.rs`: `libc::fork` | libc process creation ABI; scalar PID result | No pointer arguments. The process is single-threaded and the child touches no state guarded by inherited thread locks. |
| `main`, `src/main.rs`: `libc::_exit(0)` | libc child termination ABI | Child branch only; scalar status. Immediate termination avoids inherited Rust destructors after fork. |

Rust filesystem APIs own their buffers and paths. The only `unwrap` formats the
file name of the path just constructed with a nonempty final component.

## Threat analysis

| ID | Threat and asset | Severity | Trigger | Response and residual risk |
|---|---|---|---|---|
| T-01 | Unwanted cgroup mutation | Medium | Test is run against a valuable/shared hierarchy | Require a disposable guest; the implementation leaves `+pids` enabled even on success. |
| T-02 | False admission-test success | Medium | Kernel returns a failure unrelated to the pids cap | Require initial/moved membership and specifically `EAGAIN` or `WouldBlock`; this remains a focused regression, not comprehensive enforcement proof. |
| T-03 | Persistent test resources | Low | Any step fails after creating/moving into the group | Error is returned; environment must clean membership/groups. No rollback is implemented. |

## Thread safety and failure modes (FMEA)

There is one userspace thread; the fork child immediately exits. The kernel
serializes cgroup operations. No Rust lock or custom `Send`/`Sync` exists.

| ID | Failure mode | Cause | Local effect | System effect | Severity (1-4) | Handling |
|---|---|---|---|---|---|---|
| F-01 | Filesystem operation fails | Missing mount, permissions, existing name | `io::Error` | Test fails, possible residual group | 3 | Preserve underlying error and add path for writes. |
| F-02 | Fork succeeds unexpectedly | Missing quota enforcement | Child exits; parent reports failure | Child/group may require cleanup | 3 | Do not print PASS; harness cleans the guest. |
| F-03 | Wrong procfs text | Namespace or membership mismatch | Explicit diagnostic error | Test fails | 3 | Compare exact expected membership. |

## Failure management, privacy, and limitations

The process exits on the first error and only prints PASS after cleanup succeeds.
Diagnostics may reveal cgroup paths and task membership; no file contents beyond
procfs membership are read. The test neither restores root controller state nor
reaps an unexpected child. It tests one admission path, not delegation,
concurrent migration, namespace isolation, or authorization coverage.

## Audit checklist

- Keep the fork child free of inherited Rust cleanup and locks.
- Retain exact errno and membership checks before reporting success.
- Run in a disposable guest and account for failure-path leftovers.
- Recheck cleanup assumptions if adding threads or more child work.
