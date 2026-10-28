// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! Signal trampoline mappings for user address spaces.

use kerrno::KResult;
use khal::{mem::v2p, paging::MappingFlags};
use memaddr::PAGE_SIZE_4K;
use memspace::MmSpace;

/// Maps the read/execute/user signal trampoline page into a user address
/// space at the fixed [`kaddr_layout::SIGNAL_TRAMPOLINE`] virtual address.
///
/// Called once per address space during exec so `sigreturn` remains reachable
/// even for static binaries without a vdso restorer.
///
/// # Errors
///
/// Returns an error when the trampoline's physical address cannot be resolved
/// or the linear mapping into `aspace` fails (for example a conflicting
/// existing mapping).
pub fn map_signal_trampoline(aspace: &mut MmSpace) -> KResult {
    let signal_trampoline_paddr = v2p(crate::arch::signal_trampoline_address().into());
    aspace.map_linear(
        kaddr_layout::SIGNAL_TRAMPOLINE.into(),
        signal_trampoline_paddr,
        PAGE_SIZE_4K,
        MappingFlags::READ | MappingFlags::EXECUTE | MappingFlags::USER,
    )?;
    Ok(())
}
