// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

/// Legacy result-returning syscall invocation macro retained from the upstream API.
///
/// Accepts a number and zero through six arguments, casting arguments to `usize`.
/// **Unavailable in this kernel fork:** expansion refers to `syscall0` through
/// `syscall6`, which this crate does not provide. Importing the macro is possible,
/// but invoking it fails to compile. This crate supplies number tables and ABI
/// helpers; it does not provide a userspace trap-instruction backend.
///
/// # Examples
///
/// The missing backend is an explicit compatibility limitation:
///
/// ```compile_fail,E0425
/// use linux_sysno::{syscall, Sysno};
/// let _ = unsafe { syscall!(Sysno::getpid) };
/// ```
#[macro_export]
macro_rules! syscall {
    ($nr:expr) => {
        $crate::syscall0($nr)
    };

    ($nr:expr, $a1:expr) => {
        $crate::syscall1($nr, $a1 as usize)
    };

    ($nr:expr, $a1:expr, $a2:expr) => {
        $crate::syscall2($nr, $a1 as usize, $a2 as usize)
    };

    ($nr:expr, $a1:expr, $a2:expr, $a3:expr) => {
        $crate::syscall3($nr, $a1 as usize, $a2 as usize, $a3 as usize)
    };

    ($nr:expr, $a1:expr, $a2:expr, $a3:expr, $a4:expr) => {
        $crate::syscall4($nr, $a1 as usize, $a2 as usize, $a3 as usize, $a4 as usize)
    };

    ($nr:expr, $a1:expr, $a2:expr, $a3:expr, $a4:expr, $a5:expr) => {
        $crate::syscall5(
            $nr,
            $a1 as usize,
            $a2 as usize,
            $a3 as usize,
            $a4 as usize,
            $a5 as usize,
        )
    };

    ($nr:expr, $a1:expr, $a2:expr, $a3:expr, $a4:expr, $a5:expr, $a6:expr) => {
        $crate::syscall6(
            $nr,
            $a1 as usize,
            $a2 as usize,
            $a3 as usize,
            $a4 as usize,
            $a5 as usize,
            $a6 as usize,
        )
    };
}

/// Legacy raw-register syscall invocation macro retained from the upstream API.
///
/// Accepts a number and zero through six arguments and casts them to `usize`.
/// **Unavailable in this kernel fork:** expansion requires the absent `raw`
/// module's `syscall0` through `syscall6` functions. See [`syscall!`] for the
/// compatibility boundary; neither macro is a kernel dispatch interface.
///
/// # Examples
///
/// ```compile_fail,E0433
/// use linux_sysno::{raw_syscall, Sysno};
/// let _ = unsafe { raw_syscall!(Sysno::getpid) };
/// ```
#[macro_export]
macro_rules! raw_syscall {
    ($nr:expr) => {
        $crate::raw::syscall0($nr as usize)
    };

    ($nr:expr, $a1:expr) => {
        $crate::raw::syscall1($nr as usize, $a1 as usize)
    };

    ($nr:expr, $a1:expr, $a2:expr) => {
        $crate::raw::syscall2($nr as usize, $a1 as usize, $a2 as usize)
    };

    ($nr:expr, $a1:expr, $a2:expr, $a3:expr) => {
        $crate::raw::syscall3($nr as usize, $a1 as usize, $a2 as usize, $a3 as usize)
    };

    ($nr:expr, $a1:expr, $a2:expr, $a3:expr, $a4:expr) => {
        $crate::raw::syscall4(
            $nr as usize,
            $a1 as usize,
            $a2 as usize,
            $a3 as usize,
            $a4 as usize,
        )
    };

    ($nr:expr, $a1:expr, $a2:expr, $a3:expr, $a4:expr, $a5:expr) => {
        $crate::raw::syscall5(
            $nr as usize,
            $a1 as usize,
            $a2 as usize,
            $a3 as usize,
            $a4 as usize,
            $a5 as usize,
        )
    };

    ($nr:expr, $a1:expr, $a2:expr, $a3:expr, $a4:expr, $a5:expr, $a6:expr) => {
        $crate::raw::syscall6(
            $nr as usize,
            $a1 as usize,
            $a2 as usize,
            $a3 as usize,
            $a4 as usize,
            $a5 as usize,
            $a6 as usize,
        )
    };
}
