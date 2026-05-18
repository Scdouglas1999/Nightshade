//! Device Operations Trait
//!
//! This module defines the interface for device operations that the sequencer needs.
//! The actual implementation is provided by the bridge crate.

use async_trait::async_trait;
use std::sync::Arc;

/// Result type for device operations
pub type DeviceResult<T> = Result<T, String>;

/// Image data returned from camera
#[derive(Debug, Clone)]
pub struct ImageData {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u16>,
    pub bits_per_pixel: u32,
    pub exposure_secs: f64,
    pub gain: Option<i32>,
    pub offset: Option<i32>,
    pub temperature: Option<f64>,
    pub filter: Option<String>,
    pub timestamp: i64,
    /// Sensor type: "Monochrome" or "Color"
    pub sensor_type: Option<String>,
    /// Bayer pattern offset (X, Y) - determines actual pattern based on offsets
    pub bayer_offset: Option<(i32, i32)>,
}

/// Plate solve result
#[derive(Debug, Clone)]
pub struct PlateSolveResult {
    pub ra_degrees: f64,
    pub dec_degrees: f64,
    pub pixel_scale: f64,
    pub rotation: f64,
    pub success: bool,
}

/// Guiding status
#[derive(Debug, Clone)]
pub struct GuidingStatus {
    pub is_guiding: bool,
    pub rms_ra: f64,
    pub rms_dec: f64,
    pub rms_total: f64,
}

/// Trait defining all device operations needed by the sequencer
///
/// This trait is implemented by the bridge to provide actual device control.
/// The sequencer calls these methods without knowing the implementation details.
#[async_trait]
pub trait DeviceOps: Send + Sync {
    // =========================================================================
    // MOUNT OPERATIONS
    // =========================================================================

    /// Slew mount to coordinates (RA in hours, Dec in degrees)
    async fn mount_slew_to_coordinates(
        &self,
        mount_id: &str,
        ra_hours: f64,
        dec_degrees: f64,
    ) -> DeviceResult<()>;

    /// Abort mount slew
    async fn mount_abort_slew(&self, mount_id: &str) -> DeviceResult<()>;

    /// Get current mount coordinates (returns RA hours, Dec degrees)
    async fn mount_get_coordinates(&self, mount_id: &str) -> DeviceResult<(f64, f64)>;

    /// Sync mount to coordinates
    async fn mount_sync(&self, mount_id: &str, ra_hours: f64, dec_degrees: f64)
        -> DeviceResult<()>;

    /// Park the mount
    async fn mount_park(&self, mount_id: &str) -> DeviceResult<()>;

    /// Unpark the mount
    async fn mount_unpark(&self, mount_id: &str) -> DeviceResult<()>;

    /// Check if mount is slewing
    async fn mount_is_slewing(&self, mount_id: &str) -> DeviceResult<bool>;

    /// Check if mount is parked
    async fn mount_is_parked(&self, mount_id: &str) -> DeviceResult<bool>;

    /// Check if mount can perform a meridian flip
    /// Returns true if mount supports flipping, false otherwise
    async fn mount_can_flip(&self, mount_id: &str) -> DeviceResult<bool>;

    /// Get the side of the pier the mount is currently on
    async fn mount_side_of_pier(&self, mount_id: &str) -> DeviceResult<crate::meridian::PierSide>;

    /// Get tracking status
    async fn mount_is_tracking(&self, mount_id: &str) -> DeviceResult<bool>;

    /// Set tracking on/off
    async fn mount_set_tracking(&self, mount_id: &str, enabled: bool) -> DeviceResult<()>;

    // =========================================================================
    // CAMERA OPERATIONS
    // =========================================================================

    /// Start an exposure and return the image data
    async fn camera_start_exposure(
        &self,
        camera_id: &str,
        duration_secs: f64,
        gain: Option<i32>,
        offset: Option<i32>,
        bin_x: i32,
        bin_y: i32,
    ) -> DeviceResult<ImageData>;

    /// Abort current exposure
    async fn camera_abort_exposure(&self, camera_id: &str) -> DeviceResult<()>;

    /// Set cooler state and target temperature
    async fn camera_set_cooler(
        &self,
        camera_id: &str,
        enabled: bool,
        target_temp: f64,
    ) -> DeviceResult<()>;

    /// Get current sensor temperature
    async fn camera_get_temperature(&self, camera_id: &str) -> DeviceResult<f64>;

    /// Get cooler power percentage
    async fn camera_get_cooler_power(&self, camera_id: &str) -> DeviceResult<f64>;

    // =========================================================================
    // FOCUSER OPERATIONS
    // =========================================================================

    /// Move focuser to absolute position
    async fn focuser_move_to(&self, focuser_id: &str, position: i32) -> DeviceResult<()>;

    /// Get current focuser position
    async fn focuser_get_position(&self, focuser_id: &str) -> DeviceResult<i32>;

    /// Check if focuser is moving
    async fn focuser_is_moving(&self, focuser_id: &str) -> DeviceResult<bool>;

    /// Get focuser temperature (if available)
    async fn focuser_get_temperature(&self, focuser_id: &str) -> DeviceResult<Option<f64>>;

    /// Halt focuser movement
    async fn focuser_halt(&self, focuser_id: &str) -> DeviceResult<()>;

    // =========================================================================
    // FILTER WHEEL OPERATIONS
    // =========================================================================

