//! # INDI Protocol Support
//!
//! This module implements INDI (Instrument Neutral Distributed Interface) protocol
//! support for device communication on Linux/macOS platforms.
//!
//! ## Support Matrix
//!
//! | Device Type      | Support Level | Notes                                    |
//! |------------------|---------------|------------------------------------------|
//! | Camera           | Full          | All standard INDI camera properties      |
//! | Mount            | Full          | Slew, sync, park, tracking               |
//! | Focuser          | Full          | Absolute and relative positioning        |
//! | Filter Wheel     | Full          | Position control and naming              |
//! | Rotator          | Full          | Angle control                            |
//! | Dome             | Full          | Slew, park, shutter control              |
//! | Safety Monitor   | Full          | Safety state monitoring                  |
//! | Cover Calibrator | Partial       | No halt support, basic open/close only   |
//! | Weather          | Full          | All standard INDI weather properties     |
//! | Switch           | Full          | Custom switch property enumeration       |
//!
//! ## Unsupported Features
//!
//! The following INDI features are not currently implemented:
//! - Cover calibrator halt command
//! - BLOB streaming for video
//!
//! ## Alternatives
//!
//! For unsupported features (cover calibrator halt, BLOB streaming), use ASCOM
//! Alpaca which provides cross-platform support via HTTP.
//!
//! ## Features
//!
//! - Robust error handling with IndiError types
//! - Reader task supervision with automatic reconnection
//! - XML parse timeout for incomplete messages
//! - Atomic keepalive operations to prevent race conditions
//! - BLOB format validation and detection
//! - Property min/max extraction for number elements
//! - Permission checking before property writes
//! - Protocol version negotiation support (1.7, 1.8, 1.9)
//! - Exponential backoff with jitter for reconnection

mod client;
mod protocol;
mod error;
mod camera;
mod mount;
mod focuser;
mod filterwheel;
mod rotator;
mod dome;
mod safetymonitor;
mod covercalibrator;
mod weather;
mod switch_device;
pub mod discovery;
pub mod autofocus;

pub use client::*;
pub use error::{IndiError, IndiResult};
pub use protocol::{CcdFrameType, standard_properties, INDI_PROTOCOL_VERSION};
pub use camera::IndiCamera;
pub use mount::IndiMount;
pub use focuser::IndiFocuser;
pub use filterwheel::IndiFilterWheel;
pub use rotator::IndiRotator;
pub use dome::{IndiDome, IndiShutterStatus};
pub use safetymonitor::IndiSafetyMonitor;
pub use covercalibrator::{IndiCoverCalibrator, IndiCoverState, IndiCalibratorState};
pub use weather::{IndiWeather, IndiWeatherStatus};
pub use switch_device::{IndiSwitchDevice, IndiSwitchInfo};
pub use discovery::{discover_localhost, discover_server, discover_common_hosts, discover_local_network, discover_mdns, IndiServer, IndiDeviceInfo, IndiDeviceType};
pub use autofocus::{IndiAutofocus, IndiAutofocusConfig, IndiAutofocusResult, AutofocusMethod};

/// Error returned when an INDI feature is not supported
#[derive(Debug, Clone)]
pub struct UnsupportedFeatureError {
    pub device_type: String,
    pub feature: String,
    pub alternative: Option<String>,
}

impl std::fmt::Display for UnsupportedFeatureError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "INDI does not support {} for {}.", self.feature, self.device_type)?;
        if let Some(alt) = &self.alternative {
            write!(f, " Alternative: {}", alt)?;
        }
        Ok(())
    }
}

impl std::error::Error for UnsupportedFeatureError {}

/// Check if a feature is supported for a device type
///
/// Returns `Ok(())` if the feature is supported, or an `UnsupportedFeatureError`
/// with details about the limitation and any available alternatives.
///
/// # Arguments
///
/// * `device_type` - The type of device (e.g., "camera", "mount", "weather")
/// * `feature` - The specific feature being requested (e.g., "connect", "halt")
///
/// # Examples
///
/// ```
/// use nightshade_indi::check_feature_support;
///
/// // Camera features are fully supported
/// assert!(check_feature_support("camera", "capture").is_ok());
///
/// // Weather devices are not supported
/// assert!(check_feature_support("weather", "temperature").is_err());
/// ```
pub fn check_feature_support(device_type: &str, feature: &str) -> Result<(), UnsupportedFeatureError> {
    match (device_type.to_lowercase().as_str(), feature.to_lowercase().as_str()) {
        ("covercalibrator", "halt") => Err(UnsupportedFeatureError {
            device_type: device_type.to_string(),
            feature: feature.to_string(),
            alternative: None,
        }),
        ("covercalibrator", "blob_streaming") | ("camera", "blob_streaming") => Err(UnsupportedFeatureError {
            device_type: device_type.to_string(),
            feature: feature.to_string(),
            alternative: Some("Use standard BLOB transfers instead of streaming".to_string()),
        }),
        _ => Ok(()),
    }
}

