//! Camera operations dispatcher.
//!
//! Methods in this module are an additional impl block on `DeviceManager`
//! using Rust's split-impl-block feature. Behavior is identical to the
//! previous monolithic `devices.rs`.
//!
//! # `as`-cast policy
//!
//! Numeric casts in this file cluster into:
//! - **INDI wire f64 ↔ device numeric** (lines 118, 121, 125, 127, 937,
//!   1002, 1078, 1081): INDI represents every numeric property as `f64`
//!   over XML; i32/u32/u16 → f64 is exact widening. The reverse direction
//!   `v as i32 / u32` (lines 754, 764, 791, 801, 829, 844, 845) is bounded
//!   by INDI driver-advertised min/max ranges (gain/offset/bin are all
//!   small integers; max_adu fits u32 for any current sensor). Saturation
//!   on out-of-range surfaces as the displayed-zero baseline from the
//!   companion `unwrap_or(0)` policy below.
//! - **Sensor dimensions i32 → u32** (lines 374, 381, 675, 676): ASCOM
//!   CameraXSize/YSize are int (i32) ≥ 1 by spec; the upstream Option
//!   filter strips the None case. Negative would round to giant u32 and
//!   immediately fail buffer-sizing.
//! - **max_adu i32 → u32** (line 679): MaxADU is i32 by ASCOM spec but
//!   physically u32-sized (≤ 4_294_967_295 for 32-bit sensors); positive
//!   i32 narrows-and-widens cleanly to u32.
//! - **Readout mode index i32 → usize** (lines 1180, 1181): preceded by
//!   `mode_index >= 0` check; non-negative i32 → usize is widening on every
//!   supported target.
//!
//! Sites with a local `Why:` comment override the module-level reasoning.
//!
//! # `unwrap_or` policy
//!
//! All `unwrap_or` sites in this module are dimension/state composition
//! steps that flatten `Option<T>` values from optional ASCOM probes into
//! a flat `CameraInfo`/`CameraStatus`. Defaults:
//!
//! * sensor dimensions (`sensor_width`, `sensor_height`) → 0 when the
//!   ASCOM driver did not provide a value; the UI distinguishes "no
//!   sensor info" from "1×1 sensor" by checking the `can_*` booleans.
//! * `pixel_size_x/y` → 0.0 → "unknown" in UI scale bars.
//! * `max_adu` → `65535` — the 16-bit max representable in standard ASCOM
//!   camera readouts; safe default for histogram scaling.
//! * boolean caps (`can_cool`, `cooler_on`) → `false` — feature-not-declared.
//! * `gain`/`offset` → 0 — bottom of the legal ASCOM gain table; user
//!   adjusts via the gain UI before exposing.
//! * `target_temp.unwrap_or(-10.0)` (set_cooler) — the historical Nightshade
//!   default target when the caller does not specify; documented in the
//!   "Imaging Setup" UI help text.
//!
//! Connection-level errors are not silenced here; this layer composes
//! values *after* `with_camera!` has already established the device path.

use crate::device::*;
use crate::device_manager::DeviceManager;
use crate::dispatch::DeviceOpError;
use nightshade_native::camera::{ExposureParams, ImageData};
#[cfg(windows)]
use nightshade_native::traits::NativeCamera;
use std::sync::Arc;
use tracing::warn;

impl DeviceManager {
    // =========================================================================
    // Camera Control
    // =========================================================================

