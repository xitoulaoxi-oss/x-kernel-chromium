// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! Memory barriers for AArch64.

use aarch64_cpu::asm::barrier;

/// Completes prior stores within the Inner Shareable domain.
///
/// Use before TLB invalidation to publish preceding page-table writes.
/// This store-only barrier does not ensure completion of instruction-cache
/// or TLB maintenance; those operations require a DSB covering both reads
/// and writes.
#[inline]
pub fn dsb_ishst() {
    barrier::dsb(barrier::ISHST);
}
