// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! Userspace ABI regressions for X-Kernel's legacy DRM mode-setting entry points.
//!
//! This is the companion of `identity.rs`: same harness, same rules (a real
//! `/dev/dri/card0`, no skipping, no mocked ioctls).  It exists because the
//! delivered Xorg build drives the **legacy** (non-atomic) mode-setting path,
//! which is a different ioctl set from the atomic one the kernel used to
//! implement alone:
//!
//!   * `DRM_IOCTL_MODE_CREATE_DUMB` -- Xorg requests `bpp = 24`, while a
//!     BGRA-backed virtio-gpu scanout is 32bpp.  A driver that only accepts 32
//!     fails `ScreenInit` outright.
//!   * `DRM_IOCTL_MODE_ADDFB` (legacy, `struct drm_mode_fb_cmd`, 28 bytes) --
//!     still used by non-atomic clients.  Linux keeps both `ADDFB` and `ADDFB2`.
//!   * `DRM_IOCTL_MODE_CURSOR` -- Xorg issues it once the CRTC is up.
//!   * `DRM_IOCTL_SET_CLIENT_CAP` -- must reject unknown capabilities with
//!     `EOPNOTSUPP` and out-of-range boolean values with `EINVAL`, and must
//!     remember what it granted.  A handler that answers `Ok(0)` to everything
//!     makes a feature probe report a capability the driver does not have.
//!
//! Run one case at a time; each owns the device for its whole body:
//!
//! ```sh
//! DRM_DEVICE=/dev/dri/card0 ./drm_mode_abi_regression --nocapture
//! ```
//!
//! See `README.md` in this directory for how to build the binary.

#[cfg(not(all(target_os = "linux", target_pointer_width = "64")))]
compile_error!("DRM mode ABI regressions require a 64-bit Linux userspace target");

#[cfg(all(test, target_os = "linux", target_pointer_width = "64"))]
mod tests {
    use std::{
        ffi::{c_int, c_ulong, c_void},
        fs::{File, OpenOptions},
        io,
        mem::size_of,
        os::fd::AsRawFd,
        ptr,
    };

    // _IOWR('d', nr, struct) with 64-bit struct sizes, taken from Linux uapi
    // `include/uapi/drm/drm.h` and `drm_mode.h`.
    const SET_CLIENT_CAP: c_ulong = 0xc010_640d;
    const CREATE_DUMB: c_ulong = 0xc020_64b2;
    const MAP_DUMB: c_ulong = 0xc010_64b3;
    const DESTROY_DUMB: c_ulong = 0xc004_64b4;
    /// Legacy `struct drm_mode_fb_cmd` is 7 x u32 = 28 bytes -> size nibble 0x1c.
    const ADDFB_LEGACY: c_ulong = 0xc01c_64ae;
    /// `struct drm_mode_fb_cmd2` is 104 bytes -> size nibble 0x68.
    const ADDFB2: c_ulong = 0xc068_64b8;
    const MODE_CURSOR: c_ulong = 0xc01c_64a3;

    const DRM_CLIENT_CAP_UNIVERSAL_PLANES: u64 = 2;
    const DRM_CLIENT_CAP_ATOMIC: u64 = 3;
    /// Deliberately not a Linux capability value.
    const DRM_CLIENT_CAP_UNKNOWN: u64 = 0x40;

    const DRM_FORMAT_XRGB8888: u32 = 0x3432_5258; // 'XR24'
    const DRM_FORMAT_ARGB8888: u32 = 0x3432_5241; // 'AR24'

    const EINVAL: i32 = 22;
    const EOPNOTSUPP: i32 = 95;

    // ---------------------------------------------------------------- ABI types

    #[repr(C)]
    #[derive(Default, Clone, Copy)]
    struct SetClientCap {
        capability: u64,
        value: u64,
    }

    #[repr(C)]
    #[derive(Default, Clone, Copy)]
    struct CreateDumb {
        height: u32,
        width: u32,
        bpp: u32,
        flags: u32,
        handle: u32,
        pitch: u32,
        size: u64,
    }

