//! Device Manager with connection state management and auto-reconnection
//!
//! Provides a unified interface for managing device connections across
//! different driver backends (ASCOM, Alpaca, INDI, Native vendor SDKs).
//!
//! This module is the residual shell: it holds the `DeviceManager` and
//! `ManagedDevice` struct definitions, configuration types, constructors, and
//! lightweight query helpers (`get_all_devices`, `get_devices_by_type`,
//! `get_device`, `is_connected`). Heavier method groups live in sibling
//! submodules using Rust's split-impl-block feature:
//!
//! - `connection` — `register_device`, `connect_device`, `disconnect_device`,
//!   `reconnection_loop`, `set_auto_reconnect`, `report_error`, `shutdown`,
//!   `unregister_device`.
//! - `api_version` — cached `DeviceApiVersion` access + `query_*` dispatch +
//!   `device_supports_*` predicates.
//! - Per-driver `connect_*` and `query_*_api_version` helpers live in
//!   `crate::dispatch::{ascom,alpaca,indi,native}`.

pub(crate) mod api_version;
pub(crate) mod connection;
pub(crate) mod epoch;
pub(crate) mod heartbeat;
pub mod identity;
pub(crate) mod ops;

use crate::device::*;
use crate::state::SharedAppState;
use nightshade_native::traits::{
    NativeCamera, NativeCoverCalibrator, NativeDevice, NativeDome, NativeFilterWheel,
    NativeFocuser, NativeMount, NativeRotator, NativeSafetyMonitor, NativeSwitch, NativeWeather,
};
// Vendor SDK imports moved to crate::dispatch::native (the only consumer of
// the camera/mount/filter wheel/focuser constructors).
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Configuration for automatic reconnection
#[derive(Debug, Clone)]
pub struct ReconnectConfig {
    /// Whether auto-reconnection is enabled
    pub enabled: bool,
    /// Maximum number of reconnection attempts (0 = unlimited)
    pub max_attempts: u32,
    /// Initial delay between reconnection attempts
    pub initial_delay_secs: u64,
    /// Maximum delay between reconnection attempts
    pub max_delay_secs: u64,
    /// Backoff multiplier for exponential backoff
    pub backoff_multiplier: f64,
}

/// Configuration for heartbeat monitoring (per device type)
#[derive(Debug, Clone, Copy)]
#[flutter_rust_bridge::frb]
pub struct HeartbeatConfig {
    /// Base interval between heartbeats in seconds (default: 10)
    pub base_interval_secs: u64,
    /// Maximum interval (after backoff) in seconds (default: 60)
    pub max_interval_secs: u64,
    /// Number of consecutive failures before marking device disconnected (default: 3)
    pub failure_threshold: u32,
    /// Backoff multiplier when failures occur (default: 2.0)
    pub backoff_multiplier: f64,
    /// Whether to attempt automatic reconnection after disconnect (default: false)
    pub auto_reconnect: bool,
    /// Maximum number of reconnection attempts (0 = unlimited, default: 3)
    pub max_reconnect_attempts: u32,
    /// Delay before first reconnection attempt in seconds (default: 5)
    pub reconnect_delay_secs: u64,
    /// Whether crossing `failure_threshold` tears the device down (disconnect
    /// + reconnection loop) or merely latches a `Degraded` "stale" status while
    /// keeping the device connected and monitored.
    ///
    /// `true` for devices where liveness genuinely matters and a lost heartbeat
    /// means the session is in danger — cameras (a dead camera stalls every
    /// frame) and mounts (a dead mount drifts off target / can slew into the
    /// pier). For those, escalating to a real disconnect lets the auto-reconnect
    /// / recovery machinery act.
    ///
    /// Slow, USB-contention-prone auxiliary devices use higher failure
    /// thresholds, a per-poll retry, and explicit suppression during camera
    /// USB contention. Those protections absorb transient misses; once all of
    /// them are exhausted, keeping a dead accessory registered as Connected
    /// is worse than reconnecting it, so those devices also escalate.
    ///
    /// Default `true` so any device type that does not explicitly opt out keeps
    /// today's fail-loud behavior (errors are a feature).
    pub escalate_to_disconnect: bool,
}

impl Default for HeartbeatConfig {
    fn default() -> Self {
        Self {
            base_interval_secs: 10,
            max_interval_secs: 60,
            failure_threshold: 3,
            // Default to fixed cadence; device-specific constructors may
            // select exponential backoff when that better fits the hardware.
            backoff_multiplier: 1.0,
            auto_reconnect: false,
            max_reconnect_attempts: 3,
            reconnect_delay_secs: 5,
            escalate_to_disconnect: true,
        }
    }
}

impl HeartbeatConfig {
    /// Create a new config with the specified interval
    pub fn with_interval(interval_secs: u64) -> Self {
        Self {
            base_interval_secs: interval_secs,
            ..Default::default()
        }
    }

    /// Create a config with auto-reconnect enabled
    pub fn with_auto_reconnect(mut self, enabled: bool) -> Self {
        self.auto_reconnect = enabled;
        self
    }

    /// Set the failure threshold
    pub fn with_failure_threshold(mut self, threshold: u32) -> Self {
        self.failure_threshold = threshold;
        self
    }

    /// Set max reconnection attempts
    pub fn with_max_reconnect_attempts(mut self, attempts: u32) -> Self {
        self.max_reconnect_attempts = attempts;
        self
    }

    /// Create config optimized for cameras (less frequent during long exposures)
    pub fn for_camera() -> Self {
        Self {
            base_interval_secs: 10,
            max_interval_secs: 60,
            failure_threshold: 3,
            backoff_multiplier: 2.0,
            auto_reconnect: false,
            max_reconnect_attempts: 3,
            reconnect_delay_secs: 10,
            // Liveness genuinely matters: a dead camera stalls every frame, so
            // a sustained heartbeat loss should escalate to disconnect/recovery.
            escalate_to_disconnect: true,
        }
    }

    /// Create config optimized for mounts (frequent for tracking status)
    pub fn for_mount() -> Self {
        Self {
            base_interval_secs: 5,
            max_interval_secs: 30,
            failure_threshold: 2,
            backoff_multiplier: 1.5,
            auto_reconnect: true, // Mounts should auto-reconnect to maintain tracking
            max_reconnect_attempts: 5,
            reconnect_delay_secs: 3,
            // Liveness genuinely matters: a dead mount drifts off target and can
            // slew into the pier, so escalate to disconnect/recovery on loss.
            escalate_to_disconnect: true,
        }
    }

    /// Create config optimized for focusers (relatively stable)
    pub fn for_focuser() -> Self {
        Self {
            base_interval_secs: 15,
            max_interval_secs: 60,
            // Why: tolerate transient single-client USB contention (e.g. NINA
            // briefly holding the focuser). Each poll is also retried once.
            failure_threshold: 5,
            // Five consecutive, double-probed misses already provide strong
            // debounce. Keep polling at a fixed cadence so a genuinely dead
            // focuser is recovered in ~75s instead of several minutes.
            backoff_multiplier: 1.0,
            auto_reconnect: false,
            max_reconnect_attempts: 2,
            reconnect_delay_secs: 5,
            // Per-poll retry + camera-contention suppression handle transient
            // misses. Five sustained failures mean the registry must demote
            // the device so the Dart reconnect owner can recover it.
            escalate_to_disconnect: true,
        }
    }

    /// Create config optimized for filter wheels (rarely polled)
    pub fn for_filter_wheel() -> Self {
        Self {
            base_interval_secs: 20,
            max_interval_secs: 120,
            // Why: tolerate transient single-client USB contention (e.g. NINA
            // briefly holding the filter wheel). Each poll is retried once.
            failure_threshold: 5,
            // Fixed cadence recovers a genuinely lost wheel in ~100s while
            // retaining five consecutive double-probed misses as debounce.
            backoff_multiplier: 1.0,
            auto_reconnect: false,
            max_reconnect_attempts: 2,
            reconnect_delay_secs: 5,
            // Do not leave an unresponsive wheel in the connected inventory
            // indefinitely; sustained failures trigger Dart-owned reconnect.
            escalate_to_disconnect: true,
        }
    }

    /// Create config optimized for domes (slow operations, need patience)
    pub fn for_dome() -> Self {
        Self {
            base_interval_secs: 15,
            max_interval_secs: 90,
            failure_threshold: 4,
            backoff_multiplier: 2.0,
            auto_reconnect: true, // Domes should auto-reconnect for safety
            max_reconnect_attempts: 5,
            reconnect_delay_secs: 10,
            // Domes are a safety-relevant enclosure (rain/roof): keep today's
            // escalate-on-loss behavior so recovery runs.
            escalate_to_disconnect: true,
        }
    }

    /// Create config optimized for rotators
    pub fn for_rotator() -> Self {
        Self {
            base_interval_secs: 15,
            max_interval_secs: 60,
            // Why: tolerate transient single-client USB contention (e.g. NINA
            // briefly holding the rotator). Each poll is retried once.
            failure_threshold: 5,
            backoff_multiplier: 1.0,
            auto_reconnect: false,
            max_reconnect_attempts: 2,
            reconnect_delay_secs: 5,
            // Sustained failures must demote stale registry state so the Dart
            // reconnect owner can restore the rotator.
            escalate_to_disconnect: true,
        }
    }

    /// Create config optimized for weather stations (infrequent updates acceptable)
    pub fn for_weather() -> Self {
        Self {
            base_interval_secs: 30,
            max_interval_secs: 180,
            failure_threshold: 5,
            backoff_multiplier: 2.0,
            auto_reconnect: true, // Weather monitoring should auto-reconnect
            max_reconnect_attempts: 10,
            reconnect_delay_secs: 15,
            // Safety-relevant (clouds/rain): keep escalate-on-loss so recovery
            // runs and the session can react.
            escalate_to_disconnect: true,
        }
    }

    /// Create config for safety monitors.
    ///
    /// IMPORTANT: this heartbeat is only a LIVENESS ping. A SafetyMonitor's actual
    /// safety signal (`IsSafe`) is read on its OWN paths — the Dart environment
    /// poll and, during a run, the sequencer's fail-closed safety check — NOT via
    /// this heartbeat. The previous config put the safety monitor on the most
    /// aggressive escalate-to-disconnect path of any device (5s ping,
    /// failure_threshold 2, UNLIMITED 2s-delay auto-reconnect, escalate=true), so
    /// any flaky network hub — e.g. a JustaHub that occasionally misses a 5s
    /// quick-timeout ping — was torn down and reconnected in an endless
    /// disconnect -> error -> reconnect cycle, each iteration emitting fresh
    /// "disconnected" + "heartbeat" error toasts (a new episode every ~15-25s).
    ///
    /// Treat liveness like the focuser/filter-wheel/rotator: latch a Degraded
    /// "stale" badge and KEEP monitoring; never tear the device down on a missed
    /// ping. Genuine loss of safety is still caught by the real `IsSafe` read
    /// (fail-closed during a run), so safety is not silently lost.
    pub fn for_safety_monitor() -> Self {
        Self {
            base_interval_secs: 15,
            max_interval_secs: 60,
            failure_threshold: 4,
            backoff_multiplier: 2.0,
            auto_reconnect: false,
            max_reconnect_attempts: 2,
            reconnect_delay_secs: 10,
            escalate_to_disconnect: false,
        }
    }

    /// Create config optimized for guiders (critical during active guiding)
    pub fn for_guider() -> Self {
        Self {
            base_interval_secs: 5,
            max_interval_secs: 30,
            failure_threshold: 2,
            backoff_multiplier: 1.5,
            auto_reconnect: true,
            max_reconnect_attempts: 5,
            reconnect_delay_secs: 3,
            // Guiding liveness is critical during an exposure: escalate on loss
            // so recovery runs rather than silently letting guiding lapse.
            escalate_to_disconnect: true,
        }
    }

    /// Create config optimized for switch devices (slow-changing power/relay state)
    pub fn for_switch() -> Self {
        Self {
            base_interval_secs: 20,
            max_interval_secs: 120,
            // Why: tolerate transient single-client USB contention (e.g. NINA
            // briefly holding the switch); with 2.0 backoff + 20s base, 5
            // failures is well over a minute of genuine unresponsiveness.
            failure_threshold: 5,
            backoff_multiplier: 2.0,
            auto_reconnect: false,
            max_reconnect_attempts: 2,
            reconnect_delay_secs: 5,
            // A switch often controls rig power (dew heaters, the mount's own
            // supply). Keep escalate-on-loss so a genuinely-gone power controller
            // surfaces loudly rather than silently latching "stale". The raised
            // failure_threshold already absorbs transient USB contention.
            escalate_to_disconnect: true,
        }
    }

    /// Create config optimized for cover calibrators (session-safety accessory)
    pub fn for_cover_calibrator() -> Self {
        Self {
            base_interval_secs: 10,
            max_interval_secs: 60,
            failure_threshold: 3,
            backoff_multiplier: 2.0,
            auto_reconnect: true,
            max_reconnect_attempts: 5,
            reconnect_delay_secs: 5,
            // Session-safety accessory (flat panel / dust cover): keep
            // escalate-on-loss so recovery runs.
            escalate_to_disconnect: true,
        }
    }

    /// Get configuration for a specific device type
    pub fn for_device_type(device_type: &DeviceType) -> Self {
        match device_type {
            DeviceType::Camera => Self::for_camera(),
            DeviceType::Mount => Self::for_mount(),
            DeviceType::Focuser => Self::for_focuser(),
            DeviceType::FilterWheel => Self::for_filter_wheel(),
            DeviceType::Dome => Self::for_dome(),
            DeviceType::Rotator => Self::for_rotator(),
            DeviceType::Weather => Self::for_weather(),
            DeviceType::SafetyMonitor => Self::for_safety_monitor(),
            DeviceType::Guider => Self::for_guider(),
            DeviceType::Switch => Self::for_switch(),
            DeviceType::CoverCalibrator => Self::for_cover_calibrator(),
        }
    }
}

impl Default for ReconnectConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            max_attempts: 10,
            initial_delay_secs: 2,
            max_delay_secs: 60,
            backoff_multiplier: 1.5,
        }
    }
}

// INDI device-type inference helpers were moved to `crate::dispatch::indi`.

