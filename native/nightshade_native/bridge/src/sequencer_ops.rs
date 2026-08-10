//! Device Operations Implementation for the Sequencer
//!
//! This module implements the DeviceOps trait from the sequencer crate,
//! routing calls to actual connected devices via the bridge API.
//!
//! # `as`-cast policy
//!
//! Numeric casts in this file cluster into the sites below. They are keyed by
//! function rather than line number: the line numbers this list used to carry
//! had already drifted by ~80 lines, which makes the index worse than no index
//! at all.
//! - **Pixel-count widening (u32 → usize)**
//!   (`camera_start_exposure_with_frame_type`): expected-size computation;
//!   u32 → usize widening is exact on every supported target
//!   (≥ 32-bit usize).
//! - **bool → u8** (`camera_set_cooler`, `guider_dither`): cooler-enable /
//!   ra-only flag in the FFI wire; bool is by definition 0 or 1.
//! - **Filter wheel index ±1** (`filterwheel_set_filter_by_name`): `p` is i32
//!   position from ASCOM; `+1` for 1-based UI display is bounded by filter
//!   slot count (typically ≤ 16, fits i32 trivially).
//! - **GAIN/OFFSET i32 → i64 FITS header** (`plate_solve`): i32 → i64 is exact
//!   widening.
//! - **Star-count average f64** (`calculate_image_hfr`): `stars.len() as f64`
//!   exact for any realistic count (f64 mantissa covers usize).
//! - **Julian Day chrono fields → f64/i32** (`julian_day`): identical pattern
//!   to `sequencer/src/meridian.rs::julian_day` (which has per-site Why
//!   comments); chrono `Datelike` returns calendar-bounded small integers that
//!   fit i32 and f64 exactly.
//!
//! Sites with a local `Why:` comment override the module-level reasoning.

use crate::api::*;
use crate::device::DeviceType;
use crate::event::{EquipmentEvent, EventSeverity};
use crate::filter_matching::find_filter_match;
use crate::state::SharedAppState;
use crate::unified_device_ops::create_unified_device_ops;
use async_trait::async_trait;
use nightshade_sequencer::{
    DeviceOps, DeviceResult, GuidingCalibration, GuidingStatus, ImageData, PlateSolveResult,
};
use std::sync::Arc;

/// Real device operations implementation that uses connected devices
pub struct BridgeDeviceOps {
    app_state: SharedAppState,
}

impl BridgeDeviceOps {
    pub fn new(app_state: SharedAppState) -> Self {
        Self { app_state }
    }

    async fn resolve_safety_device_id(&self, explicit_id: Option<&str>) -> DeviceResult<String> {
        if let Some(id) = explicit_id {
            return Ok(id.to_string());
        }

        if let Some(id) = get_device_manager()
            .first_connected_device_id(DeviceType::SafetyMonitor)
            .await
        {
            return Ok(id);
        }

        if let Some(id) = self
            .app_state
            .get_profile_device_id(DeviceType::Weather)
            .await
        {
            return Ok(id);
        }

        Err(
            "No safety monitor or weather device configured for sequencer safety checks"
                .to_string(),
        )
    }

    /// Where the telescope is actually pointing, sampled for the FITS header.
    ///
    /// `FrameContext` only ever carries the TARGET's nominal coordinates, and
    /// only when the sequence has a Target group at all — so a run built the
    /// way the app itself suggests when it warns "No target group found in
    /// sequence" (Slew to Target with custom coordinates) wrote every light
    /// frame with no RA/DEC/OBJCTRA card whatsoever, leaving no record on disk
    /// of where the scope was aimed. Even WITH a target group the numbers were
    /// wrong in kind: an unedited "New Target" sits at 0h/0°, which is where
    /// the sequence meant to go, not where the mount was.
    ///
    /// RA/DEC are by convention the telescope's reported pointing (what MaxIm
    /// DL and N.I.N.A. write there), and that is also the coordinate a later
    /// plate-solve wants as its search hint, so the mount is the right source.
    ///
    /// Best-effort in the same sense as the focuser/rotator telemetry the
    /// exposure path already collects: no connected mount, or a driver that
    /// will not answer, means the keyword is omitted rather than filled with a
    /// plausible-looking lie.
    /// `when` is the instant the horizon frame is evaluated at — the exposure
    /// midpoint for a frame that recorded one. It is NOT when the mount is
    /// read: the RA/Dec below is sampled now, because a tracking mount holds
    /// it, while the altitude derived from it belongs to the light the frame
    /// actually integrated.
    async fn read_mount_pointing(
        &self,
        when: chrono::DateTime<chrono::Utc>,
    ) -> Option<MountPointing> {
        let mount_id = get_device_manager()
            .first_connected_device_id(DeviceType::Mount)
            .await?;

        match mount_get_coordinates(mount_id.clone()).await {
            Ok((ra_hours, dec_degrees)) => {
                // Altitude is derived, not read back: `mount_get_status` would
                // report it but costs a full capability sweep per saved frame
                // on ASCOM, and the geometry is exact once the site is known.
                // `None` when the observer location is unset — the writer then
                // omits AIRMASS instead of computing it from a guessed site.
                let altitude_deg = self
                    .get_observer_location()
                    .map(|(lat, lon)| altitude_degrees(ra_hours, dec_degrees, lat, lon, when));
                Some(MountPointing {
                    ra_hours,
                    dec_degrees,
                    altitude_deg,
                })
            }
            Err(e) => {
                tracing::debug!(
                    "[CAPTURE] mount_get_coordinates({}) failed; RA/DEC omitted from FITS: {}",
                    mount_id,
                    e
                );
                None
            }
        }
    }
}

/// Telescope pointing sampled from the mount at save time, for the FITS
/// `RA`/`DEC`/`OBJCTRA`/`OBJCTDEC` (and, via the altitude, `AIRMASS`) cards.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MountPointing {
    /// Right ascension the mount reports it is on, in hours.
    pub ra_hours: f64,
    /// Declination the mount reports it is on, in degrees.
    pub dec_degrees: f64,
    /// Altitude above the horizon in degrees. `None` when the observer
    /// location is unknown, in which case the writer omits `AIRMASS`.
    pub altitude_deg: Option<f64>,
}

/// Altitude above the horizon of `ra_hours`/`dec_degrees` as seen from
/// `lat`/`lon` at `when`.
///
/// Free-standing (and taking an explicit instant) so the AIRMASS fallback below
/// is testable without a clock or a device: the trait method
/// `BridgeDeviceOps::calculate_altitude` is this function at `Utc::now()`.
fn altitude_degrees(
    ra_hours: f64,
    dec_degrees: f64,
    lat: f64,
    lon: f64,
    when: chrono::DateTime<chrono::Utc>,
) -> f64 {
    let lst = local_sidereal_time(julian_day(when), lon);
    let ha_rad = ((lst - ra_hours) * 15.0_f64).to_radians();
    let dec_rad = dec_degrees.to_radians();
    let lat_rad = lat.to_radians();
    let sin_alt = lat_rad.sin() * dec_rad.sin() + lat_rad.cos() * dec_rad.cos() * ha_rad.cos();
    sin_alt.asin().to_degrees()
}

/// Fill in the altitude for a frame whose context already carries the mount's
/// coordinates but not the geometry derived from them.
///
/// Why this exists: the sequencer only derives alt/az when its own
/// `ExecutionContext` was seeded with a site, while the FITS writer's site comes
/// from app settings. A run started before the location reached the executor —
/// or a standalone burst that never carried one — therefore has pointing but no
/// altitude, and AIRMASS silently disappears from the header even though the app
/// knows exactly where the observer is. AIRMASS is not cosmetic: extinction
/// correction in any photometry workflow needs it, and it cannot be recovered
/// later from a file that never recorded the site.
///
/// This is NOT a second mount read. The coordinates are the context's own — only
/// the derived altitude is added — so the header and the `captured_images` row
/// still describe one instant.
///
/// `None` when there is nothing to add: the context already has the altitude, it
/// has no pointing to derive one from, or no site is configured anywhere (in
/// which case the writer omits AIRMASS rather than computing it from a guess).
fn context_altitude_pointing(
    frame_ctx: &nightshade_sequencer::scheduling::FrameContext,
    observer: Option<(f64, f64)>,
    when: chrono::DateTime<chrono::Utc>,
) -> Option<MountPointing> {
    if frame_ctx.mount_altitude_deg.is_some() {
        return None;
    }
    let (ra_hours, dec_degrees) = frame_ctx.mount_ra_hours.zip(frame_ctx.mount_dec_degrees)?;
    let (lat, lon) = observer?;
    Some(MountPointing {
        ra_hours,
        dec_degrees,
        altitude_deg: Some(altitude_degrees(ra_hours, dec_degrees, lat, lon, when)),
    })
}

/// The label the app already knows a connected camera by, for FITS `INSTRUME`.
///
/// Prefers `display_name` over `name` because `display_name` is
/// `"<name> (<serial>)"` whenever the driver reports a serial, and on a rig
/// carrying two of the same model the serial is the only part of the string
/// that tells the frames apart. Falls back to `name`, and to `None` when the
/// id names nothing connected — the writer then omits the keyword.
///
/// Only the DRIVER's answer is used. Nothing here derives an instrument from
/// the device id: `native:zwo:1` is an enumeration index that re-orders across
/// a replug, so stamping it into an archival keyword would label frames with
/// something that means a different camera tomorrow.
pub(crate) async fn connected_camera_label(camera_id: &str) -> Option<String> {
    api_get_connected_devices()
        .await
        .into_iter()
        .find(|d| d.id == camera_id && d.device_type == DeviceType::Camera)
        .and_then(|d| {
            let display = d.display_name.trim();
            let label = if display.is_empty() {
                d.name.trim()
            } else {
                display
            };
            if label.is_empty() {
                None
            } else {
                Some(label.to_string())
            }
        })
}

