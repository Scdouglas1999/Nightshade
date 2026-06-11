//! Device Capability Reporting
//!
//! This module provides standardized capability reporting for all device types.
//! Capabilities describe what operations a device supports, allowing the UI
//! and sequencer to adapt to device limitations.
//!
//! # Connect/Disconnect-probe guard
//!
//! Capability probes for Alpaca and ASCOM devices originally followed a
//! `connect → read properties → disconnect` pattern. That pattern kicks any
//! existing connection — e.g. when the user has the device open in the UI and
//! the bridge tries to refresh capabilities, the probe's `disconnect()` drops
//! the active session.
//!
//! The fix: probe `is_connected()` first. If `Ok(true)`, the device is already
//! up and we MUST NOT issue connect/disconnect — we just read the properties.
//! If `Ok(false)`, we perform the full connect/probe/disconnect cycle. If
//! `is_connected()` returns `Err` (driver doesn't implement `Connected` or the
//! call failed mid-transition), we treat the device as already connected: the
//! conservative choice. Spuriously skipping disconnect on a probe leaves a
//! short-lived connection that the UI / device manager will clean up via its
//! normal lifecycle; spuriously issuing disconnect on a driver that was
//! mid-operation can corrupt a live exposure or slew.
//!
//! # `as`-cast policy
//!
//! All `as` casts in this file are capability-probe widenings:
//! - **Sensor i32 → u32** (lines 517, 518): ASCOM CameraXSize/YSize are
//!   int per spec, ≥ 1 physically; `unwrap_or(0)` on the optional probe
//!   maps a missing/failed read to 0 (UI displays "unknown"). i32 → u32
//!   for non-negative i32 is a SAFE narrowing.
//! - **usize → i32 filter count** (lines 603, 998): physical filter wheels
//!   have ≤ 16 slots; saturation at i32::MAX is unreachable.
//! - **i32 → i32 filter position** (lines 604, 994, 1517): no-op widening
//!   kept for clarity around the `.map(|p| p as i32)` Option-mapping
//!   idiom in the surrounding code.
//!
//! # Example
//!
//! ```rust
//! let caps = api_get_mount_capabilities(mount_id).await?;
//! if caps.can_pulse_guide {
//!     // Enable PHD2-style guiding
//! }
//! ```

use crate::device_id::parse_device_id_cached;
use crate::error::NightshadeError;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};
use tokio::sync::{Mutex, RwLock};
// Re-use enums from device module to avoid FRB conflicts
use crate::device::{CalibratorState, CoverState, TrackingRate};

// Import NativeDevice trait for connect/disconnect methods
#[cfg(windows)]
use nightshade_native::traits::NativeDevice;

// =========================================================================
// Mount Capabilities
// =========================================================================

/// Capabilities of a mount/telescope device
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct MountCapabilities {
    /// Whether the mount can perform slew operations
    pub can_slew: bool,
    /// Whether the mount supports async (non-blocking) slews
    pub can_slew_async: bool,
    /// Whether the mount can sync its position to coordinates
    pub can_sync: bool,
    /// Whether the mount can be parked
    pub can_park: bool,
    /// Whether the mount can be unparked
    pub can_unpark: bool,
    /// Whether the mount can set its park position
    pub can_set_park: bool,
    /// Whether the mount supports pulse guiding
    pub can_pulse_guide: bool,
    /// Whether the mount can report side of pier
    pub can_get_side_of_pier: bool,
    /// Whether the mount can set side of pier (for meridian flips)
    pub can_set_side_of_pier: bool,
    /// Whether tracking can be enabled/disabled
    pub can_set_tracking: bool,
    /// Whether the tracking rate can be changed
    pub can_set_tracking_rate: bool,
    /// Supported tracking rates
    pub supported_tracking_rates: Vec<TrackingRate>,
    /// Whether the mount is an equatorial type (has RA/Dec)
    pub is_equatorial: bool,
    /// Whether the mount supports altitude/azimuth coordinates
    pub supports_alt_az: bool,
    /// Whether the mount can report its pointing state (normal/beyond pole)
    pub can_get_pointing_state: bool,
    /// Whether the mount has a home position
    pub can_find_home: bool,
    /// Whether the mount is currently tracking
    pub tracking: Option<bool>,
    /// Current tracking rate if known
    pub tracking_rate: Option<TrackingRate>,
    /// Whether the mount can abort slews
    pub can_abort_slew: bool,
    /// Maximum slew rate in degrees/second, if known
    pub max_slew_rate: Option<f64>,
    /// Whether the mount supports move axis commands
    pub can_move_axis: bool,
    /// Number of axes the mount supports (typically 2 for RA/Dec or Az/Alt)
    pub axis_count: u32,
    /// Minimum supported pulse-guide duration in milliseconds, if the driver
    /// publishes a guide-rate range. `None` means the driver does not report a
    /// lower bound (ASCOM/Alpaca have no such property; only INDI's
    /// `TELESCOPE_TIMED_GUIDE_*` number limits expose it).
    pub min_pulse_guide_ms: Option<f64>,
    /// Maximum supported pulse-guide duration in milliseconds, if the driver
    /// publishes a guide-rate range. `None` means the driver does not report an
    /// upper bound.
    pub max_pulse_guide_ms: Option<f64>,
}

// TrackingRate is imported from crate::device

// =========================================================================
// Camera Capabilities
// =========================================================================

/// Capabilities of a camera device
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CameraCapabilities {
    /// Maximum horizontal resolution in pixels
    pub max_width: u32,
    /// Maximum vertical resolution in pixels
    pub max_height: u32,
    /// Number of bits per pixel (e.g., 16 for 16-bit camera)
    pub bit_depth: u32,
    /// Whether the camera has a mechanical shutter
    pub has_shutter: bool,
    /// Whether the camera supports cooling
    pub can_set_ccd_temperature: bool,
    /// Whether the cooler can be turned on/off
    pub can_set_cooler: bool,
    /// Whether the camera reports cooler power
    pub can_get_cooler_power: bool,
    /// Whether binning is supported
    pub can_bin: bool,
    /// Maximum horizontal binning factor
    pub max_bin_x: i32,
    /// Maximum vertical binning factor
    pub max_bin_y: i32,
    /// Whether asymmetric binning is supported (bin_x != bin_y)
    pub can_asymmetric_bin: bool,
    /// Whether the camera supports gain adjustment
    pub can_set_gain: bool,
    /// Minimum gain value
    pub gain_min: Option<i32>,
    /// Maximum gain value
    pub gain_max: Option<i32>,
    /// Whether the camera supports offset adjustment
    pub can_set_offset: bool,
    /// Minimum offset value
    pub offset_min: Option<i32>,
    /// Maximum offset value
    pub offset_max: Option<i32>,
    /// Whether the camera can abort exposures
    pub can_abort_exposure: bool,
    /// Whether the camera can stop exposures (graceful stop)
    pub can_stop_exposure: bool,
    /// Whether the camera supports subframe readout
    pub can_subframe: bool,
    /// Pixel size in microns (X)
    pub pixel_size_x: Option<f64>,
    /// Pixel size in microns (Y)
    pub pixel_size_y: Option<f64>,
    /// Whether the camera has a color sensor
    pub is_color: bool,
    /// Bayer pattern if color (e.g., "RGGB")
    pub bayer_pattern: Option<String>,
    /// Sensor type description
    pub sensor_type: Option<String>,
    /// Whether the camera supports fast readout mode
    pub has_fast_readout: bool,
    /// Available readout modes
    pub readout_modes: Vec<String>,
    /// Minimum exposure time in seconds
    pub exposure_min: Option<f64>,
    /// Maximum exposure time in seconds
    pub exposure_max: Option<f64>,
    /// Current sensor temperature if available
    pub ccd_temperature: Option<f64>,
    /// Current cooler setpoint if available
    pub set_ccd_temperature: Option<f64>,
    /// Current cooler power percentage if available
    pub cooler_power: Option<f64>,
    /// Whether cooler is currently on
    pub cooler_on: Option<bool>,
    /// Minimum achievable cooler setpoint in Celsius, if the driver publishes
    /// the regulated-cooling range. `None` means the achievable range is
    /// unknown (ASCOM/Alpaca ICameraV3 has no SetCCDTemperature min/max; only
    /// INDI's `CCD_TEMPERATURE` number limits and some native vendor SDKs
    /// expose it).
    pub cooler_min_temp_c: Option<f64>,
    /// Maximum achievable cooler setpoint in Celsius, if the driver publishes
    /// the regulated-cooling range. `None` means the achievable range is
    /// unknown.
    pub cooler_max_temp_c: Option<f64>,
}

/// Manufacturer-recommended camera gain/offset values reported by the vendor SDK.
///
/// Populated on a best-effort basis on camera connect. Vendors expose these
/// inconsistently — the field is `None` whenever the SDK does NOT report a
/// value. Callers MUST treat `None` as "the SDK didn't tell us"; never
/// fabricate a recommendation.
///
/// Sources used by the bridge:
/// - ZWO: `ASIControlCaps.default_value` for `ASI_GAIN` and `ASI_OFFSET`,
///   combined with `ASICameraInfo.elec_per_adu` for the notes string.
/// - QHY: `DefaultGain` (control ID 53) and `DefaultOffset` (control ID 54),
///   probed via `IsQHYCCDControlAvailable` first.
/// - SVBony: `SvbControlCaps.default_value` for the Gain and BlackLevel controls.
/// - All other vendors (Touptek, Player One, Atik, FLI, Moravian, ASCOM,
///   Alpaca, INDI, gphoto2/Fujifilm): currently no SDK API for unity gain —
///   honest `None`. The `notes` field will be empty.
///
/// `hcg_gain` (HCG transition point) is currently always `None` — no vendor
/// SDK exposes this programmatically (it's documented in the manual).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CameraRecommendedSettings {
    /// Manufacturer-recommended unity gain (1 e-/ADU), if the SDK exposes it.
    pub unity_gain: Option<i32>,
    /// Gain at which HCG (high conversion gain) engages, if the SDK exposes it.
    pub hcg_gain: Option<i32>,
    /// Manufacturer-recommended default offset/bias, if the SDK exposes it.
    pub default_offset: Option<i32>,
    /// Manufacturer-recommended cooling setpoint in Celsius, if the SDK exposes
    /// it. Currently always `None` — no vendor SDK we bind publishes a
    /// recommended setpoint (see the native struct's doc comment). The field
    /// gives the profile layer an honest, typed slot for the value the instant
    /// a vendor SDK starts reporting it.
    pub recommended_cooling_setpoint_c: Option<f64>,
    /// Human-readable explanation of where the values above came from.
    /// Empty when nothing was queryable.
    pub notes: String,
}

impl From<nightshade_native::camera::CameraRecommendedSettings> for CameraRecommendedSettings {
    fn from(src: nightshade_native::camera::CameraRecommendedSettings) -> Self {
        Self {
            unity_gain: src.unity_gain,
            hcg_gain: src.hcg_gain,
            default_offset: src.default_offset,
            recommended_cooling_setpoint_c: src.recommended_cooling_setpoint_c,
            notes: src.notes,
        }
    }
}

// =========================================================================
// Focuser Capabilities
// =========================================================================

/// Capabilities of a focuser device
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct FocuserCapabilities {
    /// Maximum position in steps
    pub max_position: i32,
    /// Maximum step increment per move
    pub max_increment: i32,
    /// Step size in microns (if known)
    pub step_size: Option<f64>,
    /// Whether the focuser can move in absolute positions
    pub absolute: bool,
    /// Whether the focuser supports temperature compensation
    pub temp_comp_available: bool,
    /// Whether temperature compensation is currently enabled
    pub temp_comp: bool,
    /// Current temperature at focuser (if sensor available)
    pub temperature: Option<f64>,
    /// Whether the focuser is currently moving
    pub is_moving: bool,
    /// Current position in steps
    pub position: Option<i32>,
    /// Whether the focuser can halt movement
    pub can_halt: bool,
    /// Whether the focuser can reverse direction
    pub can_reverse: bool,
    /// Current reverse setting
    pub reverse: Option<bool>,
}

// =========================================================================
// Filter Wheel Capabilities
// =========================================================================

/// Capabilities of a filter wheel device
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct FilterWheelCapabilities {
    /// Number of filter positions
    pub position_count: i32,
    /// Current filter position (0-indexed)
    pub current_position: Option<i32>,
    /// Filter names for each position
    pub filter_names: Vec<String>,
    /// Focus offsets for each filter (in focuser steps)
    pub focus_offsets: Vec<i32>,
    /// Whether the wheel is currently moving
    pub is_moving: bool,
    /// Whether filter names can be set
    pub can_set_filter_names: bool,
    /// Whether focus offsets can be set
    pub can_set_focus_offsets: bool,
}

// =========================================================================
// Rotator Capabilities
// =========================================================================

/// Capabilities of a rotator device
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RotatorCapabilities {
    /// Whether the rotator can reverse direction
    pub can_reverse: bool,
    /// Current reverse setting
    pub reverse: bool,
    /// Step size in degrees
    pub step_size: Option<f64>,
    /// Whether the rotator is currently moving
    pub is_moving: bool,
    /// Current mechanical position in degrees
    pub mechanical_position: Option<f64>,
    /// Current position in degrees (may differ from mechanical due to sync)
    pub position: Option<f64>,
    /// Whether the rotator can move to absolute positions
    pub can_move_absolute: bool,
    /// Whether the rotator can halt movement
    pub can_halt: bool,
    /// Whether the rotator can sync to a position
    pub can_sync: bool,
    /// Minimum mechanical angle in degrees, if the driver publishes the angle
    /// range. `None` means the range is implicit/unknown (ASCOM/Alpaca IRotator
    /// has no min/max property — the mechanical range is unbounded 0–360 by
    /// contract; only INDI's `ABS_ROTATOR_ANGLE` number limits expose it).
    pub min_angle_deg: Option<f64>,
    /// Maximum mechanical angle in degrees, if the driver publishes the angle
    /// range. `None` means the range is implicit/unknown.
    pub max_angle_deg: Option<f64>,
}

// =========================================================================
// Dome Capabilities
// =========================================================================

/// Capabilities of a dome device
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DomeCapabilities {
    /// Whether the dome can slew to a specific azimuth
    pub can_set_azimuth: bool,
    /// Whether the dome can be parked
    pub can_park: bool,
    /// Whether the dome can find home
    pub can_find_home: bool,
    /// Whether the dome has a controllable shutter
    pub can_set_shutter: bool,
    /// Whether the dome can sync its position
    pub can_sync_azimuth: bool,
    /// Current azimuth in degrees (if known)
    pub azimuth: Option<f64>,
    /// Whether the dome is currently slewing
    pub slewing: bool,
    /// Whether the dome is at home
    pub at_home: bool,
    /// Whether the dome is at park
    pub at_park: bool,
    /// Current shutter status
    pub shutter_status: Option<ShutterStatus>,
    /// Whether slave mode is available
    pub can_slave: bool,
    /// Whether slave mode is currently enabled
    pub slaved: bool,
    /// Whether the dome can abort movement
    pub can_abort: bool,
}

/// Dome shutter status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ShutterStatus {
    /// Shutter is fully open
    Open,
    /// Shutter is fully closed
    Closed,
    /// Shutter is currently opening
    Opening,
    /// Shutter is currently closing
    Closing,
    /// Shutter status is unknown or error state
    Unknown,
}

impl Default for ShutterStatus {
    fn default() -> Self {
        ShutterStatus::Unknown
    }
}

// =========================================================================
// Cover Calibrator Capabilities
// =========================================================================

/// Capabilities of a cover calibrator device
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CoverCalibratorCapabilities {
    /// Maximum brightness level (0 if no calibrator)
    pub max_brightness: i32,
    /// Whether the device has a cover
    pub cover_present: bool,
    /// Whether the device has a calibrator light
    pub calibrator_present: bool,
    /// Current cover state
    pub cover_state: Option<CoverState>,
    /// Current calibrator state
    pub calibrator_state: Option<CalibratorState>,
    /// Current brightness level
    pub brightness: Option<i32>,
}

// CoverState is imported from crate::device

// CalibratorState is imported from crate::device

// =========================================================================
// Weather Capabilities
// =========================================================================

