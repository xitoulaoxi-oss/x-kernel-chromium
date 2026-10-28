// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! ABI-facing `times(2)` structures.

use crate::ptr::UserWrite;

/// CPU-time counters in fixed [`super::USER_HZ`] ticks, not scheduler ticks.
#[repr(C)]
pub struct Tms {
    /// Calling process user CPU time in ticks.
    pub tms_utime: usize,
    /// Calling process system CPU time in ticks.
    pub tms_stime: usize,
    /// Reaped children user CPU time in ticks.
    pub tms_cutime: usize,
    /// Reaped children system CPU time in ticks.
    pub tms_cstime: usize,
}

// SAFETY: `Tms` is a POD syscall output carrier with explicit integer fields.
unsafe impl UserWrite for Tms {}
