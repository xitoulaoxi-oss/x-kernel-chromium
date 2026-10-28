// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! Per-syscall invocation counters, for diagnosing a spinning user process.
//!
//! Why this exists: Chromium's browser process on this kernel reaches a state where
//! `/proc/<pid>/stat` field 3 is `R`, `wchan` is empty, its cumulative CPU time does
//! not advance, and its log stops at exactly 764 bytes -- the signature of a loop
//! that re-enters the kernel and returns immediately.  `/proc/<pid>/syscall` is not
//! provided by this kernel, and `wchan` is empty precisely because the task is
//! on-CPU rather than sleeping, so nothing outside the kernel can name the syscall.
//!
//! The counter answers it directly: read the table twice a few seconds apart while
//! the process is stuck, and the entries whose counts grow fastest are the loop.
//!
//! The cost is one relaxed atomic increment per syscall, and the whole facility is
//! behind the `syscall-counter` feature so it does not ship in a submitted build.

use core::sync::atomic::{AtomicU32, AtomicUsize, Ordering};

use linux_sysno::Sysno;

/// Highest syscall number tracked.  Linux aarch64 uses the generic table, which is
/// well under 512; anything above is accumulated in [`OVERFLOW`].
const MAX_SYSNO: usize = 512;

/// Invocation count per syscall number.
static COUNTERS: [AtomicU32; MAX_SYSNO] = [const { AtomicU32::new(0) }; MAX_SYSNO];

/// Calls to syscall numbers at or above [`MAX_SYSNO`].
static OVERFLOW: AtomicU32 = AtomicU32::new(0);

/// Total calls observed, used to pace the periodic dump.
static TOTAL: AtomicUsize = AtomicUsize::new(0);

/// How many syscalls between automatic dumps.
///
/// Deliberately small.  The first value tried (200_000) produced no output at all
/// while a browser was stuck, which is itself ambiguous: it could mean the loop is
/// not in the kernel, or that the dump simply never triggered.  A low threshold
/// removes that ambiguity -- if the counter works, one boot proves it, and the
/// number can be raised afterwards.
const DUMP_EVERY: usize = 2_000;

/// How many of the busiest syscalls to report per dump.
const TOP_N: usize = 8;

/// Records one invocation of `sysno`.
///
/// Called from `handle_syscall` for every syscall, so it must stay allocation-free
/// and bounded: two relaxed atomics on the common path, no locking.
pub fn record(sysno: Sysno) {
    let n = sysno as usize;
    if n < MAX_SYSNO {
        COUNTERS[n].fetch_add(1, Ordering::Relaxed);
    } else {
        OVERFLOW.fetch_add(1, Ordering::Relaxed);
    }

    if TOTAL.fetch_add(1, Ordering::Relaxed) % DUMP_EVERY == DUMP_EVERY - 1 {
        dump();
    }
}

/// Logs the busiest syscalls seen so far, highest first.
///
/// Deliberately selection-sorts `TOP_N` times over a fixed 512-entry array rather
/// than allocating a vector: this runs inside the syscall path.
pub fn dump() {
    // `taken` marks entries already reported.  A separate array rather than
    // checking membership of the output array: holding a mutable borrow of the
    // output while also reading it inside the same loop does not borrow-check.
    let mut taken = [false; MAX_SYSNO];
    for _ in 0..TOP_N {
        let mut best = usize::MAX;
        let mut best_count = 0u32;
        for (n, counter) in COUNTERS.iter().enumerate() {
            if taken[n] {
                continue;
            }
            let count = counter.load(Ordering::Relaxed);
            if count > best_count {
                best_count = count;
                best = n;
            }
        }
        if best == usize::MAX || best_count == 0 {
            break;
        }
        taken[best] = true;
        // Only numbers with a name are worth printing; a bare integer would still
        // identify the loop, but the name is what makes it actionable.
        match Sysno::new(best) {
            Some(name) => warn!("syscall-count {name:?}={best_count}"),
            None => warn!("syscall-count #{best}={best_count}"),
        }
    }
    warn!("syscall-count total={}", TOTAL.load(Ordering::Relaxed));
}
