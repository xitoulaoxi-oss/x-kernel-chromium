# fs_context design

## Purpose and background

`FsStruct` owns process filesystem state: root, working directory, umask, and an
exec-transition flag. `kprocess::ProcessRuntime` owns or shares its
`Arc<Mutex<FsStruct>>`. This is distinct from `kvfs::FsContext`, which describes
a filesystem creation/reconfiguration transaction. Path lookup, access policy,
and mount ownership belong to KVFS and POSIX callers.

## Scope and architecture

All implementation is in `src/lib.rs`. The initial object is published lazily
through `INIT_FS`; `init_fs()` clones its handle. `copy_init_fs_struct()` makes a
process-private copy. `FsStruct` owns `Option<Path>` root/pwd values, a `u32`
umask, and a boolean `in_exec`. `Path` references keep mount/dentry objects alive.

## Execution context and concurrency

Use task context with allocator and sleepable mutex support initialized. Initial
state can be created before mounting; path access requires a root to be installed.
The crate does not require a current task, CPU-local state, or device mappings.
The shared object requires the caller's outer mutex; direct `&mut FsStruct`
operations require exclusive access instead. Updates can drop VFS references and
are unsuitable for interrupt context or incompatible spinlock critical sections.
Take `root_and_pwd()` snapshots under the lock and release it before path I/O.

## State and algorithms

`for_init_task` starts with both paths absent, umask `0o022`, and `in_exec=false`.
`attach_root` validates a directory and installs it as both root and pwd. A caller
must do this before calling `root`/`pwd`, which panic on absent paths.

`from_root_and_pwd` and paired replacement validate both paths before mutation.
They do not prove that pwd is below root or in the same namespace. `set_root`
only initializes pwd if absent; `set_pwd` rejects an absent root. `new` panics
on a non-directory root instead of returning the constructor error.

- Fork without `CLONE_FS` uses `clone_for_process`, sharing `Path` references but
  clearing `in_exec`. Sharing the `Arc<Mutex<_>>` implements `CLONE_FS`.
- `snapshot` and `clone_with_pwd` retain `in_exec`, unlike `clone_for_process`.
- `replace_umask` keeps only `0o777` bits and returns the previous mask.
- `set_in_exec` only records a flag; callers implement the exec protocol.
- Namespace cloning may retarget a private context with `replace_root_and_pwd`.

## Decisions and resource lifecycle

A separate crate lets namespace and process code share one filesystem-state
owner without placing process lifecycle in KVFS. `Option` represents genuine
pre-mount initialization, not a user-visible path-resolution error. There is no
custom `Drop`: replacement and final context release drop `Path` references.
The final `Arc` release destroys a private context; the lazy initial context is
retained globally. Authorization and namespace compatibility remain caller duties.