/// State of a managed device
#[derive(Debug, Clone)]
pub struct ManagedDevice {
    pub info: DeviceInfo,
    pub connection_state: ConnectionState,
    pub last_error: Option<String>,
    pub reconnect_attempts: u32,
    pub auto_reconnect: bool,
    /// Last successful communication timestamp (milliseconds since epoch)
    pub last_successful_comm: Option<i64>,
    /// Whether heartbeat monitoring is active
    pub heartbeat_active: bool,
    /// Cached API version information for the device
    pub api_version: Option<DeviceApiVersion>,
    /// Last commanded camera cooler state `(enabled, target_temp_c)`, recorded
    /// whenever `camera_set_cooler` succeeds. Re-applied after an unplanned
    /// reconnect so a USB yank mid-run does not silently leave the sensor
    /// warming up (the driver comes back with the cooler off / setpoint
    /// cleared). `None` until the cooler has been commanded at least once;
    /// cameras only.
    pub desired_cooler: Option<(bool, Option<f64>)>,
    /// Last commanded mount tracking state, recorded whenever
    /// `mount_set_tracking` succeeds. Re-applied after an unplanned reconnect
    /// so a mount that was tracking before the disconnect resumes tracking
    /// instead of sitting parked while the sequence "resumes". `None` until
    /// tracking has been commanded at least once; mounts only.
    pub desired_tracking: Option<bool>,
}

/// The Device Manager handles all device connections
pub struct DeviceManager {
    /// Application state for publishing events
    app_state: SharedAppState,

    /// Managed devices by their ID
    pub(crate) devices: RwLock<HashMap<String, ManagedDevice>>,

    /// Identity last OBSERVED from a live driver, keyed by device id.
    ///
    /// Written only after a successful connect, from what the driver itself
    /// reported — never from `device_info_from_id`, whose name is derived from
    /// the id string and would happily "confirm" a swapped camera. This is the
    /// baseline the next connect for the same id is checked against; see
    /// [`identity`].
    pub(crate) observed_identities: RwLock<HashMap<String, identity::DeviceIdentity>>,

    /// Reconnection configuration
    reconnect_config: ReconnectConfig,

    /// Flag to stop the reconnection task
    stop_reconnect: Arc<RwLock<bool>>,

    /// Active native device instances
    // Visibility bumped to pub(crate) so dispatch/native.rs can insert connected
    // generic NativeDevice handles without an extra accessor layer.
    pub(crate) native_devices: RwLock<HashMap<String, Box<dyn NativeDevice>>>,

    /// Active ASCOM camera wrappers (for typed access, wrapped in RwLock for interior mutability)
    #[cfg(windows)]
    /// Active ASCOM camera wrappers (for typed access, wrapped in RwLock for interior mutability)
    // Visibility bumped to pub(crate) so dispatch/ascom.rs can manage the typed
    // wrappers directly during connect / query / health-check paths.
    #[cfg(windows)]
    pub(crate) ascom_cameras:
        RwLock<HashMap<String, Arc<RwLock<crate::ascom_wrapper::camera::AscomCameraWrapper>>>>,

    /// Active ASCOM mount wrappers
    #[cfg(windows)]
    pub(crate) ascom_mounts:
        RwLock<HashMap<String, Arc<RwLock<crate::ascom_wrapper::mount::AscomMountWrapper>>>>,

    /// Active ASCOM focuser wrappers
    #[cfg(windows)]
    pub(crate) ascom_focusers:
        RwLock<HashMap<String, Arc<RwLock<crate::ascom_wrapper::focuser::AscomFocuserWrapper>>>>,

    /// Active ASCOM filter wheel wrappers
    #[cfg(windows)]
    pub(crate) ascom_filter_wheels: RwLock<
        HashMap<String, Arc<RwLock<crate::ascom_wrapper::filterwheel::AscomFilterWheelWrapper>>>,
    >,

    /// Active ASCOM rotator wrappers
    #[cfg(windows)]
    pub(crate) ascom_rotators:
        RwLock<HashMap<String, Arc<RwLock<crate::ascom_wrapper::rotator::AscomRotatorWrapper>>>>,

    /// Active ASCOM dome wrappers
    #[cfg(windows)]
    pub(crate) ascom_domes:
        RwLock<HashMap<String, Arc<RwLock<crate::ascom_wrapper::dome::AscomDomeWrapper>>>>,

    /// Active ASCOM weather wrappers
    #[cfg(windows)]
    pub(crate) ascom_weather: RwLock<
        HashMap<
            String,
            Arc<RwLock<crate::ascom_wrapper::weather::AscomObservingConditionsWrapper>>,
        >,
    >,

    /// Active ASCOM safety monitor wrappers
    #[cfg(windows)]
    pub(crate) ascom_safety_monitors: RwLock<
        HashMap<
            String,
            Arc<RwLock<crate::ascom_wrapper::safetymonitor::AscomSafetyMonitorWrapper>>,
        >,
    >,

    /// Active ASCOM switch wrappers
    #[cfg(windows)]
    pub(crate) ascom_switches:
        RwLock<HashMap<String, Arc<RwLock<crate::ascom_wrapper::switch::AscomSwitchWrapper>>>>,

    /// Active ASCOM cover calibrator wrappers
    #[cfg(windows)]
    pub(crate) ascom_cover_calibrators: RwLock<
        HashMap<
            String,
            Arc<RwLock<crate::ascom_wrapper::covercalibrator::AscomCoverCalibratorWrapper>>,
        >,
    >,

    /// Active INDI clients (key: "host:port")
    // Visibility bumped to pub(crate) so dispatch/indi.rs can manage the client
    // pool directly during connect / discover / health-check paths.
    pub(crate) indi_clients: RwLock<HashMap<String, Arc<RwLock<nightshade_indi::IndiClient>>>>,

    /// Active Alpaca camera clients
    // Visibility bumped to pub(crate) so dispatch/alpaca.rs can manage the typed
    // wrappers directly during connect / query / health-check paths.
    pub(crate) alpaca_cameras: RwLock<HashMap<String, Arc<nightshade_alpaca::AlpacaCamera>>>,

    /// Active Alpaca mount clients
    pub(crate) alpaca_mounts: RwLock<HashMap<String, Arc<nightshade_alpaca::AlpacaTelescope>>>,

    /// Active Alpaca focuser clients
    pub(crate) alpaca_focusers: RwLock<HashMap<String, Arc<nightshade_alpaca::AlpacaFocuser>>>,

    /// Active Alpaca filter wheel clients
    pub(crate) alpaca_filter_wheels:
        RwLock<HashMap<String, Arc<nightshade_alpaca::AlpacaFilterWheel>>>,

    /// Active Alpaca rotator clients
    pub(crate) alpaca_rotators: RwLock<HashMap<String, Arc<nightshade_alpaca::AlpacaRotator>>>,

    /// Active Alpaca dome clients
    pub(crate) alpaca_domes: RwLock<HashMap<String, Arc<nightshade_alpaca::AlpacaDome>>>,

    /// Active Alpaca observing conditions (weather) clients
    pub(crate) alpaca_weather:
        RwLock<HashMap<String, Arc<nightshade_alpaca::AlpacaObservingConditions>>>,

    /// Active Alpaca safety monitor clients
    pub(crate) alpaca_safety_monitors:
        RwLock<HashMap<String, Arc<nightshade_alpaca::AlpacaSafetyMonitor>>>,

    /// Active Alpaca switch clients
    pub(crate) alpaca_switches: RwLock<HashMap<String, Arc<nightshade_alpaca::AlpacaSwitch>>>,

    /// Active Alpaca cover calibrator clients
    pub(crate) alpaca_cover_calibrators:
        RwLock<HashMap<String, Arc<nightshade_alpaca::AlpacaCoverCalibrator>>>,

    /// Active Native SDK cameras (stored separately for typed access)
    pub(crate) native_cameras: RwLock<HashMap<String, Box<dyn NativeCamera + Send + Sync>>>,

    /// Active Native SDK focusers (stored separately for typed access)
    pub(crate) native_focusers: RwLock<HashMap<String, Box<dyn NativeFocuser + Send + Sync>>>,

    /// Active Native SDK filter wheels (stored separately for typed access)
    pub(crate) native_filter_wheels:
        RwLock<HashMap<String, Box<dyn NativeFilterWheel + Send + Sync>>>,

    /// Active Native SDK mounts (stored separately for typed access)
    pub(crate) native_mounts: RwLock<HashMap<String, Box<dyn NativeMount + Send + Sync>>>,

    /// Active Native SDK rotators (stored separately for typed access)
    pub(crate) native_rotators: RwLock<HashMap<String, Box<dyn NativeRotator + Send + Sync>>>,

    /// Active Native SDK domes (stored separately for typed access)
    pub(crate) native_domes: RwLock<HashMap<String, Box<dyn NativeDome + Send + Sync>>>,

    /// Active Native SDK weather stations (stored separately for typed access)
    pub(crate) native_weather: RwLock<HashMap<String, Box<dyn NativeWeather + Send + Sync>>>,

    /// Active Native SDK safety monitors (stored separately for typed access)
    pub(crate) native_safety_monitors:
        RwLock<HashMap<String, Box<dyn NativeSafetyMonitor + Send + Sync>>>,

    /// Active Native SDK switches (stored separately for typed access)
    pub(crate) native_switches: RwLock<HashMap<String, Box<dyn NativeSwitch + Send + Sync>>>,

    /// Active Native SDK cover calibrators (stored separately for typed access)
    pub(crate) native_cover_calibrators:
        RwLock<HashMap<String, Box<dyn NativeCoverCalibrator + Send + Sync>>>,

    /// Active heartbeat monitoring tasks (device_id -> join handle)
    heartbeat_tasks: RwLock<HashMap<String, tokio::task::JoinHandle<()>>>,

    /// Per-device cancellation tokens for in-flight reconnect attempts.
    ///
    /// The `reconnection_loop` (see `device_manager::connection`) sleeps for
    /// backoff and then issues a `connect_device_internal` call OUTSIDE the
    /// `devices` lock. If a user manually disconnects the device during that
    /// window, `disconnect_device` flips the token to `true` so the reconnect
    /// path bails before publishing a spurious `Connected` event.
    ///
    /// Lock ordering:
    ///   1. `devices`           (read or write)
    ///   2. `reconnect_cancel_tokens`  (read or write)
    ///
    /// Never hold `devices` while awaiting on a token; never hold a token-map
    /// lock across a sleep or a driver dispatch call.
    ///
    /// `disconnect_device` trips the token AFTER releasing the `devices` write
    /// lock (so the reconnect path can acquire it to bail), and the reconnect
    /// loop checks the token both during backoff and immediately after the
    /// driver dispatch returns so a late-arriving `Connected` event from a
    /// just-canceled attempt never reaches subscribers.
    pub(crate) reconnect_cancel_tokens: RwLock<HashMap<String, tokio::sync::watch::Sender<bool>>>,

    /// Device ids that currently have a long-running blocking operation in
    /// flight (e.g. a focuser move). While a device is in this set the
    /// heartbeat loop skips its poll, because a status read contended with the
    /// operation can block, queue behind the move on the single ASCOM STA
    /// thread, or be rejected by the driver — and must not be miscounted as a
    /// heartbeat failure that escalates to a spurious disconnect.
    ///
    /// A plain `std::sync::Mutex` (not a tokio lock) so the RAII
    /// [`OperationGuard`] can clear its entry from `Drop`, which cannot await.
    /// It is only ever held for the duration of a single insert/remove/contains
    /// and never across an `.await`, so it cannot deadlock with the async
    /// device locks.
    pub(crate) active_operations: Arc<std::sync::Mutex<std::collections::HashSet<String>>>,

    /// Number of camera exposure/download windows currently in flight across
    /// the whole rig.
    ///
    /// On shared-USB rigs (a ZWO EAF/EFW behind an ASI camera) the real cause
    /// of transient auxiliary read failures is the camera saturating the USB
    /// bus during frame download. While this counter is non-zero the heartbeat
    /// loop SKIPS polls for the USB-contention-prone auxiliary device types
    /// (focuser, filter wheel, rotator) — the same skip path as a per-device
    /// active operation — so a status read that merely lost a race with the
    /// download is never miscounted as a heartbeat failure.
    ///
    /// A counter (not a bool) so concurrent/overlapping exposures across
    /// multiple cameras nest correctly: contention is "active" until the LAST
    /// exposure window closes. An [`AtomicUsize`] (not a mutex) because the
    /// RAII [`UsbContentionGuard`] decrements it from `Drop`, which cannot
    /// await, and the heartbeat loop only ever reads it.
    pub(crate) usb_contention: Arc<std::sync::atomic::AtomicUsize>,
}

/// RAII marker that keeps a device id in [`DeviceManager::active_operations`]
/// for as long as it is alive, clearing it on drop — including on early
/// return, error, or panic — so a marker can never leak and permanently
/// silence a device's heartbeat. Created via [`DeviceManager::begin_operation`].
pub(crate) struct OperationGuard {
    active: Arc<std::sync::Mutex<std::collections::HashSet<String>>>,
    device_id: String,
}

impl Drop for OperationGuard {
    fn drop(&mut self) {
        // A poisoned lock means a previous holder panicked mid-mutation; the
        // set is still structurally valid, so recover the guard via
        // `into_inner` and clear our entry. Failing to clear would leave the
        // device's heartbeat suppressed forever, which is worse than a
        // momentary inconsistency.
        let mut set = match self.active.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        set.remove(&self.device_id);
    }
}

/// RAII marker that keeps the rig in a "USB contention" state (a camera is
/// exposing/downloading) for as long as it is alive, decrementing the
/// [`DeviceManager::usb_contention`] counter on drop — including on early
/// return, error, or panic — so the marker can never leak and permanently
/// silence the auxiliary heartbeats. Created via
/// [`DeviceManager::begin_usb_contention`].
pub(crate) struct UsbContentionGuard {
    counter: Arc<std::sync::atomic::AtomicUsize>,
}

impl Drop for UsbContentionGuard {
    fn drop(&mut self) {
        // `fetch_sub` wraps on underflow; that would only happen if a guard were
        // dropped twice, which the type system prevents (it is moved, not
        // cloned). Relaxed is sufficient: the heartbeat loop tolerates reading a
        // momentarily-stale value (it just polls one tick later or skips one
        // tick early), and there is no other memory we publish through this.
        self.counter
            .fetch_sub(1, std::sync::atomic::Ordering::Relaxed);
    }
}