/// Capabilities of a weather/observing conditions device
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct WeatherCapabilities {
    /// Whether cloud cover is reported
    pub has_cloud_cover: bool,
    /// Whether dew point is reported
    pub has_dew_point: bool,
    /// Whether humidity is reported
    pub has_humidity: bool,
    /// Whether pressure is reported
    pub has_pressure: bool,
    /// Whether rain rate is reported
    pub has_rain_rate: bool,
    /// Whether sky brightness is reported
    pub has_sky_brightness: bool,
    /// Whether sky quality (mag/arcsec^2) is reported
    pub has_sky_quality: bool,
    /// Whether sky temperature is reported
    pub has_sky_temperature: bool,
    /// Whether seeing is reported
    pub has_seeing: bool,
    /// Whether temperature is reported
    pub has_temperature: bool,
    /// Whether wind direction is reported
    pub has_wind_direction: bool,
    /// Whether wind gust is reported
    pub has_wind_gust: bool,
    /// Whether wind speed is reported
    pub has_wind_speed: bool,
    /// Average time between sensor updates in seconds
    pub average_period: Option<f64>,
}

// =========================================================================
// Safety Monitor Capabilities
// =========================================================================

/// Capabilities of a safety monitor device
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SafetyMonitorCapabilities {
    /// Current safe status
    pub is_safe: bool,
    /// Description of current safety state
    pub safety_description: Option<String>,
}

// =========================================================================
// Switch Capabilities
// =========================================================================

/// Capabilities of a switch device
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SwitchCapabilities {
    /// Number of switches
    pub switch_count: i32,
    /// Switch details
    pub switches: Vec<SwitchInfo>,
}

/// Information about a single switch
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SwitchInfo {
    /// Switch index
    pub index: i32,
    /// Switch name
    pub name: String,
    /// Switch description
    pub description: String,
    /// Whether this is a boolean switch (vs. analog)
    pub is_boolean: bool,
    /// Minimum value (for analog switches)
    pub min_value: f64,
    /// Maximum value (for analog switches)
    pub max_value: f64,
    /// Step increment (for analog switches)
    pub step: f64,
    /// Whether the switch can be written
    pub can_write: bool,
    /// Current value
    pub value: f64,
}

// =========================================================================
// API Functions
// =========================================================================

const CAPABILITY_CACHE_TTL: Duration = Duration::from_secs(300);

#[derive(Debug, Clone)]
struct CapabilityCacheEntry {
    capabilities: DeviceCapabilities,
    timestamp: Instant,
}

static CAPABILITY_CACHE: OnceLock<Mutex<HashMap<String, CapabilityCacheEntry>>> = OnceLock::new();

fn capability_cache() -> &'static Mutex<HashMap<String, CapabilityCacheEntry>> {
    CAPABILITY_CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

#[cfg(windows)]
fn capability_probe_should_own_connection(connection_state: Result<bool, String>) -> bool {
    matches!(connection_state, Ok(false))
}

#[cfg(windows)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AscomCapabilityDeviceType {
    Camera,
    Mount,
    Focuser,
    FilterWheel,
    Rotator,
    Dome,
    SafetyMonitor,
    Weather,
    Switch,
    CoverCalibrator,
}

#[cfg(windows)]
fn normalize_ascom_capability_device_type(value: &str) -> Option<AscomCapabilityDeviceType> {
    let normalized = value
        .trim()
        .to_ascii_lowercase()
        .replace([' ', '-', '_'], "");
    match normalized.as_str() {
        "camera" | "icamera" | "icamerav2" | "icamerav3" | "icamerav4" => {
            Some(AscomCapabilityDeviceType::Camera)
        }
        "telescope" | "mount" | "itelescope" | "itelescopev2" | "itelescopev3" => {
            Some(AscomCapabilityDeviceType::Mount)
        }
        "focuser" | "ifocuser" | "ifocuserv2" | "ifocuserv3" => {
            Some(AscomCapabilityDeviceType::Focuser)
        }
        "filterwheel" | "ifilterwheel" | "ifilterwheelv2" => {
            Some(AscomCapabilityDeviceType::FilterWheel)
        }
        "rotator" | "irotator" | "irotatorv2" | "irotatorv3" => {
            Some(AscomCapabilityDeviceType::Rotator)
        }
        "dome" | "idome" | "idomev2" => Some(AscomCapabilityDeviceType::Dome),
        "safetymonitor" | "isafetymonitor" | "isafetymonitorv1" => {
            Some(AscomCapabilityDeviceType::SafetyMonitor)
        }
        "observingconditions" | "weather" | "iobservingconditions" => {
            Some(AscomCapabilityDeviceType::Weather)
        }
        "switch" | "iswitch" | "iswitchv2" => Some(AscomCapabilityDeviceType::Switch),
        "covercalibrator" | "icovercalibrator" | "icovercalibratorv1" => {
            Some(AscomCapabilityDeviceType::CoverCalibrator)
        }
        _ => None,
    }
}

#[cfg(windows)]
fn ascom_registry_type_for_capabilities(
    device_type: AscomCapabilityDeviceType,
) -> nightshade_ascom::AscomDeviceType {
    match device_type {
        AscomCapabilityDeviceType::Camera => nightshade_ascom::AscomDeviceType::Camera,
        AscomCapabilityDeviceType::Mount => nightshade_ascom::AscomDeviceType::Telescope,
        AscomCapabilityDeviceType::Focuser => nightshade_ascom::AscomDeviceType::Focuser,
        AscomCapabilityDeviceType::FilterWheel => nightshade_ascom::AscomDeviceType::FilterWheel,
        AscomCapabilityDeviceType::Rotator => nightshade_ascom::AscomDeviceType::Rotator,
        AscomCapabilityDeviceType::Dome => nightshade_ascom::AscomDeviceType::Dome,
        AscomCapabilityDeviceType::SafetyMonitor => {
            nightshade_ascom::AscomDeviceType::SafetyMonitor
        }
        AscomCapabilityDeviceType::Weather => {
            nightshade_ascom::AscomDeviceType::ObservingConditions
        }
        AscomCapabilityDeviceType::Switch => nightshade_ascom::AscomDeviceType::Switch,
        AscomCapabilityDeviceType::CoverCalibrator => {
            nightshade_ascom::AscomDeviceType::CoverCalibrator
        }
    }
}

#[cfg(windows)]
fn ascom_capability_device_types() -> &'static [AscomCapabilityDeviceType] {
    &[
        AscomCapabilityDeviceType::Camera,
        AscomCapabilityDeviceType::Mount,
        AscomCapabilityDeviceType::Focuser,
        AscomCapabilityDeviceType::FilterWheel,
        AscomCapabilityDeviceType::Rotator,
        AscomCapabilityDeviceType::Dome,
        AscomCapabilityDeviceType::SafetyMonitor,
        AscomCapabilityDeviceType::Weather,
        AscomCapabilityDeviceType::Switch,
        AscomCapabilityDeviceType::CoverCalibrator,
    ]
}

#[cfg(windows)]
fn classify_ascom_capability_device_type(
    prog_id: &str,
) -> Result<AscomCapabilityDeviceType, String> {
    let _ = nightshade_ascom::init_com();
    if let Ok(device) = nightshade_ascom::AscomDeviceConnection::new(prog_id) {
        if let Ok(device_type) = device.get_string_property("DeviceType") {
            if let Some(device_type) = normalize_ascom_capability_device_type(&device_type) {
                return Ok(device_type);
            }
        }
    }

    for device_type in ascom_capability_device_types() {
        let registry_type = ascom_registry_type_for_capabilities(*device_type);
        if nightshade_ascom::discover_devices(registry_type)
            .iter()
            .any(|device| device.prog_id.eq_ignore_ascii_case(prog_id))
        {
            return Ok(*device_type);
        }
    }

    Err(format!(
        "Could not determine ASCOM device type for ProgID '{}': DeviceType property was unavailable and the ProgID was not found in ASCOM driver registry",
        prog_id
    ))
}

fn native_cover_state_to_capability(
    state: nightshade_native::traits::NativeCoverState,
) -> CoverState {
    match state {
        nightshade_native::traits::NativeCoverState::NotPresent => CoverState::NotPresent,
        nightshade_native::traits::NativeCoverState::Closed => CoverState::Closed,
        nightshade_native::traits::NativeCoverState::Moving => CoverState::Moving,
        nightshade_native::traits::NativeCoverState::Open => CoverState::Open,
        nightshade_native::traits::NativeCoverState::Unknown => CoverState::Unknown,
        nightshade_native::traits::NativeCoverState::Error => CoverState::Error,
    }
}

fn native_calibrator_state_to_capability(
    state: nightshade_native::traits::NativeCalibratorState,
) -> CalibratorState {
    match state {
        nightshade_native::traits::NativeCalibratorState::NotPresent => CalibratorState::NotPresent,
        nightshade_native::traits::NativeCalibratorState::Off => CalibratorState::Off,
        nightshade_native::traits::NativeCalibratorState::NotReady => CalibratorState::NotReady,
        nightshade_native::traits::NativeCalibratorState::Ready => CalibratorState::Ready,
        nightshade_native::traits::NativeCalibratorState::Unknown => CalibratorState::Unknown,
        nightshade_native::traits::NativeCalibratorState::Error => CalibratorState::Error,
    }
}

#[cfg(test)]
pub(crate) async fn invalidate_capability_cache() {
    let mut cache = capability_cache().lock().await;
    cache.clear();
}

pub(crate) async fn invalidate_capability_cache_for_device(device_id: &str) {
    if let Some(cache) = CAPABILITY_CACHE.get() {
        cache.lock().await.remove(device_id);
    }
}

/// Get capabilities for any device type
pub async fn get_device_capabilities(
    device_id: &str,
) -> Result<DeviceCapabilities, NightshadeError> {
    // Use cached parsing for better performance
    let parsed = parse_device_id_cached(device_id)?;

    {
        let mut cache = capability_cache().lock().await;
        if let Some(entry) = cache.get(device_id) {
            if entry.timestamp.elapsed() < CAPABILITY_CACHE_TTL {
                return Ok(entry.capabilities.clone());
            }
            cache.remove(device_id);
        }
    }

    // Return capability data from the backend-specific capability providers.
    let capabilities = match parsed.driver_type {
        crate::device::DriverType::Alpaca => get_alpaca_capabilities(device_id).await,
        crate::device::DriverType::Ascom => get_ascom_capabilities(device_id).await,
        crate::device::DriverType::Indi => get_indi_capabilities(device_id).await,
        crate::device::DriverType::Native => get_native_capabilities(device_id).await,
        crate::device::DriverType::Simulator => Ok(get_simulator_capabilities(device_id)),
    }?;

    let mut cache = capability_cache().lock().await;
    cache.insert(
        device_id.to_string(),
        CapabilityCacheEntry {
            capabilities: capabilities.clone(),
            timestamp: Instant::now(),
        },
    );

    Ok(capabilities)
}

/// Unified device capabilities enum
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DeviceCapabilities {
    Mount(MountCapabilities),
    Camera(CameraCapabilities),
    Focuser(FocuserCapabilities),
    FilterWheel(FilterWheelCapabilities),
    Rotator(RotatorCapabilities),
    Dome(DomeCapabilities),
    CoverCalibrator(CoverCalibratorCapabilities),
    Weather(WeatherCapabilities),
    SafetyMonitor(SafetyMonitorCapabilities),
    Switch(SwitchCapabilities),
}