    /// Start a camera exposure
    pub async fn camera_start_exposure(
        &self,
        device_id: &str,
        duration: f64,
        // `None` means "leave the camera's current gain/offset unchanged" — the
        // node did not specify one. Previously this took a bare `i32` and the
        // sequencer collapsed `None` to `0`, which both masked the real value
        // and (on drivers that honor it) actively set gain/offset to 0. Keep it
        // optional end-to-end so each driver branch can skip the setter.
        gain: Option<i32>,
        offset: Option<i32>,
        bin_x: i32,
        bin_y: i32,
    ) -> Result<(), DeviceOpError> {
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
                            gain,
                            offset,
                            subframe: None,
                            readout_mode: None,
                        };
                        tracing::info!(
                            "DeviceManager: Calling AscomCameraWrapper.start_exposure()"
                        );
                        let mut camera = camera.write().await;
                        return camera.start_exposure(params).await.map_err(|e| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                    "Failed to start ASCOM camera exposure on {}: {}",
                                    device_id, e
                                ),
                            )
                        });
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("ASCOM camera {} not found", device_id),
                ))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    tracing::info!("DeviceManager: Calling AlpacaCamera.start_exposure()");
                    // Set gain and offset before exposure - propagate errors.
                    // Only when the node specified them (None = leave unchanged).
                    if let Some(g) = gain {
                        camera.set_gain(g).await.map_err(|e| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!("Failed to set Alpaca camera gain: {}", e),
                            )
                        })?;
                    }
                    if let Some(o) = offset {
                        camera.set_offset(o).await.map_err(|e| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!("Failed to set Alpaca camera offset: {}", e),
                            )
                        })?;
                    }
                    // Set binning - propagate errors
                    camera.set_bin_x(bin_x).await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!("Failed to set Alpaca camera bin_x: {}", e),
                        )
                    })?;
                    camera.set_bin_y(bin_y).await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!("Failed to set Alpaca camera bin_y: {}", e),
                        )
                    })?;
                    // Start the exposure
                    return camera
                        .start_exposure(duration, true)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca camera {} not found", device_id),
                ))
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
                        // Set gain/offset if the node specified them (None =
                        // leave unchanged). Some INDI cameras don't support
                        // these, so warn but continue.
                        if let Some(g) = gain {
                            if let Err(e) = locked_client
                                .set_number(&device_name, "CCD_CONTROLS", "Gain", g as f64)
                                .await
                            {
                                tracing::warn!(
                                    "Failed to set INDI camera gain (device may not support it): {}",
                                    e
                                );
                            }
                        }
                        if let Some(o) = offset {
                            if let Err(e) = locked_client
                                .set_number(&device_name, "CCD_CONTROLS", "Offset", o as f64)
                                .await
                            {
                                tracing::warn!(
                                    "Failed to set INDI camera offset (device may not support it): {}",
                                    e
                                );
                            }
                        }
                        // Set binning - propagate errors since binning is typically supported
                        locked_client
                            .set_number(&device_name, "CCD_BINNING", "HOR_BIN", bin_x as f64)
                            .await
                            .map_err(|e| {
                                DeviceOpError::hardware(
                                    Some(device_id.to_string()),
                                    format!("Failed to set INDI camera horizontal binning: {}", e),
                                )
                            })?;
                        locked_client
                            .set_number(&device_name, "CCD_BINNING", "VER_BIN", bin_y as f64)
                            .await
                            .map_err(|e| {
                                DeviceOpError::hardware(
                                    Some(device_id.to_string()),
                                    format!("Failed to set INDI camera vertical binning: {}", e),
                                )
                            })?;
                        // Start exposure
                        return locked_client
                            .set_number(
                                &device_name,
                                "CCD_EXPOSURE",
                                "CCD_EXPOSURE_VALUE",
                                duration,
                            )
                            .await
                            .map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("INDI camera {} not found", device_id),
                ))
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    tracing::info!("DeviceManager: Starting Native SDK exposure");
                    let params = ExposureParams {
                        duration_secs: duration,
                        bin_x,
                        bin_y,
                        gain,
                        offset,
                        subframe: None,
                        readout_mode: None,
                    };
                    return camera.start_exposure(params).await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to start native SDK camera exposure on {}: {}",
                                device_id, e
                            ),
                        )
                    });
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            Some(DriverType::Simulator) => {
                crate::device_manager::ops::sim_gate::require_camera_connected().await?;
                tracing::info!("camera_start_exposure: Simulator exposure started");
                Ok(())
            }
            None => Err(DeviceOpError::not_connected(
                Some(device_id.to_string()),
                format!("Device {} not found", device_id),
            )),
        }
    }

    /// Check if camera exposure is complete
    pub async fn camera_is_exposure_complete(
        &self,
        device_id: &str,
    ) -> Result<bool, DeviceOpError> {
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
                        return camera
                            .is_exposure_complete()
                            .await
                            .map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("ASCOM camera {} not found", device_id),
                ))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    return camera.image_ready().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca camera {} not found", device_id),
                ))
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
                        if let Some(value) = locked_client
                            .get_number(&device_name, "CCD_EXPOSURE", "CCD_EXPOSURE_VALUE")
                            .await
                        {
                            return Ok(value <= 0.0);
                        }
                        if locked_client
                            .is_property_busy(&device_name, "CCD_EXPOSURE")
                            .await
                        {
                            return Ok(false);
                        }
                        return Err(DeviceOpError::hardware(Some(device_id.to_string()), format!(
                            "INDI camera {} exposure status is unavailable (missing CCD_EXPOSURE_VALUE)",
                            device_name
                        )));
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("INDI camera {} not found", device_id),
                ))
            }
            Some(DriverType::Simulator) => {
                // The singleton does not literally track exposure progress
                // (SimulatedCamera::status has no `exposure_complete` field).
                // SimulatedCamera::default sets `state: CameraState::Idle` and
                // the start_exposure simulator path does not flip it, so the
                // historically correct answer for "is the (instant) simulator
                // exposure done?" is `true` whenever the singleton is
                // connected. Refuse the call if not connected so callers can
                // distinguish "nothing to expose" from "no camera attached".
                crate::device_manager::ops::sim_gate::require_camera_connected().await?;
                Ok(true)
            }
            Some(DriverType::Native) => {
                let native_cameras = self.native_cameras.read().await;
                if let Some(camera) = native_cameras.get(device_id) {
                    return camera
                        .is_exposure_complete()
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            None => Err(DeviceOpError::not_connected(
                Some(device_id.to_string()),
                format!("Camera {} not found", device_id),
            )),
        }
    }

    /// Download image from camera
    pub async fn camera_download_image(&self, device_id: &str) -> Result<ImageData, DeviceOpError> {
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
                        return camera.download_image().await.map_err(|e| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                    "Failed to download image from ASCOM camera {}: {}",
                                    device_id, e
                                ),
                            )
                        });
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("ASCOM camera {} not found", device_id),
                ))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    // Use the new download_image_data method
                    let (width, height, pixels) =
                        camera.download_image_data().await.map_err(|e| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                    "Failed to download image from Alpaca camera {}: {}",
                                    device_id, e
                                ),
                            )
                        })?;

                    // Get camera metadata
                    let gain = match camera.gain().await {
                        Ok(g) => g,
                        Err(e) => {
                            warn!(
                                "Failed to read camera gain for {}: {}. Using default 0.",
                                device_id, e
                            );
                            0
                        }
                    };
                    let offset = match camera.offset().await {
                        Ok(o) => o,
                        Err(e) => {
                            warn!(
                                "Failed to read camera offset for {}: {}. Using default 0.",
                                device_id, e
                            );
                            0
                        }
                    };
                    let bin_x = match camera.bin_x().await {
                        Ok(b) => b,
                        Err(e) => {
                            warn!(
                                "Failed to read camera bin_x for {}: {}. Using default 1.",
                                device_id, e
                            );
                            1
                        }
                    };
                    let bin_y = match camera.bin_y().await {
                        Ok(b) => b,
                        Err(e) => {
                            warn!(
                                "Failed to read camera bin_y for {}: {}. Using default 1.",
                                device_id, e
                            );
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
                                warn!(
                                    "Failed to read bayer_offset_x for {}: {}. Using default 0.",
                                    device_id, e
                                );
                                0
                            }
                        };
                        let offset_y = match camera.bayer_offset_y().await {
                            Ok(y) => y,
                            Err(e) => {
                                warn!(
                                    "Failed to read bayer_offset_y for {}: {}. Using default 0.",
                                    device_id, e
                                );
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca camera {} not found", device_id),
                ))
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
                        let camera =
                            nightshade_indi::IndiCamera::new(Arc::clone(client), &device_name);

                        // Enable BLOB transfer if not already enabled
                        let _ = camera.enable_blob().await;

                        // Get image metadata
                        let width = match camera.get_sensor_width().await {
                            Some(w) => w as u32,
                            None => {
                                warn!(
                                    "Failed to read INDI sensor width for {}. Using default 1920.",
                                    device_id
                                );
                                1920
                            }
                        };
                        let height = match camera.get_sensor_height().await {
                            Some(h) => h as u32,
                            None => {
                                warn!(
                                    "Failed to read INDI sensor height for {}. Using default 1080.",
                                    device_id
                                );
                                1080
                            }
                        };
                        let (bin_x, bin_y) = match camera
                            .get_binning_or_default(std::time::Duration::from_millis(0))
                            .await
                        {
                            Ok(b) => b,
                            Err(e) => {
                                warn!(
                                    "Failed to read INDI binning for {}: {}. Using default (1, 1).",
                                    device_id, e
                                );
                                (1, 1)
                            }
                        };
                        let temp = camera.get_temperature().await.ok();
                        let gain = match camera.get_gain().await {
                            Ok(g) => g,
                            Err(e) => {
                                warn!(
                                    "Failed to read INDI gain for {}: {}. Using default 0.",
                                    device_id, e
                                );
                                0
                            }
                        };
                        let offset = match camera.get_offset().await {
                            Ok(o) => o,
                            Err(e) => {
                                warn!(
                                    "Failed to read INDI offset for {}: {}. Using default 0.",
                                    device_id, e
                                );
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
                                return Err(DeviceOpError::hardware(
                                    Some(device_id.to_string()),
                                    "Timeout waiting for INDI image BLOB",
                                ));
                            }

                            match tokio::time::timeout(std::time::Duration::from_secs(1), rx.recv())
                                .await
                            {
                                Ok(Ok(event)) => {
                                    match event {
                                        nightshade_indi::IndiEvent::BlobReceived {
                                            device,
                                            element,
                                            data,
                                            ..
                                        } if device == device_name
                                            && (element == "CCD1" || element == "CCD2") =>
                                        {
                                            {
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
                                                            offset =
                                                                ((offset + 2879) / 2880) * 2880;
                                                            break;
                                                        }
                                                    }

                                                    // Extract binary data as u16
                                                    let binary_data = &data[offset..];
                                                    let mut pixels: Vec<u16> =
                                                        Vec::with_capacity(binary_data.len() / 2);
                                                    for chunk in binary_data.chunks_exact(2) {
                                                        let value = u16::from_be_bytes([
                                                            chunk[0], chunk[1],
                                                        ]);
                                                        pixels.push(value);
                                                    }
                                                    pixels
                                                } else {
                                                    // Not a FITS file, try to parse as raw u16 data
                                                    let mut pixels: Vec<u16> =
                                                        Vec::with_capacity(data.len() / 2);
                                                    for chunk in data.chunks_exact(2) {
                                                        let value = u16::from_le_bytes([
                                                            chunk[0], chunk[1],
                                                        ]);
                                                        pixels.push(value);
                                                    }
                                                    pixels
                                                };

                                                // INDI image BLOBs are padded to
                                                // a 2880-byte (FITS) block
                                                // boundary, so the decoded buffer
                                                // can carry trailing padding
                                                // pixels beyond width*height
                                                // (e.g. a 1280x1024 frame arrives
                                                // as 911*2880 = 2623680 bytes =
                                                // 1311840 u16, 1120 px of padding).
                                                // Trim to the exact frame so
                                                // downstream size validation
                                                // (width*height*2) accepts it
                                                // instead of rejecting the whole
                                                // exposure as "truncated or
                                                // corrupted".
                                                let expected_pixels =
                                                    (width as usize) * (height as usize);
                                                let mut image_data = image_data;
                                                if image_data.len() > expected_pixels {
                                                    image_data.truncate(expected_pixels);
                                                }

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
                                        }
                                        _ => {}
                                    }
                                }
                                Ok(Err(_)) => {
                                    return Err(DeviceOpError::hardware(
                                        Some(device_id.to_string()),
                                        "INDI event channel closed",
                                    ));
                                }
                                Err(_) => {
                                    // Timeout on recv, check total timeout and continue
                                    continue;
                                }
                            }
                        }
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("INDI camera {} not found", device_id),
                ))
            }
            Some(DriverType::Simulator) => {
                // Project gain/offset/bin/temperature from the singleton so a
                // simulated download reflects whatever the test or UI
                // configured via set_gain / set_offset / set_binning /
                // set_cooler. Sensor dimensions remain the singleton's defaults
                // (sensor_width=4144, sensor_height=2822); we keep the older
                // 1920x1080 image-size for the synthetic pixel buffer because
                // the singleton does not declare an "exposure region" and
                // tests rely on a deterministic image size.
                let sim = crate::device_manager::ops::sim_gate::read_camera_status().await?;
                // Synthesize a deterministic, non-uniform frame (faint gradient
                // background + a handful of bright "stars") rather than an
                // all-zero buffer. An all-zero frame is correctly rejected by
                // [IMAGE_VALIDATION] as a dead/black frame, which made the
                // simulator camera unusable for an end-to-end sequencer run
                // (every captured frame failed and the sequence aborted). Real
                // hardware reads real pixels here and is unaffected; this only
                // changes the simulator's synthetic download.
                const SIM_W: usize = 1920;
                const SIM_H: usize = 1080;
                let mut sim_data = vec![0u16; SIM_W * SIM_H];
                for y in 0..SIM_H {
                    let row = y * SIM_W;
                    for x in 0..SIM_W {
                        // Faint gradient (~200..600 ADU) — deterministic and
                        // never uniform, so it passes the all-identical check.
                        sim_data[row + x] = 200 + (((x + y) % 400) as u16);
                    }
                }
                for &(sx, sy) in &[(480, 270), (960, 540), (1440, 810), (300, 850)] {
                    for dy in 0..6usize {
                        for dx in 0..6usize {
                            let px = sx + dx;
                            let py = sy + dy;
                            if px < SIM_W && py < SIM_H {
                                sim_data[py * SIM_W + px] = 50_000;
                            }
                        }
                    }
                }
                Ok(ImageData {
                    width: 1920,
                    height: 1080,
                    data: sim_data,
                    bits_per_pixel: 16,
                    bayer_pattern: None,
                    metadata: nightshade_native::camera::ImageMetadata {
                        exposure_time: 1.0,
                        gain: sim.gain,
                        offset: sim.offset,
                        bin_x: sim.bin_x,
                        bin_y: sim.bin_y,
                        temperature: sim.sensor_temp,
                        timestamp: chrono::Utc::now(),
                        subframe: None,
                        readout_mode: None,
                        vendor_data: nightshade_native::camera::VendorFeatures::default(),
                    },
                })
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera.download_image().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            None => Err(DeviceOpError::not_connected(
                Some(device_id.to_string()),
                format!("Camera {} not found", device_id),
            )),
        }
    }

    /// Abort a camera exposure
    pub async fn camera_abort_exposure(&self, device_id: &str) -> Result<(), DeviceOpError> {
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
                        return camera.abort_exposure().await.map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("ASCOM camera {} not found", device_id),
                ))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    return camera.abort_exposure().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca camera {} not found", device_id),
                ))
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
                        return locked_client
                            .set_switch(&device_name, "CCD_ABORT_EXPOSURE", "ABORT", true)
                            .await
                            .map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("INDI camera {} not found", device_id),
                ))
            }
            Some(DriverType::Simulator) => {
                crate::device_manager::ops::sim_gate::require_camera_connected()
                    .await
                    .map_err(DeviceOpError::driver)
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera.abort_exposure().await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            None => Err(DeviceOpError::not_connected(
                Some(device_id.to_string()),
                format!("Camera {} not found", device_id),
            )),
        }
    }

    /// Get camera status
    pub async fn camera_get_status(
        &self,
        device_id: &str,
    ) -> Result<crate::device::CameraStatus, DeviceOpError> {
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
                        let native_status = camera_guard
                            .get_status()
                            .await
                            .map_err(DeviceOpError::driver)?;
                        let ascom_caps = camera_guard.get_capabilities().await.ok();

                        return Ok(crate::device::CameraStatus {
                            connected: true,
                            state: match native_status.state {
                                nightshade_native::camera::CameraState::Idle => {
                                    crate::device::CameraState::Idle
                                }
                                nightshade_native::camera::CameraState::Waiting => {
                                    crate::device::CameraState::Waiting
                                }
                                nightshade_native::camera::CameraState::Exposing => {
                                    crate::device::CameraState::Exposing
                                }
                                nightshade_native::camera::CameraState::Reading => {
                                    crate::device::CameraState::Reading
                                }
                                nightshade_native::camera::CameraState::Downloading => {
                                    crate::device::CameraState::Download
                                }
                                nightshade_native::camera::CameraState::Error => {
                                    crate::device::CameraState::Error
                                }
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
                            pixel_size_x: ascom_caps
                                .as_ref()
                                .and_then(|c| c.pixel_size_x)
                                .unwrap_or(0.0),
                            pixel_size_y: ascom_caps
                                .as_ref()
                                .and_then(|c| c.pixel_size_y)
                                .unwrap_or(0.0),
                            max_adu: ascom_caps
                                .as_ref()
                                .map(|c| (1u32 << c.bit_depth) - 1)
                                .unwrap_or(65535),
                            can_cool: ascom_caps
                                .as_ref()
                                .map(|c| c.can_set_ccd_temperature)
                                .unwrap_or(false),
                            can_set_gain: true,
                            can_set_offset: true,
                        });
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("ASCOM camera {} not found", device_id),
                ))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    let status = camera.get_status().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to read Alpaca camera status for {}: {}",
                                device_id, e
                            ),
                        )
                    })?;
                    let capabilities = camera.get_capabilities().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to read Alpaca camera capabilities for {}: {}",
                                device_id, e
                            ),
                        )
                    })?;
                    let sensor = camera.get_sensor_info().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to read Alpaca camera sensor info for {}: {}",
                                device_id, e
                            ),
                        )
                    })?;
                    let gain = camera.gain().await.ok();
                    let offset = camera.offset().await.ok();

                    return Ok(crate::device::CameraStatus {
                        connected: true,
                        state: match status.state {
                            nightshade_alpaca::CameraState::Idle => {
                                crate::device::CameraState::Idle
                            }
                            nightshade_alpaca::CameraState::Waiting => {
                                crate::device::CameraState::Waiting
                            }
                            nightshade_alpaca::CameraState::Exposing => {
                                crate::device::CameraState::Exposing
                            }
                            nightshade_alpaca::CameraState::Reading => {
                                crate::device::CameraState::Reading
                            }
                            nightshade_alpaca::CameraState::Download => {
                                crate::device::CameraState::Download
                            }
                            nightshade_alpaca::CameraState::Error => {
                                crate::device::CameraState::Error
                            }
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca camera {} not found", device_id),
                ))
            }
            Some(DriverType::Simulator) => {
                crate::device_manager::ops::sim_gate::read_camera_status()
                    .await
                    .map_err(DeviceOpError::driver)
            }
            Some(DriverType::Native) => {
                let native_cameras = self.native_cameras.read().await;
                if let Some(camera) = native_cameras.get(device_id) {
                    let native_status = camera.get_status().await.map_err(DeviceOpError::driver)?;
                    let capabilities = camera.capabilities();
                    let sensor_info = camera.get_sensor_info();

                    return Ok(crate::device::CameraStatus {
                        connected: camera.is_connected(),
                        state: match native_status.state {
                            nightshade_native::camera::CameraState::Idle => {
                                crate::device::CameraState::Idle
                            }
                            nightshade_native::camera::CameraState::Waiting => {
                                crate::device::CameraState::Waiting
                            }
                            nightshade_native::camera::CameraState::Exposing => {
                                crate::device::CameraState::Exposing
                            }
                            nightshade_native::camera::CameraState::Reading => {
                                crate::device::CameraState::Reading
                            }
                            nightshade_native::camera::CameraState::Downloading => {
                                crate::device::CameraState::Download
                            }
                            nightshade_native::camera::CameraState::Error => {
                                crate::device::CameraState::Error
                            }
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            Some(DriverType::Indi) => {
                // Parse device_id format: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err(DeviceOpError::invalid_device_id(format!(
                        "Invalid INDI device ID format: {}",
                        device_id
                    )));
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
                            DeviceOpError::hardware(Some(device_id.to_string()), format!(
                                "INDI camera {} missing required property CCD_BINNING.HOR_BIN; cannot determine current binning.",
                                device_id
                            ))
                        })?;
                    let bin_y = locked_client
                        .get_number(&device_name, "CCD_BINNING", "VER_BIN")
                        .await
                        .map(|v| v as i32)
                        .ok_or_else(|| {
                            DeviceOpError::hardware(Some(device_id.to_string()), format!(
                                "INDI camera {} missing required property CCD_BINNING.VER_BIN; cannot determine current binning.",
                                device_id
                            ))
                        })?;
                    let exposure_value = locked_client
                        .get_number(&device_name, "CCD_EXPOSURE", "CCD_EXPOSURE_VALUE")
                        .await;

                    // Determine camera state based on exposure value
                    let state = match exposure_value {
                        Some(v) if v > 0.0 => crate::device::CameraState::Exposing,
                        Some(_) => crate::device::CameraState::Idle,
                        None => {
                            return Err(DeviceOpError::hardware(Some(device_id.to_string()), format!(
                                "INDI camera {} missing required property CCD_EXPOSURE.CCD_EXPOSURE_VALUE; cannot determine camera state.",
                                device_id
                            )))
                        }
                    };

                    // Read sensor info from INDI CCD_INFO property.
                    let sensor_width = locked_client
                        .get_number(&device_name, "CCD_INFO", "CCD_MAX_X")
                        .await
                        .map(|v| v as u32)
                        .ok_or_else(|| {
                            DeviceOpError::hardware(Some(device_id.to_string()), format!(
                                "INDI camera {} missing required property CCD_INFO.CCD_MAX_X; cannot determine sensor width.",
                                device_id
                            ))
                        })?;
                    let sensor_height = locked_client
                        .get_number(&device_name, "CCD_INFO", "CCD_MAX_Y")
                        .await
                        .map(|v| v as u32)
                        .ok_or_else(|| {
                            DeviceOpError::hardware(Some(device_id.to_string()), format!(
                                "INDI camera {} missing required property CCD_INFO.CCD_MAX_Y; cannot determine sensor height.",
                                device_id
                            ))
                        })?;
                    let pixel_size_x = locked_client
                        .get_number(&device_name, "CCD_INFO", "CCD_PIXEL_SIZE_X")
                        .await
                        .ok_or_else(|| {
                            DeviceOpError::hardware(Some(device_id.to_string()), format!(
                                "INDI camera {} missing required property CCD_INFO.CCD_PIXEL_SIZE_X; cannot determine pixel size.",
                                device_id
                            ))
                        })?;
                    let pixel_size_y = locked_client
                        .get_number(&device_name, "CCD_INFO", "CCD_PIXEL_SIZE_Y")
                        .await
                        .ok_or_else(|| {
                            DeviceOpError::hardware(Some(device_id.to_string()), format!(
                                "INDI camera {} missing required property CCD_INFO.CCD_PIXEL_SIZE_Y; cannot determine pixel size.",
                                device_id
                            ))
                        })?;
                    let bit_depth = locked_client
                        .get_number(&device_name, "CCD_INFO", "CCD_BITSPERPIXEL")
                        .await
                        .map(|v| v as u32)
                        .ok_or_else(|| {
                            DeviceOpError::hardware(Some(device_id.to_string()), format!(
                                "INDI camera {} missing required property CCD_INFO.CCD_BITSPERPIXEL; cannot determine ADU scaling.",
                                device_id
                            ))
                        })?;
                    if bit_depth == 0 {
                        return Err(DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "INDI camera {} reported invalid CCD_INFO.CCD_BITSPERPIXEL=0.",
                                device_id
                            ),
                        ));
                    }
                    let gain_value = match locked_client
                        .get_number(&device_name, "CCD_GAIN", "GAIN")
                        .await
                    {
                        Some(value) => Some(value),
                        None => {
                            locked_client
                                .get_number(&device_name, "CCD_CONTROLS", "Gain")
                                .await
                        }
                    };
                    let offset_value = locked_client
                        .get_number(&device_name, "CCD_OFFSET", "OFFSET")
                        .await;
                    let gain = gain_value.map(|v| v as i32).unwrap_or(0);
                    let offset = offset_value.map(|v| v as i32).unwrap_or(0);
                    let cooler_power = locked_client
                        .get_number(&device_name, "CCD_COOLER_POWER", "CCD_COOLER_VALUE")
                        .await;
                    let has_gain = gain_value.is_some();
                    let has_offset = offset_value.is_some();
                    let max_adu_from_driver = match locked_client
                        .get_number(&device_name, "CCD_MAX_PIXEL_VALUE", "CCD_MAX_PIXEL_VALUE")
                        .await
                    {
                        Some(value) => Some(value),
                        None => {
                            locked_client
                                .get_number(&device_name, "CCD_INFO", "CCD_MAX_PIXEL")
                                .await
                        }
                    };
                    let max_adu = if let Some(value) = max_adu_from_driver {
                        value.max(0.0) as u32
                    } else if bit_depth >= 32 {
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("INDI client not connected for server {}", server_key),
                ))
            }
            None => Err(DeviceOpError::not_connected(
                Some(device_id.to_string()),
                format!("Camera {} not found or status not supported", device_id),
            )),
        }
    }

    /// Set camera gain
    pub async fn camera_set_gain(&self, device_id: &str, gain: i32) -> Result<(), DeviceOpError> {
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
                        return camera.set_gain(gain).await.map_err(|e| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                    "Failed to set ASCOM camera {} gain to {}: {}",
                                    device_id, gain, e
                                ),
                            )
                        });
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("ASCOM camera {} not found", device_id),
                ))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    return camera.set_gain(gain).await.map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca camera {} not found", device_id),
                ))
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera.set_gain(gain).await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to set native SDK camera {} gain to {}: {}",
                                device_id, gain, e
                            ),
                        )
                    });
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            Some(DriverType::Indi) => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err(DeviceOpError::invalid_device_id(
                        "Invalid INDI device ID format",
                    ));
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    locked
                        .set_number(&device_name, "CCD_CONTROLS", "Gain", gain as f64)
                        .await
                        .map_err(|e| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!("Failed to set INDI camera gain: {}", e),
                            )
                        })?;
                    return Ok(());
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("INDI client not connected for server {}", server_key),
                ))
            }
            Some(DriverType::Simulator) => {
                // Mutate the singleton so a subsequent `camera_get_status` /
                // `camera_download_image` reflects the new gain. A real driver
                // wouldn't silently drop the value; the simulator must not
                // either.
                let cam = crate::api::devices::simulation::get_sim_camera();
                let mut cam = cam.write().await;
                if !cam.status.connected {
                    return Err(DeviceOpError::not_connected(
                        None,
                        crate::device_manager::ops::sim_gate::not_connected_camera(),
                    ));
                }
                cam.status.gain = gain;
                Ok(())
            }
            _ => Err(DeviceOpError::not_connected(
                Some(device_id.to_string()),
                format!("Camera {} not found or not supported", device_id),
            )),
        }
    }

    /// Set camera offset
    pub async fn camera_set_offset(
        &self,
        device_id: &str,
        offset: i32,
    ) -> Result<(), DeviceOpError> {
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
                        return camera
                            .set_offset(offset)
                            .await
                            .map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("ASCOM camera {} not found", device_id),
                ))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    return camera
                        .set_offset(offset)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca camera {} not found", device_id),
                ))
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera
                        .set_offset(offset)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            Some(DriverType::Indi) => {
                // Parse INDI device ID: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err(DeviceOpError::invalid_device_id(
                        "Invalid INDI device ID format",
                    ));
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    locked
                        .set_number(&device_name, "CCD_CONTROLS", "Offset", offset as f64)
                        .await
                        .map_err(|e| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!("Failed to set INDI camera offset: {}", e),
                            )
                        })?;
                    return Ok(());
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("INDI client not connected for server {}", server_key),
                ))
            }
            Some(DriverType::Simulator) => {
                let cam = crate::api::devices::simulation::get_sim_camera();
                let mut cam = cam.write().await;
                if !cam.status.connected {
                    return Err(DeviceOpError::not_connected(
                        None,
                        crate::device_manager::ops::sim_gate::not_connected_camera(),
                    ));
                }
                cam.status.offset = offset;
                Ok(())
            }
            _ => Err(DeviceOpError::not_connected(
                Some(device_id.to_string()),
                format!("Camera {} not found or not supported", device_id),
            )),
        }
    }

    /// Set camera binning
    pub async fn camera_set_binning(
        &self,
        device_id: &str,
        bin_x: i32,
        bin_y: i32,
    ) -> Result<(), DeviceOpError> {
        tracing::info!(
            "DeviceManager: camera_set_binning for {} bin={}x{}",
            device_id,
            bin_x,
            bin_y
        );

        if bin_x < 1 || bin_y < 1 {
            return Err(DeviceOpError::invalid_parameter(format!(
                "Invalid binning values: {}x{} (must be >= 1)",
                bin_x, bin_y
            )));
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
                        return camera
                            .set_binning(bin_x, bin_y)
                            .await
                            .map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("ASCOM camera {} not found", device_id),
                ))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    camera.set_bin_x(bin_x).await?;
                    camera.set_bin_y(bin_y).await?;
                    return Ok(());
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca camera {} not found", device_id),
                ))
            }
            Some(DriverType::Indi) => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err(DeviceOpError::invalid_device_id(format!(
                        "Invalid INDI device ID format: {}",
                        device_id
                    )));
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("INDI client not connected for server {}", server_key),
                ))
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera
                        .set_binning(bin_x, bin_y)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            Some(DriverType::Simulator) => {
                let cam = crate::api::devices::simulation::get_sim_camera();
                let mut cam = cam.write().await;
                if !cam.status.connected {
                    return Err(DeviceOpError::not_connected(
                        None,
                        crate::device_manager::ops::sim_gate::not_connected_camera(),
                    ));
                }
                cam.status.bin_x = bin_x;
                cam.status.bin_y = bin_y;
                Ok(())
            }
            _ => Err(DeviceOpError::not_connected(
                Some(device_id.to_string()),
                format!("Camera {} not found or not supported", device_id),
            )),
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
    ) -> Result<(), DeviceOpError> {
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
                            .map_err(DeviceOpError::driver);
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("ASCOM camera {} not found", device_id),
                ))
            }
            Some(DriverType::Alpaca) => {
                let cameras = self.alpaca_cameras.read().await;
                if let Some(camera) = cameras.get(device_id) {
                    return camera
                        .set_readout_mode(mode_index)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca camera {} not found", device_id),
                ))
            }
            Some(DriverType::Indi) => {
                // INDI uses CCD_READ_MODE switch with indexed elements
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err(DeviceOpError::invalid_device_id(
                        "Invalid INDI device ID format",
                    ));
                }
                let server_key = format!("{}:{}", parts[1], parts[2]);
                let device_name = parts[3..].join(":");

                let clients = self.indi_clients.read().await;
                if let Some(client) = clients.get(&server_key) {
                    let mut locked = client.write().await;
                    // INDI cameras expose readout speed as a switch property.
                    // Common property names: CCD_READ_MODE, CCD_READOUT_SPEED, READOUT_QUALITY
                    let switch_props = ["CCD_READ_MODE", "CCD_READOUT_SPEED", "READOUT_QUALITY"];
                    let all_props = locked.get_properties(&device_name).await;
                    for prop_name in &switch_props {
                        if let Some(prop) = all_props.iter().find(|p| {
                            p.name == *prop_name
                                && p.property_type == nightshade_indi::IndiPropertyType::Switch
                        }) {
                            if (mode_index as usize) < prop.elements.len() {
                                let element = prop.elements[mode_index as usize].clone();
                                locked
                                    .set_switch(&device_name, prop_name, &element, true)
                                    .await
                                    .map_err(|e| {
                                        DeviceOpError::hardware(
                                            Some(device_id.to_string()),
                                            format!("Failed to set INDI readout mode: {}", e),
                                        )
                                    })?;
                                return Ok(());
                            } else {
                                return Err(DeviceOpError::invalid_parameter(format!(
                                    "Readout mode index {} out of range (camera has {} modes)",
                                    mode_index,
                                    prop.elements.len()
                                )));
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("INDI client not connected for server {}", server_key),
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
                    return camera
                        .set_readout_mode(&mode)
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            Some(DriverType::Simulator) => {
                // SimulatedCamera::status has no readout-mode field; refuse
                // the call when disconnected but accept it (no-op) when
                // connected so existing tests that set a readout mode after
                // connect_device still pass.
                crate::device_manager::ops::sim_gate::require_camera_connected().await?;
                tracing::info!(
                    "camera_set_readout_mode: simulator accepted mode_index={} (no-op)",
                    mode_index
                );
                Ok(())
            }
            _ => Err(DeviceOpError::not_connected(
                Some(device_id.to_string()),
                format!("Camera {} not found or not supported", device_id),
            )),
        }
    }

    /// Set camera cooler
    pub async fn camera_set_cooler(
        &self,
        device_id: &str,
        enabled: bool,
        target_temp: Option<f64>,
    ) -> Result<(), DeviceOpError> {
        let result = self
            .camera_set_cooler_dispatch(device_id, enabled, target_temp)
            .await;

        // Record the commanded cooler state so an unplanned reconnect (USB yank
        // mid-run) can re-apply it. The driver comes back from a reconnect with
        // the cooler off and the setpoint cleared; without this the sensor
        // silently warms up while the sequence "resumes". Only record on a
        // successful command — a failed set must not overwrite the last known
        // good desired state.
        if result.is_ok() {
            let mut devices = self.devices.write().await;
            if let Some(dev) = devices.get_mut(device_id) {
                dev.desired_cooler = Some((enabled, target_temp));
            }
        }

        result
    }

    /// Driver dispatch for `camera_set_cooler`. Split out so the public method
    /// can record the desired cooler state (for reconnect re-application)
    /// around the per-driver calls without threading the bookkeeping through
    /// every early-return arm.
    async fn camera_set_cooler_dispatch(
        &self,
        device_id: &str,
        enabled: bool,
        target_temp: Option<f64>,
    ) -> Result<(), DeviceOpError> {
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
                        let target = target_temp.unwrap_or(-10.0);
                        cam.set_cooler(enabled, target).await.map_err(|e| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                "Failed to set ASCOM camera {} cooler (enabled={}, target={}C): {}",
                                device_id, enabled, target, e
                            ),
                            )
                        })?;
                        return Ok(());
                    }
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    "ASCOM camera not connected",
                ))
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
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca camera {} not found", device_id),
                ))
            }
            Some(DriverType::Indi) => {
                // Parse device_id format: indi:host:port:device_name
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err(DeviceOpError::invalid_device_id(format!(
                        "Invalid INDI device ID format: {}",
                        device_id
                    )));
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
                    locked_client
                        .set_switch(&device_name, "CCD_COOLER", switch_element, true)
                        .await?;
                    // Set target temperature if provided
                    if let Some(temp) = target_temp {
                        locked_client
                            .set_number(
                                &device_name,
                                "CCD_TEMPERATURE",
                                "CCD_TEMPERATURE_VALUE",
                                temp,
                            )
                            .await?;
                    }
                    return Ok(());
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("INDI client not connected for server {}", server_key),
                ))
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera
                        .set_cooler(enabled, target_temp.unwrap_or(-10.0))
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            Some(DriverType::Simulator) => {
                let cam = crate::api::devices::simulation::get_sim_camera();
                let mut cam = cam.write().await;
                if !cam.status.connected {
                    return Err(DeviceOpError::not_connected(
                        None,
                        crate::device_manager::ops::sim_gate::not_connected_camera(),
                    ));
                }
                cam.status.cooler_on = enabled;
                if let Some(t) = target_temp {
                    cam.status.target_temp = Some(t);
                }
                Ok(())
            }
            None => Err(DeviceOpError::not_connected(
                Some(device_id.to_string()),
                "Driver type not found",
            )),
        }
    }

    /// Capture a live-view / preview JPEG frame when the connected driver supports it.
    pub async fn camera_capture_preview(&self, device_id: &str) -> Result<Vec<u8>, DeviceOpError> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Native) => {
                let native_cameras = self.native_cameras.read().await;
                if let Some(camera) = native_cameras.get(device_id) {
                    return camera
                        .capture_preview()
                        .await
                        .map_err(DeviceOpError::driver);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            Some(DriverType::Simulator) => Err(DeviceOpError::unsupported(
                crate::device_manager::ops::sim_gate::unsupported_simulator_device(
                    "camera preview",
                ),
            )),
            _ => Err(DeviceOpError::unsupported(format!(
                "Live view preview is not supported for driver {:?} on camera {}",
                driver_type, device_id
            ))),
        }
    }

    /// Query the camera's SDK for manufacturer-recommended gain/offset values.
    ///
    /// Only native vendor SDKs are queried — ASCOM/Alpaca/INDI do not expose
    /// per-camera unity gain through their protocols (ASCOM's
    /// `IntegerListSetting`-style enumeration only lists allowed values, not
    /// which one is "recommended"). For non-native drivers this returns an
    /// empty struct (all fields `None`).
    ///
    /// On native cameras, propagates the per-vendor implementation in
    /// [`nightshade_native::traits::NativeCamera::get_recommended_settings`].
    /// A query failure is logged and reported up — callers must treat it as
    /// "no recommendation" rather than swallowing it.
    pub async fn camera_get_recommended_settings(
        &self,
        device_id: &str,
    ) -> Result<nightshade_native::camera::CameraRecommendedSettings, DeviceOpError> {
        let driver_type = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.driver_type.clone())
        };

        match driver_type {
            Some(DriverType::Native) => {
                let native_cameras = self.native_cameras.read().await;
                if let Some(camera) = native_cameras.get(device_id) {
                    return camera.get_recommended_settings().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!(
                                "Failed to query recommended settings for native camera {}: {}",
                                device_id, e
                            ),
                        )
                    });
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Native SDK camera {} not found", device_id),
                ))
            }
            // ASCOM, Alpaca, INDI, and simulators don't expose a unity-gain
            // recommendation through their protocols. Honest empty answer.
            Some(DriverType::Ascom)
            | Some(DriverType::Alpaca)
            | Some(DriverType::Indi)
            | Some(DriverType::Simulator) => {
                Ok(nightshade_native::camera::CameraRecommendedSettings::default())
            }
            _ => Err(DeviceOpError::not_connected(
                Some(device_id.to_string()),
                format!("Camera {} not found", device_id),
            )),
        }
    }
}
