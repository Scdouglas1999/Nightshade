//! INDI Weather device wrapper
//!
//! Provides weather monitoring via INDI protocol.
//!
//! INDI weather devices expose standard properties:
//! - WEATHER_PARAMETERS: Number vector with individual sensor readings
//! - WEATHER_STATUS: Light vector with per-sensor alert states
//!
//! Standard element names under WEATHER_PARAMETERS:
//! WEATHER_TEMPERATURE, WEATHER_HUMIDITY, WEATHER_PRESSURE,
//! WEATHER_WIND_SPEED, WEATHER_WIND_GUST, WEATHER_WIND_DIRECTION,
//! WEATHER_CLOUD_COVER, WEATHER_RAIN_RATE, WEATHER_DEWPOINT,
//! WEATHER_SKY_QUALITY, WEATHER_SKY_TEMPERATURE, WEATHER_SKY_BRIGHTNESS

use crate::client::IndiClient;
use crate::error::IndiResult;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Overall weather status derived from INDI light states
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IndiWeatherStatus {
    /// All parameters OK
    Ok,
    /// Some parameters in warning range
    Warning,
    /// One or more parameters in alert range -- unsafe
    Alert,
    /// Status unknown or device not reporting
    Unknown,
}

/// INDI Weather device wrapper
pub struct IndiWeather {
    client: Arc<RwLock<IndiClient>>,
    device_name: String,
}

impl IndiWeather {
    /// Create a new INDI weather device wrapper
    pub fn new(client: Arc<RwLock<IndiClient>>, device_name: &str) -> Self {
        Self {
            client,
            device_name: device_name.to_string(),
        }
    }

    /// Get the device name
    pub fn device_name(&self) -> &str {
        &self.device_name
    }

    // =========================================================================
    // Connection
    // =========================================================================

    /// Connect to the weather device
    pub async fn connect(&self) -> IndiResult<()> {
        let mut client = self.client.write().await;
        client.connect_device(&self.device_name).await
    }

    /// Disconnect from the weather device
    pub async fn disconnect(&self) -> IndiResult<()> {
        let mut client = self.client.write().await;
        client.disconnect_device(&self.device_name).await
    }

    /// Check if connected
    pub async fn is_connected(&self) -> bool {
        let client = self.client.read().await;
        client.is_device_connected(&self.device_name).await
    }

    // =========================================================================
    // Weather Measurements
    // =========================================================================

    /// Get temperature in Celsius
    pub async fn get_temperature(&self) -> Option<f64> {
        let client = self.client.read().await;
        client
            .get_number(
                &self.device_name,
                "WEATHER_PARAMETERS",
                "WEATHER_TEMPERATURE",
            )
            .await
    }

    /// Get humidity percentage (0-100)
    pub async fn get_humidity(&self) -> Option<f64> {
        let client = self.client.read().await;
        client
            .get_number(&self.device_name, "WEATHER_PARAMETERS", "WEATHER_HUMIDITY")
            .await
    }

    /// Get barometric pressure in hPa
    pub async fn get_pressure(&self) -> Option<f64> {
        let client = self.client.read().await;
        client
            .get_number(&self.device_name, "WEATHER_PARAMETERS", "WEATHER_PRESSURE")
            .await
    }

    /// Get wind speed in m/s
    pub async fn get_wind_speed(&self) -> Option<f64> {
        let client = self.client.read().await;
        client
            .get_number(
                &self.device_name,
                "WEATHER_PARAMETERS",
                "WEATHER_WIND_SPEED",
            )
            .await
    }

    /// Get wind gust speed in m/s
    pub async fn get_wind_gust(&self) -> Option<f64> {
        let client = self.client.read().await;
        client
            .get_number(&self.device_name, "WEATHER_PARAMETERS", "WEATHER_WIND_GUST")
            .await
    }

    /// Get wind direction in degrees (0-360)
    pub async fn get_wind_direction(&self) -> Option<f64> {
        let client = self.client.read().await;
        client
            .get_number(
                &self.device_name,
                "WEATHER_PARAMETERS",
                "WEATHER_WIND_DIRECTION",
            )
            .await
    }

    /// Get cloud cover percentage (0-100)
    pub async fn get_cloud_cover(&self) -> Option<f64> {
        let client = self.client.read().await;
        client
            .get_number(
                &self.device_name,
                "WEATHER_PARAMETERS",
                "WEATHER_CLOUD_COVER",
            )
            .await
    }

    /// Get rain rate in mm/hr
    pub async fn get_rain_rate(&self) -> Option<f64> {
        let client = self.client.read().await;
        client
            .get_number(&self.device_name, "WEATHER_PARAMETERS", "WEATHER_RAIN_RATE")
            .await
    }

    /// Get dew point in Celsius
    pub async fn get_dew_point(&self) -> Option<f64> {
        let client = self.client.read().await;
        client
            .get_number(&self.device_name, "WEATHER_PARAMETERS", "WEATHER_DEWPOINT")
            .await
    }

    /// Get sky quality in mag/arcsec^2
    pub async fn get_sky_quality(&self) -> Option<f64> {
        let client = self.client.read().await;
        client
            .get_number(
                &self.device_name,
                "WEATHER_PARAMETERS",
                "WEATHER_SKY_QUALITY",
            )
            .await
    }

    /// Get sky temperature in Celsius
    pub async fn get_sky_temperature(&self) -> Option<f64> {
        let client = self.client.read().await;
        client
            .get_number(
                &self.device_name,
                "WEATHER_PARAMETERS",
                "WEATHER_SKY_TEMPERATURE",
            )
            .await
    }

