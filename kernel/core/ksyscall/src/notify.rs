// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! Wiring between the filesystem crate and the inotify object crate.
//!
//! `posix_fs` needs to report directory-entry changes, and `kfd_objects::inotify`
//! knows which watches care about them.  Neither can depend on the other:
//! `kfd_objects` already depends on `kvfs`, so `posix_fs -> kfd_objects` would close
//! a cycle.  `posix_fs` therefore exposes an injectable function pointer, and this
//! module -- in the one crate that already depends on both -- installs it.
//!
//! Kept separate from `dispatch` so the one-time cost is obviously one-time.

use core::sync::atomic::{AtomicBool, Ordering};

/// Whether the notifier has been installed.
static INSTALLED: AtomicBool = AtomicBool::new(false);

/// Installs the filesystem notifier exactly once.
///
/// Called from the syscall entry point rather than from a start-up hook because
/// `entry` only depends on this crate, and adding a kernel start-up callback for one
/// pointer would mean touching a layer that gains nothing from it.  The `swap`
/// short-circuits every call after the first, so the cost on the syscall path is one
/// relaxed load once the flag is set.
pub fn install_fs_notifier() {
    if INSTALLED.swap(true, Ordering::AcqRel) {
        return;
    }
    // The signatures match exactly: `notify_path(&[u8], u32, &[u8])`.
    posix_fs::notify::set_entry_notifier(kfd_objects::inotify::notify_path);
    debug!("filesystem entry notifier installed");
}
