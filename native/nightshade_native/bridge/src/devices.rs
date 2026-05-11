//! Device Manager with connection state management and auto-reconnection
//!
//! Provides a unified interface for managing device connections across
//! different driver backends (ASCOM, Alpaca, Simulator).

use crate::device::*;
use crate::event::*;
use crate::state::SharedAppState;
use nightshade_native::camera::{ExposureParams, ImageData};
use nightshade_native::traits::{
    NativeCamera, NativeDevice, NativeDome, NativeFilterWheel, NativeFocuser, NativeMount,
    NativeRotator, NativeSafetyMonitor, NativeWeather,
};
// Vendor SDK imports moved to crate::dispatch::native (the only consumer of
// the camera/mount/filter wheel/focuser constructors).
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tokio::time::interval;
use tracing::warn;

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

    /// Background task for automatic reconnection
    async fn reconnection_loop(&self) {
        let mut check_interval = interval(Duration::from_secs(5));

        loop {
            check_interval.tick().await;

            // Check if we should stop
            if *self.stop_reconnect.read().await {
                break;
            }

            if !self.reconnect_config.enabled {
                continue;
            }

            // Find devices that need reconnection
            let devices_to_reconnect: Vec<(String, ManagedDevice)> = {
                let devices = self.devices.read().await;
                devices
                    .iter()
                    .filter(|(_, dev)| {
                        dev.auto_reconnect
                            && dev.connection_state == ConnectionState::Error
                            && (self.reconnect_config.max_attempts == 0
                                || dev.reconnect_attempts < self.reconnect_config.max_attempts)
                    })
                    .map(|(id, dev)| (id.clone(), dev.clone()))
                    .collect()
            };

            // Attempt reconnection for each device
            for (device_id, device) in devices_to_reconnect {
                tracing::info!(
                    "Attempting reconnection for {} (attempt {})",
                    device_id,
                    device.reconnect_attempts + 1
                );

                // Calculate backoff delay
                let delay = self.calculate_backoff_delay(device.reconnect_attempts);
                tokio::time::sleep(Duration::from_secs(delay)).await;

                // Attempt reconnection
                if let Err(e) = self.connect_device_internal(&device.info).await {
                    tracing::warn!("Reconnection failed for {}: {}", device_id, e);

                    // Update attempt counter
                    let mut devices = self.devices.write().await;
                    if let Some(dev) = devices.get_mut(&device_id) {
                        dev.reconnect_attempts += 1;
                        dev.last_error = Some(e.clone());

                        // Publish reconnection failed event
                        self.app_state.publish_equipment_event(
                            EquipmentEvent::Error {
                                device_type: dev.info.device_type.as_str().to_string(),
                                device_id: device_id.clone(),
                                message: format!(
                                    "Reconnection attempt {} failed: {}",
                                    dev.reconnect_attempts, e
                                ),
                            },
                            EventSeverity::Warning,
                        );
                    }
                } else {
                    tracing::info!("Reconnection successful for {}", device_id);

                    // Reset attempt counter on success
                    let mut devices = self.devices.write().await;
                    if let Some(dev) = devices.get_mut(&device_id) {
                        dev.reconnect_attempts = 0;
                        dev.last_error = None;
                    }
                }
            }
        }
    }

    /// Calculate backoff delay for reconnection
    fn calculate_backoff_delay(&self, attempts: u32) -> u64 {
        let delay = (self.reconnect_config.initial_delay_secs as f64)
            * self
                .reconnect_config
                .backoff_multiplier
                .powi(attempts as i32);

        (delay as u64).min(self.reconnect_config.max_delay_secs)
    }

    /// Register a device for management
    pub async fn register_device(&self, info: DeviceInfo, auto_reconnect: bool) {
        let mut devices = self.devices.write().await;
        devices.insert(
            info.id.clone(),
            ManagedDevice {
                info,
                connection_state: ConnectionState::Disconnected,
                last_error: None,
                reconnect_attempts: 0,
                auto_reconnect,
                last_successful_comm: None,
                heartbeat_active: false,
                api_version: None,
            },
        );
    }

    /// Check if a device is registered
    pub async fn is_device_registered(&self, device_id: &str) -> bool {
        let devices = self.devices.read().await;
        devices.contains_key(device_id)
    }

    /// Get the display name for a registered device, if it exists.
    pub async fn get_device_display_name(&self, device_id: &str) -> Option<String> {
        let devices = self.devices.read().await;
        devices.get(device_id).map(|d| d.info.display_name.clone())
    }

    /// Connect to a device
    pub async fn connect_device(&self, device_id: &str) -> Result<(), String> {
        let device_info = {
            let devices = self.devices.read().await;
            devices
                .get(device_id)
                .map(|d| d.info.clone())
                .ok_or_else(|| format!("Device not found: {}", device_id))?
        };

        self.connect_device_internal(&device_info).await
    }

    /// Internal connection logic
    async fn connect_device_internal(&self, info: &DeviceInfo) -> Result<(), String> {
        let device_id = &info.id;

        // Update state to connecting
        {
            let mut devices = self.devices.write().await;
            if let Some(dev) = devices.get_mut(device_id) {
                dev.connection_state = ConnectionState::Connecting;
            }
        }

        // Publish connecting event
        self.app_state.publish_equipment_event(
            EquipmentEvent::Connecting {
                device_type: info.device_type.as_str().to_string(),
                device_id: device_id.clone(),
            },
            EventSeverity::Info,
        );

        // Perform actual connection based on driver type
        let result = match info.driver_type {
            DriverType::Simulator => self.connect_simulator(info).await,
            DriverType::Ascom => self.connect_ascom(info).await,
            DriverType::Alpaca => self.connect_alpaca(info).await,
            DriverType::Indi => self.connect_indi(info).await,
            DriverType::Native => self.connect_native(info).await,
        };

        // Update state based on result
        {
            let mut devices = self.devices.write().await;
            if let Some(dev) = devices.get_mut(device_id) {
                match &result {
                    Ok(_) => {
                        dev.connection_state = ConnectionState::Connected;
                        dev.last_error = None;
                        dev.reconnect_attempts = 0;
                    }
                    Err(e) => {
                        dev.connection_state = ConnectionState::Error;
                        dev.last_error = Some(e.clone());
                    }
                }
            }
        }

        // Publish result event
        match &result {
            Ok(_) => {
                self.app_state.publish_equipment_event(
                    EquipmentEvent::Connected {
                        device_type: info.device_type.as_str().to_string(),
                        device_id: device_id.clone(),
                    },
                    EventSeverity::Info,
                );

                // Also register in app state
                self.app_state
                    .register_device(info.clone(), ConnectionState::Connected)
                    .await;

                // Auto-start heartbeat monitoring for the connected device
                let heartbeat_config = Self::get_heartbeat_config(&info.device_type);
                if let Err(e) = self
                    .start_heartbeat_with_config(device_id, heartbeat_config)
                    .await
                {
                    tracing::warn!("Failed to start heartbeat for {}: {}", device_id, e);
                } else {
                    tracing::info!("Auto-started heartbeat for device {}", device_id);
                }
            }
            Err(e) => {
                self.app_state.publish_equipment_event(
                    EquipmentEvent::Error {
                        device_type: info.device_type.as_str().to_string(),
                        device_id: device_id.clone(),
                        message: e.clone(),
                    },
                    EventSeverity::Error,
                );
            }
        }

        result
    }

    /// Connect to a simulator device - DISABLED
    async fn connect_simulator(&self, _info: &DeviceInfo) -> Result<(), String> {
        Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
    }

    // connect_ascom / connect_alpaca / connect_indi / connect_native were
    // moved to `crate::dispatch::{ascom,alpaca,indi,native}` (split-impl-block).
    // The dispatcher above continues to call `self.connect_*` unchanged.

    /// Disconnect a device
    pub async fn disconnect_device(&self, device_id: &str) -> Result<(), String> {
        // Stop heartbeat monitoring first to prevent false disconnect events
        let _ = self.stop_heartbeat(device_id).await;

        let device_info = {
            let devices = self.devices.read().await;
            devices
                .get(device_id)
                .map(|d| d.info.clone())
                .ok_or_else(|| format!("Device not found: {}", device_id))?
        };

        // Update state
        {
            let mut devices = self.devices.write().await;
            if let Some(dev) = devices.get_mut(device_id) {
                dev.connection_state = ConnectionState::Disconnected;
                dev.auto_reconnect = false; // Disable auto-reconnect on manual disconnect
            }
        }

        // Clean up device from driver-specific storage based on driver type and device type
        if device_info.id == crate::builtin_guider::device_id() {
            let _ = crate::builtin_guider::disconnect().await;
        }
        match device_info.driver_type {
            DriverType::Native => {
                // Remove from generic native_devices map
                let mut native_devices = self.native_devices.write().await;
                if let Some(mut device) = native_devices.remove(device_id) {
                    let _ = device.disconnect().await;
                }

                // Also remove from typed native storage maps
                match device_info.device_type {
                    DeviceType::Camera => {
                        let mut cameras = self.native_cameras.write().await;
                        if let Some(mut camera) = cameras.remove(device_id) {
                            let _ = camera.disconnect().await;
                        }
                    }
                    DeviceType::Mount => {
                        let mut mounts = self.native_mounts.write().await;
                        if let Some(mut mount) = mounts.remove(device_id) {
                            let _ = mount.disconnect().await;
                        }
                    }
                    DeviceType::Focuser => {
                        let mut focusers = self.native_focusers.write().await;
                        if let Some(mut focuser) = focusers.remove(device_id) {
                            let _ = focuser.disconnect().await;
                        }
                    }
                    DeviceType::FilterWheel => {
                        let mut fws = self.native_filter_wheels.write().await;
                        if let Some(mut fw) = fws.remove(device_id) {
                            let _ = fw.disconnect().await;
                        }
                    }
                    DeviceType::Rotator => {
                        let mut rotators = self.native_rotators.write().await;
                        if let Some(mut rotator) = rotators.remove(device_id) {
                            let _ = rotator.disconnect().await;
                        }
                    }
                    DeviceType::Dome => {
                        let mut domes = self.native_domes.write().await;
                        if let Some(mut dome) = domes.remove(device_id) {
                            let _ = dome.disconnect().await;
                        }
                    }
                    DeviceType::Weather => {
                        let mut weather = self.native_weather.write().await;
                        if let Some(mut w) = weather.remove(device_id) {
                            let _ = w.disconnect().await;
                        }
                    }
                    DeviceType::SafetyMonitor => {
                        let mut safety = self.native_safety_monitors.write().await;
                        if let Some(mut s) = safety.remove(device_id) {
                            let _ = s.disconnect().await;
                        }
                    }
                    _ => {} // Guider, Switch, CoverCalibrator - no typed native storage
                }
            }
            DriverType::Alpaca => {
                // Remove from Alpaca storage based on device type
                match device_info.device_type {
                    DeviceType::Camera => {
                        let mut cameras = self.alpaca_cameras.write().await;
                        if let Some(camera) = cameras.remove(device_id) {
                            let _ = camera.disconnect().await;
                        }
                    }
                    DeviceType::Mount => {
                        let mut mounts = self.alpaca_mounts.write().await;
                        if let Some(mount) = mounts.remove(device_id) {
                            let _ = mount.disconnect().await;
                        }
                    }
                    DeviceType::Focuser => {
                        let mut focusers = self.alpaca_focusers.write().await;
                        if let Some(focuser) = focusers.remove(device_id) {
                            let _ = focuser.disconnect().await;
                        }
                    }
                    DeviceType::FilterWheel => {
                        let mut fws = self.alpaca_filter_wheels.write().await;
                        if let Some(fw) = fws.remove(device_id) {
                            let _ = fw.disconnect().await;
                        }
                    }
                    DeviceType::Rotator => {
                        let mut rotators = self.alpaca_rotators.write().await;
                        if let Some(rotator) = rotators.remove(device_id) {
                            let _ = rotator.disconnect().await;
                        }
                    }
                    DeviceType::Dome => {
                        let mut domes = self.alpaca_domes.write().await;
                        if let Some(dome) = domes.remove(device_id) {
                            let _ = dome.disconnect().await;
                        }
                    }
                    DeviceType::Weather => {
                        let mut weather = self.alpaca_weather.write().await;
                        if let Some(w) = weather.remove(device_id) {
                            let _ = w.disconnect().await;
                        }
                    }
                    DeviceType::SafetyMonitor => {
                        let mut safety = self.alpaca_safety_monitors.write().await;
                        if let Some(s) = safety.remove(device_id) {
                            let _ = s.disconnect().await;
                        }
                    }
                    DeviceType::Switch => {
                        let mut switches = self.alpaca_switches.write().await;
                        if let Some(sw) = switches.remove(device_id) {
                            let _ = sw.disconnect().await;
                        }
                    }
                    DeviceType::CoverCalibrator => {
                        let mut covers = self.alpaca_cover_calibrators.write().await;
                        if let Some(cover) = covers.remove(device_id) {
                            let _ = cover.disconnect().await;
                        }
                    }
                    DeviceType::Guider => {} // Alpaca guider devices are not currently managed here
                }
            }
            #[cfg(windows)]
            DriverType::Ascom => {
                // Remove from ASCOM storage based on device type
                match device_info.device_type {
                    DeviceType::Camera => {
                        let mut cameras = self.ascom_cameras.write().await;
                        if let Some(camera) = cameras.remove(device_id) {
                            let mut cam = camera.write().await;
                            let _ = cam.disconnect().await;
                        }
                    }
                    DeviceType::Mount => {
                        let mut mounts = self.ascom_mounts.write().await;
                        if let Some(mount) = mounts.remove(device_id) {
                            let mut m = mount.write().await;
                            let _ = m.disconnect().await;
                        }
                    }
                    DeviceType::Focuser => {
                        let mut focusers = self.ascom_focusers.write().await;
                        if let Some(focuser) = focusers.remove(device_id) {
                            let mut f = focuser.write().await;
                            let _ = f.disconnect().await;
                        }
                    }
                    DeviceType::FilterWheel => {
                        let mut fws = self.ascom_filter_wheels.write().await;
                        if let Some(fw) = fws.remove(device_id) {
                            let mut f = fw.write().await;
                            let _ = f.disconnect().await;
                        }
                    }
                    DeviceType::Rotator => {
                        let mut rotators = self.ascom_rotators.write().await;
                        if let Some(rotator) = rotators.remove(device_id) {
                            let mut r = rotator.write().await;
                            let _ = r.disconnect().await;
                        }
                    }
                    DeviceType::Dome => {
                        let mut domes = self.ascom_domes.write().await;
                        if let Some(dome) = domes.remove(device_id) {
                            let mut d = dome.write().await;
                            let _ = d.disconnect().await;
                        }
                    }
                    DeviceType::Weather => {
                        let mut weather = self.ascom_weather.write().await;
                        if let Some(device) = weather.remove(device_id) {
                            let mut w = device.write().await;
                            let _ = w.disconnect().await;
                        }
                    }
                    DeviceType::SafetyMonitor => {
                        let mut safety_monitors = self.ascom_safety_monitors.write().await;
                        if let Some(monitor) = safety_monitors.remove(device_id) {
                            let mut sm = monitor.write().await;
                            let _ = sm.disconnect().await;
                        }
                    }
                    DeviceType::Switch => {
                        let mut switches = self.ascom_switches.write().await;
                        if let Some(sw) = switches.remove(device_id) {
                            let mut s = sw.write().await;
                            let _ = s.disconnect().await;
                        }
                    }
                    DeviceType::CoverCalibrator => {
                        let mut covers = self.ascom_cover_calibrators.write().await;
                        if let Some(cover) = covers.remove(device_id) {
                            let mut c = cover.write().await;
                            let _ = c.disconnect().await;
                        }
                    }
                    _ => {}
                }
            }
            #[cfg(not(windows))]
            DriverType::Ascom => {
                // ASCOM not available on non-Windows platforms
            }
            DriverType::Indi => {
                // INDI cleanup handled separately through INDI client
                // The client manages device connections internally
            }
            DriverType::Simulator => {
                // Simulators should never be connected - connection is disabled
                // No cleanup needed even if this is somehow reached
            }
        }

        // Publish event
        self.app_state.publish_equipment_event(
            EquipmentEvent::Disconnected {
                device_type: device_info.device_type.as_str().to_string(),
                device_id: device_id.to_string(),
            },
            EventSeverity::Info,
        );

        // Update app state
        self.app_state
            .remove_device(device_info.device_type, device_id)
            .await;

        Ok(())
    }

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
    pub async fn is_connected(&self, device_id: &str) -> bool {
        let devices = self.devices.read().await;
        devices
            .get(device_id)
            .map(|d| d.connection_state == ConnectionState::Connected)
            .unwrap_or(false)
    }

    /// Get the cached API version for a device
    pub async fn get_device_api_version(&self, device_id: &str) -> Option<DeviceApiVersion> {
        let devices = self.devices.read().await;
        devices.get(device_id).and_then(|d| d.api_version.clone())
    }

    /// Store API version information for a device
    pub async fn set_device_api_version(&self, device_id: &str, version: DeviceApiVersion) {
        let mut devices = self.devices.write().await;
        if let Some(dev) = devices.get_mut(device_id) {
            dev.api_version = Some(version);
        }
    }



    /// Query API version for a device (dispatches based on driver type)
    pub async fn query_device_api_version(
        &self,
        device_id: &str,
    ) -> Result<DeviceApiVersion, String> {
        // Get the device info to determine driver type
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type)
        };

        match driver_type {
            Some(DriverType::Alpaca) => self.query_alpaca_api_version(device_id).await,
            Some(DriverType::Indi) => self.query_indi_api_version(device_id).await,
            #[cfg(windows)]
            Some(DriverType::Ascom) => self.query_ascom_api_version(device_id).await,
            #[cfg(not(windows))]
            Some(DriverType::Ascom) => Err("ASCOM is only supported on Windows".to_string()),
            Some(DriverType::Native) => {
                // Native devices don't have a query-able API version
                let version = DeviceApiVersion::new(device_id.to_string(), DriverType::Native);
                self.set_device_api_version(device_id, version.clone())
                    .await;
                Ok(version)
            }
            Some(DriverType::Simulator) => {
                // Simulators don't have a query-able API version
                let version = DeviceApiVersion::new(device_id.to_string(), DriverType::Simulator);
                self.set_device_api_version(device_id, version.clone())
                    .await;
                Ok(version)
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }


    /// Check if a device supports a specific interface version
    pub async fn device_supports_version(&self, device_id: &str, required_version: u32) -> bool {
        // Check cached version first
        if let Some(version) = self.get_device_api_version(device_id).await {
            if version.is_fresh() {
                return version.supports_version(required_version);
            }
        }

        // Try to query fresh version info
        if let Ok(version) = self.query_device_api_version(device_id).await {
            return version.supports_version(required_version);
        }

        false
    }

    /// Check if a device supports a specific action
    pub async fn device_supports_action(&self, device_id: &str, action: &str) -> bool {
        // Check cached version first
        if let Some(version) = self.get_device_api_version(device_id).await {
            if version.is_fresh() {
                return version.supports_action(action);
            }
        }

        // Try to query fresh version info
        if let Ok(version) = self.query_device_api_version(device_id).await {
            return version.supports_action(action);
        }

        false
    }

    /// Enable or disable auto-reconnect for a device
    pub async fn set_auto_reconnect(&self, device_id: &str, enabled: bool) {
        let mut devices = self.devices.write().await;
        if let Some(dev) = devices.get_mut(device_id) {
            dev.auto_reconnect = enabled;
        }
    }

    /// Report a connection error (triggers auto-reconnect if enabled)
    pub async fn report_error(&self, device_id: &str, error: String) {
        let mut devices = self.devices.write().await;
        if let Some(dev) = devices.get_mut(device_id) {
            dev.connection_state = ConnectionState::Error;
            dev.last_error = Some(error.clone());

            self.app_state.publish_equipment_event(
                EquipmentEvent::Error {
                    device_type: dev.info.device_type.as_str().to_string(),
                    device_id: device_id.to_string(),
                    message: error,
                },
                EventSeverity::Error,
            );
        }
    }

    /// Stop the reconnection background task
    pub async fn shutdown(&self) {
        *self.stop_reconnect.write().await = true;
    }

    /// Unregister a device
    pub async fn unregister_device(&self, device_id: &str) {
        let mut devices = self.devices.write().await;
        devices.remove(device_id);
    }




    // =========================================================================
    // Camera Control
    // =========================================================================

    /// Start a camera exposure
    pub async fn camera_start_exposure(
        &self,
        device_id: &str,
        duration: f64,
        gain: i32,
        offset: i32,
        bin_x: i32,
        bin_y: i32,
    ) -> Result<(), String> {
        tracing::info!(
            "DeviceManager: camera_start_exposure for {} duration={}",
            device_id,
            duration
        );

        // Get the driver type for this device
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let cameras = self.ascom_cameras.read().await;
                    if let Some(camera) = cameras.get(device_id) {
                        let params = ExposureParams {
                            duration_secs: duration,
                            bin_x,
                            bin_y,
                            gain: Some(gain),
                            offset: Some(offset),
                            subframe: None,
                            readout_mode: None,
                        };
                        tracing::info!("DeviceManager: Calling AscomCameraWrapper.start_exposure()");
                        let mut camera = camera.write().await;
                        return camera.start_exposure(params).await.map_err(|e| e.to_string());
                    }
                }
                Err(format!("ASCOM camera {} not found", device_id))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    tracing::info!("DeviceManager: Calling AlpacaCamera.start_exposure()");
                    // Set gain and offset before exposure - propagate errors
                    camera.set_gain(gain).await
                        .map_err(|e| format!("Failed to set Alpaca camera gain: {}", e))?;
                    camera.set_offset(offset).await
                        .map_err(|e| format!("Failed to set Alpaca camera offset: {}", e))?;
                    // Set binning - propagate errors
                    camera.set_bin_x(bin_x).await
                        .map_err(|e| format!("Failed to set Alpaca camera bin_x: {}", e))?;
                    camera.set_bin_y(bin_y).await
                        .map_err(|e| format!("Failed to set Alpaca camera bin_y: {}", e))?;
                    // Start the exposure
                    return camera.start_exposure(duration, true).await;
                }
                Err(format!("Alpaca camera {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port = parts[2];
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        tracing::info!("DeviceManager: Starting INDI exposure on {}", device_name);
                        let mut locked_client = client.write().await;
                        // Set gain/offset if supported - some INDI cameras don't support these, so warn but continue
                        if let Err(e) = locked_client.set_number(&device_name, "CCD_CONTROLS", "Gain", gain as f64).await {
                            tracing::warn!("Failed to set INDI camera gain (device may not support it): {}", e);
                        }
                        if let Err(e) = locked_client.set_number(&device_name, "CCD_CONTROLS", "Offset", offset as f64).await {
                            tracing::warn!("Failed to set INDI camera offset (device may not support it): {}", e);
                        }
                        // Set binning - propagate errors since binning is typically supported
                        locked_client.set_number(&device_name, "CCD_BINNING", "HOR_BIN", bin_x as f64).await
                            .map_err(|e| format!("Failed to set INDI camera horizontal binning: {}", e))?;
                        locked_client.set_number(&device_name, "CCD_BINNING", "VER_BIN", bin_y as f64).await
                            .map_err(|e| format!("Failed to set INDI camera vertical binning: {}", e))?;
                        // Start exposure
                        return locked_client.set_number(&device_name, "CCD_EXPOSURE", "CCD_EXPOSURE_VALUE", duration).await
                            .map_err(|e| e.to_string());
                    }
                }
                Err(format!("INDI camera {} not found", device_id))
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    tracing::info!("DeviceManager: Starting Native SDK exposure");
                    let params = ExposureParams {
                        duration_secs: duration,
                        bin_x,
                        bin_y,
                        gain: Some(gain),
                        offset: Some(offset),
                        subframe: None,
                        readout_mode: None,
                    };
                    return camera.start_exposure(params).await.map_err(|e| e.to_string());
                }
                Err(format!("Native SDK camera {} not found", device_id))
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device {} not found", device_id)),
        }
    }

    /// Check if camera exposure is complete
    pub async fn camera_is_exposure_complete(&self, device_id: &str) -> Result<bool, String> {
        // Get the driver type for this device
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let cameras = self.ascom_cameras.read().await;
                    if let Some(camera) = cameras.get(device_id) {
                        let camera = camera.read().await;
                        return camera.is_exposure_complete().await.map_err(|e| e.to_string());
                    }
                }
                Err(format!("ASCOM camera {} not found", device_id))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    return camera.image_ready().await;
                }
                Err(format!("Alpaca camera {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                // For INDI, check CCD_EXPOSURE state - when value is 0, exposure is complete
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port = parts[2];
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let locked_client = client.read().await;
                        // Check if exposure value is 0 (complete) - get_number returns Option
                        if let Some(value) = locked_client.get_number(&device_name, "CCD_EXPOSURE", "CCD_EXPOSURE_VALUE").await {
                            return Ok(value <= 0.0);
                        }
                        if locked_client.is_property_busy(&device_name, "CCD_EXPOSURE").await {
                            return Ok(false);
                        }
                        return Err(format!(
                            "INDI camera {} exposure status is unavailable (missing CCD_EXPOSURE_VALUE)",
                            device_name
                        ));
                    }
                }
                Err(format!("INDI camera {} not found", device_id))
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            Some(DriverType::Native) => {
                let native_cameras = self.native_cameras.read().await;
                if let Some(camera) = native_cameras.get(device_id) {
                    return camera.is_exposure_complete().await.map_err(|e| e.to_string());
                }
                Err(format!("Native SDK camera {} not found", device_id))
            }
            None => {
                Err(format!("Camera {} not found", device_id))
            }
        }
    }

    /// Download image from camera
    pub async fn camera_download_image(&self, device_id: &str) -> Result<ImageData, String> {
        // Get the driver type for this device
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let cameras = self.ascom_cameras.read().await;
                    if let Some(camera) = cameras.get(device_id) {
                        let mut camera = camera.write().await;
                        return camera.download_image().await.map_err(|e| e.to_string());
                    }
                }
                Err(format!("ASCOM camera {} not found", device_id))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    // Use the new download_image_data method
                    let (width, height, pixels) = camera.download_image_data().await?;

                    // Get camera metadata
                    let gain = match camera.gain().await {
                        Ok(g) => g,
                        Err(e) => {
                            warn!("Failed to read camera gain for {}: {}. Using default 0.", device_id, e);
                            0
                        }
                    };
                    let offset = match camera.offset().await {
                        Ok(o) => o,
                        Err(e) => {
                            warn!("Failed to read camera offset for {}: {}. Using default 0.", device_id, e);
                            0
                        }
                    };
                    let bin_x = match camera.bin_x().await {
                        Ok(b) => b,
                        Err(e) => {
                            warn!("Failed to read camera bin_x for {}: {}. Using default 1.", device_id, e);
                            1
                        }
                    };
                    let bin_y = match camera.bin_y().await {
                        Ok(b) => b,
                        Err(e) => {
                            warn!("Failed to read camera bin_y for {}: {}. Using default 1.", device_id, e);
                            1
                        }
                    };
                    let temp = camera.ccd_temperature().await.ok();
                    let exposure_time = match camera.last_exposure_duration().await {
                        Ok(d) => d,
                        Err(e) => {
                            warn!("Failed to read last exposure duration for {}: {}. Using default 0.0.", device_id, e);
                            0.0
                        }
                    };

                    // Determine if color camera (sensor_type: 0=Monochrome, 1=Color, etc.)
                    let sensor_type = match camera.sensor_type().await {
                        Ok(t) => t,
                        Err(e) => {
                            warn!(
                                "Failed to read sensor type for {}: {}. Marking sensor type unknown.",
                                device_id, e
                            );
                            -1
                        }
                    };
                    let bayer_pattern = if sensor_type == 1 {
                        // Get bayer offsets for color cameras
                        let offset_x = match camera.bayer_offset_x().await {
                            Ok(x) => x,
                            Err(e) => {
                                warn!("Failed to read bayer_offset_x for {}: {}. Using default 0.", device_id, e);
                                0
                            }
                        };
                        let offset_y = match camera.bayer_offset_y().await {
                            Ok(y) => y,
                            Err(e) => {
                                warn!("Failed to read bayer_offset_y for {}: {}. Using default 0.", device_id, e);
                                0
                            }
                        };
                        // Map offsets to bayer pattern
                        Some(match (offset_x, offset_y) {
                            (0, 0) => nightshade_native::camera::BayerPattern::Rggb,
                            (1, 0) => nightshade_native::camera::BayerPattern::Grbg,
                            (0, 1) => nightshade_native::camera::BayerPattern::Gbrg,
                            (1, 1) => nightshade_native::camera::BayerPattern::Bggr,
                            _ => nightshade_native::camera::BayerPattern::Rggb,
                        })
                    } else {
                        None
                    };

                    return Ok(ImageData {
                        width,
                        height,
                        data: pixels,
                        bits_per_pixel: 16,
                        bayer_pattern,
                        metadata: nightshade_native::camera::ImageMetadata {
                            exposure_time,
                            gain,
                            offset,
                            bin_x,
                            bin_y,
                            temperature: temp,
                            timestamp: chrono::Utc::now(),
                            subframe: None,
                            readout_mode: None,
                            vendor_data: nightshade_native::camera::VendorFeatures::default(),
                        },
                    });
                }
                Err(format!("Alpaca camera {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                // For INDI, image download uses event-based BLOB handling
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port = parts[2];
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        // Create an IndiCamera wrapper to handle BLOB download
                        let camera = nightshade_indi::IndiCamera::new(Arc::clone(client), &device_name);

                        // Enable BLOB transfer if not already enabled
                        let _ = camera.enable_blob().await;

                        // Get image metadata
                        let width = match camera.get_sensor_width().await {
                            Some(w) => w as u32,
                            None => {
                                warn!("Failed to read INDI sensor width for {}. Using default 1920.", device_id);
                                1920
                            }
                        };
                        let height = match camera.get_sensor_height().await {
                            Some(h) => h as u32,
                            None => {
                                warn!("Failed to read INDI sensor height for {}. Using default 1080.", device_id);
                                1080
                            }
                        };
                        let (bin_x, bin_y) = match camera
                            .get_binning_or_default(std::time::Duration::from_millis(0))
                            .await
                        {
                            Ok(b) => b,
                            Err(e) => {
                                warn!("Failed to read INDI binning for {}: {}. Using default (1, 1).", device_id, e);
                                (1, 1)
                            }
                        };
                        let temp = camera.get_temperature().await.ok();
                        let gain = match camera.get_gain().await {
                            Ok(g) => g,
                            Err(e) => {
                                warn!("Failed to read INDI gain for {}: {}. Using default 0.", device_id, e);
                                0
                            }
                        };
                        let offset = match camera.get_offset().await {
                            Ok(o) => o,
                            Err(e) => {
                                warn!("Failed to read INDI offset for {}: {}. Using default 0.", device_id, e);
                                0
                            }
                        };

                        // Subscribe to events and wait for BLOB
                        let mut rx = {
                            let locked_client = client.read().await;
                            locked_client.subscribe()
                        };

                        // Wait for BLOB data with timeout (30 seconds)
                        let timeout = std::time::Duration::from_secs(30);
                        let start_time = std::time::Instant::now();

                        loop {
                            if start_time.elapsed() > timeout {
                                return Err("Timeout waiting for INDI image BLOB".to_string());
                            }

                            match tokio::time::timeout(std::time::Duration::from_secs(1), rx.recv()).await {
                                Ok(Ok(event)) => {
                                    match event {
                                        nightshade_indi::IndiEvent::BlobReceived { device, element, data, .. } => {
                                            if device == device_name && (element == "CCD1" || element == "CCD2") {
                                                // Parse FITS data
                                                // Attempt to extract raw image data.
                                                // FITS files have a header followed by binary data
                                                // This is a simplified implementation - full FITS parsing would be more robust

                                                // Try to parse as FITS and extract u16 data
                                                let image_data = if data.starts_with(b"SIMPLE") {
                                                    // FITS file - extract binary data after header
                                                    // FITS headers are 2880-byte blocks
                                                    let mut offset = 0;
                                                    for chunk in data.chunks(80) {
                                                        offset += 80;
                                                        if chunk.starts_with(b"END") {
                                                            // Header ends, align to 2880-byte boundary
                                                            offset = ((offset + 2879) / 2880) * 2880;
                                                            break;
                                                        }
                                                    }

                                                    // Extract binary data as u16
                                                    let binary_data = &data[offset..];
                                                    let mut pixels: Vec<u16> = Vec::with_capacity(binary_data.len() / 2);
                                                    for chunk in binary_data.chunks_exact(2) {
                                                        let value = u16::from_be_bytes([chunk[0], chunk[1]]);
                                                        pixels.push(value);
                                                    }
                                                    pixels
                                                } else {
                                                    // Not a FITS file, try to parse as raw u16 data
                                                    let mut pixels: Vec<u16> = Vec::with_capacity(data.len() / 2);
                                                    for chunk in data.chunks_exact(2) {
                                                        let value = u16::from_le_bytes([chunk[0], chunk[1]]);
                                                        pixels.push(value);
                                                    }
                                                    pixels
                                                };

                                                return Ok(ImageData {
                                                    width,
                                                    height,
                                                    data: image_data,
                                                    bits_per_pixel: 16,
                                                    bayer_pattern: None,
                                                    metadata: nightshade_native::camera::ImageMetadata {
                                                        exposure_time: 0.0, // Not available in BLOB event
                                                        gain,
                                                        offset,
                                                        bin_x,
                                                        bin_y,
                                                        temperature: temp,
                                                        timestamp: chrono::Utc::now(),
                                                        subframe: None,
                                                        readout_mode: None,
                                                        vendor_data: nightshade_native::camera::VendorFeatures::default(),
                                                    },
                                                });
                                            }
                                        },
                                        _ => {}
                                    }
                                }
                                Ok(Err(_)) => {
                                    return Err("INDI event channel closed".to_string());
                                }
                                Err(_) => {
                                    // Timeout on recv, check total timeout and continue
                                    continue;
                                }
                            }
                        }
                    }
                }
                Err(format!("INDI camera {} not found", device_id))
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera.download_image().await.map_err(|e| e.to_string());
                }
                Err(format!("Native SDK camera {} not found", device_id))
            }
            None => {
                Err(format!("Camera {} not found", device_id))
            }
        }
    }

    /// Abort a camera exposure
    pub async fn camera_abort_exposure(&self, device_id: &str) -> Result<(), String> {
        tracing::info!("DeviceManager: camera_abort_exposure for {}", device_id);

        // Get the driver type for this device
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let cameras = self.ascom_cameras.read().await;
                    if let Some(camera) = cameras.get(device_id) {
                        let mut camera = camera.write().await;
                        return camera.abort_exposure().await.map_err(|e| e.to_string());
                    }
                }
                Err(format!("ASCOM camera {} not found", device_id))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    return camera.abort_exposure().await;
                }
                Err(format!("Alpaca camera {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                // For INDI, set exposure to 0 to abort
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port = parts[2];
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mut locked_client = client.write().await;
                        return locked_client.set_switch(&device_name, "CCD_ABORT_EXPOSURE", "ABORT", true).await
                            .map_err(|e| e.to_string());
                    }
                }
                Err(format!("INDI camera {} not found", device_id))
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera.abort_exposure().await.map_err(|e| e.to_string());
                }
                Err(format!("Native SDK camera {} not found", device_id))
            }
            None => {
                Err(format!("Camera {} not found", device_id))
            }
        }
    }

    /// Get camera status
    pub async fn camera_get_status(
        &self,
        device_id: &str,
    ) -> Result<crate::device::CameraStatus, String> {
        // Get the driver type for this device
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let cameras = self.ascom_cameras.read().await;
                    if let Some(camera) = cameras.get(device_id) {
                        let camera_guard = camera.read().await;
                        let native_status = camera_guard.get_status().await
                            .map_err(|e| e.to_string())?;
                        let ascom_caps = camera_guard.get_capabilities().await.ok();

                        return Ok(crate::device::CameraStatus {
                            connected: true,
                            state: match native_status.state {
                                nightshade_native::camera::CameraState::Idle => crate::device::CameraState::Idle,
                                nightshade_native::camera::CameraState::Waiting => crate::device::CameraState::Waiting,
                                nightshade_native::camera::CameraState::Exposing => crate::device::CameraState::Exposing,
                                nightshade_native::camera::CameraState::Reading => crate::device::CameraState::Reading,
                                nightshade_native::camera::CameraState::Downloading => crate::device::CameraState::Download,
                                nightshade_native::camera::CameraState::Error => crate::device::CameraState::Error,
                            },
                            sensor_temp: native_status.sensor_temp,
                            cooler_power: native_status.cooler_power,
                            target_temp: native_status.target_temp,
                            cooler_on: native_status.cooler_on,
                            gain: native_status.gain,
                            offset: native_status.offset,
                            bin_x: native_status.bin_x,
                            bin_y: native_status.bin_y,
                            sensor_width: ascom_caps.as_ref().map(|c| c.max_width).unwrap_or(0),
                            sensor_height: ascom_caps.as_ref().map(|c| c.max_height).unwrap_or(0),
                            pixel_size_x: ascom_caps.as_ref().and_then(|c| c.pixel_size_x).unwrap_or(0.0),
                            pixel_size_y: ascom_caps.as_ref().and_then(|c| c.pixel_size_y).unwrap_or(0.0),
                            max_adu: ascom_caps.as_ref().map(|c| (1u32 << c.bit_depth) - 1).unwrap_or(65535),
                            can_cool: ascom_caps.as_ref().map(|c| c.can_set_ccd_temperature).unwrap_or(false),
                            can_set_gain: true,
                            can_set_offset: true,
                        });
                    }
                }
                Err(format!("ASCOM camera {} not found", device_id))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    let status = camera.get_status().await.map_err(|e| {
                        format!("Failed to read Alpaca camera status for {}: {}", device_id, e)
                    })?;
                    let capabilities = camera.get_capabilities().await.map_err(|e| {
                        format!(
                            "Failed to read Alpaca camera capabilities for {}: {}",
                            device_id, e
                        )
                    })?;
                    let sensor = camera.get_sensor_info().await.map_err(|e| {
                        format!("Failed to read Alpaca camera sensor info for {}: {}", device_id, e)
                    })?;
                    let gain = camera.gain().await.ok();
                    let offset = camera.offset().await.ok();

                    return Ok(crate::device::CameraStatus {
                        connected: true,
                        state: match status.state {
                            nightshade_alpaca::CameraState::Idle => crate::device::CameraState::Idle,
                            nightshade_alpaca::CameraState::Waiting => crate::device::CameraState::Waiting,
                            nightshade_alpaca::CameraState::Exposing => crate::device::CameraState::Exposing,
                            nightshade_alpaca::CameraState::Reading => crate::device::CameraState::Reading,
                            nightshade_alpaca::CameraState::Download => crate::device::CameraState::Download,
                            nightshade_alpaca::CameraState::Error => crate::device::CameraState::Error,
                        },
                        sensor_temp: status.ccd_temperature,
                        cooler_power: status.cooler_power,
                        target_temp: None, // Alpaca doesn't provide target temp directly
                        cooler_on: status.cooler_on.unwrap_or(false),
                        gain: gain.unwrap_or(0),
                        offset: offset.unwrap_or(0),
                        bin_x: status.bin_x,
                        bin_y: status.bin_y,
                        sensor_width: sensor.camera_x_size as u32,
                        sensor_height: sensor.camera_y_size as u32,
                        pixel_size_x: sensor.pixel_size_x,
                        pixel_size_y: sensor.pixel_size_y,
                        max_adu: sensor.max_adu as u32,
                        can_cool: capabilities.can_set_ccd_temperature,
                        can_set_gain: gain.is_some(),
                        can_set_offset: offset.is_some(),
                    });
                }
                Err(format!("Alpaca camera {} not found", device_id))
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            Some(DriverType::Native) => {
                let native_cameras = self.native_cameras.read().await;
                if let Some(camera) = native_cameras.get(device_id) {
                    let native_status = camera.get_status().await.map_err(|e| e.to_string())?;
                    let capabilities = camera.capabilities();
                    let sensor_info = camera.get_sensor_info();

                    return Ok(crate::device::CameraStatus {
                        connected: camera.is_connected(),
                        state: match native_status.state {
                            nightshade_native::camera::CameraState::Idle => crate::device::CameraState::Idle,
                            nightshade_native::camera::CameraState::Waiting => crate::device::CameraState::Waiting,
                            nightshade_native::camera::CameraState::Exposing => crate::device::CameraState::Exposing,
                            nightshade_native::camera::CameraState::Reading => crate::device::CameraState::Reading,
                            nightshade_native::camera::CameraState::Downloading => crate::device::CameraState::Download,
                            nightshade_native::camera::CameraState::Error => crate::device::CameraState::Error,
                        },
                        sensor_temp: native_status.sensor_temp,
                        cooler_power: native_status.cooler_power,
                        target_temp: native_status.target_temp,
                        cooler_on: native_status.cooler_on,
                        gain: native_status.gain,
                        offset: native_status.offset,
                        bin_x: native_status.bin_x,
                        bin_y: native_status.bin_y,
                        sensor_width: sensor_info.width,
                        sensor_height: sensor_info.height,
                        pixel_size_x: sensor_info.pixel_size_x,
                        pixel_size_y: sensor_info.pixel_size_y,
                        max_adu: (1 << sensor_info.bit_depth) - 1,
                        can_cool: capabilities.can_cool,
                        can_set_gain: capabilities.can_set_gain,
                        can_set_offset: capabilities.can_set_offset,
                    });
                }
                Err(format!("Native SDK camera {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                // Parse device_id format: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err(format!("Invalid INDI device ID format: {}", device_id));
                }
                let host = parts[1];
                let port = parts[2];
                let device_name = parts[3..].join(":");
                let server_key = format!("{}:{}", host, port);

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked_client = client.read().await;

                    // Query INDI camera properties
                    let sensor_temp = locked_client
                        .get_number(&device_name, "CCD_TEMPERATURE", "CCD_TEMPERATURE_VALUE")
                        .await;
                    let cooler_state = locked_client
                        .get_switch(&device_name, "CCD_COOLER", "COOLER_ON")
                        .await;
                    let has_cooler = cooler_state.is_some();
                    let cooler_on = cooler_state.unwrap_or(false);
                    let bin_x = locked_client
                        .get_number(&device_name, "CCD_BINNING", "HOR_BIN")
                        .await
                        .map(|v| v as i32)
                        .ok_or_else(|| {
                            format!(
                                "INDI camera {} missing required property CCD_BINNING.HOR_BIN; cannot determine current binning.",
                                device_id
                            )
                        })?;
                    let bin_y = locked_client
                        .get_number(&device_name, "CCD_BINNING", "VER_BIN")
                        .await
                        .map(|v| v as i32)
                        .ok_or_else(|| {
                            format!(
                                "INDI camera {} missing required property CCD_BINNING.VER_BIN; cannot determine current binning.",
                                device_id
                            )
                        })?;
                    let exposure_value = locked_client
                        .get_number(&device_name, "CCD_EXPOSURE", "CCD_EXPOSURE_VALUE")
                        .await;

                    // Determine camera state based on exposure value
                    let state = match exposure_value {
                        Some(v) if v > 0.0 => crate::device::CameraState::Exposing,
                        Some(_) => crate::device::CameraState::Idle,
                        None => {
                            return Err(format!(
                                "INDI camera {} missing required property CCD_EXPOSURE.CCD_EXPOSURE_VALUE; cannot determine camera state.",
                                device_id
                            ))
                        }
                    };

                    // Read sensor info from INDI CCD_INFO property.
                    let sensor_width = locked_client
                        .get_number(&device_name, "CCD_INFO", "CCD_MAX_X")
                        .await
                        .map(|v| v as u32)
                        .ok_or_else(|| {
                            format!(
                                "INDI camera {} missing required property CCD_INFO.CCD_MAX_X; cannot determine sensor width.",
                                device_id
                            )
                        })?;
                    let sensor_height = locked_client
                        .get_number(&device_name, "CCD_INFO", "CCD_MAX_Y")
                        .await
                        .map(|v| v as u32)
                        .ok_or_else(|| {
                            format!(
                                "INDI camera {} missing required property CCD_INFO.CCD_MAX_Y; cannot determine sensor height.",
                                device_id
                            )
                        })?;
                    let pixel_size_x = locked_client
                        .get_number(&device_name, "CCD_INFO", "CCD_PIXEL_SIZE_X")
                        .await
                        .ok_or_else(|| {
                            format!(
                                "INDI camera {} missing required property CCD_INFO.CCD_PIXEL_SIZE_X; cannot determine pixel size.",
                                device_id
                            )
                        })?;
                    let pixel_size_y = locked_client
                        .get_number(&device_name, "CCD_INFO", "CCD_PIXEL_SIZE_Y")
                        .await
                        .ok_or_else(|| {
                            format!(
                                "INDI camera {} missing required property CCD_INFO.CCD_PIXEL_SIZE_Y; cannot determine pixel size.",
                                device_id
                            )
                        })?;
                    let bit_depth = locked_client
                        .get_number(&device_name, "CCD_INFO", "CCD_BITSPERPIXEL")
                        .await
                        .map(|v| v as u32)
                        .ok_or_else(|| {
                            format!(
                                "INDI camera {} missing required property CCD_INFO.CCD_BITSPERPIXEL; cannot determine ADU scaling.",
                                device_id
                            )
                        })?;
                    if bit_depth == 0 {
                        return Err(format!(
                            "INDI camera {} reported invalid CCD_INFO.CCD_BITSPERPIXEL=0.",
                            device_id
                        ));
                    }
                    let gain_value = locked_client.get_number(&device_name, "CCD_GAIN", "GAIN").await;
                    let offset_value = locked_client.get_number(&device_name, "CCD_OFFSET", "OFFSET").await;
                    let gain = gain_value.map(|v| v as i32).unwrap_or(0);
                    let offset = offset_value.map(|v| v as i32).unwrap_or(0);
                    let cooler_power = locked_client
                        .get_number(&device_name, "CCD_COOLER_POWER", "CCD_COOLER_VALUE")
                        .await;
                    let has_gain = gain_value.is_some();
                    let has_offset = offset_value.is_some();
                    let max_adu = if bit_depth >= 32 {
                        u32::MAX
                    } else {
                        (1u32 << bit_depth) - 1
                    };

                    return Ok(crate::device::CameraStatus {
                        connected: true,
                        state,
                        sensor_temp,
                        cooler_power,
                        target_temp: None,
                        cooler_on,
                        gain,
                        offset,
                        bin_x,
                        bin_y,
                        sensor_width,
                        sensor_height,
                        pixel_size_x,
                        pixel_size_y,
                        max_adu,
                        can_cool: has_cooler,
                        can_set_gain: has_gain,
                        can_set_offset: has_offset,
                    });
                }
                Err(format!("INDI client not connected for server {}", server_key))
            }
            None => {
                Err(format!("Camera {} not found or status not supported", device_id))
            }
        }
    }

    /// Set camera gain
    pub async fn camera_set_gain(&self, device_id: &str, gain: i32) -> Result<(), String> {
        tracing::info!(
            "DeviceManager: camera_set_gain for {} gain={}",
            device_id,
            gain
        );

        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let cameras = self.ascom_cameras.read().await;
                    if let Some(camera) = cameras.get(device_id) {
                        let mut camera = camera.write().await;
                        return camera.set_gain(gain).await.map_err(|e| e.to_string());
                    }
                }
                Err(format!("ASCOM camera {} not found", device_id))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    return camera.set_gain(gain).await;
                }
                Err(format!("Alpaca camera {} not found", device_id))
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera.set_gain(gain).await.map_err(|e| e.to_string());
                }
                Err(format!("Native SDK camera {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID format".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    locked.set_number(&device_name, "CCD_CONTROLS", "Gain", gain as f64)
                        .await
                        .map_err(|e| format!("Failed to set INDI camera gain: {}", e))?;
                    return Ok(());
                }
                Err(format!("INDI client not connected for server {}", server_key))
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            _ => Err(format!("Camera {} not found or not supported", device_id)),
        }
    }

    /// Set camera offset
    pub async fn camera_set_offset(&self, device_id: &str, offset: i32) -> Result<(), String> {
        tracing::info!(
            "DeviceManager: camera_set_offset for {} offset={}",
            device_id,
            offset
        );

        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let cameras = self.ascom_cameras.read().await;
                    if let Some(camera) = cameras.get(device_id) {
                        let mut camera = camera.write().await;
                        return camera.set_offset(offset).await.map_err(|e| e.to_string());
                    }
                }
                Err(format!("ASCOM camera {} not found", device_id))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    return camera.set_offset(offset).await;
                }
                Err(format!("Alpaca camera {} not found", device_id))
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera.set_offset(offset).await.map_err(|e| e.to_string());
                }
                Err(format!("Native SDK camera {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID format".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    locked.set_number(&device_name, "CCD_CONTROLS", "Offset", offset as f64)
                        .await
                        .map_err(|e| format!("Failed to set INDI camera offset: {}", e))?;
                    return Ok(());
                }
                Err(format!("INDI client not connected for server {}", server_key))
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            _ => Err(format!("Camera {} not found or not supported", device_id)),
        }
    }

    /// Set camera binning
    pub async fn camera_set_binning(
        &self,
        device_id: &str,
        bin_x: i32,
        bin_y: i32,
    ) -> Result<(), String> {
        tracing::info!(
            "DeviceManager: camera_set_binning for {} bin={}x{}",
            device_id,
            bin_x,
            bin_y
        );

        if bin_x < 1 || bin_y < 1 {
            return Err(format!(
                "Invalid binning values: {}x{} (must be >= 1)",
                bin_x, bin_y
            ));
        }

        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let cameras = self.ascom_cameras.read().await;
                    if let Some(camera) = cameras.get(device_id) {
                        let mut camera = camera.write().await;
                        return camera.set_binning(bin_x, bin_y).await.map_err(|e| e.to_string());
                    }
                }
                Err(format!("ASCOM camera {} not found", device_id))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    camera.set_bin_x(bin_x).await?;
                    camera.set_bin_y(bin_y).await?;
                    return Ok(());
                }
                Err(format!("Alpaca camera {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err(format!("Invalid INDI device ID format: {}", device_id));
                }

                let host = parts[1];
                let port = parts[2];
                let device_name = parts[3..].join(":");
                let server_key = format!("{}:{}", host, port);

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked_client = client.write().await;
                    locked_client
                        .set_number(&device_name, "CCD_BINNING", "HOR_BIN", bin_x as f64)
                        .await?;
                    locked_client
                        .set_number(&device_name, "CCD_BINNING", "VER_BIN", bin_y as f64)
                        .await?;
                    return Ok(());
                }
                Err(format!("INDI client not connected for server {}", server_key))
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera
                        .set_binning(bin_x, bin_y)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err(format!("Native SDK camera {} not found", device_id))
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            _ => Err(format!("Camera {} not found or not supported", device_id)),
        }
    }

    /// Set camera readout mode by index
    ///
    /// ASCOM: Sets the ReadoutMode property (integer index)
    /// Alpaca: Sets the readoutmode property (integer index)
    /// INDI: Sets the CCD_READ_MODE switch to the element at the given index
    /// Native: Delegates to NativeCamera::set_readout_mode with a synthetic ReadoutMode
    pub async fn camera_set_readout_mode(
        &self,
        device_id: &str,
        mode_index: i32,
    ) -> Result<(), String> {
        tracing::info!(
            "DeviceManager: camera_set_readout_mode for {} mode_index={}",
            device_id,
            mode_index
        );

        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let cameras = self.ascom_cameras.read().await;
                    if let Some(camera) = cameras.get(device_id) {
                        let mut camera = camera.write().await;
                        let mode = nightshade_native::camera::ReadoutMode {
                            name: format!("Mode {}", mode_index),
                            description: String::new(),
                            index: mode_index,
                            gain_min: None,
                            gain_max: None,
                            offset_min: None,
                            offset_max: None,
                        };
                        return camera
                            .set_readout_mode(&mode)
                            .await
                            .map_err(|e| e.to_string());
                    }
                }
                Err(format!("ASCOM camera {} not found", device_id))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    return camera.set_readout_mode(mode_index).await;
                }
                Err(format!("Alpaca camera {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                // INDI uses CCD_READ_MODE switch with indexed elements
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID format".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    // INDI cameras expose readout speed as a switch property.
                    // Common property names: CCD_READ_MODE, CCD_READOUT_SPEED, READOUT_QUALITY
                    let switch_props =
                        ["CCD_READ_MODE", "CCD_READOUT_SPEED", "READOUT_QUALITY"];
                    let all_props = locked.get_properties(&device_name).await;
                    for prop_name in &switch_props {
                        if let Some(prop) = all_props.iter().find(|p| {
                            p.name == *prop_name
                                && p.property_type
                                    == nightshade_indi::IndiPropertyType::Switch
                        }) {
                            if (mode_index as usize) < prop.elements.len() {
                                let element = prop.elements[mode_index as usize].clone();
                                locked
                                    .set_switch(
                                        &device_name,
                                        prop_name,
                                        &element,
                                        true,
                                    )
                                    .await
                                    .map_err(|e| {
                                        format!("Failed to set INDI readout mode: {}", e)
                                    })?;
                                return Ok(());
                            } else {
                                return Err(format!(
                                    "Readout mode index {} out of range (camera has {} modes)",
                                    mode_index,
                                    prop.elements.len()
                                ));
                            }
                        }
                    }
                    // No readout mode property found - not an error, many INDI cameras lack this
                    tracing::debug!(
                        "No readout mode switch property found for INDI camera {}",
                        device_name
                    );
                    return Ok(());
                }
                Err(format!(
                    "INDI client not connected for server {}",
                    server_key
                ))
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    let mode = nightshade_native::camera::ReadoutMode {
                        name: format!("Mode {}", mode_index),
                        description: String::new(),
                        index: mode_index,
                        gain_min: None,
                        gain_max: None,
                        offset_min: None,
                        offset_max: None,
                    };
                    return camera.set_readout_mode(&mode).await.map_err(|e| e.to_string());
                }
                Err(format!("Native SDK camera {} not found", device_id))
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            _ => Err(format!("Camera {} not found or not supported", device_id)),
        }
    }

    /// Set camera cooler
    pub async fn camera_set_cooler(
        &self,
        device_id: &str,
        enabled: bool,
        target_temp: Option<f64>,
    ) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let cameras = self.ascom_cameras.read().await;
                    if let Some(cam) = cameras.get(device_id) {
                        let mut cam = cam.write().await;
                        cam.set_cooler(enabled, target_temp.unwrap_or(-10.0)).await.map_err(|e| e.to_string())?;
                        return Ok(());
                    }
                }
                Err("ASCOM camera not connected".to_string())
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    camera.set_cooler_on(enabled).await?;
                    if let Some(temp) = target_temp {
                        camera.set_ccd_temperature(temp).await?;
                    }
                    return Ok(());
                }
                Err(format!("Alpaca camera {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                // Parse device_id format: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err(format!("Invalid INDI device ID format: {}", device_id));
                }
                let host = parts[1];
                let port = parts[2];
                let device_name = parts[3..].join(":");
                let server_key = format!("{}:{}", host, port);

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked_client = client.write().await;
                    // Set cooler on/off
                    let switch_element = if enabled { "COOLER_ON" } else { "COOLER_OFF" };
                    locked_client.set_switch(&device_name, "CCD_COOLER", switch_element, true).await?;
                    // Set target temperature if provided
                    if let Some(temp) = target_temp {
                        locked_client.set_number(&device_name, "CCD_TEMPERATURE", "CCD_TEMPERATURE_VALUE", temp).await?;
                    }
                    return Ok(());
                }
                Err(format!("INDI client not connected for server {}", server_key))
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera.set_cooler(enabled, target_temp.unwrap_or(-10.0)).await.map_err(|e| e.to_string());
                }
                Err(format!("Native SDK camera {} not found", device_id))
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err("Driver type not found".to_string()),
        }
    }

    // =========================================================================
    // Mount Control
    // =========================================================================

    pub async fn mount_slew(&self, device_id: &str, ra: f64, dec: f64) -> Result<(), String> {
        tracing::debug!(
            "mount_slew called: device_id={}, ra={}, dec={}",
            device_id,
            ra,
            dec
        );

        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| {
                tracing::error!("mount_slew: Device not found in devices map: {}", device_id);
                format!("Device not found: {}", device_id)
            })?;

        tracing::debug!(
            "mount_slew: Found device with driver_type={:?}",
            info.driver_type
        );

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    tracing::debug!("mount_slew: ascom_mounts contains {} entries", mounts.len());
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.slew_to_coordinates(ra, dec).await.map_err(|e| {
                            tracing::error!("mount_slew ASCOM error: {}", e);
                            e.to_string()
                        });
                    } else {
                        tracing::error!("mount_slew: Mount {} not found in ascom_mounts. Available: {:?}",
                            device_id, mounts.keys().collect::<Vec<_>>());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    tracing::debug!("mount_slew: Calling Alpaca slew_to_coordinates_async");
                    return mount.slew_to_coordinates_async(ra, dec).await.map_err(|e| {
                        tracing::error!("mount_slew Alpaca error: {}", e);
                        e
                    });
                }
                tracing::error!("mount_slew: Alpaca mount {} not connected", device_id);
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port = parts[2];
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        tracing::debug!("mount_slew: Creating INDI mount wrapper for {}", device_name);
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.slew_to_coordinates(ra, dec).await.map_err(|e| {
                            tracing::error!("mount_slew INDI error: {}", e);
                            e.to_string()
                        });
                    }
                    tracing::error!("mount_slew: INDI client not connected for {}", server_key);
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.slew_to_coordinates(ra, dec).await.map_err(|e| {
                        tracing::error!("mount_slew Native error: {}", e);
                        e.to_string()
                    });
                }
                tracing::error!("mount_slew: Native mount {} not connected", device_id);
                Err("Native mount not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_sync(&self, device_id: &str, ra: f64, dec: f64) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.sync_to_coordinates(ra, dec).await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.sync_to_coordinates(ra, dec).await;
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.sync_to_coordinates(ra, dec).await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.sync_to_coordinates(ra, dec).await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_park(&self, device_id: &str) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.park().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.park().await;
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.park().await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.park().await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_unpark(&self, device_id: &str) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.unpark().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.unpark().await;
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.unpark().await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.unpark().await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_slew_alt_az(
        &self,
        device_id: &str,
        altitude: f64,
        azimuth: f64,
    ) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.write().await;
                        return mount.slew_to_alt_az(altitude, azimuth).await.map_err(|e| {
                            tracing::error!("mount_slew_alt_az ASCOM error: {}", e);
                            e.to_string()
                        });
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.slew_to_alt_az_async(altitude, azimuth).await.map_err(|e| {
                        tracing::error!("mount_slew_alt_az Alpaca error: {}", e);
                        e
                    });
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port = parts[2];
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.slew_to_alt_az(altitude, azimuth).await.map_err(|e| {
                            tracing::error!("mount_slew_alt_az INDI error: {}", e);
                            e.to_string()
                        });
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                // Native mounts (SkyWatcher, iOptron, etc.) are equatorial; alt/az slew is not
                // natively supported. Return an error rather than silently failing.
                Err("Alt/Az slew is not supported for native serial mounts".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_find_home(&self, device_id: &str) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.write().await;
                        return mount.find_home().await.map_err(|e| {
                            tracing::error!("mount_find_home ASCOM error: {}", e);
                            e.to_string()
                        });
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.find_home().await.map_err(|e| {
                        tracing::error!("mount_find_home Alpaca error: {}", e);
                        e
                    });
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port = parts[2];
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.find_home().await.map_err(|e| {
                            tracing::error!("mount_find_home INDI error: {}", e);
                            e.to_string()
                        });
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                // Native serial mounts don't have a standardized find-home command
                Err("Find home is not supported for native serial mounts".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_get_coordinates(&self, device_id: &str) -> Result<(f64, f64), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;
                        return mount.get_coordinates().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    return mount.get_coordinates().await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    let ra = mount.right_ascension().await.map_err(|e| e.to_string())?;
                    let dec = mount.declination().await.map_err(|e| e.to_string())?;
                    return Ok((ra, dec));
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.get_coordinates().await;
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_abort(&self, device_id: &str) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.abort_slew().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.abort_slew().await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.abort_slew().await.map_err(|e| e.to_string());
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.abort_slew().await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_stop(&self, device_id: &str) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;
                        return mount.stop().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.abort_slew().await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.abort_slew().await.map_err(|e| e.to_string());
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.abort_slew().await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_set_tracking(&self, device_id: &str, enabled: bool) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.set_tracking(enabled).await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.set_tracking(enabled).await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.set_tracking(enabled).await.map_err(|e| e.to_string());
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        return mount.set_tracking(enabled).await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_pulse_guide(
        &self,
        device_id: &str,
        direction: String,
        duration_ms: u32,
    ) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        let direction_lower = direction.to_lowercase();
        let dir = match direction_lower.as_str() {
            "north" | "n" => nightshade_native::traits::GuideDirection::North,
            "south" | "s" => nightshade_native::traits::GuideDirection::South,
            "east" | "e" => nightshade_native::traits::GuideDirection::East,
            "west" | "w" => nightshade_native::traits::GuideDirection::West,
            _ => return Err(format!("Invalid direction: {}", direction)),
        };

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.pulse_guide(dir, duration_ms).await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    return mount.pulse_guide(dir, duration_ms).await.map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    let alpaca_dir = match dir {
                        nightshade_native::traits::GuideDirection::North => 0,
                        nightshade_native::traits::GuideDirection::South => 1,
                        nightshade_native::traits::GuideDirection::East => 2,
                        nightshade_native::traits::GuideDirection::West => 3,
                    };
                    return mount
                        .pulse_guide(alpaca_dir, duration_ms as i32)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                        match dir {
                            nightshade_native::traits::GuideDirection::North => {
                                mount.move_north(true).await.map_err(|e| e.to_string())?;
                                tokio::time::sleep(Duration::from_millis(duration_ms as u64)).await;
                                mount.move_north(false).await.map_err(|e| e.to_string())?;
                            }
                            nightshade_native::traits::GuideDirection::South => {
                                mount.move_south(true).await.map_err(|e| e.to_string())?;
                                tokio::time::sleep(Duration::from_millis(duration_ms as u64)).await;
                                mount.move_south(false).await.map_err(|e| e.to_string())?;
                            }
                            nightshade_native::traits::GuideDirection::East => {
                                mount.move_east(true).await.map_err(|e| e.to_string())?;
                                tokio::time::sleep(Duration::from_millis(duration_ms as u64)).await;
                                mount.move_east(false).await.map_err(|e| e.to_string())?;
                            }
                            nightshade_native::traits::GuideDirection::West => {
                                mount.move_west(true).await.map_err(|e| e.to_string())?;
                                tokio::time::sleep(Duration::from_millis(duration_ms as u64)).await;
                                mount.move_west(false).await.map_err(|e| e.to_string())?;
                            }
                        }
                        return Ok(());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_can_park(&self, device_id: &str) -> Result<bool, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;
                        return mount.can_park().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    return match mount.is_parked().await {
                        Ok(_) => Ok(true),
                        Err(nightshade_native::traits::NativeError::NotSupported) => Ok(false),
                        Err(e) => Err(format!(
                            "Failed to determine native mount park capability for {}: {}",
                            device_id, e
                        )),
                    };
                }
                Err(format!("Native mount {} not connected", device_id))
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    return mount.can_park().await.map_err(|e| e.to_string());
                }
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let server_key = format!("{}:{}", parts[1], parts[2]);
                    let device_name = parts[3..].join(":");
                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let locked = client.read().await;
                        let supports_park = locked
                            .get_switch(&device_name, "TELESCOPE_PARK", "PARK")
                            .await
                            .is_some()
                            || locked
                                .get_switch(&device_name, "TELESCOPE_PARK", "UNPARK")
                                .await
                                .is_some();
                        return Ok(supports_park);
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn mount_get_status(&self, device_id: &str) -> Result<MountStatus, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;

                        // Required fields propagate read failures — these are not optional.
                        let (ra, dec) = mount.get_coordinates().await.map_err(|e| e.to_string())?;
                        let tracking = mount.get_tracking().await.map_err(|e| e.to_string())?;
                        let slewing = mount.is_slewing().await.map_err(|e| e.to_string())?;
                        let parked = mount.is_parked().await.map_err(|e| e.to_string())?;

                        let mut availability: HashMap<String, FieldAvailability> = HashMap::new();

                        // Optional fields: the ASCOM wrapper currently does not surface a
                        // distinct "not supported" error so any failure is recorded as Error.
                        let (alt_opt, az_opt) = match mount.get_alt_az().await {
                            Ok((a, z)) => (Some(a), Some(z)),
                            Err(e) => {
                                let msg = e.to_string();
                                availability.insert(
                                    mount_status_field::ALTITUDE.to_string(),
                                    FieldAvailability::Error(msg.clone()),
                                );
                                availability.insert(
                                    mount_status_field::AZIMUTH.to_string(),
                                    FieldAvailability::Error(msg),
                                );
                                (None, None)
                            }
                        };
                        if alt_opt.is_some() {
                            availability.insert(
                                mount_status_field::ALTITUDE.to_string(),
                                FieldAvailability::Available,
                            );
                            availability.insert(
                                mount_status_field::AZIMUTH.to_string(),
                                FieldAvailability::Available,
                            );
                        }

                        let side_of_pier_opt = Self::availability_from_native_result(
                            mount.get_side_of_pier().await,
                            mount_status_field::SIDE_OF_PIER,
                            &mut availability,
                        )
                        .map(Self::pier_side_from_native);

                        let sidereal_time_opt = Self::availability_from_native_result(
                            mount.get_sidereal_time().await,
                            mount_status_field::SIDEREAL_TIME,
                            &mut availability,
                        );

                        // ASCOM wrapper does not yet expose AtHome — record as Unsupported
                        // rather than fabricating false. Driver work tracked separately.
                        availability.insert(
                            mount_status_field::AT_HOME.to_string(),
                            FieldAvailability::Unsupported,
                        );

                        let capabilities = match mount.get_capabilities().await {
                            Ok(caps) => caps,
                            Err(err) => {
                                warn!(
                                    "Failed to query ASCOM mount capabilities for {}: {}. Marking capabilities unavailable.",
                                    device_id, err
                                );
                                crate::ascom_wrapper_mount::AscomMountCapabilities::default()
                            }
                        };

                        let (tracking_rate_opt, can_set_tracking_rate) = match mount
                            .get_tracking_rate()
                            .await
                        {
                            Ok(rate) => {
                                availability.insert(
                                    mount_status_field::TRACKING_RATE.to_string(),
                                    FieldAvailability::Available,
                                );
                                (Some(Self::tracking_rate_from_native(rate)), true)
                            }
                            Err(nightshade_native::traits::NativeError::NotSupported) => {
                                availability.insert(
                                    mount_status_field::TRACKING_RATE.to_string(),
                                    FieldAvailability::Unsupported,
                                );
                                (None, false)
                            }
                            Err(err) => {
                                availability.insert(
                                    mount_status_field::TRACKING_RATE.to_string(),
                                    FieldAvailability::Error(err.to_string()),
                                );
                                (None, false)
                            }
                        };

                        return Ok(MountStatus {
                            connected: true,
                            tracking,
                            slewing,
                            parked,
                            at_home: None,
                            side_of_pier: side_of_pier_opt,
                            right_ascension: ra,
                            declination: dec,
                            altitude: alt_opt,
                            azimuth: az_opt,
                            sidereal_time: sidereal_time_opt,
                            tracking_rate: tracking_rate_opt,
                            can_park: capabilities.can_park,
                            can_slew: capabilities.can_slew,
                            can_sync: capabilities.can_sync,
                            can_pulse_guide: capabilities.can_pulse_guide,
                            can_set_tracking_rate,
                            availability,
                        });
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    // Required fields propagate read failures — these are not optional.
                    let (ra, dec) = mount.get_coordinates().await.map_err(|e| e.to_string())?;
                    let tracking = mount.get_tracking().await.map_err(|e| e.to_string())?;
                    let slewing = mount.is_slewing().await.map_err(|e| e.to_string())?;
                    let (parked, can_park) = match mount.is_parked().await {
                        Ok(p) => (p, true),
                        Err(nightshade_native::traits::NativeError::NotSupported) => (false, false),
                        Err(e) => {
                            return Err(format!(
                                "Failed to read native mount parked state for {}: {}",
                                device_id, e
                            ));
                        }
                    };

                    let mut availability: HashMap<String, FieldAvailability> = HashMap::new();

                    // get_side_of_pier on `NativeMount` returns Unknown rather than Err
                    // for unsupported mounts (e.g. SkyWatcher), so distinguish here:
                    // Unknown → Unsupported availability; East/West → Available.
                    let side_of_pier_opt = match mount.get_side_of_pier().await {
                        Ok(nightshade_native::traits::PierSide::Unknown) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Unsupported,
                            );
                            None
                        }
                        Ok(other) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Available,
                            );
                            Some(Self::pier_side_from_native(other))
                        }
                        Err(nightshade_native::traits::NativeError::NotSupported) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Unsupported,
                            );
                            None
                        }
                        Err(e) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Error(e.to_string()),
                            );
                            None
                        }
                    };

                    // Native drivers report Err(NotSupported) explicitly for alt/az and
                    // sidereal time on protocols that lack them (e.g. SkyWatcher, LX200).
                    let alt_az_pair = Self::availability_from_native_result(
                        mount.get_alt_az().await,
                        // Use ALTITUDE as primary key; AZIMUTH mirror is set below.
                        mount_status_field::ALTITUDE,
                        &mut availability,
                    );
                    // Mirror availability onto the AZIMUTH key — they share a single call.
                    let alt_avail = availability
                        .get(mount_status_field::ALTITUDE)
                        .cloned()
                        .unwrap_or(FieldAvailability::Available);
                    availability
                        .insert(mount_status_field::AZIMUTH.to_string(), alt_avail);
                    let (alt_opt, az_opt) = match alt_az_pair {
                        Some((a, z)) => (Some(a), Some(z)),
                        None => (None, None),
                    };

                    let sidereal_time_opt = Self::availability_from_native_result(
                        mount.get_sidereal_time().await,
                        mount_status_field::SIDEREAL_TIME,
                        &mut availability,
                    );

                    // Native mount trait does not currently surface AtHome.
                    availability.insert(
                        mount_status_field::AT_HOME.to_string(),
                        FieldAvailability::Unsupported,
                    );

                    let tracking_rate_opt = Self::availability_from_native_result(
                        mount.get_tracking_rate().await,
                        mount_status_field::TRACKING_RATE,
                        &mut availability,
                    )
                    .map(Self::tracking_rate_from_native);

                    return Ok(MountStatus {
                        connected: true,
                        tracking,
                        slewing,
                        parked,
                        at_home: None,
                        side_of_pier: side_of_pier_opt,
                        right_ascension: ra,
                        declination: dec,
                        altitude: alt_opt,
                        azimuth: az_opt,
                        sidereal_time: sidereal_time_opt,
                        tracking_rate: tracking_rate_opt,
                        can_park,
                        can_slew: mount.can_slew(),
                        can_sync: mount.can_sync(),
                        can_pulse_guide: mount.can_pulse_guide(),
                        can_set_tracking_rate: mount.can_set_tracking_rate(),
                        availability,
                    });
                }
                Err("Native mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    // Required fields propagate read failures.
                    let ra = mount.right_ascension().await.map_err(|e| {
                        format!("Failed to read Alpaca mount RA for {}: {}", device_id, e)
                    })?;
                    let dec = mount.declination().await.map_err(|e| {
                        format!("Failed to read Alpaca mount Dec for {}: {}", device_id, e)
                    })?;
                    let tracking = mount.tracking().await.map_err(|e| {
                        format!("Failed to read Alpaca mount tracking for {}: {}", device_id, e)
                    })?;
                    let slewing = mount.slewing().await.map_err(|e| {
                        format!("Failed to read Alpaca mount slewing for {}: {}", device_id, e)
                    })?;
                    let parked = mount.at_park().await.map_err(|e| {
                        format!("Failed to read Alpaca mount at_park for {}: {}", device_id, e)
                    })?;

                    let mut availability: HashMap<String, FieldAvailability> = HashMap::new();

                    // Alpaca returns Result<_, String>; we cannot reliably distinguish
                    // "PropertyNotImplemented" from a transient HTTP failure without
                    // parsing the error message. Treat all failures as Error so callers
                    // see the underlying reason verbatim. UI can match on the prefix
                    // "PropertyNotImplemented" if it wants to render Unsupported.
                    let alt_opt = Self::availability_from_string_result(
                        mount.altitude().await,
                        mount_status_field::ALTITUDE,
                        &mut availability,
                    );
                    let az_opt = Self::availability_from_string_result(
                        mount.azimuth().await,
                        mount_status_field::AZIMUTH,
                        &mut availability,
                    );
                    let at_home_opt = Self::availability_from_string_result(
                        mount.at_home().await,
                        mount_status_field::AT_HOME,
                        &mut availability,
                    );
                    let sidereal_time_opt = Self::availability_from_string_result(
                        mount.sidereal_time().await,
                        mount_status_field::SIDEREAL_TIME,
                        &mut availability,
                    );

                    let side_of_pier_opt = match mount.side_of_pier().await {
                        Ok(nightshade_alpaca::PierSide::Unknown) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Unsupported,
                            );
                            None
                        }
                        Ok(other) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Available,
                            );
                            Some(match other {
                                nightshade_alpaca::PierSide::East => crate::device::PierSide::East,
                                nightshade_alpaca::PierSide::West => crate::device::PierSide::West,
                                nightshade_alpaca::PierSide::Unknown => {
                                    crate::device::PierSide::Unknown
                                }
                            })
                        }
                        Err(e) => {
                            availability.insert(
                                mount_status_field::SIDE_OF_PIER.to_string(),
                                FieldAvailability::Error(e),
                            );
                            None
                        }
                    };

                    let (can_park, can_slew, can_sync, can_pulse_guide) =
                        match mount.get_capabilities().await {
                            Ok(caps) => (
                                caps.can_park,
                                caps.can_slew,
                                caps.can_sync,
                                caps.can_pulse_guide,
                            ),
                            Err(e) => {
                                warn!(
                                    "Failed to query Alpaca mount capabilities for {}: {}. Marking capabilities unsupported.",
                                    device_id, e
                                );
                                (false, false, false, false)
                            }
                        };
                    let can_set_tracking_rate = mount.can_set_tracking().await.unwrap_or(false);

                    let tracking_rate_opt = match mount.tracking_rate().await {
                        Ok(rate) => {
                            availability.insert(
                                mount_status_field::TRACKING_RATE.to_string(),
                                FieldAvailability::Available,
                            );
                            Some(match rate {
                                nightshade_alpaca::DriveRate::Sidereal => TrackingRate::Sidereal,
                                nightshade_alpaca::DriveRate::Lunar => TrackingRate::Lunar,
                                nightshade_alpaca::DriveRate::Solar => TrackingRate::Solar,
                                nightshade_alpaca::DriveRate::King => TrackingRate::King,
                            })
                        }
                        Err(e) => {
                            availability.insert(
                                mount_status_field::TRACKING_RATE.to_string(),
                                FieldAvailability::Error(e),
                            );
                            None
                        }
                    };

                    return Ok(MountStatus {
                        connected: true,
                        tracking,
                        slewing,
                        parked,
                        at_home: at_home_opt,
                        side_of_pier: side_of_pier_opt,
                        right_ascension: ra,
                        declination: dec,
                        altitude: alt_opt,
                        azimuth: az_opt,
                        sidereal_time: sidereal_time_opt,
                        tracking_rate: tracking_rate_opt,
                        can_park,
                        can_slew,
                        can_sync,
                        can_pulse_guide,
                        can_set_tracking_rate,
                        availability,
                    });
                }
                Err("Alpaca mount not connected".to_string())
            }
            DriverType::Indi => {
                let (host, port, device_name) = Self::parse_indi_device_id(device_id)?;
                let server_key = format!("{}:{}", host, port);
                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);
                    let (ra, dec) = mount.get_coordinates().await.map_err(|e| {
                        format!(
                            "Failed to read INDI mount coordinates for {}: {}",
                            device_id, e
                        )
                    })?;
                    let tracking = mount.try_is_tracking().await.map_err(|e| {
                        format!("Failed to read INDI mount tracking for {}: {}", device_id, e)
                    })?;
                    let slewing = mount.try_is_slewing().await.map_err(|e| {
                        format!("Failed to read INDI mount slewing for {}: {}", device_id, e)
                    })?;
                    let parked = mount.try_is_parked().await.map_err(|e| {
                        format!("Failed to read INDI mount parked state for {}: {}", device_id, e)
                    })?;

                    let mut availability: HashMap<String, FieldAvailability> = HashMap::new();

                    let (alt_opt, az_opt) = match mount.get_horizontal_coordinates().await {
                        Ok((a, z)) => {
                            availability.insert(
                                mount_status_field::ALTITUDE.to_string(),
                                FieldAvailability::Available,
                            );
                            availability.insert(
                                mount_status_field::AZIMUTH.to_string(),
                                FieldAvailability::Available,
                            );
                            (Some(a), Some(z))
                        }
                        Err(e) => {
                            availability.insert(
                                mount_status_field::ALTITUDE.to_string(),
                                FieldAvailability::Error(e.clone()),
                            );
                            availability.insert(
                                mount_status_field::AZIMUTH.to_string(),
                                FieldAvailability::Error(e),
                            );
                            (None, None)
                        }
                    };

                    let locked = client.read().await;
                    let (can_park, can_slew, can_sync, can_pulse_guide) = {
                        let can_park = locked
                            .get_switch(&device_name, "TELESCOPE_PARK", "PARK")
                            .await
                            .is_some()
                            || locked
                                .get_switch(&device_name, "TELESCOPE_PARK", "UNPARK")
                                .await
                                .is_some();
                        let can_slew = locked
                            .get_switch(&device_name, "ON_COORD_SET", "SLEW")
                            .await
                            .is_some();
                        let can_sync = locked
                            .get_switch(&device_name, "ON_COORD_SET", "SYNC")
                            .await
                            .is_some();
                        let can_pulse_guide = locked
                            .get_switch(&device_name, "TELESCOPE_MOTION_NS", "MOTION_NORTH")
                            .await
                            .is_some()
                            && locked
                                .get_switch(
                                    &device_name,
                                    "TELESCOPE_MOTION_NS",
                                    "MOTION_SOUTH",
                                )
                                .await
                                .is_some()
                            && locked
                                .get_switch(&device_name, "TELESCOPE_MOTION_WE", "MOTION_EAST")
                                .await
                                .is_some()
                            && locked
                                .get_switch(&device_name, "TELESCOPE_MOTION_WE", "MOTION_WEST")
                                .await
                                .is_some();
                        (can_park, can_slew, can_sync, can_pulse_guide)
                    };
                    let (tracking_rate_native, can_set_tracking_rate) =
                        Self::indi_mount_tracking_rate(&locked, &device_name).await;
                    let tracking_rate_opt = if can_set_tracking_rate {
                        availability.insert(
                            mount_status_field::TRACKING_RATE.to_string(),
                            FieldAvailability::Available,
                        );
                        Some(tracking_rate_native)
                    } else {
                        // INDI helper currently signals "no tracking-rate property" by
                        // returning false for the second tuple element; treat that as
                        // Unsupported rather than asserting Sidereal.
                        availability.insert(
                            mount_status_field::TRACKING_RATE.to_string(),
                            FieldAvailability::Unsupported,
                        );
                        None
                    };

                    // INDI does not standardise an at-home property, and TIME_LST is
                    // optional — record both as Unsupported until per-driver support
                    // can be added.
                    availability.insert(
                        mount_status_field::AT_HOME.to_string(),
                        FieldAvailability::Unsupported,
                    );
                    availability.insert(
                        mount_status_field::SIDEREAL_TIME.to_string(),
                        FieldAvailability::Unsupported,
                    );
                    // Pier side recovery from INDI requires per-driver heuristics; mark
                    // Unsupported for now so the sequencer refuses meridian flips.
                    availability.insert(
                        mount_status_field::SIDE_OF_PIER.to_string(),
                        FieldAvailability::Unsupported,
                    );

                    return Ok(MountStatus {
                        connected: true,
                        tracking,
                        slewing,
                        parked,
                        at_home: None,
                        side_of_pier: None,
                        right_ascension: ra,
                        declination: dec,
                        altitude: alt_opt,
                        azimuth: az_opt,
                        sidereal_time: None,
                        tracking_rate: tracking_rate_opt,
                        can_park,
                        can_slew,
                        can_sync,
                        can_pulse_guide,
                        can_set_tracking_rate,
                        availability,
                    });
                }
                Err(format!("INDI client not connected for {}", server_key))
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    /// Convert a `Result<T, NativeError>` into `(Option<T>, FieldAvailability)`,
    /// inserting the availability entry under `field` and returning the value.
    ///
    /// Used by `mount_get_status` so each per-field branch shrinks to one call
    /// instead of duplicating the same availability/log scaffolding.
    fn availability_from_native_result<T>(
        result: Result<T, nightshade_native::traits::NativeError>,
        field: &'static str,
        availability: &mut HashMap<String, FieldAvailability>,
    ) -> Option<T> {
        match result {
            Ok(v) => {
                availability.insert(field.to_string(), FieldAvailability::Available);
                Some(v)
            }
            Err(nightshade_native::traits::NativeError::NotSupported) => {
                availability.insert(field.to_string(), FieldAvailability::Unsupported);
                None
            }
            Err(e) => {
                availability.insert(field.to_string(), FieldAvailability::Error(e.to_string()));
                None
            }
        }
    }

    /// Same shape as `availability_from_native_result` but for drivers that
    /// surface errors as plain `String` (Alpaca, INDI). Without a typed
    /// "unsupported" variant we always classify failures as `Error(reason)`.
    fn availability_from_string_result<T>(
        result: Result<T, String>,
        field: &'static str,
        availability: &mut HashMap<String, FieldAvailability>,
    ) -> Option<T> {
        match result {
            Ok(v) => {
                availability.insert(field.to_string(), FieldAvailability::Available);
                Some(v)
            }
            Err(e) => {
                availability.insert(field.to_string(), FieldAvailability::Error(e));
                None
            }
        }
    }

    fn pier_side_from_native(side: nightshade_native::traits::PierSide) -> crate::device::PierSide {
        match side {
            nightshade_native::traits::PierSide::East => crate::device::PierSide::East,
            nightshade_native::traits::PierSide::West => crate::device::PierSide::West,
            nightshade_native::traits::PierSide::Unknown => crate::device::PierSide::Unknown,
        }
    }

    fn tracking_rate_from_native(rate: nightshade_native::traits::TrackingRate) -> TrackingRate {
        match rate {
            nightshade_native::traits::TrackingRate::Sidereal => TrackingRate::Sidereal,
            nightshade_native::traits::TrackingRate::Lunar => TrackingRate::Lunar,
            nightshade_native::traits::TrackingRate::Solar => TrackingRate::Solar,
            nightshade_native::traits::TrackingRate::King => TrackingRate::King,
            nightshade_native::traits::TrackingRate::Custom => TrackingRate::Custom,
        }
    }

    pub async fn mount_set_tracking_rate(&self, device_id: &str, rate: i32) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount
                            .set_tracking_rate_raw(rate)
                            .await
                            .map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let mut native_mounts = self.native_mounts.write().await;
                if let Some(mount) = native_mounts.get_mut(device_id) {
                    // Convert i32 rate to TrackingRate enum
                    let tracking_rate = match rate {
                        0 => nightshade_native::traits::TrackingRate::Sidereal,
                        1 => nightshade_native::traits::TrackingRate::Lunar,
                        2 => nightshade_native::traits::TrackingRate::Solar,
                        3 => nightshade_native::traits::TrackingRate::King,
                        4 => nightshade_native::traits::TrackingRate::Custom,
                        _ => return Err(format!("Invalid tracking rate: {}", rate)),
                    };
                    return mount
                        .set_tracking_rate(tracking_rate)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err("Native mount not connected".to_string())
            }
            _ => Err("Setting tracking rate is not supported by this driver type".to_string()),
        }
    }

    pub async fn mount_get_tracking_rate(&self, device_id: &str) -> Result<i32, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    if let Some(mount) = mounts.get(device_id) {
                        let mount = mount.read().await;
                        return mount
                            .get_tracking_rate_raw()
                            .await
                            .map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Native => {
                let native_mounts = self.native_mounts.read().await;
                if let Some(mount) = native_mounts.get(device_id) {
                    let rate = mount.get_tracking_rate().await.map_err(|e| e.to_string())?;
                    return Ok(rate as i32);
                }
                Err("Native mount not connected".to_string())
            }
            _ => Err("Getting tracking rate is not supported by this driver type".to_string()),
        }
    }

    /// Move an axis at the specified rate (degrees/second)
    /// axis: 0=RA/Azimuth (primary), 1=Dec/Altitude (secondary)
    /// rate: degrees per second (positive = N/E, negative = S/W), 0 to stop
    pub async fn mount_move_axis(
        &self,
        device_id: &str,
        axis: i32,
        rate: f64,
    ) -> Result<(), String> {
        tracing::debug!(
            "mount_move_axis called: device_id={}, axis={}, rate={}",
            device_id,
            axis,
            rate
        );

        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| {
                tracing::error!(
                    "mount_move_axis: Device not found in devices map: {}",
                    device_id
                );
                format!("Device not found: {}", device_id)
            })?;

        tracing::debug!(
            "mount_move_axis: Found device with driver_type={:?}",
            info.driver_type
        );

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let mounts = self.ascom_mounts.read().await;
                    tracing::debug!("mount_move_axis: ascom_mounts contains {} entries", mounts.len());
                    if let Some(mount) = mounts.get(device_id) {
                        let mut mount = mount.write().await;
                        return mount.move_axis(axis, rate).await.map_err(|e| {
                            tracing::error!("mount_move_axis ASCOM error: {}", e);
                            e.to_string()
                        });
                    } else {
                        tracing::error!("mount_move_axis: Mount {} not found in ascom_mounts. Available: {:?}",
                            device_id, mounts.keys().collect::<Vec<_>>());
                    }
                }
                Err("ASCOM mount not connected".to_string())
            }
            DriverType::Alpaca => {
                let mounts = self.alpaca_mounts.read().await;
                if let Some(mount) = mounts.get(device_id) {
                    tracing::debug!("mount_move_axis: Calling Alpaca move_axis");
                    return mount.move_axis(axis, rate).await.map_err(|e| {
                        tracing::error!("mount_move_axis Alpaca error: {}", e);
                        e
                    });
                }
                tracing::error!("mount_move_axis: Alpaca mount {} not connected", device_id);
                Err(format!("Alpaca mount {} not connected", device_id))
            }
            DriverType::Indi => {
                // INDI uses directional movement (NSEW) instead of axis rates
                // We need to map axis/rate to directional commands
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port = parts[2];
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let mount = nightshade_indi::IndiMount::new(client.clone(), &device_name);

                        // Convert axis/rate to directional movement
                        // axis 0 = RA/Az (East/West), axis 1 = Dec/Alt (North/South)
                        // rate > 0 = North/East, rate < 0 = South/West, rate = 0 = stop
                        if axis == 0 {
                            // RA/Azimuth axis
                            if rate > 0.0 {
                                return mount.move_east(true).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (move east): {}", e);
                                    e.to_string()
                                });
                            } else if rate < 0.0 {
                                return mount.move_west(true).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (move west): {}", e);
                                    e.to_string()
                                });
                            } else {
                                // Stop both directions
                                let _ = mount.move_east(false).await;
                                return mount.move_west(false).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (stop RA): {}", e);
                                    e.to_string()
                                });
                            }
                        } else {
                            // Dec/Altitude axis
                            if rate > 0.0 {
                                return mount.move_north(true).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (move north): {}", e);
                                    e.to_string()
                                });
                            } else if rate < 0.0 {
                                return mount.move_south(true).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (move south): {}", e);
                                    e.to_string()
                                });
                            } else {
                                // Stop both directions
                                let _ = mount.move_north(false).await;
                                return mount.move_south(false).await.map_err(|e| {
                                    tracing::error!("mount_move_axis INDI error (stop Dec): {}", e);
                                    e.to_string()
                                });
                            }
                        }
                    }
                    tracing::error!("mount_move_axis: INDI client not connected for {}", server_key);
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err(format!("Invalid INDI device ID format: {}", device_id))
            }
            DriverType::Native => {
                tracing::warn!("mount_move_axis: Native SDK does not support mount axis movement");
                Err("Native SDK does not support mount axis movement".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    // =========================================================================
    // Focuser Control
    // =========================================================================

    pub async fn focuser_move_abs(&self, device_id: &str, position: i32) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;
        drop(devices);

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let mut focuser = focuser.write().await;
                        return focuser.move_to(position).await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let mut native_focusers = self.native_focusers.write().await;
                if let Some(focuser) = native_focusers.get_mut(device_id) {
                    return focuser.move_to(position).await.map_err(|e| e.to_string());
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    return focuser
                        .move_to_typed(position)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port in INDI device ID")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
                        return focuser.move_to(position).await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn focuser_move_rel(&self, device_id: &str, steps: i32) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;
        drop(devices);

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let mut focuser = focuser.write().await;
                        return focuser.move_relative(steps).await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let mut native_focusers = self.native_focusers.write().await;
                if let Some(focuser) = native_focusers.get_mut(device_id) {
                    return focuser.move_relative(steps).await.map_err(|e| e.to_string());
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                // Alpaca focusers only support absolute positioning, so we compute target position
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    let current_position = focuser.position().await?;
                    let target_position = current_position + steps;
                    return focuser
                        .move_to_typed(target_position)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port in INDI device ID")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
                        return focuser.move_relative(steps).await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn focuser_halt(&self, device_id: &str) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;
        drop(devices);

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let mut focuser = focuser.write().await;
                        return focuser.halt().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let mut native_focusers = self.native_focusers.write().await;
                if let Some(focuser) = native_focusers.get_mut(device_id) {
                    return focuser.halt().await.map_err(|e| e.to_string());
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    return focuser.halt().await;
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port in INDI device ID")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
                        return focuser.abort_motion().await.map_err(|e| e.to_string());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
// Fallback logic for devices not matching specific driver types
            // This is primarily for the catch-all pattern required by match
            // but in practice DriverType is exhaustive for supported devices.
            // Keeping this arm for safety but returning an error is correct.
        }
    }

    pub async fn focuser_get_position(&self, device_id: &str) -> Result<i32, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let focuser = focuser.read().await;
                        return focuser.get_position().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let native_focusers = self.native_focusers.read().await;
                if let Some(focuser) = native_focusers.get(device_id) {
                    return focuser.get_position().await.map_err(|e| e.to_string());
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    return focuser.position().await;
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port in INDI device ID")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
                        return focuser.get_position().await;
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
// Fallback logic for devices not matching specific driver types
        }
    }

    pub async fn focuser_is_moving(&self, device_id: &str) -> Result<bool, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let focuser = focuser.read().await;
                        return focuser.is_moving().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let native_focusers = self.native_focusers.read().await;
                if let Some(focuser) = native_focusers.get(device_id) {
                    return focuser.is_moving().await.map_err(|e| e.to_string());
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    return focuser.is_moving().await;
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
                        return Ok(focuser.is_moving().await);
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
// Fallback logic for devices not matching specific driver types
        }
    }

    pub async fn focuser_is_absolute(&self, device_id: &str) -> Result<bool, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;
        drop(devices);

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let focuser = focuser.read().await;
                        return focuser.is_absolute().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => Ok(true),
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    return focuser.absolute().await;
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let client = client.read().await;
                        return Ok(client
                            .get_property_state(&device_name, "ABS_FOCUS_POSITION")
                            .await
                            .is_some());
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn focuser_get_temp(&self, device_id: &str) -> Result<Option<f64>, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let focuser = focuser.read().await;
                        return focuser.get_temperature().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let native_focusers = self.native_focusers.read().await;
                if let Some(focuser) = native_focusers.get(device_id) {
                    return focuser.get_temperature().await.map_err(|e| e.to_string());
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    // Alpaca temperature() returns f64, wrap in Some for consistency
                    return focuser.temperature().await.map(Some);
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port in INDI device ID")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
                        // Temperature might not be available on all focusers
                        match focuser.get_temperature().await {
                            Ok(temp) => return Ok(Some(temp)),
                            Err(_) => return Ok(None), // Temperature not available
                        }
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn focuser_get_details(&self, device_id: &str) -> Result<(i32, f64), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let focusers = self.ascom_focusers.read().await;
                    if let Some(focuser) = focusers.get(device_id) {
                        let focuser = focuser.read().await;
                        return Ok((focuser.get_max_position(), focuser.get_step_size()));
                    }
                }
                Err("ASCOM focuser not connected".to_string())
            }
            DriverType::Native => {
                let native_focusers = self.native_focusers.read().await;
                if let Some(focuser) = native_focusers.get(device_id) {
                    return Ok((focuser.get_max_position(), focuser.get_step_size()));
                }
                Err("Native focuser not connected".to_string())
            }
            DriverType::Alpaca => {
                let alpaca_focusers = self.alpaca_focusers.read().await;
                if let Some(focuser) = alpaca_focusers.get(device_id) {
                    let max_step = focuser.max_step().await?;
                    let step_size = match focuser.step_size().await {
                        Ok(s) => s,
                        Err(e) => {
                            warn!("Failed to read Alpaca focuser step_size for {}: {}. Using default 1.0.", device_id, e);
                            1.0
                        }
                    };
                    return Ok((max_step, step_size));
                }
                Err("Alpaca focuser not connected".to_string())
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port in INDI device ID")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let client = client.read().await;

                        // Try to get max position from FOCUS_MAX property (common INDI standard)
                        // If unavailable, report unknown (0) instead of inventing a fake limit.
                        let max_position = match client.get_number(&device_name, "FOCUS_MAX", "FOCUS_MAX_VALUE").await {
                            Some(v) => v as i32,
                            None => {
                                warn!(
                                    "Failed to read INDI focuser max position for {}: property not available. Reporting unknown max position.",
                                    device_id
                                );
                                0
                            }
                        };

                        // Step size is not universally standardized in INDI
                        // Report unknown (0.0) when unavailable rather than assuming 1.0.
                        let step_size = match client.get_number(&device_name, "FOCUS_STEP", "FOCUS_STEP_VALUE").await {
                            Some(s) => s,
                            None => {
                                warn!(
                                    "Failed to read INDI focuser step size for {}: property not available. Reporting unknown step size.",
                                    device_id
                                );
                                0.0
                            }
                        };

                        return Ok((max_position, step_size));
                    }
                    return Err(format!("INDI client not connected for {}", server_key));
                }
                Err("Invalid INDI device ID format".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    // =========================================================================
    // Filter Wheel Control
    // =========================================================================

    pub async fn filter_wheel_set_position(
        &self,
        device_id: &str,
        position: i32,
    ) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;
        drop(devices);

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let wheels = self.ascom_filter_wheels.read().await;
                    if let Some(wheel) = wheels.get(device_id) {
                        let mut wheel = wheel.write().await;
                        return wheel.move_to_position(position).await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM filter wheel not connected".to_string())
            }
            DriverType::Native => {
                let mut native_filter_wheels = self.native_filter_wheels.write().await;
                if let Some(wheel) = native_filter_wheels.get_mut(device_id) {
                    return wheel.move_to_position(position).await.map_err(|e| e.to_string());
                }
                Err("Native filter wheel not connected".to_string())
            }
            DriverType::Alpaca => {
                let wheels = self.alpaca_filter_wheels.read().await;
                if let Some(wheel) = wheels.get(device_id) {
                    return wheel.set_position(position).await;
                }
                Err(format!("Alpaca filter wheel {} not found", device_id))
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID format".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    // INDI filter slots are 1-based
                    return locked.set_number(&device_name, "FILTER_SLOT", "FILTER_SLOT_VALUE", position as f64).await.map_err(|e| e.to_string());
                }
                Err("INDI filter wheel not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }

            // Fallback logic for devices not matching specific driver types
            // This is primarily for the catch-all pattern required by match
            // but in practice DriverType is exhaustive for supported devices.
            // Keeping this arm for safety but returning an error is correct.
        }
    }

    pub async fn filter_wheel_get_position(&self, device_id: &str) -> Result<i32, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            let info = devices
                .get(device_id)
                .map(|d| d.info.clone())
                .ok_or_else(|| format!("Device not found: {}", device_id))?;
            info.driver_type
        }; // devices lock dropped here before acquiring other locks

        match driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let wheels = self.ascom_filter_wheels.read().await;
                    if let Some(wheel) = wheels.get(device_id) {
                        let wheel = wheel.read().await;
                        return wheel.get_position().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM filter wheel not connected".to_string())
            }
            DriverType::Native => {
                let native_filter_wheels = self.native_filter_wheels.read().await;
                if let Some(wheel) = native_filter_wheels.get(device_id) {
                    return wheel.get_position().await.map_err(|e| e.to_string());
                }
                Err("Native filter wheel not connected".to_string())
            }
            DriverType::Alpaca => {
                let wheels = self.alpaca_filter_wheels.read().await;
                if let Some(wheel) = wheels.get(device_id) {
                    return wheel.position().await;
                }
                Err(format!("Alpaca filter wheel {} not found", device_id))
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID format".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    // INDI filter slots are 1-based, convert to 0-based for consistency
                    if let Some(pos) = locked.get_number(&device_name, "FILTER_SLOT", "FILTER_SLOT_VALUE").await {
                        return Ok((pos as i32) - 1);
                    }
                    return Err("Could not read filter position from INDI device".to_string());
                }
                Err("INDI filter wheel not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn filter_wheel_is_moving(&self, device_id: &str) -> Result<bool, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            let info = devices
                .get(device_id)
                .map(|d| d.info.clone())
                .ok_or_else(|| format!("Device not found: {}", device_id))?;
            info.driver_type
        }; // devices lock dropped here

        match driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let wheels = self.ascom_filter_wheels.read().await;
                    if let Some(wheel) = wheels.get(device_id) {
                        let wheel = wheel.read().await;
                        return wheel.is_moving().await.map_err(|e| e.to_string());
                    }
                }
                Err("ASCOM filter wheel not connected".to_string())
            }
            DriverType::Native => {
                let native_filter_wheels = self.native_filter_wheels.read().await;
                if let Some(wheel) = native_filter_wheels.get(device_id) {
                    return wheel.is_moving().await.map_err(|e| e.to_string());
                }
                Err("Native filter wheel not connected".to_string())
            }
            DriverType::Alpaca => {
                let wheels = self.alpaca_filter_wheels.read().await;
                if let Some(wheel) = wheels.get(device_id) {
                    // Alpaca filter wheels return -1 for position when moving
                    let pos = wheel.position().await?;
                    return Ok(pos == -1);
                }
                Err(format!("Alpaca filter wheel {} not found", device_id))
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID format".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    // INDI uses property busy state to indicate movement
                    return Ok(locked.is_property_busy(&device_name, "FILTER_SLOT").await);
                }
                Err("INDI filter wheel not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    pub async fn filter_wheel_get_config(
        &self,
        device_id: &str,
    ) -> Result<(i32, Vec<String>), String> {
        tracing::debug!(
            "filter_wheel_get_config: Looking up device_id='{}'",
            device_id
        );

        let devices = self.devices.read().await;
        let device_keys: Vec<_> = devices.keys().collect();
        tracing::debug!(
            "filter_wheel_get_config: Available devices in registry: {:?}",
            device_keys
        );

        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;
        tracing::debug!(
            "filter_wheel_get_config: Found device with driver_type={:?}",
            info.driver_type
        );
        drop(devices); // Release the lock before async operations

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let wheels = self.ascom_filter_wheels.read().await;
                    let ascom_keys: Vec<_> = wheels.keys().collect();
                    tracing::debug!("filter_wheel_get_config: Looking for '{}' in ascom_filter_wheels: {:?}", device_id, ascom_keys);

                    if let Some(wheel) = wheels.get(device_id) {
                        let wheel = wheel.read().await;
                        let names = wheel.get_filter_names().await.map_err(|e| e.to_string())?;
                        let count = names.len() as i32;
                        return Ok((count, names));
                    }
                    tracing::error!("filter_wheel_get_config: ASCOM filter wheel '{}' not found in ascom_filter_wheels map!", device_id);
                }
                Err("ASCOM filter wheel not connected".to_string())
            }
            DriverType::Alpaca => {
                let wheels = self.alpaca_filter_wheels.read().await;
                if let Some(wheel) = wheels.get(device_id) {
                    let names = wheel.names().await?;
                    let count = names.len() as i32;
                    return Ok((count, names));
                }
                Err(format!("Alpaca filter wheel {} not found", device_id))
            }
            DriverType::Indi => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() >= 4 {
                    let host = parts[1];
                    let port: u16 = parts[2].parse().map_err(|_| "Invalid port")?;
                    let device_name = parts[3..].join(":");
                    let server_key = format!("{}:{}", host, port);

                    let clients = self.indi_clients.read().await;
                    if let Some(client) = clients.get(&server_key) {
                        let locked_client = client.read().await;
                        let names = locked_client.get_filter_names(&device_name).await
                            .unwrap_or_else(|_| vec![]);
                        let count = names.len() as i32;
                        return Ok((count, names));
                    }
                }
                Err("INDI filter wheel not connected".to_string())
            }
            DriverType::Native => {
                let native_filter_wheels = self.native_filter_wheels.read().await;
                let native_keys: Vec<_> = native_filter_wheels.keys().collect();
                tracing::debug!("filter_wheel_get_config: Looking for '{}' in native_filter_wheels: {:?}", device_id, native_keys);

                if let Some(wheel) = native_filter_wheels.get(device_id) {
                    let count = wheel.get_filter_count();
                    let names = wheel.get_filter_names().await.map_err(|e| e.to_string())?;
                    tracing::info!("filter_wheel_get_config: Returning {} filter names: {:?}", count, names);
                    return Ok((count, names));
                }
                tracing::error!("filter_wheel_get_config: Native filter wheel '{}' not found in native_filter_wheels map!", device_id);
                Err("Native filter wheel not connected".to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    /// Set filter names on a filter wheel.
    /// This pushes user-defined filter names from the equipment profile to the hardware driver.
    pub async fn filter_wheel_set_filter_names(
        &self,
        device_id: &str,
        names: Vec<String>,
    ) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;
        drop(devices);

        tracing::info!(
            "filter_wheel_set_filter_names: Setting filter names for '{}': {:?}",
            device_id,
            names
        );

        match info.driver_type {
            DriverType::Native => {
                let mut native_filter_wheels = self.native_filter_wheels.write().await;
                if let Some(wheel) = native_filter_wheels.get_mut(device_id) {
                    for (i, name) in names.iter().enumerate() {
                        wheel.set_filter_name(i as i32, name.clone()).await.map_err(|e| e.to_string())?;
                    }
                    tracing::info!("filter_wheel_set_filter_names: Successfully set {} filter names", names.len());
                    return Ok(());
                }
                Err("Native filter wheel not connected".to_string())
            }
            DriverType::Ascom => {
                // ASCOM filter names are typically stored in the driver's configuration
                // Many ASCOM drivers don't support programmatic name setting
                let msg = "ASCOM filter names are managed by the driver and cannot be set programmatically";
                tracing::warn!("filter_wheel_set_filter_names: {}", msg);
                Err(msg.to_string())
            }
            DriverType::Alpaca => {
                // Alpaca filter names are typically read-only from the driver
                let msg = "Alpaca filter names are read-only and cannot be set programmatically";
                tracing::warn!("filter_wheel_set_filter_names: {}", msg);
                Err(msg.to_string())
            }
            DriverType::Indi => {
                // INDI filter names can be set via FILTER_NAME property
                let msg = "INDI filter name setting is unavailable in this manager path";
                tracing::warn!("filter_wheel_set_filter_names: {}", msg);
                Err(msg.to_string())
            }
            DriverType::Simulator => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
        }
    }

    // =========================================================================
    // Rotator Control
    // =========================================================================

    /// Get rotator position (sky angle in degrees)
    pub async fn rotator_get_position(&self, device_id: &str) -> Result<f64, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let rotators = self.alpaca_rotators.read().await;
                if let Some(rotator) = rotators.get(device_id) {
                    return rotator.position().await;
                }
                Err(format!("Alpaca rotator {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let rotators = self.ascom_rotators.read().await;
                    if let Some(rotator) = rotators.get(device_id) {
                        let rotator_guard = rotator.read().await;
                        return rotator_guard.position().await;
                    }
                    Err(format!("ASCOM rotator {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM is only available on Windows".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    if let Some(pos) = locked.get_number(&device_name, "ABS_ROTATOR_ANGLE", "ANGLE").await {
                        return Ok(pos);
                    }
                }
                Err("INDI rotator not connected".to_string())
            }
            Some(DriverType::Native) => {
                let native_rotators = self.native_rotators.read().await;
                if let Some(rotator) = native_rotators.get(device_id) {
                    return rotator.get_position().await.map_err(|e| e.to_string());
                }
                Err("Native rotator not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Move rotator to absolute sky position (degrees)
    pub async fn rotator_move_absolute(
        &self,
        device_id: &str,
        position: f64,
    ) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let rotators = self.alpaca_rotators.read().await;
                if let Some(rotator) = rotators.get(device_id) {
                    return rotator.move_absolute(position).await;
                }
                Err(format!("Alpaca rotator {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let rotators = self.ascom_rotators.read().await;
                    if let Some(rotator) = rotators.get(device_id) {
                        let rotator_guard = rotator.read().await;
                        return rotator_guard.move_absolute(position).await;
                    }
                    Err(format!("ASCOM rotator {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM is only available on Windows".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    return locked.set_number(&device_name, "ABS_ROTATOR_ANGLE", "ANGLE", position).await.map_err(|e| e.to_string());
                }
                Err("INDI rotator not connected".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_rotators = self.native_rotators.write().await;
                if let Some(rotator) = native_rotators.get_mut(device_id) {
                    return rotator.move_to(position).await.map_err(|e| e.to_string());
                }
                Err("Native rotator not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Halt rotator motion
    pub async fn rotator_halt(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let rotators = self.alpaca_rotators.read().await;
                if let Some(rotator) = rotators.get(device_id) {
                    return rotator.halt().await;
                }
                Err(format!("Alpaca rotator {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let rotators = self.ascom_rotators.read().await;
                    if let Some(rotator) = rotators.get(device_id) {
                        let rotator_guard = rotator.read().await;
                        return rotator_guard.halt().await;
                    }
                    Err(format!("ASCOM rotator {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM is only available on Windows".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    return locked.set_switch(&device_name, "ROTATOR_ABORT_MOTION", "ABORT", true).await.map_err(|e| e.to_string());
                }
                Err("INDI rotator not connected".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_rotators = self.native_rotators.write().await;
                if let Some(rotator) = native_rotators.get_mut(device_id) {
                    return rotator.halt().await.map_err(|e| e.to_string());
                }
                Err("Native rotator not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Sync the reported rotator sky angle to `position` without moving the
    /// hardware. Used after a plate solve to align the driver's reported PA
    /// with the astrometric PA of the last frame. Why dispatch matches
    /// `rotator_move_absolute`: identical driver layout (Alpaca/ASCOM/INDI/
    /// Native) and lock acquisition rules.
    pub async fn rotator_sync(&self, device_id: &str, position: f64) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let rotators = self.alpaca_rotators.read().await;
                if let Some(rotator) = rotators.get(device_id) {
                    return rotator.sync(position).await;
                }
                Err(format!("Alpaca rotator {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let rotators = self.ascom_rotators.read().await;
                    if let Some(rotator) = rotators.get(device_id) {
                        let rotator_guard = rotator.read().await;
                        return rotator_guard.sync(position).await;
                    }
                    Err(format!("ASCOM rotator {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM is only available on Windows".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    // INDI standard property for syncing the reported angle
                    // without rotating: SYNC_ROTATOR_ANGLE/ANGLE.
                    return locked
                        .set_number(&device_name, "SYNC_ROTATOR_ANGLE", "ANGLE", position)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err("INDI rotator not connected".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_rotators = self.native_rotators.write().await;
                if let Some(rotator) = native_rotators.get_mut(device_id) {
                    return rotator.sync(position).await.map_err(|e| e.to_string());
                }
                Err("Native rotator not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Check if rotator is moving
    pub async fn rotator_is_moving(&self, device_id: &str) -> Result<bool, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let rotators = self.alpaca_rotators.read().await;
                if let Some(rotator) = rotators.get(device_id) {
                    return rotator.is_moving().await;
                }
                Err(format!("Alpaca rotator {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let rotators = self.ascom_rotators.read().await;
                    if let Some(rotator) = rotators.get(device_id) {
                        let rotator_guard = rotator.read().await;
                        return rotator_guard.is_moving().await;
                    }
                    Err(format!("ASCOM rotator {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM is only available on Windows".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    return Ok(locked.is_property_busy(&device_name, "ABS_ROTATOR_ANGLE").await);
                }
                Err("INDI rotator not connected".to_string())
            }
            Some(DriverType::Native) => {
                let native_rotators = self.native_rotators.read().await;
                if let Some(rotator) = native_rotators.get(device_id) {
                    return rotator.is_moving().await.map_err(|e| e.to_string());
                }
                Err("Native rotator not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    // =========================================================================
    // Dome Control
    // =========================================================================

    /// Open dome shutter
    pub async fn dome_open_shutter(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.open_shutter().await;
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.open_shutter().await.map_err(|e| e.to_string());
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    return locked.set_switch(&device_name, "DOME_SHUTTER", "SHUTTER_OPEN", true).await.map_err(|e| e.to_string());
                }
                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_domes = self.native_domes.write().await;
                if let Some(dome) = native_domes.get_mut(device_id) {
                    return dome.open_shutter().await.map_err(|e| e.to_string());
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Close dome shutter
    pub async fn dome_close_shutter(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.close_shutter().await;
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.close_shutter().await.map_err(|e| e.to_string());
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    return locked.set_switch(&device_name, "DOME_SHUTTER", "SHUTTER_CLOSE", true).await.map_err(|e| e.to_string());
                }
                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_domes = self.native_domes.write().await;
                if let Some(dome) = native_domes.get_mut(device_id) {
                    return dome.close_shutter().await.map_err(|e| e.to_string());
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Slew dome to azimuth
    pub async fn dome_slew_to_azimuth(&self, device_id: &str, azimuth: f64) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.slew_to_azimuth(azimuth).await;
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    return locked.set_number(&device_name, "ABS_DOME_POSITION", "DOME_ABSOLUTE_POSITION", azimuth).await.map_err(|e| e.to_string());
                }
                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.slew_to_azimuth(azimuth).await;
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_domes = self.native_domes.write().await;
                if let Some(dome) = native_domes.get_mut(device_id) {
                    return dome.slew_to_azimuth(azimuth).await.map_err(|e| e.to_string());
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Get dome azimuth
    pub async fn dome_get_azimuth(&self, device_id: &str) -> Result<f64, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.azimuth().await;
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    if let Some(az) = locked.get_number(&device_name, "ABS_DOME_POSITION", "DOME_ABSOLUTE_POSITION").await {
                        return Ok(az);
                    }
                }
                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.azimuth().await;
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Native) => {
                let native_domes = self.native_domes.read().await;
                if let Some(dome) = native_domes.get(device_id) {
                    return dome.get_azimuth().await.map_err(|e| e.to_string());
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Get dome shutter status
    pub async fn dome_get_shutter_status(&self, device_id: &str) -> Result<i32, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    let status = dome.shutter_status().await?;
                    return Ok(status as i32);
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.shutter_status().await;
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    // Check INDI shutter switches: 0=Open, 1=Closed, 4=Unknown
                    if locked.get_switch(&device_name, "DOME_SHUTTER", "SHUTTER_OPEN").await.unwrap_or(false) {
                        return Ok(0); // Open
                    } else if locked.get_switch(&device_name, "DOME_SHUTTER", "SHUTTER_CLOSE").await.unwrap_or(false) {
                        return Ok(1); // Closed
                    }
                }
                Ok(4) // Unknown/Error
            }
            Some(DriverType::Native) => {
                let native_domes = self.native_domes.read().await;
                if let Some(dome) = native_domes.get(device_id) {
                    let status = dome.get_shutter_status().await.map_err(|e| e.to_string())?;
                    // Convert ShutterState enum to i32: Open=0, Closed=1, Opening=2, Closing=3, Error=4, Unknown=5
                    let code = match status {
                        nightshade_native::traits::ShutterState::Open => 0,
                        nightshade_native::traits::ShutterState::Closed => 1,
                        nightshade_native::traits::ShutterState::Opening => 2,
                        nightshade_native::traits::ShutterState::Closing => 3,
                        nightshade_native::traits::ShutterState::Error => 4,
                        nightshade_native::traits::ShutterState::Unknown => 5,
                    };
                    return Ok(code);
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Park dome
    pub async fn dome_park(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.park().await;
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.park().await.map_err(|e| e.to_string());
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    return locked.set_switch(&device_name, "DOME_PARK", "PARK", true).await.map_err(|e| e.to_string());
                }
                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Native) => {
                let mut native_domes = self.native_domes.write().await;
                if let Some(dome) = native_domes.get_mut(device_id) {
                    return dome.park().await.map_err(|e| e.to_string());
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Check if dome is slewing
    pub async fn dome_is_slewing(&self, device_id: &str) -> Result<bool, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.slewing().await;
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;
                        return dome_guard.slewing().await.map_err(|e| e.to_string());
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    let az_busy = locked
                        .is_property_busy(&device_name, "ABS_DOME_POSITION")
                        .await;
                    let shutter_busy = locked.is_property_busy(&device_name, "DOME_SHUTTER").await;
                    return Ok(az_busy || shutter_busy);
                }
                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Native) => {
                let native_domes = self.native_domes.read().await;
                if let Some(dome) = native_domes.get(device_id) {
                    return dome.is_slewing().await.map_err(|e| e.to_string());
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    /// Get comprehensive dome status
    pub async fn dome_get_status(
        &self,
        device_id: &str,
    ) -> Result<crate::device::DomeStatus, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let domes = self.alpaca_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    // Get status from Alpaca dome
                    let alpaca_status = dome.get_status().await?;

                    // Query capabilities
                    let can_set_altitude = dome.can_set_altitude().await.map_err(|e| {
                        format!(
                            "Failed to query Alpaca dome can_set_altitude for {}: {}",
                            device_id, e
                        )
                    })?;
                    let can_set_azimuth = dome.can_set_azimuth().await.map_err(|e| {
                        format!(
                            "Failed to query Alpaca dome can_set_azimuth for {}: {}",
                            device_id, e
                        )
                    })?;
                    let can_set_shutter = dome.can_set_shutter().await.map_err(|e| {
                        format!(
                            "Failed to query Alpaca dome can_set_shutter for {}: {}",
                            device_id, e
                        )
                    })?;
                    let can_slave = dome.can_slave().await.map_err(|e| {
                        format!("Failed to query Alpaca dome can_slave for {}: {}", device_id, e)
                    })?;

                    return Ok(crate::device::DomeStatus {
                        connected: true,
                        azimuth: alpaca_status.azimuth,
                        altitude: alpaca_status.altitude,
                        shutter_status: match alpaca_status.shutter_status {
                            nightshade_alpaca::ShutterStatus::Open => crate::device::ShutterState::Open,
                            nightshade_alpaca::ShutterStatus::Closed => crate::device::ShutterState::Closed,
                            nightshade_alpaca::ShutterStatus::Opening => crate::device::ShutterState::Opening,
                            nightshade_alpaca::ShutterStatus::Closing => crate::device::ShutterState::Closing,
                            nightshade_alpaca::ShutterStatus::Error => crate::device::ShutterState::Error,
                        },
                        slewing: alpaca_status.slewing,
                        at_home: alpaca_status.at_home,
                        at_park: alpaca_status.at_park,
                        can_set_altitude,
                        can_set_azimuth,
                        can_set_shutter,
                        can_slave,
                        is_slaved: alpaca_status.slaved,
                    });
                }
                Err(format!("Alpaca dome {} not found", device_id))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let domes = self.ascom_domes.read().await;
                    if let Some(dome) = domes.get(device_id) {
                        let dome_guard = dome.read().await;

                        // Query all dome properties from ASCOM driver
                        let shutter_status_code = match dome_guard.shutter_status().await {
                            Ok(s) => s,
                            Err(e) => {
                                warn!("Failed to read ASCOM dome shutter_status for {}: {}. Using error code 4.", device_id, e);
                                4 // Error state
                            }
                        };
                        let slewing = dome_guard.slewing().await.map_err(|e| {
                            format!("Failed to read ASCOM dome slewing for {}: {}", device_id, e)
                        })?;
                        let at_park = dome_guard.at_park().await.map_err(|e| {
                            format!("Failed to read ASCOM dome at_park for {}: {}", device_id, e)
                        })?;

                        // Map ASCOM shutter status codes to ShutterState
                        let shutter_status = match shutter_status_code {
                            0 => crate::device::ShutterState::Open,
                            1 => crate::device::ShutterState::Closed,
                            2 => crate::device::ShutterState::Opening,
                            3 => crate::device::ShutterState::Closing,
                            4 => crate::device::ShutterState::Error,
                            _ => crate::device::ShutterState::Unknown,
                        };

                        return Ok(crate::device::DomeStatus {
                            connected: true,
                            azimuth: 0.0, // ASCOM domes don't always expose azimuth
                            altitude: None, // ASCOM domes typically don't have altitude
                            shutter_status,
                            slewing,
                            at_home: false, // ASCOM dome interface doesn't have at_home
                            at_park,
                            can_set_altitude: false,
                            can_set_azimuth: false, // Could query CanSetAzimuth if needed
                            can_set_shutter: true, // All ASCOM domes have shutter control
                            can_slave: false,
                            is_slaved: false,
                        });
                    }
                    Err(format!("ASCOM dome {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM not supported on this platform".to_string())
            }
            Some(DriverType::Indi) => {
                let (host, port, device_name) = Self::parse_indi_device_id(device_id)?;
                let server_key = format!("{}:{}", host, port);

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;

                    let azimuth = locked
                        .get_number(&device_name, "ABS_DOME_POSITION", "DOME_ABSOLUTE_POSITION")
                        .await
                        .ok_or_else(|| format!("Failed to read INDI dome azimuth for {}", device_id))?;
                    let can_set_azimuth = true;

                    let shutter_open = locked
                        .get_switch(&device_name, "DOME_SHUTTER", "SHUTTER_OPEN")
                        .await;
                    let shutter_close = locked
                        .get_switch(&device_name, "DOME_SHUTTER", "SHUTTER_CLOSE")
                        .await;
                    let shutter_busy = locked.is_property_busy(&device_name, "DOME_SHUTTER").await;

                    let shutter_status = match (shutter_open, shutter_close, shutter_busy) {
                        (Some(true), Some(false), true) => crate::device::ShutterState::Opening,
                        (Some(false), Some(true), true) => crate::device::ShutterState::Closing,
                        (Some(true), Some(false), false) => crate::device::ShutterState::Open,
                        (Some(false), Some(true), false) => crate::device::ShutterState::Closed,
                        _ => crate::device::ShutterState::Unknown,
                    };

                    let azimuth_busy = locked
                        .is_property_busy(&device_name, "ABS_DOME_POSITION")
                        .await;
                    let slewing = azimuth_busy || shutter_busy;

                    let at_home = locked
                        .get_switch(&device_name, "DOME_GOTO", "DOME_HOME")
                        .await
                        .unwrap_or(false);
                    let at_park = locked
                        .get_switch(&device_name, "DOME_PARK", "PARK")
                        .await
                        .unwrap_or(false)
                        || locked
                            .get_switch(&device_name, "DOME_GOTO", "DOME_PARK")
                            .await
                            .unwrap_or(false);

                    let can_set_shutter = shutter_open.is_some() || shutter_close.is_some();

                    let autosync_enable = locked
                        .get_switch(&device_name, "DOME_AUTOSYNC", "DOME_AUTOSYNC_ENABLE")
                        .await;
                    let autosync_disable = locked
                        .get_switch(&device_name, "DOME_AUTOSYNC", "DOME_AUTOSYNC_DISABLE")
                        .await;
                    let can_slave = autosync_enable.is_some() || autosync_disable.is_some();
                    let is_slaved = autosync_enable.unwrap_or(false);

                    return Ok(crate::device::DomeStatus {
                        connected: true,
                        azimuth,
                        altitude: None,
                        shutter_status,
                        slewing,
                        at_home,
                        at_park,
                        can_set_altitude: false,
                        can_set_azimuth,
                        can_set_shutter,
                        can_slave,
                        is_slaved,
                    });
                }

                Err("INDI dome not connected".to_string())
            }
            Some(DriverType::Native) => {
                let native_domes = self.native_domes.read().await;
                if let Some(dome) = native_domes.get(device_id) {
                    // Query all native dome properties
                    let azimuth = dome.get_azimuth().await.map_err(|e| {
                        format!("Failed to read native dome azimuth for {}: {}", device_id, e)
                    })?;
                    let altitude = dome.get_altitude().await.ok().flatten();
                    let shutter_state_native = match dome.get_shutter_status().await {
                        Ok(s) => s,
                        Err(nightshade_native::traits::NativeError::NotSupported) => {
                            nightshade_native::traits::ShutterState::Unknown
                        }
                        Err(e) => {
                            return Err(format!(
                                "Failed to read native dome shutter status for {}: {}",
                                device_id, e
                            ));
                        }
                    };
                    let shutter_status = match shutter_state_native {
                        nightshade_native::traits::ShutterState::Open => crate::device::ShutterState::Open,
                        nightshade_native::traits::ShutterState::Closed => crate::device::ShutterState::Closed,
                        nightshade_native::traits::ShutterState::Opening => crate::device::ShutterState::Opening,
                        nightshade_native::traits::ShutterState::Closing => crate::device::ShutterState::Closing,
                        nightshade_native::traits::ShutterState::Error => crate::device::ShutterState::Error,
                        nightshade_native::traits::ShutterState::Unknown => crate::device::ShutterState::Unknown,
                    };
                    let slewing = match dome.is_slewing().await {
                        Ok(s) => s,
                        Err(nightshade_native::traits::NativeError::NotSupported) => false,
                        Err(e) => {
                            return Err(format!(
                                "Failed to read native dome slewing for {}: {}",
                                device_id, e
                            ));
                        }
                    };
                    let at_home = match dome.is_at_home().await {
                        Ok(h) => h,
                        Err(nightshade_native::traits::NativeError::NotSupported) => false,
                        Err(e) => {
                            return Err(format!(
                                "Failed to read native dome is_at_home for {}: {}",
                                device_id, e
                            ));
                        }
                    };
                    let at_park = match dome.is_parked().await {
                        Ok(p) => p,
                        Err(nightshade_native::traits::NativeError::NotSupported) => false,
                        Err(e) => {
                            return Err(format!(
                                "Failed to read native dome is_parked for {}: {}",
                                device_id, e
                            ));
                        }
                    };
                    let is_slaved = match dome.is_slaved().await {
                        Ok(s) => s,
                        Err(nightshade_native::traits::NativeError::NotSupported) => false,
                        Err(e) => {
                            return Err(format!(
                                "Failed to read native dome is_slaved for {}: {}",
                                device_id, e
                            ));
                        }
                    };

                    return Ok(crate::device::DomeStatus {
                        connected: true,
                        azimuth,
                        altitude,
                        shutter_status,
                        slewing,
                        at_home,
                        at_park,
                        can_set_altitude: dome.can_set_altitude(),
                        can_set_azimuth: dome.can_set_azimuth(),
                        can_set_shutter: dome.can_set_shutter(),
                        can_slave: dome.can_slave(),
                        is_slaved,
                    });
                }
                Err("Native dome not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    // =========================================================================
    // Weather (Observing Conditions)
    // =========================================================================

    /// Get weather conditions
    pub async fn weather_get_conditions(
        &self,
        device_id: &str,
    ) -> Result<WeatherConditions, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let weather_devs = self.alpaca_weather.read().await;
                if let Some(weather) = weather_devs.get(device_id) {
                    return Ok(WeatherConditions {
                        temperature: weather.temperature().await.ok(),
                        humidity: weather.humidity().await.ok(),
                        pressure: weather.pressure().await.ok(),
                        cloud_cover: weather.cloud_cover().await.ok(),
                        dew_point: weather.dew_point().await.ok(),
                        wind_speed: weather.wind_speed().await.ok(),
                        wind_direction: weather.wind_direction().await.ok(),
                        sky_quality: weather.sky_quality().await.ok(),
                        sky_temperature: weather.sky_temperature().await.ok(),
                        rain_rate: weather.rain_rate().await.ok(),
                    });
                }
                Err(format!("Alpaca weather device {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    return Ok(WeatherConditions {
                        temperature: locked.get_number(&device_name, "WEATHER_PARAMETERS", "WEATHER_TEMPERATURE").await,
                        humidity: locked.get_number(&device_name, "WEATHER_PARAMETERS", "WEATHER_HUMIDITY").await,
                        pressure: locked.get_number(&device_name, "WEATHER_PARAMETERS", "WEATHER_PRESSURE").await,
                        cloud_cover: locked.get_number(&device_name, "WEATHER_PARAMETERS", "WEATHER_CLOUD_COVER").await,
                        dew_point: locked.get_number(&device_name, "WEATHER_PARAMETERS", "WEATHER_DEWPOINT").await,
                        wind_speed: locked.get_number(&device_name, "WEATHER_PARAMETERS", "WEATHER_WIND_SPEED").await,
                        wind_direction: locked.get_number(&device_name, "WEATHER_PARAMETERS", "WEATHER_WIND_DIRECTION").await,
                        sky_quality: locked.get_number(&device_name, "WEATHER_PARAMETERS", "WEATHER_SKY_QUALITY").await,
                        sky_temperature: locked.get_number(&device_name, "WEATHER_PARAMETERS", "WEATHER_SKY_TEMPERATURE").await,
                        rain_rate: locked.get_number(&device_name, "WEATHER_PARAMETERS", "WEATHER_RAIN_RATE").await,
                    });
                }
                Err("INDI weather device not connected".to_string())
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let weather_devices = self.ascom_weather.read().await;
                    if let Some(weather) = weather_devices.get(device_id) {
                        let weather_guard = weather.read().await;
                        return Ok(WeatherConditions {
                            temperature: weather_guard.temperature().await.ok(),
                            humidity: weather_guard.humidity().await.ok(),
                            pressure: weather_guard.pressure().await.ok(),
                            cloud_cover: weather_guard.cloud_cover().await.ok(),
                            dew_point: weather_guard.dew_point().await.ok(),
                            wind_speed: weather_guard.wind_speed().await.ok(),
                            wind_direction: weather_guard.wind_direction().await.ok(),
                            sky_quality: weather_guard.sky_quality().await.ok(),
                            sky_temperature: weather_guard.sky_temperature().await.ok(),
                            rain_rate: weather_guard.rain_rate().await.ok(),
                        });
                    }
                    Err(format!("ASCOM weather device {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM is only available on Windows".to_string())
            }
            Some(DriverType::Native) => {
                let native_weather = self.native_weather.read().await;
                if let Some(weather) = native_weather.get(device_id) {
                    return Ok(WeatherConditions {
                        temperature: weather.get_temperature().await.ok().flatten(),
                        humidity: weather.get_humidity().await.ok().flatten(),
                        pressure: weather.get_pressure().await.ok().flatten(),
                        cloud_cover: weather.get_cloud_cover().await.ok().flatten(),
                        dew_point: weather.get_dew_point().await.ok().flatten(),
                        wind_speed: weather.get_wind_speed().await.ok().flatten(),
                        wind_direction: weather.get_wind_direction().await.ok().flatten(),
                        sky_quality: weather.get_sky_quality().await.ok().flatten(),
                        sky_temperature: None, // Not in native trait, could add later
                        rain_rate: weather.get_rain_rate().await.ok().flatten(),
                    });
                }
                Err("Native weather device not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    // =========================================================================
    // Safety Monitor
    // =========================================================================

    /// Check if conditions are safe
    pub async fn safety_is_safe(&self, device_id: &str) -> Result<bool, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let safety_devs = self.alpaca_safety_monitors.read().await;
                if let Some(safety) = safety_devs.get(device_id) {
                    return safety.is_safe().await;
                }
                Err(format!("Alpaca safety monitor {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID format".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    use nightshade_indi::IndiSafetyMonitor;
                    let safety = IndiSafetyMonitor::new(client.clone(), &device_name);
                    return safety.is_safe().await;
                }
                Err(format!("INDI client not connected for server {}", server_key))
            }
            Some(DriverType::Ascom) => {
                #[cfg(windows)]
                {
                    let safety_monitors = self.ascom_safety_monitors.read().await;
                    if let Some(safety) = safety_monitors.get(device_id) {
                        let safety_guard = safety.read().await;
                        return safety_guard.is_safe().await;
                    }
                    Err(format!("ASCOM safety monitor {} not found", device_id))
                }
                #[cfg(not(windows))]
                Err("ASCOM is only available on Windows".to_string())
            }
            Some(DriverType::Native) => {
                let native_safety = self.native_safety_monitors.read().await;
                if let Some(safety) = native_safety.get(device_id) {
                    return safety.is_safe().await.map_err(|e| e.to_string());
                }
                Err("Native safety monitor not connected".to_string())
            }
            Some(DriverType::Simulator) => {
                Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
            }
            None => Err(format!("Device not found: {}", device_id)),
        }
    }

    // =========================================================================
    // Heartbeat Monitoring
    // =========================================================================

    /// Configuration for heartbeat monitoring per device type
    /// Uses optimized presets for each device type based on operational characteristics
    fn get_heartbeat_config(device_type: &DeviceType) -> HeartbeatConfig {
        match device_type {
            DeviceType::Camera => HeartbeatConfig::for_camera(),
            DeviceType::Mount => HeartbeatConfig::for_mount(),
            DeviceType::Focuser => HeartbeatConfig::for_focuser(),
            DeviceType::FilterWheel => HeartbeatConfig::for_filter_wheel(),
            DeviceType::Dome => HeartbeatConfig::for_dome(),
            DeviceType::Rotator => HeartbeatConfig::for_rotator(),
            DeviceType::Weather => HeartbeatConfig::for_weather(),
            DeviceType::SafetyMonitor => HeartbeatConfig::for_safety_monitor(),
            // Default for other devices (guiders, switches, cover calibrators)
            _ => HeartbeatConfig::default(),
        }
    }

    /// Perform a health check for a specific device
    /// Returns Ok(true) if healthy, Ok(false) if not responding, Err for connection errors
    async fn perform_health_check(
        &self,
        device_id: &str,
        device_type: &DeviceType,
        driver_type: &DriverType,
    ) -> Result<bool, String> {
        match driver_type {
            DriverType::Alpaca => {
                self.perform_alpaca_health_check(device_id, device_type)
                    .await
            }
            #[cfg(windows)]
            DriverType::Ascom => {
                self.perform_ascom_health_check(device_id, device_type)
                    .await
            }
            #[cfg(not(windows))]
            DriverType::Ascom => Err("ASCOM is not supported on this platform".to_string()),
            DriverType::Indi => self.perform_indi_health_check(device_id).await,
            DriverType::Native => {
                // Native devices maintain their own connection state
                Ok(true)
            }
            DriverType::Simulator => Err("Simulator devices are disabled".to_string()),
        }
    }

    // perform_alpaca_health_check / perform_ascom_health_check /
    // perform_indi_health_check moved to crate::dispatch::{alpaca,ascom,indi}.


    /// Start heartbeat monitoring for a device with default configuration
    ///
    /// This spawns a background task that periodically checks if the device
    /// is still responding. If the device fails to respond after multiple
    /// attempts with exponential backoff, a Disconnected event is emitted.
    ///
    /// Uses device-type specific defaults for heartbeat configuration.
    /// If `interval` is non-zero, it overrides the device-type default interval.
    pub async fn start_heartbeat(&self, device_id: &str, interval: Duration) -> Result<(), String> {
        // Check if device exists and get its info
        let (device_type, _device_type_str, _driver_type) = {
            let devices = self.devices.read().await;
            match devices.get(device_id) {
                Some(device) => (
                    device.info.device_type.clone(),
                    device.info.device_type.as_str().to_string(),
                    device.info.driver_type.clone(),
                ),
                None => return Err(format!("Device {} not found", device_id)),
            }
        };

        // Get device-type specific heartbeat configuration
        let mut config = Self::get_heartbeat_config(&device_type);

        // Allow interval override if provided (non-zero)
        if !interval.is_zero() {
            config.base_interval_secs = interval.as_secs();
        }

        // Use the configurable version
        self.start_heartbeat_with_config(device_id, config).await
    }

    /// Start heartbeat monitoring with custom configuration
    ///
    /// Allows full control over heartbeat parameters including:
    /// - Check interval and backoff behavior
    /// - Failure threshold before marking as disconnected
    /// - Auto-reconnect settings
    pub async fn start_heartbeat_with_config(
        &self,
        device_id: &str,
        config: HeartbeatConfig,
    ) -> Result<(), String> {
        // Check if device exists and get its info
        let (device_type, device_type_str, driver_type) = {
            let devices = self.devices.read().await;
            match devices.get(device_id) {
                Some(device) => (
                    device.info.device_type.clone(),
                    device.info.device_type.as_str().to_string(),
                    device.info.driver_type.clone(),
                ),
                None => return Err(format!("Device {} not found", device_id)),
            }
        };

        // Stop any existing heartbeat for this device
        self.stop_heartbeat(device_id).await?;

        tracing::info!(
            "Starting heartbeat for device {} (type: {}, driver: {:?}): interval={}s, threshold={}, auto_reconnect={}",
            device_id,
            device_type_str,
            driver_type,
            config.base_interval_secs,
            config.failure_threshold,
            config.auto_reconnect
        );

        // Emit heartbeat started event
        self.app_state.publish_equipment_event(
            EquipmentEvent::HeartbeatStarted {
                device_type: device_type_str.clone(),
                device_id: device_id.to_string(),
                interval_secs: config.base_interval_secs,
            },
            EventSeverity::Info,
        );

        // Mark heartbeat as active
        {
            let mut devices = self.devices.write().await;
            if let Some(device) = devices.get_mut(device_id) {
                device.heartbeat_active = true;
                device.last_successful_comm = Some(chrono::Utc::now().timestamp_millis());
            }
        }

        // Spawn heartbeat task
        let device_id_clone = device_id.to_string();
        let app_state = self.app_state.clone();
        // We need a reference to perform health checks - clone Arc pointer from the global singleton
        let manager = crate::api::get_device_manager().clone();

        let task = tokio::spawn(async move {
            let mut current_interval = Duration::from_secs(config.base_interval_secs);
            let max_interval = Duration::from_secs(config.max_interval_secs);
            let mut consecutive_failures = 0u32;
            let mut reconnect_attempts = 0u32;
            let mut is_reconnecting = false;

            loop {
                // Wait for interval
                tokio::time::sleep(current_interval).await;

                // Perform health check using the actual driver-specific implementation
                let health_check_result = manager
                    .perform_health_check(&device_id_clone, &device_type, &driver_type)
                    .await;

                match health_check_result {
                    Ok(true) => {
                        // Device is healthy - reset failure counter and interval
                        if consecutive_failures > 0 || is_reconnecting {
                            tracing::info!(
                                "Heartbeat recovered for device {} after {} failures{}",
                                device_id_clone,
                                consecutive_failures,
                                if is_reconnecting {
                                    " (reconnected)"
                                } else {
                                    ""
                                }
                            );

                            // Emit HeartbeatStatusChanged event for recovery
                            if is_reconnecting {
                                app_state.publish_equipment_event(
                                    EquipmentEvent::HeartbeatReconnected {
                                        device_type: device_type_str.clone(),
                                        device_id: device_id_clone.clone(),
                                        after_attempts: reconnect_attempts,
                                    },
                                    EventSeverity::Info,
                                );
                            }

                            app_state.publish_equipment_event(
                                EquipmentEvent::HeartbeatStatusChanged {
                                    device_type: device_type_str.clone(),
                                    device_id: device_id_clone.clone(),
                                    status: crate::event::HeartbeatStatus::Healthy,
                                    consecutive_failures: 0,
                                    last_rtt_ms: None, // RTT not available for generic health check
                                },
                                EventSeverity::Info,
                            );
                        }
                        consecutive_failures = 0;
                        reconnect_attempts = 0;
                        is_reconnecting = false;
                        current_interval = Duration::from_secs(config.base_interval_secs);

                        // Update last successful communication time
                        {
                            let mut devices = manager.devices.write().await;
                            if let Some(device) = devices.get_mut(&device_id_clone) {
                                device.last_successful_comm =
                                    Some(chrono::Utc::now().timestamp_millis());
                            }
                        }

                        tracing::trace!("Heartbeat OK for device: {}", device_id_clone);
                    }
                    Ok(false) | Err(_) => {
                        // Health check failed
                        consecutive_failures += 1;
                        let error_msg = match &health_check_result {
                            Err(e) => e.clone(),
                            _ => "Device not responding".to_string(),
                        };

                        tracing::warn!(
                            "Heartbeat failure {}/{} for device {}: {}",
                            consecutive_failures,
                            config.failure_threshold,
                            device_id_clone,
                            error_msg
                        );

                        // Apply exponential backoff
                        let new_interval = Duration::from_secs_f64(
                            current_interval.as_secs_f64() * config.backoff_multiplier,
                        );
                        current_interval = new_interval.min(max_interval);

                        // Emit degraded status if we have failures but not yet at threshold
                        if consecutive_failures < config.failure_threshold {
                            app_state.publish_equipment_event(
                                EquipmentEvent::HeartbeatStatusChanged {
                                    device_type: device_type_str.clone(),
                                    device_id: device_id_clone.clone(),
                                    status: crate::event::HeartbeatStatus::Degraded,
                                    consecutive_failures,
                                    last_rtt_ms: None,
                                },
                                EventSeverity::Warning,
                            );
                        }

                        // Check if we've exceeded failure threshold
                        if consecutive_failures >= config.failure_threshold {
                            tracing::error!(
                                "Heartbeat failed {} times for device {} - marking disconnected",
                                consecutive_failures,
                                device_id_clone
                            );

                            // Update device state
                            {
                                let mut devices = manager.devices.write().await;
                                if let Some(device) = devices.get_mut(&device_id_clone) {
                                    device.connection_state = ConnectionState::Error;
                                    device.last_error = Some(format!(
                                        "Unresponsive after {} heartbeat failures",
                                        consecutive_failures
                                    ));
                                }
                            }

                            // Emit disconnected status via HeartbeatStatusChanged
                            app_state.publish_equipment_event(
                                EquipmentEvent::HeartbeatStatusChanged {
                                    device_type: device_type_str.clone(),
                                    device_id: device_id_clone.clone(),
                                    status: crate::event::HeartbeatStatus::Disconnected,
                                    consecutive_failures,
                                    last_rtt_ms: None,
                                },
                                EventSeverity::Error,
                            );

                            app_state.publish_equipment_event(
                                EquipmentEvent::Disconnected {
                                    device_type: device_type_str.clone(),
                                    device_id: device_id_clone.clone(),
                                },
                                EventSeverity::Warning,
                            );

                            app_state.publish_equipment_event(
                                EquipmentEvent::Error {
                                    device_type: device_type_str.clone(),
                                    device_id: device_id_clone.clone(),
                                    message: format!(
                                        "Device unresponsive after {} heartbeat failures: {}",
                                        consecutive_failures, error_msg
                                    ),
                                },
                                EventSeverity::Error,
                            );

                            // Handle auto-reconnect if enabled
                            if config.auto_reconnect {
                                let max_reconnects = config.max_reconnect_attempts;
                                let should_try =
                                    max_reconnects == 0 || reconnect_attempts < max_reconnects;

                                if should_try {
                                    reconnect_attempts += 1;
                                    is_reconnecting = true;

                                    tracing::info!(
                                        "Attempting auto-reconnect for device {} (attempt {}/{})",
                                        device_id_clone,
                                        reconnect_attempts,
                                        if max_reconnects == 0 {
                                            "unlimited".to_string()
                                        } else {
                                            max_reconnects.to_string()
                                        }
                                    );

                                    // Emit reconnecting status
                                    app_state.publish_equipment_event(
                                        EquipmentEvent::HeartbeatStatusChanged {
                                            device_type: device_type_str.clone(),
                                            device_id: device_id_clone.clone(),
                                            status: crate::event::HeartbeatStatus::Reconnecting,
                                            consecutive_failures,
                                            last_rtt_ms: None,
                                        },
                                        EventSeverity::Info,
                                    );

                                    app_state.publish_equipment_event(
                                        EquipmentEvent::HeartbeatReconnecting {
                                            device_type: device_type_str.clone(),
                                            device_id: device_id_clone.clone(),
                                            attempt: reconnect_attempts,
                                            max_attempts: max_reconnects,
                                        },
                                        EventSeverity::Info,
                                    );

                                    app_state.publish_equipment_event(
                                        EquipmentEvent::Connecting {
                                            device_type: device_type_str.clone(),
                                            device_id: device_id_clone.clone(),
                                        },
                                        EventSeverity::Info,
                                    );

                                    // Wait before reconnection attempt
                                    let reconnect_delay = Duration::from_secs(
                                        config.reconnect_delay_secs * (reconnect_attempts as u64),
                                    );
                                    tokio::time::sleep(reconnect_delay).await;

                                    // Reset failure counter for reconnect monitoring
                                    consecutive_failures = 0;
                                    current_interval =
                                        Duration::from_secs(config.base_interval_secs);

                                    // Continue monitoring - if connection recovers, we'll see it
                                    continue;
                                } else {
                                    tracing::error!(
                                        "Max reconnection attempts ({}) reached for device {}",
                                        max_reconnects,
                                        device_id_clone
                                    );

                                    app_state.publish_equipment_event(
                                        EquipmentEvent::Error {
                                            device_type: device_type_str.clone(),
                                            device_id: device_id_clone.clone(),
                                            message: format!(
                                                "Auto-reconnect failed after {} attempts",
                                                reconnect_attempts
                                            ),
                                        },
                                        EventSeverity::Error,
                                    );
                                }
                            }

                            // Stop heartbeat monitoring
                            break;
                        }
                    }
                }
            }

            tracing::debug!("Heartbeat task ended for device: {}", device_id_clone);

            // Mark heartbeat as inactive when task ends
            {
                let mut devices = manager.devices.write().await;
                if let Some(device) = devices.get_mut(&device_id_clone) {
                    device.heartbeat_active = false;
                }
            }
        });

        // Store the task handle
        {
            let mut tasks = self.heartbeat_tasks.write().await;
            tasks.insert(device_id.to_string(), task);
        }

        Ok(())
    }

    /// Stop heartbeat monitoring for a device
    pub async fn stop_heartbeat(&self, device_id: &str) -> Result<(), String> {
        // Get device type for the event before removing task
        let device_type_str = {
            let devices = self.devices.read().await;
            devices
                .get(device_id)
                .map(|d| d.info.device_type.as_str().to_string())
        };

        // Remove and abort the task
        let task = {
            let mut tasks = self.heartbeat_tasks.write().await;
            tasks.remove(device_id)
        };

        if let Some(task) = task {
            // Abort the task (gracefully cancels via the select!)
            task.abort();

            // Wait briefly for clean shutdown
            match tokio::time::timeout(Duration::from_millis(100), task).await {
                Ok(_) => tracing::debug!("Heartbeat task stopped cleanly for {}", device_id),
                Err(_) => tracing::debug!("Heartbeat task aborted for {}", device_id),
            }

            // Emit heartbeat stopped event
            if let Some(device_type) = device_type_str {
                self.app_state.publish_equipment_event(
                    EquipmentEvent::HeartbeatStopped {
                        device_type,
                        device_id: device_id.to_string(),
                    },
                    EventSeverity::Info,
                );
            }
        }

        // Mark heartbeat as inactive
        {
            let mut devices = self.devices.write().await;
            if let Some(device) = devices.get_mut(device_id) {
                device.heartbeat_active = false;
            }
        }

        Ok(())
    }

    /// Stop all heartbeat tasks (call during shutdown)
    pub async fn stop_all_heartbeats(&self) {
        let tasks: Vec<(String, tokio::task::JoinHandle<()>)> = {
            let mut tasks = self.heartbeat_tasks.write().await;
            std::mem::take(&mut *tasks).into_iter().collect()
        };

        for (device_id, task) in tasks {
            task.abort();
            tracing::debug!("Aborted heartbeat for device: {}", device_id);
        }

        // Mark all heartbeats as inactive
        {
            let mut devices = self.devices.write().await;
            for device in devices.values_mut() {
                device.heartbeat_active = false;
            }
        }
    }

    /// Get device health status
    ///
    /// Returns (last_successful_timestamp_ms, is_healthy)
    pub async fn get_device_health(&self, device_id: &str) -> Result<(i64, bool), String> {
        let devices = self.devices.read().await;

        if let Some(device) = devices.get(device_id) {
            let last_comm = device.last_successful_comm.unwrap_or(0);
            let now = chrono::Utc::now().timestamp_millis();

            // Consider device unhealthy if no communication in last 30 seconds
            let is_healthy = if let Some(last) = device.last_successful_comm {
                (now - last) < 30_000
            } else {
                false
            };

            Ok((last_comm, is_healthy))
        } else {
            Err(format!("Device {} not found", device_id))
        }
    }

    /// Update last successful communication timestamp for a device
    ///
    /// This should be called by device operations when they successfully
    /// communicate with the device.
    pub async fn update_device_communication(&self, device_id: &str) {
        let mut devices = self.devices.write().await;
        if let Some(device) = devices.get_mut(device_id) {
            device.last_successful_comm = Some(chrono::Utc::now().timestamp_millis());
        }
    }

    /// Check if heartbeat is active for a device
    pub async fn is_heartbeat_active(&self, device_id: &str) -> bool {
        let devices = self.devices.read().await;
        devices
            .get(device_id)
            .map(|d| d.heartbeat_active)
            .unwrap_or(false)
    }

    // =========================================================================
    // INDI Switch Helpers
    // =========================================================================

    // indi_get_all_switches / indi_get_switch_at moved to
    // `crate::dispatch::indi`; call sites use `self.indi_*` unchanged.

    // =========================================================================
    // Switch Control
    // =========================================================================

    /// Get the number of switches exposed by a switch device
    pub async fn switch_get_max(&self, device_id: &str) -> Result<i32, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_max_switch().await;
                    }
                }
                Err(format!("ASCOM switch {} not found", device_id))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.max_switch().await;
                }
                Err(format!("Alpaca switch {} not found", device_id))
            }
            DriverType::Indi => {
                // INDI switches use named properties -- enumerate and count them
                let switches = self.indi_get_all_switches(device_id).await?;
                Ok(switches.len() as i32)
            }
            DriverType::Native => Err("Native switch devices are not supported by the current native backend".to_string()),
            DriverType::Simulator => Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string()),
        }
    }

    /// Get the boolean state of a switch
    pub async fn switch_get_state(&self, device_id: &str, switch_id: i32) -> Result<bool, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_switch(switch_id).await;
                    }
                }
                Err(format!("ASCOM switch {} not found", device_id))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.get_switch(switch_id).await;
                }
                Err(format!("Alpaca switch {} not found", device_id))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                Ok(sw.state)
            }
            DriverType::Native => Err("Native switch devices are not supported by the current native backend".to_string()),
            DriverType::Simulator => Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string()),
        }
    }

    /// Set the boolean state of a switch
    pub async fn switch_set_state(
        &self,
        device_id: &str,
        switch_id: i32,
        state: bool,
    ) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let mut sw = sw.write().await;
                        return sw.set_switch(switch_id, state).await;
                    }
                }
                Err(format!("ASCOM switch {} not found", device_id))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.set_switch(switch_id, state).await;
                }
                Err(format!("Alpaca switch {} not found", device_id))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                if !sw.writable {
                    return Err(format!("INDI switch '{}' / '{}' is read-only", sw.property_name, sw.element_name));
                }
                let (host, port, device_name) = Self::parse_indi_device_id(device_id)?;
                let server_key = format!("{}:{}", host, port);
                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let switch_dev = nightshade_indi::IndiSwitchDevice::new(client.clone(), &device_name);
                    return switch_dev.set_switch_state(&sw.property_name, &sw.element_name, state).await
                        .map_err(|e| e.to_string());
                }
                Err("INDI switch device not connected".to_string())
            }
            DriverType::Native => Err("Native switch devices are not supported by the current native backend".to_string()),
            DriverType::Simulator => Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string()),
        }
    }

    /// Get the name of a switch
    pub async fn switch_get_name(&self, device_id: &str, switch_id: i32) -> Result<String, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_switch_name(switch_id).await;
                    }
                }
                Err(format!("ASCOM switch {} not found", device_id))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.get_switch_name(switch_id).await;
                }
                Err(format!("Alpaca switch {} not found", device_id))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                Ok(sw.element_name.clone())
            }
            DriverType::Native => Err("Native switch devices are not supported by the current native backend".to_string()),
            DriverType::Simulator => Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string()),
        }
    }

    /// Get the description of a switch
    pub async fn switch_get_description(
        &self,
        device_id: &str,
        switch_id: i32,
    ) -> Result<String, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_switch_description(switch_id).await;
                    }
                }
                Err(format!("ASCOM switch {} not found", device_id))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.get_switch_description(switch_id).await;
                }
                Err(format!("Alpaca switch {} not found", device_id))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                // For INDI, description is "property_name / label"
                Ok(format!("{} / {}", sw.property_name, sw.label))
            }
            DriverType::Native => Err("Native switch devices are not supported by the current native backend".to_string()),
            DriverType::Simulator => Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string()),
        }
    }

    /// Get the numeric value of a switch
    pub async fn switch_get_value(&self, device_id: &str, switch_id: i32) -> Result<f64, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_switch_value(switch_id).await;
                    }
                }
                Err(format!("ASCOM switch {} not found", device_id))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.get_switch_value(switch_id).await;
                }
                Err(format!("Alpaca switch {} not found", device_id))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                // INDI switches can have associated number values (e.g., PWM duty cycle)
                let parts: Vec<&str> = device_id.split(':').collect();
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");
                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let switch_dev = nightshade_indi::IndiSwitchDevice::new(client.clone(), &device_name);
                    if let Some(val) = switch_dev.get_switch_value(&sw.property_name, &sw.element_name).await {
                        return Ok(val);
                    }
                    // If no numeric value, return 1.0 for on, 0.0 for off
                    return Ok(if sw.state { 1.0 } else { 0.0 });
                }
                Err("INDI switch device not connected".to_string())
            }
            DriverType::Native => Err("Native switch devices are not supported by the current native backend".to_string()),
            DriverType::Simulator => Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string()),
        }
    }

    /// Set the numeric value of a switch
    pub async fn switch_set_value(
        &self,
        device_id: &str,
        switch_id: i32,
        value: f64,
    ) -> Result<(), String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let mut sw = sw.write().await;
                        return sw.set_switch_value(switch_id, value).await;
                    }
                }
                Err(format!("ASCOM switch {} not found", device_id))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.set_switch_value(switch_id, value).await;
                }
                Err(format!("Alpaca switch {} not found", device_id))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                if !sw.writable {
                    return Err(format!("INDI switch '{}' / '{}' is read-only", sw.property_name, sw.element_name));
                }
                let (host, port, device_name) = Self::parse_indi_device_id(device_id)?;
                let server_key = format!("{}:{}", host, port);
                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let switch_dev = nightshade_indi::IndiSwitchDevice::new(client.clone(), &device_name);
                    return switch_dev.set_switch_value(&sw.property_name, &sw.element_name, value).await
                        .map_err(|e| e.to_string());
                }
                Err("INDI switch device not connected".to_string())
            }
            DriverType::Native => Err("Native switch devices are not supported by the current native backend".to_string()),
            DriverType::Simulator => Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string()),
        }
    }

    /// Get the minimum value for a switch
    pub async fn switch_get_min_value(
        &self,
        device_id: &str,
        switch_id: i32,
    ) -> Result<f64, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_min_switch_value(switch_id).await;
                    }
                }
                Err(format!("ASCOM switch {} not found", device_id))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.min_switch_value(switch_id).await;
                }
                Err(format!("Alpaca switch {} not found", device_id))
            }
            DriverType::Indi => {
                // INDI boolean switches have min 0.0
                Ok(0.0)
            }
            DriverType::Native => Err("Native switch devices are not supported by the current native backend".to_string()),
            DriverType::Simulator => Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string()),
        }
    }

    /// Get the maximum value for a switch
    pub async fn switch_get_max_value(
        &self,
        device_id: &str,
        switch_id: i32,
    ) -> Result<f64, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.get_max_switch_value(switch_id).await;
                    }
                }
                Err(format!("ASCOM switch {} not found", device_id))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.max_switch_value(switch_id).await;
                }
                Err(format!("Alpaca switch {} not found", device_id))
            }
            DriverType::Indi => {
                // INDI boolean switches have max 1.0
                Ok(1.0)
            }
            DriverType::Native => Err("Native switch devices are not supported by the current native backend".to_string()),
            DriverType::Simulator => Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string()),
        }
    }

    /// Check if a switch can be written to
    pub async fn switch_can_write(&self, device_id: &str, switch_id: i32) -> Result<bool, String> {
        let devices = self.devices.read().await;
        let info = devices
            .get(device_id)
            .map(|d| d.info.clone())
            .ok_or_else(|| format!("Device not found: {}", device_id))?;

        match info.driver_type {
            DriverType::Ascom => {
                #[cfg(windows)]
                {
                    let switches = self.ascom_switches.read().await;
                    if let Some(sw) = switches.get(device_id) {
                        let sw = sw.read().await;
                        return sw.can_write(switch_id).await;
                    }
                }
                Err(format!("ASCOM switch {} not found", device_id))
            }
            DriverType::Alpaca => {
                let switches = self.alpaca_switches.read().await;
                if let Some(sw) = switches.get(device_id) {
                    return sw.can_write(switch_id).await;
                }
                Err(format!("Alpaca switch {} not found", device_id))
            }
            DriverType::Indi => {
                let sw = self.indi_get_switch_at(device_id, switch_id).await?;
                Ok(sw.writable)
            }
            DriverType::Native => Err("Native switch devices are not supported by the current native backend".to_string()),
            DriverType::Simulator => Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string()),
        }
    }

    // =========================================================================
    // Cover Calibrator Control
    // =========================================================================

    /// Open cover calibrator cover
    pub async fn cover_calibrator_open_cover(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.open_cover().await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.open_cover().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    return locked
                        .set_switch(&device_name, "CAP_PARK", "UNPARK", true)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Close cover calibrator cover
    pub async fn cover_calibrator_close_cover(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.close_cover().await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.close_cover().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    return locked
                        .set_switch(&device_name, "CAP_PARK", "PARK", true)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Halt cover calibrator cover movement
    pub async fn cover_calibrator_halt_cover(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.halt_cover().await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.halt_cover().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                // INDI doesn't have a specific halt command for dust caps
                Err("INDI cover calibrator halt not supported".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Turn on cover calibrator light
    pub async fn cover_calibrator_calibrator_on(
        &self,
        device_id: &str,
        brightness: i32,
    ) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.calibrator_on(brightness).await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.calibrator_on(brightness).await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    // Set brightness first, then turn on
                    locked
                        .set_number(
                            &device_name,
                            "FLAT_LIGHT_INTENSITY",
                            "FLAT_LIGHT_INTENSITY_VALUE",
                            brightness as f64,
                        )
                        .await
                        .map_err(|e| e.to_string())?;
                    return locked
                        .set_switch(&device_name, "FLAT_LIGHT_CONTROL", "FLAT_LIGHT_ON", true)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Turn off cover calibrator light
    pub async fn cover_calibrator_calibrator_off(&self, device_id: &str) -> Result<(), String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.calibrator_off().await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let mut locked = cover_cal.write().await;
                    return locked.calibrator_off().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    return locked
                        .set_switch(&device_name, "FLAT_LIGHT_CONTROL", "FLAT_LIGHT_OFF", true)
                        .await
                        .map_err(|e| e.to_string());
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Get cover calibrator cover state
    /// Returns: 0=NotPresent, 1=Closed, 2=Moving, 3=Open, 4=Unknown, 5=Error
    pub async fn cover_calibrator_get_cover_state(&self, device_id: &str) -> Result<i32, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let state = cover_cal.cover_state().await?;
                    return Ok(state as i32);
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let locked = cover_cal.read().await;
                    return locked.cover_state().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    if let Some(state) = locked.get_switch(&device_name, "CAP_PARK", "PARK").await {
                        // PARK=on means closed, UNPARK=on means open
                        return Ok(if state { 1 } else { 3 }); // 1=Closed, 3=Open
                    }
                    return Ok(4); // Unknown
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Get cover calibrator calibrator state
    /// Returns: 0=NotPresent, 1=Off, 2=NotReady, 3=Ready, 4=Unknown, 5=Error
    pub async fn cover_calibrator_get_calibrator_state(
        &self,
        device_id: &str,
    ) -> Result<i32, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let state = cover_cal.calibrator_state().await?;
                    return Ok(state as i32);
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let locked = cover_cal.read().await;
                    return locked.calibrator_state().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    if let Some(state) = locked
                        .get_switch(&device_name, "FLAT_LIGHT_CONTROL", "FLAT_LIGHT_ON")
                        .await
                    {
                        // FLAT_LIGHT_ON=true means Ready (light is on), false means Off
                        return Ok(if state { 3 } else { 1 }); // 3=Ready, 1=Off
                    }
                    return Ok(4); // Unknown
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Get cover calibrator brightness
    pub async fn cover_calibrator_get_brightness(&self, device_id: &str) -> Result<i32, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.brightness().await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let locked = cover_cal.read().await;
                    return locked.brightness().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err("Invalid INDI device ID".to_string());
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let locked = client.read().await;
                    if let Some(brightness) = locked
                        .get_number(
                            &device_name,
                            "FLAT_LIGHT_INTENSITY",
                            "FLAT_LIGHT_INTENSITY_VALUE",
                        )
                        .await
                    {
                        return Ok(brightness as i32);
                    }
                    return Ok(0);
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Get cover calibrator max brightness
    pub async fn cover_calibrator_get_max_brightness(
        &self,
        device_id: &str,
    ) -> Result<i32, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    return cover_cal.max_brightness().await;
                }
                Err(format!("Alpaca cover calibrator {} not found", device_id))
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                if let Some(cover_cal) = cover_cals.get(device_id) {
                    let locked = cover_cal.read().await;
                    return locked.max_brightness().await;
                }
                Err(format!("ASCOM cover calibrator {} not found", device_id))
            }
            Some(DriverType::Indi) => {
                let (host, port, device_name) = Self::parse_indi_device_id(device_id)?;
                let server_key = format!("{}:{}", host, port);
                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let cover_cal =
                        nightshade_indi::IndiCoverCalibrator::new(client.clone(), &device_name);
                    return cover_cal.get_max_brightness().await;
                }
                Err("INDI cover calibrator not connected".to_string())
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
    }

    /// Get cover calibrator status (combined state)
    pub async fn cover_calibrator_get_status(
        &self,
        device_id: &str,
    ) -> Result<CoverCalibratorStatus, String> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Alpaca) => {
                let cover_cals = self.alpaca_cover_calibrators.read().await;
                let Some(cover_cal) = cover_cals.get(device_id) else {
                    return Err(format!("Alpaca cover calibrator {} not found", device_id));
                };

                let status = cover_cal.get_status().await?;
                let max_brightness = cover_cal.max_brightness().await.unwrap_or_else(|e| {
                    warn!(
                        "Failed to read cover calibrator max_brightness for {}: {}. Using default 255.",
                        device_id, e
                    );
                    255
                });

                Ok(CoverCalibratorStatus {
                    connected: true,
                    cover_state: CoverState::from_i32(status.cover_state as i32),
                    calibrator_state: CalibratorState::from_i32(status.calibrator_state as i32),
                    brightness: status.brightness.unwrap_or(0),
                    max_brightness,
                })
            }
            #[cfg(windows)]
            Some(DriverType::Ascom) => {
                let cover_cals = self.ascom_cover_calibrators.read().await;
                let Some(cover_cal) = cover_cals.get(device_id) else {
                    return Err(format!("ASCOM cover calibrator {} not found", device_id));
                };

                let locked = cover_cal.read().await;
                let cover_state_raw = locked.cover_state().await.unwrap_or_else(|e| {
                    warn!(
                        "Failed to read cover calibrator cover_state for {}: {}. Using Unknown (4).",
                        device_id, e
                    );
                    4
                });
                let calibrator_state_raw = locked.calibrator_state().await.unwrap_or_else(|e| {
                    warn!(
                        "Failed to read cover calibrator calibrator_state for {}: {}. Using Unknown (4).",
                        device_id, e
                    );
                    4
                });
                let brightness = locked.brightness().await.unwrap_or_else(|e| {
                    warn!(
                        "Failed to read cover calibrator brightness for {}: {}. Using default 0.",
                        device_id, e
                    );
                    0
                });

                Ok(CoverCalibratorStatus {
                    connected: true,
                    cover_state: CoverState::from_i32(cover_state_raw),
                    calibrator_state: CalibratorState::from_i32(calibrator_state_raw),
                    brightness,
                    max_brightness: locked.cached_max_brightness(),
                })
            }
            Some(DriverType::Indi) => {
                let cover_state_raw = match self.cover_calibrator_get_cover_state(device_id).await {
                    Ok(s) => s,
                    Err(e) => {
                        warn!(
                            "Failed to read cover calibrator cover_state for {}: {}. Using Unknown (4).",
                            device_id, e
                        );
                        4
                    }
                };
                let calibrator_state_raw = match self
                    .cover_calibrator_get_calibrator_state(device_id)
                    .await
                {
                    Ok(s) => s,
                    Err(e) => {
                        warn!(
                                "Failed to read cover calibrator calibrator_state for {}: {}. Using Unknown (4).",
                                device_id, e
                            );
                        4
                    }
                };
                let brightness = self
                    .cover_calibrator_get_brightness(device_id)
                    .await
                    .unwrap_or_else(|e| {
                        warn!(
                            "Failed to read cover calibrator brightness for {}: {}. Using default 0.",
                            device_id, e
                        );
                        0
                    });
                let max_brightness = self
                    .cover_calibrator_get_max_brightness(device_id)
                    .await
                    .unwrap_or_else(|e| {
                        warn!(
                            "Failed to read cover calibrator max_brightness for {}: {}. Using default 255.",
                            device_id, e
                        );
                        255
                    });

                Ok(CoverCalibratorStatus {
                    connected: true,
                    cover_state: CoverState::from_i32(cover_state_raw),
                    calibrator_state: CalibratorState::from_i32(calibrator_state_raw),
                    brightness,
                    max_brightness,
                })
            }
            _ => Err("Cover calibrator not supported for this driver type".to_string()),
        }
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
