// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

const HZ_PER_KHZ: u64 = 1_000;
const HZ_PER_MHZ: u64 = 1_000_000;

/// A frequency stored canonically as cycles per second (hertz).
///
/// Conversions to coarser units explicitly round down so hardware and logging
/// boundaries cannot silently treat truncated kHz or MHz values as exact.
#[repr(transparent)]
#[derive(Clone, Copy, Debug, Default, Eq, Ord, PartialEq, PartialOrd)]
pub struct Frequency(u64);

impl Frequency {
    /// Zero hertz.
    pub const ZERO: Self = Self(0);

    /// Creates a frequency from hertz.
    pub const fn from_hz(hz: u64) -> Self {
        Self(hz)
    }

    /// Creates a frequency from kilohertz, returning `None` on overflow.
    pub const fn checked_from_khz(khz: u64) -> Option<Self> {
        match khz.checked_mul(HZ_PER_KHZ) {
            Some(hz) => Some(Self(hz)),
            None => None,
        }
    }

    /// Creates a frequency from megahertz, returning `None` on overflow.
    pub const fn checked_from_mhz(mhz: u64) -> Option<Self> {
        match mhz.checked_mul(HZ_PER_MHZ) {
            Some(hz) => Some(Self(hz)),
            None => None,
        }
    }

    /// Returns the frequency in hertz.
    pub const fn as_hz(self) -> u64 {
        self.0
    }

    /// Returns whole kilohertz, rounding down any sub-kHz remainder.
    pub const fn as_khz_floor(self) -> u64 {
        self.0 / HZ_PER_KHZ
    }

    /// Returns whole megahertz, rounding down any sub-MHz remainder.
    pub const fn as_mhz_floor(self) -> u64 {
        self.0 / HZ_PER_MHZ
    }

    /// Returns whether the frequency is zero.
    pub const fn is_zero(self) -> bool {
        self.0 == 0
    }
}
