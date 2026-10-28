// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! Inotify syscalls.
//!
//! The instance object lives in `kfd_objects::inotify`; this module is the
//! syscall ABI adapter. `inotify_init1` therefore returns a real descriptor
//! instead of a sentinel, which matters because `0` names the caller's stdin
//! and a browser that treats it as an inotify instance will close or poll it.

use alloc::vec::Vec;
use core::ffi::c_char;

use bitflags::bitflags;
use kerrno::KResult;
use kfd_objects::inotify::{INOTIFY_PATH_MAX, Inotify};
use linux_raw_sys::general::{IN_CLOEXEC, IN_NONBLOCK};
use posix_types::UserConstPtr;

bitflags! {
    /// Flags accepted by `inotify_init1`.
    #[derive(Debug, Clone, Copy, Default)]
    pub struct InotifyInitFlags: u32 {
        /// Create a non-blocking instance.
        const NONBLOCK = IN_NONBLOCK;
        /// Set close-on-exec on the new descriptor.
        const CLOEXEC = IN_CLOEXEC;
    }
}

/// Creates an inotify instance and returns its new file descriptor.
pub(crate) fn sys_inotify_init1(flags: u32) -> KResult<isize> {
    let flags = InotifyInitFlags::from_bits(flags).ok_or(kerrno::KError::InvalidInput)?;
    debug!("sys_inotify_init1 <= flags: {flags:?}");

    // 与 eventfd 一致：匿名 inode 文件只消费 O_NONBLOCK，
    // O_CLOEXEC 交给下面的 add_file 处理，避免 OpenFlags::from_bits 拒绝它。
    let file = Inotify::new_file(flags.bits() & IN_NONBLOCK, kprocess::current_cred())?;
    kprocess::current_resources()
        .add_file(file, flags.contains(InotifyInitFlags::CLOEXEC))
        .map(|fd| fd as isize)
}

/// Loads the watch path from user memory with a `PATH_MAX` bound.
///
/// Non-UTF-8 bytes are preserved: the kernel treats the name as an opaque byte
/// sequence, and the object compares it byte-for-byte.
fn load_watch_path(path: UserConstPtr<c_char>) -> KResult<Vec<u8>> {
    path.load_bytes_with_max_len(INOTIFY_PATH_MAX)
}

/// Adds a watch and returns its watch descriptor.
pub(crate) fn sys_inotify_add_watch(
    fd: i32,
    path: UserConstPtr<c_char>,
    mask: u32,
) -> KResult<isize> {
    let inotify = kprocess::current_resources().get_file_private::<Inotify>(fd)?;
    let path = load_watch_path(path)?;
    debug!(
        "sys_inotify_add_watch <= fd: {fd}, path_len: {}, mask: {mask:#x}",
        path.len()
    );

    inotify.add_watch(&path, mask).map(|wd| wd as isize)
}

/// Removes the watch registered under `wd`.
pub(crate) fn sys_inotify_rm_watch(fd: i32, wd: i32) -> KResult<isize> {
    let inotify = kprocess::current_resources().get_file_private::<Inotify>(fd)?;
    debug!("sys_inotify_rm_watch <= fd: {fd}, wd: {wd}");

    inotify.remove_watch(wd).map(|()| 0)
}
