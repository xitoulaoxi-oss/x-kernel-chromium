// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

use alloc::sync::Arc;

use kerrno::KResult;

use crate::{Pid, Process, lookup};

/// Resolves the non-exited process whose resource limits are being queried or updated.
///
/// # Errors
///
/// Returns `kerrno::KError::NoSuchProcess` when the PID is unpublished or the
/// process has exited. PID zero selects the current user process.
pub fn target_process(pid: Pid) -> KResult<Arc<Process>> {
    lookup::live_process(pid)
}
