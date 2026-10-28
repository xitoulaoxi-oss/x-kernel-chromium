// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! Timer-domain delivery descriptions.

use ksignal::Signo;
use posix_types::k_sigval;

use crate::Tid;

/// A timer-produced signal before it is converted into `SignalInfo`.
#[derive(Clone)]
pub enum TimerSignal {
    /// Legacy `setitimer` expiration (`SIGALRM`/`SIGVTALRM`/`SIGPROF`)
    /// carrying no payload.
    Legacy {
        /// Signal number implied by the interval-timer kind.
        signo: Signo,
    },
    /// POSIX timer expiration carrying the `SI_TIMER` payload fields.
    Posix {
        /// Notification signal chosen at `timer_create`.
        signo: Signo,
        /// Kernel timer ID used by `timer_getoverrun`/dequeue validation.
        timer_id: i32,
        /// Overrun count frozen for this notification.
        overrun: i32,
        /// Generation of the timer state at expiration; stale notifications
        /// are dropped at dequeue time.
        signal_seq: u32,
        /// `sigval` payload requested at `timer_create`.
        value: k_sigval,
    },
}

/// A process- or thread-directed timer delivery.
#[derive(Clone)]
pub enum TimerDelivery {
    /// Deliver to the process (any unblocked thread may handle it).
    Process(TimerSignal),
    /// Deliver to one specific thread (`SIGEV_THREAD_ID`).
    Thread {
        /// Target thread ID.
        tid: Tid,
        /// Notification signal payload.
        signal: TimerSignal,
    },
}
