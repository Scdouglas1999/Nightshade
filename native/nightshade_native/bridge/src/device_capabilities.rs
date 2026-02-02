//! Device Capability Reporting
//!
//! This module provides standardized capability reporting for all device types.
//! Capabilities describe what operations a device supports, allowing the UI
//! and sequencer to adapt to device limitations.
//!
//! # Example
//!
//! ```rust
//! let caps = api_get_mount_capabilities(mount_id).await?;
//! if caps.can_pulse_guide {
//!     // Enable PHD2-style guiding
//! }
//! ```

use serde::{Deserialize, Serialize};
use crate::error::NightshadeError;
use crate::device_id::parse_device_id_cached;
// Re-use enums from device module to avoid FRB conflicts
use crate::device::{TrackingRate, CoverState, CalibratorState};

// Import NativeDevice trait for connect/disconnect methods
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

/// Get capabilities for any device type
pub async fn get_device_capabilities(device_id: &str) -> Result<DeviceCapabilities, NightshadeError> {
    // Use cached parsing for better performance
    let parsed = parse_device_id_cached(device_id)?;

    // For now, return basic capabilities
    // Full implementation would query the actual device
    match parsed.driver_type {
        crate::device::DriverType::Alpaca => {
            get_alpaca_capabilities(device_id).await
        }
        crate::device::DriverType::Ascom => {
            get_ascom_capabilities(device_id).await
        }
        crate::device::DriverType::Indi => {
            get_indi_capabilities(device_id).await
        }
        crate::device::DriverType::Native => {
            get_native_capabilities(device_id).await
        }
        crate::device::DriverType::Simulator => {
            Ok(get_simulator_capabilities(device_id))
        }
    }
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
async fn get_alpaca_capabilities(device_id: &str) -> Result<DeviceCapabilities, NightshadeError> {
    // Use cached parsing for better performance
    let parsed = parse_device_id_cached(device_id)?;
    let (_, _, _, device_type, device_num) = parsed.alpaca_info()
        .ok_or_else(|| NightshadeError::invalid_device_id(device_id, "Not an Alpaca device"))?;
    let base_url = parsed.alpaca_base_url()
        .ok_or_else(|| NightshadeError::invalid_device_id(device_id, "Missing base URL"))?;

    match device_type {
        "telescope" | "mount" => {
            let telescope = nightshade_alpaca::AlpacaTelescope::from_server(base_url, device_num);
            telescope.connect().await.map_err(|e| NightshadeError::connection_failed(device_id, e))?;

            let caps = MountCapabilities {
                can_slew: telescope.can_slew().await.unwrap_or(false),
                can_slew_async: telescope.can_slew_async().await.unwrap_or(false),
                can_sync: telescope.can_sync().await.unwrap_or(false),
                can_park: telescope.can_park().await.unwrap_or(false),
                can_unpark: telescope.can_unpark().await.unwrap_or(false),
                can_set_park: telescope.can_set_park().await.unwrap_or(false),
                can_pulse_guide: telescope.can_pulse_guide().await.unwrap_or(false),
                can_set_tracking: telescope.can_set_tracking().await.unwrap_or(false),
                is_equatorial: telescope.equatorial_system().await.unwrap_or(0) > 0,
                can_find_home: telescope.can_find_home().await.unwrap_or(false),
                tracking: telescope.tracking().await.ok(),
                can_abort_slew: true, // Most mounts support abort
                axis_count: 2, // Alpaca lacks axis_count method, default to 2
                ..Default::default()
            };

            telescope.disconnect().await.ok();
            Ok(DeviceCapabilities::Mount(caps))
        }
        "camera" => {
            let camera = nightshade_alpaca::AlpacaCamera::from_server(base_url, device_num);
            camera.connect().await.map_err(|e| NightshadeError::connection_failed(device_id, e))?;

            let caps = CameraCapabilities {
                max_width: camera.camera_x_size().await.unwrap_or(0) as u32,
                max_height: camera.camera_y_size().await.unwrap_or(0) as u32,
                bit_depth: camera.max_adu().await.map(|a| if a > 65535 { 32 } else if a > 255 { 16 } else { 8 }).unwrap_or(16),
                has_shutter: camera.has_shutter().await.unwrap_or(false),
                can_set_ccd_temperature: camera.can_set_ccd_temperature().await.unwrap_or(false),
                can_bin: camera.max_bin_x().await.unwrap_or(1) > 1,
                max_bin_x: camera.max_bin_x().await.unwrap_or(1),
                max_bin_y: camera.max_bin_y().await.unwrap_or(1),
                can_abort_exposure: camera.can_abort_exposure().await.unwrap_or(false),
                can_stop_exposure: camera.can_stop_exposure().await.unwrap_or(false),
                pixel_size_x: camera.pixel_size_x().await.ok(),
                pixel_size_y: camera.pixel_size_y().await.ok(),
                is_color: camera.sensor_type().await.map(|t| t > 0).unwrap_or(false),
                exposure_min: None, // Alpaca lacks exposure_min method
                exposure_max: None, // Alpaca lacks exposure_max method
                ..Default::default()
            };

            camera.disconnect().await.ok();
            Ok(DeviceCapabilities::Camera(caps))
        }
        "focuser" => {
            let focuser = nightshade_alpaca::AlpacaFocuser::from_server(base_url, device_num);
            focuser.connect().await.map_err(|e| NightshadeError::connection_failed(device_id, e))?;

            let caps = FocuserCapabilities {
                max_position: focuser.max_step().await.unwrap_or(0),
                max_increment: focuser.max_increment().await.unwrap_or(0),
                step_size: focuser.step_size().await.ok(),
                absolute: focuser.absolute().await.unwrap_or(false),
                temp_comp_available: focuser.temp_comp_available().await.unwrap_or(false),
                temp_comp: focuser.temp_comp().await.unwrap_or(false),
                temperature: focuser.temperature().await.ok(),
                is_moving: focuser.is_moving().await.unwrap_or(false),
                position: focuser.position().await.ok(),
                ..Default::default()
            };

            focuser.disconnect().await.ok();
            Ok(DeviceCapabilities::Focuser(caps))
        }
        "filterwheel" => {
            let fw = nightshade_alpaca::AlpacaFilterWheel::from_server(base_url, device_num);
            fw.connect().await.map_err(|e| NightshadeError::connection_failed(device_id, e))?;

            let names = fw.names().await.unwrap_or_default();
            let offsets = fw.focus_offsets().await.unwrap_or_default();

            let caps = FilterWheelCapabilities {
                position_count: names.len() as i32,
                current_position: fw.position().await.ok().map(|p| p as i32),
                filter_names: names,
                focus_offsets: offsets,
                is_moving: false, // Alpaca doesn't have a direct is_moving
                ..Default::default()
            };

            fw.disconnect().await.ok();
            Ok(DeviceCapabilities::FilterWheel(caps))
        }
        "rotator" => {
            let rotator = nightshade_alpaca::AlpacaRotator::from_server(base_url, device_num);
            rotator.connect().await.map_err(|e| NightshadeError::connection_failed(device_id, e))?;

            let caps = RotatorCapabilities {
                can_reverse: rotator.can_reverse().await.unwrap_or(false),
                reverse: rotator.reverse().await.unwrap_or(false),
                step_size: rotator.step_size().await.ok(),
                is_moving: rotator.is_moving().await.unwrap_or(false),
                mechanical_position: rotator.mechanical_position().await.ok(),
                position: rotator.position().await.ok(),
                can_move_absolute: true, // Alpaca rotators support absolute positioning
                can_halt: true, // All rotators support halt
                can_sync: true, // Most rotators support sync
            };

            rotator.disconnect().await.ok();
            Ok(DeviceCapabilities::Rotator(caps))
        }
        "dome" => {
            let dome = nightshade_alpaca::AlpacaDome::from_server(base_url, device_num);
            dome.connect().await.map_err(|e| NightshadeError::connection_failed(device_id, e))?;

            // Convert Alpaca ShutterStatus to our ShutterStatus
            let shutter_status = dome.shutter_status().await.ok().map(|s| {
                match s {
                    nightshade_alpaca::ShutterStatus::Open => ShutterStatus::Open,
                    nightshade_alpaca::ShutterStatus::Closed => ShutterStatus::Closed,
                    nightshade_alpaca::ShutterStatus::Opening => ShutterStatus::Opening,
                    nightshade_alpaca::ShutterStatus::Closing => ShutterStatus::Closing,
                    nightshade_alpaca::ShutterStatus::Error => ShutterStatus::Unknown,
                }
            });

            let caps = DomeCapabilities {
                can_set_azimuth: dome.can_set_azimuth().await.unwrap_or(false),
                can_park: dome.can_park().await.unwrap_or(false),
                can_find_home: dome.can_find_home().await.unwrap_or(false),
                can_set_shutter: dome.can_set_shutter().await.unwrap_or(false),
                can_sync_azimuth: dome.can_sync_azimuth().await.unwrap_or(false),
                azimuth: dome.azimuth().await.ok(),
                slewing: dome.slewing().await.unwrap_or(false),
                at_home: dome.at_home().await.unwrap_or(false),
                at_park: dome.at_park().await.unwrap_or(false),
                shutter_status,
                can_slave: dome.can_slave().await.unwrap_or(false),
                slaved: dome.slaved().await.unwrap_or(false),
                can_abort: true, // Alpaca domes support abort
            };

            dome.disconnect().await.ok();
            Ok(DeviceCapabilities::Dome(caps))
        }
        "covercalibrator" => {
            let cc = nightshade_alpaca::AlpacaCoverCalibrator::from_server(base_url, device_num);
            cc.connect().await.map_err(|e| NightshadeError::connection_failed(device_id, e))?;

            // Convert Alpaca CoverStatus to our CoverState
            let cover_state = cc.cover_state().await.ok().map(|s| {
                match s {
                    nightshade_alpaca::CoverStatus::NotPresent => CoverState::NotPresent,
                    nightshade_alpaca::CoverStatus::Closed => CoverState::Closed,
                    nightshade_alpaca::CoverStatus::Moving => CoverState::Moving,
                    nightshade_alpaca::CoverStatus::Open => CoverState::Open,
                    nightshade_alpaca::CoverStatus::Unknown => CoverState::Unknown,
                    nightshade_alpaca::CoverStatus::Error => CoverState::Error,
                }
            });

            // Convert Alpaca CalibratorStatus to our CalibratorState
            let calibrator_state = cc.calibrator_state().await.ok().map(|s| {
                match s {
                    nightshade_alpaca::CalibratorStatus::NotPresent => CalibratorState::NotPresent,
                    nightshade_alpaca::CalibratorStatus::Off => CalibratorState::Off,
                    nightshade_alpaca::CalibratorStatus::NotReady => CalibratorState::NotReady,
                    nightshade_alpaca::CalibratorStatus::Ready => CalibratorState::Ready,
                    nightshade_alpaca::CalibratorStatus::Unknown => CalibratorState::Unknown,
                    nightshade_alpaca::CalibratorStatus::Error => CalibratorState::Error,
                }
            });

            let caps = CoverCalibratorCapabilities {
                max_brightness: cc.max_brightness().await.unwrap_or(0),
                cover_present: cover_state.map_or(false, |s| s != CoverState::NotPresent),
                calibrator_present: calibrator_state.map_or(false, |s| s != CalibratorState::NotPresent),
                cover_state,
                calibrator_state,
                brightness: cc.brightness().await.ok(),
            };

            cc.disconnect().await.ok();
            Ok(DeviceCapabilities::CoverCalibrator(caps))
        }
        "observingconditions" => {
            let weather = nightshade_alpaca::AlpacaObservingConditions::from_server(base_url, device_num);
            weather.connect().await.map_err(|e| NightshadeError::connection_failed(device_id, e))?;

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

            weather.disconnect().await.ok();
            Ok(DeviceCapabilities::Weather(caps))
        }
        "safetymonitor" => {
            let safety = nightshade_alpaca::AlpacaSafetyMonitor::from_server(base_url, device_num);
            safety.connect().await.map_err(|e| NightshadeError::connection_failed(device_id, e))?;

            let caps = SafetyMonitorCapabilities {
                is_safe: safety.is_safe().await.unwrap_or(false),
                safety_description: None, // Alpaca doesn't provide a description
            };

            safety.disconnect().await.ok();
            Ok(DeviceCapabilities::SafetyMonitor(caps))
        }
        "switch" => {
            let switch = nightshade_alpaca::AlpacaSwitch::from_server(base_url, device_num);
            switch.connect().await.map_err(|e| NightshadeError::connection_failed(device_id, e))?;

            let max_switch = switch.max_switch().await.unwrap_or(0);
            let mut switches = Vec::new();

            for i in 0..max_switch {
                let name = switch.get_switch_name(i).await.unwrap_or_else(|_| format!("Switch {}", i));
                let description = switch.get_switch_description(i).await.unwrap_or_default();
                let min_value = switch.min_switch_value(i).await.unwrap_or(0.0);
                let max_value = switch.max_switch_value(i).await.unwrap_or(1.0);
                // Alpaca doesn't provide switch step, default to 1.0
                let step = 1.0;
                let can_write = switch.can_write(i).await.unwrap_or(false);
                let value = switch.get_switch_value(i).await.unwrap_or(0.0);

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
        _ => Err(NightshadeError::not_supported(device_id, "get_capabilities")),
    }
}

/// Get capabilities for an ASCOM device (Windows only)
#[cfg(windows)]
async fn get_ascom_capabilities(device_id: &str) -> Result<DeviceCapabilities, NightshadeError> {
    use crate::ascom_wrapper::AscomCameraWrapper;
    use crate::ascom_wrapper_mount::AscomMountWrapper;

    let parsed = parse_device_id_cached(device_id)?;
    let prog_id = match &parsed.connection_info {
        crate::device_id::ConnectionInfo::Ascom { prog_id } => prog_id.clone(),
        _ => return Err(NightshadeError::invalid_device_id(device_id, "Not an ASCOM device")),
    };

    // Determine device type from ProgID (common ASCOM naming conventions)
    let prog_id_lower = prog_id.to_lowercase();

    if prog_id_lower.contains("camera") {
        // Query camera capabilities
        let mut wrapper = AscomCameraWrapper::new(prog_id.clone())
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        // Try to connect and get capabilities
        wrapper.connect().await
            .map_err(|e| NightshadeError::connection_failed(device_id, format!("{:?}", e)))?;

        let ascom_caps = wrapper.get_capabilities().await
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
            ..Default::default()
        }))
    } else if prog_id_lower.contains("telescope") || prog_id_lower.contains("mount") {
        // Query mount capabilities
        let mut wrapper = AscomMountWrapper::new(prog_id.clone())
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        wrapper.connect().await
            .map_err(|e| NightshadeError::connection_failed(device_id, format!("{:?}", e)))?;

        let ascom_caps = wrapper.get_capabilities().await
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
            axis_count: if ascom_caps.can_move_axis_secondary { 2 } else { 1 },
            ..Default::default()
        }))
    } else if prog_id_lower.contains("focuser") {
        // For focuser, use the ASCOM library directly since we don't have a wrapper yet
        use nightshade_ascom::{AscomFocuser, init_com};

        // Initialize COM on this thread if needed
        let _ = init_com();

        let mut focuser = AscomFocuser::new(&prog_id)
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        focuser.connect()
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        let caps = focuser.get_capabilities();
        let _ = focuser.disconnect();

        Ok(DeviceCapabilities::Focuser(FocuserCapabilities {
            max_position: caps.max_step.unwrap_or(0),
            max_increment: caps.max_increment.unwrap_or(0),
            step_size: caps.step_size,
            absolute: caps.absolute.unwrap_or(false),
            temp_comp_available: caps.temp_comp_available.unwrap_or(false),
            ..Default::default()
        }))
    } else if prog_id_lower.contains("filterwheel") || prog_id_lower.contains("filter") {
        // For filter wheel, use the ASCOM library directly
        use nightshade_ascom::{AscomFilterWheel, init_com};

        let _ = init_com();

        let mut fw = AscomFilterWheel::new(&prog_id)
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        fw.connect()
            .map_err(|e| NightshadeError::connection_failed(device_id, e))?;

        let names = fw.names().unwrap_or_default();
        let position = fw.position().ok().map(|p| p as i32);
        let _ = fw.disconnect();

        Ok(DeviceCapabilities::FilterWheel(FilterWheelCapabilities {
            position_count: names.len() as i32,
            current_position: position,
            filter_names: names,
            focus_offsets: vec![], // ASCOM FocusOffsets not always available
            ..Default::default()
        }))
    } else {
        Err(NightshadeError::not_supported(device_id, "Unknown ASCOM device type"))
    }
}