impl DeviceManager {
    /// Mark the rig as being in a camera exposure/download window until the
    /// returned [`UsbContentionGuard`] is dropped. While the window is open the
    /// heartbeat loop skips polls for the USB-contention-prone auxiliary device
    /// types (focuser, filter wheel, rotator) — see [`Self::is_usb_contended`]
    /// and `run_heartbeat_loop` — so a status read that merely lost a race with
    /// the frame download on a shared USB bus is not miscounted as a heartbeat
    /// failure. Hold the guard for the full exposure+download window via
    /// `let _contention = mgr.begin_usb_contention();`.
    pub(crate) fn begin_usb_contention(&self) -> UsbContentionGuard {
        self.usb_contention
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        UsbContentionGuard {
            counter: self.usb_contention.clone(),
        }
    }

    /// Whether at least one camera exposure/download window is currently open
    /// (the rig is contending for shared USB bandwidth). The heartbeat loop
    /// consults this for the auxiliary device types so a contended status read
    /// is not counted as a failure.
    pub(crate) fn is_usb_contended(&self) -> bool {
        self.usb_contention
            .load(std::sync::atomic::Ordering::Relaxed)
            > 0
    }

    /// Whether the given device type is one whose heartbeat we suppress during
    /// a camera USB-contention window. These are the slow auxiliary devices
    /// that typically share the camera's USB path (ZWO EAF/EFW behind an ASI
    /// camera, a Pegasus focuser on the same hub, …) and whose liveness polls
    /// lose races with frame downloads. The camera and mount are deliberately
    /// excluded: the camera is the one driving the contention (and we never
    /// want to stop watching it), and the mount is on its own link / matters
    /// for tracking safety.
    pub(crate) fn device_type_suppressed_by_usb_contention(device_type: &DeviceType) -> bool {
        matches!(
            device_type,
            DeviceType::Focuser | DeviceType::FilterWheel | DeviceType::Rotator
        )
    }

    /// Mark `device_id` as having a blocking operation in flight until the
    /// returned [`OperationGuard`] is dropped. The heartbeat loop skips its
    /// poll for a device with an active operation (see `run_heartbeat_loop`),
    /// so a status read merely contended with the operation is not counted as a
    /// heartbeat failure. Hold the returned guard for the full duration of the
    /// operation (e.g. a focuser move) via `let _op = self.begin_operation(id);`.
    pub(crate) fn begin_operation(&self, device_id: &str) -> OperationGuard {
        let mut set = match self.active_operations.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        set.insert(device_id.to_string());
        drop(set);
        OperationGuard {
            active: self.active_operations.clone(),
            device_id: device_id.to_string(),
        }
    }

    /// Whether a blocking operation (e.g. a focuser move) is currently in
    /// flight for `device_id`. A poisoned lock is treated as "no active
    /// operation" so a panic elsewhere can never wedge the heartbeat into
    /// skipping forever.
    pub(crate) fn is_operation_active(&self, device_id: &str) -> bool {
        self.active_operations
            .lock()
            .map(|set| set.contains(device_id))
            .unwrap_or(false)
    }
}

impl DeviceManager {
    /// Create a new device manager
    pub fn new(app_state: SharedAppState) -> Arc<Self> {
        let manager = Arc::new(Self {
            app_state,
            devices: RwLock::new(HashMap::new()),
            observed_identities: RwLock::new(HashMap::new()),
            reconnect_config: ReconnectConfig::default(),
            stop_reconnect: Arc::new(RwLock::new(false)),
            native_devices: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_cameras: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_mounts: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_focusers: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_filter_wheels: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_rotators: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_domes: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_weather: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_safety_monitors: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_switches: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_cover_calibrators: RwLock::new(HashMap::new()),
            indi_clients: RwLock::new(HashMap::new()),
            alpaca_cameras: RwLock::new(HashMap::new()),
            alpaca_mounts: RwLock::new(HashMap::new()),
            alpaca_focusers: RwLock::new(HashMap::new()),
            alpaca_filter_wheels: RwLock::new(HashMap::new()),
            alpaca_rotators: RwLock::new(HashMap::new()),
            alpaca_domes: RwLock::new(HashMap::new()),
            alpaca_weather: RwLock::new(HashMap::new()),
            alpaca_safety_monitors: RwLock::new(HashMap::new()),
            alpaca_switches: RwLock::new(HashMap::new()),
            alpaca_cover_calibrators: RwLock::new(HashMap::new()),
            native_cameras: RwLock::new(HashMap::new()),
            native_focusers: RwLock::new(HashMap::new()),
            native_filter_wheels: RwLock::new(HashMap::new()),
            native_mounts: RwLock::new(HashMap::new()),
            native_rotators: RwLock::new(HashMap::new()),
            native_domes: RwLock::new(HashMap::new()),
            native_weather: RwLock::new(HashMap::new()),
            native_safety_monitors: RwLock::new(HashMap::new()),
            native_switches: RwLock::new(HashMap::new()),
            native_cover_calibrators: RwLock::new(HashMap::new()),
            heartbeat_tasks: RwLock::new(HashMap::new()),
            reconnect_cancel_tokens: RwLock::new(HashMap::new()),
            active_operations: Arc::new(std::sync::Mutex::new(std::collections::HashSet::new())),
            usb_contention: Arc::new(std::sync::atomic::AtomicUsize::new(0)),
        });

        // Start the reconnection background task
        // Note: Must have runtime available - ensured by api_init() calling ensure_runtime()
        let manager_clone = Arc::clone(&manager);
        // Get the runtime handle and spawn the task
        // We use the crate-level runtime which must be initialized first
        if let Ok(runtime) = crate::ensure_runtime() {
            runtime.handle().spawn(async move {
                manager_clone.reconnection_loop().await;
            });
        } else {
            tracing::error!("Cannot start reconnection loop: runtime initialization failed");
        }

        manager
    }

    /// Create with custom reconnection config
    pub fn with_config(app_state: SharedAppState, config: ReconnectConfig) -> Arc<Self> {
        let manager = Arc::new(Self {
            app_state,
            devices: RwLock::new(HashMap::new()),
            observed_identities: RwLock::new(HashMap::new()),
            reconnect_config: config,
            stop_reconnect: Arc::new(RwLock::new(false)),
            native_devices: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_cameras: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_mounts: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_focusers: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_filter_wheels: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_rotators: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_domes: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_weather: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_safety_monitors: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_switches: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_cover_calibrators: RwLock::new(HashMap::new()),
            indi_clients: RwLock::new(HashMap::new()),
            alpaca_cameras: RwLock::new(HashMap::new()),
            alpaca_mounts: RwLock::new(HashMap::new()),
            alpaca_focusers: RwLock::new(HashMap::new()),
            alpaca_filter_wheels: RwLock::new(HashMap::new()),
            alpaca_rotators: RwLock::new(HashMap::new()),
            alpaca_domes: RwLock::new(HashMap::new()),
            alpaca_weather: RwLock::new(HashMap::new()),
            alpaca_safety_monitors: RwLock::new(HashMap::new()),
            alpaca_switches: RwLock::new(HashMap::new()),
            alpaca_cover_calibrators: RwLock::new(HashMap::new()),
            native_cameras: RwLock::new(HashMap::new()),
            native_focusers: RwLock::new(HashMap::new()),
            native_filter_wheels: RwLock::new(HashMap::new()),
            native_mounts: RwLock::new(HashMap::new()),
            native_rotators: RwLock::new(HashMap::new()),
            native_domes: RwLock::new(HashMap::new()),
            native_weather: RwLock::new(HashMap::new()),
            native_safety_monitors: RwLock::new(HashMap::new()),
            native_switches: RwLock::new(HashMap::new()),
            native_cover_calibrators: RwLock::new(HashMap::new()),
            heartbeat_tasks: RwLock::new(HashMap::new()),
            reconnect_cancel_tokens: RwLock::new(HashMap::new()),
            active_operations: Arc::new(std::sync::Mutex::new(std::collections::HashSet::new())),
            usb_contention: Arc::new(std::sync::atomic::AtomicUsize::new(0)),
        });

        // Start the reconnection background task
        // Note: Must have runtime available - ensured by api_init() calling ensure_runtime()
        let manager_clone = Arc::clone(&manager);
        // Get the runtime handle and spawn the task
        // We use the crate-level runtime which must be initialized first
        if let Ok(runtime) = crate::ensure_runtime() {
            runtime.handle().spawn(async move {
                manager_clone.reconnection_loop().await;
            });
        } else {
            tracing::error!("Cannot start reconnection loop: runtime initialization failed");
        }

        manager
    }

    // `parse_indi_device_id` and `indi_mount_tracking_rate` moved to
    // `crate::dispatch::indi` (split-impl-block); call sites use `Self::...`
    // unchanged.
    //
    // Connection lifecycle (reconnection_loop, calculate_backoff_delay,
    // register_device, is_device_registered, get_device_display_name,
    // connect_device, connect_device_internal, connect_simulator,
    // disconnect_device, set_auto_reconnect, report_error, shutdown,
    // unregister_device) moved to `crate::device_manager::connection`.
    //
    // API version helpers (get/set/query_device_api_version,
    // device_supports_version, device_supports_action) moved to
    // `crate::device_manager::api_version`.

    /// Get all managed devices
    pub async fn get_all_devices(&self) -> Vec<ManagedDevice> {
        let devices = self.devices.read().await;
        devices.values().cloned().collect()
    }

    /// Get devices by type
    pub async fn get_devices_by_type(&self, device_type: DeviceType) -> Vec<ManagedDevice> {
        let devices = self.devices.read().await;
        devices
            .values()
            .filter(|d| d.info.device_type == device_type)
            .cloned()
            .collect()
    }

    /// Get a specific device
    pub async fn get_device(&self, device_id: &str) -> Option<ManagedDevice> {
        let devices = self.devices.read().await;
        devices.get(device_id).cloned()
    }

    /// Check if a device is connected
    ///
    /// # `unwrap_or` policy
    ///
    /// Device-not-registered → "not connected". Same rationale as
    /// `state::SharedAppState::is_device_connected`: a tri-state return
    /// (yes/no/unknown) would force every caller to handle an "unknown"
    /// branch that the UI maps back to "not connected" anyway.
    pub async fn is_connected(&self, device_id: &str) -> bool {
        let devices = self.devices.read().await;
        devices
            .get(device_id)
            .map(|d| d.connection_state == ConnectionState::Connected)
            .unwrap_or(false)
    }

    /// Whether a device of the given type and id is in the `Connected` state.
    pub async fn is_device_connected(&self, device_type: DeviceType, device_id: &str) -> bool {
        let devices = self.devices.read().await;
        devices
            .get(device_id)
            .map(|d| {
                d.info.device_type == device_type
                    && d.connection_state == ConnectionState::Connected
            })
            .unwrap_or(false)
    }

    /// First connected device id for a type (live `DeviceManager` registry).
    pub async fn first_connected_device_id(&self, device_type: DeviceType) -> Option<String> {
        let devices = self.devices.read().await;
        devices
            .values()
            .find(|d| {
                d.info.device_type == device_type
                    && d.connection_state == ConnectionState::Connected
            })
            .map(|d| d.info.id.clone())
    }

    /// Connected devices for FFI / Dart (`api_get_connected_devices` source of truth).
    pub async fn get_connected_device_infos(&self) -> Vec<DeviceInfo> {
        let devices = self.devices.read().await;
        devices
            .values()
            .filter(|d| d.connection_state == ConnectionState::Connected)
            .map(|d| d.info.clone())
            .collect()
    }

    /// Clone the shared Alpaca HTTP client for a connected device, if present.
    ///
    /// Reads the typed Alpaca maps owned by `DeviceManager` (not the legacy
    /// `ALPACA_CLIENTS` static in `api/connection.rs`).
    pub async fn alpaca_client_for_device(
        &self,
        device_id: &str,
    ) -> Option<Arc<nightshade_alpaca::AlpacaClient>> {
        let registered = self.alpaca_cameras.read().await.contains_key(device_id)
            || self.alpaca_mounts.read().await.contains_key(device_id)
            || self.alpaca_focusers.read().await.contains_key(device_id)
            || self
                .alpaca_filter_wheels
                .read()
                .await
                .contains_key(device_id)
            || self.alpaca_rotators.read().await.contains_key(device_id)
            || self.alpaca_domes.read().await.contains_key(device_id)
            || self.alpaca_weather.read().await.contains_key(device_id)
            || self
                .alpaca_safety_monitors
                .read()
                .await
                .contains_key(device_id)
            || self.alpaca_switches.read().await.contains_key(device_id)
            || self
                .alpaca_cover_calibrators
                .read()
                .await
                .contains_key(device_id);

        if registered {
            Self::alpaca_client_from_device_id(device_id)
        } else {
            None
        }
    }

