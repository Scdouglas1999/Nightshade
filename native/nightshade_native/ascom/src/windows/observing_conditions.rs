//! ASCOM Observing Conditions wrapper and batch status types.

use super::connection::AscomDeviceConnection;
use super::health::ConnectionHealth;

/// ASCOM Observing Conditions
pub struct AscomObservingConditions {
    device: AscomDeviceConnection,
}

impl AscomObservingConditions {
    pub fn new(prog_id: &str) -> Result<Self, String> {
        Ok(Self {
            device: AscomDeviceConnection::new(prog_id)?,
        })
    }

    pub fn connect(&mut self) -> Result<(), String> {
        self.device.connect()
    }

    pub fn disconnect(&mut self) -> Result<(), String> {
        self.device.disconnect()
    }

    pub fn name(&self) -> Result<String, String> {
        self.device.get_string_property("Name")
    }

    /// Get the interface version number
    pub fn interface_version(&self) -> Result<i32, String> {
        self.device.get_int_property("InterfaceVersion")
    }

    /// Get the driver version string
    pub fn driver_version(&self) -> Result<String, String> {
        self.device.get_string_property("DriverVersion")
    }

    /// Get the driver info/description
    pub fn driver_info(&self) -> Result<String, String> {
        self.device.get_string_property("DriverInfo")
    }

    /// Get the list of supported custom actions
    pub fn supported_actions(&self) -> Result<Vec<String>, String> {
        self.device.get_string_array_property("SupportedActions")
    }

    pub fn cloud_cover(&self) -> Result<f64, String> {
        self.device.get_double_property("CloudCover")
    }

    pub fn dew_point(&self) -> Result<f64, String> {
        self.device.get_double_property("DewPoint")
    }

    pub fn humidity(&self) -> Result<f64, String> {
        self.device.get_double_property("Humidity")
    }

    pub fn pressure(&self) -> Result<f64, String> {
        self.device.get_double_property("Pressure")
    }

    pub fn rain_rate(&self) -> Result<f64, String> {
        self.device.get_double_property("RainRate")
    }

    pub fn sky_brightness(&self) -> Result<f64, String> {
        self.device.get_double_property("SkyBrightness")
    }

    pub fn sky_quality(&self) -> Result<f64, String> {
        self.device.get_double_property("SkyQuality")
    }

    pub fn sky_temperature(&self) -> Result<f64, String> {
        self.device.get_double_property("SkyTemperature")
    }

    pub fn star_fwhm(&self) -> Result<f64, String> {
        self.device.get_double_property("StarFWHM")
    }

    pub fn temperature(&self) -> Result<f64, String> {
        self.device.get_double_property("Temperature")
    }

    pub fn wind_direction(&self) -> Result<f64, String> {
        self.device.get_double_property("WindDirection")
    }

    pub fn wind_gust(&self) -> Result<f64, String> {
        self.device.get_double_property("WindGust")
    }

    pub fn wind_speed(&self) -> Result<f64, String> {
        self.device.get_double_property("WindSpeed")
    }

    // ========================================================================
    // Batch Property Queries
    // ========================================================================

    /// Get weather conditions in a single batch operation
    pub fn get_weather_status(&self) -> WeatherStatus {
        WeatherStatus {
            temperature: self.temperature().ok(),
            humidity: self.humidity().ok(),
            dew_point: self.dew_point().ok(),
            pressure: self.pressure().ok(),
        }
    }

    /// Get wind conditions in a single batch operation
    pub fn get_wind_status(&self) -> WindStatus {
        WindStatus {
            wind_speed: self.wind_speed().ok(),
            wind_gust: self.wind_gust().ok(),
            wind_direction: self.wind_direction().ok(),
        }
    }

    /// Get sky conditions in a single batch operation
    pub fn get_sky_status(&self) -> SkyStatus {
        SkyStatus {
            cloud_cover: self.cloud_cover().ok(),
            sky_brightness: self.sky_brightness().ok(),
            sky_quality: self.sky_quality().ok(),
            sky_temperature: self.sky_temperature().ok(),
            star_fwhm: self.star_fwhm().ok(),
            rain_rate: self.rain_rate().ok(),
        }
    }

    /// Get complete observing conditions status in a single batch operation
    pub fn get_full_status(&self) -> ObservingConditionsFullStatus {
        ObservingConditionsFullStatus {
            weather: self.get_weather_status(),
            wind: self.get_wind_status(),
            sky: self.get_sky_status(),
        }
    }

    /// Perform a heartbeat check to verify device is still responding
    pub fn heartbeat(&self) -> Result<(), String> {
        self.device.heartbeat()
    }

    /// Get connection health status
    pub fn get_health(&self) -> ConnectionHealth {
        self.device.get_health()
    }
}

/// Weather status
#[derive(Debug, Clone, Default)]
pub struct WeatherStatus {
    pub temperature: Option<f64>,
    pub humidity: Option<f64>,
    pub dew_point: Option<f64>,
    pub pressure: Option<f64>,
}

/// Wind status
#[derive(Debug, Clone, Default)]
pub struct WindStatus {
    pub wind_speed: Option<f64>,
    pub wind_gust: Option<f64>,
    pub wind_direction: Option<f64>,
}

/// Sky status
#[derive(Debug, Clone, Default)]
pub struct SkyStatus {
    pub cloud_cover: Option<f64>,
    pub sky_brightness: Option<f64>,
    pub sky_quality: Option<f64>,
    pub sky_temperature: Option<f64>,
    pub star_fwhm: Option<f64>,
    pub rain_rate: Option<f64>,
}

/// Full observing conditions status
#[derive(Debug, Clone, Default)]
pub struct ObservingConditionsFullStatus {
    pub weather: WeatherStatus,
    pub wind: WindStatus,
    pub sky: SkyStatus,
}