/// Get capabilities for an Alpaca device
///
/// # Silent-fallback contract
///
/// This function probes optional ASCOM/Alpaca capability properties (`CanSlew`,
/// `CanPark`, etc.). Per the ASCOM specification, drivers signal "this feature is
/// not supported" by returning Alpaca error `0x400` (`NotImplemented`) or, on
/// transport failure, a HTTP/parse error. The capability struct exists exactly to
/// expose these advertised-feature flags to the UI; the lenient `unwrap_or(false)`
/// at each site is therefore the **correct** semantics: "if the driver refuses to
/// answer, treat the feature as unavailable rather than crashing the connection
/// dialog". The per-site `// Why:` annotations below cite the specific ASCOM
/// property each fallback represents.
async fn get_alpaca_capabilities(device_id: &str) -> Result<DeviceCapabilities, NightshadeError> {
    // Use cached parsing for better performance
    let parsed = parse_device_id_cached(device_id)?;
    let (_, _, _, device_type, device_num) = parsed
        .alpaca_info()
        .ok_or_else(|| NightshadeError::invalid_device_id(device_id, "Not an Alpaca device"))?;
    let base_url = parsed
        .alpaca_base_url()
        .ok_or_else(|| NightshadeError::invalid_device_id(device_id, "Missing base URL"))?;

    match device_type {
        "telescope" | "mount" => {
            let telescope = nightshade_alpaca::AlpacaTelescope::from_server(base_url, device_num);

            // probe-and-restore. If the driver is already connected
            // (e.g. the UI has the mount open), reuse the connection rather
            // than connect/disconnect-ing around the property reads, which
            // would kick the active session. `is_connected()` Err → assume
            // connected (fail-safe: never disconnect a session we can't prove
            // we opened).
            let was_connected = telescope.is_connected().await.unwrap_or(true);
            if !was_connected {
                telescope
                    .connect()
                    .await
                    .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
            }

            // Why: every `CanXxx` flag below maps to an OPTIONAL ASCOM telescope
            // property. Drivers that don't implement a capability return 0x400 /
            // NotImplemented; defaulting to `false` means "feature absent" — the
            // intended ASCOM contract for capability discovery.
            let caps = MountCapabilities {
                can_slew: telescope.can_slew().await.unwrap_or(false), // Why: ASCOM ITelescopeV3.CanSlew (optional)
                can_slew_async: telescope.can_slew_async().await.unwrap_or(false), // Why: ASCOM ITelescopeV3.CanSlewAsync (optional)
                can_sync: telescope.can_sync().await.unwrap_or(false), // Why: ASCOM ITelescopeV3.CanSync (optional)
                can_park: telescope.can_park().await.unwrap_or(false), // Why: ASCOM ITelescopeV3.CanPark (optional)
                can_unpark: telescope.can_unpark().await.unwrap_or(false), // Why: ASCOM ITelescopeV3.CanUnpark (optional)
                can_set_park: telescope.can_set_park().await.unwrap_or(false), // Why: ASCOM ITelescopeV3.CanSetPark (optional)
                can_pulse_guide: telescope.can_pulse_guide().await.unwrap_or(false), // Why: ASCOM ITelescopeV3.CanPulseGuide (optional)
                can_set_tracking: telescope.can_set_tracking().await.unwrap_or(false), // Why: ASCOM ITelescopeV3.CanSetTracking (optional)
                // Why: ASCOM EquatorialSystem enum (0=Other, 1=Topocentric…). Treating an
                // unreadable value as "0 → not equatorial" is conservative: AltAz-only
                // mounts return 0 explicitly, so the downstream UI shouldn't enable
                // RA/Dec controls if the property is missing.
                is_equatorial: telescope.equatorial_system().await.unwrap_or(0) > 0,
                can_find_home: telescope.can_find_home().await.unwrap_or(false), // Why: ASCOM ITelescopeV3.CanFindHome (optional)
                tracking: telescope.tracking().await.ok(),
                can_abort_slew: true, // Most mounts support abort
                axis_count: 2,        // Alpaca lacks axis_count method, default to 2
                // Why: ASCOM/Alpaca ITelescopeV3 has NO pulse-guide duration-range
                // property — PulseGuide(direction, duration) accepts any non-negative
                // duration and the spec defines no min/max. None = "range unknown",
                // so the UI imposes no artificial clamp on guide-pulse length.
                min_pulse_guide_ms: None,
                max_pulse_guide_ms: None,
                ..Default::default()
            };

            if !was_connected {
                telescope.disconnect().await.ok();
            }
            Ok(DeviceCapabilities::Mount(caps))
        }
        "camera" => {
            let camera = nightshade_alpaca::AlpacaCamera::from_server(base_url, device_num);

            // see top-level docblock. Reuse existing connection if
            // the driver already has it open.
            let was_connected = camera.is_connected().await.unwrap_or(true);
            if !was_connected {
                camera
                    .connect()
                    .await
                    .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
            }

            // Why: ASCOM ICameraV3 capability struct. `CameraXSize/YSize` and `MaxADU`
            // are MANDATORY for any working camera, but we tolerate failure to keep
            // the capability dialog usable on partially-broken drivers (the user
            // will see "0x0 sensor" and disconnect). All `Can*` and `MaxBinX/Y` are
            // optional; defaulting bin to 1 means "no binning supported", which
            // matches the ASCOM convention for cameras that omit `MaxBinX`.
            let caps = CameraCapabilities {
                // Why: ICameraV3.CameraXSize is mandatory but treating 0 as "unknown
                // sensor" lets the dialog open even if the driver flakes out on first
                // query; user sees clearly-broken dimensions and reconnects.
                max_width: camera.camera_x_size().await.unwrap_or(0) as u32,
                max_height: camera.camera_y_size().await.unwrap_or(0) as u32, // Why: same as max_width above
                bit_depth: camera
                    .max_adu()
                    .await
                    .map(|a| {
                        if a > 65535 {
                            32
                        } else if a > 255 {
                            16
                        } else {
                            8
                        }
                    })
                    // Why: ICameraV3.MaxADU missing → assume the dominant astro-CCD
                    // depth of 16-bit. 8-bit cameras are vanishingly rare; assuming
                    // 16-bit avoids truncating real 16-bit data should the driver
                    // recover later in the session.
                    .unwrap_or(16),
                has_shutter: camera.has_shutter().await.unwrap_or(false), // Why: ICameraV3.HasShutter (optional, cooled CCDs only)
                can_set_ccd_temperature: camera.can_set_ccd_temperature().await.unwrap_or(false), // Why: ICameraV3.CanSetCCDTemperature (optional)
                // Why: ICameraV3.MaxBinX absent → assume bin 1×1 (no binning), the
                // safest assumption that prevents the UI from offering bin modes
                // the driver may reject.
                can_bin: camera.max_bin_x().await.unwrap_or(1) > 1,
                max_bin_x: camera.max_bin_x().await.unwrap_or(1), // Why: same MaxBinX rationale
                max_bin_y: camera.max_bin_y().await.unwrap_or(1), // Why: same — MaxBinY absent → 1
                can_abort_exposure: camera.can_abort_exposure().await.unwrap_or(false), // Why: ICameraV3.CanAbortExposure (optional)
                can_stop_exposure: camera.can_stop_exposure().await.unwrap_or(false), // Why: ICameraV3.CanStopExposure (optional)
                pixel_size_x: camera.pixel_size_x().await.ok(),
                pixel_size_y: camera.pixel_size_y().await.ok(),
                // Why: SensorType enum 0=Monochrome, >0 = color variant. If the
                // driver hides this property, default to monochrome — debayering
                // a mono frame is a no-op, debayering a hidden color sensor
                // produces a green frame, so mono is the safer fallback.
                is_color: camera.sensor_type().await.map(|t| t > 0).unwrap_or(false),
                exposure_min: None, // Alpaca lacks exposure_min method
                exposure_max: None, // Alpaca lacks exposure_max method
                // Why: ASCOM/Alpaca ICameraV3 exposes SetCCDTemperature (the
                // setpoint) but NO min/max bounds for it — the spec defines no
                // achievable-range property. None = "range unknown"; the UI shows
                // the setpoint field without inventing clamps.
                cooler_min_temp_c: None,
                cooler_max_temp_c: None,
                ..Default::default()
            };

            if !was_connected {
                camera.disconnect().await.ok();
            }
            Ok(DeviceCapabilities::Camera(caps))
        }
        "focuser" => {
            let focuser = nightshade_alpaca::AlpacaFocuser::from_server(base_url, device_num);

            // see top-level docblock.
            let was_connected = focuser.is_connected().await.unwrap_or(true);
            if !was_connected {
                focuser
                    .connect()
                    .await
                    .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
            }

            let caps = FocuserCapabilities {
                // Why: ASCOM IFocuserV3.MaxStep is mandatory but tolerating absence
                // with 0 keeps the dialog usable on relative-only focusers that
                // misreport. Downstream UI shows "max 0" → user disables auto-focus.
                max_position: focuser.max_step().await.unwrap_or(0),
                max_increment: focuser.max_increment().await.unwrap_or(0), // Why: IFocuserV3.MaxIncrement (mandatory but tolerated, same as MaxStep)
                step_size: focuser.step_size().await.ok(),
                absolute: focuser.absolute().await.unwrap_or(false), // Why: IFocuserV3.Absolute — default to relative focuser if unknown (safer: forces relative-move UI)
                temp_comp_available: focuser.temp_comp_available().await.unwrap_or(false), // Why: IFocuserV3.TempCompAvailable (optional)
                temp_comp: focuser.temp_comp().await.unwrap_or(false), // Why: IFocuserV3.TempComp — off by default if unreadable
                temperature: focuser.temperature().await.ok(),
                is_moving: focuser.is_moving().await.unwrap_or(false), // Why: IFocuserV3.IsMoving — "not moving" is the safer default; UI re-polls
                position: focuser.position().await.ok(),
                ..Default::default()
            };

            if !was_connected {
                focuser.disconnect().await.ok();
            }
            Ok(DeviceCapabilities::Focuser(caps))
        }
        "filterwheel" => {
            let fw = nightshade_alpaca::AlpacaFilterWheel::from_server(base_url, device_num);

            // see top-level docblock.
            let was_connected = fw.is_connected().await.unwrap_or(true);
            if !was_connected {
                fw.connect()
                    .await
                    .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
            }

            // Why: ASCOM IFilterWheelV2.Names is mandatory but tolerated. If the
            // driver fails the names lookup we surface an empty wheel (0 positions)
            // rather than aborting connection setup; user retries via "rescan".
            let names = fw.names().await.unwrap_or_default();
            // Why: IFilterWheelV2.FocusOffsets is mandatory and parallel to Names
            // but defaults to empty so the auto-focus subsystem skips per-filter
            // offset compensation rather than panicking on a missing array.
            let offsets = fw.focus_offsets().await.unwrap_or_default();

            let caps = FilterWheelCapabilities {
                position_count: names.len() as i32,
                current_position: fw.position().await.ok().map(|p| p as i32),
                filter_names: names,
                focus_offsets: offsets,
                is_moving: false, // Alpaca doesn't have a direct is_moving
                ..Default::default()
            };

            if !was_connected {
                fw.disconnect().await.ok();
            }
            Ok(DeviceCapabilities::FilterWheel(caps))
        }
        "rotator" => {
            let rotator = nightshade_alpaca::AlpacaRotator::from_server(base_url, device_num);

            // see top-level docblock.
            let was_connected = rotator.is_connected().await.unwrap_or(true);
            if !was_connected {
                rotator
                    .connect()
                    .await
                    .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
            }

            let caps = RotatorCapabilities {
                can_reverse: rotator.can_reverse().await.unwrap_or(false), // Why: ASCOM IRotatorV3.CanReverse (optional; pre-V3 rotators lack reversal)
                reverse: rotator.reverse().await.unwrap_or(false), // Why: IRotatorV3.Reverse — false (not reversed) is the safer default
                step_size: rotator.step_size().await.ok(),
                is_moving: rotator.is_moving().await.unwrap_or(false), // Why: IRotatorV3.IsMoving — "stationary" default; UI re-polls during slew
                mechanical_position: rotator.mechanical_position().await.ok(),
                position: rotator.position().await.ok(),
                can_move_absolute: true, // Alpaca rotators support absolute positioning
                can_halt: true,          // All rotators support halt
                can_sync: true,          // Most rotators support sync
                // Why: ASCOM/Alpaca IRotatorV3 has NO min/max angle property — the
                // mechanical range is implicit (positions wrap within 0–360 per the
                // spec). None = "range unknown / unbounded by contract".
                min_angle_deg: None,
                max_angle_deg: None,
            };

            if !was_connected {
                rotator.disconnect().await.ok();
            }
            Ok(DeviceCapabilities::Rotator(caps))
        }
        "dome" => {
            let dome = nightshade_alpaca::AlpacaDome::from_server(base_url, device_num);

            // see top-level docblock.
            let was_connected = dome.is_connected().await.unwrap_or(true);
            if !was_connected {
                dome.connect()
                    .await
                    .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
            }

            // Convert Alpaca ShutterStatus to our ShutterStatus
            let shutter_status = dome.shutter_status().await.ok().map(|s| match s {
                nightshade_alpaca::ShutterStatus::Open => ShutterStatus::Open,
                nightshade_alpaca::ShutterStatus::Closed => ShutterStatus::Closed,
                nightshade_alpaca::ShutterStatus::Opening => ShutterStatus::Opening,
                nightshade_alpaca::ShutterStatus::Closing => ShutterStatus::Closing,
                nightshade_alpaca::ShutterStatus::Error => ShutterStatus::Unknown,
            });

            // Why: ASCOM IDomeV2 `Can*` and state flags are all OPTIONAL per spec
            // (a clamshell-only dome implements almost none). Defaulting to false
            // means "feature absent / not in that state", which is the conservative
            // posture for a structure that costs money to mis-control.
            let caps = DomeCapabilities {
                can_set_azimuth: dome.can_set_azimuth().await.unwrap_or(false), // Why: IDomeV2.CanSetAzimuth (optional)
                can_park: dome.can_park().await.unwrap_or(false), // Why: IDomeV2.CanPark (optional)
                can_find_home: dome.can_find_home().await.unwrap_or(false), // Why: IDomeV2.CanFindHome (optional)
                can_set_shutter: dome.can_set_shutter().await.unwrap_or(false), // Why: IDomeV2.CanSetShutter (optional; clamshells often false)
                can_sync_azimuth: dome.can_sync_azimuth().await.unwrap_or(false), // Why: IDomeV2.CanSyncAzimuth (optional)
                azimuth: dome.azimuth().await.ok(),
                slewing: dome.slewing().await.unwrap_or(false), // Why: IDomeV2.Slewing — "not slewing" is the safe initial state
                at_home: dome.at_home().await.unwrap_or(false), // Why: IDomeV2.AtHome — "not at home" is the safe initial state
                at_park: dome.at_park().await.unwrap_or(false), // Why: IDomeV2.AtPark — assume not parked until proven otherwise
                shutter_status,
                can_slave: dome.can_slave().await.unwrap_or(false), // Why: IDomeV2.CanSlave (optional)
                slaved: dome.slaved().await.unwrap_or(false), // Why: IDomeV2.Slaved — "not slaved" is the safe default
                can_abort: true,                              // Alpaca domes support abort
            };

            if !was_connected {
                dome.disconnect().await.ok();
            }
            Ok(DeviceCapabilities::Dome(caps))
        }
        "covercalibrator" => {
            let cc = nightshade_alpaca::AlpacaCoverCalibrator::from_server(base_url, device_num);

            // see top-level docblock.
            let was_connected = cc.is_connected().await.unwrap_or(true);
            if !was_connected {
                cc.connect()
                    .await
                    .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
            }

            // Convert Alpaca CoverStatus to our CoverState
            let cover_state = cc.cover_state().await.ok().map(|s| match s {
                nightshade_alpaca::CoverStatus::NotPresent => CoverState::NotPresent,
                nightshade_alpaca::CoverStatus::Closed => CoverState::Closed,
                nightshade_alpaca::CoverStatus::Moving => CoverState::Moving,
                nightshade_alpaca::CoverStatus::Open => CoverState::Open,
                nightshade_alpaca::CoverStatus::Unknown => CoverState::Unknown,
                nightshade_alpaca::CoverStatus::Error => CoverState::Error,
            });

            // Convert Alpaca CalibratorStatus to our CalibratorState
            let calibrator_state = cc.calibrator_state().await.ok().map(|s| match s {
                nightshade_alpaca::CalibratorStatus::NotPresent => CalibratorState::NotPresent,
                nightshade_alpaca::CalibratorStatus::Off => CalibratorState::Off,
                nightshade_alpaca::CalibratorStatus::NotReady => CalibratorState::NotReady,
                nightshade_alpaca::CalibratorStatus::Ready => CalibratorState::Ready,
                nightshade_alpaca::CalibratorStatus::Unknown => CalibratorState::Unknown,
                nightshade_alpaca::CalibratorStatus::Error => CalibratorState::Error,
            });

            let caps = CoverCalibratorCapabilities {
                // Why: ICoverCalibratorV1.MaxBrightness is mandatory only when a
                // calibrator is present. Defaulting to 0 means "no brightness
                // levels available" — correct for cover-only devices where the
                // calibrator slot is absent.
                max_brightness: cc.max_brightness().await.unwrap_or(0),
                cover_present: cover_state.map_or(false, |s| s != CoverState::NotPresent),
                calibrator_present: calibrator_state
                    .map_or(false, |s| s != CalibratorState::NotPresent),
                cover_state,
                calibrator_state,
                brightness: cc.brightness().await.ok(),
            };

            if !was_connected {
                cc.disconnect().await.ok();
            }
            Ok(DeviceCapabilities::CoverCalibrator(caps))
        }
        "observingconditions" => {
            let weather =
                nightshade_alpaca::AlpacaObservingConditions::from_server(base_url, device_num);

            // see top-level docblock.
            let was_connected = weather.is_connected().await.unwrap_or(true);
            if !was_connected {
                weather
                    .connect()
                    .await
                    .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
            }

            // Check which sensors are available by trying to read them
            // If a sensor returns an error, it's likely not available
            let has_cloud_cover = weather.cloud_cover().await.is_ok();
            let has_dew_point = weather.dew_point().await.is_ok();
            let has_humidity = weather.humidity().await.is_ok();
            let has_pressure = weather.pressure().await.is_ok();
            let has_rain_rate = weather.rain_rate().await.is_ok();
            let has_sky_brightness = weather.sky_brightness().await.is_ok();
            let has_sky_quality = weather.sky_quality().await.is_ok();
            let has_sky_temperature = weather.sky_temperature().await.is_ok();
            // Note: star_fwhm/seeing is not part of the standard Alpaca observing conditions API
            let has_seeing = false;
            let has_temperature = weather.temperature().await.is_ok();
            let has_wind_direction = weather.wind_direction().await.is_ok();
            let has_wind_gust = weather.wind_gust().await.is_ok();
            let has_wind_speed = weather.wind_speed().await.is_ok();

            let caps = WeatherCapabilities {
                has_cloud_cover,
                has_dew_point,
                has_humidity,
                has_pressure,
                has_rain_rate,
                has_sky_brightness,
                has_sky_quality,
                has_sky_temperature,
                has_seeing,
                has_temperature,
                has_wind_direction,
                has_wind_gust,
                has_wind_speed,
                average_period: weather.average_period().await.ok(),
            };

            if !was_connected {
                weather.disconnect().await.ok();
            }
            Ok(DeviceCapabilities::Weather(caps))
        }
        "safetymonitor" => {
            let safety = nightshade_alpaca::AlpacaSafetyMonitor::from_server(base_url, device_num);

            // see top-level docblock.
            let was_connected = safety.is_connected().await.unwrap_or(true);
            if !was_connected {
                safety
                    .connect()
                    .await
                    .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
            }

            let caps = SafetyMonitorCapabilities {
                // Why: ISafetyMonitorV1.IsSafe is the entire raison-d'être of this
                // device. Defaulting to `false` ("not safe") on read failure is the
                // ONLY correct fallback — a comms error must NEVER be reported as
                // "safe to image". This is the conservative SafetyMonitor contract.
                is_safe: safety.is_safe().await.unwrap_or(false),
                safety_description: None, // Alpaca doesn't provide a description
            };

            safety.disconnect().await.ok();
            Ok(DeviceCapabilities::SafetyMonitor(caps))
        }
        "switch" => {
            let switch = nightshade_alpaca::AlpacaSwitch::from_server(base_url, device_num);
            switch
                .connect()
                .await
                .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

            // Why: ASCOM ISwitchV2.MaxSwitch is mandatory. Defaulting to 0 on
            // read failure means "no channels exposed" — the for-loop below then
            // returns an empty `switches` vec, which the UI shows as a switch
            // device with zero controllable outputs. User-visible, non-fatal.
            let max_switch = switch.max_switch().await.unwrap_or(0);
            let mut switches = Vec::new();

            for i in 0..max_switch {
                // Why: ISwitchV2.GetSwitchName(i) is mandatory but tolerating
                // failure with "Switch {i}" lets the user still discriminate
                // channels by index when a driver omits the name table.
                let name = switch
                    .get_switch_name(i)
                    .await
                    .unwrap_or_else(|_| format!("Switch {}", i));
                let description = switch.get_switch_description(i).await.unwrap_or_default(); // Why: ISwitchV2.GetSwitchDescription(i) — empty string OK; UI hides empty descriptions
                let min_value = switch.min_switch_value(i).await.unwrap_or(0.0); // Why: ISwitchV2.MinSwitchValue(i) — 0.0 matches the boolean-switch convention below
                let max_value = switch.max_switch_value(i).await.unwrap_or(1.0); // Why: ISwitchV2.MaxSwitchValue(i) — 1.0 pairs with 0.0 above to produce a boolean switch by default
                                                                                 // Alpaca doesn't provide switch step, default to 1.0
                let step = 1.0;
                let can_write = switch.can_write(i).await.unwrap_or(false); // Why: ISwitchV2.CanWrite(i) — read-only default forces user to verify before issuing writes
                let value = switch.get_switch_value(i).await.unwrap_or(0.0); // Why: ISwitchV2.GetSwitchValue(i) — 0.0 = "off" / lowest, the safest displayed state

                // Determine if this is a boolean switch
                // If min == 0 and max == 1, it's boolean
                let is_boolean = (min_value == 0.0 && max_value == 1.0) || (min_value == max_value);

                let switch_info = SwitchInfo {
                    index: i,
                    name,
                    description,
                    is_boolean,
                    min_value,
                    max_value,
                    step,
                    can_write,
                    value,
                };
                switches.push(switch_info);
            }

            let caps = SwitchCapabilities {
                switch_count: max_switch,
                switches,
            };

            switch.disconnect().await.ok();
            Ok(DeviceCapabilities::Switch(caps))
        }
        _ => Err(NightshadeError::not_supported(
            device_id,
            "get_capabilities",
        )),
    }
}