/// Assemble the rich FITS header for a sequencer-saved frame.
///
/// Split out of `save_fits` so the pointing decision is exercisable without a
/// connected mount — reading the mount is the only thing `save_fits` adds.
fn build_rich_header(
    image_data: &ImageData,
    frame_ctx: &nightshade_sequencer::scheduling::FrameContext,
    pointing: Option<MountPointing>,
) -> crate::api::FitsWriteHeaderRich {
    // Image Grading: rich-header path. Replaces the previous
    // 9-keyword hand-rolled FitsHeader so this adapter writes the same
    // full keyword set as the real device path.
    let mut header = crate::api::FitsWriteHeaderRich::from_frame_context(frame_ctx);

    // The `FrameContext` wins over `ImageData` for every value the two both
    // carry, because the context is also what the `captured_images` row is
    // written from — one source, so a card and its column cannot disagree
    // about one frame. `ImageData` remains the fallback for callers that hand
    // us a context with the field unset (the flat wizard, one-shot captures),
    // which would otherwise lose the keyword outright.
    //
    // For the sequencer this changes nothing on disk: `build_frame_context_for_save`
    // already folds the camera's own report into the context before calling
    // here, so these fields are equal by construction. What it removes is the
    // ability for them to stop being equal.
    if header.gain.is_none() {
        header.gain = image_data.gain;
    }
    if header.offset.is_none() {
        header.offset = image_data.offset;
    }
    if header.ccd_temp.is_none() {
        header.ccd_temp = image_data.temperature;
    }
    if frame_ctx.duration_secs <= 0.0 {
        header.exposure_time = image_data.exposure_secs;
    }

    // The mount's own report wins over the target's nominal coordinates: RA
    // and DEC mean "where the telescope was", not "where the sequence meant to
    // be". The target coordinates stay as the fallback so a run whose mount
    // cannot be read is no worse off than before.
    //
    // Preference order matters. The sequencer now samples the mount into
    // `FrameContext` at the same instant it samples the focuser and rotator,
    // and that struct is what the `captured_images` row is also stamped from —
    // so taking the pointing from it, rather than from this function's own
    // late second read, is what guarantees the header and the row agree. The
    // `pointing` argument stays as the fallback for save paths that build a
    // `FrameContext` without touching the mount (the flat wizard, one-shot
    // captures), which would otherwise regress to no RA/DEC card at all.
    let context_pointing = frame_ctx.mount_ra_hours.zip(frame_ctx.mount_dec_degrees);
    if let Some((ra_hours, dec_degrees)) = context_pointing {
        header.ra = Some(ra_hours);
        header.dec = Some(dec_degrees);
        // The altitude is allowed to come from `pointing` even when the
        // coordinates did not: a context can carry pointing and still have no
        // altitude, because the sequencer derives alt/az only when ITS OWN
        // execution context was seeded with a site, while the site the FITS
        // writer knows about lives in app settings. Without this fallback a
        // sequenced frame loses AIRMASS outright in that (entirely ordinary)
        // configuration. See `context_altitude_pointing`, which is where the
        // fallback's coordinates come from — they are this same context's, so
        // the card is still describing one instant, not two reads.
        // `.or(header.altitude)` last: an assignment cannot be allowed to
        // replace the altitude `from_frame_context` already derived from this
        // same pointing with `None`. Overwriting a good value with nothing is
        // how a keyword disappears from a file for a reason that has nothing
        // to do with whether it was knowable.
        header.altitude = frame_ctx
            .mount_altitude_deg
            .or_else(|| pointing.and_then(|p| p.altitude_deg))
            .or(header.altitude);
    } else if let Some(p) = pointing {
        header.ra = Some(p.ra_hours);
        header.dec = Some(p.dec_degrees);
        header.altitude = p.altitude_deg;
    }

    header
}

#[async_trait]
impl DeviceOps for BridgeDeviceOps {
    // =========================================================================
    // MOUNT OPERATIONS
    // =========================================================================

    async fn mount_slew_to_coordinates(
        &self,
        mount_id: &str,
        ra_hours: f64,
        dec_degrees: f64,
    ) -> DeviceResult<()> {
        // Emit start event
        self.app_state.publish_equipment_event(
            EquipmentEvent::MountSlewStarted {
                ra: ra_hours,
                dec: dec_degrees,
            },
            EventSeverity::Info,
        );

        tracing::info!(
            "Slewing mount {} to RA={:.4}h Dec={:.4}°",
            mount_id,
            ra_hours,
            dec_degrees
        );

        let result = mount_slew(mount_id.to_string(), ra_hours, dec_degrees)
            .await
            .map_err(|e| format!("Slew failed: {}", e));

        // Emit completion event on success
        if result.is_ok() {
            self.app_state.publish_equipment_event(
                EquipmentEvent::MountSlewCompleted {
                    ra: ra_hours,
                    dec: dec_degrees,
                },
                EventSeverity::Info,
            );
        }

        result
    }

    async fn mount_abort_slew(&self, mount_id: &str) -> DeviceResult<()> {
        tracing::info!("Aborting slew for mount {}", mount_id);

        mount_abort(mount_id.to_string())
            .await
            .map_err(|e| format!("Abort slew failed: {}", e))
    }

    async fn mount_get_coordinates(&self, mount_id: &str) -> DeviceResult<(f64, f64)> {
        mount_get_coordinates(mount_id.to_string())
            .await
            .map_err(|e| format!("Get coordinates failed: {}", e))
    }

    async fn mount_sync(
        &self,
        mount_id: &str,
        ra_hours: f64,
        dec_degrees: f64,
    ) -> DeviceResult<()> {
        tracing::info!(
            "Syncing mount {} to RA={:.4}h Dec={:.4}°",
            mount_id,
            ra_hours,
            dec_degrees
        );

        mount_sync(mount_id.to_string(), ra_hours, dec_degrees)
            .await
            .map_err(|e| format!("Sync failed: {}", e))
    }

    async fn mount_park(&self, mount_id: &str) -> DeviceResult<()> {
        // Emit start event
        self.app_state
            .publish_equipment_event(EquipmentEvent::MountParkStarted, EventSeverity::Info);

        tracing::info!("Parking mount {}", mount_id);

        let result = mount_park(mount_id.to_string())
            .await
            .map_err(|e| format!("Park failed: {}", e));

        // Emit completion event on success
        if result.is_ok() {
            self.app_state
                .publish_equipment_event(EquipmentEvent::MountParkCompleted, EventSeverity::Info);
        }

        result
    }

    async fn mount_unpark(&self, mount_id: &str) -> DeviceResult<()> {
        tracing::info!("Unparking mount {}", mount_id);

        let result = mount_unpark(mount_id.to_string())
            .await
            .map_err(|e| format!("Unpark failed: {}", e));

        // Emit event on success
        if result.is_ok() {
            self.app_state
                .publish_equipment_event(EquipmentEvent::MountUnparked, EventSeverity::Info);
        }

        result
    }

    async fn mount_is_slewing(&self, mount_id: &str) -> DeviceResult<bool> {
        let status = mount_get_status(mount_id.to_string())
            .await
            .map_err(|e| format!("Failed to get mount status: {}", e))?;

        Ok(status.slewing)
    }

    async fn mount_is_parked(&self, mount_id: &str) -> DeviceResult<bool> {
        let status = mount_get_status(mount_id.to_string())
            .await
            .map_err(|e| format!("Failed to get mount status: {}", e))?;

        Ok(status.parked)
    }

    async fn mount_can_flip(&self, mount_id: &str) -> DeviceResult<bool> {
        let status = mount_get_status(mount_id.to_string())
            .await
            .map_err(|e| format!("Failed to get mount status: {}", e))?;

        if !status.can_slew {
            return Ok(false);
        }
        // None (driver couldn't read or doesn't support pier side) is treated
        // identically to Unknown — both prevent a safe meridian flip.
        match status.side_of_pier {
            None | Some(crate::device::PierSide::Unknown) => Err(
                "Mount does not report side-of-pier state; flip capability cannot be determined"
                    .to_string(),
            ),
            Some(_) => Ok(true),
        }
    }

    async fn mount_side_of_pier(
        &self,
        mount_id: &str,
    ) -> DeviceResult<nightshade_sequencer::meridian::PierSide> {
        let status = mount_get_status(mount_id.to_string())
            .await
            .map_err(|e| format!("Failed to get mount status: {}", e))?;

        // Convert from bridge PierSide to sequencer PierSide.
        // None collapses to Unknown so the meridian module sees the same
        // "indeterminate" signal regardless of whether the driver reported
        // Unknown or failed to read at all.
        use crate::device::PierSide as BridgePierSide;
        use nightshade_sequencer::meridian::PierSide as SeqPierSide;

        Ok(match status.side_of_pier {
            Some(BridgePierSide::East) => SeqPierSide::East,
            Some(BridgePierSide::West) => SeqPierSide::West,
            Some(BridgePierSide::Unknown) | None => SeqPierSide::Unknown,
        })
    }

    async fn mount_is_tracking(&self, mount_id: &str) -> DeviceResult<bool> {
        let status = mount_get_status(mount_id.to_string())
            .await
            .map_err(|e| format!("Failed to get mount status: {}", e))?;

        Ok(status.tracking)
    }

    async fn mount_set_tracking(&self, mount_id: &str, enabled: bool) -> DeviceResult<()> {
        tracing::info!(
            "Setting tracking {} for mount {}",
            if enabled { "on" } else { "off" },
            mount_id
        );

        let result = mount_set_tracking(mount_id.to_string(), if enabled { 1 } else { 0 })
            .await
            .map_err(|e| format!("Set tracking failed: {}", e));

        // Emit event on success
        if result.is_ok() {
            self.app_state.publish_equipment_event(
                if enabled {
                    EquipmentEvent::MountTrackingStarted
                } else {
                    EquipmentEvent::MountTrackingStopped
                },
                EventSeverity::Info,
            );
        }

        result
    }

