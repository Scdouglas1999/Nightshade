//! Simulator connection-gate helpers (DEV-P3-3 follow-up).
//!
//! `device_manager::connection::connect_simulator` flips the matching
//! `simulation.rs` singleton's `connected` flag, but the per-op dispatchers
//! in `ops/{camera,mount,focuser,filter_wheel,rotator,...}.rs` previously
//! ignored that flag and returned hardcoded `Ok(value)` constants for every
//! `DriverType::Simulator` arm. That made the singleton's `connected`
//! state essentially decorative — a "disconnected" simulator still answered
//! every read with synthetic data, hiding bugs where the UI thought it
//! had an attached device when it did not.
//!
//! This module funnels every simulator op through one of two policies:
//!
//! 1. **Gated read** (`with_*_status`): consult the singleton; if
//!    `connected == true`, hand the caller a snapshot of the status
//!    struct and let it project whatever field it needs. If
//!    `connected == false`, return a descriptive `Err` so the caller
//!    surfaces the same fail-loud signal as a real driver that lost
//!    its handle.
//! 2. **Gated write** (`require_*_connected`): used by mutating ops
//!    (set/move/park/halt) that the singleton does not literally model
//!    but which still need to refuse to "succeed" when the simulator
//!    isn't connected. Returns `Ok(())` on connected, `Err` otherwise.
//!
//! Device types without a singleton (dome, cover, safety monitor, switch,
//! weather) are NOT served by this module — those ops emit the existing
//! "Simulator devices are disabled" fail-loud error (camera.rs:1591 style)
//! directly. Adding singletons for those device types is tracked separately
//! and intentionally out of scope here (CLAUDE.md: no stubs).
//!
//! Errors are a feature (CLAUDE.md). Every error returned from this module
//! names the simulator device type so the failure message points the user
//! at "connect first" rather than at an opaque `Ok(0)` that misled them
//! about whether the call succeeded.

use crate::api::devices::simulation::{
    get_sim_camera, get_sim_filterwheel, get_sim_focuser, get_sim_mount, get_sim_rotator,
};
use crate::device::{CameraStatus, FilterWheelStatus, FocuserStatus, MountStatus, RotatorStatus};

/// Format the not-connected error message uniformly across all simulator
/// device types. Keeping the wording centralized means tests can match on
/// a single substring (`"is not connected"`) without coupling to the exact
/// phrasing of each device type.
pub(crate) fn not_connected(kind: &'static str) -> String {
    format!(
        "Simulator {} is not connected. Call connect_device first.",
        kind
    )
}

/// Per-device-type convenience wrappers around `not_connected` for write-side
/// arms that take the singleton's write lock themselves (so they cannot use
/// `require_*_connected`, which would force two separate lock acquisitions).
#[inline]
pub(crate) fn not_connected_camera() -> String {
    not_connected("camera")
}

#[inline]
pub(crate) fn not_connected_mount() -> String {
    not_connected("mount")
}

#[inline]
pub(crate) fn not_connected_focuser() -> String {
    not_connected("focuser")
}

#[inline]
pub(crate) fn not_connected_filterwheel() -> String {
    not_connected("filter wheel")
}

#[inline]
pub(crate) fn not_connected_rotator() -> String {
    not_connected("rotator")
}

/// Read-side helper for camera ops: clones the singleton status when
/// connected, otherwise returns `Err`.
///
/// Status fields not modelled by `SimulatedCamera` (e.g. sensor dimensions
/// match the singleton's defaults — see `SimulatedCamera::default`) are
/// covered by the singleton's defaults and need no special handling at
/// the call site.
pub(crate) async fn read_camera_status() -> Result<CameraStatus, String> {
    let cam = get_sim_camera().read().await;
    if !cam.status.connected {
        return Err(not_connected("camera"));
    }
    Ok(cam.status.clone())
}

/// Write-side gate for camera ops: returns `Ok(())` only when the
/// simulator camera singleton is currently connected.
pub(crate) async fn require_camera_connected() -> Result<(), String> {
    if !get_sim_camera().read().await.status.connected {
        return Err(not_connected("camera"));
    }
    Ok(())
}

/// Read-side helper for mount ops.
pub(crate) async fn read_mount_status() -> Result<MountStatus, String> {
    let mount = get_sim_mount().read().await;
    if !mount.status.connected {
        return Err(not_connected("mount"));
    }
    Ok(mount.status.clone())
}

/// Write-side gate for mount ops.
pub(crate) async fn require_mount_connected() -> Result<(), String> {
    if !get_sim_mount().read().await.status.connected {
        return Err(not_connected("mount"));
    }
    Ok(())
}

/// Read-side helper for focuser ops.
pub(crate) async fn read_focuser_status() -> Result<FocuserStatus, String> {
    let focuser = get_sim_focuser().read().await;
    if !focuser.status.connected {
        return Err(not_connected("focuser"));
    }
    Ok(focuser.status.clone())
}

/// Write-side gate for focuser ops.
///
/// Kept as part of the symmetric surface even when current callers all
/// take the singleton's write lock themselves (and therefore use
/// `not_connected_focuser` instead) — symmetry makes "did the simulator
/// arm forget the gate?" reviewable at a glance.
#[allow(dead_code)]
pub(crate) async fn require_focuser_connected() -> Result<(), String> {
    if !get_sim_focuser().read().await.status.connected {
        return Err(not_connected("focuser"));
    }
    Ok(())
}

/// Read-side helper for filter wheel ops.
pub(crate) async fn read_filterwheel_status() -> Result<FilterWheelStatus, String> {
    let fw = get_sim_filterwheel().read().await;
    if !fw.status.connected {
        return Err(not_connected("filter wheel"));
    }
    Ok(fw.status.clone())
}

/// Write-side gate for filter wheel ops.
///
/// See `require_focuser_connected` for why this stays in the API surface
/// even when not currently invoked.
#[allow(dead_code)]
pub(crate) async fn require_filterwheel_connected() -> Result<(), String> {
    if !get_sim_filterwheel().read().await.status.connected {
        return Err(not_connected("filter wheel"));
    }
    Ok(())
}

/// Read-side helper for rotator ops.
pub(crate) async fn read_rotator_status() -> Result<RotatorStatus, String> {
    let rotator = get_sim_rotator().read().await;
    if !rotator.status.connected {
        return Err(not_connected("rotator"));
    }
    Ok(rotator.status.clone())
}

/// Write-side gate for rotator ops.
///
/// See `require_focuser_connected` for why this stays in the API surface
/// even when not currently invoked.
#[allow(dead_code)]
pub(crate) async fn require_rotator_connected() -> Result<(), String> {
    if !get_sim_rotator().read().await.status.connected {
        return Err(not_connected("rotator"));
    }
    Ok(())
}

/// Loud-error helper for simulator device types that have NO matching
/// singleton in `api::devices::simulation` (dome, cover calibrator,
/// safety monitor, switch, weather). The error mirrors `camera.rs:1591`
/// so the policy reads identically across files.
///
/// Adding a `SimulatedDome` etc. is tracked separately (see DEV-P3-3
/// follow-ups); this helper keeps the fail-loud wording consistent so
/// when a singleton is eventually added the call site only needs to
/// swap helpers, not rewrite the error message.
pub(crate) fn unsupported_simulator_device(kind: &'static str) -> String {
    format!(
        "Simulator {} devices are disabled (no simulator implementation). \
         Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.",
        kind
    )
}