/// Get capabilities for an ASCOM device (Windows only)
///
/// # Silent-fallback contract
///
/// ASCOM drivers raise `PropertyNotImplementedException` (HRESULT `0x80040400`)
/// when asked for an optional property they don't implement. The COM wrappers
/// in `nightshade_ascom` translate that to `Err`. Each `unwrap_or(false / 0)`
/// below therefore preserves the documented ASCOM "feature absent" semantics —
/// the per-site `// Why:` annotations cite the specific COM property each
/// fallback represents. Forwarding these errors as `?` would prevent the
/// connection dialog from ever populating for partially-conforming drivers.
#[cfg(windows)]
async fn get_ascom_capabilities(device_id: &str) -> Result<DeviceCapabilities, NightshadeError> {
    use crate::ascom_wrapper::camera::AscomCameraWrapper;
    use crate::ascom_wrapper::mount::AscomMountWrapper;

    let parsed = parse_device_id_cached(device_id)?;
    let prog_id = match &parsed.connection_info {
        crate::device_id::ConnectionInfo::Ascom { prog_id } => prog_id.clone(),
        _ => {
            return Err(NightshadeError::invalid_device_id(
                device_id,
                "Not an ASCOM device",
            ))
        }
    };

    let device_type = classify_ascom_capability_device_type(&prog_id)
        .map_err(|e| NightshadeError::not_supported(device_id, &e))?;

    if device_type == AscomCapabilityDeviceType::Camera {
        // Query camera capabilities
        let mut wrapper = AscomCameraWrapper::new(prog_id.clone())
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        // Try to connect and get capabilities
        wrapper
            .connect()
            .await
            .map_err(|e| NightshadeError::connection_failed(device_id, format!("{:?}", e)))?;

        let ascom_caps = wrapper
            .get_capabilities()
            .await
            .map_err(|e| NightshadeError::hardware_error(device_id, format!("{:?}", e)))?;

        let _ = wrapper.disconnect().await; // Best-effort disconnect

        Ok(DeviceCapabilities::Camera(CameraCapabilities {
            max_width: ascom_caps.max_width,
            max_height: ascom_caps.max_height,
            bit_depth: ascom_caps.bit_depth,
            has_shutter: ascom_caps.has_shutter,
            can_set_ccd_temperature: ascom_caps.can_set_ccd_temperature,
            can_set_cooler: ascom_caps.can_set_ccd_temperature, // ASCOM doesn't distinguish
            can_get_cooler_power: ascom_caps.can_get_cooler_power,
            can_bin: ascom_caps.can_bin,
            max_bin_x: ascom_caps.max_bin_x,
            max_bin_y: ascom_caps.max_bin_y,
            can_abort_exposure: ascom_caps.can_abort_exposure,
            can_stop_exposure: ascom_caps.can_stop_exposure,
            pixel_size_x: ascom_caps.pixel_size_x,
            pixel_size_y: ascom_caps.pixel_size_y,
            is_color: ascom_caps.is_color,
            bayer_pattern: ascom_caps.bayer_pattern,
            sensor_type: ascom_caps.sensor_name,
            readout_modes: ascom_caps.readout_modes,
            // Why: ASCOM ICameraV3 exposes SetCCDTemperature (the setpoint) but no
            // property bounding the achievable range, so the wrapper cannot report
            // one. None = "range unknown"; the UI shows the setpoint field unclamped.
            cooler_min_temp_c: None,
            cooler_max_temp_c: None,
            ..Default::default()
        }))
    } else if device_type == AscomCapabilityDeviceType::Mount {
        // Query mount capabilities
        let mut wrapper = AscomMountWrapper::new(prog_id.clone())
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        wrapper
            .connect()
            .await
            .map_err(|e| NightshadeError::connection_failed(device_id, format!("{:?}", e)))?;

        let ascom_caps = wrapper
            .get_capabilities()
            .await
            .map_err(|e| NightshadeError::hardware_error(device_id, format!("{:?}", e)))?;

        let _ = wrapper.disconnect().await;

        Ok(DeviceCapabilities::Mount(MountCapabilities {
            can_slew: ascom_caps.can_slew,
            can_slew_async: ascom_caps.can_slew_async,
            can_sync: ascom_caps.can_sync,
            can_park: ascom_caps.can_park,
            can_unpark: ascom_caps.can_unpark,
            can_set_park: ascom_caps.can_set_park,
            can_pulse_guide: ascom_caps.can_pulse_guide,
            can_set_tracking: ascom_caps.can_set_tracking,
            can_find_home: ascom_caps.can_find_home,
            can_move_axis: ascom_caps.can_move_axis_primary || ascom_caps.can_move_axis_secondary,
            is_equatorial: ascom_caps.is_equatorial,
            axis_count: if ascom_caps.can_move_axis_secondary {
                2
            } else {
                1
            },
            // Why: ASCOM ITelescopeV3.PulseGuide accepts any non-negative duration
            // and the spec defines no min/max guide-pulse property, so the wrapper
            // cannot report a range. None = "range unknown" (no artificial clamp).
            min_pulse_guide_ms: None,
            max_pulse_guide_ms: None,
            ..Default::default()
        }))
    } else if device_type == AscomCapabilityDeviceType::Focuser {
        // For focuser, use the ASCOM library directly since we don't have a wrapper yet
        use nightshade_ascom::{init_com, AscomFocuser};

        // Initialize COM on this thread if needed
        let _ = init_com();

        let mut focuser = AscomFocuser::new(&prog_id)
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        let should_disconnect = capability_probe_should_own_connection(focuser.is_connected());
        if should_disconnect {
            focuser
                .connect()
                .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
        }

        let caps = focuser.get_capabilities();
        if should_disconnect {
            let _ = focuser.disconnect();
        }

        Ok(DeviceCapabilities::Focuser(FocuserCapabilities {
            // Why: ASCOM IFocuserV3.MaxStep — when wrapper returns None the
            // property threw PropertyNotImplementedException. 0 means "no
            // travel range advertised", which disables absolute-position UI.
            max_position: caps.max_step.unwrap_or(0),
            max_increment: caps.max_increment.unwrap_or(0), // Why: IFocuserV3.MaxIncrement — same contract as MaxStep above
            step_size: caps.step_size,
            absolute: caps.absolute.unwrap_or(false), // Why: IFocuserV3.Absolute — default to relative focuser if driver omits it (safer UX)
            temp_comp_available: caps.temp_comp_available.unwrap_or(false), // Why: IFocuserV3.TempCompAvailable (optional)
            ..Default::default()
        }))
    } else if device_type == AscomCapabilityDeviceType::FilterWheel {
        // For filter wheel, use the ASCOM library directly
        use nightshade_ascom::{init_com, AscomFilterWheel};

        let _ = init_com();

        let mut fw = AscomFilterWheel::new(&prog_id)
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        let should_disconnect = capability_probe_should_own_connection(fw.is_connected());
        if should_disconnect {
            fw.connect()
                .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
        }

        // Why: ASCOM IFilterWheelV2.Names is mandatory but tolerated. On
        // PropertyNotImplemented we expose an empty filter list — UI shows a
        // 0-position wheel and the user reconfigures the driver. Better than
        // failing the entire equipment-profile load on one bad accessor.
        let names = fw.names().unwrap_or_default();
        let focus_offsets = fw.focus_offsets().unwrap_or_default();
        let position = fw.position().ok();
        if should_disconnect {
            let _ = fw.disconnect();
        }

        Ok(DeviceCapabilities::FilterWheel(FilterWheelCapabilities {
            position_count: i32::try_from(names.len()).unwrap_or(i32::MAX),
            current_position: position,
            filter_names: names,
            focus_offsets,
            can_set_focus_offsets: false,
            ..Default::default()
        }))
    } else if device_type == AscomCapabilityDeviceType::Rotator {
        // Query rotator capabilities via ASCOM COM
        use nightshade_ascom::{init_com, AscomRotator};

        let _ = init_com();

        let mut rotator = AscomRotator::new(&prog_id)
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        let should_disconnect = capability_probe_should_own_connection(rotator.is_connected());
        if should_disconnect {
            rotator
                .connect()
                .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
        }

        let caps = RotatorCapabilities {
            // Why: ASCOM IRotator.InterfaceVersion — if missing, assume the
            // V1 baseline (version 0 < 3) which lacks CanReverse. This is
            // strictly conservative: CanReverse=true on a V1 driver would
            // be a UI bug (the driver throws on Reverse property access).
            can_reverse: rotator.interface_version().unwrap_or(0) >= 3,
            reverse: false,  // Must query if can_reverse is true
            step_size: None, // ASCOM rotators don't expose step size directly
            is_moving: rotator.is_moving().unwrap_or(false), // Why: IRotatorV3.IsMoving — "stationary" default; the polling loop will correct it on the next tick
            mechanical_position: rotator.mechanical_position().ok(),
            position: rotator.position().ok(),
            can_move_absolute: true, // All ASCOM rotators support MoveAbsolute
            can_halt: true,          // All ASCOM rotators support Halt
            // Why: Same interface-version contract as can_reverse above —
            // assume V1 (no Sync) when InterfaceVersion is unreadable.
            can_sync: rotator.interface_version().unwrap_or(0) >= 3,
            // Why: ASCOM IRotatorV3 has NO min/max angle property — the mechanical
            // range is implicit (positions wrap within 0–360 per spec). None =
            // "range unknown / unbounded by contract".
            min_angle_deg: None,
            max_angle_deg: None,
        };

        if should_disconnect {
            let _ = rotator.disconnect();
        }
        Ok(DeviceCapabilities::Rotator(caps))
    } else if device_type == AscomCapabilityDeviceType::Dome {
        // Query dome capabilities via ASCOM COM
        use nightshade_ascom::{init_com, AscomDome};

        let _ = init_com();

        let mut dome = AscomDome::new(&prog_id)
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        let should_disconnect = capability_probe_should_own_connection(dome.is_connected());
        if should_disconnect {
            dome.connect()
                .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
        }

        // Map ASCOM ShutterStatus integer to our ShutterStatus enum
        let shutter_status = dome.shutter_status().ok().map(|s| match s {
            0 => ShutterStatus::Open,
            1 => ShutterStatus::Closed,
            2 => ShutterStatus::Opening,
            3 => ShutterStatus::Closing,
            _ => ShutterStatus::Unknown,
        });

        let caps = DomeCapabilities {
            // Why: ASCOM IDomeV2 does not expose CanSetAzimuth directly. We
            // probe by attempting SlewToAzimuth(0); success means CanSetAzimuth.
            // On failure, fall back to whether Azimuth is readable — a dome
            // that reports its azimuth but rejects slew is still usable in
            // read-only roles (slaving by another scope's tracking).
            can_set_azimuth: dome
                .slew_to_azimuth(0.0)
                .is_ok()
                .then_some(true)
                .unwrap_or(dome.azimuth().is_ok()),
            can_park: dome.at_park().is_ok(),
            can_find_home: false, // ASCOM Dome doesn't expose CanFindHome directly; conservative
            can_set_shutter: shutter_status.is_some(),
            can_sync_azimuth: false, // ASCOM Dome SyncToAzimuth availability is driver-specific
            azimuth: dome.azimuth().ok(),
            slewing: dome.slewing().unwrap_or(false), // Why: IDomeV2.Slewing — "not slewing" is the safe initial state; polled afterwards
            at_home: false,
            at_park: dome.at_park().unwrap_or(false), // Why: IDomeV2.AtPark — assume "not parked" if unreadable so the user is prompted to park manually
            shutter_status,
            can_slave: false, // Conservative default
            slaved: false,
            can_abort: true, // All ASCOM domes support AbortSlew
        };

        if should_disconnect {
            let _ = dome.disconnect();
        }
        Ok(DeviceCapabilities::Dome(caps))
    } else if device_type == AscomCapabilityDeviceType::SafetyMonitor {
        // Query safety monitor capabilities via ASCOM COM
        use nightshade_ascom::{init_com, AscomSafetyMonitor};

        let _ = init_com();

        let mut safety = AscomSafetyMonitor::new(&prog_id)
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        let should_disconnect = capability_probe_should_own_connection(safety.is_connected());
        if should_disconnect {
            safety
                .connect()
                .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
        }

        let caps = SafetyMonitorCapabilities {
            // Why: ASCOM ISafetyMonitorV1.IsSafe — the entire purpose of this
            // device class. Defaulting to `false` ("not safe") on read failure
            // is mandatory: a COM error must NEVER be coerced into "safe to
            // image". This matches the ASCOM specification's fail-closed
            // safety contract.
            is_safe: safety.is_safe().unwrap_or(false),
            safety_description: safety.driver_info().ok(),
        };

        if should_disconnect {
            let _ = safety.disconnect();
        }
        Ok(DeviceCapabilities::SafetyMonitor(caps))
    } else if device_type == AscomCapabilityDeviceType::Weather {
        // Query observing conditions capabilities via ASCOM COM
        use nightshade_ascom::{init_com, AscomObservingConditions};

        let _ = init_com();

        let mut weather = AscomObservingConditions::new(&prog_id)
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        let should_disconnect = capability_probe_should_own_connection(weather.is_connected());
        if should_disconnect {
            weather
                .connect()
                .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
        }

        // Probe each sensor -- ASCOM throws PropertyNotImplementedException for unavailable sensors
        let caps = WeatherCapabilities {
            has_cloud_cover: weather.cloud_cover().is_ok(),
            has_dew_point: weather.dew_point().is_ok(),
            has_humidity: weather.humidity().is_ok(),
            has_pressure: weather.pressure().is_ok(),
            has_rain_rate: weather.rain_rate().is_ok(),
            has_sky_brightness: weather.sky_brightness().is_ok(),
            has_sky_quality: weather.sky_quality().is_ok(),
            has_sky_temperature: weather.sky_temperature().is_ok(),
            has_seeing: weather.star_fwhm().is_ok(),
            has_temperature: weather.temperature().is_ok(),
            has_wind_direction: weather.wind_direction().is_ok(),
            has_wind_gust: weather.wind_gust().is_ok(),
            has_wind_speed: weather.wind_speed().is_ok(),
            average_period: None, // ASCOM ObservingConditions doesn't expose AveragePeriod as a standard property
        };

        if should_disconnect {
            let _ = weather.disconnect();
        }
        Ok(DeviceCapabilities::Weather(caps))
    } else if device_type == AscomCapabilityDeviceType::Switch {
        // Query switch capabilities via ASCOM COM
        use nightshade_ascom::{init_com, AscomSwitch};

        let _ = init_com();

        let mut switch = AscomSwitch::new(&prog_id)
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        let should_disconnect = capability_probe_should_own_connection(switch.is_connected());
        if should_disconnect {
            switch
                .connect()
                .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
        }

        // Why: ASCOM ISwitchV2.MaxSwitch — 0 fallback means "no channels
        // advertised" so the loop produces an empty switches list; user sees
        // a switch device with no controllable outputs and reconfigures.
        let max_switch = switch.max_switch().unwrap_or(0);
        let mut switches = Vec::new();

        for i in 0..max_switch {
            // Why: ISwitchV2.GetSwitchName(i) — "Switch {i}" fallback lets the
            // user still discriminate channels by index when the driver omits
            // the name array.
            let name = switch
                .get_switch_name(i)
                .unwrap_or_else(|_| format!("Switch {}", i));
            let description = switch.get_switch_description(i).unwrap_or_default(); // Why: ISwitchV2.GetSwitchDescription(i) — empty OK; UI hides empty descriptions
            let min_value = switch.min_switch_value(i).unwrap_or(0.0); // Why: ISwitchV2.MinSwitchValue(i) — pairs with max=1.0 to form a boolean switch by default
            let max_value = switch.max_switch_value(i).unwrap_or(1.0); // Why: ISwitchV2.MaxSwitchValue(i) — see min_value
            let step = 1.0; // ASCOM ISwitchV2 doesn't expose SwitchStep
            let can_write = switch.can_write(i).unwrap_or(false); // Why: ISwitchV2.CanWrite(i) — read-only default forces user verification before issuing writes
            let value = switch.get_switch_value(i).unwrap_or(0.0); // Why: ISwitchV2.GetSwitchValue(i) — 0.0 = "off"/lowest, the safest displayed state
            let is_boolean = (min_value == 0.0 && max_value == 1.0) || (min_value == max_value);

            switches.push(SwitchInfo {
                index: i,
                name,
                description,
                is_boolean,
                min_value,
                max_value,
                step,
                can_write,
                value,
            });
        }

        let caps = SwitchCapabilities {
            switch_count: max_switch,
            switches,
        };

        if should_disconnect {
            let _ = switch.disconnect();
        }
        Ok(DeviceCapabilities::Switch(caps))
    } else if device_type == AscomCapabilityDeviceType::CoverCalibrator {
        // Query cover calibrator capabilities via ASCOM COM
        use nightshade_ascom::{init_com, AscomCoverCalibrator};

        let _ = init_com();

        let mut cc = AscomCoverCalibrator::new(&prog_id)
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        let should_disconnect = capability_probe_should_own_connection(cc.is_connected());
        if should_disconnect {
            cc.connect()
                .map_err(|e| NightshadeError::connection_failed(device_id, e))?;
        }

        // ASCOM CoverState: 0=NotPresent, 1=Closed, 2=Moving, 3=Open, 4=Unknown, 5=Error
        let cover_state = cc.cover_state().ok().map(|s| match s {
            0 => CoverState::NotPresent,
            1 => CoverState::Closed,
            2 => CoverState::Moving,
            3 => CoverState::Open,
            4 => CoverState::Unknown,
            5 => CoverState::Error,
            _ => CoverState::Unknown,
        });

        // ASCOM CalibratorState: 0=NotPresent, 1=Off, 2=NotReady, 3=Ready, 4=Unknown, 5=Error
        let calibrator_state = cc.calibrator_state().ok().map(|s| match s {
            0 => CalibratorState::NotPresent,
            1 => CalibratorState::Off,
            2 => CalibratorState::NotReady,
            3 => CalibratorState::Ready,
            4 => CalibratorState::Unknown,
            5 => CalibratorState::Error,
            _ => CalibratorState::Unknown,
        });

        let caps = CoverCalibratorCapabilities {
            // Why: ASCOM ICoverCalibratorV1.MaxBrightness is mandatory only
            // when a calibrator is present; cover-only devices throw
            // PropertyNotImplemented. 0 means "no brightness levels" which
            // disables the brightness slider — correct for cover-only setups.
            max_brightness: cc.max_brightness().unwrap_or(0),
            cover_present: cover_state.map_or(false, |s| s != CoverState::NotPresent),
            calibrator_present: calibrator_state
                .map_or(false, |s| s != CalibratorState::NotPresent),
            cover_state,
            calibrator_state,
            brightness: cc.brightness().ok(),
        };

        if should_disconnect {
            let _ = cc.disconnect();
        }
        Ok(DeviceCapabilities::CoverCalibrator(caps))
    } else {
        Err(NightshadeError::not_supported(
            device_id,
            "Unknown ASCOM device type",
        ))
    }
}

