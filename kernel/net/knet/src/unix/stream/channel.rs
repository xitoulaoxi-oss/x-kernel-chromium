// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! Connected Unix stream channel state.

use alloc::{collections::VecDeque, sync::Arc, vec::Vec};
use core::sync::atomic::{AtomicBool, AtomicI32, Ordering};

use kerrno::LinuxError;
use kpoll::{IoEvents, PollContext, PollRegisterError, PollSet};
use kspin::SpinNoPreempt;
use ksync::Mutex;
use ringbuf::{
    HeapCons, HeapProd, HeapRb,
    traits::{Observer, Split},
};

use crate::AncillaryData;

pub(super) const STREAM_BUF_BYTES: usize = 64 * 1024;
pub(super) const STREAM_WRITABLE_MAX_OCCUPIED_BYTES: usize = STREAM_BUF_BYTES / 4;

pub(super) fn is_stream_writable(occupied_bytes: usize) -> bool {
    occupied_bytes <= STREAM_WRITABLE_MAX_OCCUPIED_BYTES
}

fn new_ring_pair() -> (HeapProd<u8>, HeapCons<u8>) {
    let rb = HeapRb::new(STREAM_BUF_BYTES);
    rb.split()
}

/// Control data published with the first byte of a send.
///
/// The byte range is half-open and a receive stops at `end`, so one recvmsg
/// cannot merge two rights lists that the sender kept apart.
pub(super) struct ControlRecord {
    pub(super) start: usize,
    pub(super) end: usize,
    pub(super) data: Vec<AncillaryData>,
}

/// Control-message side channel of one transmit direction.
///
/// `written` and `read` are byte positions of the channel's transmit ring
/// and wrap together with it; their distance never exceeds `STREAM_BUF_BYTES`
/// because the ring cannot hold more than that many unpublished bytes.
///
/// Lock order is channel mutex -> control mutex -> endpoint `tx_order`.
/// User copies may fault and run under sleepable mutexes, never under
/// `tx_order`.
#[derive(Default)]
pub(super) struct StreamControl {
    pub(super) written: usize,
    pub(super) read: usize,
    pub(super) records: VecDeque<ControlRecord>,
}

#[derive(Default)]
pub(super) struct StreamPollSets {
    pub(super) readable: PollSet,
    pub(super) writable: PollSet,
    state: PollSet,
}

impl StreamPollSets {
    pub(super) fn register(
        &self,
        context: &mut PollContext<'_>,
        events: IoEvents,
    ) -> Result<(), PollRegisterError> {
        let has_read_events =
            events.intersects(IoEvents::IN | IoEvents::RDNORM | IoEvents::RDBAND | IoEvents::RDHUP);
        let has_write_events =
            events.intersects(IoEvents::OUT | IoEvents::WRNORM | IoEvents::WRBAND);
        if has_read_events {
            context.register(&self.readable)?;
        }
        if has_write_events {
            context.register(&self.writable)?;
        }
        if !has_read_events && !has_write_events && events.intersects(IoEvents::ERR | IoEvents::HUP)
        {
            context.register(&self.state)?;
        }
        Ok(())
    }

    pub(super) fn wake_state_change(&self) {
        self.readable.wake();
        self.writable.wake();
        self.state.wake();
    }
}

#[derive(Default)]
pub(super) struct StreamEndpoint {
    pub(super) polls: StreamPollSets,
    /// Orders data publication, shutdown, and EOF observation for this
    /// endpoint's transmit direction.
    pub(super) tx_order: SpinNoPreempt<()>,
    pub(super) rx_closed: AtomicBool,
    pub(super) tx_closed: AtomicBool,
    pub(super) socket_error: AtomicI32,
}

pub(super) fn new_duplex_channel(
    client_endpoint: Arc<StreamEndpoint>,
    server_endpoint: Arc<StreamEndpoint>,
    pid: u32,
) -> (Channel, Channel) {
    let (client_tx, server_rx) = new_ring_pair();
    let (server_tx, client_rx) = new_ring_pair();
    // The transmit control queue of one side is the receive control queue of
    // the other, because in-band bytes and their control data travel together.
    let client_control = Arc::new(Mutex::new(StreamControl::default()));
    let server_control = Arc::new(Mutex::new(StreamControl::default()));
    (
        Channel {
            tx: client_tx,
            rx: client_rx,
            tx_control: client_control.clone(),
            rx_control: server_control.clone(),
            endpoint: client_endpoint.clone(),
            peer_endpoint: server_endpoint.clone(),
            peer_pid: pid,
        },
        Channel {
            tx: server_tx,
            rx: server_rx,
            tx_control: server_control,
            rx_control: client_control,
            endpoint: server_endpoint,
            peer_endpoint: client_endpoint,
            peer_pid: pid,
        },
    )
}

pub(super) struct Channel {
    pub(super) tx: HeapProd<u8>,
    pub(super) rx: HeapCons<u8>,
    pub(super) tx_control: Arc<Mutex<StreamControl>>,
    pub(super) rx_control: Arc<Mutex<StreamControl>>,
    pub(super) endpoint: Arc<StreamEndpoint>,
    pub(super) peer_endpoint: Arc<StreamEndpoint>,
    pub(super) peer_pid: u32,
}

impl Drop for Channel {
    fn drop(&mut self) {
        let (is_rx_changed, has_unread_input) = {
            let _tx_order = self.peer_endpoint.tx_order.lock();
            (
                !self.endpoint.rx_closed.swap(true, Ordering::AcqRel),
                self.rx.occupied_len() > 0,
            )
        };
        let is_tx_changed = {
            let _tx_order = self.endpoint.tx_order.lock();
            !self.endpoint.tx_closed.swap(true, Ordering::AcqRel)
        };
        // Stop publication before detaching rights that nobody received.
        // Their destructors may close sockets and reenter this transport, so
        // no channel or control guard may survive the release.
        let discarded = core::mem::take(&mut self.rx_control.lock().records);
        drop(discarded);
        if has_unread_input {
            self.peer_endpoint
                .socket_error
                .store(LinuxError::ECONNRESET.into_raw(), Ordering::Release);
        }
        if is_rx_changed || is_tx_changed || has_unread_input {
            self.endpoint.polls.wake_state_change();
            self.peer_endpoint.polls.wake_state_change();
        }
    }
}