#[cfg(not(windows))]
async fn get_ascom_capabilities(device_id: &str) -> Result<DeviceCapabilities, NightshadeError> {
    Err(NightshadeError::not_supported(device_id, "ASCOM is only available on Windows"))
}

/// Get capabilities for an INDI device
///
/// INDI devices report capabilities through their property definitions.
/// This function queries the INDI server to discover what properties
/// (and thus capabilities) a device supports.
async fn get_indi_capabilities(device_id: &str) -> Result<DeviceCapabilities, NightshadeError> {
    use nightshade_indi::IndiClient;

    let parsed = parse_device_id_cached(device_id)?;
    let (host, port, device_name) = match &parsed.connection_info {
        crate::device_id::ConnectionInfo::Indi { host, port, device_name } => {
            (host.clone(), *port, device_name.clone())
        }
        _ => return Err(NightshadeError::invalid_device_id(device_id, "Not an INDI device")),
    };

    // Create and connect to INDI server
    let mut client = IndiClient::new(&host, Some(port));
    client.connect().await
        .map_err(|e| NightshadeError::connection_failed(device_id, format!("{:?}", e)))?;

    // Give the server time to populate properties
    tokio::time::sleep(std::time::Duration::from_millis(1000)).await;

    // Get all properties for this device
    let properties = client.get_properties(&device_name).await;

    // Determine device type based on standard INDI property names
    let has_ccd_props = properties.iter().any(|p| {
        p.name.starts_with("CCD_") || p.name == "CCD_EXPOSURE"
    });
    let has_telescope_props = properties.iter().any(|p| {
        p.name.starts_with("EQUATORIAL_") || p.name == "TELESCOPE_MOTION_NS"
    });
    let has_focuser_props = properties.iter().any(|p| {
        p.name.starts_with("FOCUS_") || p.name == "ABS_FOCUS_POSITION"
    });
    let has_filter_props = properties.iter().any(|p| {
        p.name.starts_with("FILTER_") || p.name == "FILTER_SLOT"
    });

    // Build capabilities based on discovered properties
    if has_ccd_props {
        // Check for specific CCD capabilities
        let can_abort = properties.iter().any(|p| p.name == "CCD_ABORT_EXPOSURE");
        let has_cooler = properties.iter().any(|p| p.name == "CCD_COOLER" || p.name == "CCD_TEMPERATURE");
        let has_binning = properties.iter().any(|p| p.name == "CCD_BINNING");
        let has_gain = properties.iter().any(|p| p.name == "CCD_GAIN" || p.name == "CCD_CONTROLS");

        Ok(DeviceCapabilities::Camera(CameraCapabilities {
            can_abort_exposure: can_abort,
            can_set_ccd_temperature: has_cooler,
            can_set_cooler: has_cooler,
            can_bin: has_binning,
            can_set_gain: has_gain,
            // Other properties default to false/unknown since INDI doesn't always expose min/max
            ..Default::default()
        }))
    } else if has_telescope_props {
        let can_park = properties.iter().any(|p| p.name == "TELESCOPE_PARK");
        let can_sync = properties.iter().any(|p| p.name == "ON_COORD_SET");
        let can_guide = properties.iter().any(|p| p.name.starts_with("TELESCOPE_TIMED_GUIDE_"));
        let can_track = properties.iter().any(|p| p.name == "TELESCOPE_TRACK_STATE");

        Ok(DeviceCapabilities::Mount(MountCapabilities {
            can_slew: true, // Most INDI mounts support slewing
            can_slew_async: true,
            can_sync,
            can_park,
            can_unpark: can_park,
            can_pulse_guide: can_guide,
            can_set_tracking: can_track,
            is_equatorial: properties.iter().any(|p| p.name.starts_with("EQUATORIAL_")),
            ..Default::default()
        }))
    } else if has_focuser_props {
        let is_absolute = properties.iter().any(|p| p.name == "ABS_FOCUS_POSITION");
        let has_temp_comp = properties.iter().any(|p| p.name == "FOCUS_TEMPERATURE");

        Ok(DeviceCapabilities::Focuser(FocuserCapabilities {
            absolute: is_absolute,
            temp_comp_available: has_temp_comp,
            ..Default::default()
        }))
    } else if has_filter_props {
        Ok(DeviceCapabilities::FilterWheel(FilterWheelCapabilities {
            ..Default::default()
        }))
    } else {
        // Unknown device type - return minimal capabilities
        Err(NightshadeError::not_supported(device_id, "Could not determine INDI device type from properties"))
    }
}