    /// Construct an Alpaca HTTP client from a canonical device id (legacy API helper).
    fn alpaca_client_from_device_id(
        device_id: &str,
    ) -> Option<Arc<nightshade_alpaca::AlpacaClient>> {
        use crate::device_id::{parse_device_id_cached, ConnectionInfo};
        use nightshade_alpaca::{AlpacaClient, AlpacaDevice, AlpacaDeviceType};

        let parsed = parse_device_id_cached(device_id).ok()?;
        let ConnectionInfo::Alpaca {
            base_url,
            device_type,
            device_num,
            ..
        } = parsed.connection_info
        else {
            return None;
        };
        let alpaca_type = AlpacaDeviceType::from_str(&device_type)?;
        let device = AlpacaDevice {
            device_type: alpaca_type,
            device_number: device_num,
            server_name: base_url.clone(),
            manufacturer: String::new(),
            device_name: String::new(),
            unique_id: device_id.to_string(),
            base_url,
        };
        Some(Arc::new(AlpacaClient::new(&device)))
    }
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(windows)]
    use crate::ascom_wrapper::mount::test_support::{build_test_mount_wrapper, TestMountResponses};
    use crate::state::AppState;
    use std::collections::HashMap;
    use std::sync::Arc;
    use tokio::sync::{Mutex, RwLock};

    /// The one crate-wide lock over the simulator singletons. It lives next to
    /// the singletons themselves so every test module that touches them takes
    /// the SAME lock — two independent mutexes over one shared state exclude
    /// nothing.
    fn simulator_singleton_test_lock() -> &'static Mutex<()> {
        crate::api::devices::simulation::sim_singleton_test_lock()
    }

    #[test]
    fn test_heartbeat_config_default() {
        let config = HeartbeatConfig::default();
        assert_eq!(config.base_interval_secs, 10);
        assert_eq!(config.max_interval_secs, 60);
        assert_eq!(config.failure_threshold, 3);
        // 1.0 = FIXED cadence. The default deliberately does not back off;
        // exponential backoff is opted into by the device-specific constructors
        // (see HeartbeatConfig::default and the per-device `for_*` builders),
        // so a default multiplier of 2.0 here would silently stretch every
        // device's poll interval that had not chosen a policy.
        assert!((config.backoff_multiplier - 1.0).abs() < f64::EPSILON);
        assert!(!config.auto_reconnect);
        assert_eq!(config.max_reconnect_attempts, 3);
        assert_eq!(config.reconnect_delay_secs, 5);
    }

    #[test]
    fn test_heartbeat_config_for_camera() {
        let config = HeartbeatConfig::for_camera();
        assert_eq!(config.base_interval_secs, 10);
        assert_eq!(config.failure_threshold, 3);
        assert!(!config.auto_reconnect);
    }

    #[test]
    fn test_heartbeat_config_for_mount() {
        let config = HeartbeatConfig::for_mount();
        // Mounts should have more frequent monitoring
        assert_eq!(config.base_interval_secs, 5);
        // Mounts should auto-reconnect to maintain tracking
        assert!(config.auto_reconnect);
        assert_eq!(config.max_reconnect_attempts, 5);
    }

    #[test]
    fn test_heartbeat_config_for_safety_monitor() {
        let config = HeartbeatConfig::for_safety_monitor();
        // A safety monitor's heartbeat is only a LIVENESS ping — the real IsSafe
        // signal is read on separate paths — so it is treated like the auxiliary
        // devices: tolerate transient misses and NEVER escalate to a disconnect
        // (which previously flooded the UI with disconnect/error toasts on any
        // flaky network hub). See for_safety_monitor().
        assert_eq!(config.base_interval_secs, 15);
        assert_eq!(config.failure_threshold, 4);
        assert!(!config.auto_reconnect);
        assert!(!config.escalate_to_disconnect);
    }

    #[test]
    fn test_heartbeat_config_for_accessory_device_types() {
        let guider = HeartbeatConfig::for_device_type(&DeviceType::Guider);
        assert_eq!(guider.base_interval_secs, 5);
        assert!(guider.auto_reconnect);

        let switch = HeartbeatConfig::for_device_type(&DeviceType::Switch);
        assert_eq!(switch.base_interval_secs, 20);
        // Raised to 5 to tolerate transient single-client USB contention.
        assert_eq!(switch.failure_threshold, 5);
        assert!(!switch.auto_reconnect);

        let cover = HeartbeatConfig::for_device_type(&DeviceType::CoverCalibrator);
        assert_eq!(cover.base_interval_secs, 10);
        assert!(cover.auto_reconnect);
    }

    #[test]
    fn test_heartbeat_config_non_critical_failure_thresholds_raised() {
        // Why: non-critical accessories tolerate transient single-client USB
        // contention (e.g. NINA briefly holding the device). Five double-probed
        // misses provide debounce; fixed polling cadence still disconnects a
        // genuinely unresponsive accessory promptly enough for recovery.
        let focuser = HeartbeatConfig::for_focuser();
        assert_eq!(focuser.failure_threshold, 5);
        assert_eq!(focuser.base_interval_secs, 15);
        assert_eq!(focuser.backoff_multiplier, 1.0);
        assert!(focuser.escalate_to_disconnect);

        let filter_wheel = HeartbeatConfig::for_filter_wheel();
        assert_eq!(filter_wheel.failure_threshold, 5);
        assert_eq!(filter_wheel.base_interval_secs, 20);
        assert_eq!(filter_wheel.backoff_multiplier, 1.0);
        assert!(filter_wheel.escalate_to_disconnect);

        let rotator = HeartbeatConfig::for_rotator();
        assert_eq!(rotator.failure_threshold, 5);
        assert_eq!(rotator.base_interval_secs, 15);
        assert_eq!(rotator.backoff_multiplier, 1.0);
        assert!(rotator.escalate_to_disconnect);

        let switch = HeartbeatConfig::for_switch();
        assert_eq!(switch.failure_threshold, 5);
        assert_eq!(switch.base_interval_secs, 20);

        // Safety monitors are now non-escalating liveness (see for_safety_monitor):
        // threshold raised 2 -> 4 and they no longer tear down on a missed ping.
        assert_eq!(HeartbeatConfig::for_safety_monitor().failure_threshold, 4);

        // Critical/auto-reconnecting device types are intentionally unchanged.
        assert_eq!(HeartbeatConfig::for_camera().failure_threshold, 3);
        assert_eq!(HeartbeatConfig::for_mount().failure_threshold, 2);
        assert_eq!(HeartbeatConfig::for_guider().failure_threshold, 2);
        assert_eq!(HeartbeatConfig::for_dome().failure_threshold, 4);
        assert_eq!(HeartbeatConfig::for_weather().failure_threshold, 5);
        assert_eq!(HeartbeatConfig::for_cover_calibrator().failure_threshold, 3);
    }

    #[test]
    fn test_heartbeat_config_for_device_type() {
        // Test that for_device_type delegates to correct methods
        let camera_config = HeartbeatConfig::for_device_type(&DeviceType::Camera);
        assert_eq!(
            camera_config.base_interval_secs,
            HeartbeatConfig::for_camera().base_interval_secs
        );

        let mount_config = HeartbeatConfig::for_device_type(&DeviceType::Mount);
        assert!(mount_config.auto_reconnect);

        let safety_config = HeartbeatConfig::for_device_type(&DeviceType::SafetyMonitor);
        assert!(!safety_config.escalate_to_disconnect);
        assert_eq!(safety_config.max_reconnect_attempts, 2);
    }

    #[test]
    fn test_heartbeat_config_with_interval() {
        let config = HeartbeatConfig::with_interval(30);
        assert_eq!(config.base_interval_secs, 30);
        // Other fields should be default
        assert_eq!(config.failure_threshold, 3);
    }

    #[test]
    fn test_heartbeat_config_builder_pattern() {
        let config = HeartbeatConfig::with_interval(20)
            .with_auto_reconnect(true)
            .with_failure_threshold(5)
            .with_max_reconnect_attempts(10);

        assert_eq!(config.base_interval_secs, 20);
        assert!(config.auto_reconnect);
        assert_eq!(config.failure_threshold, 5);
        assert_eq!(config.max_reconnect_attempts, 10);
    }

    #[test]
    fn test_heartbeat_config_device_type_variations() {
        // All device types should return valid configurations
        let device_types = vec![
            DeviceType::Camera,
            DeviceType::Mount,
            DeviceType::Focuser,
            DeviceType::FilterWheel,
            DeviceType::Dome,
            DeviceType::Rotator,
            DeviceType::Weather,
            DeviceType::SafetyMonitor,
            DeviceType::Guider,
            DeviceType::Switch,
            DeviceType::CoverCalibrator,
        ];

        for device_type in device_types {
            let config = HeartbeatConfig::for_device_type(&device_type);
            // All configs should have reasonable values
            assert!(config.base_interval_secs > 0);
            assert!(config.base_interval_secs <= config.max_interval_secs);
            assert!(config.failure_threshold > 0);
            assert!(config.backoff_multiplier >= 1.0);
            assert!(config.reconnect_delay_secs > 0);
        }
    }

    #[test]
    fn test_reconnect_config_default() {
        let config = ReconnectConfig::default();
        assert!(config.enabled);
        assert_eq!(config.max_attempts, 10);
        assert_eq!(config.initial_delay_secs, 2);
        assert_eq!(config.max_delay_secs, 60);
        assert!((config.backoff_multiplier - 1.5).abs() < f64::EPSILON);
    }

    fn build_switch_info(id: &str, driver_type: DriverType) -> DeviceInfo {
        DeviceInfo {
            id: id.to_string(),
            name: "Test Switch".to_string(),
            device_type: DeviceType::Switch,
            driver_type,
            description: "Test switch device".to_string(),
            driver_version: "1.0".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: "Test Switch".to_string(),
        }
    }

    fn build_mount_info(id: &str, driver_type: DriverType) -> DeviceInfo {
        DeviceInfo {
            id: id.to_string(),
            name: "Test Mount".to_string(),
            device_type: DeviceType::Mount,
            driver_type,
            description: "Test mount device".to_string(),
            driver_version: "1.0".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: "Test Mount".to_string(),
        }
    }

    fn build_device_manager() -> DeviceManager {
        DeviceManager {
            app_state: AppState::new(),
            devices: RwLock::new(HashMap::new()),
            observed_identities: RwLock::new(HashMap::new()),
            reconnect_config: ReconnectConfig::default(),
            stop_reconnect: Arc::new(RwLock::new(false)),
            native_devices: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_cameras: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_mounts: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_focusers: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_filter_wheels: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_rotators: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_domes: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_weather: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_safety_monitors: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_switches: RwLock::new(HashMap::new()),
            #[cfg(windows)]
            ascom_cover_calibrators: RwLock::new(HashMap::new()),
            indi_clients: RwLock::new(HashMap::new()),
            alpaca_cameras: RwLock::new(HashMap::new()),
            alpaca_mounts: RwLock::new(HashMap::new()),
            alpaca_focusers: RwLock::new(HashMap::new()),
            alpaca_filter_wheels: RwLock::new(HashMap::new()),
            alpaca_rotators: RwLock::new(HashMap::new()),
            alpaca_domes: RwLock::new(HashMap::new()),
            alpaca_weather: RwLock::new(HashMap::new()),
            alpaca_safety_monitors: RwLock::new(HashMap::new()),
            alpaca_switches: RwLock::new(HashMap::new()),
            alpaca_cover_calibrators: RwLock::new(HashMap::new()),
            native_cameras: RwLock::new(HashMap::new()),
            native_focusers: RwLock::new(HashMap::new()),
            native_filter_wheels: RwLock::new(HashMap::new()),
            native_mounts: RwLock::new(HashMap::new()),
            native_rotators: RwLock::new(HashMap::new()),
            native_domes: RwLock::new(HashMap::new()),
            native_weather: RwLock::new(HashMap::new()),
            native_safety_monitors: RwLock::new(HashMap::new()),
            native_switches: RwLock::new(HashMap::new()),
            native_cover_calibrators: RwLock::new(HashMap::new()),
            heartbeat_tasks: RwLock::new(HashMap::new()),
            reconnect_cancel_tokens: RwLock::new(HashMap::new()),
            active_operations: Arc::new(std::sync::Mutex::new(std::collections::HashSet::new())),
            usb_contention: Arc::new(std::sync::atomic::AtomicUsize::new(0)),
        }
    }

    // =========================================================================
    // Device identity: a positional id must not silently re-bind
    // =========================================================================

    /// A connected vendor-SDK device whose reported identity the test controls.
    ///
    /// Stands in for the real thing behind `native:zwo:{n}`: on the reference
    /// rig that id is an ASI enumeration index, so replugging swapped
    /// `native:zwo:1` from the ASI1600MM-Cool to the ASI178MM while the id, the
    /// displayed name and the cached capabilities all stayed put.
    #[derive(Debug)]
    struct FakeIdentityDevice {
        id: String,
        model: String,
        serial: Option<String>,
    }

    #[async_trait::async_trait]
    impl nightshade_native::traits::NativeDevice for FakeIdentityDevice {
        fn id(&self) -> &str {
            &self.id
        }
        fn name(&self) -> &str {
            &self.model
        }
        fn vendor(&self) -> nightshade_native::NativeVendor {
            nightshade_native::NativeVendor::Zwo
        }
        fn serial_number(&self) -> Option<String> {
            self.serial.clone()
        }
        fn is_connected(&self) -> bool {
            true
        }
        async fn connect(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
        async fn disconnect(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
    }

    fn build_identity_camera_info() -> DeviceInfo {
        DeviceInfo {
            id: "sim_camera_1".to_string(),
            // The placeholder `device_info_from_id` derives from the id string:
            // it knows the vendor token and the index, and nothing else.
            name: "ZWO 1".to_string(),
            device_type: DeviceType::Camera,
            driver_type: DriverType::Simulator,
            description: "Native zwo driver".to_string(),
            driver_version: "Native".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: "ZWO 1".to_string(),
        }
    }

    async fn install_fake_device(
        manager: &DeviceManager,
        id: &str,
        model: &str,
        serial: Option<&str>,
    ) {
        manager.native_devices.write().await.insert(
            id.to_string(),
            Box::new(FakeIdentityDevice {
                id: id.to_string(),
                model: model.to_string(),
                serial: serial.map(|s| s.to_string()),
            }),
        );
    }

    /// A connect must read identity back off the driver and replace the
    /// id-derived placeholder name with it.
    ///
    /// Before this, `GET /api/devices/connected` reported `native:zwo:1` as
    /// `"ZWO 1"` on the live rig while discovery for the same id said
    /// `"ZWO ASI178MM"` — the connected-device name was a pure function of the
    /// id string and the driver was never asked.
    #[tokio::test]
    async fn connect_replaces_the_id_derived_name_with_the_drivers_own() {
        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = build_device_manager();
        let info = build_identity_camera_info();

        manager.register_device(info.clone(), false).await;
        install_fake_device(&manager, &info.id, "ZWO ASI1600MM-Cool", None).await;

        manager
            .connect_device_internal(&info)
            .await
            .expect("connect should succeed");

        assert_eq!(
            manager.get_device_display_name(&info.id).await.as_deref(),
            Some("ZWO ASI1600MM-Cool"),
            "the driver's own name must replace the id-derived placeholder"
        );

        crate::api::devices::simulation::get_sim_camera()
            .write()
            .await
            .status
            .connected = false;
    }

    /// The headline case: the id survives a replug but the hardware behind it
    /// does not. The connect must fail rather than image the wrong sensor.
    #[tokio::test]
    async fn connect_refuses_an_id_that_re_bound_to_different_hardware() {
        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = build_device_manager();
        let info = build_identity_camera_info();

        manager.register_device(info.clone(), false).await;

        // First connect: this id is the 1600, and that is recorded.
        install_fake_device(&manager, &info.id, "ZWO ASI1600MM-Cool", None).await;
        manager
            .connect_device_internal(&info)
            .await
            .expect("first connect should succeed");

        // Replug. The SDK re-enumerates and the same id is now the other body.
        install_fake_device(&manager, &info.id, "ZWO ASI178MM", Some("3520810329000900")).await;

        let err = manager
            .connect_device_internal(&info)
            .await
            .expect_err("a swapped camera must not connect");

        assert!(
            err.contains("no longer the same hardware"),
            "error should name the cause, got: {err}"
        );
        assert!(
            err.contains("ZWO ASI1600MM-Cool") && err.contains("ZWO ASI178MM"),
            "error should name both cameras so the operator can see the swap, got: {err}"
        );

        crate::api::devices::simulation::get_sim_camera()
            .write()
            .await
            .status
            .connected = false;
    }

    /// Reconnecting to the SAME hardware must stay routine — the gate must not
    /// turn an ordinary USB blip into a night-ending failure.
    #[tokio::test]
    async fn reconnecting_the_same_camera_is_not_treated_as_a_swap() {
        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = build_device_manager();
        let info = build_identity_camera_info();

        manager.register_device(info.clone(), false).await;
        install_fake_device(&manager, &info.id, "ZWO ASI178MM", Some("3520810329000900")).await;

        manager
            .connect_device_internal(&info)
            .await
            .expect("first connect should succeed");
        manager
            .connect_device_internal(&info)
            .await
            .expect("reconnecting the same camera must succeed");

        crate::api::devices::simulation::get_sim_camera()
            .write()
            .await
            .status
            .connected = false;
    }

    #[tokio::test]
    async fn test_mount_can_park_requires_registered_device() {
        let manager = build_device_manager();
        let err = manager
            .mount_can_park("missing-mount")
            .await
            .expect_err("missing mount should error");
        assert!(err.to_string().contains("Device not found"));
    }

    #[test]
    fn operation_guard_marks_and_clears_active_operations() {
        let manager = build_device_manager();

        // No operation in flight initially.
        assert!(!manager.is_operation_active("ascom:focuser"));

        {
            let _op = manager.begin_operation("ascom:focuser");
            // The guarded device is marked active...
            assert!(manager.is_operation_active("ascom:focuser"));
            // ...but an unrelated device is not, so a focuser move never
            // suppresses (for example) the mount's heartbeat.
            assert!(!manager.is_operation_active("ascom:mount"));
        }

        // Dropping the guard clears the marker so the heartbeat resumes.
        assert!(!manager.is_operation_active("ascom:focuser"));
    }

    #[test]
    fn operation_guards_are_independent_per_device() {
        let manager = build_device_manager();
        let op_a = manager.begin_operation("focuser:a");
        {
            let _op_b = manager.begin_operation("focuser:b");
            assert!(manager.is_operation_active("focuser:a"));
            assert!(manager.is_operation_active("focuser:b"));
        }
        // Dropping b leaves a's marker intact.
        assert!(manager.is_operation_active("focuser:a"));
        assert!(!manager.is_operation_active("focuser:b"));
        drop(op_a);
        assert!(!manager.is_operation_active("focuser:a"));
    }

    #[test]
    fn usb_contention_guard_marks_and_clears_contention() {
        let manager = build_device_manager();

        // No exposure in flight initially.
        assert!(!manager.is_usb_contended());

        {
            let _contention = manager.begin_usb_contention();
            assert!(
                manager.is_usb_contended(),
                "a live exposure window must mark the rig USB-contended"
            );
        }

        // Dropping the guard clears contention so aux heartbeats resume.
        assert!(!manager.is_usb_contended());
    }

    #[test]
    fn usb_contention_nests_for_overlapping_exposures() {
        let manager = build_device_manager();

        let outer = manager.begin_usb_contention();
        {
            let _inner = manager.begin_usb_contention();
            assert!(manager.is_usb_contended());
        }
        // Inner exposure finished but the outer one is still running: the rig
        // remains contended until the LAST window closes. This is the dual-
        // camera / overlapping-frame case.
        assert!(
            manager.is_usb_contended(),
            "contention must persist while any exposure window is still open"
        );
        drop(outer);
        assert!(
            !manager.is_usb_contended(),
            "contention clears only after the last exposure window closes"
        );
    }

    #[test]
    fn usb_contention_suppresses_only_aux_device_types() {
        // The focuser/filter-wheel/rotator share the camera's USB path and are
        // suppressed during a download window. The camera (which is driving the
        // contention) and the mount (own link, tracking-critical) are not.
        assert!(DeviceManager::device_type_suppressed_by_usb_contention(
            &DeviceType::Focuser
        ));
        assert!(DeviceManager::device_type_suppressed_by_usb_contention(
            &DeviceType::FilterWheel
        ));
        assert!(DeviceManager::device_type_suppressed_by_usb_contention(
            &DeviceType::Rotator
        ));

        for not_suppressed in [
            DeviceType::Camera,
            DeviceType::Mount,
            DeviceType::Dome,
            DeviceType::Weather,
            DeviceType::SafetyMonitor,
            DeviceType::Guider,
            DeviceType::Switch,
            DeviceType::CoverCalibrator,
        ] {
            assert!(
                !DeviceManager::device_type_suppressed_by_usb_contention(&not_suppressed),
                "{:?} must NOT be suppressed by USB contention",
                not_suppressed
            );
        }
    }

    #[test]
    fn escalate_to_disconnect_is_a_per_device_type_property() {
        // Every operational device escalates a sustained heartbeat loss so
        // stale registry state cannot remain advertised as connected.
        for escalating in [
            DeviceType::Camera,
            DeviceType::Mount,
            DeviceType::Focuser,
            DeviceType::FilterWheel,
            DeviceType::Rotator,
            DeviceType::Dome,
            DeviceType::Weather,
            DeviceType::Guider,
            DeviceType::Switch,
            DeviceType::CoverCalibrator,
        ] {
            assert!(
                HeartbeatConfig::for_device_type(&escalating).escalate_to_disconnect,
                "{:?} must escalate a heartbeat loss to disconnect",
                escalating
            );
        }

        // SafetyMonitor heartbeat is only a liveness hint; the independent
        // IsSafe signal owns enclosure safety decisions.
        assert!(!HeartbeatConfig::for_safety_monitor().escalate_to_disconnect);
    }

    #[tokio::test]
    async fn test_mount_stop_requires_registered_device() {
        let manager = build_device_manager();
        let err = manager
            .mount_stop("missing-mount")
            .await
            .expect_err("missing mount should error");
        assert!(err.to_string().contains("Device not found"));
    }

    /// Register a simulator mount so the simulator ops can be driven the same
    /// way a real driver is.
    async fn register_sim_mount(manager: &DeviceManager, device_id: &str) {
        manager.devices.write().await.insert(
            device_id.to_string(),
            ManagedDevice {
                info: build_mount_info(device_id, DriverType::Simulator),
                connection_state: ConnectionState::Connected,
                last_error: None,
                reconnect_attempts: 0,
                auto_reconnect: false,
                last_successful_comm: None,
                heartbeat_active: false,
                api_version: None,
                desired_cooler: None,
                desired_tracking: None,
            },
        );
    }

    /// A DISCONNECTED simulated mount must refuse motion commands and refuse to
    /// report a status, exactly as a real driver that lost its handle does.
    ///
    /// The HTTP API used to short-circuit `sim_` ids ahead of this gate, so a
    /// disconnected mount accepted slews and then reported itself simultaneously
    /// tracking and parked at coordinates it had taken while disconnected. Every
    /// "device disconnected mid-run" assertion on that surface was vacuous.
    #[tokio::test]
    async fn disconnected_simulated_mount_refuses_motion_and_status() {
        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = build_device_manager();
        let device_id = "sim_mount_disconnect_gate";
        register_sim_mount(&manager, device_id).await;

        {
            let mount = crate::api::devices::simulation::get_sim_mount();
            let mut mount = mount.write().await;
            mount.status.connected = false;
            mount.status.right_ascension = 0.0;
            mount.status.declination = 0.0;
            mount.status.parked = true;
            mount.status.tracking = false;
        }

        let slew = manager.mount_slew(device_id, 12.34, -5.6).await;
        assert!(
            slew.is_err(),
            "a disconnected simulated mount accepted a slew: {slew:?}"
        );
        assert!(manager.mount_park(device_id).await.is_err());
        assert!(manager.mount_unpark(device_id).await.is_err());
        assert!(manager.mount_set_tracking(device_id, true).await.is_err());
        assert!(
            manager.mount_get_status(device_id).await.is_err(),
            "a disconnected simulated mount answered a status read"
        );

        // And the refused slew must not have moved it.
        let mount = crate::api::devices::simulation::get_sim_mount()
            .read()
            .await
            .status
            .clone();
        assert_eq!(mount.right_ascension, 0.0);
        assert_eq!(mount.declination, 0.0);
        assert!(
            mount.parked,
            "a refused slew must leave the mount parked, not unparked"
        );
    }

    /// Once connected the same commands are accepted, so the refusal above is a
    /// gate rather than a permanently broken op.
    #[tokio::test]
    async fn connected_simulated_mount_accepts_a_slew() {
        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = build_device_manager();
        let device_id = "sim_mount_connect_gate";
        register_sim_mount(&manager, device_id).await;

        {
            let mount = crate::api::devices::simulation::get_sim_mount();
            let mut mount = mount.write().await;
            mount.status.connected = true;
            mount.status.parked = true;
        }

        manager
            .mount_slew(device_id, 5.5, 30.0)
            .await
            .expect("a connected simulated mount should accept a slew");

        // The simulated mount travels rather than teleporting, so read through
        // `mount_get_status` (which advances the motion) until it arrives.
        let mut mount = manager.mount_get_status(device_id).await.unwrap();
        for _ in 0..200 {
            if !mount.slewing {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(25)).await;
            mount = manager.mount_get_status(device_id).await.unwrap();
        }
        assert!(!mount.slewing, "the simulated slew never finished");
        assert!((mount.right_ascension - 5.5).abs() < 1e-9);
        assert!((mount.declination - 30.0).abs() < 1e-9);
        assert!(!mount.parked);

        crate::api::devices::simulation::get_sim_mount()
            .write()
            .await
            .status
            .connected = false;
    }

    #[cfg(windows)]
    #[tokio::test]
    async fn test_mount_get_status_uses_ascom_can_park() {
        let manager = build_device_manager();
        let device_id = "ascom:test-mount";
        let info = build_mount_info(device_id, DriverType::Ascom);

        manager.devices.write().await.insert(
            device_id.to_string(),
            ManagedDevice {
                info,
                connection_state: ConnectionState::Connected,
                last_error: None,
                reconnect_attempts: 0,
                auto_reconnect: false,
                last_successful_comm: None,
                heartbeat_active: false,
                api_version: None,
                desired_cooler: None,
                desired_tracking: None,
            },
        );

        let responses = TestMountResponses {
            coordinates: (1.0, 2.0),
            alt_az: (3.0, 4.0),
            tracking: true,
            slewing: false,
            parked: false,
            side_of_pier: nightshade_native::traits::PierSide::East,
            sidereal_time: 5.0,
            can_park: false,
        };
        manager.ascom_mounts.write().await.insert(
            device_id.to_string(),
            Arc::new(RwLock::new(build_test_mount_wrapper(responses))),
        );

        let status = manager
            .mount_get_status(device_id)
            .await
            .expect("mount_get_status");
        assert!(!status.can_park);
    }

    #[tokio::test]
    async fn test_switch_methods_require_registered_device() {
        let manager = build_device_manager();
        let device_id = "missing-switch";

        let err = manager.switch_get_max(device_id).await.unwrap_err();
        assert!(err.to_string().contains("Device not found"));

        let err = manager.switch_get_state(device_id, 0).await.unwrap_err();
        assert!(err.to_string().contains("Device not found"));

        let err = manager
            .switch_set_state(device_id, 0, true)
            .await
            .unwrap_err();
        assert!(err.to_string().contains("Device not found"));

        let err = manager.switch_get_name(device_id, 0).await.unwrap_err();
        assert!(err.to_string().contains("Device not found"));

        let err = manager
            .switch_get_description(device_id, 0)
            .await
            .unwrap_err();
        assert!(err.to_string().contains("Device not found"));

        let err = manager.switch_get_value(device_id, 0).await.unwrap_err();
        assert!(err.to_string().contains("Device not found"));

        let err = manager
            .switch_set_value(device_id, 0, 1.0)
            .await
            .unwrap_err();
        assert!(err.to_string().contains("Device not found"));

        let err = manager
            .switch_get_min_value(device_id, 0)
            .await
            .unwrap_err();
        assert!(err.to_string().contains("Device not found"));

        let err = manager
            .switch_get_max_value(device_id, 0)
            .await
            .unwrap_err();
        assert!(err.to_string().contains("Device not found"));

        let err = manager.switch_can_write(device_id, 0).await.unwrap_err();
        assert!(err.to_string().contains("Device not found"));
    }

    #[tokio::test]
    async fn test_switch_get_max_reports_missing_alpaca_device() {
        let manager = build_device_manager();
        let device_id = "alpaca:test-switch";
        let info = build_switch_info(device_id, DriverType::Alpaca);
        manager.register_device(info, false).await;

        let err = manager.switch_get_max(device_id).await.unwrap_err();
        assert!(err.to_string().contains("Alpaca switch"));
    }

    // -------------------------------------------------------------------------
    // stop_heartbeat must not emit HeartbeatStopped when there was
    // no heartbeat task to stop. Otherwise every connect (which defensively
    // calls stop_heartbeat first) emits a spurious stop event.
    // -------------------------------------------------------------------------
    #[tokio::test]
    async fn stop_heartbeat_on_unknown_device_emits_no_event() {
        use crate::event::{EquipmentEvent, EventPayload};
        use tokio::sync::broadcast::error::TryRecvError;

        let manager = build_device_manager();
        // Subscribe BEFORE the call so we'd catch any published event.
        let mut rx = manager.app_state.event_bus.subscribe();

        // Device id that was never registered and never had a heartbeat.
        manager
            .stop_heartbeat("nonexistent-device-id")
            .await
            .expect("stop_heartbeat on unknown device should succeed");

        // Drain any events and assert NONE of them are HeartbeatStopped for
        // our device id. Other events from background tasks are tolerated.
        loop {
            match rx.try_recv() {
                Ok(event) => {
                    if let EventPayload::Equipment(EquipmentEvent::HeartbeatStopped {
                        device_id,
                        ..
                    }) = &event.payload
                    {
                        panic!(
                            "stop_heartbeat on unknown device unexpectedly published \
                             HeartbeatStopped for {}",
                            device_id
                        );
                    }
                }
                Err(TryRecvError::Empty) | Err(TryRecvError::Closed) => break,
                Err(TryRecvError::Lagged(_)) => continue,
            }
        }
    }

    // Same protection for a registered device that simply never had a heartbeat
    // started — `start_heartbeat_with_config` calls `stop_heartbeat` defensively
    // first, so the very first connect would otherwise publish a stop event.
    #[tokio::test]
    async fn stop_heartbeat_on_registered_but_inactive_device_emits_no_event() {
        use crate::event::{EquipmentEvent, EventPayload};
        use tokio::sync::broadcast::error::TryRecvError;

        let manager = build_device_manager();
        let device_id = "alpaca:test-mount";
        let info = build_mount_info(device_id, DriverType::Alpaca);
        manager.register_device(info, false).await;

        let mut rx = manager.app_state.event_bus.subscribe();

        manager
            .stop_heartbeat(device_id)
            .await
            .expect("stop_heartbeat on registered-but-inactive device should succeed");

        loop {
            match rx.try_recv() {
                Ok(event) => {
                    if let EventPayload::Equipment(EquipmentEvent::HeartbeatStopped {
                        device_id: published_id,
                        ..
                    }) = &event.payload
                    {
                        assert_ne!(
                            published_id, device_id,
                            "stop_heartbeat on registered-but-inactive device must not \
                             publish HeartbeatStopped"
                        );
                    }
                }
                Err(TryRecvError::Empty) | Err(TryRecvError::Closed) => break,
                Err(TryRecvError::Lagged(_)) => continue,
            }
        }
    }

    // -------------------------------------------------------------------------
    // `disconnect_device` must route PHD2 device ids through the
    // PHD2-specific disconnect helper (mirroring the built-in-guider check),
    // otherwise the PHD2 client is leaked on disconnect.
    //
    // We can't run the real PHD2 dispatch in a unit test (no server), but we
    // can at least lock down the contract that:
    //   - the helper name we depend on exists and has the expected signature
    //     (this is a compile-time check: a typo would break the build)
    //   - `is_phd2_device_id` recognizes the canonical PHD2 ids the
    //     `disconnect_device` arm dispatches on.
    // -------------------------------------------------------------------------
    #[tokio::test]
    async fn disconnect_phd2_via_generic_route_calls_phd2_disconnect() {
        // Compile-time check: ensure both helpers referenced by
        // `disconnect_device` exist with the expected signatures. If either
        // changes name or shape, this test stops compiling — which is the
        // signal we want, because the dispatch arm in connection.rs depends
        // on them. The `let _ = ...` pattern with explicit return-type
        // bindings forces the compiler to resolve the symbols without
        // actually invoking them.
        let _is_id_fn: fn(&str) -> bool = crate::api::connection::is_phd2_device_id;
        // `api_phd2_disconnect` is async; binding the call (not the await)
        // produces a future we discard. This both proves the symbol exists
        // AND that its return type unifies with `Result<(), _>` shape.
        let _disconnect_fut = async {
            let _: Result<(), crate::error::NightshadeError> =
                crate::api::phd2::api_phd2_disconnect().await;
        };

        // Behavioral check: the id-recognition helper must accept every form
        // a PHD2 device id can take, so the dispatch arm fires for all of
        // them. If a new id format is added, both this list and
        // `is_phd2_device_id` need to be updated together.
        for id in ["phd2", "phd2_guider", "phd2:localhost:4400", "phd2://host"] {
            assert!(
                crate::api::connection::is_phd2_device_id(id),
                "is_phd2_device_id must recognize {} so disconnect_device dispatches \
                 PHD2-specific cleanup",
                id
            );
        }

        // And a non-PHD2 id must NOT trigger the dispatch arm.
        assert!(!crate::api::connection::is_phd2_device_id(
            "alpaca:test-guider"
        ));
        assert!(!crate::api::connection::is_phd2_device_id(
            "phd2x-not-really-phd2"
        ));
    }

    // -------------------------------------------------------------------------
    // a manual `disconnect_device` arriving while a reconnect attempt
    // is between backoff and dispatch (i.e. inside `connect_device_internal`)
    // must trip the per-device cancel token so the connect attempt bails with
    // `RECONNECT_CANCELED_MSG` instead of overwriting the user's Disconnected
    // state with Connected.
    //
    // This test exercises the contract directly:
    //   1. Install the cancel token (mirrors what `reconnection_loop` does
    //      after backoff begins).
    //   2. Run `disconnect_device`, which must call `trip_reconnect_cancel_
    //      token` AFTER releasing the devices write lock.
    //   3. A subsequent `connect_device_internal` call (mirrors the dispatch
    //      the loop would issue after backoff) must short-circuit with
    //      `RECONNECT_CANCELED_MSG` and must NOT flip the device back to
    //      `Connected`.
    // -------------------------------------------------------------------------
    #[tokio::test]
    async fn manual_disconnect_trips_in_flight_reconnect_cancel_token() {
        use crate::device_manager::connection::RECONNECT_CANCELED_MSG;

        let manager = build_device_manager();
        let device_id = "simulator:test-reconnect-cancel";
        let info = DeviceInfo {
            id: device_id.to_string(),
            name: "Sim Cancel Mount".to_string(),
            device_type: DeviceType::Mount,
            driver_type: DriverType::Simulator,
            description: "Test mount for cancel token wiring".to_string(),
            driver_version: "1.0".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: "Sim Cancel Mount".to_string(),
        };

        // Step 1: register and mark the device as in the Error state, which is
        // what reconnection_loop sees when it picks it up. Auto-reconnect ON.
        manager.register_device(info.clone(), true).await;
        {
            let mut devices = manager.devices.write().await;
            let dev = devices
                .get_mut(device_id)
                .expect("device should be registered");
            dev.connection_state = ConnectionState::Error;
            dev.last_error = Some("simulated transient failure".to_string());
        }

        // Step 2: install the cancel token (mirrors reconnection_loop before
        // its backoff sleep). We hold a receiver to assert the trip below.
        let mut cancel_rx = manager.install_reconnect_cancel_token(device_id).await;
        assert!(!*cancel_rx.borrow(), "token must start un-tripped");

        // Step 3: user calls disconnect_device. This must trip the token.
        manager
            .disconnect_device(device_id)
            .await
            .expect("disconnect_device should succeed for registered simulator device");

        // The cancel token must now be tripped. `changed()` resolves
        // immediately because `send_replace(true)` woke the watcher.
        cancel_rx
            .changed()
            .await
            .expect("trip_reconnect_cancel_token must signal watchers");
        assert!(
            *cancel_rx.borrow(),
            "disconnect_device must trip the in-flight reconnect cancel token"
        );

        // Auto-reconnect must also be off so the loop wouldn't re-pick this
        // device on its next tick (defense-in-depth: even if the dispatch
        // call below somehow ignored the token, the loop's filter would).
        {
            let devices = manager.devices.read().await;
            let dev = devices.get(device_id).expect("device still registered");
            assert!(
                !dev.auto_reconnect,
                "disconnect_device must clear auto_reconnect"
            );
            assert_eq!(
                dev.connection_state,
                ConnectionState::Disconnected,
                "disconnect_device must leave state Disconnected"
            );
        }

        // Step 4: the reconnection loop, unaware of the disconnect, now
        // dispatches `connect_device_internal`. Because the token is tripped,
        // this must return RECONNECT_CANCELED_MSG and must NOT mutate the
        // device's state back to Connected.
        let result = manager.connect_device_internal(&info).await;
        match result {
            Err(e) if e == RECONNECT_CANCELED_MSG => {}
            other => panic!(
                "connect_device_internal with tripped token must return \
                 RECONNECT_CANCELED_MSG, got {:?}",
                other
            ),
        }

        // The device state must remain Disconnected — the reconnect attempt
        // is not allowed to silently re-Connect a device the user released.
        let devices = manager.devices.read().await;
        let dev = devices.get(device_id).expect("device still registered");
        assert_eq!(
            dev.connection_state,
            ConnectionState::Disconnected,
            "canceled reconnect must NOT flip state back to Connected"
        );
    }

    // -------------------------------------------------------------------------
    // DEV-P3-3: `connect_simulator` / `disconnect_simulator` must actually flip
    // the matching `simulation.rs` singleton's `connected` flag, and the
    // heartbeat path for `DriverType::Simulator` must read that flag instead
    // of trivially reporting healthy. Previously `connect_simulator` was a
    // no-op and the heartbeat returned `Ok(true)` unconditionally — so a
    // "connected" simulator had no real driver state behind it.
    //
    // Tests use distinct device_type prefixes to avoid cross-test interference
    // through the process-wide simulation.rs singletons.
    // -------------------------------------------------------------------------
    fn build_sim_info(id: &str, device_type: DeviceType) -> DeviceInfo {
        DeviceInfo {
            id: id.to_string(),
            name: format!("Simulated {}", device_type.as_str()),
            device_type,
            driver_type: DriverType::Simulator,
            description: "Simulator under test".to_string(),
            driver_version: "1.0".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: format!("Simulated {}", device_type.as_str()),
        }
    }

    #[tokio::test]
    async fn connect_simulator_marks_singleton_connected() {
        use crate::api::devices::simulation::get_sim_focuser;

        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = build_device_manager();
        let info = build_sim_info("sim_focuser_1", DeviceType::Focuser);

        // Reset the singleton to disconnected so this test is independent of
        // any earlier test that may have left state behind.
        {
            let mut focuser = get_sim_focuser().write().await;
            focuser.status.connected = false;
        }

        manager
            .connect_simulator(&info)
            .await
            .expect("connect_simulator should succeed for a valid sim focuser id");

        let connected = get_sim_focuser().read().await.status.connected;
        assert!(
            connected,
            "connect_simulator must set the focuser singleton's connected flag to true"
        );

        // Idempotency: a second connect must succeed and leave connected=true.
        manager
            .connect_simulator(&info)
            .await
            .expect("connect_simulator must be idempotent");
        assert!(get_sim_focuser().read().await.status.connected);

        // Unrecognized id (no `sim_` prefix) must surface a descriptive error.
        let bogus = build_sim_info("not_a_sim", DeviceType::Focuser);
        let err = manager
            .connect_simulator(&bogus)
            .await
            .expect_err("non-sim id must fail loudly");
        assert!(
            err.contains("not a simulator id"),
            "error message must call out the prefix mismatch: {}",
            err
        );

        // Unsupported device type (no simulation.rs singleton) must error.
        // Guider is the remaining one; switch and cover calibrator now have
        // simulators and are covered by their own test below.
        let guider = build_sim_info("sim_guider_1", DeviceType::Guider);
        let err = manager
            .connect_simulator(&guider)
            .await
            .expect_err("unsupported sim device type must fail loudly");
        assert!(
            err.contains("no simulator implementation"),
            "error message must call out the missing implementation: {}",
            err
        );

        // Cleanup: restore the singleton to the default disconnected state so
        // other tests that touch SIM_FOCUSER aren't affected.
        get_sim_focuser().write().await.status.connected = false;
    }

    #[tokio::test]
    async fn observatory_accessory_simulators_support_status_and_safe_controls() {
        use crate::api::devices::simulation::{
            get_sim_dome, get_sim_safety_monitor, get_sim_weather,
        };

        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = build_device_manager();
        let devices = [
            build_sim_info("sim_dome_1", DeviceType::Dome),
            build_sim_info("sim_weather_1", DeviceType::Weather),
            build_sim_info("sim_safety_monitor_1", DeviceType::SafetyMonitor),
        ];

        for info in &devices {
            manager.register_device(info.clone(), false).await;
            manager
                .connect_simulator(info)
                .await
                .expect("accessory simulator should connect");
        }

        let initial = manager
            .dome_get_status("sim_dome_1")
            .await
            .expect("read initial dome status");
        assert!(initial.connected);
        assert_eq!(initial.shutter_status, ShutterState::Closed);

        manager
            .dome_open_shutter("sim_dome_1")
            .await
            .expect("open simulated shutter");
        manager
            .dome_slew_to_azimuth("sim_dome_1", 42.5)
            .await
            .expect("slew simulated dome");
        manager
            .dome_set_slaved("sim_dome_1", true)
            .await
            .expect("slave simulated dome");
        let changed = manager
            .dome_get_status("sim_dome_1")
            .await
            .expect("read changed dome status");
        assert_eq!(changed.shutter_status, ShutterState::Open);
        assert!((changed.azimuth - 42.5).abs() < f64::EPSILON);
        assert!(changed.is_slaved);

        manager
            .dome_close_shutter("sim_dome_1")
            .await
            .expect("close simulated shutter");
        manager
            .dome_park("sim_dome_1")
            .await
            .expect("park simulated dome");
        let parked = manager
            .dome_get_status("sim_dome_1")
            .await
            .expect("read parked dome status");
        assert_eq!(parked.shutter_status, ShutterState::Closed);
        assert!(parked.at_park);

        let weather = manager
            .weather_get_conditions("sim_weather_1")
            .await
            .expect("read simulated weather");
        assert_eq!(weather.rain_rate, Some(0.0));
        assert!(weather.temperature.is_some());

        assert!(manager
            .safety_is_safe("sim_safety_monitor_1")
            .await
            .expect("read simulated safety state"));

        for info in &devices {
            assert!(manager
                .perform_health_check(&info.id, &info.device_type, &DriverType::Simulator)
                .await
                .expect("accessory simulator heartbeat"));
            manager
                .disconnect_simulator(info)
                .await
                .expect("accessory simulator should disconnect");
        }

        assert!(!get_sim_dome().read().await.status.connected);
        assert!(!get_sim_weather().read().await.connected);
        assert!(!get_sim_safety_monitor().read().await.status.connected);
    }

    #[tokio::test]
    async fn disconnect_simulator_marks_singleton_disconnected() {
        use crate::api::devices::simulation::get_sim_filterwheel;

        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = build_device_manager();
        let info = build_sim_info("sim_filterwheel_1", DeviceType::FilterWheel);

        // Pre-condition: bring the singleton to connected.
        manager
            .connect_simulator(&info)
            .await
            .expect("connect_simulator setup should succeed");
        assert!(get_sim_filterwheel().read().await.status.connected);

        manager
            .disconnect_simulator(&info)
            .await
            .expect("disconnect_simulator should succeed for a valid sim fw id");

        let connected = get_sim_filterwheel().read().await.status.connected;
        assert!(
            !connected,
            "disconnect_simulator must clear the filter wheel singleton's connected flag"
        );

        // Idempotency: a second disconnect must succeed and leave it false.
        manager
            .disconnect_simulator(&info)
            .await
            .expect("disconnect_simulator must be idempotent");
        assert!(!get_sim_filterwheel().read().await.status.connected);

        // Non-sim id surfaces an error.
        let bogus = build_sim_info("ascom:foo", DeviceType::FilterWheel);
        let err = manager
            .disconnect_simulator(&bogus)
            .await
            .expect_err("non-sim id must fail loudly");
        assert!(
            err.contains("not a simulator id"),
            "error message must call out the prefix mismatch: {}",
            err
        );
    }

    #[tokio::test]
    async fn heartbeat_reflects_simulator_singleton_state() {
        use crate::api::devices::simulation::get_sim_mount;

        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = build_device_manager();
        let device_id = "sim_mount_1";
        let info = build_sim_info(device_id, DeviceType::Mount);

        // Register and connect the simulator so the heartbeat target exists.
        manager.register_device(info.clone(), false).await;
        manager
            .connect_simulator(&info)
            .await
            .expect("connect_simulator should succeed");

        // Health check uses the private `perform_health_check`; exercise it
        // through `perform_simulator_health_check` directly via the public
        // surface that exists. Because `perform_health_check` is private to
        // the device_manager module we can call it from this in-module test.
        let healthy = manager
            .perform_health_check(device_id, &DeviceType::Mount, &DriverType::Simulator)
            .await
            .expect("simulator health check should not error for a valid sim mount");
        assert!(
            healthy,
            "heartbeat must report healthy while the mount singleton is connected"
        );

        // Flip the singleton state out-of-band — this mirrors what a future
        // user-triggered disconnect (or a forced state change) would do.
        get_sim_mount().write().await.status.connected = false;

        let unhealthy = manager
            .perform_health_check(device_id, &DeviceType::Mount, &DriverType::Simulator)
            .await
            .expect("simulator health check should not error when the singleton is disconnected");
        assert!(
            !unhealthy,
            "heartbeat must report unhealthy after the mount singleton is flipped to disconnected"
        );

        // Restoring the flag must restore healthy reporting.
        get_sim_mount().write().await.status.connected = true;
        let healthy_again = manager
            .perform_health_check(device_id, &DeviceType::Mount, &DriverType::Simulator)
            .await
            .expect("simulator health check should succeed after re-connect");
        assert!(
            healthy_again,
            "heartbeat must report healthy again once the mount singleton is reconnected"
        );

        // Cleanup so we leave the global singleton in a deterministic state
        // for any tests that run after us.
        get_sim_mount().write().await.status.connected = false;
    }

    // -------------------------------------------------------------------------
    // ND-INDI heartbeat must invoke the INDI client's own recovery path.
    //
    // The previous health check read `client.is_connected()` and returned
    // `Ok(false)` when the server connection had already dropped. That made
    // the bridge heartbeat mark the device unhealthy but never called the
    // INDI client's implemented `recover_reader` / reconnect machinery. This
    // test locks down the new contract: a disconnected INDI client must attempt
    // reader recovery, and if that recovery cannot reconnect it must surface a
    // real error instead of a passive "not healthy" result.
    // -------------------------------------------------------------------------
    #[tokio::test]
    async fn indi_health_check_attempts_reader_recovery_when_server_disconnected() {
        let manager = build_device_manager();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind ephemeral localhost port");
        let port = listener.local_addr().expect("read listener address").port();
        drop(listener);

        let device_id = format!("indi:127.0.0.1:{}:Test Mount", port);
        let info = build_mount_info(&device_id, DriverType::Indi);
        manager.register_device(info, false).await;

        let timeout_config = nightshade_indi::IndiTimeoutConfig {
            connection_timeout_secs: 1,
            ..Default::default()
        };
        let client = nightshade_indi::IndiClient::with_timeout_config(
            "127.0.0.1",
            Some(port),
            timeout_config,
        );

        manager
            .indi_clients
            .write()
            .await
            .insert(format!("127.0.0.1:{}", port), Arc::new(RwLock::new(client)));

        let err = manager
            .perform_health_check(&device_id, &DeviceType::Mount, &DriverType::Indi)
            .await
            .expect_err("disconnected INDI client must attempt recovery and surface failure");

        assert!(
            err.contains("reader recovery failed"),
            "INDI health check must call recover_reader instead of returning Ok(false): {}",
            err
        );
        assert!(
            err.contains("Failed to connect") || err.contains("timeout"),
            "recovery failure should include the underlying connect error: {}",
            err
        );
    }

    #[tokio::test]
    async fn indi_health_check_reissues_device_connect_after_server_recovery() {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};

        let manager = build_device_manager();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind fake INDI server");
        let port = listener.local_addr().expect("read listener address").port();
        let device_name = "Test Mount";
        let device_id = format!("indi:127.0.0.1:{}:{}", port, device_name);

        let (connect_seen_tx, connect_seen_rx) = tokio::sync::oneshot::channel::<String>();
        let server = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.expect("accept INDI client");
            let mut buf = vec![0_u8; 4096];

            let _ = socket
                .read(&mut buf)
                .await
                .expect("read initial getProperties");
            socket
                .write_all(
                    br#"
<defSwitchVector device="Test Mount" name="CONNECTION" state="Idle" perm="rw">
  <defSwitch name="CONNECT">Off</defSwitch>
  <defSwitch name="DISCONNECT">On</defSwitch>
</defSwitchVector>
<setSwitchVector device="Test Mount" name="CONNECTION" state="Ok">
  <oneSwitch name="CONNECT">Off</oneSwitch>
  <oneSwitch name="DISCONNECT">On</oneSwitch>
</setSwitchVector>
"#,
                )
                .await
                .expect("write disconnected device state");

            loop {
                buf.fill(0);
                let n = socket.read(&mut buf).await.expect("read reconnect command");
                if n == 0 {
                    break;
                }
                let command = String::from_utf8_lossy(&buf[..n]).to_string();
                if command.contains("<newSwitchVector")
                    && command.contains("name=\"CONNECTION\"")
                    && command.contains("name=\"CONNECT\">On")
                {
                    let _ = connect_seen_tx.send(command);
                    break;
                }
            }
        });

        let info = build_mount_info(&device_id, DriverType::Indi);
        manager.register_device(info, false).await;

        let timeout_config = nightshade_indi::IndiTimeoutConfig {
            connection_timeout_secs: 1,
            ..Default::default()
        };
        let mut client = nightshade_indi::IndiClient::with_timeout_config(
            "127.0.0.1",
            Some(port),
            timeout_config,
        );
        client.connect().await.expect("connect fake INDI client");

        let property_deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(2);
        while client
            .get_property(device_name, "CONNECTION")
            .await
            .is_none()
        {
            assert!(
                tokio::time::Instant::now() < property_deadline,
                "fake INDI CONNECTION property was not parsed in time"
            );
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
        assert!(
            !client.is_device_connected(device_name).await,
            "test setup expects the fake server to report the device disconnected"
        );

        manager
            .indi_clients
            .write()
            .await
            .insert(format!("127.0.0.1:{}", port), Arc::new(RwLock::new(client)));

        let healthy = manager
            .perform_health_check(&device_id, &DeviceType::Mount, &DriverType::Indi)
            .await
            .expect("INDI health check should send device reconnect command");
        assert!(
            !healthy,
            "health stays false until the INDI driver confirms CONNECT=On"
        );

        let command = tokio::time::timeout(std::time::Duration::from_secs(2), connect_seen_rx)
            .await
            .expect("fake INDI server should receive CONNECT command")
            .expect("server task should send observed command");
        assert!(
            command.contains("Test Mount"),
            "CONNECT command must target the managed INDI device: {}",
            command
        );

        server.await.expect("fake INDI server task should finish");
    }

    // -------------------------------------------------------------------------
    // DEV-P3-3 follow-up: ops/* simulator arms must consult the singleton
    // instead of returning hardcoded `Ok(value)` constants. These tests
    // exercise the connect → read → disconnect → read cycle for two
    // representative shapes (read-side + write-side) and one no-singleton
    // device type (switch).
    //
    // Note: the simulation.rs singletons are process-wide, so these tests
    // hold `simulator_singleton_test_lock` while they run and explicitly reset
    // singleton state before returning.
    // -------------------------------------------------------------------------

    #[tokio::test]
    async fn camera_ops_simulator_gates_on_singleton_connected() {
        use crate::api::devices::simulation::get_sim_camera;

        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = Arc::new(build_device_manager());
        let device_id = "sim_camera_ops_1";
        let info = build_sim_info(device_id, DeviceType::Camera);
        manager.register_device(info.clone(), false).await;

        // Pre-condition: singleton starts disconnected.
        get_sim_camera().write().await.status.connected = false;

        // Read before connect → loud error.
        let err = manager
            .camera_get_status(device_id)
            .await
            .expect_err("disconnected sim camera must surface an error");
        assert!(
            err.to_string().contains("not connected"),
            "error must call out missing connection: {}",
            err
        );

        // Connect flips the singleton; ops reads now succeed and reflect
        // the singleton's defaults.
        manager
            .connect_simulator(&info)
            .await
            .expect("connect_simulator should succeed");

        let status = manager
            .camera_get_status(device_id)
            .await
            .expect("connected sim camera status read must succeed");
        assert!(status.connected, "status must reflect connected singleton");
        let default_gain = status.gain;

        // Write-side: setting gain mutates the singleton (singleton-as-state)
        // and the next read returns the new value — no silent drop.
        manager
            .camera_set_gain(device_id, default_gain + 25)
            .await
            .expect("connected sim camera set_gain must succeed");
        let status_after = manager
            .camera_get_status(device_id)
            .await
            .expect("re-read connected sim camera status");
        assert_eq!(status_after.gain, default_gain + 25);

        // Disconnect flips the singleton back; reads and writes both fail loud.
        manager
            .disconnect_simulator(&info)
            .await
            .expect("disconnect_simulator should succeed");
        let err = manager
            .camera_get_status(device_id)
            .await
            .expect_err("disconnected sim camera must surface an error");
        assert!(err.to_string().contains("not connected"));
        let err = manager
            .camera_set_gain(device_id, 999)
            .await
            .expect_err("disconnected sim camera set_gain must surface an error");
        assert!(err.to_string().contains("not connected"));

        // Cleanup so any later tests using SIM_CAMERA see a clean slate.
        get_sim_camera().write().await.status.connected = false;
    }

    #[tokio::test]
    async fn focuser_ops_simulator_gates_on_singleton_connected() {
        use crate::api::devices::simulation::get_sim_focuser;

        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = Arc::new(build_device_manager());
        let device_id = "sim_focuser_ops_1";
        let info = build_sim_info(device_id, DeviceType::Focuser);
        manager.register_device(info.clone(), false).await;

        get_sim_focuser().write().await.status.connected = false;

        // Disconnected read fails loud.
        let err = manager
            .focuser_get_position(device_id)
            .await
            .expect_err("disconnected sim focuser must surface an error");
        assert!(err.to_string().contains("not connected"));

        // Connect, then read the singleton's default position.
        manager
            .connect_simulator(&info)
            .await
            .expect("connect_simulator should succeed");
        let default_pos = manager
            .focuser_get_position(device_id)
            .await
            .expect("connected sim focuser position read must succeed");

        // Move absolute mutates the singleton.
        manager
            .focuser_move_abs(device_id, default_pos + 100)
            .await
            .expect("connected sim focuser move_abs must succeed");
        let new_pos = manager
            .focuser_get_position(device_id)
            .await
            .expect("re-read connected sim focuser position");
        assert_eq!(new_pos, default_pos + 100);

        // Disconnect → write fails loud (no silent acceptance).
        manager
            .disconnect_simulator(&info)
            .await
            .expect("disconnect_simulator should succeed");
        let err = manager
            .focuser_move_abs(device_id, 12345)
            .await
            .expect_err("disconnected sim focuser move_abs must surface an error");
        assert!(err.to_string().contains("not connected"));

        get_sim_focuser().write().await.status.connected = false;
    }

    /// The simulated switch and cover calibrator obey the same connection gate
    /// as every other simulator: they answer once connected and refuse before.
    ///
    /// This replaces an assertion that both device types loud-errored
    /// unconditionally, which was true only because neither had a simulator at
    /// all — the reason the app logged "Discovery complete for Switch: 0
    /// devices" every launch and flat-panel flows could not be run without
    /// hardware. Answering while disconnected would be the opposite failure and
    /// is what the second half of this test pins down.
    #[tokio::test]
    async fn switch_and_cover_simulators_answer_only_while_connected() {
        let _guard = simulator_singleton_test_lock().lock().await;
        // The singletons are process-global; start from the power-on state so
        // an earlier test's open cover cannot masquerade as this one's.
        crate::api::devices::simulation::reset_sim_cover_calibrator().await;
        crate::api::devices::simulation::reset_sim_switch().await;
        let manager = Arc::new(build_device_manager());

        let switch_info = build_sim_info("sim_switch_1", DeviceType::Switch);
        let cover_info = build_sim_info("sim_cover_calibrator_1", DeviceType::CoverCalibrator);
        manager.register_device(switch_info.clone(), false).await;
        manager.register_device(cover_info.clone(), false).await;

        for info in [&switch_info, &cover_info] {
            manager
                .disconnect_simulator(info)
                .await
                .expect("disconnect_simulator should succeed for a supported sim type");
        }

        for err in [
            manager
                .switch_get_max("sim_switch_1")
                .await
                .expect_err("a disconnected sim switch must not report a channel count")
                .to_string(),
            manager
                .cover_calibrator_get_cover_state("sim_cover_calibrator_1")
                .await
                .expect_err("a disconnected sim panel must not report a cover state")
                .to_string(),
        ] {
            assert!(
                err.contains("not connected"),
                "the refusal must name the disconnection: {err}"
            );
        }

        for info in [&switch_info, &cover_info] {
            manager
                .connect_simulator(info)
                .await
                .expect("connect_simulator should succeed for a supported sim type");
        }

        assert!(
            manager
                .switch_get_max("sim_switch_1")
                .await
                .expect("a connected sim switch reports its channels")
                > 0
        );
        assert_eq!(
            manager
                .cover_calibrator_get_cover_state("sim_cover_calibrator_1")
                .await
                .expect("a connected sim panel reports its cover state"),
            CoverState::Closed.to_i32(),
            "a freshly connected flat panel must report its cover closed"
        );

        for info in [&switch_info, &cover_info] {
            manager
                .disconnect_simulator(info)
                .await
                .expect("disconnect_simulator should succeed");
        }
    }

    // -------------------------------------------------------------------------
    // Hot-plug reconnect: re-apply essential device state.
    //
    // After an *unplanned* reconnect (the device's connection_state was Error,
    // i.e. heartbeat-lost / report_error), `connect_device_internal` must
    // re-apply the last commanded camera cooling setpoint and mount tracking
    // state — the driver comes back in power-on defaults and would otherwise
    // silently warm the sensor / leave the mount parked while the sequence
    // "resumes". A *fresh* connect (from Disconnected) must NOT re-apply.
    // -------------------------------------------------------------------------

    /// Setting tracking records `desired_tracking`; an Error->reconnect replays it.
    #[tokio::test]
    async fn reconnect_reapplies_mount_tracking() {
        use crate::api::devices::simulation::get_sim_mount;

        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = Arc::new(build_device_manager());
        let device_id = "sim_mount_reapply";
        let info = build_sim_info(device_id, DeviceType::Mount);
        manager.register_device(info.clone(), false).await;
        manager
            .connect_device(device_id)
            .await
            .expect("initial connect should succeed");

        // Operator/sequencer commands tracking on; this records desired state.
        manager
            .mount_set_tracking(device_id, true)
            .await
            .expect("set_tracking should succeed on connected sim mount");
        assert_eq!(
            manager
                .devices
                .read()
                .await
                .get(device_id)
                .unwrap()
                .desired_tracking,
            Some(true),
            "successful set_tracking must record desired_tracking"
        );

        // Simulate a heartbeat-lost disconnect: device goes to Error and the
        // driver loses tracking (sim singleton flipped off).
        manager
            .handle_heartbeat_lost(device_id, true, 5, "simulated yank")
            .await;
        get_sim_mount().write().await.status.tracking = false;
        assert_eq!(
            manager
                .devices
                .read()
                .await
                .get(device_id)
                .unwrap()
                .connection_state,
            ConnectionState::Error
        );

        // Reconnect via the public path (routes through connect_device_internal).
        manager
            .connect_device(device_id)
            .await
            .expect("reconnect should succeed");

        // Essential state must have been replayed onto the driver.
        assert!(
            get_sim_mount().read().await.status.tracking,
            "reconnect must re-apply mount tracking that was active before the disconnect"
        );

        get_sim_mount().write().await.status.tracking = false;
        get_sim_mount().write().await.status.connected = false;
    }

    /// Setting the cooler records `desired_cooler`; an Error->reconnect replays it.
    #[tokio::test]
    async fn reconnect_reapplies_camera_cooler() {
        use crate::api::devices::simulation::get_sim_camera;

        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = Arc::new(build_device_manager());
        let device_id = "sim_camera_reapply";
        let info = build_sim_info(device_id, DeviceType::Camera);
        manager.register_device(info.clone(), false).await;
        manager
            .connect_device(device_id)
            .await
            .expect("initial connect should succeed");

        manager
            .camera_set_cooler(device_id, true, Some(-12.0))
            .await
            .expect("set_cooler should succeed on connected sim camera");
        assert_eq!(
            manager
                .devices
                .read()
                .await
                .get(device_id)
                .unwrap()
                .desired_cooler,
            Some((true, Some(-12.0))),
            "successful set_cooler must record desired_cooler"
        );

        // Heartbeat-lost: Error state + driver loses cooler (sim defaults).
        manager
            .handle_heartbeat_lost(device_id, true, 3, "simulated yank")
            .await;
        {
            let mut cam = get_sim_camera().write().await;
            cam.status.cooler_on = false;
            cam.status.target_temp = None;
        }

        manager
            .connect_device(device_id)
            .await
            .expect("reconnect should succeed");

        {
            let cam = get_sim_camera().read().await;
            assert!(cam.status.cooler_on, "reconnect must re-enable the cooler");
            assert_eq!(
                cam.status.target_temp,
                Some(-12.0),
                "reconnect must restore the cooling setpoint"
            );
        }

        let mut cam = get_sim_camera().write().await;
        cam.status.connected = false;
    }

    /// A *fresh* connect (state was Disconnected, not Error) must NOT replay any
    /// recorded desired state — only an unplanned reconnect re-applies.
    #[tokio::test]
    async fn fresh_connect_does_not_reapply_state() {
        use crate::api::devices::simulation::get_sim_mount;

        let _guard = simulator_singleton_test_lock().lock().await;
        let manager = Arc::new(build_device_manager());
        let device_id = "sim_mount_fresh";
        let info = build_sim_info(device_id, DeviceType::Mount);
        manager.register_device(info.clone(), false).await;
        manager
            .connect_device(device_id)
            .await
            .expect("initial connect should succeed");
        manager
            .mount_set_tracking(device_id, true)
            .await
            .expect("set_tracking should succeed");

        // A clean disconnect (NOT an error): state goes to Disconnected.
        manager
            .disconnect_device(device_id)
            .await
            .expect("disconnect should succeed");
        assert_ne!(
            manager
                .devices
                .read()
                .await
                .get(device_id)
                .unwrap()
                .connection_state,
            ConnectionState::Error,
            "a clean disconnect must not leave the device in Error"
        );
        get_sim_mount().write().await.status.tracking = false;

        // Fresh connect from Disconnected — must NOT auto-resume tracking.
        manager
            .connect_device(device_id)
            .await
            .expect("fresh connect should succeed");
        assert!(
            !get_sim_mount().read().await.status.tracking,
            "a fresh connect must not silently re-apply tracking the user did not re-request"
        );

        get_sim_mount().write().await.status.connected = false;
    }

    // =========================================================================
    // Cooler setpoint: what actually reaches the driver
    // =========================================================================

    /// A native camera that records every `set_cooler` argument it is handed.
    ///
    /// The point of the recording is the second element: whether a setpoint
    /// reached the driver at all. Nightshade used to substitute -10 C for a
    /// `None` target, so a "switch the cooler off" command arrived at the
    /// hardware carrying a temperature nobody asked for.
    #[derive(Debug, Clone, Default)]
    struct RecordingCoolerCamera {
        calls: Arc<std::sync::Mutex<Vec<(bool, Option<f64>)>>>,
    }

    #[async_trait::async_trait]
    impl nightshade_native::traits::NativeDevice for RecordingCoolerCamera {
        fn id(&self) -> &str {
            "native:test:cooler"
        }
        fn name(&self) -> &str {
            "Recording Cooler Camera"
        }
        fn vendor(&self) -> nightshade_native::NativeVendor {
            nightshade_native::NativeVendor::Other("Test".to_string())
        }
        fn is_connected(&self) -> bool {
            true
        }
        async fn connect(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
        async fn disconnect(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
    }

    #[async_trait::async_trait]
    impl nightshade_native::traits::NativeCamera for RecordingCoolerCamera {
        fn capabilities(&self) -> nightshade_native::camera::CameraCapabilities {
            nightshade_native::camera::CameraCapabilities {
                can_cool: true,
                ..Default::default()
            }
        }
        async fn get_status(
            &self,
        ) -> Result<nightshade_native::camera::CameraStatus, nightshade_native::traits::NativeError>
        {
            Ok(nightshade_native::camera::CameraStatus {
                state: nightshade_native::camera::CameraState::Idle,
                sensor_temp: Some(-10.0),
                cooler_power: Some(0.0),
                target_temp: Some(-10.0),
                cooler_on: false,
                gain: 0,
                offset: 0,
                bin_x: 1,
                bin_y: 1,
                exposure_remaining: None,
            })
        }
        async fn start_exposure(
            &mut self,
            _params: nightshade_native::camera::ExposureParams,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
        async fn abort_exposure(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
        async fn is_exposure_complete(
            &self,
        ) -> Result<bool, nightshade_native::traits::NativeError> {
            Ok(true)
        }
        async fn download_image(
            &mut self,
        ) -> Result<nightshade_native::camera::ImageData, nightshade_native::traits::NativeError>
        {
            Err(nightshade_native::traits::NativeError::NotSupported)
        }
        async fn set_cooler(
            &mut self,
            enabled: bool,
            target_temp: Option<f64>,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            self.calls
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .push((enabled, target_temp));
            Ok(())
        }
        async fn get_temperature(&self) -> Result<f64, nightshade_native::traits::NativeError> {
            Ok(-10.0)
        }
        async fn get_cooler_power(&self) -> Result<f64, nightshade_native::traits::NativeError> {
            Ok(0.0)
        }
        async fn set_gain(
            &mut self,
            _gain: i32,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
        async fn get_gain(&self) -> Result<i32, nightshade_native::traits::NativeError> {
            Ok(0)
        }
        async fn set_offset(
            &mut self,
            _offset: i32,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
        async fn get_offset(&self) -> Result<i32, nightshade_native::traits::NativeError> {
            Ok(0)
        }
        async fn set_binning(
            &mut self,
            _bin_x: i32,
            _bin_y: i32,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
        async fn get_binning(&self) -> Result<(i32, i32), nightshade_native::traits::NativeError> {
            Ok((1, 1))
        }
        async fn set_subframe(
            &mut self,
            _subframe: Option<nightshade_native::camera::SubFrame>,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
        fn get_sensor_info(&self) -> nightshade_native::camera::SensorInfo {
            nightshade_native::camera::SensorInfo {
                width: 4656,
                height: 3520,
                pixel_size_x: 3.8,
                pixel_size_y: 3.8,
                max_adu: 65535,
                bit_depth: 16,
                color: false,
                bayer_pattern: None,
            }
        }
        async fn get_readout_modes(
            &self,
        ) -> Result<
            Vec<nightshade_native::camera::ReadoutMode>,
            nightshade_native::traits::NativeError,
        > {
            Ok(Vec::new())
        }
        async fn set_readout_mode(
            &mut self,
            _mode: &nightshade_native::camera::ReadoutMode,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
        async fn get_vendor_features(
            &self,
        ) -> Result<nightshade_native::camera::VendorFeatures, nightshade_native::traits::NativeError>
        {
            Ok(nightshade_native::camera::VendorFeatures::default())
        }
        async fn get_gain_range(
            &self,
        ) -> Result<(i32, i32), nightshade_native::traits::NativeError> {
            Ok((0, 600))
        }
        async fn get_offset_range(
            &self,
        ) -> Result<(i32, i32), nightshade_native::traits::NativeError> {
            Ok((0, 255))
        }
    }

    fn build_native_camera_info(id: &str) -> DeviceInfo {
        DeviceInfo {
            id: id.to_string(),
            name: "Recording Cooler Camera".to_string(),
            device_type: DeviceType::Camera,
            driver_type: DriverType::Native,
            description: "Native camera under test".to_string(),
            driver_version: "1.0".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: "Recording Cooler Camera".to_string(),
        }
    }

    /// L19, reproduced on the reference rig on 2026-08-09: `POST
    /// /api/camera/cooling {"enabled":false}` carries no setpoint, and the
    /// device layer used to substitute -10 C (`target_temp.unwrap_or(-10.0)`)
    /// before handing the command to the driver. On the rig that fabricated
    /// write is what threw — `SetCCDTemperature` on a camera reporting
    /// `CanSetCCDTemperature = False` — so the cooler could not be turned off
    /// at all, which is exactly what end-of-night warm-up and the safe-rig
    /// shutdown both do.
    #[tokio::test]
    async fn turning_the_cooler_off_sends_no_setpoint_to_the_driver() {
        let manager = Arc::new(build_device_manager());
        let device_id = "native:test:cooler_off";
        manager
            .register_device(build_native_camera_info(device_id), false)
            .await;

        let camera = RecordingCoolerCamera::default();
        let calls = camera.calls.clone();
        manager
            .native_cameras
            .write()
            .await
            .insert(device_id.to_string(), Box::new(camera));

        // The exact request the warm-up controller and safe_rig both issue.
        manager
            .camera_set_cooler(device_id, false, None)
            .await
            .expect("turning a cooler off must not fail");

        let recorded = calls.lock().unwrap_or_else(|e| e.into_inner()).clone();
        assert_eq!(
            recorded,
            vec![(false, None)],
            "a cooler-off command must reach the driver with no setpoint; \
             a fabricated default here is what failed on the rig"
        );
    }

    /// Even a caller that does name a temperature while switching off must not
    /// cause a setpoint write: the driver is being told to stop, and on ASCOM
    /// the write is a separate property that may not exist.
    #[tokio::test]
    async fn a_setpoint_supplied_with_a_cooler_off_command_is_dropped() {
        let manager = Arc::new(build_device_manager());
        let device_id = "native:test:cooler_off_with_target";
        manager
            .register_device(build_native_camera_info(device_id), false)
            .await;

        let camera = RecordingCoolerCamera::default();
        let calls = camera.calls.clone();
        manager
            .native_cameras
            .write()
            .await
            .insert(device_id.to_string(), Box::new(camera));

        // The sequencer's WarmCamera instruction ends with exactly this shape:
        // `camera_set_cooler(id, false, 20.0)`.
        manager
            .camera_set_cooler(device_id, false, Some(20.0))
            .await
            .expect("turning a cooler off must not fail");

        let recorded = calls.lock().unwrap_or_else(|e| e.into_inner()).clone();
        assert_eq!(recorded, vec![(false, None)]);

        // …and the recorded desired state (replayed after a USB reconnect)
        // must not resurrect a setpoint the operator never asked for.
        assert_eq!(
            manager
                .devices
                .read()
                .await
                .get(device_id)
                .unwrap()
                .desired_cooler,
            Some((false, None))
        );
    }

    /// The enable direction is unchanged: the caller's setpoint is passed
    /// through verbatim, and an absent one is still not invented.
    #[tokio::test]
    async fn enabling_passes_the_callers_setpoint_through_unchanged() {
        let manager = Arc::new(build_device_manager());
        let device_id = "native:test:cooler_on";
        manager
            .register_device(build_native_camera_info(device_id), false)
            .await;

        let camera = RecordingCoolerCamera::default();
        let calls = camera.calls.clone();
        manager
            .native_cameras
            .write()
            .await
            .insert(device_id.to_string(), Box::new(camera));

        manager
            .camera_set_cooler(device_id, true, Some(-15.0))
            .await
            .expect("enabling the cooler should succeed");
        manager
            .camera_set_cooler(device_id, true, None)
            .await
            .expect("enabling without a setpoint should succeed");

        let recorded = calls.lock().unwrap_or_else(|e| e.into_inner()).clone();
        assert_eq!(
            recorded,
            vec![(true, Some(-15.0)), (true, None)],
            "no -10C (or any other) default may be substituted for an absent setpoint"
        );
    }
}
