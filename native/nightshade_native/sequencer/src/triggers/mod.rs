//! Trigger system for the sequencer.
//!
//! Split by concern: [`trigger`] holds the [`Trigger`] record and its
//! condition evaluation, [`state`] the observed-condition snapshot the
//! evaluation reads, [`manager`] the collection that ticks them all,
//! [`meridian_window`] the shared flip-window test, and [`dawn`] the twilight
//! helper. This module is declarations and shared constants only.

mod dawn;
mod manager;
mod meridian_window;
mod state;
mod trigger;

pub use dawn::*;
pub use manager::*;
pub use meridian_window::*;
pub use state::*;
pub use trigger::*;

/// Hard upper bound on the FocusDrift rolling-window length.
/// The window is user-configurable (`TriggerType::FocusDrift::window_size`,
/// `lib.rs:1115`); enforcing a ceiling here keeps the in-memory footprint
/// bounded and prevents a misconfigured sequence from allocating an
/// unbounded ring buffer per trigger evaluation. 100 samples at the typical
/// 1 Hz monitor tick is 100 s of drift history — well past any reasonable
/// focus-drift detection horizon.
pub const FOCUS_DRIFT_WINDOW_MAX: usize = 100;

/// Extra time past the end of an exposure during which the camera still counts
/// as busy, covering sensor readout and download. Generous on purpose: the
/// cost of over-waiting is that a trigger-fired autofocus starts a few seconds
/// late, and the cost of under-waiting is a destroyed frame and a dead run.
pub const CAMERA_BUSY_DOWNLOAD_SLACK_SECS: f64 = 20.0;

#[cfg(test)]
mod cross_run_target_hygiene_tests;
#[cfg(test)]
mod east_target_flip_tests;
#[cfg(test)]
mod filter_change_edge_tests;
#[cfg(test)]
mod tests;
