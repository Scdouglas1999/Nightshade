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
use nightshade_native::camera::{ExposureParams, ImageData, SubFrame};
#[cfg(windows)]
use nightshade_native::traits::NativeCamera;
use std::sync::Arc;
use tracing::warn;

/// Sentinel meaning "this camera setting could not be read".
///
/// `ImageMetadata.gain`/`offset` are plain `i32` (unlike `temperature`, which is
/// already `Option`) and are constructed by every vendor driver, so widening
/// them to `Option` would be a large refactor of code that is not at fault.
/// Real gain/offset values are never negative, so a negative marker is
/// unambiguous, and [`camera_setting_or_unknown`] converts it back to `None` at
/// the one boundary that feeds FITS metadata.
pub(crate) const UNKNOWN_CAMERA_SETTING: i32 = -1;

/// `None` when a camera setting was recorded as unreadable, else `Some(value)`.
///
/// Keeps a failed device read from outranking the operator's configured value in
/// `image_data.gain.or(config.gain)`.
pub(crate) fn camera_setting_or_unknown(value: i32) -> Option<i32> {
    if value <= UNKNOWN_CAMERA_SETTING {
        None
    } else {
        Some(value)
    }
}

/// Parse the integer value out of a fixed-format 80-byte FITS header card.
///
/// FITS mandates `KEYWORD = value / comment` with the value right-justified in
/// bytes 10..30, so splitting on `=` and taking everything before any `/` is
/// sufficient — no full FITS parser needed for NAXIS1/NAXIS2. Returns `None`
/// for a malformed card so the caller can fall back rather than trust a guess.
fn parse_fits_card_u32(card: &[u8]) -> Option<u32> {
    let text = std::str::from_utf8(card).ok()?;
    let after_eq = text.split_once('=')?.1;
    let value = after_eq.split('/').next()?.trim();
    value.parse::<u32>().ok()
}

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
        frame_type: nightshade_native::camera::FrameType,
    ) -> Result<(), DeviceOpError> {
        self.camera_start_exposure_configured(
            device_id, duration, gain, offset, bin_x, bin_y, None, frame_type,
        )
        .await
    }

    /// Start an exposure while preserving the complete per-frame acquisition
    /// contract, including a binned-pixel ROI when one was requested.
    #[allow(clippy::too_many_arguments)]
    pub async fn camera_start_exposure_configured(
        &self,
        device_id: &str,
        duration: f64,
        gain: Option<i32>,
        offset: Option<i32>,
        bin_x: i32,
        bin_y: i32,
        subframe: Option<SubFrame>,
        frame_type: nightshade_native::camera::FrameType,
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
                            subframe,
                            readout_mode: None,
                            frame_type,
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
                    // Gain and Offset are OPTIONAL in ASCOM ICameraV3 — a camera
                    // that doesn't implement them throws PropertyNotImplemented
                    // (error 1024). Warn and continue rather than failing the
                    // whole exposure (mirrors the INDI path below), so gain-less
                    // cameras (many CCDs, and CMOS in certain modes) can still
                    // capture instead of erroring out on every frame.
                    if let Some(g) = gain {
                        if let Err(e) = camera.set_gain(g).await {
                            tracing::warn!(
                                "Failed to set Alpaca camera gain (device may not \
                                 support it); continuing without it: {}",
                                e
                            );
                        }
                    }
                    if let Some(o) = offset {
                        if let Err(e) = camera.set_offset(o).await {
                            tracing::warn!(
                                "Failed to set Alpaca camera offset (device may not \
                                 support it); continuing without it: {}",
                                e
                            );
                        }
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
                    // Alpaca/ASCOM defines NumX/NumY in binned pixels. Changing
                    // BinX/BinY does not require drivers to resize an existing
                    // full-frame ROI, and several leave the old unbinned
                    // dimensions in place. Reset the full-frame ROI after
                    // binning so a 2x2 exposure on an 800x600 sensor requests
                    // 400x300 instead of the invalid 800x600.
                    let sensor_width = camera.camera_x_size().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!("Failed to read Alpaca camera width: {}", e),
                        )
                    })?;
                    let sensor_height = camera.camera_y_size().await.map_err(|e| {
                        DeviceOpError::hardware(
                            Some(device_id.to_string()),
                            format!("Failed to read Alpaca camera height: {}", e),
                        )
                    })?;
                    let full_width = sensor_width
                        .checked_div(bin_x)
                        .filter(|v| *v > 0)
                        .ok_or_else(|| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                    "Invalid Alpaca full-frame width {} at bin {}",
                                    sensor_width, bin_x
                                ),
                            )
                        })?;
                    let full_height = sensor_height
                        .checked_div(bin_y)
                        .filter(|v| *v > 0)
                        .ok_or_else(|| {
                            DeviceOpError::hardware(
                                Some(device_id.to_string()),
                                format!(
                                    "Invalid Alpaca full-frame height {} at bin {}",
                                    sensor_height, bin_y
                                ),
                            )
                        })?;
                    let (start_x, start_y, num_x, num_y) = match subframe {
                        Some(ref roi) => {
                            let start_x = i32::try_from(roi.start_x).map_err(|_| {
                                DeviceOpError::hardware(
                                    Some(device_id.to_string()),
                                    "Alpaca ROI start_x exceeds the driver integer range",
                                )
                            })?;
                            let start_y = i32::try_from(roi.start_y).map_err(|_| {
                                DeviceOpError::hardware(
                                    Some(device_id.to_string()),
                                    "Alpaca ROI start_y exceeds the driver integer range",
                                )
                            })?;
                            let width = i32::try_from(roi.width).map_err(|_| {
                                DeviceOpError::hardware(
                                    Some(device_id.to_string()),
                                    "Alpaca ROI width exceeds the driver integer range",
                                )
                            })?;
                            let height = i32::try_from(roi.height).map_err(|_| {
                                DeviceOpError::hardware(
                                    Some(device_id.to_string()),
                                    "Alpaca ROI height exceeds the driver integer range",
                                )
                            })?;
                            if start_x.checked_add(width).is_none_or(|v| v > full_width)
                                || start_y.checked_add(height).is_none_or(|v| v > full_height)
                            {
                                return Err(DeviceOpError::hardware(
                                    Some(device_id.to_string()),
                                    format!(
                                        "Alpaca ROI {}x{}+{}+{} exceeds binned sensor {}x{}",
                                        width, height, start_x, start_y, full_width, full_height
                                    ),
                                ));
                            }
                            (start_x, start_y, width, height)
                        }
                        None => (0, 0, full_width, full_height),
                    };
                    camera
                        .set_start_x(start_x)
                        .await
                        .map_err(DeviceOpError::from)?;
                    camera
                        .set_start_y(start_y)
                        .await
                        .map_err(DeviceOpError::from)?;
                    camera.set_num_x(num_x).await.map_err(DeviceOpError::from)?;
                    camera.set_num_y(num_y).await.map_err(DeviceOpError::from)?;
                    // Start the exposure
                    return camera
                        .start_exposure(duration, true)
                        .await
                        .map_err(DeviceOpError::from);
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
                        let (frame_x, frame_y, frame_width, frame_height) =
                            if let Some(ref roi) = subframe {
                                (
                                    f64::from(roi.start_x),
                                    f64::from(roi.start_y),
                                    f64::from(roi.width),
                                    f64::from(roi.height),
                                )
                            } else {
                                let sensor_width = locked_client
                                    .get_number(&device_name, "CCD_INFO", "CCD_MAX_X")
                                    .await
                                    .filter(|value| value.is_finite() && *value > 0.0)
                                    .ok_or_else(|| {
                                        DeviceOpError::hardware(
                                        Some(device_id.to_string()),
                                        "INDI camera did not report CCD_MAX_X for full-frame reset",
                                    )
                                    })?;
                                let sensor_height = locked_client
                                    .get_number(&device_name, "CCD_INFO", "CCD_MAX_Y")
                                    .await
                                    .filter(|value| value.is_finite() && *value > 0.0)
                                    .ok_or_else(|| {
                                        DeviceOpError::hardware(
                                        Some(device_id.to_string()),
                                        "INDI camera did not report CCD_MAX_Y for full-frame reset",
                                    )
                                    })?;
                                (
                                    0.0,
                                    0.0,
                                    sensor_width / f64::from(bin_x),
                                    sensor_height / f64::from(bin_y),
                                )
                            };
                        locked_client
                            .set_numbers(
                                &device_name,
                                "CCD_FRAME",
                                &[
                                    ("X", frame_x),
                                    ("Y", frame_y),
                                    ("WIDTH", frame_width),
                                    ("HEIGHT", frame_height),
                                ],
                            )
                            .await
                            .map_err(|e| {
                                DeviceOpError::hardware(
                                    Some(device_id.to_string()),
                                    format!("Failed to set INDI camera frame geometry: {}", e),
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
                            .map_err(DeviceOpError::from);
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
                        subframe,
                        readout_mode: None,
                        frame_type,
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
                // Commit the requested settings to the singleton so the download
                // reports what this exposure was actually taken with. Skipping
                // this made the simulator answer with its defaults (gain 100 /
                // offset 10 / 1.0s) regardless of the request, so a simulated
                // run wrote FITS headers that contradicted the sequence — the
                // kind of disagreement that makes simulator testing worse than
                // no testing. `None` gain/offset still means "leave unchanged",
                // matching the real driver branches above.
                {
                    // Starts the exposure CLOCK as well as recording the
                    // duration: the simulator integrates for the time it was
                    // asked for, so callers are paced the way real hardware
                    // paces them.
                    crate::api::devices::simulation::begin_sim_exposure(
                        crate::api::devices::simulation::SimExposureRequest {
                            secs: duration,
                            frame_type,
                            subframe: subframe
                                .as_ref()
                                .map(|r| (r.start_x, r.start_y, r.width, r.height)),
                        },
                    )
                    .await;
                    let sim = crate::api::devices::simulation::get_sim_camera();
                    let mut guard = sim.write().await;
                    if let Some(g) = gain {
                        guard.status.gain = g;
                    }
                    if let Some(o) = offset {
                        guard.status.offset = o;
                    }
                    guard.status.bin_x = bin_x;
                    guard.status.bin_y = bin_y;
                }
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
                            .map_err(DeviceOpError::from);
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
                    return camera.image_ready().await.map_err(DeviceOpError::from);
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
                // Complete once the requested integration time has actually
                // elapsed. This used to be an unconditional `Ok(true)`, which
                // left the simulator with no way to pace a capture loop — see
                // `SIM_EXPOSURE_START` for what that cost. Refuse the call if
                // not connected so callers can distinguish "nothing to expose"
                // from "no camera attached".
                crate::device_manager::ops::sim_gate::require_camera_connected().await?;
                Ok(crate::api::devices::simulation::sim_exposure_is_complete().await)
            }
            Some(DriverType::Native) => {
                let native_cameras = self.native_cameras.read().await;
                if let Some(camera) = native_cameras.get(device_id) {
                    return camera
                        .is_exposure_complete()
                        .await
                        .map_err(DeviceOpError::from);
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
                    // Same as the INDI path below: record a failed read as UNKNOWN
                    // rather than 0, so it cannot outrank the configured gain and
                    // mislabel the frame's FITS header.
                    let gain = match camera.gain().await {
                        Ok(g) => g,
                        Err(e) => {
                            warn!(
                                "Failed to read camera gain for {}: {}. Recording it as \
                                 unknown so the configured gain is used instead.",
                                device_id, e
                            );
                            UNKNOWN_CAMERA_SETTING
                        }
                    };
                    let offset = match camera.offset().await {
                        Ok(o) => o,
                        Err(e) => {
                            warn!(
                                "Failed to read camera offset for {}: {}. Recording it as \
                                 unknown so the configured offset is used instead.",
                                device_id, e
                            );
                            UNKNOWN_CAMERA_SETTING
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
                        // Both offsets must be READ, not assumed. Defaulting a failed
                        // read to 0 mapped to RGGB — indistinguishable from a genuine
                        // RGGB sensor — so a BGGR/GRBG one-shot-colour camera whose
                        // bayeroffsetx/y read failed got red and blue TRANSPOSED in
                        // every debayered frame and the wrong BAYERPAT written into
                        // the FITS header, which cannot be undone after the fact.
                        // `None` here means "pattern unknown", which leaves the frame
                        // undebayered rather than debayered wrongly.
                        let offsets =
                            match (camera.bayer_offset_x().await, camera.bayer_offset_y().await) {
                                (Ok(x), Ok(y)) => Some((x, y)),
                                (x, y) => {
                                    warn!(
                                        "Failed to read bayer offsets for {} (x: {:?}, y: {:?}). \
                                     Leaving the Bayer pattern UNKNOWN so the frame is not \
                                     debayered with a guessed pattern.",
                                        device_id,
                                        x.err(),
                                        y.err()
                                    );
                                    None
                                }
                            };
                        // Map offsets to bayer pattern. An offset pair outside the
                        // 2x2 grid is also "unknown" rather than silently RGGB.
                        offsets.and_then(|(offset_x, offset_y)| match (offset_x, offset_y) {
                            (0, 0) => Some(nightshade_native::camera::BayerPattern::Rggb),
                            (1, 0) => Some(nightshade_native::camera::BayerPattern::Grbg),
                            (0, 1) => Some(nightshade_native::camera::BayerPattern::Gbrg),
                            (1, 1) => Some(nightshade_native::camera::BayerPattern::Bggr),
                            _ => {
                                warn!(
                                    "Camera {} reported out-of-range bayer offsets \
                                         ({}, {}); Bayer pattern left unknown.",
                                    device_id, offset_x, offset_y
                                );
                                None
                            }
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

                        // Subscribe to BLOB events BEFORE enable_blob + the
                        // metadata round-trips below: the exposure may already
                        // be completing, and a BLOB emitted during those reads
                        // would otherwise be missed by a later subscription.
                        let mut rx = {
                            let locked_client = client.read().await;
                            locked_client.subscribe()
                        };

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
                        // A FAILED read must not masquerade as "gain 0": that 0 was
                        // wrapped in Some() downstream, which short-circuited
                        // `image_data.gain.or(config.gain)` and let it BEAT the
                        // operator's configured gain — stamping GAIN=0 into every
                        // frame's FITS header for the run and permanently breaking
                        // dark/flat library matching, which keys on gain.
                        // UNKNOWN_CAMERA_SETTING is mapped back to None at the
                        // ImageMetadata boundary so the configured value wins.
                        let gain = match camera.get_gain().await {
                            Ok(g) => g,
                            Err(e) => {
                                warn!(
                                    "Failed to read INDI gain for {}: {}. Recording it as \
                                     unknown so the configured gain is used instead.",
                                    device_id, e
                                );
                                UNKNOWN_CAMERA_SETTING
                            }
                        };
                        let offset = match camera.get_offset().await {
                            Ok(o) => o,
                            Err(e) => {
                                warn!(
                                    "Failed to read INDI offset for {}: {}. Recording it as \
                                     unknown so the configured offset is used instead.",
                                    device_id, e
                                );
                                UNKNOWN_CAMERA_SETTING
                            }
                        };

                        // Build an ImageData from a raw INDI image BLOB (FITS or
                        // raw u16). Shared by the event path and the cached-BLOB
                        // fallback below so both decode identically.
                        let build_image = |data: Vec<u8>| -> ImageData {
                            // The FITS header carries the frame's TRUE geometry in
                            // the mandatory NAXIS1/NAXIS2 keywords; prefer them
                            // over the CCD_INFO-derived guess. CCD_MAX_X/Y is the
                            // full UNBINNED sensor, so at bin 2 the two disagree —
                            // verified against a live INDI CCD simulator: CCD_INFO
                            // said 1280x1024 while the BLOB said NAXIS1=640,
                            // NAXIS2=512. Using CCD_INFO there built an ImageData
                            // claiming 1280x1024 around a 640x512 frame, which
                            // failed validation outright (binned INDI capture was
                            // broken); and when CCD_INFO is unreadable the 1920x1080
                            // fallback below silently CROPPED and re-strided the
                            // frame instead, because the truncate() made the
                            // downstream size check pass tautologically.
                            let mut fits_dims: Option<(u32, u32)> = None;
                            let image_data = if data.starts_with(b"SIMPLE") {
                                let mut off = 0;
                                let mut naxis1: Option<u32> = None;
                                let mut naxis2: Option<u32> = None;
                                for chunk in data.chunks(80) {
                                    off += 80;
                                    if chunk.starts_with(b"NAXIS1") {
                                        naxis1 = parse_fits_card_u32(chunk);
                                    } else if chunk.starts_with(b"NAXIS2") {
                                        naxis2 = parse_fits_card_u32(chunk);
                                    }
                                    if chunk.starts_with(b"END") {
                                        off = ((off + 2879) / 2880) * 2880;
                                        break;
                                    }
                                }
                                if let (Some(w), Some(h)) = (naxis1, naxis2) {
                                    if w > 0 && h > 0 {
                                        fits_dims = Some((w, h));
                                    }
                                }
                                let binary_data = &data[off.min(data.len())..];
                                let mut pixels: Vec<u16> =
                                    Vec::with_capacity(binary_data.len() / 2);
                                for chunk in binary_data.chunks_exact(2) {
                                    pixels.push(u16::from_be_bytes([chunk[0], chunk[1]]));
                                }
                                pixels
                            } else {
                                let mut pixels: Vec<u16> = Vec::with_capacity(data.len() / 2);
                                for chunk in data.chunks_exact(2) {
                                    pixels.push(u16::from_le_bytes([chunk[0], chunk[1]]));
                                }
                                pixels
                            };
                            let (eff_width, eff_height) = match fits_dims {
                                Some((w, h)) => {
                                    if (w, h) != (width, height) {
                                        tracing::info!(
                                            "INDI {}: using FITS NAXIS {}x{} instead of \
                                             CCD_INFO-derived {}x{} (binning/subframe)",
                                            device_id,
                                            w,
                                            h,
                                            width,
                                            height
                                        );
                                    }
                                    (w, h)
                                }
                                None => (width, height),
                            };
                            // Trim FITS block padding beyond width*height. Only ever
                            // discards the tail padding now that the dimensions are
                            // the frame's own; a SHORT buffer is left short so
                            // validation can still catch it rather than being
                            // silently reshaped.
                            let expected_pixels = (eff_width as usize) * (eff_height as usize);
                            let mut image_data = image_data;
                            if image_data.len() > expected_pixels {
                                image_data.truncate(expected_pixels);
                            }
                            ImageData {
                                width: eff_width,
                                height: eff_height,
                                data: image_data,
                                bits_per_pixel: 16,
                                bayer_pattern: None,
                                metadata: nightshade_native::camera::ImageMetadata {
                                    exposure_time: 0.0,
                                    gain,
                                    offset,
                                    bin_x,
                                    bin_y,
                                    temperature: temp,
                                    timestamp: chrono::Utc::now(),
                                    subframe: None,
                                    readout_mode: None,
                                    vendor_data: nightshade_native::camera::VendorFeatures::default(
                                    ),
                                },
                            }
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
                                Ok(Ok(event)) => match event {
                                    nightshade_indi::IndiEvent::BlobReceived {
                                        device,
                                        element,
                                        data,
                                        ..
                                    } if device == device_name
                                        && (element == "CCD1" || element == "CCD2") =>
                                    {
                                        return Ok(build_image(data));
                                    }
                                    _ => {}
                                },
                                Ok(Err(_)) => {
                                    return Err(DeviceOpError::hardware(
                                        Some(device_id.to_string()),
                                        "INDI event channel closed",
                                    ));
                                }
                                Err(_) => {
                                    // recv timed out; the reader may have stored
                                    // the BLOB before we subscribed. Poll the
                                    // cache before looping so a race can't hang.
                                    let cached = {
                                        let lc = client.read().await;
                                        match lc.take_blob(&device_name, "CCD1", "CCD1").await {
                                            Some(d) => Some(d),
                                            None => {
                                                lc.take_blob(&device_name, "CCD2", "CCD2").await
                                            }
                                        }
                                    };
                                    if let Some(data) = cached {
                                        return Ok(build_image(data));
                                    }
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
                // set_cooler, and take the frame geometry from the SAME sensor
                // declaration the camera advertised.
                let sim = crate::device_manager::ops::sim_gate::read_camera_status().await?;
                let request =
                    crate::device_manager::ops::sim_gate::read_camera_last_exposure().await?;
                // Claim the finished frame, which both refuses a download the
                // camera cannot honestly satisfy and returns it to idle so a
                // caller that polls completion afterwards is not told to keep
                // waiting. Ungated, this synthesized a full frame stamped with
                // the requested EXPTIME mid-exposure and after an abort, so a
                // cancelled or raced capture still produced a saved light frame.
                crate::api::devices::simulation::take_sim_exposure_for_download()
                    .await
                    .map_err(|detail| {
                        DeviceOpError::hardware(Some(device_id.to_string()), detail)
                    })?;
                // Synthetic download: an electron-domain frame whose star PSF
                // tracks focuser defocus. Extracted into `crate::sim_frame` so it
                // can be unit-tested against the real star detector — an
                // unverified synthetic frame is worse than none, because every
                // focus/HFR result measured against it is then unfalsifiable.
                let focus_position = {
                    let focuser = crate::api::devices::simulation::get_sim_focuser()
                        .read()
                        .await;
                    if focuser.status.connected {
                        Some(focuser.status.position)
                    } else {
                        None
                    }
                };
                // Star position tracks the simulated mount, so guide pulses and
                // tracking drift are visible to whatever is measuring the frame.
                let (offset_x, offset_y) =
                    crate::api::devices::simulation::sim_guide_offset_px().await;
                let frame_request = crate::sim_frame::SimFrameRequest {
                    width: sim.sensor_width.max(1) as usize,
                    height: sim.sensor_height.max(1) as usize,
                    exposure_secs: request.secs,
                    gain: sim.gain,
                    offset: sim.offset,
                    frame_type: request.frame_type,
                    focus_position,
                    offset_x,
                    offset_y,
                    bin_x: sim.bin_x.max(1) as u32,
                    bin_y: sim.bin_y.max(1) as u32,
                    subframe: request.subframe,
                    max_adu: sim.max_adu.clamp(1, u32::from(u16::MAX)) as u16,
                    seed: crate::api::devices::simulation::next_sim_frame_seed(),
                };
                let (width, height) = crate::sim_frame::sim_frame_dimensions(&frame_request);
                let sim_data = crate::sim_frame::synthesize_sim_frame(&frame_request);
                Ok(ImageData {
                    width,
                    height,
                    data: sim_data,
                    bits_per_pixel: 16,
                    bayer_pattern: None,
                    metadata: nightshade_native::camera::ImageMetadata {
                        exposure_time: request.secs,
                        gain: sim.gain,
                        offset: sim.offset,
                        bin_x: sim.bin_x,
                        bin_y: sim.bin_y,
                        temperature: sim.sensor_temp,
                        timestamp: chrono::Utc::now(),
                        subframe: request.subframe.map(|(start_x, start_y, width, height)| {
                            nightshade_native::camera::SubFrame {
                                start_x,
                                start_y,
                                width,
                                height,
                            }
                        }),
                        readout_mode: None,
                        vendor_data: nightshade_native::camera::VendorFeatures::default(),
                    },
                })
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera.download_image().await.map_err(DeviceOpError::from);
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
                        return camera.abort_exposure().await.map_err(DeviceOpError::from);
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
                    return camera.abort_exposure().await.map_err(DeviceOpError::from);
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
                            .map_err(DeviceOpError::from);
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
                    .map_err(DeviceOpError::from)?;
                // Release a caller polling for completion, but remember that the
                // frame was abandoned: a download afterwards has nothing to
                // hand back and must say so.
                crate::api::devices::simulation::abort_sim_exposure().await;
                Ok(())
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera.abort_exposure().await.map_err(DeviceOpError::from);
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
                            .map_err(DeviceOpError::from)?;
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
                            // The driver's own MaxADU, not `2^bit_depth - 1`:
                            // `bit_depth` here is a bucket (8/16/32) inferred FROM
                            // MaxADU, so reconstructing the range from it reported
                            // 65535 for every driver whose MaxADU exceeded 255.
                            max_adu: ascom_caps
                                .as_ref()
                                .map(|c| if c.max_adu == 0 { 65535 } else { c.max_adu })
                                .unwrap_or(65535),
                            can_cool: ascom_caps
                                .as_ref()
                                .map(|c| c.can_set_ccd_temperature)
                                .unwrap_or(false),
                            // Read from the driver like every other field here,
                            // rather than asserting true. These were hardcoded
                            // while `ascom_caps` — already in hand and used for
                            // `can_cool` directly above — carried the real
                            // answer, so `/api/equipment/camera/status` flatly
                            // contradicted `/api/equipment/camera/capabilities`
                            // for the same device. Observed against the ASCOM
                            // Camera Simulator: capabilities correctly said
                            // `canSetGain: false` (its Gain property throws
                            // 0x80020009 / PropertyNotImplemented) while status
                            // claimed `canSetGain: true`, so a client trusting
                            // status offered a gain control that always failed.
                            // `unwrap_or(false)` matches `can_cool`: if the
                            // capability probe itself failed we must not promise
                            // a control we cannot deliver.
                            can_set_gain: ascom_caps
                                .as_ref()
                                .map(|c| c.can_set_gain)
                                .unwrap_or(false),
                            can_set_offset: ascom_caps
                                .as_ref()
                                .map(|c| c.can_set_offset)
                                .unwrap_or(false),
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
                    .map_err(DeviceOpError::from)
            }
            Some(DriverType::Native) => {
                let native_cameras = self.native_cameras.read().await;
                if let Some(camera) = native_cameras.get(device_id) {
                    let native_status = camera.get_status().await.map_err(DeviceOpError::from)?;
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
                        // The DRIVER owns this value. Re-deriving it from
                        // `bit_depth` here overwrote whatever the vendor SDK
                        // reported with the ADC range, which is a different
                        // quantity: an ASI1600MM (12-bit, Raw16 left-justified)
                        // was published as `maxAdu: 4095` while its frames
                        // measurably contained values up to 65504. See the
                        // `nightshade_native::camera::SensorInfo` contract.
                        // 0 = the driver never populated it; 65535 is the
                        // container ceiling and the documented fallback (see the
                        // `unwrap_or` policy in this module's header).
                        max_adu: if sensor_info.max_adu == 0 {
                            65535
                        } else {
                            sensor_info.max_adu
                        },
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
                    return camera.set_gain(gain).await.map_err(DeviceOpError::from);
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
                        return camera.set_offset(offset).await.map_err(DeviceOpError::from);
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
                    return camera.set_offset(offset).await.map_err(DeviceOpError::from);
                }
                Err(DeviceOpError::not_connected(
                    Some(device_id.to_string()),
                    format!("Alpaca camera {} not found", device_id),
                ))
            }
            Some(DriverType::Native) => {
                let mut native_cameras = self.native_cameras.write().await;
                if let Some(camera) = native_cameras.get_mut(device_id) {
                    return camera.set_offset(offset).await.map_err(DeviceOpError::from);
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
                            .map_err(DeviceOpError::from);
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
                        .map_err(DeviceOpError::from);
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
                            .map_err(DeviceOpError::from);
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
                        .map_err(DeviceOpError::from);
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
                        .map_err(DeviceOpError::from);
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
                        .map_err(DeviceOpError::from);
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
                    return camera.capture_preview().await.map_err(DeviceOpError::from);
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

#[cfg(test)]
mod fits_card_tests {
    use super::parse_fits_card_u32;

    /// These two cards are the verbatim 80-byte headers from a BLOB captured off
    /// a live `indi_simulator_ccd` at 2x2 binning, where CCD_INFO advertised the
    /// unbinned 1280x1024 while the frame was really 640x512. Reading NAXIS is
    /// what keeps those two facts from being confused.
    #[test]
    fn parses_naxis_cards_from_a_real_indi_blob() {
        let naxis1 =
            b"NAXIS1  =                  640 / length of data axis 1                          ";
        let naxis2 =
            b"NAXIS2  =                  512 / length of data axis 2                          ";
        assert_eq!(parse_fits_card_u32(naxis1), Some(640));
        assert_eq!(parse_fits_card_u32(naxis2), Some(512));
    }

    #[test]
    fn rejects_cards_it_cannot_trust() {
        // No '=', a non-numeric value, and a float value all fall back to None
        // so the caller keeps its own dimensions instead of using a bad parse.
        assert_eq!(parse_fits_card_u32(b"COMMENT no equals sign here"), None);
        assert_eq!(
            parse_fits_card_u32(b"NAXIS1  =                    T / bad"),
            None
        );
        assert_eq!(
            parse_fits_card_u32(b"NAXIS1  =                 6.40 / float"),
            None
        );
        assert_eq!(
            parse_fits_card_u32(b"NAXIS1  =                   -1 / negative"),
            None
        );
    }

    #[test]
    fn parses_a_card_with_no_comment() {
        assert_eq!(
            parse_fits_card_u32(b"NAXIS1  =                 4144"),
            Some(4144)
        );
    }

    /// A gain of 0 is a LEGITIMATE setting (unity gain on many cameras), so the
    /// unknown marker must be distinguishable from it — that conflation is what
    /// let a failed read outrank the operator's configured gain.
    #[test]
    fn unknown_camera_setting_is_distinct_from_a_real_zero() {
        use super::{camera_setting_or_unknown, UNKNOWN_CAMERA_SETTING};

        assert_eq!(camera_setting_or_unknown(UNKNOWN_CAMERA_SETTING), None);
        assert_eq!(camera_setting_or_unknown(0), Some(0));
        assert_eq!(camera_setting_or_unknown(139), Some(139));
        // `.or(config)` only falls through on None, which is the whole point.
        assert_eq!(
            camera_setting_or_unknown(UNKNOWN_CAMERA_SETTING).or(Some(120)),
            Some(120)
        );
        assert_eq!(camera_setting_or_unknown(0).or(Some(120)), Some(0));
    }
}

#[cfg(test)]
mod sim_camera_tests {
    use crate::api::devices::simulation::{
        clear_sim_exposure, get_sim_camera, sim_singleton_test_lock,
    };
    use crate::api::get_device_manager;
    use crate::device::{CameraState, DeviceInfo, DeviceType, DriverType};
    use nightshade_native::camera::FrameType;

    /// `expect_err` on a `Result<ImageData, _>` would dump a whole 1920x1080
    /// frame into the failure output, which buries the assertion.
    async fn download_error(device_id: &str, why: &str) -> String {
        match get_device_manager().camera_download_image(device_id).await {
            Ok(image) => panic!(
                "{why}, yet a complete {}x{} frame was returned \
                 (metadata claims a {}s exposure)",
                image.width, image.height, image.metadata.exposure_time
            ),
            Err(e) => e.to_string(),
        }
    }

    async fn attach_sim_camera(device_id: &str) {
        let info = DeviceInfo {
            id: device_id.to_string(),
            name: "Simulated Camera".to_string(),
            device_type: DeviceType::Camera,
            driver_type: DriverType::Simulator,
            description: "Simulated camera".to_string(),
            driver_version: "1.0".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: "Simulated Camera".to_string(),
        };
        get_device_manager().register_device(info, false).await;
        get_sim_camera().write().await.status.connected = true;
        clear_sim_exposure().await;
    }

    /// `camera_get_status` and `camera_is_exposure_complete` are polled by the
    /// same UI and must never contradict each other. The status arm reported
    /// `Idle` throughout a running exposure while the completion arm said "not
    /// yet", so the dashboard showed an idle camera mid-frame and no progress
    /// UI could be exercised without hardware.
    #[tokio::test]
    async fn status_walks_the_exposure_state_machine() {
        let _serialized = sim_singleton_test_lock().lock().await;
        let device_id = "sim_camera_state_machine";
        attach_sim_camera(device_id).await;
        let mgr = get_device_manager();

        assert_eq!(
            mgr.camera_get_status(device_id).await.unwrap().state,
            CameraState::Idle,
            "a camera with no exposure in flight is idle"
        );

        mgr.camera_start_exposure(device_id, 0.4, None, None, 1, 1, FrameType::Light)
            .await
            .expect("simulated exposure should start");

        let mid = mgr.camera_get_status(device_id).await.unwrap();
        assert!(
            !mgr.camera_is_exposure_complete(device_id).await.unwrap(),
            "0.4s exposure cannot be complete immediately"
        );
        assert_eq!(
            mid.state,
            CameraState::Exposing,
            "status said {:?} while the exposure was still integrating",
            mid.state
        );

        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        assert!(mgr.camera_is_exposure_complete(device_id).await.unwrap());
        assert_eq!(
            mgr.camera_get_status(device_id).await.unwrap().state,
            CameraState::Reading,
            "an integrated but undownloaded frame is waiting to be read out"
        );

        mgr.camera_download_image(device_id)
            .await
            .expect("a completed exposure should download");
        assert_eq!(
            mgr.camera_get_status(device_id).await.unwrap().state,
            CameraState::Idle,
            "the camera returns to idle once the frame has been read out"
        );
    }

    /// Downloading mid-exposure returned a complete frame stamped with the full
    /// requested `EXPTIME`. A caller that skipped (or raced) the completion poll
    /// therefore wrote a FITS file whose header was a lie about how long the
    /// sensor had integrated.
    #[tokio::test]
    async fn download_before_completion_is_refused() {
        let _serialized = sim_singleton_test_lock().lock().await;
        let device_id = "sim_camera_early_download";
        attach_sim_camera(device_id).await;
        let mgr = get_device_manager();

        mgr.camera_start_exposure(device_id, 3.0, None, None, 1, 1, FrameType::Light)
            .await
            .unwrap();
        assert!(!mgr.camera_is_exposure_complete(device_id).await.unwrap());

        let err = download_error(device_id, "the exposure was still integrating").await;
        assert!(
            err.contains("still integrating"),
            "expected a not-ready error, got: {err}"
        );

        mgr.camera_abort_exposure(device_id).await.unwrap();
    }

    /// An aborted exposure has no frame to hand back. Returning one made abort
    /// indistinguishable from success, so a cancelled sequence still produced
    /// a saved light frame.
    #[tokio::test]
    async fn download_after_abort_is_refused() {
        let _serialized = sim_singleton_test_lock().lock().await;
        let device_id = "sim_camera_aborted_download";
        attach_sim_camera(device_id).await;
        let mgr = get_device_manager();

        mgr.camera_start_exposure(device_id, 5.0, None, None, 1, 1, FrameType::Light)
            .await
            .unwrap();
        mgr.camera_abort_exposure(device_id).await.unwrap();

        assert_eq!(
            mgr.camera_get_status(device_id).await.unwrap().state,
            CameraState::Idle,
            "an aborted camera is idle, not still exposing"
        );
        let err = download_error(device_id, "the exposure was aborted").await;
        assert!(
            err.contains("aborted"),
            "expected an abort error, got: {err}"
        );
    }

    /// Aborting must still release a caller that is waiting on completion —
    /// the refusal above applies to the download, not to the poll loop.
    #[tokio::test]
    async fn abort_releases_a_waiting_poller() {
        let _serialized = sim_singleton_test_lock().lock().await;
        let device_id = "sim_camera_abort_releases";
        attach_sim_camera(device_id).await;
        let mgr = get_device_manager();

        mgr.camera_start_exposure(device_id, 30.0, None, None, 1, 1, FrameType::Light)
            .await
            .unwrap();
        assert!(!mgr.camera_is_exposure_complete(device_id).await.unwrap());
        mgr.camera_abort_exposure(device_id).await.unwrap();
        assert!(
            mgr.camera_is_exposure_complete(device_id).await.unwrap(),
            "abort must not strand a poll loop waiting out the original duration"
        );
    }

    /// Downloading without having started anything is a caller bug, not an
    /// invitation to synthesize a frame out of the last request's parameters.
    #[tokio::test]
    async fn download_without_an_exposure_is_refused() {
        let _serialized = sim_singleton_test_lock().lock().await;
        let device_id = "sim_camera_no_exposure";
        attach_sim_camera(device_id).await;

        let err = download_error(device_id, "no exposure had been started").await;
        assert!(
            err.contains("No exposure"),
            "expected a no-exposure error, got: {err}"
        );
    }
}
