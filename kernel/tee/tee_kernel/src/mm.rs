// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

use alloc::{string::String, vec::Vec};
use core::ffi::c_char;

use kerrno::{KError, KResult};
use osvm::{load_vec_until_null, read_vm_bytes};

/// Upper bound for a single user-supplied string loaded from a TEE syscall.
///
/// A length that arrives directly from the syscall ABI is untrusted, so it must
/// be bounded before it can drive a heap reservation. Without the bound a bogus
/// length such as `usize::MAX` reaches the allocator first and can terminate the
/// kernel instead of returning an error to the caller.
pub const VM_STRING_MAX_LEN: usize = 128 * 1024;

pub fn vm_load_string(ptr: *const c_char) -> KResult<String> {
    let bytes = load_vec_until_null(ptr.cast::<u8>())?;
    String::from_utf8(bytes).map_err(|_| KError::IllegalBytes)
}

/// Load exactly `len` bytes from user memory and decode them as UTF-8.
///
/// Lengths above [`VM_STRING_MAX_LEN`] are rejected with [`KError::OutOfRange`]
/// before any heap capacity is requested, and the capacity is acquired through a
/// fallible reservation, so an over-large request cannot panic inside the
/// collection. The reservation reports collection-level capacity failure and any
/// failure the allocator itself returns as `Err`; heap exhaustion is not
/// observable here, because the kernel allocator terminates on failure instead
/// of returning a null pointer (see `kalloc`'s `GlobalAlloc` implementation), so
/// turning real exhaustion into [`KError::NoMemory`] requires a fallible
/// allocator interface. The copy stays range-checked and fault-tolerant through
/// `read_vm_bytes`, which reports an inaccessible user range as
/// [`KError::BadAddress`].
pub fn vm_load_string_with_len(ptr: *const c_char, len: usize) -> KResult<String> {
    let bytes = load_bytes_with_len(ptr.cast::<u8>(), len)?;
    String::from_utf8(bytes).map_err(|_| KError::IllegalBytes)
}

fn load_bytes_with_len(ptr: *const u8, len: usize) -> KResult<Vec<u8>> {
    if len > VM_STRING_MAX_LEN {
        return Err(KError::OutOfRange);
    }

    let mut bytes = Vec::new();
    // Fallible reservation: a request the collection cannot represent fails here
    // instead of panicking. It does not cover heap exhaustion, which the
    // allocator reports through its own failure path rather than as `Err`.
    bytes.try_reserve_exact(len).map_err(|_| KError::NoMemory)?;

    read_vm_bytes(ptr, &mut bytes.spare_capacity_mut()[..len])?;
    // SAFETY: `read_vm_bytes` returned `Ok`, so it initialized all `len` bytes
    // of the spare-capacity slice from the user range it range-checked; the
    // `len` bytes below the resulting length are therefore valid `u8` values.
    unsafe { bytes.set_len(len) };
    Ok(bytes)
}

#[unittest::mod_test]
pub mod tests_mm {
    use unittest::{assert, assert_eq};

    use super::*;

    #[unittest::def_test(user)]
    fn test_load_string_with_len_exact_content() {
        let user_buf = crate::TestUserBuffer::new(5).unwrap();
        user_buf.write_bytes(b"hello").unwrap();

        let loaded = vm_load_string_with_len(user_buf.as_user_ptr(), 5).unwrap();
        assert_eq!(loaded, "hello");
    }

    #[unittest::def_test(user)]
    fn test_load_string_with_len_rejects_over_limit_before_alloc() {
        // The null pointer is never dereferenced: the length check must reject
        // the request before any allocation or user-memory access happens.
        assert_eq!(
            vm_load_string_with_len(core::ptr::null(), usize::MAX),
            Err(KError::OutOfRange)
        );
        assert_eq!(
            vm_load_string_with_len(core::ptr::null(), VM_STRING_MAX_LEN + 1),
            Err(KError::OutOfRange)
        );
    }

    #[unittest::def_test(user)]
    fn test_load_string_with_len_accepts_limit_boundary() {
        let filler = alloc::vec![b'a'; VM_STRING_MAX_LEN];
        let user_buf = crate::TestUserBuffer::new(VM_STRING_MAX_LEN).unwrap();
        user_buf.write_bytes(&filler).unwrap();

        let loaded = vm_load_string_with_len(user_buf.as_user_ptr(), VM_STRING_MAX_LEN).unwrap();
        assert_eq!(loaded.len(), VM_STRING_MAX_LEN);
        assert!(loaded.bytes().all(|byte| byte == b'a'));
    }

    #[unittest::def_test(user)]
    fn test_load_string_with_len_rejects_invalid_addr() {
        assert_eq!(
            vm_load_string_with_len(core::ptr::null(), 8),
            Err(KError::BadAddress)
        );
    }

    #[unittest::def_test(user)]
    fn test_load_string_with_len_rejects_invalid_utf8() {
        let user_buf = crate::TestUserBuffer::new(1).unwrap();
        user_buf.write_bytes(&[0xFF]).unwrap();

        assert_eq!(
            vm_load_string_with_len(user_buf.as_user_ptr(), 1),
            Err(KError::IllegalBytes)
        );
    }
}