/// Default INDI server port
pub const INDI_DEFAULT_PORT: u16 = 7624;

/// INDI device information
#[derive(Debug, Clone)]
pub struct IndiDevice {
    pub name: String,
    pub driver: String,
}

/// Check if INDI is available on this platform
pub fn is_available() -> bool {
    true
}

/// INDI property types
#[derive(Debug, Clone)]
pub enum IndiPropertyType {
    Text,
    Number,
    Switch,
    Light,
    Blob,
}

/// INDI property state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IndiPropertyState {
    Idle,
    Ok,
    Busy,
    Alert,
}

/// An INDI property
#[derive(Debug, Clone)]
pub struct IndiProperty {
    pub device: String,
    pub name: String,
    pub label: String,
    pub group: String,
    pub property_type: IndiPropertyType,
    pub state: IndiPropertyState,
    pub perm: IndiPermission,
    pub elements: Vec<String>,
}

/// INDI property permission
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IndiPermission {
    ReadOnly,
    WriteOnly,
    ReadWrite,
}

/// Timeout configuration for INDI operations
#[derive(Debug, Clone)]
pub struct IndiTimeoutConfig {
    /// Connection timeout for initial TCP connection (default: 30 seconds)
    pub connection_timeout_secs: u64,
    /// Timeout for completing partial XML messages (default: 60 seconds)
    /// If a partial XML message is not completed within this time, the parser resets
    pub message_timeout_secs: u64,
    /// Timeout for receiving BLOB data (default: 300 seconds for large images)
    pub blob_timeout_secs: u64,
    /// Timeout for property responses (default: 30 seconds)
    pub property_timeout_secs: u64,
    /// Mount slew timeout (default: 300 seconds)
    pub mount_slew_timeout_secs: u64,
    /// Focuser move timeout (default: 120 seconds)
    pub focuser_move_timeout_secs: u64,
    /// Filter change timeout (default: 60 seconds)
    pub filter_change_timeout_secs: u64,
    /// Dome slew timeout (default: 300 seconds)
    pub dome_slew_timeout_secs: u64,
    /// Rotator move timeout (default: 120 seconds)
    pub rotator_move_timeout_secs: u64,
    /// Camera exposure timeout buffer (added to exposure time, default: 60 seconds)
    pub camera_exposure_buffer_secs: u64,
    /// Property state polling interval (default: 500ms)
    pub property_poll_interval_ms: u64,
    /// Connection keepalive interval (default: 30 seconds)
    pub keepalive_interval_secs: u64,
    /// Reconnection base delay (default: 1 second)
    pub reconnect_base_delay_secs: u64,
    /// Reconnection max delay (default: 30 seconds)
    pub reconnect_max_delay_secs: u64,
    /// Reconnection max attempts (default: 5)
    pub reconnect_max_attempts: u32,
}

impl Default for IndiTimeoutConfig {
    fn default() -> Self {
        Self {
            connection_timeout_secs: 30,
            message_timeout_secs: 60,
            blob_timeout_secs: 300,
            property_timeout_secs: 30,
            mount_slew_timeout_secs: 300,
            focuser_move_timeout_secs: 120,
            filter_change_timeout_secs: 60,
            dome_slew_timeout_secs: 300,
            rotator_move_timeout_secs: 120,
            camera_exposure_buffer_secs: 60,
            property_poll_interval_ms: 500,
            keepalive_interval_secs: 30,
            reconnect_base_delay_secs: 1,
            reconnect_max_delay_secs: 30,
            reconnect_max_attempts: 5,
        }
    }
}

impl IndiTimeoutConfig {
    /// Get the message timeout as a Duration
    pub fn message_timeout(&self) -> std::time::Duration {
        std::time::Duration::from_secs(self.message_timeout_secs)
    }

    /// Get the BLOB timeout as a Duration
    pub fn blob_timeout(&self) -> std::time::Duration {
        std::time::Duration::from_secs(self.blob_timeout_secs)
    }

    /// Get the property timeout as a Duration
    pub fn property_timeout(&self) -> std::time::Duration {
        std::time::Duration::from_secs(self.property_timeout_secs)
    }

    /// Get the connection timeout as a Duration
    pub fn connection_timeout(&self) -> std::time::Duration {
        std::time::Duration::from_secs(self.connection_timeout_secs)
    }
}

/// Timeout error with context
#[derive(Debug, Clone, thiserror::Error)]
#[error("Operation timeout for device '{device}', property '{property}': {context}")]
pub struct IndiTimeoutError {
    pub device: String,
    pub property: String,
    pub context: String,
    pub last_state: Option<IndiPropertyState>,
}
