//! Camera-specific types and structures for native drivers

use serde::{Deserialize, Serialize};

/// Camera capabilities
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CameraCapabilities {
    pub can_cool: bool,
    pub can_set_gain: bool,
    pub can_set_offset: bool,
    pub can_set_binning: bool,
    pub can_subframe: bool,
    pub has_shutter: bool,
    pub has_guider_port: bool,
    pub max_bin_x: i32,
    pub max_bin_y: i32,
    pub supports_readout_modes: bool,
}

/// Current camera status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CameraStatus {
    pub state: CameraState,
    pub sensor_temp: Option<f64>,
    pub cooler_power: Option<f64>,
    pub target_temp: Option<f64>,
    pub cooler_on: bool,
    pub gain: i32,
    pub offset: i32,
    pub bin_x: i32,
    pub bin_y: i32,
    pub exposure_remaining: Option<f64>, // seconds
}

/// Camera operational state
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CameraState {
    Idle,
    Waiting,
    Exposing,
    Reading,
    Downloading,
    Error,
}

/// Exposure parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExposureParams {
    pub duration_secs: f64,
    pub gain: Option<i32>,
    pub offset: Option<i32>,
    pub bin_x: i32,
    pub bin_y: i32,
    pub subframe: Option<SubFrame>,
    pub readout_mode: Option<String>, // Vendor-specific readout mode name
}

/// Subframe region for partial readout
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubFrame {
    pub start_x: u32,
    pub start_y: u32,
    pub width: u32,
    pub height: u32,
}

/// Sensor information
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SensorInfo {
    pub width: u32,
    pub height: u32,
    pub pixel_size_x: f64, // microns
    pub pixel_size_y: f64, // microns
    pub max_adu: u32,
    pub bit_depth: u32,
    pub color: bool,
    pub bayer_pattern: Option<BayerPattern>,
}

/// Bayer pattern for color sensors
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BayerPattern {
    Rggb,
    Grbg,
    Gbrg,
    Bggr,
}

/// Readout mode (vendor-specific)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReadoutMode {
    pub name: String,
    pub description: String,
    pub index: i32,
    pub gain_min: Option<i32>,
    pub gain_max: Option<i32>,
    pub offset_min: Option<i32>,
    pub offset_max: Option<i32>,
}

/// Vendor-specific features
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct VendorFeatures {
    /// QHY: Sensor chamber air pressure (hPa)
    pub sensor_chamber_pressure: Option<f64>,

    /// QHY: Sensor chamber humidity (%)
    pub sensor_chamber_humidity: Option<f64>,

    /// ZWO/QHY/SVBony: USB bandwidth percentage
    pub usb_bandwidth: Option<f64>,

    /// ZWO: Hardware binning support
    pub hardware_binning: bool,

    /// ZWO/Player One: Anti-dew heater control
    pub anti_dew_heater: Option<bool>,

    /// Player One: Fan power percentage (0-100)
    pub fan_power: Option<f64>,

    /// Generic: Additional vendor-specific data
    pub custom_data: std::collections::HashMap<String, serde_json::Value>,
}

/// Image data from camera
#[derive(Debug, Clone)]
pub struct ImageData {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u16>, // 16-bit raw data
    pub bits_per_pixel: u32,
    pub bayer_pattern: Option<BayerPattern>,
    pub metadata: ImageMetadata,
}

/// Image metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageMetadata {
    pub exposure_time: f64,
    pub gain: i32,
    pub offset: i32,
    pub bin_x: i32,
    pub bin_y: i32,
    pub temperature: Option<f64>,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub subframe: Option<SubFrame>,
    pub readout_mode: Option<String>,
    pub vendor_data: VendorFeatures,
}





