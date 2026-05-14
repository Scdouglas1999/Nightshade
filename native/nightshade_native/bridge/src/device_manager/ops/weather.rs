//! Weather (observing conditions) operations dispatcher.
//!
//! Methods in this module are an additional impl block on `DeviceManager`
//! using Rust's split-impl-block feature. Behavior is identical to the
//! previous monolithic `devices.rs`.

use crate::device::*;
use crate::device_manager::DeviceManager;

impl DeviceManager {
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
}