    // =========================================================================
    // CAMERA OPERATIONS
    // =========================================================================

    async fn camera_start_exposure(
        &self,
        camera_id: &str,
        duration_secs: f64,
        gain: Option<i32>,
        offset: Option<i32>,
        bin_x: i32,
        bin_y: i32,
    ) -> DeviceResult<ImageData> {
        // Frame-type-agnostic entry point → Light. Dark/bias flows through the
        // frame-type-aware method below (shared body).
        self.camera_start_exposure_with_frame_type(
            camera_id,
            duration_secs,
            gain,
            offset,
            bin_x,
            bin_y,
            "Light",
        )
        .await
    }

    async fn camera_start_exposure_with_frame_type(
        &self,
        camera_id: &str,
        duration_secs: f64,
        gain: Option<i32>,
        offset: Option<i32>,
        bin_x: i32,
        bin_y: i32,
        frame_type: &str,
    ) -> DeviceResult<ImageData> {
        tracing::info!(
            "Starting {:.1}s exposure on camera {}",
            duration_secs,
            camera_id
        );

        // Use UnifiedDeviceOps directly to get image data without going through global storage.
        // This eliminates the race condition where concurrent exposures from different cameras
        // could overwrite each other's data in the global LAST_RAW_IMAGE_INFO storage.
        let unified_ops = create_unified_device_ops();
        let image_data = unified_ops
            .camera_start_exposure_with_frame_type(
                camera_id,
                duration_secs,
                gain,
                offset,
                bin_x,
                bin_y,
                frame_type,
            )
            .await?;

        // Validate the raw data
        let expected_size = (image_data.width as usize) * (image_data.height as usize);
        if image_data.data.len() != expected_size {
            return Err(format!(
                "Image data size mismatch: got {} pixels, expected {} ({}x{})",
                image_data.data.len(),
                expected_size,
                image_data.width,
                image_data.height
            ));
        }

        // Check for obviously bad frames - but allow bias frames which legitimately have
        // nearly uniform data. We allow up to 10 differing pixels for bias frame tolerance.
        if !image_data.data.is_empty() {
            let first_val = image_data.data[0];
            let differing_count = image_data.data.iter().filter(|&&v| v != first_val).count();

            // If ALL pixels are identical, it's likely a sensor failure or dead frame
            // But if only a few pixels differ (< 10), it could be a valid bias frame
            if differing_count == 0 {
                tracing::warn!(
                    "Suspicious image: all {} pixels have identical value {} - possible sensor failure or bias frame",
                    image_data.data.len(), first_val
                );
                // For bias frames with 0-second exposure, this is expected - don't error
                // Only error for longer exposures where uniform data indicates a problem
                if duration_secs > 0.1 {
                    return Err(format!(
                        "Invalid image: all {} pixels have identical value {} - possible sensor failure or dead frame",
                        image_data.data.len(), first_val
                    ));
                }
            }
        }

        tracing::info!(
            "Raw image captured: {}x{}, {} pixels, sensor_type={:?}, bayer_offset={:?}",
            image_data.width,
            image_data.height,
            image_data.data.len(),
            image_data.sensor_type,
            image_data.bayer_offset
        );

        Ok(image_data)
    }

    async fn camera_abort_exposure(&self, camera_id: &str) -> DeviceResult<()> {
        tracing::info!("Aborting exposure on camera {}", camera_id);

        cancel_exposure(camera_id.to_string())
            .await
            .map_err(|e| format!("Abort failed: {}", e))
    }

    async fn camera_set_cooler(
        &self,
        camera_id: &str,
        enabled: bool,
        target_temp: f64,
    ) -> DeviceResult<()> {
        // Emit event before starting
        self.app_state.publish_equipment_event(
            if enabled {
                EquipmentEvent::CameraCoolingStarted { target_temp }
            } else {
                EquipmentEvent::CameraWarmingStarted
            },
            EventSeverity::Info,
        );

        tracing::info!(
            "Camera {} cooler: enabled={}, target={}°C",
            camera_id,
            enabled,
            target_temp
        );

        set_camera_cooler(camera_id.to_string(), enabled as u8, Some(target_temp))
            .await
            .map_err(|e| format!("Cooler control failed: {}", e))
    }

    async fn camera_get_temperature(&self, camera_id: &str) -> DeviceResult<f64> {
        let status = get_camera_status(camera_id.to_string())
            .await
            .map_err(|e| format!("Failed to get camera status: {}", e))?;

        status
            .sensor_temp
            .ok_or_else(|| "Temperature not available".to_string())
    }

    async fn camera_get_cooler_power(&self, camera_id: &str) -> DeviceResult<f64> {
        let status = get_camera_status(camera_id.to_string())
            .await
            .map_err(|e| format!("Failed to get camera status: {}", e))?;

        status
            .cooler_power
            .ok_or_else(|| "Cooler power not available".to_string())
    }

    async fn camera_get_pixel_size_um(&self, camera_id: &str) -> DeviceResult<Option<(f64, f64)>> {
        let status = get_camera_status(camera_id.to_string())
            .await
            .map_err(|e| format!("Failed to get camera status: {}", e))?;

        // A driver with nothing to say reports 0.0 here, which is not a pitch —
        // writing it would tell a solver the sensor has zero-sized pixels.
        Ok(match (status.pixel_size_x, status.pixel_size_y) {
            (x, y) if x > 0.0 && y > 0.0 => Some((x, y)),
            _ => None,
        })
    }

    async fn camera_get_model(&self, camera_id: &str) -> DeviceResult<Option<String>> {
        Ok(connected_camera_label(camera_id).await)
    }

    // =========================================================================
    // FOCUSER OPERATIONS
    // =========================================================================

    async fn focuser_move_to(&self, focuser_id: &str, position: i32) -> DeviceResult<()> {
        // Emit start event
        self.app_state.publish_equipment_event(
            EquipmentEvent::FocuserMoveStarted {
                target_position: position,
            },
            EventSeverity::Info,
        );

        tracing::info!("Moving focuser {} to position {}", focuser_id, position);

        let result = focuser_move_abs(focuser_id.to_string(), position)
            .await
            .map_err(|e| format!("Focuser move failed: {}", e));

        // Emit completion event on success
        if result.is_ok() {
            self.app_state.publish_equipment_event(
                EquipmentEvent::FocuserMoveCompleted { position },
                EventSeverity::Info,
            );
        }

        result
    }

    async fn focuser_get_position(&self, focuser_id: &str) -> DeviceResult<i32> {
        let pos = focuser_get_position(focuser_id.to_string())
            .await
            .map_err(|e| format!("Failed to get focuser position: {}", e))?;

        Ok(pos)
    }

    async fn focuser_is_moving(&self, focuser_id: &str) -> DeviceResult<bool> {
        let status = api_get_focuser_status(focuser_id.to_string())
            .await
            .map_err(|e| format!("Failed to get focuser status: {}", e))?;

        Ok(status.moving)
    }

    async fn focuser_get_temperature(&self, focuser_id: &str) -> DeviceResult<Option<f64>> {
        focuser_get_temp(focuser_id.to_string())
            .await
            .map_err(|e| format!("Failed to get focuser temp: {}", e))
    }

    async fn focuser_halt(&self, focuser_id: &str) -> DeviceResult<()> {
        tracing::info!("Halting focuser {}", focuser_id);

        focuser_halt(focuser_id.to_string())
            .await
            .map_err(|e| format!("Halt failed: {}", e))
    }

    // =========================================================================
    // FILTER WHEEL OPERATIONS
    // =========================================================================

    async fn filterwheel_set_position(&self, fw_id: &str, position: i32) -> DeviceResult<()> {
        // Get current position for event
        let from_position = match filter_wheel_get_position(fw_id.to_string()).await {
            Ok(position) => position,
            Err(err) => {
                tracing::warn!(
                    "Unable to read current filter wheel position for {} before change: {}",
                    fw_id,
                    err
                );
                -1
            }
        };

        // Emit changing event
        self.app_state.publish_equipment_event(
            EquipmentEvent::FilterChanging {
                from_position,
                to_position: position,
                filter_name: None,
            },
            EventSeverity::Info,
        );

        tracing::info!("Setting filter wheel {} to position {}", fw_id, position);

        let result = filter_wheel_set_position(fw_id.to_string(), position)
            .await
            .map_err(|e| format!("Filter change failed: {}", e));

        // Emit changed event on success
        if result.is_ok() {
            self.app_state.publish_equipment_event(
                EquipmentEvent::FilterChanged {
                    position,
                    filter_name: None,
                },
                EventSeverity::Info,
            );
        }

        result
    }

    async fn filterwheel_get_position(&self, fw_id: &str) -> DeviceResult<i32> {
        filter_wheel_get_position(fw_id.to_string())
            .await
            .map_err(|e| format!("Failed to get filter wheel position: {}", e))
    }

    async fn filterwheel_get_names(&self, fw_id: &str) -> DeviceResult<Vec<String>> {
        let (_, names) = filter_wheel_get_config(fw_id.to_string())
            .await
            .map_err(|e| format!("Failed to get filter wheel config: {}", e))?;

        Ok(names)
    }

    async fn filterwheel_set_filter_by_name(&self, fw_id: &str, name: &str) -> DeviceResult<i32> {
        let names = self.filterwheel_get_names(fw_id).await?;
        tracing::info!(
            "filterwheel_set_filter_by_name: Looking for '{}' in available filters: {:?}",
            name,
            names
        );

        // Find the filter position by name (case-insensitive)
        // INDI filter slots are 1-based; ASCOM/Alpaca/Native use 0-based positions
        let position = find_filter_match(&names, name)
            .map(|p| {
                if fw_id.starts_with("indi:") {
                    (p + 1) as i32
                } else {
                    p as i32
                }
            })
            .ok_or_else(|| format!("Filter '{}' not found. Available: {:?}", name, names))?;

        self.filterwheel_set_position(fw_id, position).await?;
        Ok(position)
    }