    /// Set filter wheel position by index (1-based)
    async fn filterwheel_set_position(&self, fw_id: &str, position: i32) -> DeviceResult<()>;

    /// Get current filter wheel position
    async fn filterwheel_get_position(&self, fw_id: &str) -> DeviceResult<i32>;

    /// Get filter names
    async fn filterwheel_get_names(&self, fw_id: &str) -> DeviceResult<Vec<String>>;

    /// Set filter by name (returns position used)
    async fn filterwheel_set_filter_by_name(&self, fw_id: &str, name: &str) -> DeviceResult<i32>;

    // =========================================================================
    // ROTATOR OPERATIONS
    // =========================================================================

    /// Move rotator to angle (degrees)
    async fn rotator_move_to(&self, rotator_id: &str, angle: f64) -> DeviceResult<()>;

    /// Move rotator by relative amount
    async fn rotator_move_relative(&self, rotator_id: &str, delta: f64) -> DeviceResult<()>;

    /// Get current rotator angle
    async fn rotator_get_angle(&self, rotator_id: &str) -> DeviceResult<f64>;

    /// Halt rotator movement
    async fn rotator_halt(&self, rotator_id: &str) -> DeviceResult<()>;

    // =========================================================================
    // GUIDING / PHD2 OPERATIONS
    // =========================================================================

    /// Start dithering
    async fn guider_dither(
        &self,
        pixels: f64,
        settle_pixels: f64,
        settle_time: f64,
        settle_timeout: f64,
        ra_only: bool,
    ) -> DeviceResult<()>;

    /// Get guiding status
    async fn guider_get_status(&self) -> DeviceResult<GuidingStatus>;

    /// Start guiding
    async fn guider_start(
        &self,
        settle_pixels: f64,
        settle_time: f64,
        settle_timeout: f64,
    ) -> DeviceResult<()>;

    /// Stop guiding
    async fn guider_stop(&self) -> DeviceResult<()>;

    // =========================================================================
    // PLATE SOLVING
    // =========================================================================

    /// Plate solve an image
    async fn plate_solve(
        &self,
        image_data: &ImageData,
        hint_ra: Option<f64>,
        hint_dec: Option<f64>,
        hint_scale: Option<f64>,
    ) -> DeviceResult<PlateSolveResult>;

    // =========================================================================
    // IMAGE SAVING
    // =========================================================================

    /// Save image as FITS file
    async fn save_fits(
        &self,
        image_data: &ImageData,
        file_path: &str,
        target_name: Option<&str>,
        filter: Option<&str>,
        ra_hours: Option<f64>,
        dec_degrees: Option<f64>,
    ) -> DeviceResult<()>;

    // =========================================================================
    // NOTIFICATIONS
    // =========================================================================

    /// Send a notification
    async fn send_notification(&self, level: &str, title: &str, message: &str) -> DeviceResult<()>;

    // =========================================================================
    // UTILITY
    // =========================================================================

    /// Calculate current altitude of a target (returns degrees)
    fn calculate_altitude(&self, ra_hours: f64, dec_degrees: f64, lat: f64, lon: f64) -> f64;

    /// Get observer location
    fn get_observer_location(&self) -> Option<(f64, f64)>;

    // =========================================================================
    // POLAR ALIGNMENT
    // =========================================================================

    /// Send polar alignment update
    async fn polar_align_update(
        &self,
        result: &crate::polar_align::PolarAlignResult,
    ) -> DeviceResult<()>;

    // =========================================================================
    // DOME OPERATIONS
    // =========================================================================

    /// Open dome shutter
    async fn dome_open(&self, dome_id: &str) -> DeviceResult<()>;

    /// Close dome shutter
    async fn dome_close(&self, dome_id: &str) -> DeviceResult<()>;

    /// Park dome
    async fn dome_park(&self, dome_id: &str) -> DeviceResult<()>;

    /// Get dome status (shutter status)
    async fn dome_get_shutter_status(&self, dome_id: &str) -> DeviceResult<String>;

    // =========================================================================
    // SAFETY MONITOR / WEATHER OPERATIONS
    // =========================================================================

    /// Check if conditions are safe for observing
    /// Returns true if safe, false if unsafe.
    /// Returns Err when safety status cannot be determined (missing device, driver error, etc.).
    async fn safety_is_safe(&self, safety_id: Option<&str>) -> DeviceResult<bool>;

    /// Read humidity percentage (0-100) from the weather/observatory device.
    ///
    /// Returns `Ok(Some(value))` when the device reports humidity, `Ok(None)`
    /// when humidity is genuinely not supported by the connected weather
    /// device, and `Err(_)` when the query failed (driver error, no device
    /// configured, etc.). The trigger monitor uses this to feed the
    /// `HumidityThreshold` trigger; an `Err` result is logged and the trigger
    /// state is left unchanged so a stale-but-known reading does not get
    /// overwritten by a transient driver hiccup.
    ///
    /// Default implementation returns `Ok(None)` so existing DeviceOps
    /// implementations that do not know about humidity continue to compile.
    /// Real implementations should override this.
    async fn weather_get_humidity(&self, weather_id: Option<&str>) -> DeviceResult<Option<f64>> {
        let _ = weather_id;
        Ok(None)
    }

    // =========================================================================
    // IMAGE ANALYSIS
    // =========================================================================

    /// Calculate median HFR from an image
    async fn calculate_image_hfr(&self, image_data: &ImageData) -> DeviceResult<Option<f64>>;