    /// Get sky brightness in lux
    pub async fn get_sky_brightness(&self) -> Option<f64> {
        let client = self.client.read().await;
        client
            .get_number(
                &self.device_name,
                "WEATHER_PARAMETERS",
                "WEATHER_SKY_BRIGHTNESS",
            )
            .await
    }

    // =========================================================================
    // Overall Status
    // =========================================================================

    /// Get overall weather status from WEATHER_STATUS light property
    ///
    /// INDI light states: Idle (0), Ok (1), Busy (2), Alert (3)
    /// The overall status is determined by the worst individual sensor state.
    pub async fn get_overall_status(&self) -> IndiWeatherStatus {
        let client = self.client.read().await;

        // Check overall WEATHER_SAFE element first
        if let Some(state) = client
            .get_light_state(&self.device_name, "WEATHER_STATUS", "WEATHER_SAFE")
            .await
        {
            return match state {
                0 | 1 => IndiWeatherStatus::Ok,
                2 => IndiWeatherStatus::Warning,
                3 => IndiWeatherStatus::Alert,
                _ => IndiWeatherStatus::Unknown,
            };
        }

        // Fall back to checking individual weather status elements
        let elements = [
            "WEATHER_RAIN",
            "WEATHER_WIND",
            "WEATHER_CLOUDS",
            "WEATHER_HUMIDITY",
            "WEATHER_TEMPERATURE",
        ];

        let mut worst_state = 0i32;
        let mut found_any = false;

        for element in &elements {
            if let Some(state) = client
                .get_light_state(&self.device_name, "WEATHER_STATUS", element)
                .await
            {
                found_any = true;
                if state > worst_state {
                    worst_state = state;
                }
            }
        }

        if !found_any {
            return IndiWeatherStatus::Unknown;
        }

        match worst_state {
            0 | 1 => IndiWeatherStatus::Ok,
            2 => IndiWeatherStatus::Warning,
            3 => IndiWeatherStatus::Alert,
            _ => IndiWeatherStatus::Unknown,
        }
    }

    /// Check if conditions are safe for observing
    pub async fn is_safe(&self) -> bool {
        match self.get_overall_status().await {
            IndiWeatherStatus::Ok => true,
            IndiWeatherStatus::Warning => true,
            IndiWeatherStatus::Alert => false,
            IndiWeatherStatus::Unknown => true, // Fail-open; caller should check has_weather_status()
        }
    }

    // =========================================================================
    // Alert States
    // =========================================================================

    /// Check if there's a rain alert
    pub async fn has_rain_alert(&self) -> bool {
        let client = self.client.read().await;
        client
            .get_light_state(&self.device_name, "WEATHER_STATUS", "WEATHER_RAIN")
            .await
            .map(|s| s == 3)
            .unwrap_or(false)
    }

    /// Check if there's a wind alert
    pub async fn has_wind_alert(&self) -> bool {
        let client = self.client.read().await;
        client
            .get_light_state(&self.device_name, "WEATHER_STATUS", "WEATHER_WIND")
            .await
            .map(|s| s == 3)
            .unwrap_or(false)
    }

    /// Check if there's a cloud alert
    pub async fn has_cloud_alert(&self) -> bool {
        let client = self.client.read().await;
        client
            .get_light_state(&self.device_name, "WEATHER_STATUS", "WEATHER_CLOUDS")
            .await
            .map(|s| s == 3)
            .unwrap_or(false)
    }

    /// Check if there's a humidity alert
    pub async fn has_humidity_alert(&self) -> bool {
        let client = self.client.read().await;
        client
            .get_light_state(&self.device_name, "WEATHER_STATUS", "WEATHER_HUMIDITY")
            .await
            .map(|s| s == 3)
            .unwrap_or(false)
    }

    // =========================================================================
    // Sensor Availability
    // =========================================================================

    /// Check if WEATHER_STATUS property is available (device reports weather states)
    pub async fn has_weather_status(&self) -> bool {
        let client = self.client.read().await;
        client
            .has_property(&self.device_name, "WEATHER_STATUS")
            .await
    }

    /// Check if WEATHER_PARAMETERS property is available (device reports readings)
    pub async fn has_weather_parameters(&self) -> bool {
        let client = self.client.read().await;
        client
            .has_property(&self.device_name, "WEATHER_PARAMETERS")
            .await
    }

    /// Check if temperature sensor is available
    pub async fn has_temperature(&self) -> bool {
        self.get_temperature().await.is_some()
    }

    /// Check if humidity sensor is available
    pub async fn has_humidity(&self) -> bool {
        self.get_humidity().await.is_some()
    }

    /// Check if pressure sensor is available
    pub async fn has_pressure(&self) -> bool {
        self.get_pressure().await.is_some()
    }

    /// Check if wind speed sensor is available
    pub async fn has_wind_speed(&self) -> bool {
        self.get_wind_speed().await.is_some()
    }

    /// Check if cloud cover sensor is available
    pub async fn has_cloud_cover(&self) -> bool {
        self.get_cloud_cover().await.is_some()
    }

    /// Check if rain rate sensor is available
    pub async fn has_rain_rate(&self) -> bool {
        self.get_rain_rate().await.is_some()
    }

    /// Check if sky quality sensor is available
    pub async fn has_sky_quality(&self) -> bool {
        self.get_sky_quality().await.is_some()
    }

    /// Check if sky temperature sensor is available
    pub async fn has_sky_temperature(&self) -> bool {
        self.get_sky_temperature().await.is_some()
    }

    /// Check if sky brightness sensor is available
    pub async fn has_sky_brightness(&self) -> bool {
        self.get_sky_brightness().await.is_some()
    }
}