    // =========================================================================
    // ROTATOR OPERATIONS
    // =========================================================================

    async fn rotator_move_to(&self, rotator_id: &str, angle: f64) -> DeviceResult<()> {
        // Emit start event
        self.app_state.publish_equipment_event(
            EquipmentEvent::RotatorMoveStarted {
                target_angle: angle,
            },
            EventSeverity::Info,
        );

        tracing::info!("Moving rotator {} to {}°", rotator_id, angle);

        let result = api_rotator_move_to(rotator_id.to_string(), angle)
            .await
            .map_err(|e| format!("Rotator move failed: {}", e));

        // Emit completion event on success
        if result.is_ok() {
            self.app_state.publish_equipment_event(
                EquipmentEvent::RotatorMoveCompleted { angle },
                EventSeverity::Info,
            );
        }

        result
    }

    async fn rotator_move_relative(&self, rotator_id: &str, delta: f64) -> DeviceResult<()> {
        tracing::info!("Moving rotator {} by {}°", rotator_id, delta);

        api_rotator_move_relative(rotator_id.to_string(), delta)
            .await
            .map_err(|e| format!("Rotator relative move failed: {}", e))
    }

    async fn rotator_get_angle(&self, rotator_id: &str) -> DeviceResult<f64> {
        let status = api_get_rotator_status(rotator_id.to_string())
            .await
            .map_err(|e| format!("Failed to get rotator status: {}", e))?;

        Ok(status.position)
    }

    async fn rotator_halt(&self, rotator_id: &str) -> DeviceResult<()> {
        tracing::info!("Halting rotator {}", rotator_id);

        api_rotator_halt(rotator_id.to_string())
            .await
            .map_err(|e| format!("Rotator halt failed: {}", e))
    }

    // =========================================================================
    // GUIDING / PHD2 OPERATIONS
    // =========================================================================

    async fn guider_dither(
        &self,
        pixels: f64,
        settle_pixels: f64,
        settle_time: f64,
        settle_timeout: f64,
        ra_only: bool,
    ) -> DeviceResult<()> {
        tracing::info!(
            "Dithering {} pixels (settle: <{}px in {}s)",
            pixels,
            settle_pixels,
            settle_time
        );

        let guider_id = get_active_guider_id_for_ops()
            .await
            .ok_or_else(|| "No active guider configured".to_string())?;
        api_guider_dither(
            guider_id,
            pixels,
            ra_only as u8,
            settle_pixels,
            settle_time,
            settle_timeout,
        )
        .await
        .map_err(|e| format!("Dither failed: {}", e))
    }

    async fn guider_get_status(&self) -> DeviceResult<GuidingStatus> {
        let guider_id = get_active_guider_id_for_ops()
            .await
            .ok_or_else(|| "No active guider configured".to_string())?;
        let status = api_guider_get_status(guider_id)
            .await
            .map_err(|e| format!("Failed to get guider status: {}", e))?;

        Ok(GuidingStatus {
            is_guiding: status.state == "Guiding",
            rms_ra: status.rms_ra,
            rms_dec: status.rms_dec,
            rms_total: status.rms_total,
        })
    }

    async fn guider_get_calibration(&self) -> DeviceResult<GuidingCalibration> {
        let guider_id = get_active_guider_id_for_ops()
            .await
            .ok_or_else(|| "No active guider configured".to_string())?;
        let calib = crate::api::phd2::api_guider_get_calibration(guider_id)
            .await
            .map_err(|e| format!("Failed to get guider calibration: {}", e))?;
        Ok(GuidingCalibration {
            is_calibrated: calib.is_calibrated,
            ra_angle_deg: calib.ra_angle,
            dec_angle_deg: calib.dec_angle,
        })
    }

    async fn guider_start(
        &self,
        settle_pixels: f64,
        settle_time: f64,
        settle_timeout: f64,
    ) -> DeviceResult<()> {
        tracing::info!(
            "Starting guiding (settle: <{}px in {}s, timeout {}s)",
            settle_pixels,
            settle_time,
            settle_timeout
        );

        let guider_id = get_active_guider_id_for_ops()
            .await
            .ok_or_else(|| "No active guider configured".to_string())?;
        api_guider_start_guiding(guider_id, settle_pixels, settle_time, settle_timeout)
            .await
            .map_err(|e| format!("Start guiding failed: {}", e))
    }

    async fn guider_stop(&self) -> DeviceResult<()> {
        tracing::info!("Stopping guiding");

        let guider_id = get_active_guider_id_for_ops()
            .await
            .ok_or_else(|| "No active guider configured".to_string())?;
        api_guider_stop(guider_id)
            .await
            .map_err(|e| format!("Stop guiding failed: {}", e))
    }

    // =========================================================================
    // PLATE SOLVING
    // =========================================================================

    async fn plate_solve(
        &self,
        image_data: &ImageData,
        hint_ra: Option<f64>,
        hint_dec: Option<f64>,
        hint_scale: Option<f64>,
    ) -> DeviceResult<PlateSolveResult> {
        tracing::info!("Plate solving image");

        let temp_file = create_unique_temp_fits_path("nightshade_platesolve_temp");
        let temp_path = temp_file.to_string_lossy().to_string();

        // Convert to imaging::ImageData
        let img = nightshade_imaging::ImageData::from_u16(
            image_data.width,
            image_data.height,
            1, // Raw FITS input is single-plane (mono or Bayer mosaic)
            &image_data.data,
        );

        // Create header
        let mut header = nightshade_imaging::FitsHeader::new();
        header.set_float("EXPTIME", image_data.exposure_secs);
        if let Some(gain) = image_data.gain {
            header.set_int("GAIN", gain as i64);
        }
        if let Some(offset) = image_data.offset {
            header.set_int("OFFSET", offset as i64);
        }
        if let Some(temp) = image_data.temperature {
            header.set_float("CCD-TEMP", temp);
        }
        if let Some(ra) = hint_ra {
            header.set_float("RA", ra / 15.0); // Hours
        }
        if let Some(dec) = hint_dec {
            header.set_float("DEC", dec);
        }
        if let Some(scale) = hint_scale {
            // Do not synthesize focal length from an assumed pixel size.
            // Preserve the caller-provided scale hint without adding inferred metadata.
            header.set_float("SCALE", scale);
        }

        // The optics, so the solver knows the field scale.
        //
        // Without these cards the temp FITS carries no scale information at
        // all, and ASTAP falls back to sweeping the field of view downward
        // from ~9.5° — which turns a 0.3-second solve into a multi-second
        // search that only sometimes reaches the right scale. Observed live:
        // the same target solved on one run ("Warning scale was inaccurate!
        // Set FOV=0.23d") and exited non-zero on the next, having never got
        // below 2.8°. These are measured values, not assumptions: the focal
        // length is the operator's own profile entry and the pixel pitch is
        // what the camera reports, so nothing is inferred here — a device
        // that reports no pitch simply contributes no card.
        let mut focal_length_written: Option<f64> = None;
        let mut pixel_pitch_written: Option<f64> = None;
        if let Some(profile) = crate::get_state().get_profile().await {
            let focal_length_mm = profile.telescope_focal_length;
            if focal_length_mm.is_finite() && focal_length_mm > 0.0 {
                header.set_float("FOCALLEN", focal_length_mm);
                focal_length_written = Some(focal_length_mm);
            }

            if let Some(camera_id) = profile.camera_id.as_deref() {
                match get_camera_status(camera_id.to_string()).await {
                    Ok(status) => {
                        // 0.0 is a driver saying "I don't know", not a pitch.
                        if status.pixel_size_x > 0.0 && status.pixel_size_y > 0.0 {
                            header.set_float("XPIXSZ", status.pixel_size_x);
                            header.set_float("YPIXSZ", status.pixel_size_y);
                            header.set_float("PIXSIZE1", status.pixel_size_x);
                            header.set_float("PIXSIZE2", status.pixel_size_y);
                            pixel_pitch_written = Some(status.pixel_size_x);
                        }
                        // Binning matters: XPIXSZ above is the unbinned pitch,
                        // so a binned frame's scale is only right if the solver
                        // is told the binning too.
                        if status.bin_x > 0 && status.bin_y > 0 {
                            header.set_int("XBINNING", i64::from(status.bin_x));
                            header.set_int("YBINNING", i64::from(status.bin_y));
                        }
                    }
                    Err(e) => {
                        tracing::debug!(
                            "Plate solve: camera '{}' status unavailable ({}); solving without \
                             a pixel-scale hint",
                            camera_id,
                            e
                        );
                    }
                }
            }
        }

        // Say out loud whether the solver is getting a scale or is about to
        // sweep for one. A blind sweep is not an error and produces no warning
        // of its own, so without this line the slow, unreliable case and the
        // fast, reliable case look identical in the log.
        match (focal_length_written, pixel_pitch_written) {
            (Some(focal), Some(pitch)) => tracing::info!(
                "Plate solve scale hint: focal length {:.1} mm, pixel pitch {:.2} µm \
                 ({:.2}\"/px unbinned)",
                focal,
                pitch,
                206.264_806 * pitch / focal
            ),
            _ => tracing::warn!(
                "Plate solve has no field-scale hint (focal length {}, pixel pitch {}); \
                 the solver must search for the scale, which is slower and can fail on a \
                 field it would otherwise solve. Set the telescope focal length on the \
                 active equipment profile.",
                focal_length_written
                    .map_or_else(|| "unknown".to_string(), |v| format!("{v:.1} mm")),
                pixel_pitch_written
                    .map_or_else(|| "unknown".to_string(), |v| format!("{v:.2} µm")),
            ),
        }

        // Save temp FITS
        nightshade_imaging::write_fits(std::path::Path::new(&temp_path), &img, &header)
            .map_err(|e| format!("Failed to save temp FITS: {}", e))?;

        tracing::info!("Saved temp FITS for plate solving: {}", temp_path);

        // Run solver
        let result = if let (Some(ra), Some(dec)) = (hint_ra, hint_dec) {
            nightshade_imaging::solve_near(
                std::path::Path::new(&temp_path),
                ra,
                dec,
                5.0, // 5 degree search radius
            )
        } else {
            nightshade_imaging::blind_solve(std::path::Path::new(&temp_path))
        };

        // Clean up
        let _ = std::fs::remove_file(&temp_path);

        let r = result; // No need to map error, it returns PlateSolveResult directly

        if r.success {
            Ok(PlateSolveResult {
                ra_degrees: r.ra,
                dec_degrees: r.dec,
                pixel_scale: r.pixel_scale,
                rotation: r.rotation,
                success: true,
            })
        } else {
            tracing::warn!("Plate solve failed: {:?}", r.error);
            Err(r
                .error
                .unwrap_or_else(|| "Unknown plate solve error".to_string()))
        }
    }