    /// Detect stars and return their HFRs (returns x, y, hfr tuples)
    async fn detect_stars_in_image(
        &self,
        image_data: &ImageData,
    ) -> DeviceResult<Vec<(f64, f64, f64)>>;

    // =========================================================================
    // COVER CALIBRATOR (FLAT PANEL / DUST COVER) OPERATIONS
    // =========================================================================

    /// Open the cover (unpark dust cap)
    async fn cover_calibrator_open_cover(&self, device_id: &str) -> DeviceResult<()>;

    /// Close the cover (park dust cap)
    async fn cover_calibrator_close_cover(&self, device_id: &str) -> DeviceResult<()>;

    /// Halt cover movement
    async fn cover_calibrator_halt_cover(&self, device_id: &str) -> DeviceResult<()>;

    /// Turn on the calibrator (flat panel light) at specified brightness
    async fn cover_calibrator_calibrator_on(
        &self,
        device_id: &str,
        brightness: i32,
    ) -> DeviceResult<()>;

    /// Turn off the calibrator (flat panel light)
    async fn cover_calibrator_calibrator_off(&self, device_id: &str) -> DeviceResult<()>;

    /// Get current cover state (0=NotPresent, 1=Closed, 2=Moving, 3=Open, 4=Unknown, 5=Error)
    async fn cover_calibrator_get_cover_state(&self, device_id: &str) -> DeviceResult<i32>;

    /// Get current calibrator state (0=NotPresent, 1=Off, 2=NotReady, 3=Ready, 4=Unknown, 5=Error)
    async fn cover_calibrator_get_calibrator_state(&self, device_id: &str) -> DeviceResult<i32>;

    /// Get current brightness level
    async fn cover_calibrator_get_brightness(&self, device_id: &str) -> DeviceResult<i32>;

    /// Get maximum brightness level
    async fn cover_calibrator_get_max_brightness(&self, device_id: &str) -> DeviceResult<i32>;
}

/// Shared device operations handle
pub type SharedDeviceOps = Arc<dyn DeviceOps>;

/// A null implementation for testing without real devices
pub struct NullDeviceOps;

#[async_trait]
impl DeviceOps for NullDeviceOps {
    async fn mount_slew_to_coordinates(
        &self,
        _mount_id: &str,
        ra: f64,
        dec: f64,
    ) -> DeviceResult<()> {
        tracing::info!("[NULL] Slew to RA={:.4}h, Dec={:.4}°", ra, dec);
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        Ok(())
    }

    async fn mount_abort_slew(&self, _mount_id: &str) -> DeviceResult<()> {
        tracing::info!("[NULL] Aborting mount slew");
        Ok(())
    }

    async fn mount_get_coordinates(&self, _mount_id: &str) -> DeviceResult<(f64, f64)> {
        Ok((12.0, 45.0))
    }

    async fn mount_sync(&self, _mount_id: &str, _ra: f64, _dec: f64) -> DeviceResult<()> {
        Ok(())
    }

    async fn mount_park(&self, _mount_id: &str) -> DeviceResult<()> {
        tracing::info!("[NULL] Parking mount");
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        Ok(())
    }

    async fn mount_unpark(&self, _mount_id: &str) -> DeviceResult<()> {
        tracing::info!("[NULL] Unparking mount");
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
        Ok(())
    }

    async fn mount_is_slewing(&self, _mount_id: &str) -> DeviceResult<bool> {
        Ok(false)
    }

    async fn mount_is_parked(&self, _mount_id: &str) -> DeviceResult<bool> {
        Ok(false)
    }

    async fn mount_can_flip(&self, _mount_id: &str) -> DeviceResult<bool> {
        tracing::info!("[NULL] Mount supports flipping");
        Ok(true)
    }

    async fn mount_side_of_pier(&self, _mount_id: &str) -> DeviceResult<crate::meridian::PierSide> {
        Ok(crate::meridian::PierSide::East)
    }

    async fn mount_is_tracking(&self, _mount_id: &str) -> DeviceResult<bool> {
        Ok(true)
    }

    async fn mount_set_tracking(&self, _mount_id: &str, enabled: bool) -> DeviceResult<()> {
        tracing::info!("[NULL] Set tracking: {}", enabled);
        Ok(())
    }

    async fn camera_start_exposure(
        &self,
        _camera_id: &str,
        duration_secs: f64,
        gain: Option<i32>,
        offset: Option<i32>,
        _bin_x: i32,
        _bin_y: i32,
    ) -> DeviceResult<ImageData> {
        tracing::info!("[NULL] Starting {:.1}s exposure", duration_secs);
        tokio::time::sleep(std::time::Duration::from_secs_f64(duration_secs)).await;

        Ok(ImageData {
            width: 4144,
            height: 2822,
            data: vec![0u16; 4144 * 2822],
            bits_per_pixel: 16,
            exposure_secs: duration_secs,
            gain,
            offset,
            temperature: Some(-10.0),
            filter: None,
            timestamp: chrono::Utc::now().timestamp(),
            sensor_type: Some("Monochrome".to_string()), // Default to Mono
            bayer_offset: None,                          // No Bayer pattern for mono
        })
    }

    async fn camera_abort_exposure(&self, _camera_id: &str) -> DeviceResult<()> {
        Ok(())
    }

