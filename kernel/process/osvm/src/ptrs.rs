// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! Virtual pointer helpers for safe user memory access.
use core::{mem::MaybeUninit, ptr::NonNull, slice};

use bytemuck::AnyBitPattern;

use crate::{MemResult, read_vm_mem, write_vm_mem};

/// Read-only virtual pointer access helpers.
///
/// Implemented for raw pointers and [`NonNull`] so syscall layers can keep
/// user pointers untyped while performing checked, byte-copy-based access.
/// No method in this trait creates a reference into user memory.
pub trait VirtPtr: Copy {
    /// The pointee type used for alignment and sizing decisions.
    type Target;

    /// Returns the raw pointer.
    ///
    /// The value is only ever used as an address for checked copies, never
    /// dereferenced.
    fn as_ptr(self) -> *const Self::Target;

    /// Returns `None` if the pointer is null, otherwise `Some(self)`.
    ///
    /// Used to implement Linux's "NULL means absent" ABI convention without
    /// turning a null check into an `EFAULT`.
    fn check_non_null(self) -> Option<Self> {
        if self.as_ptr().is_null() {
            None
        } else {
            Some(self)
        }
    }

    /// Reads one `Target` into an uninitialized buffer without requiring any
    /// bit-pattern validity for `Target`.
    ///
    /// # Errors
    ///
    /// Returns [`MemError::InvalidAddr`](crate::MemError::InvalidAddr) when
    /// misaligned, or the provider's error when inaccessible.
    fn read_uninit(self) -> MemResult<MaybeUninit<Self::Target>> {
        let mut u = MaybeUninit::<Self::Target>::uninit();
        read_vm_mem(self.as_ptr(), slice::from_mut(&mut u))?;
        Ok(u)
    }

    /// Reads a typed value from user memory.
    ///
    /// # Errors
    ///
    /// Returns the errors of [`VirtPtr::read_uninit`].
    fn read_vm(self) -> MemResult<Self::Target>
    where
        Self::Target: AnyBitPattern,
    {
        let u = self.read_uninit()?;
        // SAFETY: `AnyBitPattern` guarantees every bit pattern is a valid value
        // for `Self::Target`, so the initialized bytes can be assumed valid.
        Ok(unsafe { u.assume_init() })
    }
}

impl<T> VirtPtr for *const T {
    type Target = T;

    fn as_ptr(self) -> *const T {
        self
    }
}

impl<T> VirtPtr for *mut T {
    type Target = T;

    fn as_ptr(self) -> *const T {
        self
    }
}

impl<T> VirtPtr for NonNull<T> {
    type Target = T;

    fn as_ptr(self) -> *const T {
        self.as_ptr()
    }
}

/// Mutable virtual pointer access helpers.
///
/// Extends [`VirtPtr`] with checked writes; like the base trait it never
/// forms references into user memory.
pub trait VirtMutPtr: VirtPtr {
    /// Writes a typed value to user memory.
    ///
    /// # Errors
    ///
    /// Returns [`MemError::InvalidAddr`](crate::MemError::InvalidAddr) when
    /// misaligned, or the provider's error when inaccessible.
    fn write_vm(self, v: Self::Target) -> MemResult {
        write_vm_mem(self.as_ptr().cast_mut(), slice::from_ref(&v))
    }
}

impl<T> VirtMutPtr for *mut T {}
impl<T> VirtMutPtr for NonNull<T> {}