#[cfg(not(windows))]
async fn get_ascom_capabilities(device_id: &str) -> Result<DeviceCapabilities, NightshadeError> {
    Err(NightshadeError::not_supported(
        device_id,
        "ASCOM is only available on Windows",
    ))
}

fn indi_sensor_type_is_color(sensor_type: &str) -> bool {
    let normalized = sensor_type.to_ascii_lowercase();
    normalized.contains("color")
        || normalized.contains("colour")
        || normalized.contains("bayer")
        || normalized.contains("cfa")
        || normalized.contains("rgb")
        || normalized.contains("osc")
}

fn indi_readout_mode_label(mode: &nightshade_indi::IndiReadoutMode) -> String {
    if mode.label.is_empty() {
        mode.element.clone()
    } else {
        mode.label.clone()
    }
}

/// Get capabilities for an INDI device
///
/// INDI devices report capabilities through their property definitions.
/// This function queries the INDI server to discover what properties
/// (and thus capabilities) a device supports.
async fn get_indi_capabilities(device_id: &str) -> Result<DeviceCapabilities, NightshadeError> {
    use nightshade_indi::{IndiCamera, IndiClient, IndiFilterWheel, IndiFocuser, IndiPermission};

    let parsed = parse_device_id_cached(device_id)?;
    let (host, port, device_name) = match &parsed.connection_info {
        crate::device_id::ConnectionInfo::Indi {
            host,
            port,
            device_name,
        } => (host.clone(), *port, device_name.clone()),
        _ => {
            return Err(NightshadeError::invalid_device_id(
                device_id,
                "Not an INDI device",
            ))
        }
    };

    let server_key = format!("{}:{}", host, port);
    let client = {
        let mgr = crate::api::get_device_manager();
        if let Some(client) = mgr.indi_clients.read().await.get(&server_key).cloned() {
            client
        } else {
            let mut clients = mgr.indi_clients.write().await;
            if let Some(client) = clients.get(&server_key).cloned() {
                client
            } else {
                let mut new_client = IndiClient::new(&host, Some(port));
                new_client
                    .connect()
                    .await
                    .map_err(|e| NightshadeError::connection_failed(device_id, e.to_string()))?;
                let client = Arc::new(RwLock::new(new_client));
                clients.insert(server_key.clone(), Arc::clone(&client));
                client
            }
        }
    };

    // INDI servers publish capability-bearing property definitions
    // asynchronously after connect; reuse an existing populated client when
    // present, otherwise wait briefly for the newly pooled client to hydrate.
    let start = std::time::Instant::now();
    let properties = loop {
        let properties = {
            let locked_client = client.read().await;
            locked_client.get_properties(&device_name).await
        };
        if !properties.is_empty() || start.elapsed() >= std::time::Duration::from_secs(1) {
            break properties;
        }
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    };

    // Determine device type based on standard INDI property names
    let has_ccd_props = properties
        .iter()
        .any(|p| p.name.starts_with("CCD_") || p.name == "CCD_EXPOSURE");
    let has_telescope_props = properties
        .iter()
        .any(|p| p.name.starts_with("EQUATORIAL_") || p.name == "TELESCOPE_MOTION_NS");
    let has_focuser_props = properties
        .iter()
        .any(|p| p.name.starts_with("FOCUS_") || p.name == "ABS_FOCUS_POSITION");
    let has_filter_props = properties
        .iter()
        .any(|p| p.name.starts_with("FILTER_") || p.name == "FILTER_SLOT");
    // Mirrors the rotator detection in indi/src/discovery.rs (ABS_ROTATOR_ANGLE
    // is the absolute-position rotator; ROTATOR_ANGLE is the legacy/raw form).
    let has_rotator_props = properties
        .iter()
        .any(|p| p.name == "ABS_ROTATOR_ANGLE" || p.name == "ROTATOR_ANGLE");

    // Build capabilities based on discovered properties
    if has_ccd_props {
        // Check for specific CCD capabilities
        let can_abort = properties.iter().any(|p| p.name == "CCD_ABORT_EXPOSURE");
        let has_cooler = properties
            .iter()
            .any(|p| p.name == "CCD_COOLER" || p.name == "CCD_TEMPERATURE");
        let has_binning = properties.iter().any(|p| p.name == "CCD_BINNING");
        let has_subframe = properties.iter().any(|p| p.name == "CCD_FRAME");
        let has_gain = properties
            .iter()
            .any(|p| p.name == "CCD_GAIN" || p.name == "CCD_CONTROLS");
        let has_offset = properties.iter().any(|p| p.name == "CCD_OFFSET");

        let camera = IndiCamera::new(Arc::clone(&client), &device_name);
        let gain_range = camera.get_gain_range().await;
        let sensor_type = camera.get_sensor_type().await;
        let bayer_pattern = camera.get_bayer_pattern().await;
        let readout_modes = camera.get_readout_modes().await;
        let max_bin_x = camera.try_get_max_bin_x().await.ok().flatten().unwrap_or(0);
        let max_bin_y = camera.try_get_max_bin_y().await.ok().flatten().unwrap_or(0);
        let bit_depth = camera
            .get_bits_per_pixel()
            .await
            .and_then(|v| u32::try_from(v).ok())
            .unwrap_or(0);
        let sensor_type_is_color = sensor_type
            .as_deref()
            .map(indi_sensor_type_is_color)
            .unwrap_or(false);
        let is_color = bayer_pattern.is_some() || sensor_type_is_color;
        let readout_mode_names: Vec<String> =
            readout_modes.iter().map(indi_readout_mode_label).collect();

        // Why: INDI exposes the achievable regulated-cooling range via the
        // CCD_TEMPERATURE number property's min/max limits (the same source the
        // driver clamps the setpoint to). Absent property/limits → None ("range
        // unknown"), never a fabricated clamp.
        let (cooler_min_temp_c, cooler_max_temp_c) = {
            let locked_client = client.read().await;
            let limits = locked_client
                .get_number_limits(&device_name, "CCD_TEMPERATURE", "CCD_TEMPERATURE_VALUE")
                .await;
            (
                limits.as_ref().and_then(|l| l.min),
                limits.as_ref().and_then(|l| l.max),
            )
        };

        Ok(DeviceCapabilities::Camera(CameraCapabilities {
            can_abort_exposure: can_abort,
            can_set_ccd_temperature: has_cooler,
            can_set_cooler: has_cooler,
            can_bin: has_binning,
            max_bin_x,
            max_bin_y,
            can_asymmetric_bin: max_bin_x != max_bin_y,
            can_set_gain: has_gain,
            gain_min: gain_range.map(|(min, _)| min),
            gain_max: gain_range.map(|(_, max)| max),
            can_set_offset: has_offset,
            can_subframe: has_subframe,
            max_width: camera
                .get_sensor_width()
                .await
                .and_then(|v| u32::try_from(v).ok())
                .unwrap_or(0),
            max_height: camera
                .get_sensor_height()
                .await
                .and_then(|v| u32::try_from(v).ok())
                .unwrap_or(0),
            bit_depth,
            pixel_size_x: camera.get_pixel_size_x().await,
            pixel_size_y: camera.get_pixel_size_y().await,
            is_color,
            bayer_pattern: bayer_pattern.map(|p| p.pattern),
            sensor_type,
            has_fast_readout: readout_mode_names.len() > 1,
            readout_modes: readout_mode_names,
            cooler_min_temp_c,
            cooler_max_temp_c,
            ..Default::default()
        }))
    } else if has_telescope_props {
        let has_equatorial = properties.iter().any(|p| p.name.starts_with("EQUATORIAL_"));
        let supports_alt_az = properties.iter().any(|p| p.name == "HORIZONTAL_COORD");
        let can_park = properties.iter().any(|p| p.name == "TELESCOPE_PARK");
        let can_sync = properties.iter().any(|p| p.name == "ON_COORD_SET");
        let can_guide = properties
            .iter()
            .any(|p| p.name.starts_with("TELESCOPE_TIMED_GUIDE_"));
        let can_track = properties.iter().any(|p| p.name == "TELESCOPE_TRACK_STATE");
        let can_get_side_of_pier = properties.iter().any(|p| p.name == "TELESCOPE_PIER_SIDE");
        let can_set_tracking_rate = properties
            .iter()
            .any(|p| p.name == "TELESCOPE_TRACK_RATE" || p.name == "TELESCOPE_TRACK_MODE");
        let mut supported_tracking_rates = Vec::new();
        if properties.iter().any(|p| p.name == "TELESCOPE_TRACK_MODE") {
            supported_tracking_rates.extend([
                TrackingRate::Sidereal,
                TrackingRate::Lunar,
                TrackingRate::Solar,
                TrackingRate::King,
            ]);
        }
        let can_move_ns = properties.iter().any(|p| p.name == "TELESCOPE_MOTION_NS");
        let can_move_we = properties.iter().any(|p| p.name == "TELESCOPE_MOTION_WE");
        let max_slew_rate =
            if let Some(slew_rate) = properties.iter().find(|p| p.name == "TELESCOPE_SLEW_RATE") {
                let locked_client = client.read().await;
                let mut max_rate: Option<f64> = None;
                for element in &slew_rate.elements {
                    if let Some(max) = locked_client
                        .get_number_limits(&device_name, "TELESCOPE_SLEW_RATE", element)
                        .await
                        .and_then(|limits| limits.max)
                    {
                        max_rate = Some(max_rate.map_or(max, |current| current.max(max)));
                    }
                }
                max_rate
            } else {
                None
            };

        // Why: INDI publishes the achievable pulse-guide duration range as the
        // min/max number limits of the TELESCOPE_TIMED_GUIDE_NS (TIMED_GUIDE_N/S)
        // and TELESCOPE_TIMED_GUIDE_WE (TIMED_GUIDE_W/E) properties. We take the
        // smallest reported min and largest reported max across all four elements
        // — the union of both axes — so the UI never offers a pulse outside what
        // any axis accepts. Absent properties/limits → None ("range unknown"),
        // never a fabricated clamp. Mirrors the max_slew_rate element-scan above.
        let (min_pulse_guide_ms, max_pulse_guide_ms) = {
            const TIMED_GUIDE_PROPS: [&str; 2] =
                ["TELESCOPE_TIMED_GUIDE_NS", "TELESCOPE_TIMED_GUIDE_WE"];
            let mut min_pulse: Option<f64> = None;
            let mut max_pulse: Option<f64> = None;
            let locked_client = client.read().await;
            for prop_name in TIMED_GUIDE_PROPS {
                let Some(prop) = properties.iter().find(|p| p.name == prop_name) else {
                    continue;
                };
                for element in &prop.elements {
                    let Some(limits) = locked_client
                        .get_number_limits(&device_name, prop_name, element)
                        .await
                    else {
                        continue;
                    };
                    if let Some(min) = limits.min {
                        min_pulse = Some(min_pulse.map_or(min, |current| current.min(min)));
                    }
                    if let Some(max) = limits.max {
                        max_pulse = Some(max_pulse.map_or(max, |current| current.max(max)));
                    }
                }
            }
            (min_pulse, max_pulse)
        };

        Ok(DeviceCapabilities::Mount(MountCapabilities {
            can_slew: has_equatorial || supports_alt_az,
            can_slew_async: has_equatorial || supports_alt_az,
            can_sync,
            can_park,
            can_unpark: can_park,
            can_set_park: false,
            can_pulse_guide: can_guide,
            can_get_side_of_pier,
            can_set_tracking: can_track,
            can_set_tracking_rate,
            supported_tracking_rates,
            is_equatorial: has_equatorial,
            supports_alt_az,
            can_find_home: properties.iter().any(|p| p.name == "TELESCOPE_HOME"),
            can_abort_slew: properties
                .iter()
                .any(|p| p.name == "TELESCOPE_ABORT_MOTION"),
            max_slew_rate,
            can_move_axis: can_move_ns || can_move_we,
            axis_count: u32::from(can_move_ns) + u32::from(can_move_we),
            min_pulse_guide_ms,
            max_pulse_guide_ms,
            ..Default::default()
        }))
    } else if has_focuser_props {
        let is_absolute = properties.iter().any(|p| p.name == "ABS_FOCUS_POSITION");
        let has_temp_comp = properties
            .iter()
            .any(|p| p.name == "FOCUS_TEMPERATURE_COMP" || p.name == "FOCUS_TEMP_COMP");
        let can_halt = properties.iter().any(|p| p.name == "FOCUS_ABORT_MOTION");
        let focuser = IndiFocuser::new(Arc::clone(&client), &device_name);
        let max_position = focuser.get_max_step().await.unwrap_or(0);

        Ok(DeviceCapabilities::Focuser(FocuserCapabilities {
            max_position,
            max_increment: max_position,
            step_size: focuser.get_step_size().await,
            absolute: is_absolute,
            temp_comp_available: has_temp_comp,
            temp_comp: focuser.is_temp_comp_enabled().await.unwrap_or(false),
            temperature: focuser.get_temperature().await.ok(),
            is_moving: focuser.is_moving().await,
            position: focuser.get_position().await.ok(),
            can_halt,
            ..Default::default()
        }))
    } else if has_filter_props {
        let filter_wheel = IndiFilterWheel::new(Arc::clone(&client), &device_name);
        let filter_names = filter_wheel.get_names().await.unwrap_or_default();
        let slot_limits = {
            let locked_client = client.read().await;
            locked_client
                .get_number_limits(&device_name, "FILTER_SLOT", "FILTER_SLOT_VALUE")
                .await
        };
        let position_count = slot_limits
            .and_then(|limits| match (limits.min, limits.max) {
                (Some(min), Some(max)) if max >= min => {
                    // Why: INDI filter slots are a small
                    // physical count; after finite/range validation, f64 to
                    // i32 conversion is bounded and represents a whole count.
                    Some((max - min + 1.0).round() as i32)
                }
                _ => None,
            })
            .or_else(|| i32::try_from(filter_names.len()).ok())
            .unwrap_or(0);
        let can_set_filter_names = properties
            .iter()
            .find(|p| p.name == "FILTER_NAME")
            .map(|p| {
                matches!(
                    p.perm,
                    IndiPermission::WriteOnly | IndiPermission::ReadWrite
                )
            })
            .unwrap_or(false);

        Ok(DeviceCapabilities::FilterWheel(FilterWheelCapabilities {
            position_count,
            current_position: filter_wheel.get_position().await.ok(),
            filter_names,
            focus_offsets: Vec::new(),
            is_moving: filter_wheel.is_moving().await,
            can_set_filter_names,
            can_set_focus_offsets: false,
        }))
    } else if has_rotator_props {
        // INDI rotator. Capabilities are derived from which standard properties
        // the driver published (see indi/src/rotator.rs + protocol.rs for the
        // property/element names). `has_*` flags below are presence checks, so a
        // missing property honestly maps to "capability absent" (false) — no
        // fabricated capability.
        let has_abs_angle = properties.iter().any(|p| p.name == "ABS_ROTATOR_ANGLE");
        let can_reverse = properties.iter().any(|p| p.name == "ROTATOR_REVERSE");
        let can_halt = properties.iter().any(|p| p.name == "ROTATOR_ABORT_MOTION");
        let can_sync = properties.iter().any(|p| p.name == "SYNC_ROTATOR_ANGLE");

        // The absolute rotator exposes its angle under ABS_ROTATOR_ANGLE/ANGLE;
        // legacy drivers use ROTATOR_ANGLE/ANGLE. Read whichever the driver
        // actually published so the position and its limits come from the same
        // property.
        let angle_property = if has_abs_angle {
            "ABS_ROTATOR_ANGLE"
        } else {
            "ROTATOR_ANGLE"
        };

        let (position, min_angle_deg, max_angle_deg) = {
            let locked_client = client.read().await;
            let position = locked_client
                .get_number(&device_name, angle_property, "ANGLE")
                .await;
            // Why: INDI publishes the mechanical angle range as the ANGLE
            // element's min/max number limits. Absent property/limits → None
            // ("range unknown"), never a fabricated 0–360 clamp.
            let limits = locked_client
                .get_number_limits(&device_name, angle_property, "ANGLE")
                .await;
            (
                position,
                limits.as_ref().and_then(|l| l.min),
                limits.as_ref().and_then(|l| l.max),
            )
        };

        let caps = RotatorCapabilities {
            can_reverse,
            // Why: INDI does not report the current reverse state via a
            // capability snapshot here; the rotator state provider polls
            // ROTATOR_REVERSE live. `false` is the safe display default.
            reverse: false,
            // Why: INDI rotators expose absolute angle in degrees but no
            // per-step resolution property; None = "step size unknown".
            step_size: None,
            // Why: motion state is transient and re-polled by the rotator state
            // provider; a capability snapshot defaults to "stationary".
            is_moving: false,
            // INDI reports a single angle; mechanical and sky position coincide
            // until a SYNC_ROTATOR_ANGLE offset is applied (tracked live by the
            // state provider, not in this static snapshot).
            mechanical_position: position,
            position,
            can_move_absolute: has_abs_angle,
            can_halt,
            can_sync,
            min_angle_deg,
            max_angle_deg,
        };

        Ok(DeviceCapabilities::Rotator(caps))
    } else {
        // Unknown device type - return minimal capabilities
        Err(NightshadeError::not_supported(
            device_id,
            "Could not determine INDI device type from properties",
        ))
    }
}