    async fn camera_set_cooler(
        &self,
        _camera_id: &str,
        enabled: bool,
        target: f64,
    ) -> DeviceResult<()> {
        tracing::info!("[NULL] Cooler: enabled={}, target={}°C", enabled, target);
        Ok(())
    }

    async fn camera_get_temperature(&self, _camera_id: &str) -> DeviceResult<f64> {
        Ok(-10.0)
    }

    async fn camera_get_cooler_power(&self, _camera_id: &str) -> DeviceResult<f64> {
        Ok(50.0)
    }

    async fn focuser_move_to(&self, _focuser_id: &str, position: i32) -> DeviceResult<()> {
        tracing::info!("[NULL] Moving focuser to {}", position);
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
        Ok(())
    }

    async fn focuser_get_position(&self, _focuser_id: &str) -> DeviceResult<i32> {
        Ok(25000)
    }

    async fn focuser_is_moving(&self, _focuser_id: &str) -> DeviceResult<bool> {
        Ok(false)
    }

    async fn focuser_get_temperature(&self, _focuser_id: &str) -> DeviceResult<Option<f64>> {
        Ok(Some(15.0))
    }

    async fn focuser_halt(&self, _focuser_id: &str) -> DeviceResult<()> {
        tracing::info!("[NULL] Halting focuser");
        Ok(())
    }

    async fn filterwheel_set_position(&self, _fw_id: &str, position: i32) -> DeviceResult<()> {
        tracing::info!("[NULL] Setting filter to position {}", position);
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
        Ok(())
    }

    async fn filterwheel_get_position(&self, _fw_id: &str) -> DeviceResult<i32> {
        Ok(1)
    }

    async fn filterwheel_get_names(&self, _fw_id: &str) -> DeviceResult<Vec<String>> {
        Ok(vec![
            "L".into(),
            "R".into(),
            "G".into(),
            "B".into(),
            "Ha".into(),
            "OIII".into(),
            "SII".into(),
        ])
    }

    async fn filterwheel_set_filter_by_name(&self, _fw_id: &str, name: &str) -> DeviceResult<i32> {
        let pos = match name.to_uppercase().as_str() {
            "L" | "LUMINANCE" => 1,
            "R" | "RED" => 2,
            "G" | "GREEN" => 3,
            "B" | "BLUE" => 4,
            "HA" | "H-ALPHA" => 5,
            "OIII" | "O3" => 6,
            "SII" | "S2" => 7,
            _ => 1,
        };
        self.filterwheel_set_position(_fw_id, pos).await?;
        Ok(pos)
    }

    async fn rotator_move_to(&self, _rotator_id: &str, angle: f64) -> DeviceResult<()> {
        tracing::info!("[NULL] Rotating to {}°", angle);
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        Ok(())
    }

    async fn rotator_move_relative(&self, rotator_id: &str, delta: f64) -> DeviceResult<()> {
        let current = self.rotator_get_angle(rotator_id).await?;
        self.rotator_move_to(rotator_id, current + delta).await
    }

    async fn rotator_get_angle(&self, _rotator_id: &str) -> DeviceResult<f64> {
        Ok(0.0)
    }

    async fn rotator_halt(&self, _rotator_id: &str) -> DeviceResult<()> {
        tracing::info!("[NULL] Halting rotator");
        Ok(())
    }

    async fn guider_dither(
        &self,
        pixels: f64,
        settle_pixels: f64,
        settle_time: f64,
        _settle_timeout: f64,
        _ra_only: bool,
    ) -> DeviceResult<()> {
        tracing::info!(
            "[NULL] Dithering {} pixels, settle <{} px in {}s",
            pixels,
            settle_pixels,
            settle_time
        );
        tokio::time::sleep(std::time::Duration::from_secs_f64(settle_time.min(5.0))).await;
        Ok(())
    }

    async fn guider_get_status(&self) -> DeviceResult<GuidingStatus> {
        Ok(GuidingStatus {
            is_guiding: true,
            rms_ra: 0.5,
            rms_dec: 0.4,
            rms_total: 0.64,
        })
    }

    async fn guider_start(
        &self,
        _settle_pixels: f64,
        settle_time: f64,
        _settle_timeout: f64,
    ) -> DeviceResult<()> {
        tracing::info!("[NULL] Starting guiding");
        tokio::time::sleep(std::time::Duration::from_secs_f64(settle_time.min(5.0))).await;
        Ok(())
    }

    async fn guider_stop(&self) -> DeviceResult<()> {
        tracing::info!("[NULL] Stopping guiding");
        Ok(())
    }

    async fn plate_solve(
        &self,
        _image_data: &ImageData,
        hint_ra: Option<f64>,
        hint_dec: Option<f64>,
        _hint_scale: Option<f64>,
    ) -> DeviceResult<PlateSolveResult> {
        tracing::info!("[NULL] Plate solving");
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        let ra_degrees = hint_ra.ok_or_else(|| {
            "NullDeviceOps plate_solve requires hint_ra in simulation mode".to_string()
        })?;
        let dec_degrees = hint_dec.ok_or_else(|| {
            "NullDeviceOps plate_solve requires hint_dec in simulation mode".to_string()
        })?;

        Ok(PlateSolveResult {
            ra_degrees,
            dec_degrees,
            pixel_scale: 1.5,
            rotation: 0.0,
            success: true,
        })
    }