    #[repr(C)]
    #[derive(Default, Clone, Copy)]
    struct MapDumb {
        handle: u32,
        pad: u32,
        offset: u64,
    }

    #[repr(C)]
    #[derive(Default, Clone, Copy)]
    struct DestroyDumb {
        handle: u32,
    }

    /// Legacy `struct drm_mode_fb_cmd`.
    #[repr(C)]
    #[derive(Default, Clone, Copy)]
    struct FbCmd {
        fb_id: u32,
        width: u32,
        height: u32,
        pitch: u32,
        bpp: u32,
        depth: u32,
        handle: u32,
    }

    /// `struct drm_mode_fb_cmd2`.
    #[repr(C)]
    #[derive(Default, Clone, Copy)]
    struct FbCmd2 {
        fb_id: u32,
        width: u32,
        height: u32,
        pixel_format: u32,
        flags: u32,
        handles: [u32; 4],
        pitches: [u32; 4],
        offsets: [u32; 4],
        modifier: [u64; 4],
    }

    #[repr(C)]
    #[derive(Default, Clone, Copy)]
    struct ModeCursor {
        flags: u32,
        crtc_id: u32,
        x: i32,
        y: i32,
        handle: u32,
        pad: u32,
    }

    // ------------------------------------------------------------------ helpers

    fn open_card() -> File {
        let path = std::env::var("DRM_DEVICE").unwrap_or_else(|_| "/dev/dri/card0".into());
        OpenOptions::new()
            .read(true)
            .write(true)
            .open(&path)
            .unwrap_or_else(|error| panic!("cannot open DRM device {path}: {error}"))
    }

    fn ioctl_arg<T>(file: &File, command: c_ulong, value: &mut T) -> io::Result<()> {
        // SAFETY: callers pair each command with its repr(C) ABI struct, and
        // the storage stays live for the duration of the call.
        let result = unsafe { ioctl(file.as_raw_fd(), command, ptr::from_mut(value)) };
        if result < 0 {
            Err(io::Error::last_os_error())
        } else {
            Ok(())
        }
    }

    fn errno(result: io::Result<()>) -> i32 {
        result
            .expect_err("ioctl was expected to fail")
            .raw_os_error()
            .expect("ioctl error must carry an errno")
    }

    /// Create a dumb buffer, returning `(handle, pitch, size)`.
    fn create_dumb(file: &File, width: u32, height: u32, bpp: u32) -> io::Result<CreateDumb> {
        let mut request = CreateDumb {
            width,
            height,
            bpp,
            ..CreateDumb::default()
        };
        ioctl_arg(file, CREATE_DUMB, &mut request)?;
        Ok(request)
    }

    fn destroy_dumb(file: &File, handle: u32) {
        let mut request = DestroyDumb { handle };
        let _ = ioctl_arg(file, DESTROY_DUMB, &mut request);
    }

    // ------------------------------------------------------------------- cases

    // SET_CLIENT_CAP must behave like Linux `drm_setclientcap()`.
    #[test]
    fn set_client_cap_rejects_unknown_and_out_of_range() {
        assert_eq!(size_of::<SetClientCap>(), 16);
        let card = open_card();

        let mut unknown = SetClientCap {
            capability: DRM_CLIENT_CAP_UNKNOWN,
            value: 1,
        };
        assert_eq!(
            errno(ioctl_arg(&card, SET_CLIENT_CAP, &mut unknown)),
            EOPNOTSUPP,
            "an unknown capability must be reported as unsupported, not silently accepted"
        );

        for capability in [DRM_CLIENT_CAP_UNIVERSAL_PLANES, DRM_CLIENT_CAP_ATOMIC] {
            let mut out_of_range = SetClientCap {
                capability,
                value: 2,
            };
            assert_eq!(
                errno(ioctl_arg(&card, SET_CLIENT_CAP, &mut out_of_range)),
                EINVAL,
                "capability {capability} accepted a boolean value other than 0 or 1"
            );
            let mut valid = SetClientCap {
                capability,
                value: 1,
            };
            ioctl_arg(&card, SET_CLIENT_CAP, &mut valid).unwrap_or_else(|error| {
                panic!("capability {capability} must be grantable: {error}")
            });
            let mut revoked = SetClientCap {
                capability,
                value: 0,
            };
            ioctl_arg(&card, SET_CLIENT_CAP, &mut revoked).unwrap_or_else(|error| {
                panic!("capability {capability} must be revocable: {error}")
            });
        }
    }

