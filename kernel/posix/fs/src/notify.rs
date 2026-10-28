// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! Directory-entry notification hook for filesystem implementations.
//!
//! `inotify` watches can only see changes if something tells them a directory entry
//! changed.  The natural place to observe that is here, in the syscalls that create
//! and remove entries -- but the watch bookkeeping lives in `kfd_objects`, and
//! `kfd_objects` already depends on `kvfs`, so `posix_fs` importing it would create a
//! cycle.
//!
//! The dependency is therefore inverted: this module owns a function pointer that
//! whoever can see both sides (`ksyscall`) installs once at startup.  Until it is
//! installed every notification is a no-op, which is also what makes the filesystem
//! crate usable in unit tests with no inotify instance anywhere.

use core::sync::atomic::{AtomicUsize, Ordering};

/// Signature of the installed notifier: `(parent_path, event_mask, entry_name)`.
pub type EntryNotifier = fn(&[u8], u32, &[u8]);

/// `IN_CREATE`: a file or directory was created inside the watched directory.
pub const IN_CREATE: u32 = 0x0000_0100;

/// `IN_DELETE`: a file or directory was removed from the watched directory.
pub const IN_DELETE: u32 = 0x0000_0200;

/// The installed notifier, or 0 when none is installed.
///
/// A plain `AtomicUsize` rather than a lazily-initialised lock: this is read on
/// every file creation and removal, and a lock there would be a hot-path cost for a
/// facility that is usually absent.
static NOTIFIER: AtomicUsize = AtomicUsize::new(0);

/// Installs the notifier.  Called once during kernel start-up.
pub fn set_entry_notifier(notifier: EntryNotifier) {
    NOTIFIER.store(notifier as usize, Ordering::Release);
}

/// Reports that `name` inside `parent` changed, with the inotify event bit `mask`.
///
/// `parent` must be spelled the way `inotify_add_watch` stored it, because the watch
/// index is keyed by the caller's own path bytes.  A mismatch here fails silently --
/// no error, no event -- so callers should pass the directory component of the path
/// exactly as user space supplied it.
pub fn notify_entry(parent: &[u8], mask: u32, name: &[u8]) {
    let raw = NOTIFIER.load(Ordering::Acquire);
    if raw == 0 {
        return;
    }
    // SAFETY: the only value ever stored came from `set_entry_notifier`, which casts
    // a `fn` item of exactly this signature.  `fn` pointers are `Copy`, so the
    // transmute cannot duplicate ownership of anything.
    let notifier: EntryNotifier = unsafe { core::mem::transmute::<usize, EntryNotifier>(raw) };
    notifier(parent, mask, name);
}

/// Reports a directory-entry change for a path spelled relative to a base directory.
///
/// Splits `path` into the directory that contains the entry and the entry's own name,
/// rooted at `base`, and forwards them to [`notify_entry`].  Splitting here rather than
/// at each call site keeps the syscalls that need it from repeating the trailing-slash,
/// empty-name and no-parent cases -- all of which fail silently, because a mis-spelled
/// parent simply matches no watch.
///
/// Callers pass `fs.pwd()` as `base`; that is the same path space the kernel resolves
/// relative names against, so an absolute watch path and a relative syscall argument
/// still meet at the same key.
pub fn notify_change_at(base: &[u8], path: &[u8], mask: u32) {
    // A trailing slash names the directory itself, not an entry inside it.
    let trimmed = path.strip_suffix(b"/").unwrap_or(path);
    let Some(index) = trimmed.iter().rposition(|&c| c == b'/') else {
        // No separator: the entry sits directly inside the base directory.
        if base.is_empty() || trimmed.is_empty() {
            return;
        }
        notify_entry(base, mask, trimmed);
        return;
    };
    let (parent, name) = if index == 0 {
        // "/name": the parent is the filesystem root.
        (&trimmed[..1], &trimmed[1..])
    } else {
        (&trimmed[..index], &trimmed[index + 1..])
    };
    if parent.is_empty() || name.is_empty() {
        return;
    }
    notify_entry(parent, mask, name);
}
