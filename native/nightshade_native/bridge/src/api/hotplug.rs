//! Hot-plug FFI surface.
//!
//! Exposes the manual rescan trigger used by the equipment-screen "Rescan
//! equipment" button. See `crate::hotplug` for the underlying hybrid
//! event-driven + slow-poll architecture.
//!
//! Why a separate module: the rest of `crate::api` is large and topical
//! (discovery, devices, sequencer, ...). Pulling the rescan entry point into
//! its own file keeps the call graph obvious — every Dart-callable hotplug
//! function lives here, and the implementation it delegates to lives in
//! `crate::hotplug`. No business logic in this file beyond the FFI shim.

use crate::api::api_invalidate_discovery_cache;
use crate::hotplug;

/// Force an immediate hot-plug diff pass across every polled driver and
/// device type, independent of the 30 s slow-poll cadence.
///
/// Wired to the equipment-screen "Rescan equipment" button. Behaviour:
///   1. Invalidate the per-(type, driver) discovery cache so the next UI
///      `discoverAll()` call cannot serve stale TTL'd results.
///   2. Run `hotplug::trigger_rescan` which walks the native vendor SDKs
///      and (on Windows) the ASCOM registry, diffs against the cached
///      snapshot and emits `device_discovered` / `device_lost` events for
///      any deltas. Existing devices do NOT re-emit (the diff is
///      idempotent across calls — see `cache_diff_detects_arrival_and_removal`
///      in `hotplug::tests`).
///
/// Returns when the diff finishes. The UI uses this as the await-target for
/// its spinner / "Rescanning..." label.
///
/// Errors: individual backend scan failures are surfaced via `tracing` from
/// inside `poll_once` and do not propagate here. We do NOT bubble them as a
/// `Result` because the diff itself is total — a single backend erroring
/// out must not cancel the other backends' arrival events, and a user
/// pressing Rescan does not want to debug an ASI SDK error from a Dart
/// snackbar. Real failures show up in the rolling log.
pub async fn api_rescan_devices() {
    tracing::info!("Manual hot-plug rescan triggered from UI");
    // Invalidate first so the diff's "fresh observed set" comes from a
    // re-enumerated SDK list, not a cached-50-seconds-ago one.
    api_invalidate_discovery_cache().await;
    hotplug::trigger_rescan().await;
}
