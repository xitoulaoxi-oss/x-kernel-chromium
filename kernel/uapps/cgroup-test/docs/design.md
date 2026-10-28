# cgroup-test design

## Purpose and scope

This standalone user-space Cargo binary is a destructive guest regression test
for cgroup v2 pids admission. `src/main.rs` contains the entire test; `libc`
provides `fork` and `_exit`. It tests kernel behavior through procfs and cgroup2fs
and does not implement cgroup policy itself.

## Environment and flow

Run `cgroup-test` in a disposable guest with writable `/sys/fs/cgroup`, a visible
`/proc/self/cgroup`, and permission to enable the root pids controller. Initial
membership must be exactly `0::/\n`. It is a single-threaded process, not an
interrupt or early-boot component.

1. Read and validate initial membership.
2. Enable `+pids` on the root and create `xkernel-test-<pid>`.
3. Write `pids.max=1`, move self via `cgroup.procs=0`, and verify the procfs path.
4. Attempt `fork`; a created child immediately calls `_exit(0)`.
5. Require fork failure with `EAGAIN`/`WouldBlock`.
6. Move back to root, remove the test group, and print
   `cgroup v2 pids regression: PASS`.

Filesystem and kernel admission operations occur synchronously in that order.
There are no Rust worker threads or shared mutable data. The parent relies on
kernel cgroup accounting for its one occupied task slot.

## Design decisions and resource lifecycle

A limit of one isolates admission behavior after migration: the parent fills the
quota, so a fork must fail. The PID suffix reduces ordinary name collisions but
does not retry existing names. `write` adds path context to filesystem errors.
All failures return `io::Error` and terminate the test; success alone reaches the
membership restoration and group removal. Root controller enablement remains
changed. There is no rollback guard, and an unexpectedly successful fork is not
waited for before the parent returns an error. Run only where leftover groups
and process cleanup can be handled by the test environment.
