// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

// Helper for generating the Errno implementation.
macro_rules! errno_enum {
    (
        $(#[$meta:meta])*
        $vis:vis enum $Name:ident {
            $(
                $(#[$attrs:meta])*
                $item:ident($code:expr) = $doc:expr,
            )*
        }
    ) => {
        /// A raw Linux errno carrier with named constants and return-register decoding.
        ///
        /// Named constants are positive; [`Self::new`] can also represent arbitrary
        /// integers. [`Self::name`] distinguishes named codes from unknown values.
        ///
        /// # Panics
        ///
        /// Formatting `Errno::new(i32::MIN)` with `Display` can overflow in checked
        /// builds because display negates values accepted by `is_valid`.
        $(#[$meta])*
        #[derive(Copy, Clone, Eq, PartialEq, Ord, PartialOrd, Hash)]
        #[cfg_attr(feature = "serde", derive(serde::Deserialize, serde::Serialize))]
        $vis struct $Name(pub(super) i32);

        impl $Name {
            $(
                #[doc = $doc]
                $(#[$attrs])*
                pub const $item: $Name = $Name($code);
            )*

            /// Returns a pair containing the name of the error and a string
            /// describing the error.
            pub fn name_and_description(&self) -> Option<(&'static str, &'static str)> {
                match *self {
                    $(
                        $(#[$attrs])*
                        $Name::$item => Some((stringify!($item), $doc)),
                    )*
                    _ => None,
                }
            }
        }
    }
}