    // Xorg's modesetting driver asks for 24bpp on its legacy path.  The driver
    // may back it with a 32bpp buffer, but it must not reject the request.
    #[test]
    fn create_dumb_accepts_24bpp_with_a_32bpp_compatible_layout() {
        assert_eq!(size_of::<CreateDumb>(), 32);
        let card = open_card();

        let bpp32 = create_dumb(&card, 1280, 800, 32).expect("32bpp CREATE_DUMB");
        assert_eq!(bpp32.pitch, 1280 * 4, "32bpp pitch must be width * 4");
        assert!(
            bpp32.size >= u64::from(bpp32.pitch) * u64::from(bpp32.height),
            "CREATE_DUMB reported {} bytes for {}x{} at pitch {}",
            bpp32.size,
            bpp32.width,
            bpp32.height,
            bpp32.pitch
        );

        let bpp24 = create_dumb(&card, 1280, 800, 24)
            .expect("24bpp CREATE_DUMB must be accepted for legacy mode-setting clients");
        assert_eq!(
            bpp24.pitch, bpp32.pitch,
            "24bpp requests are backed by the same 32bpp layout, so the pitch must match"
        );

        for (width, height, bpp) in [(0u32, 800u32, 32u32), (1280, 0, 32), (1280, 800, 16)] {
            let mut invalid = CreateDumb {
                width,
                height,
                bpp,
                ..CreateDumb::default()
            };
            assert_eq!(
                errno(ioctl_arg(&card, CREATE_DUMB, &mut invalid)),
                EINVAL,
                "CREATE_DUMB accepted width={width} height={height} bpp={bpp}"
            );
        }

        destroy_dumb(&card, bpp24.handle);
        destroy_dumb(&card, bpp32.handle);
    }

    // A dumb buffer must be mappable, because that is how clients obtain the
    // pixels they later hand to ADDFB.
    #[test]
    fn dumb_buffer_is_mappable() {
        let card = open_card();
        let dumb = create_dumb(&card, 64, 64, 32).expect("CREATE_DUMB");
        let mut map = MapDumb {
            handle: dumb.handle,
            ..MapDumb::default()
        };
        ioctl_arg(&card, MAP_DUMB, &mut map).expect("MAP_DUMB");
        assert_eq!(map.offset % 4096, 0, "MAP_DUMB offset must be page aligned");
        destroy_dumb(&card, dumb.handle);
    }

