// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

use alloc::sync::Arc;

use kerrno::KResult;

use crate::{Pid, Process, ProcessGroup, lookup};

/// Resolves the non-exited process targeted by job-control mutation syscalls.
///
/// # Errors
///
/// Returns `kerrno::KError::NoSuchProcess` when the PID is unpublished or the
/// process has exited. PID zero selects the current user process.
pub fn target_process(pid: Pid) -> KResult<Arc<Process>> {
    lookup::live_process(pid)
}

/// Resolves the process group targeted by job-control syscalls.
///
/// # Errors
///
/// Returns `kerrno::KError::NoSuchProcess` when the requested published target
/// is absent or no longer has the required live backing.
pub fn target_group(pgid: Pid) -> KResult<Arc<ProcessGroup>> {
    lookup::process_group(pgid)
}

/// Resolves a visible process identity for job/session query syscalls.
///
/// # Errors
///
/// Returns `kerrno::KError::NoSuchProcess` when the PID is unpublished.
/// Published zombie identities remain valid; PID zero selects the current process.
pub fn query_process(pid: Pid) -> KResult<Arc<Process>> {
    lookup::published_process(pid)
}
