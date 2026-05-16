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
pub(crate) mod heartbeat;
pub(crate) mod ops;

use crate::device::*;
use crate::state::SharedAppState;
use nightshade_native::traits::{
    NativeCamera, NativeDevice, NativeDome, NativeFilterWheel, NativeFocuser, NativeMount,
    NativeRotator, NativeSafetyMonitor, NativeWeather,
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
}

impl Default for HeartbeatConfig {
    fn default() -> Self {
        Self {
            base_interval_secs: 10,
            max_interval_secs: 60,
            failure_threshold: 3,
            backoff_multiplier: 2.0,
            auto_reconnect: false,
            max_reconnect_attempts: 3,
            reconnect_delay_secs: 5,
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
        }
    }

    /// Create config optimized for focusers (relatively stable)
    pub fn for_focuser() -> Self {
        Self {
            base_interval_secs: 15,
            max_interval_secs: 60,
            failure_threshold: 3,
            backoff_multiplier: 2.0,
            auto_reconnect: false,
            max_reconnect_attempts: 2,
            reconnect_delay_secs: 5,
        }
    }

    /// Create config optimized for filter wheels (rarely polled)
    pub fn for_filter_wheel() -> Self {
        Self {
            base_interval_secs: 20,
            max_interval_secs: 120,
            failure_threshold: 3,
            backoff_multiplier: 2.0,
            auto_reconnect: false,
            max_reconnect_attempts: 2,
            reconnect_delay_secs: 5,
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
        }
    }

    /// Create config optimized for rotators
    pub fn for_rotator() -> Self {
        Self {
            base_interval_secs: 15,
            max_interval_secs: 60,
            failure_threshold: 3,
            backoff_multiplier: 2.0,
            auto_reconnect: false,
            max_reconnect_attempts: 2,
            reconnect_delay_secs: 5,
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
        }
    }