    // Linux implements BOTH legacy ADDFB and ADDFB2.  Non-atomic clients such
    // as Xorg use the legacy one, and a missing implementation is fatal for
    // them even when ADDFB2 works.
    #[test]
    fn legacy_addfb_and_addfb2_agree() {
        assert_eq!(size_of::<FbCmd>(), 28);
        assert_eq!(size_of::<FbCmd2>(), 104);
        let card = open_card();

        let dumb = create_dumb(&card, 256, 256, 32).expect("CREATE_DUMB");

        let mut modern = FbCmd2 {
            width: dumb.width,
            height: dumb.height,
            pixel_format: DRM_FORMAT_XRGB8888,
            handles: [dumb.handle, 0, 0, 0],
            pitches: [dumb.pitch, 0, 0, 0],
            ..FbCmd2::default()
        };
        ioctl_arg(&card, ADDFB2, &mut modern).expect("ADDFB2");
        assert_ne!(modern.fb_id, 0, "ADDFB2 returned no framebuffer id");

        let mut legacy = FbCmd {
            width: dumb.width,
            height: dumb.height,
            pitch: dumb.pitch,
            bpp: 32,
            depth: 24,
            handle: dumb.handle,
            ..FbCmd::default()
        };
        ioctl_arg(&card, ADDFB_LEGACY, &mut legacy)
            .expect("legacy ADDFB must be implemented; non-atomic clients depend on it");
        assert_ne!(legacy.fb_id, 0, "legacy ADDFB returned no framebuffer id");
        assert_ne!(
            legacy.fb_id, modern.fb_id,
            "each ADDFB allocates its own framebuffer id"
        );

        // 24bpp must be accepted here too, otherwise the CREATE_DUMB allowance
        // above is pointless: callers hand the same bpp straight back.
        let mut legacy_24 = FbCmd {
            width: dumb.width,
            height: dumb.height,
            pitch: dumb.pitch,
            bpp: 24,
            depth: 24,
            handle: dumb.handle,
            ..FbCmd::default()
        };
        ioctl_arg(&card, ADDFB_LEGACY, &mut legacy_24).expect("legacy ADDFB with bpp=24");

        let mut nonsense = FbCmd {
            width: dumb.width,
            height: dumb.height,
            pitch: dumb.pitch,
            bpp: 32,
            depth: 0,
            handle: dumb.handle,
            ..FbCmd::default()
        };
        assert_eq!(
            errno(ioctl_arg(&card, ADDFB_LEGACY, &mut nonsense)),
            EINVAL,
            "ADDFB accepted depth=0"
        );

        let mut bad_format = FbCmd2 {
            width: dumb.width,
            height: dumb.height,
            pixel_format: DRM_FORMAT_ARGB8888,
            handles: [dumb.handle, 0, 0, 0],
            pitches: [dumb.pitch, 0, 0, 0],
            ..FbCmd2::default()
        };
        let _ = ioctl_arg(&card, ADDFB2, &mut bad_format);

        destroy_dumb(&card, dumb.handle);
    }

    // Xorg issues MODE_CURSOR once the CRTC is up.  The kernel may report a
    // soft-cursor fallback, but the request must not fail with EOPNOTSUPP.
    #[test]
    fn mode_cursor_is_implemented() {
        assert_eq!(size_of::<ModeCursor>(), 24);
        let card = open_card();

        let mut cursor = ModeCursor::default();
        match ioctl_arg(&card, MODE_CURSOR, &mut cursor) {
            Ok(()) => {}
            Err(error) => {
                let code = error.raw_os_error().unwrap_or(0);
                assert_ne!(
                    code, EOPNOTSUPP,
                    "MODE_CURSOR is not implemented; the kernel must answer it so legacy \
                     mode-setting clients do not abort their initialisation"
                );
                panic!("MODE_CURSOR failed with errno {code}");
            }
        }
    }

    // Every ioctl above must survive a close/reopen cycle without leaking a
    // master reference, because `x11-session` respawns the whole X server.
    #[test]
    fn session_restart_reacquires_the_device() {
        let first = open_card();
        let dumb = create_dumb(&first, 32, 32, 32).expect("CREATE_DUMB");
        destroy_dumb(&first, dumb.handle);
        drop(first);

        let second = open_card();
        let mut cap = SetClientCap {
            capability: DRM_CLIENT_CAP_UNIVERSAL_PLANES,
            value: 1,
        };
        ioctl_arg(&second, SET_CLIENT_CAP, &mut cap).expect("SET_CLIENT_CAP after reopen");
        let mut cursor = ModeCursor::default();
        let _ = ioctl_arg(&second, MODE_CURSOR, &mut cursor);
    }

    #[allow(dead_code)]
    fn ioctl_takes_null_argument(file: &File, command: c_ulong) -> io::Result<()> {
        // SAFETY: only used for commands documented to take no argument.
        let result = unsafe { ioctl(file.as_raw_fd(), command, ptr::null_mut::<c_void>()) };
        if result < 0 {
            Err(io::Error::last_os_error())
        } else {
            Ok(())
        }
    }

    unsafe extern "C" {
        fn ioctl(fd: c_int, request: c_ulong, ...) -> c_int;
    }
}
