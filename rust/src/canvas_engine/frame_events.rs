//! Coalesced frame notifications for native texture hosts. Waiting hosts sleep
//! until GPU completion; closing a subscription also releases a blocked waiter.
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock};

#[derive(Default)]
struct State {
    pending: bool,
    closed: bool,
}

#[derive(Default)]
struct FrameEvents {
    state: Mutex<State>,
    changed: Condvar,
}

impl FrameEvents {
    fn notify(&self) {
        let mut state = self.state.lock().unwrap_or_else(|err| err.into_inner());
        state.pending = true;
        self.changed.notify_one();
    }

    fn wait(&self) -> bool {
        let state = self.state.lock().unwrap_or_else(|err| err.into_inner());
        let mut state = self
            .changed
            .wait_while(state, |state| !state.pending && !state.closed)
            .unwrap_or_else(|err| err.into_inner());
        state.pending = false;
        !state.closed
    }

    fn close(&self) {
        let mut state = self.state.lock().unwrap_or_else(|err| err.into_inner());
        state.closed = true;
        self.changed.notify_all();
    }
}

static NEXT_ID: AtomicU64 = AtomicU64::new(1);
static SUBSCRIBERS: OnceLock<Mutex<HashMap<u64, Arc<FrameEvents>>>> = OnceLock::new();

fn subscribers() -> &'static Mutex<HashMap<u64, Arc<FrameEvents>>> {
    SUBSCRIBERS.get_or_init(Mutex::default)
}

fn lookup(id: u64) -> Option<Arc<FrameEvents>> {
    subscribers()
        .lock()
        .unwrap_or_else(|err| err.into_inner())
        .get(&id)
        .cloned()
}

pub(crate) fn notify_all() {
    let entries = subscribers().lock().unwrap_or_else(|err| err.into_inner());
    for events in entries.values() {
        events.notify();
    }
}

#[no_mangle]
pub extern "C" fn engine_frame_events_create() -> u64 {
    let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    let events = Arc::new(FrameEvents::default());
    // Scan once on registration, including frames completed before subscribing.
    events.notify();
    subscribers()
        .lock()
        .unwrap_or_else(|err| err.into_inner())
        .insert(id, events);
    id
}

/// Blocks off the UI thread. False means the subscription was disposed.
#[no_mangle]
pub extern "C" fn engine_frame_events_wait(id: u64) -> bool {
    lookup(id).is_some_and(|events| events.wait())
}

/// Rescan after texture registration, which may finish after GPU completion.
#[no_mangle]
pub extern "C" fn engine_frame_events_request(id: u64) {
    if let Some(events) = lookup(id) {
        events.notify();
    }
}

#[no_mangle]
pub extern "C" fn engine_frame_events_dispose(id: u64) {
    let events = subscribers()
        .lock()
        .unwrap_or_else(|err| err.into_inner())
        .remove(&id);
    if let Some(events) = events {
        events.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{sync::mpsc, thread, time::Duration};

    #[test]
    fn notifications_coalesce_and_waiter_sleeps_until_closed() {
        let events = Arc::new(FrameEvents::default());
        // A frame produced before wait must not be lost; repeated frames coalesce.
        events.notify();
        events.notify();
        assert!(events.wait());
        let (tx, rx) = mpsc::channel();
        let waiter_events = Arc::clone(&events);
        let waiter = thread::spawn(move || tx.send(waiter_events.wait()).unwrap());
        assert_eq!(
            rx.recv_timeout(Duration::from_millis(150)),
            Err(mpsc::RecvTimeoutError::Timeout)
        );
        events.close();
        assert!(!rx.recv_timeout(Duration::from_secs(5)).unwrap());
        waiter.join().unwrap();
    }

    #[test]
    fn disposing_subscription_releases_a_waiter_and_does_not_affect_others() {
        let first = engine_frame_events_create();
        let second = engine_frame_events_create();
        assert!(engine_frame_events_wait(first));
        assert!(engine_frame_events_wait(second));
        let (tx, rx) = mpsc::channel();
        let waiter = thread::spawn(move || tx.send(engine_frame_events_wait(first)).unwrap());
        engine_frame_events_dispose(first);
        assert!(!rx.recv_timeout(Duration::from_secs(5)).unwrap());
        engine_frame_events_request(second);
        assert!(engine_frame_events_wait(second));
        engine_frame_events_dispose(second);
        assert!(!engine_frame_events_wait(second));
        waiter.join().unwrap();
    }
}
