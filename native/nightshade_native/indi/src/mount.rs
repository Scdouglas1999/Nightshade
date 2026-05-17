//! INDI Mount wrapper
//!
//! Provides high-level telescope mount control via INDI protocol.

use crate::client::IndiClient;
use crate::error::{IndiError, IndiResult};
use crate::protocol::coord_elements::*;
use crate::protocol::standard_properties::*;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;

/// INDI Mount device wrapper
pub struct IndiMount {
    client: Arc<RwLock<IndiClient>>,
    device_name: String,
}

impl IndiMount {
    async fn current_on_coord_set_mode(
        client: &IndiClient,
        device_name: &str,
    ) -> Option<&'static str> {
        let slew = client.get_switch(device_name, ON_COORD_SET, "SLEW").await;
        let sync = client.get_switch(device_name, ON_COORD_SET, "SYNC").await;
        let track = client.get_switch(device_name, ON_COORD_SET, "TRACK").await;

        if slew == Some(true) {
            Some("SLEW")
        } else if sync == Some(true) {
            Some("SYNC")
        } else if track.is_some() {
            Some("TRACK")
        } else {
            None
        }
    }

    async fn restore_on_coord_set_mode(
        client: &mut IndiClient,
        device_name: &str,
        previous_mode: Option<&'static str>,
    ) {
        if let Some(mode) = previous_mode {
            if let Err(error) = client
                .set_switch(device_name, ON_COORD_SET, mode, true)
                .await
            {
                tracing::warn!(
                    "Failed to restore ON_COORD_SET mode '{}' for {} after slew error: {}",
                    mode,
                    device_name,
                    error
                );
            }
        }
    }

    /// Create a new INDI mount wrapper
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

    /// Connect to the mount
    pub async fn connect(&self) -> IndiResult<()> {
        let mut client = self.client.write().await;
        client.connect_device(&self.device_name).await
    }

    /// Disconnect from the mount
    pub async fn disconnect(&self) -> IndiResult<()> {
        let mut client = self.client.write().await;
        client.disconnect_device(&self.device_name).await
    }

    /// Check if connected
    pub async fn is_connected(&self) -> bool {
        let client = self.client.read().await;
        client.is_device_connected(&self.device_name).await
    }

    /// Get current coordinates (RA in hours, Dec in degrees)
    pub async fn get_coordinates(&self) -> Result<(f64, f64), String> {
        let client = self.client.read().await;

        // Try J2000 coordinates first, then fall back to EOD coordinates
        let ra = client
            .get_number(&self.device_name, EQUATORIAL_COORD, RA)
            .await
            .or(client
                .get_number(&self.device_name, EQUATORIAL_EOD_COORD, RA)
                .await)
            .ok_or_else(|| "RA not available".to_string())?;

        let dec = client
            .get_number(&self.device_name, EQUATORIAL_COORD, DEC)
            .await
            .or(client
                .get_number(&self.device_name, EQUATORIAL_EOD_COORD, DEC)
                .await)
            .ok_or_else(|| "Dec not available".to_string())?;

        Ok((ra, dec))
    }

    /// Slew to coordinates (RA in hours, Dec in degrees)
    pub async fn slew_to_coordinates(&self, ra_hours: f64, dec_degrees: f64) -> IndiResult<()> {
        let mut client = self.client.write().await;
        let previous_mode = Self::current_on_coord_set_mode(&client, &self.device_name).await;

        // Set coordinate mode to SLEW
        client
            .set_switch(&self.device_name, ON_COORD_SET, "SLEW", true)
            .await?;

        // Set target coordinates
        if let Err(error) = client
            .set_numbers(
                &self.device_name,
                EQUATORIAL_EOD_COORD,
                &[(RA, ra_hours), (DEC, dec_degrees)],
            )
            .await
        {
            Self::restore_on_coord_set_mode(&mut client, &self.device_name, previous_mode).await;
            return Err(error);
        }

        Ok(())
    }

    /// Slew to coordinates with timeout (RA in hours, Dec in degrees)
    pub async fn slew_to_coordinates_with_timeout(
        &self,
        ra_hours: f64,
        dec_degrees: f64,
        timeout: Option<Duration>,
    ) -> Result<(), String> {
        // Read config outside the closure - async-friendly
        let timeout_duration = if let Some(t) = timeout {
            t
        } else {
            let client = self.client.read().await;
            Duration::from_secs(client.timeout_config().mount_slew_timeout_secs)
        };

        // Start the slew
        {
            let mut client = self.client.write().await;
            let previous_mode = Self::current_on_coord_set_mode(&client, &self.device_name).await;
            client
                .set_switch(&self.device_name, ON_COORD_SET, "SLEW", true)
                .await?;
            if let Err(error) = client
                .set_numbers(
                    &self.device_name,
                    EQUATORIAL_EOD_COORD,
                    &[(RA, ra_hours), (DEC, dec_degrees)],
                )
                .await
            {
                Self::restore_on_coord_set_mode(&mut client, &self.device_name, previous_mode)
                    .await;
                return Err(error.to_string());
            }
        }

        // Wait for slew to complete
        let client = self.client.read().await;
        client
            .wait_for_property_not_busy(&self.device_name, EQUATORIAL_EOD_COORD, timeout_duration)
            .await
            .map_err(|e| {
                format!(
                    "Mount slew to RA={:.4}h, Dec={:.4}° failed: {}",
                    ra_hours, dec_degrees, e
                )
            })
    }

    /// Sync to coordinates (RA in hours, Dec in degrees)
    pub async fn sync_to_coordinates(&self, ra_hours: f64, dec_degrees: f64) -> IndiResult<()> {
        let mut client = self.client.write().await;

        // Set coordinate mode to SYNC
        client
            .set_switch(&self.device_name, ON_COORD_SET, "SYNC", true)
            .await?;

        // Set target coordinates
        client
            .set_numbers(
                &self.device_name,
                EQUATORIAL_EOD_COORD,
                &[(RA, ra_hours), (DEC, dec_degrees)],
            )
            .await
    }

    /// Abort slew
    pub async fn abort_slew(&self) -> IndiResult<()> {
        let mut client = self.client.write().await;
        client
            .set_switch(&self.device_name, TELESCOPE_ABORT_MOTION, "ABORT", true)
            .await
    }

    /// Park the mount
    pub async fn park(&self) -> IndiResult<()> {
        let mut client = self.client.write().await;
        client
            .set_switch(&self.device_name, TELESCOPE_PARK, "PARK", true)
            .await
    }

    /// Unpark the mount
    pub async fn unpark(&self) -> IndiResult<()> {
        let mut client = self.client.write().await;
        client
            .set_switch(&self.device_name, TELESCOPE_PARK, "UNPARK", true)
            .await
    }

    /// Check if parked.
    ///
    /// Returns:
    /// * `Ok(true)` — `TELESCOPE_PARK/PARK` is `On`.
    /// * `Ok(false)` — the property is defined but `PARK` is `Off`.
    /// * `Err(IndiError::PropertyNotFound)` — the driver has not (yet)
    ///   defined `TELESCOPE_PARK`. The UI must surface "unknown" rather than
    ///   "not parked"; per audit §5.15 a disconnected mount should never look
    ///   like "alive but stationary".
    pub async fn try_is_parked(&self) -> Result<bool, IndiError> {
        let client = self.client.read().await;
        match client
            .get_switch(&self.device_name, TELESCOPE_PARK, "PARK")
            .await
        {
            Some(v) => Ok(v),
            None => Err(IndiError::PropertyNotFound {
                device: self.device_name.clone(),
                property: TELESCOPE_PARK.to_string(),
            }),
        }
    }

    /// Set tracking state
    pub async fn set_tracking(&self, enabled: bool) -> IndiResult<()> {
        let mut client = self.client.write().await;
        if enabled {
            client
                .set_switch(&self.device_name, TELESCOPE_TRACK_STATE, "TRACK_ON", true)
                .await
        } else {
            client
                .set_switch(&self.device_name, TELESCOPE_TRACK_STATE, "TRACK_OFF", true)
                .await
        }
    }

    /// Check if tracking.
    ///
    /// Returns:
    /// * `Ok(true)` — `TELESCOPE_TRACK_STATE/TRACK_ON` is `On`.
    /// * `Ok(false)` — the property is defined but `TRACK_ON` is `Off`.
    /// * `Err(IndiError::PropertyNotFound)` — the driver has not (yet)
    ///   defined `TELESCOPE_TRACK_STATE`.
    pub async fn try_is_tracking(&self) -> Result<bool, IndiError> {
        let client = self.client.read().await;
        match client
            .get_switch(&self.device_name, TELESCOPE_TRACK_STATE, "TRACK_ON")
            .await
        {
            Some(v) => Ok(v),
            None => Err(IndiError::PropertyNotFound {
                device: self.device_name.clone(),
                property: TELESCOPE_TRACK_STATE.to_string(),
            }),
        }
    }

    /// Check if slewing.
    ///
    /// Returns:
    /// * `Ok(true)` — `EQUATORIAL_EOD_COORD` is in the `Busy` state.
    /// * `Ok(false)` — the property is defined and not `Busy`.
    /// * `Err(IndiError::PropertyNotFound)` — the property has not been
    ///   defined yet, so the mount may not be initialised. Per audit §5.15
    ///   this is distinct from "definitely not slewing".
    pub async fn try_is_slewing(&self) -> Result<bool, IndiError> {
        let client = self.client.read().await;
        match client
            .get_property_state(&self.device_name, EQUATORIAL_EOD_COORD)
            .await
        {
            Some(state) => Ok(state == crate::IndiPropertyState::Busy),
            None => Err(IndiError::PropertyNotFound {
                device: self.device_name.clone(),
                property: EQUATORIAL_EOD_COORD.to_string(),
            }),
        }
    }

    /// Move north
    pub async fn move_north(&self, start: bool) -> IndiResult<()> {
        let mut client = self.client.write().await;
        client
            .set_switch(
                &self.device_name,
                TELESCOPE_MOTION_NS,
                "MOTION_NORTH",
                start,
            )
            .await
    }

    /// Move south
    pub async fn move_south(&self, start: bool) -> IndiResult<()> {
        let mut client = self.client.write().await;
        client
            .set_switch(
                &self.device_name,
                TELESCOPE_MOTION_NS,
                "MOTION_SOUTH",
                start,
            )
            .await
    }

    /// Move west
    pub async fn move_west(&self, start: bool) -> IndiResult<()> {
        let mut client = self.client.write().await;
        client
            .set_switch(&self.device_name, TELESCOPE_MOTION_WE, "MOTION_WEST", start)
            .await
    }

    /// Move east
    pub async fn move_east(&self, start: bool) -> IndiResult<()> {
        let mut client = self.client.write().await;
        client
            .set_switch(&self.device_name, TELESCOPE_MOTION_WE, "MOTION_EAST", start)
            .await
    }

    /// Set slew rate (0-4 typically, where 0 is slowest)
    pub async fn set_slew_rate(&self, rate: i32) -> IndiResult<()> {
        let mut client = self.client.write().await;
        // Different mounts use different switch names, try common patterns
        let rate_names = ["1x", "2x", "4x", "8x", "16x", "32x", "64x", "MAX"];
        // Why: rate is i32 (0..7 expected). Clamp negatives to 0 explicitly
        // rather than relying on i32->usize sign-wrap + .min() accidentally
        // landing at MAX. Negative input is a caller bug; clamping to slowest
        // rate is the safest fallback for a mount slew request.
        let rate_clamped = rate.max(0);
        let rate_idx = usize::try_from(rate_clamped)
            .unwrap_or(0)
            .min(rate_names.len() - 1);

        // Try numbered rate first
        if client
            .set_switch(
                &self.device_name,
                TELESCOPE_SLEW_RATE,
                rate_names[rate_idx],
                true,
            )
            .await
            .is_ok()
        {
            return Ok(());
        }

        // Try SLEWMODE pattern
        let mode = format!("SLEW{}", rate);
        client
            .set_switch(&self.device_name, "SLEWMODE", &mode, true)
            .await
    }

    /// Slew to horizontal coordinates (Alt/Az)
    ///
    /// INDI mounts that support HORIZONTAL_COORD can be slewed in alt/az mode
    /// by writing to the HORIZONTAL_COORD number property.
    pub async fn slew_to_alt_az(&self, altitude: f64, azimuth: f64) -> IndiResult<()> {
        let mut client = self.client.write().await;

        // Set target horizontal coordinates - the INDI driver handles the
        // coordinate transformation and slew internally
        client
            .set_numbers(
                &self.device_name,
                HORIZONTAL_COORD,
                &[(ALT, altitude), (AZ, azimuth)],
            )
            .await
    }

    /// Find mount home position
    ///
    /// Sets the TELESCOPE_HOME switch to "GO" which commands the mount to
    /// find its home position. Not all INDI mounts support this property.
    pub async fn find_home(&self) -> IndiResult<()> {
        let mut client = self.client.write().await;
        client
            .set_switch(&self.device_name, TELESCOPE_HOME, "GO", true)
            .await
    }

    /// Get horizontal coordinates (Altitude, Azimuth)
    pub async fn get_horizontal_coordinates(&self) -> Result<(f64, f64), String> {
        let client = self.client.read().await;
        let alt = client
            .get_number(&self.device_name, HORIZONTAL_COORD, ALT)
            .await
            .ok_or_else(|| "Altitude not available".to_string())?;
        let az = client
            .get_number(&self.device_name, HORIZONTAL_COORD, AZ)
            .await
            .ok_or_else(|| "Azimuth not available".to_string())?;
        Ok((alt, az))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::IndiClient;

    #[tokio::test]
    async fn test_mount_creation() {
        let client = Arc::new(RwLock::new(IndiClient::new("localhost", Some(7624))));
        let mount = IndiMount::new(client, "TestMount");
        assert_eq!(mount.device_name(), "TestMount");
    }

    #[tokio::test]
    async fn test_slew_with_timeout_error_message() {
        let client = Arc::new(RwLock::new(IndiClient::new("localhost", Some(7624))));
        let mount = IndiMount::new(client, "TestMount");

        // This will fail since we're not connected
        let result = mount
            .slew_to_coordinates_with_timeout(10.5, 45.0, Some(Duration::from_millis(100)))
            .await;

        assert!(result.is_err());
        if let Err(e) = result {
            // Error should mention either the coordinates or that we're not connected
            assert!(e.contains("RA=10.5") || e.to_lowercase().contains("not connected"));
        }
    }

    #[tokio::test]
    async fn test_mount_timeout_uses_config() {
        let config = crate::IndiTimeoutConfig {
            mount_slew_timeout_secs: 600, // Custom timeout
            ..Default::default()
        };

        let client = Arc::new(RwLock::new(IndiClient::with_timeout_config(
            "localhost",
            Some(7624),
            config,
        )));
        let _mount = IndiMount::new(client.clone(), "TestMount");

        // Verify the timeout config is accessible
        let timeout_secs = {
            let c = client.read().await;
            c.timeout_config().mount_slew_timeout_secs
        };
        assert_eq!(timeout_secs, 600);
    }

    /// §5.15: when TELESCOPE_PARK is undefined, try_is_parked must return
    /// PropertyNotFound (not Ok(false)) so the UI can render "unknown".
    #[tokio::test]
    async fn try_is_parked_errors_when_undefined() {
        let client = Arc::new(RwLock::new(IndiClient::new("localhost", Some(7624))));
        let mount = IndiMount::new(client, "TestMount");
        let result = mount.try_is_parked().await;
        assert!(matches!(result, Err(IndiError::PropertyNotFound { .. })));
    }

    /// §5.15: same contract for try_is_tracking.
    #[tokio::test]
    async fn try_is_tracking_errors_when_undefined() {
        let client = Arc::new(RwLock::new(IndiClient::new("localhost", Some(7624))));
        let mount = IndiMount::new(client, "TestMount");
        let result = mount.try_is_tracking().await;
        assert!(matches!(result, Err(IndiError::PropertyNotFound { .. })));
    }

    /// §5.15: same contract for try_is_slewing.
    #[tokio::test]
    async fn try_is_slewing_errors_when_undefined() {
        let client = Arc::new(RwLock::new(IndiClient::new("localhost", Some(7624))));
        let mount = IndiMount::new(client, "TestMount");
        let result = mount.try_is_slewing().await;
        assert!(matches!(result, Err(IndiError::PropertyNotFound { .. })));
    }
}
