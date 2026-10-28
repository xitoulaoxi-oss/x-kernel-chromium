// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

use crate::{Read, Result, Write};

/// Reader created by [`read_fn`].
pub struct ReadFn<R> {
    r: R,
}

/// Creates a reader whose `read` calls invoke `r` synchronously.
///
/// The callback must follow [`Read::read`], including its byte-count bound.
/// Errors and callback execution-context requirements are forwarded unchanged.
pub fn read_fn<R>(r: R) -> ReadFn<R>
where
    R: FnMut(&mut [u8]) -> Result<usize>,
{
    ReadFn { r }
}

impl<R> Read for ReadFn<R>
where
    R: FnMut(&mut [u8]) -> Result<usize>,
{
    #[inline]
    fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        (self.r)(buf)
    }
}

/// Writer created by [`write_fn`].
pub struct WriteFn<W> {
    w: W,
}

/// Creates a writer whose `write` calls invoke `w` synchronously.
///
/// The callback must follow [`Write::write`], including its byte-count bound.
/// Errors are forwarded unchanged. `flush` is a no-op returning success;
/// this adapter provides no callback for durability or pending-output handling.
pub fn write_fn<W>(w: W) -> WriteFn<W>
where
    W: FnMut(&[u8]) -> Result<usize>,
{
    WriteFn { w }
}

impl<W> Write for WriteFn<W>
where
    W: FnMut(&[u8]) -> Result<usize>,
{
    #[inline]
    fn write(&mut self, buf: &[u8]) -> Result<usize> {
        (self.w)(buf)
    }

    #[inline]
    fn flush(&mut self) -> Result<()> {
        Ok(())
    }
}