    async fn save_fits(
        &self,
        _image_data: &ImageData,
        file_path: &str,
        target_name: Option<&str>,
        _filter: Option<&str>,
        _ra: Option<f64>,
        _dec: Option<f64>,
    ) -> DeviceResult<()> {
        tracing::info!(
            "[NULL] Saving FITS to {} (target: {:?})",
            file_path,
            target_name
        );
        Ok(())
    }

    async fn send_notification(&self, level: &str, title: &str, message: &str) -> DeviceResult<()> {
        tracing::info!("[NOTIFICATION][{}] {}: {}", level, title, message);
        Ok(())
    }

    fn calculate_altitude(&self, ra_hours: f64, dec_degrees: f64, lat: f64, lon: f64) -> f64 {
        let now = chrono::Utc::now();
        let jd = crate::node::julian_day(&now);
        let lst_hours = crate::node::local_sidereal_time(jd, lon);

        let mut ha_hours = lst_hours - ra_hours;
        while ha_hours > 12.0 {
            ha_hours -= 24.0;
        }
        while ha_hours < -12.0 {
            ha_hours += 24.0;
        }

        let ha_rad = (ha_hours * 15.0).to_radians();
        let dec_rad = dec_degrees.to_radians();
        let lat_rad = lat.to_radians();

        let sin_alt = lat_rad.sin() * dec_rad.sin() + lat_rad.cos() * dec_rad.cos() * ha_rad.cos();
        sin_alt.clamp(-1.0, 1.0).asin().to_degrees()
    }

    fn get_observer_location(&self) -> Option<(f64, f64)> {
        None
    }

    async fn polar_align_update(
        &self,
        result: &crate::polar_align::PolarAlignResult,
    ) -> DeviceResult<()> {
        tracing::info!("[NULL] Polar Align Update: {:?}", result);
        Ok(())
    }

    async fn dome_open(&self, _dome_id: &str) -> DeviceResult<()> {
        tracing::info!("[NULL] Opening dome shutter");
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        Ok(())
    }

    async fn dome_close(&self, _dome_id: &str) -> DeviceResult<()> {
        tracing::info!("[NULL] Closing dome shutter");
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        Ok(())
    }

    async fn dome_park(&self, _dome_id: &str) -> DeviceResult<()> {
        tracing::info!("[NULL] Parking dome");
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        Ok(())
    }

    async fn dome_get_shutter_status(&self, _dome_id: &str) -> DeviceResult<String> {
        Ok("Open".to_string())
    }

    async fn safety_is_safe(&self, _safety_id: Option<&str>) -> DeviceResult<bool> {
        // Tests using NullDeviceOps need WeatherUnsafe to never fire; returning
        // true unconditionally is the simplest contract for that.
        tracing::info!("[NULL] Safety check: safe");
        Ok(true)
    }

    async fn calculate_image_hfr(&self, _image_data: &ImageData) -> DeviceResult<Option<f64>> {
        // Stub returns a plausible random HFR (1.5–3.0 px) so autofocus tests
        // get a varying curve to fit, exercising the V-curve solver without
        // requiring a real star detector.
        use rand::Rng;
        let mut rng = rand::thread_rng();
        let hfr = rng.gen_range(1.5..3.0);
        tracing::debug!("[NULL] Calculated HFR: {:.2}", hfr);
        Ok(Some(hfr))
    }

    async fn detect_stars_in_image(
        &self,
        _image_data: &ImageData,
    ) -> DeviceResult<Vec<(f64, f64, f64)>> {
        // Synthesize a randomized star field so MIN_STAR_COUNT-style validation
        // in tests sees a non-trivial detector output.
        use rand::Rng;
        let mut rng = rand::thread_rng();
        let num_stars = rng.gen_range(10..50);
        let stars: Vec<(f64, f64, f64)> = (0..num_stars)
            .map(|_| {
                let x = rng.gen_range(100.0..4000.0);
                let y = rng.gen_range(100.0..2700.0);
                let hfr = rng.gen_range(1.5..3.0);
                (x, y, hfr)
            })
            .collect();
        tracing::debug!("[NULL] Detected {} stars", stars.len());
        Ok(stars)
    }

    async fn cover_calibrator_open_cover(&self, _device_id: &str) -> DeviceResult<()> {
        tracing::info!("[NULL] Opening cover");
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        Ok(())
    }

    async fn cover_calibrator_close_cover(&self, _device_id: &str) -> DeviceResult<()> {
        tracing::info!("[NULL] Closing cover");
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        Ok(())
    }

    async fn cover_calibrator_halt_cover(&self, _device_id: &str) -> DeviceResult<()> {
        tracing::info!("[NULL] Halting cover");
        Ok(())
    }

    async fn cover_calibrator_calibrator_on(
        &self,
        _device_id: &str,
        brightness: i32,
    ) -> DeviceResult<()> {
        tracing::info!("[NULL] Turning calibrator on at brightness {}", brightness);
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        Ok(())
    }

    async fn cover_calibrator_calibrator_off(&self, _device_id: &str) -> DeviceResult<()> {
        tracing::info!("[NULL] Turning calibrator off");
        Ok(())
    }

    async fn cover_calibrator_get_cover_state(&self, _device_id: &str) -> DeviceResult<i32> {
        // ASCOM CoverState::Open == 3; the pre-flip cover check (§1.19) treats
        // anything ≠ Closed as "ok to slew", so Open is the safe stub default.
        Ok(3)
    }