    // =========================================================================
    // IMAGE SAVING
    // =========================================================================

    async fn save_fits(
        &self,
        image_data: &ImageData,
        file_path: &str,
        frame_ctx: &nightshade_sequencer::scheduling::FrameContext,
    ) -> DeviceResult<()> {
        tracing::info!(
            "Saving FITS image to: {} ({})",
            file_path,
            frame_ctx.log_label()
        );

        // Only ask the mount when the caller did not already sample it. A
        // sequencer frame arrives with the pointing on its `FrameContext`, and
        // re-reading here would both cost a driver round-trip per saved frame
        // and re-open the gap this whole path exists to close — two reads of a
        // moving mount, taken at different instants, disagreeing about one
        // frame. What such a frame CAN still be missing is the derived
        // altitude, which app settings can supply even when the sequencer's own
        // location seed could not.
        // The horizon frame is evaluated at the EXPOSURE MIDPOINT, not at save
        // time: this runs after readout, so `Utc::now()` here dated the
        // altitude — and therefore AIRMASS — by the whole exposure plus
        // download. See `FrameContext::exposure_midpoint`. Frames that never
        // recorded a shutter-open instant fall back to the clock, which is no
        // worse than before.
        let sky_epoch = frame_ctx
            .exposure_midpoint()
            .unwrap_or_else(chrono::Utc::now);
        let pointing = if frame_ctx.mount_ra_hours.is_some() {
            context_altitude_pointing(frame_ctx, self.get_observer_location(), sky_epoch)
        } else {
            self.read_mount_pointing(sky_epoch).await
        };
        let header = build_rich_header(image_data, frame_ctx, pointing);

        crate::api::save_fits_file_rich(
            file_path.to_string(),
            image_data.width,
            image_data.height,
            image_data.data.clone(),
            header,
        )
        .await
        .map_err(|e| format!("Save FITS failed: {}", e))
    }

    // =========================================================================
    // NOTIFICATIONS
    // =========================================================================

    async fn send_notification(
        &self,
        level: &str,
        title: &str,
        message: &str,
        explicit_transports: Option<&[String]>,
    ) -> DeviceResult<()> {
        tracing::info!(
            "[NOTIFICATION][{}] {}: {}",
            level.to_uppercase(),
            title,
            message
        );

        // Publish as event to the event bus
        use crate::event::*;

        let severity = match level {
            "error" => EventSeverity::Error,
            "warning" => EventSeverity::Warning,
            _ => EventSeverity::Info,
        };

        self.app_state.publish_event(create_event_auto_id(
            severity,
            EventCategory::System,
            EventPayload::System(SystemEvent::Notification {
                title: title.to_string(),
                message: message.to_string(),
                level: level.to_string(),
                explicit_transports: explicit_transports.map(|s| s.to_vec()),
            }),
        ));

        Ok(())
    }

    async fn polar_align_update(
        &self,
        result: &nightshade_sequencer::PolarAlignResult,
    ) -> DeviceResult<()> {
        tracing::info!(
            "Polar Align Update: Alt {:.1}', Az {:.1}'",
            result.altitude_error,
            result.azimuth_error
        );

        use crate::event::*;

        let event = PolarAlignmentEvent {
            azimuth_error: result.azimuth_error,
            altitude_error: result.altitude_error,
            total_error: result.total_error,
            current_ra: result.current_ra,
            current_dec: result.current_dec,
            target_ra: result.target_ra,
            target_dec: result.target_dec,
        };

        self.app_state.publish_event(create_event_auto_id(
            EventSeverity::Info,
            EventCategory::PolarAlignment,
            EventPayload::PolarAlignment(event),
        ));

        Ok(())
    }

    // =========================================================================
    // DOME OPERATIONS
    // =========================================================================

    /// The sequencer's dome/cover role slots are never populated (see
    /// `DeviceOps::active_dome_id`), so answer with whatever is connected —
    /// the same first-connected lookup `resolve_safety_device_id` uses.
    async fn active_dome_id(&self) -> Option<String> {
        get_device_manager()
            .first_connected_device_id(DeviceType::Dome)
            .await
    }

    async fn active_cover_calibrator_id(&self) -> Option<String> {
        get_device_manager()
            .first_connected_device_id(DeviceType::CoverCalibrator)
            .await
    }

    async fn dome_open(&self, dome_id: &str) -> DeviceResult<()> {
        tracing::info!("Opening dome shutter {}", dome_id);

        get_device_manager()
            .dome_open_shutter(dome_id)
            .await
            .map_err(|e| format!("Open dome shutter failed: {}", e))
    }

    async fn dome_close(&self, dome_id: &str) -> DeviceResult<()> {
        tracing::info!("Closing dome shutter {}", dome_id);

        get_device_manager()
            .dome_close_shutter(dome_id)
            .await
            .map_err(|e| format!("Close dome shutter failed: {}", e))
    }

    async fn dome_park(&self, dome_id: &str) -> DeviceResult<()> {
        tracing::info!("Parking dome {}", dome_id);

        get_device_manager()
            .dome_park(dome_id)
            .await
            .map_err(|e| format!("Park dome failed: {}", e))
    }

    async fn dome_get_shutter_status(&self, dome_id: &str) -> DeviceResult<String> {
        let status = get_device_manager()
            .dome_get_shutter_status(dome_id)
            .await
            .map_err(|e| format!("Get dome shutter status failed: {}", e))?;

        // Convert i32 status to string
        // ASCOM ShutterStatus: 0=Open, 1=Closed, 2=Opening, 3=Closing, 4=Error
        Ok(match status {
            0 => "Open".to_string(),
            1 => "Closed".to_string(),
            2 => "Opening".to_string(),
            3 => "Closing".to_string(),
            _ => "Error".to_string(),
        })
    }

    // =========================================================================
    // UTILITY
    // =========================================================================

    fn calculate_altitude(&self, ra_hours: f64, dec_degrees: f64, lat: f64, lon: f64) -> f64 {
        altitude_degrees(ra_hours, dec_degrees, lat, lon, chrono::Utc::now())
    }

    fn get_observer_location(&self) -> Option<(f64, f64)> {
        // Get observer location from app settings
        match self.app_state.get_observer_location() {
            Ok(Some(location)) => {
                tracing::debug!(
                    "Observer location retrieved: lat={}, lon={}",
                    location.latitude,
                    location.longitude
                );
                Some((location.latitude, location.longitude))
            }
            Ok(None) => {
                tracing::debug!("Observer location not set in settings, will retry");
                None
            }
            Err(e) => {
                tracing::warn!("Failed to get observer location: {}", e);
                None
            }
        }
    }

    async fn safety_is_safe(&self, safety_id: Option<&str>) -> DeviceResult<bool> {
        // Prefer a connected SafetyMonitor device. Equipment profiles still
        // only store weather_id, so weather remains a fallback rather than the
        // primary safety source.
        let device_id = self.resolve_safety_device_id(safety_id).await?;

        tracing::debug!("Checking safety status for device: {}", device_id);

        // Route through DeviceManager for all driver types.
        match get_device_manager().safety_is_safe(&device_id).await {
            Ok(is_safe) => {
                tracing::info!(
                    "Safety monitor {} reports: {}",
                    device_id,
                    if is_safe { "SAFE" } else { "UNSAFE" }
                );
                Ok(is_safe)
            }
            Err(e) => Err(format!("Safety check failed for {}: {}", device_id, e)),
        }
    }

    /// Trust-patch §2: feed `HumidityThreshold` triggers with live humidity
    /// from the configured weather/observatory device. Routes through the
    /// same DeviceManager `weather_get_conditions` call the bridge already
    /// exposes — we just project the humidity field. Returns:
    ///   * `Ok(Some(value))` when the weather device reports humidity
    ///   * `Ok(None)`         when the device exists but does not advertise humidity
    ///   * `Err(_)`           when no weather device is configured or the
    ///                        DeviceManager call fails (the trigger monitor
    ///                        retains the previous reading on Err).
    async fn weather_get_humidity(&self, weather_id: Option<&str>) -> DeviceResult<Option<f64>> {
        let device_id = match weather_id {
            Some(id) => id.to_string(),
            None => {
                let profile = self.app_state.get_profile().await;
                match profile.and_then(|p| p.weather_id) {
                    Some(id) => id,
                    None => {
                        // No configured weather device — humidity polling is
                        // a no-op rather than an error so the trigger monitor
                        // doesn't log every tick on an undeployed device.
                        return Ok(None);
                    }
                }
            }
        };

        match get_device_manager()
            .weather_get_conditions(&device_id)
            .await
        {
            Ok(conditions) => Ok(conditions.humidity),
            Err(e) => Err(format!("Humidity poll failed for {}: {}", device_id, e)),
        }
    }

    // =========================================================================
    // IMAGE ANALYSIS
    // =========================================================================