    /// Create config optimized for safety monitors (critical - need responsive monitoring)
    pub fn for_safety_monitor() -> Self {
        Self {
            base_interval_secs: 5,
            max_interval_secs: 15,
            failure_threshold: 2, // Quick failure detection for safety
            backoff_multiplier: 1.2,
            auto_reconnect: true, // Safety monitors should always auto-reconnect
            max_reconnect_attempts: 0, // Unlimited reconnect attempts
            reconnect_delay_secs: 2,
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
            _ => Self::default(),
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
}

/// The Device Manager handles all device connections
pub struct DeviceManager {
    /// Application state for publishing events
    app_state: SharedAppState,

    /// Managed devices by their ID
    pub(crate) devices: RwLock<HashMap<String, ManagedDevice>>,

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
        RwLock<HashMap<String, Arc<RwLock<crate::ascom_wrapper::AscomCameraWrapper>>>>,

    /// Active ASCOM mount wrappers
    #[cfg(windows)]
    pub(crate) ascom_mounts:
        RwLock<HashMap<String, Arc<RwLock<crate::ascom_wrapper_mount::AscomMountWrapper>>>>,

    /// Active ASCOM focuser wrappers
    #[cfg(windows)]
    pub(crate) ascom_focusers:
        RwLock<HashMap<String, Arc<RwLock<crate::ascom_wrapper_focuser::AscomFocuserWrapper>>>>,

    /// Active ASCOM filter wheel wrappers
    #[cfg(windows)]
    pub(crate) ascom_filter_wheels: RwLock<
        HashMap<String, Arc<RwLock<crate::ascom_wrapper_filterwheel::AscomFilterWheelWrapper>>>,
    >,

    /// Active ASCOM rotator wrappers
    #[cfg(windows)]
    pub(crate) ascom_rotators:
        RwLock<HashMap<String, Arc<RwLock<crate::ascom_wrapper_rotator::AscomRotatorWrapper>>>>,

    /// Active ASCOM dome wrappers
    #[cfg(windows)]
    pub(crate) ascom_domes:
        RwLock<HashMap<String, Arc<RwLock<crate::ascom_wrapper_dome::AscomDomeWrapper>>>>,

    /// Active ASCOM weather wrappers
    #[cfg(windows)]
    pub(crate) ascom_weather: RwLock<
        HashMap<String, Arc<RwLock<crate::ascom_wrapper_weather::AscomObservingConditionsWrapper>>>,
    >,

    /// Active ASCOM safety monitor wrappers
    #[cfg(windows)]
    pub(crate) ascom_safety_monitors: RwLock<
        HashMap<String, Arc<RwLock<crate::ascom_wrapper_safetymonitor::AscomSafetyMonitorWrapper>>>,
    >,

    /// Active ASCOM switch wrappers
    #[cfg(windows)]
    pub(crate) ascom_switches:
        RwLock<HashMap<String, Arc<RwLock<crate::ascom_wrapper_switch::AscomSwitchWrapper>>>>,

    /// Active ASCOM cover calibrator wrappers
    #[cfg(windows)]
    pub(crate) ascom_cover_calibrators: RwLock<
        HashMap<
            String,
            Arc<RwLock<crate::ascom_wrapper_covercalibrator::AscomCoverCalibratorWrapper>>,
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

    /// Active heartbeat monitoring tasks (device_id -> join handle)
    heartbeat_tasks: RwLock<HashMap<String, tokio::task::JoinHandle<()>>>,
}

impl DeviceManager {
    /// Create a new device manager
    pub fn new(app_state: SharedAppState) -> Arc<Self> {
        let manager = Arc::new(Self {
            app_state,
            devices: RwLock::new(HashMap::new()),
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
            heartbeat_tasks: RwLock::new(HashMap::new()),
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
            heartbeat_tasks: RwLock::new(HashMap::new()),
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
    /// # `unwrap_or` policy (audit-rust §4.3)
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
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(windows)]
    use crate::ascom_wrapper_mount::test_support::{build_test_mount_wrapper, TestMountResponses};
    use crate::state::AppState;
    use std::collections::HashMap;
    use std::sync::Arc;
    use tokio::sync::RwLock;

    #[test]
    fn test_heartbeat_config_default() {
        let config = HeartbeatConfig::default();
        assert_eq!(config.base_interval_secs, 10);
        assert_eq!(config.max_interval_secs, 60);
        assert_eq!(config.failure_threshold, 3);
        assert!((config.backoff_multiplier - 2.0).abs() < f64::EPSILON);
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
        // Safety monitors need quick failure detection
        assert_eq!(config.base_interval_secs, 5);
        assert_eq!(config.failure_threshold, 2);
        // Safety monitors should always auto-reconnect
        assert!(config.auto_reconnect);
        // Unlimited reconnect attempts for safety
        assert_eq!(config.max_reconnect_attempts, 0);
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
        assert_eq!(safety_config.max_reconnect_attempts, 0);
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
            heartbeat_tasks: RwLock::new(HashMap::new()),
        }
    }

    #[tokio::test]
    async fn test_mount_can_park_requires_registered_device() {
        let manager = build_device_manager();
        let err = manager
            .mount_can_park("missing-mount")
            .await
            .expect_err("missing mount should error");
        assert!(err.contains("Device not found"));
    }

    #[tokio::test]
    async fn test_mount_stop_requires_registered_device() {
        let manager = build_device_manager();
        let err = manager
            .mount_stop("missing-mount")
            .await
            .expect_err("missing mount should error");
        assert!(err.contains("Device not found"));
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
        assert!(err.contains("Device not found"));

        let err = manager.switch_get_state(device_id, 0).await.unwrap_err();
        assert!(err.contains("Device not found"));

        let err = manager
            .switch_set_state(device_id, 0, true)
            .await
            .unwrap_err();
        assert!(err.contains("Device not found"));

        let err = manager.switch_get_name(device_id, 0).await.unwrap_err();
        assert!(err.contains("Device not found"));

        let err = manager
            .switch_get_description(device_id, 0)
            .await
            .unwrap_err();
        assert!(err.contains("Device not found"));

        let err = manager.switch_get_value(device_id, 0).await.unwrap_err();
        assert!(err.contains("Device not found"));

        let err = manager
            .switch_set_value(device_id, 0, 1.0)
            .await
            .unwrap_err();
        assert!(err.contains("Device not found"));

        let err = manager
            .switch_get_min_value(device_id, 0)
            .await
            .unwrap_err();
        assert!(err.contains("Device not found"));

        let err = manager
            .switch_get_max_value(device_id, 0)
            .await
            .unwrap_err();
        assert!(err.contains("Device not found"));

        let err = manager.switch_can_write(device_id, 0).await.unwrap_err();
        assert!(err.contains("Device not found"));
    }

    #[tokio::test]
    async fn test_switch_get_max_reports_missing_alpaca_device() {
        let manager = build_device_manager();
        let device_id = "alpaca:test-switch";
        let info = build_switch_info(device_id, DriverType::Alpaca);
        manager.register_device(info, false).await;

        let err = manager.switch_get_max(device_id).await.unwrap_err();
        assert!(err.contains("Alpaca switch"));
    }
}
