// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

use kerrno::KResult;

use crate::{Pid, lookup};

/// Validates that a capability-target PID names a non-exited process.
///
/// # Errors
///
/// Returns `kerrno::KError::NoSuchProcess` when the PID is unpublished or the
/// process has exited. PID zero selects the current user process.
pub fn validate_target_pid(pid: Pid) -> KResult<()> {
    let _ = lookup::live_process(pid)?;
    Ok(())
}