    async fn calculate_image_hfr(&self, image_data: &ImageData) -> DeviceResult<Option<f64>> {
        // Use nightshade_imaging to calculate HFR
        let img = nightshade_imaging::ImageData::from_u16(
            image_data.width,
            image_data.height,
            1,
            &image_data.data,
        );

        let config = nightshade_imaging::StarDetectionConfig::default();
        let stars = nightshade_imaging::detect_stars(&img, &config);

        if stars.is_empty() {
            return Ok(None);
        }

        // Calculate average HFR
        let total_hfr: f64 = stars.iter().map(|s| s.hfr).sum();
        let avg_hfr = total_hfr / stars.len() as f64;

        Ok(Some(avg_hfr))
    }

    async fn detect_stars_in_image(
        &self,
        image_data: &ImageData,
    ) -> DeviceResult<Vec<(f64, f64, f64)>> {
        // Use nightshade_imaging to detect stars
        let img = nightshade_imaging::ImageData::from_u16(
            image_data.width,
            image_data.height,
            1,
            &image_data.data,
        );

        let config = nightshade_imaging::StarDetectionConfig::default();
        let stars = nightshade_imaging::detect_stars(&img, &config);

        // Convert to (x, y, hfr) tuples
        let result: Vec<(f64, f64, f64)> = stars.iter().map(|s| (s.x, s.y, s.hfr)).collect();

        Ok(result)
    }

    async fn measure_frame_eccentricity(
        &self,
        image_data: &ImageData,
    ) -> DeviceResult<Option<f64>> {
        let img = nightshade_imaging::ImageData::from_u16(
            image_data.width,
            image_data.height,
            1,
            &image_data.data,
        );

        let config = nightshade_imaging::StarDetectionConfig::default();
        let stars = nightshade_imaging::detect_stars(&img, &config);

        // Fails closed (None) when too few reliable stars — never fabricated.
        Ok(nightshade_imaging::frame_eccentricity(&stars))
    }

    // =========================================================================
    // COVER CALIBRATOR (FLAT PANEL) OPERATIONS
    // =========================================================================

    async fn cover_calibrator_open_cover(&self, device_id: &str) -> DeviceResult<()> {
        tracing::info!("Opening cover calibrator cover: {}", device_id);
        api_cover_calibrator_open_cover(device_id.to_string())
            .await
            .map_err(|e| format!("Open cover failed: {}", e))
    }

    async fn cover_calibrator_close_cover(&self, device_id: &str) -> DeviceResult<()> {
        tracing::info!("Closing cover calibrator cover: {}", device_id);
        api_cover_calibrator_close_cover(device_id.to_string())
            .await
            .map_err(|e| format!("Close cover failed: {}", e))
    }

    async fn cover_calibrator_halt_cover(&self, device_id: &str) -> DeviceResult<()> {
        tracing::info!("Halting cover calibrator cover: {}", device_id);
        api_cover_calibrator_halt_cover(device_id.to_string())
            .await
            .map_err(|e| format!("Halt cover failed: {}", e))
    }

    async fn cover_calibrator_calibrator_on(
        &self,
        device_id: &str,
        brightness: i32,
    ) -> DeviceResult<()> {
        tracing::info!(
            "Turning on calibrator {} at brightness {}",
            device_id,
            brightness
        );
        api_cover_calibrator_calibrator_on(device_id.to_string(), brightness)
            .await
            .map_err(|e| format!("Calibrator on failed: {}", e))
    }

    async fn cover_calibrator_calibrator_off(&self, device_id: &str) -> DeviceResult<()> {
        tracing::info!("Turning off calibrator {}", device_id);
        api_cover_calibrator_calibrator_off(device_id.to_string())
            .await
            .map_err(|e| format!("Calibrator off failed: {}", e))
    }

    async fn cover_calibrator_get_cover_state(&self, device_id: &str) -> DeviceResult<i32> {
        api_cover_calibrator_get_cover_state(device_id.to_string())
            .await
            .map_err(|e| format!("Get cover state failed: {}", e))
    }

    async fn cover_calibrator_get_calibrator_state(&self, device_id: &str) -> DeviceResult<i32> {
        api_cover_calibrator_get_calibrator_state(device_id.to_string())
            .await
            .map_err(|e| format!("Get calibrator state failed: {}", e))
    }

    async fn cover_calibrator_get_brightness(&self, device_id: &str) -> DeviceResult<i32> {
        api_cover_calibrator_get_brightness(device_id.to_string())
            .await
            .map_err(|e| format!("Get brightness failed: {}", e))
    }

    async fn cover_calibrator_get_max_brightness(&self, device_id: &str) -> DeviceResult<i32> {
        api_cover_calibrator_get_max_brightness(device_id.to_string())
            .await
            .map_err(|e| format!("Get max brightness failed: {}", e))
    }
}

/// Calculate Julian Day from UTC datetime
fn julian_day(dt: chrono::DateTime<chrono::Utc>) -> f64 {
    use chrono::{Datelike, Timelike};

    let year = dt.year();
    let month = dt.month() as i32;
    let day = dt.day() as f64;
    let hour = dt.hour() as f64 + dt.minute() as f64 / 60.0 + dt.second() as f64 / 3600.0;

    let (y, m) = if month <= 2 {
        (year - 1, month + 12)
    } else {
        (year, month)
    };

    let a = (y as f64 / 100.0).floor();
    let b = 2.0 - a + (a / 4.0).floor();

    (365.25 * (y + 4716) as f64).floor()
        + (30.6001 * (m + 1) as f64).floor()
        + day
        + hour / 24.0
        + b
        - 1524.5
}

/// Calculate Local Sidereal Time in hours
fn local_sidereal_time(jd: f64, longitude: f64) -> f64 {
    let t = (jd - 2451545.0) / 36525.0;

    // Greenwich Mean Sidereal Time
    let gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t
        - t * t * t / 38710000.0;

    let lst = (gmst + longitude) % 360.0;
    if lst < 0.0 {
        (lst + 360.0) / 15.0
    } else {
        lst / 15.0
    }
}

/// Create a BridgeDeviceOps from the global app state
pub fn create_device_ops() -> Arc<dyn nightshade_sequencer::DeviceOps> {
    Arc::new(BridgeDeviceOps::new(crate::api::get_state().clone()))
}

#[cfg(test)]
mod pointing_tests {
    use super::{altitude_degrees, build_rich_header, context_altitude_pointing, MountPointing};
    use nightshade_imaging::read_fits;
    use nightshade_sequencer::scheduling::FrameContext;
    use nightshade_sequencer::ImageData;
    use std::path::{Path, PathBuf};

    /// Scratch directory that removes itself even when a test panics.
    struct TempDir(PathBuf);

