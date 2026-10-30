// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn>
// See LICENSES for license details.

//! Fixed-capacity, default-off diagnostic event ring (trace-followup/03).
//!
//! The object is a plain byte image so its layout matches `ring-layout.json`
//! exactly and the host decoder can read it without Rust ABI assumptions.  The
//! feature is compiled out of production builds; when enabled, writers are
//! lock-free and never allocate.

use core::sync::atomic::{AtomicU32, AtomicU64, Ordering};

const MAGIC: u64 = u64::from_le_bytes(*b"XKRING02");
const SCHEMA: u32 = 2;
const HEADER_LEN: usize = 128;
const META_LEN: usize = 64;
const ENTRY_SIZE: usize = 40;
const CPU_COUNT: usize = 4;
const ENTRIES_PER_CPU: usize = 1024;
const ENTRIES_OFF: usize = HEADER_LEN + META_LEN * CPU_COUNT;
const TOTAL_LEN: usize = ENTRIES_OFF + ENTRY_SIZE * ENTRIES_PER_CPU * CPU_COUNT;
const COMMITTED: u32 = 1;

pub const INIT: u16 = 1;
pub const IDLE_ENTER: u16 = 2;
pub const IDLE_RETURN: u16 = 3;
pub const TIMER_ARM: u16 = 4;
pub const TIMER_DISARM: u16 = 5;
pub const TIMER_IRQ: u16 = 6;
pub const IPI_RECV: u16 = 8;

#[repr(align(64))]
struct Storage([u8; TOTAL_LEN]);

const _: () = assert!(core::mem::size_of::<Storage>() == TOTAL_LEN);

/// The host locates this symbol in the ELF and reads the same bytes through QMP.
#[used]
#[unsafe(no_mangle)]
pub static mut XK_TRACE_RING: Storage = Storage([0; TOTAL_LEN]);

#[inline]
fn base() -> *mut u8 {
    // SAFETY: the static is a single object with a stable address; all access is
    // through volatile/atomic operations at the documented offsets.
    unsafe { core::ptr::addr_of_mut!(XK_TRACE_RING.0) as *mut u8 }
}

#[inline]
unsafe fn w32(p: *mut u8, off: usize, v: u32) {
    // SAFETY: caller guarantees `off` is an aligned field in the ring.
    unsafe { core::ptr::write_volatile(p.add(off) as *mut u32, v.to_le()) }
}

#[inline]
unsafe fn w64(p: *mut u8, off: usize, v: u64) {
    // SAFETY: caller guarantees `off` is an aligned field in the ring.
    unsafe { core::ptr::write_volatile(p.add(off) as *mut u64, v.to_le()) }
}

#[inline]
unsafe fn r64(p: *const u8, off: usize) -> u64 {
    // SAFETY: caller guarantees `off` is an aligned field in the ring.
    unsafe { core::ptr::read_volatile(p.add(off) as *const u64) }
}

fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut h = 0xcbf2_9ce4_8422_2325u64;
    for b in bytes {
        h ^= u64::from(*b);
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

fn header_checksum(p: *mut u8) -> u64 {
    // SAFETY: header is 128 bytes and checksum field is temporarily zeroed.
    unsafe {
        w64(p, 56, 0);
        let bytes = core::slice::from_raw_parts(p, HEADER_LEN);
        fnv1a64(bytes)
    }
}

/// Initializes the header once on the boot CPU and emits a self-test record.
pub fn init(cpu_count: usize) {
    let p = base();
    // A previous boot cannot survive -snapshot, but zeroing keeps a reused image
    // deterministic if the feature is built into a different boot path.
    // SAFETY: init runs before any writer; the whole object is ours.
    unsafe { core::ptr::write_bytes(p, 0, TOTAL_LEN) };
    let cpus = cpu_count.min(CPU_COUNT) as u32;
    // SAFETY: offsets match ring-layout.json and are naturally aligned.
    unsafe {
        w64(p, 0, MAGIC);
        w32(p, 8, SCHEMA);
        w32(p, 12, HEADER_LEN as u32);
        w32(p, 16, TOTAL_LEN as u32);
        w32(p, 20, cpus);
        w32(p, 24, ENTRY_SIZE as u32);
        w32(p, 28, ENTRIES_PER_CPU as u32);
        let nonce = khal::time::now_ticks().as_raw();
        w64(p, 32, nonce);
        w64(p, 40, khal::time::frequency().as_hz());
        w32(p, 48, 0); // arch timer counter domain
        w32(p, 52, 0);
        let sum = header_checksum(p);
        w64(p, 56, sum);
    }
    record(1, 0x584b_5249_4e47_3032, 0); // kind 1 = ring init self-test
}

/// Appends one event.  `kind` is the small event vocabulary in ring-layout.json.
pub fn record(kind: u16, arg0: u64, arg1: u64) {
    let p = base();
    // SAFETY: magic is immutable after init and read-only here.
    if unsafe { r64(p, 0) } != MAGIC {
        return;
    }
    let cpu = khal::percpu::this_cpu_id().as_usize();
    if cpu >= CPU_COUNT {
        return;
    }
    let meta = HEADER_LEN + cpu * META_LEN;
    // SAFETY: each CPU has one writer for its metadata/entries; the host is a
    // read-only observer and exports only after the guest is frozen.
    unsafe {
        let seq_atomic = AtomicU64::from_ptr(p.add(meta) as *mut u64);
        let seq = seq_atomic.load(Ordering::Relaxed);
        let slot = (seq as usize) % ENTRIES_PER_CPU;
        let entry = ENTRIES_OFF + (cpu * ENTRIES_PER_CPU + slot) * ENTRY_SIZE;
        let e = p.add(entry);
        w64(e, 0, seq);
        w64(e, 8, khal::time::now_ticks().as_raw());
        w64(e, 16, arg0);
        w64(e, 24, arg1);
        w32(e, 32, ((cpu as u32) << 16) | u32::from(kind));
        // Payload is visible before the commit flag (release).
        AtomicU32::from_ptr(e.add(36) as *mut u32).store(COMMITTED, Ordering::Release);
        seq_atomic.store(seq.wrapping_add(1), Ordering::Release);
        if seq >= ENTRIES_PER_CPU as u64 {
            let dropped = AtomicU64::from_ptr(p.add(meta + 8) as *mut u64);
            dropped.fetch_add(1, Ordering::Relaxed);
        }
    }
}