/// Get capabilities for a native SDK device
///
/// Native SDK devices (ZWO, QHY, PlayerOne, etc.) typically have well-defined
/// capabilities that can be queried from their SDK functions. This function
/// returns capability information based on the vendor and device type.
///
/// # Silent-fallback contract
///
/// Native vendor SDKs use their own `Result` types: failures here usually mean
/// "the SDK rejected the call because the camera/mount is mid-state-transition"
/// (e.g. querying `is_moving` while a homing routine is firing). The capability
/// struct is a SNAPSHOT — defaulting transient-state booleans to `false` and
/// missing-list queries to empty is acceptable because the equipment view
/// re-polls these values on a timer once the connection is established.
async fn get_native_capabilities(device_id: &str) -> Result<DeviceCapabilities, NightshadeError> {
    let mgr = crate::api::get_device_manager();

    // Look up the device in the device registry to determine its type
    let device_type = {
        let devices = mgr.devices.read().await;
        devices.get(device_id).map(|d| d.info.device_type.clone())
    };

    let device_type = device_type.ok_or_else(|| {
        NightshadeError::hardware_error(device_id, "Device not found in registry")
    })?;

    match device_type {
        crate::device::DeviceType::Camera => {
            let native_cameras = mgr.native_cameras.read().await;
            if let Some(camera) = native_cameras.get(device_id) {
                let native_caps = camera.capabilities();
                let sensor_info = camera.get_sensor_info();
                let gain_range = camera.get_gain_range().await.ok();
                let offset_range = camera.get_offset_range().await.ok();
                // Why: vendor SDK readout-mode enumeration is optional (only ZWO
                // and QHY expose multi-mode sensors). Empty vec → UI hides the
                // readout-mode selector, matching cameras that have a single
                // hard-coded mode.
                let readout_modes = camera.get_readout_modes().await.unwrap_or_default();
                let status = camera.get_status().await.ok();
                let cooler_power = status.as_ref().and_then(|s| s.cooler_power);
                // Why: the NativeCamera trait's get_cooler_temp_range default
                // returns Ok(None); only drivers that publish the achievable
                // regulated-cooling range (currently ZWO, via C2) override it.
                // `.ok().flatten()` collapses a transient SDK error to None
                // ("range unknown") — the equipment view re-probes on a timer,
                // and an unknown range simply leaves the setpoint field unclamped
                // rather than fabricating limits.
                let (cooler_min_temp_c, cooler_max_temp_c) = camera
                    .get_cooler_temp_range()
                    .await
                    .ok()
                    .flatten()
                    .map_or((None, None), |(min, max)| (Some(min), Some(max)));

                Ok(DeviceCapabilities::Camera(CameraCapabilities {
                    max_width: sensor_info.width,
                    max_height: sensor_info.height,
                    bit_depth: sensor_info.bit_depth,
                    has_shutter: native_caps.has_shutter,
                    can_set_ccd_temperature: native_caps.can_cool,
                    can_set_cooler: native_caps.can_cool,
                    can_get_cooler_power: cooler_power.is_some(),
                    can_bin: native_caps.can_set_binning,
                    max_bin_x: native_caps.max_bin_x,
                    max_bin_y: native_caps.max_bin_y,
                    can_set_gain: native_caps.can_set_gain,
                    gain_min: gain_range.map(|(min, _)| min),
                    gain_max: gain_range.map(|(_, max)| max),
                    can_set_offset: native_caps.can_set_offset,
                    offset_min: offset_range.map(|(min, _)| min),
                    offset_max: offset_range.map(|(_, max)| max),
                    can_abort_exposure: true,
                    can_subframe: native_caps.can_subframe,
                    pixel_size_x: Some(sensor_info.pixel_size_x),
                    pixel_size_y: Some(sensor_info.pixel_size_y),
                    is_color: sensor_info.color,
                    bayer_pattern: sensor_info.bayer_pattern.map(|bp| format!("{:?}", bp)),
                    readout_modes: readout_modes.into_iter().map(|m| m.name).collect(),
                    ccd_temperature: status.as_ref().and_then(|s| s.sensor_temp),
                    set_ccd_temperature: status.as_ref().and_then(|s| s.target_temp),
                    cooler_power,
                    cooler_on: status.as_ref().map(|s| s.cooler_on),
                    cooler_min_temp_c,
                    cooler_max_temp_c,
                    ..Default::default()
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native camera not connected",
                ))
            }
        }
        crate::device::DeviceType::Mount => {
            let native_mounts = mgr.native_mounts.read().await;
            if let Some(mount) = native_mounts.get(device_id) {
                let tracking = mount.get_tracking().await.ok();
                let can_set_tracking = tracking.is_some();
                let can_park = mount.is_parked().await.is_ok();
                let can_abort_slew = mount.is_slewing().await.is_ok();
                Ok(DeviceCapabilities::Mount(MountCapabilities {
                    can_slew: true,
                    can_slew_async: true,
                    can_sync: true,
                    can_park,
                    can_unpark: can_park,
                    can_pulse_guide: true,
                    can_set_tracking,
                    can_abort_slew,
                    is_equatorial: true,
                    tracking,
                    axis_count: 2,
                    ..Default::default()
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native mount not connected",
                ))
            }
        }
        crate::device::DeviceType::Focuser => {
            let native_focusers = mgr.native_focusers.read().await;
            if let Some(focuser) = native_focusers.get(device_id) {
                let position = focuser.get_position().await.ok();
                let temperature = focuser.get_temperature().await.ok().flatten();
                // Why: transient-state probe — if the focuser SDK is busy with
                // another command we treat the focuser as stationary in this
                // snapshot. The equipment poller re-reads on a 500 ms cadence,
                // so a false "stationary" reading self-corrects within a frame.
                let is_moving = focuser.is_moving().await.unwrap_or(false);
                Ok(DeviceCapabilities::Focuser(FocuserCapabilities {
                    max_position: focuser.get_max_position(),
                    step_size: Some(focuser.get_step_size()),
                    absolute: true,
                    position,
                    temperature,
                    is_moving,
                    can_halt: true,
                    ..Default::default()
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native focuser not connected",
                ))
            }
        }
        crate::device::DeviceType::FilterWheel => {
            let native_fws = mgr.native_filter_wheels.read().await;
            if let Some(fw) = native_fws.get(device_id) {
                // Why: vendor SDKs that don't persist filter labels (e.g. ZWO
                // EFW) return an error here on first connect. Empty vec → UI
                // renders generic "Filter 1, Filter 2..." labels indexed off
                // `get_filter_count()`, which is sufficient for slot selection.
                let names = fw.get_filter_names().await.unwrap_or_default();
                let position = fw.get_position().await.ok().map(|p| p as i32);
                // Why: same transient-state contract as focuser is_moving above.
                let is_moving = fw.is_moving().await.unwrap_or(false);
                Ok(DeviceCapabilities::FilterWheel(FilterWheelCapabilities {
                    position_count: fw.get_filter_count(),
                    current_position: position,
                    filter_names: names,
                    is_moving,
                    ..Default::default()
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native filter wheel not connected",
                ))
            }
        }
        crate::device::DeviceType::Rotator => {
            let native_rotators = mgr.native_rotators.read().await;
            if let Some(rotator) = native_rotators.get(device_id) {
                let position = rotator.get_position().await.ok();
                let mechanical_position = rotator.get_mechanical_position().await.ok();
                let moving_result = rotator.is_moving().await;
                let can_halt = moving_result.is_ok();
                let is_moving = moving_result.unwrap_or(false);
                let can_reverse = rotator.can_reverse();
                let reverse = if can_reverse {
                    rotator.get_reverse().await.unwrap_or(false)
                } else {
                    false
                };

                Ok(DeviceCapabilities::Rotator(RotatorCapabilities {
                    can_reverse,
                    reverse,
                    step_size: None,
                    is_moving,
                    mechanical_position,
                    position,
                    can_move_absolute: true,
                    can_halt,
                    can_sync: true,
                    // Why: the NativeRotator trait exposes no angle-range accessor
                    // (vendor rotator SDKs do not publish mechanical min/max), so
                    // the range is genuinely unknown here. None = "unbounded by
                    // contract", never a fabricated 0–360 clamp.
                    min_angle_deg: None,
                    max_angle_deg: None,
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native rotator not connected",
                ))
            }
        }
        crate::device::DeviceType::Dome => {
            let native_domes = mgr.native_domes.read().await;
            if let Some(dome) = native_domes.get(device_id) {
                let azimuth = dome.get_azimuth().await.ok();
                let slewing_result = dome.is_slewing().await;
                let can_abort = slewing_result.is_ok();
                // Why: paired-probe pattern: the Result<bool> tells us BOTH whether
                // the capability exists (Ok = `can_abort`) and the current state
                // (false on Err is safe-default "not slewing"). The capability is
                // returned via `can_abort` so callers can distinguish "absent" from
                // "present and false" via the separate flag.
                let slewing = slewing_result.unwrap_or(false);
                let at_home_result = dome.is_at_home().await;
                let can_find_home = at_home_result.is_ok();
                let at_home = at_home_result.unwrap_or(false); // Why: same paired-probe pattern as `slewing` above
                let at_park_result = dome.is_parked().await;
                let can_park = at_park_result.is_ok();
                let at_park = at_park_result.unwrap_or(false); // Why: same paired-probe pattern as `slewing` above
                                                               // Why: NativeDome.is_slaved() failure is treated as "not slaved"
                                                               // because the slave-loop is a host-side process we control; if
                                                               // it's not visible to the device wrapper, it's not running.
                let slaved = dome.is_slaved().await.unwrap_or(false);
                let shutter_status =
                    dome.get_shutter_status()
                        .await
                        .ok()
                        .map(|status| match status {
                            nightshade_native::traits::ShutterState::Open => ShutterStatus::Open,
                            nightshade_native::traits::ShutterState::Closed => {
                                ShutterStatus::Closed
                            }
                            nightshade_native::traits::ShutterState::Opening => {
                                ShutterStatus::Opening
                            }
                            nightshade_native::traits::ShutterState::Closing => {
                                ShutterStatus::Closing
                            }
                            nightshade_native::traits::ShutterState::Error => {
                                ShutterStatus::Unknown
                            }
                            nightshade_native::traits::ShutterState::Unknown => {
                                ShutterStatus::Unknown
                            }
                        });

                Ok(DeviceCapabilities::Dome(DomeCapabilities {
                    can_set_azimuth: dome.can_set_azimuth(),
                    can_park,
                    can_find_home,
                    can_set_shutter: dome.can_set_shutter(),
                    can_sync_azimuth: false,
                    azimuth,
                    slewing,
                    at_home,
                    at_park,
                    shutter_status,
                    can_slave: dome.can_slave(),
                    slaved,
                    can_abort,
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native dome not connected",
                ))
            }
        }
        crate::device::DeviceType::Weather => {
            let native_weather = mgr.native_weather.read().await;
            if let Some(weather) = native_weather.get(device_id) {
                let has_cloud_cover = weather.get_cloud_cover().await.ok().flatten().is_some();
                let has_dew_point = weather.get_dew_point().await.ok().flatten().is_some();
                let has_humidity = weather.get_humidity().await.ok().flatten().is_some();
                let has_pressure = weather.get_pressure().await.ok().flatten().is_some();
                let has_rain_rate = weather.get_rain_rate().await.ok().flatten().is_some();
                let has_sky_quality = weather.get_sky_quality().await.ok().flatten().is_some();
                let has_temperature = weather.get_temperature().await.ok().flatten().is_some();
                let has_wind_direction =
                    weather.get_wind_direction().await.ok().flatten().is_some();
                let has_wind_speed = weather.get_wind_speed().await.ok().flatten().is_some();

                Ok(DeviceCapabilities::Weather(WeatherCapabilities {
                    has_cloud_cover,
                    has_dew_point,
                    has_humidity,
                    has_pressure,
                    has_rain_rate,
                    has_sky_quality,
                    has_temperature,
                    has_wind_direction,
                    has_wind_speed,
                    has_sky_brightness: false,
                    has_sky_temperature: false,
                    has_seeing: false,
                    has_wind_gust: false,
                    average_period: None,
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native weather station not connected",
                ))
            }
        }
        crate::device::DeviceType::SafetyMonitor => {
            let native_safety = mgr.native_safety_monitors.read().await;
            if let Some(safety) = native_safety.get(device_id) {
                // Why: SafetyMonitor "fail-closed" rule — a comms error from a
                // native safety driver MUST report "unsafe", never "safe".
                // Matches the ASCOM ISafetyMonitorV1 contract enforced at the
                // Alpaca/ASCOM branches above.
                let is_safe = safety.is_safe().await.unwrap_or(false);
                Ok(DeviceCapabilities::SafetyMonitor(
                    SafetyMonitorCapabilities {
                        is_safe,
                        safety_description: None,
                    },
                ))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native safety monitor not connected",
                ))
            }
        }
        crate::device::DeviceType::Switch => {
            let native_switches = mgr.native_switches.read().await;
            if let Some(switch) = native_switches.get(device_id) {
                let switch_count = switch.get_switch_count().await.unwrap_or(0);
                let switches = switch
                    .get_switches()
                    .await
                    .unwrap_or_default()
                    .into_iter()
                    .map(|channel| SwitchInfo {
                        index: channel.id,
                        name: channel.name,
                        description: channel.description,
                        is_boolean: channel.is_boolean,
                        min_value: channel.min_value,
                        max_value: channel.max_value,
                        step: channel.step,
                        can_write: channel.can_write,
                        value: channel.value,
                    })
                    .collect();

                Ok(DeviceCapabilities::Switch(SwitchCapabilities {
                    switch_count,
                    switches,
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native switch not connected",
                ))
            }
        }
        crate::device::DeviceType::CoverCalibrator => {
            let native_covers = mgr.native_cover_calibrators.read().await;
            if let Some(cover) = native_covers.get(device_id) {
                let cover_state = cover
                    .get_cover_state()
                    .await
                    .ok()
                    .map(native_cover_state_to_capability);
                let calibrator_state = cover
                    .get_calibrator_state()
                    .await
                    .ok()
                    .map(native_calibrator_state_to_capability);
                let brightness = cover.get_brightness().await.ok();
                let max_brightness = cover.get_max_brightness().await.unwrap_or(0);

                Ok(DeviceCapabilities::CoverCalibrator(
                    CoverCalibratorCapabilities {
                        max_brightness,
                        cover_present: cover_state.map_or(false, |s| s != CoverState::NotPresent),
                        calibrator_present: calibrator_state
                            .map_or(false, |s| s != CalibratorState::NotPresent),
                        cover_state,
                        calibrator_state,
                        brightness,
                    },
                ))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native cover calibrator not connected",
                ))
            }
        }
        _ => Err(NightshadeError::not_supported(
            device_id,
            &format!(
                "Native capabilities are unavailable for device type {:?}",
                device_type
            ),
        )),
    }
}

/// Get capabilities for a simulator device
fn get_simulator_capabilities(device_id: &str) -> DeviceCapabilities {
    let device_id_lower = device_id.to_lowercase();

    // Simulator devices have full capabilities
    if device_id_lower.contains("camera") {
        DeviceCapabilities::Camera(CameraCapabilities {
            max_width: 4096,
            max_height: 4096,
            bit_depth: 16,
            has_shutter: true,
            can_set_ccd_temperature: true,
            can_set_cooler: true,
            can_get_cooler_power: true,
            can_bin: true,
            max_bin_x: 4,
            max_bin_y: 4,
            can_asymmetric_bin: false,
            can_set_gain: true,
            gain_min: Some(0),
            gain_max: Some(600),
            can_set_offset: true,
            offset_min: Some(0),
            offset_max: Some(255),
            can_abort_exposure: true,
            can_stop_exposure: true,
            can_subframe: true,
            pixel_size_x: Some(3.8),
            pixel_size_y: Some(3.8),
            is_color: false,
            exposure_min: Some(0.001),
            exposure_max: Some(3600.0),
            // Simulator advertises a representative regulated-cooling range so
            // the setpoint UI and its clamping path are exercised end-to-end.
            cooler_min_temp_c: Some(-40.0),
            cooler_max_temp_c: Some(40.0),
            ..Default::default()
        })
    } else if device_id_lower.contains("mount") || device_id_lower.contains("telescope") {
        DeviceCapabilities::Mount(MountCapabilities {
            can_slew: true,
            can_slew_async: true,
            can_sync: true,
            can_park: true,
            can_unpark: true,
            can_pulse_guide: true,
            can_set_tracking: true,
            is_equatorial: true,
            can_find_home: true,
            can_abort_slew: true,
            axis_count: 2,
            // Simulator advertises a representative pulse-guide duration range
            // (1 ms minimum tick to 8 s, the common INDI TIMED_GUIDE ceiling) so
            // the guide-pulse UI and its range validation are exercised.
            min_pulse_guide_ms: Some(1.0),
            max_pulse_guide_ms: Some(8000.0),
            ..Default::default()
        })
    } else if device_id_lower.contains("focuser") {
        DeviceCapabilities::Focuser(FocuserCapabilities {
            max_position: 100000,
            max_increment: 50000,
            step_size: Some(1.0),
            absolute: true,
            temp_comp_available: true,
            can_halt: true,
            can_reverse: true,
            ..Default::default()
        })
    } else if device_id_lower.contains("filter") {
        DeviceCapabilities::FilterWheel(FilterWheelCapabilities {
            position_count: 7,
            filter_names: vec![
                "L".into(),
                "R".into(),
                "G".into(),
                "B".into(),
                "Ha".into(),
                "OIII".into(),
                "SII".into(),
            ],
            focus_offsets: vec![0, 10, 20, 30, 100, 120, 140],
            can_set_filter_names: true,
            can_set_focus_offsets: true,
            ..Default::default()
        })
    } else if device_id_lower.contains("rotator") {
        DeviceCapabilities::Rotator(RotatorCapabilities {
            can_reverse: true,
            reverse: false,
            step_size: Some(0.1),
            is_moving: false,
            mechanical_position: Some(0.0),
            position: Some(0.0),
            can_move_absolute: true,
            can_halt: true,
            can_sync: true,
            // Simulator advertises the full mechanical sweep so the angle-range
            // UI and its clamping are exercised end-to-end.
            min_angle_deg: Some(0.0),
            max_angle_deg: Some(360.0),
        })
    } else if device_id_lower.contains("dome") {
        DeviceCapabilities::Dome(DomeCapabilities {
            can_set_azimuth: true,
            can_park: true,
            can_find_home: true,
            can_set_shutter: true,
            can_sync_azimuth: true,
            azimuth: Some(0.0),
            slewing: false,
            at_home: true,
            at_park: false,
            shutter_status: Some(ShutterStatus::Closed),
            can_slave: true,
            slaved: false,
            can_abort: true,
        })
    } else if device_id_lower.contains("covercalibrator") || device_id_lower.contains("flatpanel") {
        DeviceCapabilities::CoverCalibrator(CoverCalibratorCapabilities {
            max_brightness: 255,
            cover_present: true,
            calibrator_present: true,
            cover_state: Some(CoverState::Closed),
            calibrator_state: Some(CalibratorState::Off),
            brightness: Some(0),
        })
    } else if device_id_lower.contains("weather") || device_id_lower.contains("observingconditions")
    {
        DeviceCapabilities::Weather(WeatherCapabilities {
            has_cloud_cover: true,
            has_dew_point: true,
            has_humidity: true,
            has_pressure: true,
            has_rain_rate: true,
            has_sky_brightness: true,
            has_sky_quality: true,
            has_sky_temperature: true,
            has_seeing: true,
            has_temperature: true,
            has_wind_direction: true,
            has_wind_gust: true,
            has_wind_speed: true,
            average_period: Some(60.0),
        })
    } else if device_id_lower.contains("safetymonitor") {
        DeviceCapabilities::SafetyMonitor(SafetyMonitorCapabilities {
            is_safe: true,
            safety_description: Some("Simulator safety monitor - always safe".to_string()),
        })
    } else if device_id_lower.contains("switch") {
        DeviceCapabilities::Switch(SwitchCapabilities {
            switch_count: 4,
            switches: vec![
                SwitchInfo {
                    index: 0,
                    name: "Power Port 1".to_string(),
                    description: "12V power output".to_string(),
                    is_boolean: true,
                    min_value: 0.0,
                    max_value: 1.0,
                    step: 1.0,
                    can_write: true,
                    value: 0.0,
                },
                SwitchInfo {
                    index: 1,
                    name: "Power Port 2".to_string(),
                    description: "12V power output".to_string(),
                    is_boolean: true,
                    min_value: 0.0,
                    max_value: 1.0,
                    step: 1.0,
                    can_write: true,
                    value: 0.0,
                },
                SwitchInfo {
                    index: 2,
                    name: "Dew Heater A".to_string(),
                    description: "Variable dew heater".to_string(),
                    is_boolean: false,
                    min_value: 0.0,
                    max_value: 100.0,
                    step: 1.0,
                    can_write: true,
                    value: 0.0,
                },
                SwitchInfo {
                    index: 3,
                    name: "USB Hub".to_string(),
                    description: "USB hub power".to_string(),
                    is_boolean: true,
                    min_value: 0.0,
                    max_value: 1.0,
                    step: 1.0,
                    can_write: true,
                    value: 1.0,
                },
            ],
        })
    } else {
        // Default to camera for unknown simulator devices
        DeviceCapabilities::Camera(CameraCapabilities::default())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug)]
    struct FakeNativeRotator;

    #[async_trait::async_trait]
    impl nightshade_native::traits::NativeDevice for FakeNativeRotator {
        fn id(&self) -> &str {
            "native:zwo:900001"
        }

        fn name(&self) -> &str {
            "Fake Native Rotator"
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
    impl nightshade_native::traits::NativeRotator for FakeNativeRotator {
        async fn move_to(
            &mut self,
            _position: f64,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }

        async fn get_position(&self) -> Result<f64, nightshade_native::traits::NativeError> {
            Ok(12.5)
        }

        async fn get_mechanical_position(
            &self,
        ) -> Result<f64, nightshade_native::traits::NativeError> {
            Ok(14.0)
        }

        async fn is_moving(&self) -> Result<bool, nightshade_native::traits::NativeError> {
            Ok(true)
        }

        async fn halt(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }

        async fn sync(
            &mut self,
            _position: f64,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }

        fn can_reverse(&self) -> bool {
            true
        }

        async fn set_reverse(
            &mut self,
            _reverse: bool,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }

        async fn get_reverse(&self) -> Result<bool, nightshade_native::traits::NativeError> {
            Ok(true)
        }
    }

    #[derive(Debug)]
    struct FakeNativeSwitch;

    #[async_trait::async_trait]
    impl nightshade_native::traits::NativeDevice for FakeNativeSwitch {
        fn id(&self) -> &str {
            "native:qhy:900002"
        }

        fn name(&self) -> &str {
            "Fake Native Switch"
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
    impl nightshade_native::traits::NativeSwitch for FakeNativeSwitch {
        async fn get_switch_count(&self) -> Result<i32, nightshade_native::traits::NativeError> {
            Ok(1)
        }

        async fn get_switches(
            &self,
        ) -> Result<
            Vec<nightshade_native::traits::NativeSwitchChannel>,
            nightshade_native::traits::NativeError,
        > {
            Ok(vec![nightshade_native::traits::NativeSwitchChannel {
                id: 0,
                name: "Relay".to_string(),
                description: "Dew heater".to_string(),
                state: true,
                value: 0.75,
                min_value: 0.0,
                max_value: 1.0,
                step: 0.05,
                can_write: true,
                is_boolean: false,
            }])
        }

        async fn get_switch_state(
            &self,
            _switch_id: i32,
        ) -> Result<bool, nightshade_native::traits::NativeError> {
            Ok(true)
        }

        async fn set_switch_state(
            &mut self,
            _switch_id: i32,
            _state: bool,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }

        async fn get_switch_value(
            &self,
            _switch_id: i32,
        ) -> Result<f64, nightshade_native::traits::NativeError> {
            Ok(0.75)
        }

        async fn set_switch_value(
            &mut self,
            _switch_id: i32,
            _value: f64,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }

        async fn get_switch_name(
            &self,
            _switch_id: i32,
        ) -> Result<String, nightshade_native::traits::NativeError> {
            Ok("Relay".to_string())
        }

        async fn get_switch_description(
            &self,
            _switch_id: i32,
        ) -> Result<String, nightshade_native::traits::NativeError> {
            Ok("Dew heater".to_string())
        }

        async fn get_switch_min_value(
            &self,
            _switch_id: i32,
        ) -> Result<f64, nightshade_native::traits::NativeError> {
            Ok(0.0)
        }

        async fn get_switch_max_value(
            &self,
            _switch_id: i32,
        ) -> Result<f64, nightshade_native::traits::NativeError> {
            Ok(1.0)
        }

        async fn get_switch_step(
            &self,
            _switch_id: i32,
        ) -> Result<f64, nightshade_native::traits::NativeError> {
            Ok(0.05)
        }

        async fn can_write(
            &self,
            _switch_id: i32,
        ) -> Result<bool, nightshade_native::traits::NativeError> {
            Ok(true)
        }
    }

    #[derive(Debug)]
    struct FakeNativeCoverCalibrator;

    #[async_trait::async_trait]
    impl nightshade_native::traits::NativeDevice for FakeNativeCoverCalibrator {
        fn id(&self) -> &str {
            "native:player_one:900003"
        }

        fn name(&self) -> &str {
            "Fake Native Cover"
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
    impl nightshade_native::traits::NativeCoverCalibrator for FakeNativeCoverCalibrator {
        async fn open_cover(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }

        async fn close_cover(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }

        async fn halt_cover(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }

        async fn calibrator_on(
            &mut self,
            _brightness: i32,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }

        async fn calibrator_off(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }

        async fn get_cover_state(
            &self,
        ) -> Result<
            nightshade_native::traits::NativeCoverState,
            nightshade_native::traits::NativeError,
        > {
            Ok(nightshade_native::traits::NativeCoverState::Open)
        }

        async fn get_calibrator_state(
            &self,
        ) -> Result<
            nightshade_native::traits::NativeCalibratorState,
            nightshade_native::traits::NativeError,
        > {
            Ok(nightshade_native::traits::NativeCalibratorState::Ready)
        }

        async fn get_brightness(&self) -> Result<i32, nightshade_native::traits::NativeError> {
            Ok(42)
        }

        async fn get_max_brightness(&self) -> Result<i32, nightshade_native::traits::NativeError> {
            Ok(255)
        }
    }

    fn native_test_info(
        id: &str,
        device_type: crate::device::DeviceType,
    ) -> crate::device::DeviceInfo {
        crate::device::DeviceInfo {
            id: id.to_string(),
            name: id.to_string(),
            device_type,
            driver_type: crate::device::DriverType::Native,
            description: "Fake native test device".to_string(),
            driver_version: "test".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: id.to_string(),
        }
    }

    async fn register_native_test_device(id: &str, device_type: crate::device::DeviceType) {
        let manager = crate::api::get_device_manager();
        manager.devices.write().await.insert(
            id.to_string(),
            crate::device_manager::ManagedDevice {
                info: native_test_info(id, device_type),
                connection_state: crate::device::ConnectionState::Connected,
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
        invalidate_capability_cache_for_device(id).await;
    }

    #[test]
    fn indi_sensor_type_color_detection_is_conservative() {
        assert!(indi_sensor_type_is_color("COLOR"));
        assert!(indi_sensor_type_is_color("Bayer RGGB"));
        assert!(indi_sensor_type_is_color("OSC"));
        assert!(!indi_sensor_type_is_color("MONOCHROME"));
        assert!(!indi_sensor_type_is_color("CCD_SENSOR_MONO"));
    }

    #[test]
    fn indi_readout_mode_label_falls_back_to_element_name() {
        let labeled = nightshade_indi::IndiReadoutMode {
            element: "MODE_0".to_string(),
            label: "High Gain".to_string(),
        };
        let unlabeled = nightshade_indi::IndiReadoutMode {
            element: "MODE_1".to_string(),
            label: String::new(),
        };

        assert_eq!(indi_readout_mode_label(&labeled), "High Gain");
        assert_eq!(indi_readout_mode_label(&unlabeled), "MODE_1");
    }

    #[tokio::test]
    async fn capability_cache_stores_and_invalidates_by_device() {
        let device_id = "simulator:camera:0";
        invalidate_capability_cache().await;

        let caps = get_device_capabilities(device_id)
            .await
            .expect("simulator capabilities should resolve");
        assert!(matches!(caps, DeviceCapabilities::Camera(_)));
        assert_eq!(capability_cache().lock().await.len(), 1);

        invalidate_capability_cache_for_device(device_id).await;
        assert_eq!(capability_cache().lock().await.len(), 0);
    }

    #[cfg(windows)]
    #[test]
    fn capability_probe_only_owns_known_disconnected_session() {
        assert!(capability_probe_should_own_connection(Ok(false)));
        assert!(!capability_probe_should_own_connection(Ok(true)));
        assert!(!capability_probe_should_own_connection(Err(
            "Connected property unavailable".to_string(),
        )));
    }

    #[cfg(windows)]
    #[test]
    fn ascom_device_type_normalization_requires_exact_device_type() {
        assert_eq!(
            normalize_ascom_capability_device_type("Camera"),
            Some(AscomCapabilityDeviceType::Camera)
        );
        assert_eq!(
            normalize_ascom_capability_device_type("Telescope"),
            Some(AscomCapabilityDeviceType::Mount)
        );
        assert_eq!(
            normalize_ascom_capability_device_type("CoverCalibrator"),
            Some(AscomCapabilityDeviceType::CoverCalibrator)
        );
        assert_eq!(normalize_ascom_capability_device_type("CameraGuard"), None);
    }

    #[tokio::test]
    async fn native_rotator_capabilities_use_connected_trait_object() {
        let device_id = "native:zwo:900001";
        register_native_test_device(device_id, crate::device::DeviceType::Rotator).await;
        crate::api::get_device_manager()
            .native_rotators
            .write()
            .await
            .insert(device_id.to_string(), Box::new(FakeNativeRotator));

        let caps = get_device_capabilities(device_id)
            .await
            .expect("native rotator capabilities should resolve");

        match caps {
            DeviceCapabilities::Rotator(caps) => {
                assert_eq!(caps.position, Some(12.5));
                assert_eq!(caps.mechanical_position, Some(14.0));
                assert!(caps.is_moving);
                assert!(caps.can_reverse);
                assert!(caps.reverse);
                assert!(caps.can_move_absolute);
                assert!(caps.can_halt);
                assert!(caps.can_sync);
                // The NativeRotator trait exposes no angle-range accessor, so the
                // probe must surface an honest "unknown" rather than a clamp.
                assert_eq!(caps.min_angle_deg, None);
                assert_eq!(caps.max_angle_deg, None);
            }
            other => panic!("expected rotator capabilities, got {other:?}"),
        }

        crate::api::get_device_manager()
            .native_rotators
            .write()
            .await
            .remove(device_id);
        crate::api::get_device_manager()
            .devices
            .write()
            .await
            .remove(device_id);
        invalidate_capability_cache_for_device(device_id).await;
    }

    #[tokio::test]
    async fn native_switch_capabilities_use_connected_trait_object() {
        let device_id = "native:qhy:900002";
        register_native_test_device(device_id, crate::device::DeviceType::Switch).await;
        crate::api::get_device_manager()
            .native_switches
            .write()
            .await
            .insert(device_id.to_string(), Box::new(FakeNativeSwitch));

        let caps = get_device_capabilities(device_id)
            .await
            .expect("native switch capabilities should resolve");

        match caps {
            DeviceCapabilities::Switch(caps) => {
                assert_eq!(caps.switch_count, 1);
                assert_eq!(caps.switches.len(), 1);
                assert_eq!(caps.switches[0].name, "Relay");
                assert_eq!(caps.switches[0].description, "Dew heater");
                assert_eq!(caps.switches[0].value, 0.75);
                assert!(caps.switches[0].can_write);
            }
            other => panic!("expected switch capabilities, got {other:?}"),
        }

        crate::api::get_device_manager()
            .native_switches
            .write()
            .await
            .remove(device_id);
        crate::api::get_device_manager()
            .devices
            .write()
            .await
            .remove(device_id);
        invalidate_capability_cache_for_device(device_id).await;
    }

    #[tokio::test]
    async fn native_cover_capabilities_use_connected_trait_object() {
        let device_id = "native:player_one:900003";
        register_native_test_device(device_id, crate::device::DeviceType::CoverCalibrator).await;
        crate::api::get_device_manager()
            .native_cover_calibrators
            .write()
            .await
            .insert(device_id.to_string(), Box::new(FakeNativeCoverCalibrator));

        let caps = get_device_capabilities(device_id)
            .await
            .expect("native cover capabilities should resolve");

        match caps {
            DeviceCapabilities::CoverCalibrator(caps) => {
                assert_eq!(caps.max_brightness, 255);
                assert_eq!(caps.brightness, Some(42));
                assert_eq!(caps.cover_state, Some(CoverState::Open));
                assert_eq!(caps.calibrator_state, Some(CalibratorState::Ready));
                assert!(caps.cover_present);
                assert!(caps.calibrator_present);
            }
            other => panic!("expected cover calibrator capabilities, got {other:?}"),
        }

        crate::api::get_device_manager()
            .native_cover_calibrators
            .write()
            .await
            .remove(device_id);
        crate::api::get_device_manager()
            .devices
            .write()
            .await
            .remove(device_id);
        invalidate_capability_cache_for_device(device_id).await;
    }

    #[tokio::test]
    async fn native_cover_switch_rotator_operations_dispatch_to_trait_objects() {
        let manager = crate::api::get_device_manager();
        let rotator_id = "native:zwo:900011";
        let switch_id = "native:qhy:900012";
        let cover_id = "native:player_one:900013";

        register_native_test_device(rotator_id, crate::device::DeviceType::Rotator).await;
        register_native_test_device(switch_id, crate::device::DeviceType::Switch).await;
        register_native_test_device(cover_id, crate::device::DeviceType::CoverCalibrator).await;

        manager
            .native_rotators
            .write()
            .await
            .insert(rotator_id.to_string(), Box::new(FakeNativeRotator));
        manager
            .native_switches
            .write()
            .await
            .insert(switch_id.to_string(), Box::new(FakeNativeSwitch));
        manager
            .native_cover_calibrators
            .write()
            .await
            .insert(cover_id.to_string(), Box::new(FakeNativeCoverCalibrator));

        assert_eq!(
            manager.rotator_get_position(rotator_id).await.unwrap(),
            12.5
        );
        manager
            .rotator_move_absolute(rotator_id, 45.0)
            .await
            .unwrap();
        manager.rotator_halt(rotator_id).await.unwrap();

        assert_eq!(manager.switch_get_max(switch_id).await.unwrap(), 1);
        assert!(manager.switch_get_state(switch_id, 0).await.unwrap());
        assert_eq!(manager.switch_get_value(switch_id, 0).await.unwrap(), 0.75);
        assert!(manager.switch_can_write(switch_id, 0).await.unwrap());
        manager.switch_set_state(switch_id, 0, false).await.unwrap();
        manager.switch_set_value(switch_id, 0, 0.25).await.unwrap();

        manager.cover_calibrator_open_cover(cover_id).await.unwrap();
        manager
            .cover_calibrator_calibrator_on(cover_id, 42)
            .await
            .unwrap();
        let status = manager.cover_calibrator_get_status(cover_id).await.unwrap();
        assert_eq!(status.cover_state, CoverState::Open);
        assert_eq!(status.calibrator_state, CalibratorState::Ready);
        assert_eq!(status.brightness, 42);
        assert_eq!(status.max_brightness, 255);

        manager.native_rotators.write().await.remove(rotator_id);
        manager.native_switches.write().await.remove(switch_id);
        manager
            .native_cover_calibrators
            .write()
            .await
            .remove(cover_id);
        let mut devices = manager.devices.write().await;
        devices.remove(rotator_id);
        devices.remove(switch_id);
        devices.remove(cover_id);
        drop(devices);
        invalidate_capability_cache_for_device(rotator_id).await;
        invalidate_capability_cache_for_device(switch_id).await;
        invalidate_capability_cache_for_device(cover_id).await;
    }

    // ---------------------------------------------------------------------
    // C1: cooler-range / pulse-guide-range / angle-range capability fields
    // ---------------------------------------------------------------------

    /// Minimal native camera whose SDK exposes a regulated-cooling range but no
    /// recommended setpoint — mirrors the ZWO shape that C2 will wire through
    /// the real driver. Only the methods `get_native_capabilities` touches need
    /// realistic values; the rest return benign defaults.
    #[derive(Debug)]
    struct FakeRangedCamera;

    #[async_trait::async_trait]
    impl nightshade_native::traits::NativeDevice for FakeRangedCamera {
        fn id(&self) -> &str {
            "native:zwo:900021"
        }
        fn name(&self) -> &str {
            "Fake Ranged Camera"
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
    impl nightshade_native::traits::NativeCamera for FakeRangedCamera {
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
                sensor_temp: Some(-5.0),
                cooler_power: Some(40.0),
                target_temp: Some(-10.0),
                cooler_on: true,
                gain: 100,
                offset: 30,
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
            _enabled: bool,
            _target_temp: f64,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
        async fn get_temperature(&self) -> Result<f64, nightshade_native::traits::NativeError> {
            Ok(-5.0)
        }
        async fn get_cooler_power(&self) -> Result<f64, nightshade_native::traits::NativeError> {
            Ok(40.0)
        }
        async fn set_gain(
            &mut self,
            _gain: i32,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
        async fn get_gain(&self) -> Result<i32, nightshade_native::traits::NativeError> {
            Ok(100)
        }
        async fn set_offset(
            &mut self,
            _offset: i32,
        ) -> Result<(), nightshade_native::traits::NativeError> {
            Ok(())
        }
        async fn get_offset(&self) -> Result<i32, nightshade_native::traits::NativeError> {
            Ok(30)
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
                width: 6248,
                height: 4176,
                pixel_size_x: 3.76,
                pixel_size_y: 3.76,
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

        // The seam C1 adds and C2 will override for real ZWO hardware: report a
        // concrete achievable cooling range.
        async fn get_cooler_temp_range(
            &self,
        ) -> Result<Option<(f64, f64)>, nightshade_native::traits::NativeError> {
            Ok(Some((-45.0, 35.0)))
        }
    }

    #[tokio::test]
    async fn native_camera_capabilities_map_cooler_temp_range_from_trait() {
        let device_id = "native:zwo:900021";
        register_native_test_device(device_id, crate::device::DeviceType::Camera).await;
        crate::api::get_device_manager()
            .native_cameras
            .write()
            .await
            .insert(device_id.to_string(), Box::new(FakeRangedCamera));

        let caps = get_device_capabilities(device_id)
            .await
            .expect("native camera capabilities should resolve");

        match caps {
            DeviceCapabilities::Camera(caps) => {
                // The trait override flows through get_native_capabilities into
                // the bridge struct.
                assert_eq!(caps.cooler_min_temp_c, Some(-45.0));
                assert_eq!(caps.cooler_max_temp_c, Some(35.0));
                assert!(caps.can_set_ccd_temperature);
            }
            other => panic!("expected camera capabilities, got {other:?}"),
        }

        crate::api::get_device_manager()
            .native_cameras
            .write()
            .await
            .remove(device_id);
        crate::api::get_device_manager()
            .devices
            .write()
            .await
            .remove(device_id);
        invalidate_capability_cache_for_device(device_id).await;
    }

    #[test]
    fn camera_capabilities_roundtrip_preserves_cooler_range() {
        let caps = CameraCapabilities {
            can_set_ccd_temperature: true,
            cooler_min_temp_c: Some(-40.0),
            cooler_max_temp_c: Some(40.0),
            ..Default::default()
        };
        let json = serde_json::to_string(&caps).expect("serialize");
        let back: CameraCapabilities = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(back.cooler_min_temp_c, Some(-40.0));
        assert_eq!(back.cooler_max_temp_c, Some(40.0));
        assert!(back.can_set_ccd_temperature);
    }

    #[test]
    fn mount_capabilities_roundtrip_preserves_pulse_guide_range() {
        let caps = MountCapabilities {
            can_pulse_guide: true,
            min_pulse_guide_ms: Some(1.0),
            max_pulse_guide_ms: Some(8000.0),
            ..Default::default()
        };
        let json = serde_json::to_string(&caps).expect("serialize");
        let back: MountCapabilities = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(back.min_pulse_guide_ms, Some(1.0));
        assert_eq!(back.max_pulse_guide_ms, Some(8000.0));
        assert!(back.can_pulse_guide);
    }

    #[test]
    fn rotator_capabilities_roundtrip_preserves_angle_range() {
        let caps = RotatorCapabilities {
            can_move_absolute: true,
            min_angle_deg: Some(0.0),
            max_angle_deg: Some(360.0),
            ..Default::default()
        };
        let json = serde_json::to_string(&caps).expect("serialize");
        let back: RotatorCapabilities = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(back.min_angle_deg, Some(0.0));
        assert_eq!(back.max_angle_deg, Some(360.0));
        assert!(back.can_move_absolute);
    }

    /// Serialize `value`, strip the named keys to simulate a JSON document
    /// persisted before those keys existed, and return the re-encoded string.
    /// This proves the back-compat contract without hard-coding the (large,
    /// evolving) set of pre-existing mandatory fields into each test.
    fn json_without_keys<T: Serialize>(value: &T, keys: &[&str]) -> String {
        let mut obj = match serde_json::to_value(value).expect("serialize to value") {
            serde_json::Value::Object(map) => map,
            other => panic!("expected a JSON object, got {other:?}"),
        };
        for key in keys {
            assert!(
                obj.remove(*key).is_some(),
                "expected new field {key} to be present before stripping"
            );
        }
        serde_json::to_string(&obj).expect("re-serialize")
    }

    #[test]
    fn camera_capabilities_backcompat_missing_cooler_range_is_none() {
        // A persisted JSON object from before these fields existed must
        // deserialize cleanly with the new fields as None (back-compat).
        let json = json_without_keys(
            &CameraCapabilities {
                max_width: 4096,
                cooler_min_temp_c: Some(-40.0),
                cooler_max_temp_c: Some(40.0),
                ..Default::default()
            },
            &["cooler_min_temp_c", "cooler_max_temp_c"],
        );
        let caps: CameraCapabilities = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(caps.cooler_min_temp_c, None);
        assert_eq!(caps.cooler_max_temp_c, None);
        assert_eq!(caps.max_width, 4096);
    }

    #[test]
    fn mount_capabilities_backcompat_missing_pulse_range_is_none() {
        let json = json_without_keys(
            &MountCapabilities {
                can_pulse_guide: true,
                min_pulse_guide_ms: Some(1.0),
                max_pulse_guide_ms: Some(8000.0),
                ..Default::default()
            },
            &["min_pulse_guide_ms", "max_pulse_guide_ms"],
        );
        let caps: MountCapabilities = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(caps.min_pulse_guide_ms, None);
        assert_eq!(caps.max_pulse_guide_ms, None);
        assert!(caps.can_pulse_guide);
    }

    #[test]
    fn rotator_capabilities_backcompat_missing_angle_range_is_none() {
        let json = json_without_keys(
            &RotatorCapabilities {
                can_move_absolute: true,
                min_angle_deg: Some(0.0),
                max_angle_deg: Some(360.0),
                ..Default::default()
            },
            &["min_angle_deg", "max_angle_deg"],
        );
        let caps: RotatorCapabilities = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(caps.min_angle_deg, None);
        assert_eq!(caps.max_angle_deg, None);
        assert!(caps.can_move_absolute);
    }

    #[test]
    fn recommended_settings_from_native_maps_cooling_setpoint() {
        let native = nightshade_native::camera::CameraRecommendedSettings {
            unity_gain: Some(100),
            hcg_gain: None,
            default_offset: Some(30),
            recommended_cooling_setpoint_c: Some(-10.0),
            notes: "test".to_string(),
        };
        let bridge: CameraRecommendedSettings = native.into();
        assert_eq!(bridge.unity_gain, Some(100));
        assert_eq!(bridge.default_offset, Some(30));
        assert_eq!(bridge.recommended_cooling_setpoint_c, Some(-10.0));
        assert_eq!(bridge.notes, "test");
    }
}