    impl AsRef<Path> for TempDir {
        fn as_ref(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn temp_scratch_dir(tag: &str) -> TempDir {
        let p = std::env::temp_dir().join(format!(
            "ns_seqops_{}_{}_{}",
            tag,
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&p).unwrap();
        TempDir(p)
    }

    fn tiny_frame() -> ImageData {
        ImageData {
            width: 4,
            height: 4,
            data: vec![0u16; 16],
            bits_per_pixel: 16,
            exposure_secs: 3.0,
            gain: Some(100),
            offset: Some(10),
            temperature: Some(20.0),
            filter: None,
            timestamp: 0,
            sensor_type: Some("Monochrome".to_string()),
            bayer_offset: None,
        }
    }

    /// The reported repro: a sequence with NO Target group (Slew to Target with
    /// custom coordinates) captured four lights whose FITS headers carried no
    /// RA, DEC, OBJCTRA or OBJCTDEC card at all — the night left no record of
    /// where the telescope was aimed. The mount's own report must fill them.
    #[tokio::test]
    async fn untargeted_frame_carries_the_mount_pointing() {
        let ctx = FrameContext::new_light("sess-untargeted", 1, 1, 3.0, 1);
        assert!(
            ctx.target_ra_hours.is_none() && ctx.target_dec_degrees.is_none(),
            "precondition: an untargeted run has no target coordinates to fall back on"
        );

        let header = build_rich_header(
            &tiny_frame(),
            &ctx,
            Some(MountPointing {
                ra_hours: 17.0,
                dec_degrees: 30.0,
                altitude_deg: Some(52.0),
            }),
        );

        let scratch = temp_scratch_dir("untargeted");
        let path = scratch.as_ref().join("untargeted_0001.fits");
        crate::api::save_fits_file_rich(
            path.to_string_lossy().to_string(),
            4,
            4,
            vec![0u16; 16],
            header,
        )
        .await
        .expect("FITS save should succeed");

        let (_image, parsed) = read_fits(&path).expect("FITS read-back should succeed");

        // The numeric RA card is degrees by universal convention; internal RA
        // is hours.
        let ra_deg = parsed.get_float("RA").expect("RA card must be present");
        assert!(
            (ra_deg - 17.0 * 15.0).abs() < 1e-6,
            "RA card should be the mount's 17h in degrees, got {ra_deg}"
        );
        assert_eq!(parsed.get_float("DEC"), Some(30.0));
        assert_eq!(parsed.get_string("OBJCTRA"), Some("17 00 00.00"));
        assert_eq!(parsed.get_string("OBJCTDEC"), Some("+30 00 00.00"));
        // Altitude rides along so AIRMASS becomes computable for sequenced
        // frames, which previously always lacked it.
        assert!(
            parsed.get_float("AIRMASS").is_some(),
            "AIRMASS should be derivable once the pointing carries an altitude"
        );
    }

    /// The rig frame, at the layer that actually wrote it.
    ///
    /// `Polaris_1_0001.fits` came out of `BridgeDeviceOps::save_fits`, which is
    /// `build_rich_header` plus a mount read — not `from_frame_context` alone.
    /// When no mount answers, `read_mount_pointing` returns `None` and NEITHER
    /// pointing branch below runs, so whatever `from_frame_context` derived is
    /// what reaches the file. That makes this function, not the constructor,
    /// the place where "a mountless frame keeps its altitude" is either true or
    /// silently undone by a later assignment.
    ///
    /// Reproduced on hardware before this was written: the real file carried
    /// `SITELAT 39.97190`, `RA 37.95450`, `DEC 89.264` and neither horizon
    /// keyword, and a camera-only run against the Linux build wrote the same
    /// header shape.
    ///
    /// Dec 90° is deliberate: the celestial pole sits at the observer's
    /// latitude for every hour angle, at every longitude, for ever, so the
    /// expected altitude is a constant that cannot drift with the clock.
    #[tokio::test]
    async fn mountless_sequencer_frame_keeps_its_altitude_through_the_save_path() {
        const SITE_LAT: f64 = 39.9719;

        let mut ctx = FrameContext::new_light("sess-mountless", 1, 1, 3.0, 1);
        ctx.target_ra_hours = Some(2.5303);
        ctx.target_dec_degrees = Some(90.0);
        ctx.site_latitude_deg = Some(SITE_LAT);
        ctx.site_longitude_deg = Some(-75.3576);
        ctx.exposure_started_at = Some(chrono::Utc::now());
        assert!(
            ctx.mount_ra_hours.is_none() && ctx.mount_altitude_deg.is_none(),
            "precondition: no mount answered for this frame"
        );

        // `None` is exactly what `read_mount_pointing` returns with no mount
        // connected — the state the rig was in.
        let header = build_rich_header(&tiny_frame(), &ctx, None);

        let scratch = temp_scratch_dir("mountless_save_path");
        let path = scratch.as_ref().join("mountless_0001.fits");
        crate::api::save_fits_file_rich(
            path.to_string_lossy().to_string(),
            4,
            4,
            vec![0u16; 16],
            header,
        )
        .await
        .expect("FITS save should succeed");

        let (_image, parsed) = read_fits(&path).expect("FITS read-back should succeed");

        let alt = parsed
            .get_float("OBJCTALT")
            .expect("a mountless sequencer frame must still record its altitude");
        assert!(
            (alt - SITE_LAT).abs() < 0.05,
            "the pole sits at the observer's latitude {SITE_LAT}, got OBJCTALT {alt}"
        );
        // Physics, not a second run of the formula: a refracting atmosphere is
        // always a slightly shorter path than the plane-parallel sec z.
        let airmass = parsed
            .get_float("AIRMASS")
            .expect("AIRMASS follows from a recorded altitude");
        let plane_parallel = 1.0 / (90.0 - SITE_LAT).to_radians().cos();
        assert!(
            airmass < plane_parallel && plane_parallel - airmass < 0.02,
            "AIRMASS {airmass} is not just below the plane-parallel ceiling {plane_parallel}"
        );
        // ...and it describes the direction the file is labelled with.
        let ra_deg = parsed.get_float("RA").expect("RA card must be present");
        assert!(
            (ra_deg - 2.5303 * 15.0).abs() < 1e-6,
            "RA card should be the target's 2.5303h in degrees, got {ra_deg}"
        );
        assert_eq!(parsed.get_float("DEC"), Some(90.0));
    }

    /// Even with a Target group the old header was wrong in kind: it wrote the
    /// target's NOMINAL coordinates, so an unedited "New Target" stamped
    /// 0h/0° onto frames the mount took 17h away. The mount's report wins.
    #[tokio::test]
    async fn mount_pointing_wins_over_nominal_target_coordinates() {
        let mut ctx = FrameContext::new_light("sess-targeted", 1, 1, 3.0, 1);
        ctx.target_name = Some("New Target".to_string());
        ctx.target_ra_hours = Some(0.0);
        ctx.target_dec_degrees = Some(0.0);

        let header = build_rich_header(
            &tiny_frame(),
            &ctx,
            Some(MountPointing {
                ra_hours: 17.0,
                dec_degrees: 30.0,
                altitude_deg: None,
            }),
        );

        assert_eq!(header.ra, Some(17.0), "RA must come from the mount");
        assert_eq!(header.dec, Some(30.0), "DEC must come from the mount");
        // OBJECT still names the target — only the coordinates change source.
        assert_eq!(header.object_name.as_deref(), Some("New Target"));
    }

    /// The reported defect: a sequenced frame landed in `captured_images` with
    /// no gain, offset, sensor temperature, pointing, focuser position or
    /// rotator angle, while the FITS file written microseconds earlier from the
    /// same exposure had all of them — the database and the file disagreeing
    /// about one frame.
    ///
    /// This asserts the collapse. One `FrameContext` is built, the real FITS
    /// file is written from it and read back off disk, and every card is
    /// checked against the `FrameCaptureMetadata` the frame event carries —
    /// which is exactly what the Dart listener writes the row from. If the two
    /// surfaces ever get separate sources again, this fails.
    #[tokio::test]
    async fn database_row_and_fits_header_agree_for_the_same_frame() {
        let mut ctx = FrameContext::new_light("sess-agree", 2, 2, 120.0, 7);
        ctx.frame_type = "Dark".to_string();
        ctx.target_id = Some("tgt-agree".to_string());
        ctx.gain = Some(139);
        ctx.offset = Some(21);
        ctx.sensor_temp_c = Some(-9.5);
        ctx.cooler_power_percent = Some(63.5);
        ctx.focuser_position = Some(31_705);
        ctx.focuser_temperature_c = Some(4.25);
        ctx.rotator_angle_deg = Some(212.5);
        ctx.mount_ra_hours = Some(5.5);
        ctx.mount_dec_degrees = Some(-5.25);
        ctx.mount_altitude_deg = Some(48.5);
        ctx.mount_azimuth_deg = Some(171.25);
        ctx.pier_side = Some("West".to_string());

        // What the database row is written from.
        let capture = nightshade_sequencer::scheduling::FrameCaptureMetadata::from(&ctx);

        // What the file on disk is written from. `tiny_frame()` deliberately
        // reports a DIFFERENT gain/offset/temperature/exposure than the
        // context: the header must not quietly prefer a second source.
        let header = build_rich_header(&tiny_frame(), &ctx, None);
        let scratch = temp_scratch_dir("agree");
        let path = scratch.as_ref().join("agree_0007.fits");
        crate::api::save_fits_file_rich(
            path.to_string_lossy().to_string(),
            4,
            4,
            vec![0u16; 16],
            header,
        )
        .await
        .expect("FITS save should succeed");
        let (_image, parsed) = read_fits(&path).expect("FITS read-back should succeed");

        assert_eq!(
            parsed.get_int("GAIN").map(|g| g as i32),
            capture.gain,
            "GAIN card and the row's gain must be the same number"
        );
        assert_eq!(
            parsed.get_int("OFFSET").map(|o| o as i32),
            capture.offset,
            "OFFSET card and the row's offset must be the same number"
        );
        assert_eq!(
            parsed.get_float("CCD-TEMP"),
            capture.sensor_temp_c,
            "CCD-TEMP card and the row's sensor_temp must be the same number"
        );
        assert_eq!(
            parsed.get_float("EXPTIME"),
            Some(capture.exposure_secs),
            "EXPTIME card and the row's exposure_duration must be the same number"
        );
        assert_eq!(
            parsed.get_int("XBINNING").map(|b| b as u32),
            Some(capture.bin_x),
            "XBINNING card and the row's bin_x must be the same number"
        );
        assert_eq!(
            parsed.get_int("YBINNING").map(|b| b as u32),
            Some(capture.bin_y),
            "YBINNING card and the row's bin_y must be the same number"
        );
        assert_eq!(
            parsed.get_string("IMAGETYP"),
            Some(capture.frame_type.as_str()),
            "IMAGETYP card and the row's frame_type must describe the same frame"
        );
        assert_eq!(
            parsed.get_int("FOCUSPOS").map(|p| p as i32),
            capture.focuser_position,
            "FOCUSPOS card and the row's focuser_position must be the same number"
        );
        assert_eq!(
            parsed.get_float("FOCTEMP"),
            capture.focuser_temperature_c,
            "FOCTEMP card and the row's focuser_temp must be the same number"
        );
        assert_eq!(
            parsed.get_float("ROTATPOS"),
            capture.rotator_angle_deg,
            "ROTATPOS card and the row's rotator_angle must be the same number"
        );
        // The numeric RA card is degrees by universal convention while both
        // the row and the context carry hours, so this is the one field where
        // agreement means "the same pointing", not "the same number".
        let ra_deg = parsed.get_float("RA").expect("RA card must be present");
        assert!(
            (ra_deg / 15.0 - capture.mount_ra_hours.expect("row carries the pointing")).abs()
                < 1e-9,
            "RA card ({ra_deg}°) and the row's mount_ra must be the same pointing"
        );
        assert_eq!(
            parsed.get_float("DEC"),
            capture.mount_dec_degrees,
            "DEC card and the row's mount_dec must be the same number"
        );

        // Columns with no FITS card of their own still have to come off the
        // same struct, or they are back to being invented somewhere else.
        assert_eq!(capture.cooler_power_percent, Some(63.5));
        assert_eq!(capture.mount_altitude_deg, Some(48.5));
        assert_eq!(capture.mount_azimuth_deg, Some(171.25));
        assert_eq!(capture.pier_side.as_deref(), Some("West"));
        assert_eq!(capture.target_id.as_deref(), Some("tgt-agree"));
    }

    /// No connected mount (or a driver that will not answer) must not make the
    /// header worse than it was: the target coordinates remain the fallback,
    /// and nothing is invented.
    #[test]
    fn missing_mount_falls_back_to_target_coordinates() {
        let mut ctx = FrameContext::new_light("sess-nomount", 1, 1, 3.0, 1);
        ctx.target_ra_hours = Some(20.967);
        ctx.target_dec_degrees = Some(44.333);

        let header = build_rich_header(&tiny_frame(), &ctx, None);

        assert_eq!(header.ra, Some(20.967));
        assert_eq!(header.dec, Some(44.333));
        assert_eq!(header.altitude, None);
    }

    // -----------------------------------------------------------------------
    // AIRMASS: the site the sequencer was seeded with vs the site app settings
    // knows about.
    // -----------------------------------------------------------------------

    /// A run whose executor never received a location produces pointing with no
    /// altitude. Skipping the mount read (correct — the pointing is already
    /// here) must not also skip resolving the altitude, or the frame loses
    /// AIRMASS while the app has the site sitting in settings.
    #[test]
    fn context_pointing_without_altitude_resolves_it_from_app_settings() {
        let mut ctx = FrameContext::new_light("sess-nosite", 1, 1, 3.0, 1);
        ctx.mount_ra_hours = Some(17.0);
        ctx.mount_dec_degrees = Some(30.0);
        assert!(
            ctx.mount_altitude_deg.is_none(),
            "precondition: an unseeded executor derives no altitude"
        );

        let when = chrono::DateTime::parse_from_rfc3339("2026-08-02T04:00:00Z")
            .unwrap()
            .with_timezone(&chrono::Utc);
        let resolved = context_altitude_pointing(&ctx, Some((40.0, -75.0)), when)
            .expect("app settings knows the site, so the altitude is derivable");

        // The coordinates are the CONTEXT's own — the point of the fallback is
        // that it adds geometry, not a second mount read.
        assert_eq!(resolved.ra_hours, 17.0);
        assert_eq!(resolved.dec_degrees, 30.0);
        let altitude = resolved.altitude_deg.expect("altitude derived");
        assert!(
            (altitude - altitude_degrees(17.0, 30.0, 40.0, -75.0, when)).abs() < 1e-9,
            "altitude must be the same geometry the mount-read path uses"
        );

        // ... and it has to actually reach the card.
        let header = build_rich_header(&tiny_frame(), &ctx, Some(resolved));
        assert_eq!(header.ra, Some(17.0));
        assert_eq!(header.altitude, Some(altitude));
    }

    #[test]
    fn context_altitude_wins_and_no_site_stays_absent() {
        let mut ctx = FrameContext::new_light("sess-site", 1, 1, 3.0, 1);
        ctx.mount_ra_hours = Some(17.0);
        ctx.mount_dec_degrees = Some(30.0);
        let when = chrono::Utc::now();

        // Nothing to add when the sequencer already derived the altitude: its
        // value was computed at capture time, which is closer to the truth than
        // anything recomputed at save time.
        ctx.mount_altitude_deg = Some(52.0);
        assert!(context_altitude_pointing(&ctx, Some((40.0, -75.0)), when).is_none());
        assert_eq!(
            build_rich_header(&tiny_frame(), &ctx, None).altitude,
            Some(52.0)
        );

        // No site anywhere: AIRMASS stays absent rather than being computed
        // from a guessed location.
        ctx.mount_altitude_deg = None;
        assert!(context_altitude_pointing(&ctx, None, when).is_none());
        assert_eq!(build_rich_header(&tiny_frame(), &ctx, None).altitude, None);
    }

    /// `save_fits` is the only place that decides WHICH context the header gets
    /// built from and what fallback pointing rides along with it. Both are
    /// invisible to every test that calls `build_rich_header` directly, so this
    /// one drives the real method: hand `build_rich_header` anything but the
    /// context `save_fits` received, or drop the altitude fallback, and the
    /// file on disk changes.
    #[tokio::test]
    async fn save_fits_writes_the_header_from_its_own_frame_context() {
        let app_state = crate::state::AppState::new();
        app_state
            .set_observer_location(Some(crate::storage::ObserverLocation {
                latitude: 40.0,
                longitude: -75.0,
                elevation: 200.0,
            }))
            .expect("observer location");
        let ops = super::BridgeDeviceOps::new(app_state);

        let mut ctx = FrameContext::new_light("sess-savefits", 3, 3, 90.0, 1);
        ctx.mount_ra_hours = Some(17.0);
        // Circumpolar from 40 N (min altitude 35 deg), so this assertion does not
        // depend on the wall clock. At Dec +30 the target is below the horizon for
        // part of every day and AIRMASS is CORRECTLY omitted, which made this test
        // pass or fail depending on the time of day it was run.
        ctx.mount_dec_degrees = Some(85.0);
        // Deliberately unset: this is the seeded-site gap the AIRMASS fallback
        // exists for.
        ctx.mount_altitude_deg = None;
        // Every value below differs from `tiny_frame()`'s, so a header built
        // from anything other than THIS struct is visible in the file.
        ctx.gain = Some(139);
        ctx.offset = Some(21);
        ctx.sensor_temp_c = Some(-9.5);
        ctx.focuser_position = Some(31_705);
        ctx.rotator_angle_deg = Some(212.5);
        ctx.camera_pixel_size_x_um = Some(3.76);
        ctx.camera_pixel_size_y_um = Some(3.76);

        let scratch = temp_scratch_dir("save_fits_ctx");
        let path = scratch.as_ref().join("save_fits_ctx_0001.fits");
        nightshade_sequencer::DeviceOps::save_fits(
            &ops,
            &tiny_frame(),
            &path.to_string_lossy(),
            &ctx,
        )
        .await
        .expect("save should succeed");

        let (_image, parsed) = read_fits(&path).expect("FITS read-back should succeed");

        assert_eq!(parsed.get_int("GAIN").map(|g| g as i32), Some(139));
        assert_eq!(parsed.get_int("OFFSET").map(|o| o as i32), Some(21));
        assert_eq!(parsed.get_float("CCD-TEMP"), Some(-9.5));
        assert_eq!(parsed.get_float("EXPTIME"), Some(90.0));
        assert_eq!(parsed.get_int("XBINNING").map(|b| b as u32), Some(3));
        assert_eq!(parsed.get_int("FOCUSPOS").map(|p| p as i32), Some(31_705));
        assert_eq!(parsed.get_float("ROTATPOS"), Some(212.5));
        let ra_deg = parsed.get_float("RA").expect("RA card must be present");
        assert!((ra_deg - 17.0 * 15.0).abs() < 1e-6, "RA card was {ra_deg}");

        // The plate scale a stacker needs. This card was absent from every
        // sequenced frame because the header builder hardcoded the pitch to
        // None; 3.76 um binned 3x3 reads out as 11.28 um pixels.
        let xpixsz = parsed.get_float("XPIXSZ").expect("XPIXSZ card");
        assert!(
            (xpixsz - 11.28).abs() < 1e-6,
            "XPIXSZ must be the binned pitch, got {xpixsz}"
        );

        assert!(
            parsed.get_float("AIRMASS").is_some(),
            "a sequenced frame must keep AIRMASS when app settings knows the \
             site, even though the sequencer's own location seed did not"
        );
    }

    /// OBJCTALT/AIRMASS describe the light the frame integrated, so they are
    /// evaluated at the exposure midpoint — not at the moment the file is
    /// written.
    ///
    /// `save_fits` runs after readout, so deriving the altitude from
    /// `Utc::now()` here dated it by the whole exposure plus download. The rig
    /// below makes that error unmissable and, deliberately, clock-independent:
    /// the mount is pointed at whatever is culminating RIGHT NOW, so the
    /// save-time answer is the target's maximum altitude while the midpoint —
    /// six hours earlier — is measurably lower, whatever time of day the suite
    /// runs. Dec +85 keeps it circumpolar from 40 N so both instants are above
    /// the horizon and AIRMASS exists either way.
    #[tokio::test]
    async fn save_fits_derives_the_altitude_at_the_exposure_midpoint() {
        const LAT: f64 = 40.0;
        const LON: f64 = -75.0;

        let app_state = crate::state::AppState::new();
        app_state
            .set_observer_location(Some(crate::storage::ObserverLocation {
                latitude: LAT,
                longitude: LON,
                elevation: 200.0,
            }))
            .expect("observer location");
        let ops = super::BridgeDeviceOps::new(app_state);

        let now = chrono::Utc::now();
        let ra_hours = nightshade_sequencer::meridian::local_sidereal_time(
            nightshade_sequencer::meridian::julian_day(&now),
            LON,
        )
        .rem_euclid(24.0);

        let mut ctx = FrameContext::new_light("sess-midpoint", 1, 1, 7200.0, 1);
        ctx.mount_ra_hours = Some(ra_hours);
        ctx.mount_dec_degrees = Some(85.0);
        // The seeded-site gap: the sequencer derived no altitude, so this save
        // is the one that decides which instant the geometry belongs to.
        ctx.mount_altitude_deg = None;
        // Shutter opened 7 h ago and stayed open 2 h, so the midpoint is 6 h
        // back while `Utc::now()` is culmination.
        ctx.exposure_started_at = Some(now - chrono::Duration::hours(7));

        let scratch = temp_scratch_dir("save_fits_midpoint");
        let path = scratch.as_ref().join("midpoint_0001.fits");
        nightshade_sequencer::DeviceOps::save_fits(
            &ops,
            &tiny_frame(),
            &path.to_string_lossy(),
            &ctx,
        )
        .await
        .expect("save should succeed");

        let (_image, parsed) = read_fits(&path).expect("FITS read-back should succeed");
        let recorded = parsed
            .get_float("OBJCTALT")
            .expect("OBJCTALT card must be present");

        let at_midpoint =
            altitude_degrees(ra_hours, 85.0, LAT, LON, now - chrono::Duration::hours(6));
        let at_save_time = altitude_degrees(ra_hours, 85.0, LAT, LON, now);
        assert!(
            (at_save_time - at_midpoint).abs() > 1.0,
            "test rig is not discriminating: save-time {at_save_time:.4} deg vs \
             midpoint {at_midpoint:.4} deg"
        );
        assert!(
            (recorded - at_midpoint).abs() < 0.01,
            "OBJCTALT was {recorded:.4} deg; the exposure midpoint is \
             {at_midpoint:.4} deg and save time is {at_save_time:.4} deg"
        );
    }
}