    async fn cover_calibrator_get_calibrator_state(&self, _device_id: &str) -> DeviceResult<i32> {
        // ASCOM CalibratorState::Ready == 3 — the "no-wait" state, so the flat
        // wizard does not loop waiting for the panel to warm up in tests.
        Ok(3)
    }

    async fn cover_calibrator_get_brightness(&self, _device_id: &str) -> DeviceResult<i32> {
        Ok(128)
    }

    async fn cover_calibrator_get_max_brightness(&self, _device_id: &str) -> DeviceResult<i32> {
        Ok(255)
    }
}

/// Result of a park-with-retry attempt.
///
/// `attempts_made` counts the total invocations of `mount_park` (the initial
/// attempt plus retries), so callers can include the count in failure messages
/// surfaced to the operator.
#[derive(Debug, Clone)]
pub struct ParkRetryResult {
    /// Whether the mount was successfully parked.
    pub success: bool,
    /// Total number of park-call attempts made (initial + retries).
    pub attempts_made: u32,
    /// Last error reported by `mount_park`, present iff `success == false`.
    pub last_error: Option<String>,
}

/// Try to park the mount, retrying with a fixed delay between attempts.
///
/// Audit (trust-patch §8): the two pre-existing call sites (executor's
/// `RecoveryAction::ParkAndAbort` and `Recovery::ParkAndAbort` in `node.rs`)
/// previously diverged — one did a single retry with a hardcoded 2s wait, the
/// other called park exactly once and ignored the result. This helper is the
/// single source of truth so both paths report park-failure specifically in
/// their failure events.
///
/// # Arguments
/// * `device_ops` - Shared device operations handle.
/// * `mount_id` - The mount device ID.
/// * `max_retries` - How many additional attempts to make after the initial
///   call. `0` means try once with no retries; the total number of park calls
///   is `1 + max_retries`.
/// * `retry_delay_secs` - Seconds to sleep between attempts. Always uses
///   `tokio::time::sleep` so the caller's runtime cancellation still works.
pub async fn try_park_with_retry(
    device_ops: &SharedDeviceOps,
    mount_id: &str,
    max_retries: u32,
    retry_delay_secs: f64,
) -> ParkRetryResult {
    let total_attempts = max_retries.saturating_add(1);
    let mut last_error: Option<String> = None;

    for attempt in 1..=total_attempts {
        match device_ops.mount_park(mount_id).await {
            Ok(()) => {
                if attempt == 1 {
                    tracing::info!("mount_park({}) succeeded on initial attempt", mount_id);
                } else {
                    tracing::info!(
                        "mount_park({}) succeeded on attempt {}/{}",
                        mount_id,
                        attempt,
                        total_attempts
                    );
                }
                return ParkRetryResult {
                    success: true,
                    attempts_made: attempt,
                    last_error: None,
                };
            }
            Err(e) => {
                tracing::error!(
                    "mount_park({}) FAILED on attempt {}/{}: {}",
                    mount_id,
                    attempt,
                    total_attempts,
                    e
                );
                last_error = Some(e);
                if attempt < total_attempts && retry_delay_secs > 0.0 {
                    tokio::time::sleep(std::time::Duration::from_secs_f64(retry_delay_secs.max(0.0)))
                        .await;
                }
            }
        }
    }

    tracing::error!(
        "mount_park({}) exhausted {} attempt(s); last error: {:?}. \
         Mount may be in an unsafe position!",
        mount_id,
        total_attempts,
        last_error
    );
    ParkRetryResult {
        success: false,
        attempts_made: total_attempts,
        last_error,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::sync::Arc as StdArc;

    /// A DeviceOps wrapper that fails `mount_park` a configurable number of
    /// times before succeeding. Used by the retry-helper tests.
    struct FlakyParkOps {
        inner: StdArc<NullDeviceOps>,
        fail_count: AtomicU32,
        attempts: AtomicU32,
        fail_forever: bool,
    }

    impl FlakyParkOps {
        fn new(fail_count: u32, fail_forever: bool) -> Self {
            Self {
                inner: StdArc::new(NullDeviceOps),
                fail_count: AtomicU32::new(fail_count),
                attempts: AtomicU32::new(0),
                fail_forever,
            }
        }

        fn attempts(&self) -> u32 {
            self.attempts.load(Ordering::SeqCst)
        }
    }

    #[async_trait]
    impl DeviceOps for FlakyParkOps {
        // Only mount_park is overridden; every other method delegates to NullDeviceOps.
        async fn mount_park(&self, mount_id: &str) -> DeviceResult<()> {
            self.attempts.fetch_add(1, Ordering::SeqCst);
            if self.fail_forever {
                return Err(format!("simulated park failure for {}", mount_id));
            }
            let remaining = self.fail_count.load(Ordering::SeqCst);
            if remaining > 0 {
                self.fail_count.fetch_sub(1, Ordering::SeqCst);
                return Err(format!(
                    "simulated park failure for {} ({} failures remaining)",
                    mount_id, remaining
                ));
            }
            Ok(())
        }

        // === delegating methods ===
        async fn mount_slew_to_coordinates(
            &self,
            id: &str,
            ra: f64,
            dec: f64,
        ) -> DeviceResult<()> {
            self.inner.mount_slew_to_coordinates(id, ra, dec).await
        }
        async fn mount_abort_slew(&self, id: &str) -> DeviceResult<()> {
            self.inner.mount_abort_slew(id).await
        }
        async fn mount_get_coordinates(&self, id: &str) -> DeviceResult<(f64, f64)> {
            self.inner.mount_get_coordinates(id).await
        }
        async fn mount_sync(&self, id: &str, ra: f64, dec: f64) -> DeviceResult<()> {
            self.inner.mount_sync(id, ra, dec).await
        }
        async fn mount_unpark(&self, id: &str) -> DeviceResult<()> {
            self.inner.mount_unpark(id).await
        }
        async fn mount_is_slewing(&self, id: &str) -> DeviceResult<bool> {
            self.inner.mount_is_slewing(id).await
        }
        async fn mount_is_parked(&self, id: &str) -> DeviceResult<bool> {
            self.inner.mount_is_parked(id).await
        }
        async fn mount_can_flip(&self, id: &str) -> DeviceResult<bool> {
            self.inner.mount_can_flip(id).await
        }
        async fn mount_side_of_pier(
            &self,
            id: &str,
        ) -> DeviceResult<crate::meridian::PierSide> {
            self.inner.mount_side_of_pier(id).await
        }
        async fn mount_is_tracking(&self, id: &str) -> DeviceResult<bool> {
            self.inner.mount_is_tracking(id).await
        }
        async fn mount_set_tracking(&self, id: &str, enabled: bool) -> DeviceResult<()> {
            self.inner.mount_set_tracking(id, enabled).await
        }
        async fn camera_start_exposure(
            &self,
            id: &str,
            d: f64,
            g: Option<i32>,
            o: Option<i32>,
            bx: i32,
            by: i32,
        ) -> DeviceResult<ImageData> {
            self.inner.camera_start_exposure(id, d, g, o, bx, by).await
        }
        async fn camera_abort_exposure(&self, id: &str) -> DeviceResult<()> {
            self.inner.camera_abort_exposure(id).await
        }
        async fn camera_set_cooler(
            &self,
            id: &str,
            e: bool,
            t: f64,
        ) -> DeviceResult<()> {
            self.inner.camera_set_cooler(id, e, t).await
        }
        async fn camera_get_temperature(&self, id: &str) -> DeviceResult<f64> {
            self.inner.camera_get_temperature(id).await
        }
        async fn camera_get_cooler_power(&self, id: &str) -> DeviceResult<f64> {
            self.inner.camera_get_cooler_power(id).await
        }
        async fn focuser_move_to(&self, id: &str, p: i32) -> DeviceResult<()> {
            self.inner.focuser_move_to(id, p).await
        }
        async fn focuser_get_position(&self, id: &str) -> DeviceResult<i32> {
            self.inner.focuser_get_position(id).await
        }
        async fn focuser_is_moving(&self, id: &str) -> DeviceResult<bool> {
            self.inner.focuser_is_moving(id).await
        }
        async fn focuser_get_temperature(&self, id: &str) -> DeviceResult<Option<f64>> {
            self.inner.focuser_get_temperature(id).await
        }
        async fn focuser_halt(&self, id: &str) -> DeviceResult<()> {
            self.inner.focuser_halt(id).await
        }
        async fn filterwheel_set_position(&self, id: &str, p: i32) -> DeviceResult<()> {
            self.inner.filterwheel_set_position(id, p).await
        }
        async fn filterwheel_get_position(&self, id: &str) -> DeviceResult<i32> {
            self.inner.filterwheel_get_position(id).await
        }
        async fn filterwheel_get_names(&self, id: &str) -> DeviceResult<Vec<String>> {
            self.inner.filterwheel_get_names(id).await
        }
        async fn filterwheel_set_filter_by_name(&self, id: &str, n: &str) -> DeviceResult<i32> {
            self.inner.filterwheel_set_filter_by_name(id, n).await
        }
        async fn rotator_move_to(&self, id: &str, a: f64) -> DeviceResult<()> {
            self.inner.rotator_move_to(id, a).await
        }
        async fn rotator_move_relative(&self, id: &str, d: f64) -> DeviceResult<()> {
            self.inner.rotator_move_relative(id, d).await
        }
        async fn rotator_get_angle(&self, id: &str) -> DeviceResult<f64> {
            self.inner.rotator_get_angle(id).await
        }
        async fn rotator_halt(&self, id: &str) -> DeviceResult<()> {
            self.inner.rotator_halt(id).await
        }
        async fn guider_dither(
            &self,
            p: f64,
            sp: f64,
            st: f64,
            sto: f64,
            ra: bool,
        ) -> DeviceResult<()> {
            self.inner.guider_dither(p, sp, st, sto, ra).await
        }
        async fn guider_get_status(&self) -> DeviceResult<GuidingStatus> {
            self.inner.guider_get_status().await
        }
        async fn guider_start(&self, sp: f64, st: f64, sto: f64) -> DeviceResult<()> {
            self.inner.guider_start(sp, st, sto).await
        }
        async fn guider_stop(&self) -> DeviceResult<()> {
            self.inner.guider_stop().await
        }
        async fn plate_solve(
            &self,
            d: &ImageData,
            ra: Option<f64>,
            dec: Option<f64>,
            s: Option<f64>,
        ) -> DeviceResult<PlateSolveResult> {
            self.inner.plate_solve(d, ra, dec, s).await
        }
        async fn save_fits(
            &self,
            d: &ImageData,
            f: &str,
            t: Option<&str>,
            fl: Option<&str>,
            r: Option<f64>,
            de: Option<f64>,
        ) -> DeviceResult<()> {
            self.inner.save_fits(d, f, t, fl, r, de).await
        }
        async fn send_notification(&self, l: &str, t: &str, m: &str) -> DeviceResult<()> {
            self.inner.send_notification(l, t, m).await
        }
        fn calculate_altitude(&self, r: f64, d: f64, la: f64, lo: f64) -> f64 {
            self.inner.calculate_altitude(r, d, la, lo)
        }
        fn get_observer_location(&self) -> Option<(f64, f64)> {
            self.inner.get_observer_location()
        }
        async fn polar_align_update(
            &self,
            r: &crate::polar_align::PolarAlignResult,
        ) -> DeviceResult<()> {
            self.inner.polar_align_update(r).await
        }
        async fn dome_open(&self, id: &str) -> DeviceResult<()> {
            self.inner.dome_open(id).await
        }
        async fn dome_close(&self, id: &str) -> DeviceResult<()> {
            self.inner.dome_close(id).await
        }
        async fn dome_park(&self, id: &str) -> DeviceResult<()> {
            self.inner.dome_park(id).await
        }
        async fn dome_get_shutter_status(&self, id: &str) -> DeviceResult<String> {
            self.inner.dome_get_shutter_status(id).await
        }
        async fn safety_is_safe(&self, id: Option<&str>) -> DeviceResult<bool> {
            self.inner.safety_is_safe(id).await
        }
        async fn calculate_image_hfr(&self, d: &ImageData) -> DeviceResult<Option<f64>> {
            self.inner.calculate_image_hfr(d).await
        }
        async fn detect_stars_in_image(
            &self,
            d: &ImageData,
        ) -> DeviceResult<Vec<(f64, f64, f64)>> {
            self.inner.detect_stars_in_image(d).await
        }
        async fn cover_calibrator_open_cover(&self, id: &str) -> DeviceResult<()> {
            self.inner.cover_calibrator_open_cover(id).await
        }
        async fn cover_calibrator_close_cover(&self, id: &str) -> DeviceResult<()> {
            self.inner.cover_calibrator_close_cover(id).await
        }
        async fn cover_calibrator_halt_cover(&self, id: &str) -> DeviceResult<()> {
            self.inner.cover_calibrator_halt_cover(id).await
        }
        async fn cover_calibrator_calibrator_on(&self, id: &str, b: i32) -> DeviceResult<()> {
            self.inner.cover_calibrator_calibrator_on(id, b).await
        }
        async fn cover_calibrator_calibrator_off(&self, id: &str) -> DeviceResult<()> {
            self.inner.cover_calibrator_calibrator_off(id).await
        }
        async fn cover_calibrator_get_cover_state(&self, id: &str) -> DeviceResult<i32> {
            self.inner.cover_calibrator_get_cover_state(id).await
        }
        async fn cover_calibrator_get_calibrator_state(&self, id: &str) -> DeviceResult<i32> {
            self.inner.cover_calibrator_get_calibrator_state(id).await
        }
        async fn cover_calibrator_get_brightness(&self, id: &str) -> DeviceResult<i32> {
            self.inner.cover_calibrator_get_brightness(id).await
        }
        async fn cover_calibrator_get_max_brightness(&self, id: &str) -> DeviceResult<i32> {
            self.inner.cover_calibrator_get_max_brightness(id).await
        }
    }

    #[tokio::test]
    async fn try_park_with_retry_succeeds_first_attempt() {
        let ops: SharedDeviceOps = Arc::new(FlakyParkOps::new(0, false));
        let result = try_park_with_retry(&ops, "mount-1", 3, 0.0).await;
        assert!(result.success);
        assert_eq!(result.attempts_made, 1);
        assert!(result.last_error.is_none());
    }

    #[tokio::test]
    async fn try_park_with_retry_recovers_after_retries() {
        let ops_concrete = Arc::new(FlakyParkOps::new(2, false));
        let ops: SharedDeviceOps = ops_concrete.clone();
        let result = try_park_with_retry(&ops, "mount-1", 3, 0.0).await;
        assert!(result.success, "should succeed after 2 failures");
        assert_eq!(result.attempts_made, 3);
        assert_eq!(ops_concrete.attempts(), 3);
        assert!(result.last_error.is_none());
    }

    #[tokio::test]
    async fn try_park_with_retry_gives_up_after_exhausting_attempts() {
        let ops_concrete = Arc::new(FlakyParkOps::new(0, true));
        let ops: SharedDeviceOps = ops_concrete.clone();
        let result = try_park_with_retry(&ops, "mount-1", 2, 0.0).await;
        assert!(!result.success);
        // max_retries=2 means total 3 attempts (initial + 2 retries).
        assert_eq!(result.attempts_made, 3);
        assert_eq!(ops_concrete.attempts(), 3);
        assert!(result.last_error.is_some());
    }

    #[tokio::test]
    async fn try_park_with_retry_zero_retries_means_one_attempt() {
        let ops_concrete = Arc::new(FlakyParkOps::new(0, true));
        let ops: SharedDeviceOps = ops_concrete.clone();
        let result = try_park_with_retry(&ops, "mount-1", 0, 0.0).await;
        assert!(!result.success);
        assert_eq!(result.attempts_made, 1);
        assert_eq!(ops_concrete.attempts(), 1);
    }
}
