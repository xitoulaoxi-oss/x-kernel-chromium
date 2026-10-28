// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! Credential secure-bits flags used across set-ID transitions.
//!
//! Capability-set side effects of these bits remain a future step; the flag
//! state itself is what `prctl(PR_{GET,SET}_KEEPCAPS)` observes and mutates.
//!
//! Bit indices match Linux `uapi/linux/securebits.h`
//! (`SECURE_KEEP_CAPS = 4`, `SECURE_KEEP_CAPS_LOCKED = 5`).

bitflags::bitflags! {
    /// Process secure-bits stored on [`super::Cred`].
    #[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
    pub(crate) struct SecureBits: u32 {
        /// Keep-capabilities request flag; capability-set effects are not implemented.
        const KEEP_CAPS = 1 << 4;
        /// Reject keep-capabilities setters; exec still clears [`Self::KEEP_CAPS`].
        const KEEP_CAPS_LOCKED = 1 << 5;
    }
}