/// Get capabilities for a native SDK device
///
/// Native SDK devices (ZWO, QHY, PlayerOne, etc.) typically have well-defined
/// capabilities that can be queried from their SDK functions. This function
/// returns capability information based on the vendor and device type.
async fn get_native_capabilities(device_id: &str) -> Result<DeviceCapabilities, NightshadeError> {
    let parsed = parse_device_id_cached(device_id)?;
    let (vendor, _device_idx) = match &parsed.connection_info {
        crate::device_id::ConnectionInfo::Native { vendor, device_index, .. } => {
            (vendor.clone(), *device_index)
        }
        _ => return Err(NightshadeError::invalid_device_id(device_id, "Not a native SDK device")),
    };

    // Native SDK capabilities vary by vendor
    // For now, return capabilities based on vendor defaults
    // A full implementation would query the SDK for specific device capabilities
    let vendor_lower = vendor.to_lowercase();

    if vendor_lower.contains("camera") || device_id.to_lowercase().contains("camera") {
        // Return camera capabilities with vendor-specific defaults
        let (has_cooler, has_gain, has_offset) = match vendor_lower.as_str() {
            "zwo" | "zwocamera" => (true, true, true),
            "qhy" | "qhycamera" => (true, true, true),
            "playerone" | "playeonecamera" => (true, true, true),
            "svbony" | "svbonycamera" => (false, true, true),
            _ => (false, true, false),
        };

        Ok(DeviceCapabilities::Camera(CameraCapabilities {
            can_set_ccd_temperature: has_cooler,
            can_set_cooler: has_cooler,
            can_get_cooler_power: has_cooler,
            can_set_gain: has_gain,
            can_set_offset: has_offset,
            can_abort_exposure: true,
            can_bin: true,
            can_subframe: true,
            ..Default::default()
        }))
    } else if vendor_lower.contains("mount") || device_id.to_lowercase().contains("mount") {
        // Native mount drivers (iOptron, SkyWatcher, etc.)
        Ok(DeviceCapabilities::Mount(MountCapabilities {
            can_slew: true,
            can_slew_async: true,
            can_sync: true,
            can_park: true,
            can_unpark: true,
            can_pulse_guide: true,
            can_set_tracking: true,
            is_equatorial: true,
            ..Default::default()
        }))
    } else {
        // Unknown native device type
        Err(NightshadeError::not_supported(
            device_id,
            "Could not determine native SDK device type",
        ))
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
            filter_names: vec!["L".into(), "R".into(), "G".into(), "B".into(), "Ha".into(), "OIII".into(), "SII".into()],
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
    } else if device_id_lower.contains("weather") || device_id_lower.contains("observingconditions") {
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
