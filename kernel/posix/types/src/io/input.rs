// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! ABI-facing input device structures.

use crate::ptr::UserWrite;

/// The Linux `struct input_id` carrier used by evdev ioctls such as `EVIOCGID`.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct InputId {
    /// Linux input bus type identifier.
    pub bus_type: u16,
    /// Vendor identifier reported by the input device.
    pub vendor: u16,
    /// Product identifier reported by the input device.
    pub product: u16,
    /// Device version identifier.
    pub version: u16,
}

// SAFETY: `InputId` is a POD ioctl result structure with no hidden validity invariants.
unsafe impl UserWrite for InputId {}
