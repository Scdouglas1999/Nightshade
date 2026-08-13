//! Unified Device Operations Implementation
//!
//! This module is the one and only `DeviceOps` implementation the sequencer
//! runs against. It absorbed the two earlier ones — `BridgeDeviceOps` (routed
//! through the bridge API) and `RealDeviceOps` (direct ASCOM/Alpaca access) —
//! both of which have been deleted; nothing may reintroduce a second impl,
//! because `set_device_ops` on the process-global executor is last-writer-wins.
//!
//! # Architecture
//!
//! ```text
//! ┌─────────────────┐
//! │    Sequencer    │
//! └────────┬────────┘
//!          │ uses DeviceOps trait
//!          ▼
//! ┌─────────────────┐
//! │ UnifiedDeviceOps│
//! └────────┬────────┘
//!          │ calls bridge API
//!          ▼
//! ┌─────────────────┐
//! │   Bridge API    │
//! │  (api_* funcs)  │
//! └────────┬────────┘
//!          │ routes by device ID prefix
//!          ▼
//! ┌─────────────────────────────────────────┐
//! │              DeviceManager              │
//! ├────────┬────────┬─────────┬────────────┤
//! │ ASCOM  │ Alpaca │  INDI   │   Native   │
//! │(ascom:)│(alpaca:)│(indi:) │(native:zwo)│
//! └────────┴────────┴─────────┴────────────┘
//! ```
//!
//! # Usage
//!
//! ```rust,ignore
//! use nightshade_bridge::unified_device_ops::create_unified_device_ops;
//!
//! let ops = create_unified_device_ops();
//! executor.set_device_ops(ops);
//! ```
//!
//! # `as`-cast policy
//!
//! Same pattern groupings as `sequencer_ops.rs` (this file is the unified
//! replacement and the cast taxonomy is identical):
//! - **Pixel histogram u16 → usize index** (line 548): u16 max 65535 fits
//!   any supported usize.
//! - **Image normalize u16 → f64** (line 505): exact widening.
//! - **bool → u8** (lines 660, 904): wire encoding.
//! - **Filter wheel index ±1** (lines 815, 817): bounded by slot count.
//! - **star_count usize → u32** (line 544): real frames have ≤ tens of
//!   thousands of stars; saturating cast would catch any pathology.
//! - **Star-count average f64** (line 1300): exact widening.
//! - **Julian Day chrono fields**: this file no longer computes a Julian Day
//!   of its own — it calls `sequencer/src/meridian.rs::julian_day`, where
//!   those per-site Why comments live.

/// Prefix marking a capture that failed *image validation* rather than failing
/// in the driver or the transport.
///
/// The `DeviceOps` trait signs its errors as bare `String` (`DeviceResult<T> =
/// Result<T, String>`), so a caller cannot otherwise tell "the camera worked and
/// the frame is unusable" apart from "the camera broke". That distinction
/// matters at the HTTP boundary: a completely saturated frame is a normal,
/// operator-actionable outcome (shorten the exposure) and must not be reported
/// as an internal server fault. `api::imaging` matches this prefix to promote
/// the error to [`NightshadeError::ExposureFailed`], which the headless API maps
/// to 422 instead of 500.
///
/// Producer and consumer live in the same crate and share this constant so the
/// two cannot drift apart.
pub(crate) const IMAGE_VALIDATION_FAILED_PREFIX: &str = "Image validation failed: ";

fn median_from_sorted_f64(sorted: &[f64]) -> Option<f64> {
    if sorted.is_empty() {
        return None;
    }

    let mid = sorted.len() / 2;
    if sorted.len() % 2 == 0 {
        Some((sorted[mid - 1] + sorted[mid]) / 2.0)
    } else {
        Some(sorted[mid])
    }
}

use crate::adaptive_polling::{AdaptivePoller, PollerPreset};
use crate::api::*;
use crate::device::DeviceType;
use crate::event::*;
use crate::filter_matching::find_filter_match;
use crate::state::SharedAppState;
use crate::FitsWriteHeader;
use async_trait::async_trait;
// The Julian Day / LST pair this file used to carry privately was a
// byte-for-byte copy of these two (same Meeus day-number, same single wrap of
// `gmst + longitude`), and line 3047 below already called the sequencer's copy
// directly — so the file was importing and re-typing the same function.
use nightshade_sequencer::meridian::{julian_day, local_sidereal_time};
use nightshade_sequencer::{
    CameraSubframe, DeviceOps, DeviceResult, GuidingCalibration, GuidingStatus, ImageData,
    PlateSolveResult, PolarAlignResult,
};
use std::collections::HashMap;
use std::sync::{Arc, OnceLock};
use tokio::sync::Mutex;

const EXPOSURE_COMPLETION_MARGIN: std::time::Duration = std::time::Duration::from_secs(60);

static EXPOSURE_ABORT_GENERATIONS: OnceLock<Mutex<HashMap<String, u64>>> = OnceLock::new();

fn exposure_abort_generations() -> &'static Mutex<HashMap<String, u64>> {
    EXPOSURE_ABORT_GENERATIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(crate) async fn exposure_abort_generation(camera_id: &str) -> u64 {
    *exposure_abort_generations()
        .lock()
        .await
        .get(camera_id)
        .unwrap_or(&0)
}

/// Invalidate the in-flight acquisition before issuing a hardware abort.
///
/// Some camera SDKs report a terminal Success immediately after StopExposure.
/// Without a generation check the original task then downloads and publishes
/// that aborted buffer as a valid image.
pub(crate) async fn mark_camera_exposure_aborted(camera_id: &str) {
    let mut generations = exposure_abort_generations().lock().await;
    let entry = generations.entry(camera_id.to_string()).or_default();
    *entry = entry.wrapping_add(1);
}

fn exposure_completion_timeout(duration_secs: f64) -> std::time::Duration {
    std::time::Duration::from_secs_f64(duration_secs.max(0.0)) + EXPOSURE_COMPLETION_MARGIN
}

/// [acquisition_generation] is the abort generation read when this acquisition
/// started. Once it moves the operator has aborted, and this returns
/// immediately: a driver that answers "not complete" for an exposure it has
/// already been told to stop would otherwise keep this loop publishing
/// `ExposureProgress` until the duration+margin deadline, so the preview went
/// on counting down a frame that was never going to arrive.
async fn wait_for_camera_exposure_complete<F, Fut>(
    camera_id: &str,
    duration_secs: f64,
    timeout_after: std::time::Duration,
    acquisition_generation: u64,
    app_state: &SharedAppState,
    mut is_complete: F,
) -> DeviceResult<()>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<bool, String>>,
{
    let start_time = std::time::Instant::now();
    let mut poller: AdaptivePoller<bool> = AdaptivePoller::from_preset(PollerPreset::Exposure);

    loop {
        if exposure_abort_generation(camera_id).await != acquisition_generation {
            return Ok(());
        }
        let elapsed_now = start_time.elapsed();
        if elapsed_now >= timeout_after {
            return Err(format!(
                "Exposure on {} did not complete within {:.1}s timeout ({:.1}s requested exposure plus safety margin)",
                camera_id,
                timeout_after.as_secs_f64(),
                duration_secs
            ));
        }
        let remaining = timeout_after - elapsed_now;

        // Bound each status poll by the remaining deadline. Without this the
        // deadline check above is only reached BETWEEN polls, so a status call
        // that itself stalls (USB hiccup, or contention on a shared vendor SDK
        // mutex held by a slow/wedged download) would never return control to
        // the check and the advertised timeout could never fire. With the
        // per-poll bound the overall deadline stays authoritative.
        match tokio::time::timeout(remaining, is_complete()).await {
            Ok(Ok(true)) => return Ok(()),
            Ok(Ok(false)) => {}
            Ok(Err(e)) => return Err(format!("Failed to check exposure status: {}", e)),
            Err(_) => {
                return Err(format!(
                    "Exposure status poll on {} did not return within the {:.1}s deadline ({:.1}s requested exposure plus safety margin)",
                    camera_id,
                    timeout_after.as_secs_f64(),
                    duration_secs
                ));
            }
        }

        let elapsed = start_time.elapsed();
        let progress = if duration_secs > 0.0 {
            (elapsed.as_secs_f64() / duration_secs).min(1.0)
        } else {
            1.0
        };
        let remaining_secs = (duration_secs - elapsed.as_secs_f64()).max(0.0);

        app_state.publish_imaging_event(
            ImagingEvent::ExposureProgress {
                progress,
                remaining_secs,
            },
            EventSeverity::Info,
        );

        // Reaching this point means the current poll observed "not complete";
        // a completed exposure returns immediately above.
        let poll_interval = poller.tick(&false);
        let remaining_timeout = timeout_after.saturating_sub(start_time.elapsed());
        tokio::time::sleep(poll_interval.min(remaining_timeout)).await;
    }
}

/// Unified device operations implementation
///
/// This is the recommended DeviceOps implementation for the sequencer.
/// It routes all device operations through the bridge API which handles:
/// - Device ID prefix routing (ascom:, alpaca:, indi:, native:)
/// - Connection state management
/// - Error handling and logging
pub struct UnifiedDeviceOps {
    app_state: SharedAppState,
}

impl UnifiedDeviceOps {
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

        // Audit C1: the profile now persists a SafetyMonitor selection. Prefer
        // that over falling through to a weather device so sequencer safety
        // checks consult the dedicated sensor instead of inferring safe/unsafe
        // from a weather station.
        if let Some(id) = self
            .app_state
            .get_profile_device_id(DeviceType::SafetyMonitor)
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
/// `UnifiedDeviceOps::calculate_altitude` is this function at `Utc::now()`.
fn altitude_degrees(
    ra_hours: f64,
    dec_degrees: f64,
    lat: f64,
    lon: f64,
    when: chrono::DateTime<chrono::Utc>,
) -> f64 {
    let lst = local_sidereal_time(julian_day(&when), lon);
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
impl DeviceOps for UnifiedDeviceOps {
    // =========================================================================
    // CONNECTION / RECOVERY
    // =========================================================================
    //
    // These two overrides are what make device-disconnect recovery actually
    // work on the live path. Without them the trait defaults
    // (`device_ops.rs`) return `Err("not supported")`, so the
    // `DeviceDisconnected` recovery loop fails instantly on every driver and a
    // USB/comms blip aborts the night. They delegate straight to the
    // `DeviceManager` primitives.

    async fn device_is_connected(&self, device_id: &str) -> DeviceResult<bool> {
        Ok(get_device_manager().is_connected(device_id).await)
    }

    async fn connect_device(&self, device_id: &str) -> DeviceResult<()> {
        // Mark the device auto-reconnectable so the background reconnection
        // loop keeps retrying it too (camera/focuser/filter-wheel default to
        // false), then drive an immediate connect attempt. Both together make
        // recovery actively reconnect instead of waiting out the budget.
        get_device_manager()
            .set_auto_reconnect(device_id, true)
            .await;
        get_device_manager().connect_device(device_id).await
    }

    // =========================================================================
    // MOUNT OPERATIONS
    // =========================================================================

    async fn mount_slew_to_coordinates(
        &self,
        mount_id: &str,
        ra_hours: f64,
        dec_degrees: f64,
    ) -> DeviceResult<()> {
        tracing::info!(
            "Slewing mount {} to RA={:.4}h Dec={:.4}°",
            mount_id,
            ra_hours,
            dec_degrees
        );

        // Emit slew started event
        self.app_state.publish_event(create_event_auto_id(
            EventSeverity::Info,
            EventCategory::Equipment,
            EventPayload::Equipment(EquipmentEvent::MountSlewStarted {
                ra: ra_hours,
                dec: dec_degrees,
            }),
        ));

        let result = get_device_manager()
            .mount_slew(mount_id, ra_hours, dec_degrees)
            .await
            .map_err(|e| format!("Slew failed: {}", e));

        // Emit slew completed event on success
        if result.is_ok() {
            self.app_state.publish_event(create_event_auto_id(
                EventSeverity::Info,
                EventCategory::Equipment,
                EventPayload::Equipment(EquipmentEvent::MountSlewCompleted {
                    ra: ra_hours,
                    dec: dec_degrees,
                }),
            ));
        }

        result
    }

    async fn mount_abort_slew(&self, mount_id: &str) -> DeviceResult<()> {
        tracing::info!("Aborting slew for mount {}", mount_id);

        get_device_manager()
            .mount_abort(mount_id)
            .await
            .map_err(|e| format!("Abort slew failed: {}", e))
    }

    async fn mount_get_coordinates(&self, mount_id: &str) -> DeviceResult<(f64, f64)> {
        let status = get_device_manager()
            .mount_get_status(mount_id)
            .await
            .map_err(|e| format!("Failed to get mount status: {}", e))?;

        Ok((status.right_ascension, status.declination))
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

        get_device_manager()
            .mount_sync(mount_id, ra_hours, dec_degrees)
            .await
            .map_err(|e| format!("Sync failed: {}", e))
    }

    async fn mount_park(&self, mount_id: &str) -> DeviceResult<()> {
        tracing::info!("Parking mount {}", mount_id);

        // Emit park started event
        self.app_state.publish_event(create_event_auto_id(
            EventSeverity::Info,
            EventCategory::Equipment,
            EventPayload::Equipment(EquipmentEvent::MountParkStarted),
        ));

        let result = get_device_manager()
            .mount_park(mount_id)
            .await
            .map_err(|e| format!("Park failed: {}", e));

        if result.is_ok() {
            self.app_state.publish_event(create_event_auto_id(
                EventSeverity::Info,
                EventCategory::Equipment,
                EventPayload::Equipment(EquipmentEvent::MountParkCompleted),
            ));
        }

        result
    }

    async fn mount_unpark(&self, mount_id: &str) -> DeviceResult<()> {
        tracing::info!("Unparking mount {}", mount_id);

        let result = get_device_manager()
            .mount_unpark(mount_id)
            .await
            .map_err(|e| format!("Unpark failed: {}", e));

        if result.is_ok() {
            self.app_state.publish_event(create_event_auto_id(
                EventSeverity::Info,
                EventCategory::Equipment,
                EventPayload::Equipment(EquipmentEvent::MountUnparked),
            ));
        }

        result
    }

    async fn mount_is_slewing(&self, mount_id: &str) -> DeviceResult<bool> {
        let status = get_device_manager()
            .mount_get_status(mount_id)
            .await
            .map_err(|e| format!("Failed to get mount status: {}", e))?;

        Ok(status.slewing)
    }

    async fn mount_is_parked(&self, mount_id: &str) -> DeviceResult<bool> {
        let status = get_device_manager()
            .mount_get_status(mount_id)
            .await
            .map_err(|e| format!("Failed to get mount status: {}", e))?;

        Ok(status.parked)
    }

    async fn mount_can_flip(&self, mount_id: &str) -> DeviceResult<bool> {
        let status = get_device_manager()
            .mount_get_status(mount_id)
            .await
            .map_err(|e| format!("Failed to get mount status: {}", e))?;

        if !status.can_slew {
            return Ok(false);
        }
        // None (couldn't read or unsupported) collapses to Unknown — both
        // prevent the sequencer from issuing a meridian flip.
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
        // Get pier side from mount status. None collapses to Unknown so the
        // meridian module receives a single "indeterminate" signal.
        let status = get_device_manager()
            .mount_get_status(mount_id)
            .await
            .map_err(|e| format!("Failed to get mount status: {}", e))?;

        Ok(match status.side_of_pier {
            Some(crate::device::PierSide::East) => nightshade_sequencer::meridian::PierSide::East,
            Some(crate::device::PierSide::West) => nightshade_sequencer::meridian::PierSide::West,
            Some(crate::device::PierSide::Unknown) | None => {
                nightshade_sequencer::meridian::PierSide::Unknown
            }
        })
    }

    async fn mount_is_tracking(&self, mount_id: &str) -> DeviceResult<bool> {
        let status = get_device_manager()
            .mount_get_status(mount_id)
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

        get_device_manager()
            .mount_set_tracking(mount_id, enabled)
            .await
            .map_err(|e| format!("Set tracking failed: {}", e))
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
        // Frame-type-agnostic entry point → Light (shutter open). Dark/bias is
        // carried by the frame-type-aware method below (shared body).
        self.camera_start_exposure_configured(
            camera_id,
            duration_secs,
            gain,
            offset,
            bin_x,
            bin_y,
            None,
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
        self.camera_start_exposure_configured(
            camera_id,
            duration_secs,
            gain,
            offset,
            bin_x,
            bin_y,
            None,
            frame_type,
        )
        .await
    }

    async fn camera_start_exposure_configured(
        &self,
        camera_id: &str,
        duration_secs: f64,
        gain: Option<i32>,
        offset: Option<i32>,
        bin_x: i32,
        bin_y: i32,
        subframe: Option<CameraSubframe>,
        frame_type: &str,
    ) -> DeviceResult<ImageData> {
        let acquisition_generation = exposure_abort_generation(camera_id).await;
        let native_frame_type = nightshade_native::camera::FrameType::from_str_lenient(frame_type);
        tracing::info!(
            "Starting {:.1}s exposure on camera {}",
            duration_secs,
            camera_id
        );

        let mgr = get_device_manager();

        // Mark the rig as USB-contended for the whole exposure+download window.
        // On shared-USB rigs (a ZWO EAF/EFW behind an ASI camera) the camera
        // saturates the bus during frame download, so an auxiliary device's
        // liveness poll loses the race and returns a transient failure — the
        // real cause of the spurious focuser/filter-wheel disconnects. While
        // this guard is alive the heartbeat loop SKIPS polls for the
        // focuser/filter-wheel/rotator (see `run_heartbeat_loop` /
        // `is_usb_contended`). The guard clears the marker when this function
        // returns — success, error, or panic — including every `?` early return
        // below, so it can never leak and permanently silence those heartbeats.
        let _usb_contention = mgr.begin_usb_contention();

        // Publish ExposureStarted event
        self.app_state.publish_imaging_event(
            ImagingEvent::ExposureStarted {
                duration_secs,
                frame_type: match native_frame_type {
                    nightshade_native::camera::FrameType::Dark => crate::device::FrameType::Dark,
                    nightshade_native::camera::FrameType::Flat => crate::device::FrameType::Flat,
                    nightshade_native::camera::FrameType::Bias => crate::device::FrameType::Bias,
                    nightshade_native::camera::FrameType::DarkFlat => {
                        crate::device::FrameType::DarkFlat
                    }
                    nightshade_native::camera::FrameType::Light => crate::device::FrameType::Light,
                },
            },
            EventSeverity::Info,
        );

        // Start the exposure. gain/offset are Option<i32>; None means "use the
        // camera's current value, don't change it" and is threaded through to
        // each driver branch so the setter is genuinely skipped (rather than
        // the old `unwrap_or(0)` which silently commanded gain/offset 0).
        mgr.camera_start_exposure_configured(
            camera_id,
            duration_secs,
            gain,
            offset,
            bin_x,
            bin_y,
            subframe.map(|roi| nightshade_native::camera::SubFrame {
                start_x: roi.start_x,
                start_y: roi.start_y,
                width: roi.width,
                height: roi.height,
            }),
            native_frame_type,
        )
        .await
        .inspect_err(|_e| {
            // Publish failure event
            self.app_state.publish_imaging_event(
                ImagingEvent::ExposureComplete { success: false },
                EventSeverity::Error,
            );
        })
        .map_err(|e| format!("Exposure failed: {}", e))?;

        if let Err(e) = wait_for_camera_exposure_complete(
            camera_id,
            duration_secs,
            exposure_completion_timeout(duration_secs),
            acquisition_generation,
            &self.app_state,
            || async {
                mgr.camera_is_exposure_complete(camera_id)
                    .await
                    .map_err(|e| e.to_string())
            },
        )
        .await
        {
            // The wait failed (status-poll error or the completion deadline)
            // while the camera is still physically exposing. Abort it so the
            // sensor is left idle — otherwise the sequencer's retry races a
            // still-running exposure and fails with "exposure already in
            // progress". Abort is best-effort; the original error is returned.
            let _ = mgr.camera_abort_exposure(camera_id).await;
            self.app_state.publish_imaging_event(
                ImagingEvent::ExposureComplete { success: false },
                EventSeverity::Error,
            );
            return Err(e);
        }

        if exposure_abort_generation(camera_id).await != acquisition_generation {
            self.app_state.publish_imaging_event(
                ImagingEvent::ExposureComplete { success: false },
                EventSeverity::Info,
            );
            return Err("Exposure cancelled".to_string());
        }

        // Download image under a hard ceiling so a stalled download cannot
        // hang the whole sequence indefinitely. A USB stall / hub brown-out /
        // contention on the shared vendor SDK mutex makes the download block;
        // bounding it turns "hang until morning" into a recoverable node
        // failure that the disconnect/recovery path can act on.
        //
        // NOTE: tokio's timeout cancels at an await point. It reliably fires
        // for stalls that yield (lock contention, the shared-mutex cascade,
        // late-returning USB calls). A vendor FFI call that blocks the worker
        // thread and literally never returns cannot be force-cancelled here —
        // fully isolating that would require running the blocking SDK call on
        // spawn_blocking inside each vendor driver, which is tracked
        // separately as it needs on-hardware validation per SDK.
        let native_image = match tokio::time::timeout(
            crate::timeout_ops::Timeouts::image_download_large(),
            mgr.camera_download_image(camera_id),
        )
        .await
        {
            Ok(inner) => inner.map_err(|e| {
                self.app_state.publish_imaging_event(
                    ImagingEvent::ExposureComplete { success: false },
                    EventSeverity::Error,
                );
                format!("Failed to download image: {}", e)
            })?,
            Err(_) => {
                self.app_state.publish_imaging_event(
                    ImagingEvent::ExposureComplete { success: false },
                    EventSeverity::Error,
                );
                return Err(format!(
                    "Image download on {} exceeded the {}s timeout — failing the frame so recovery can run",
                    camera_id,
                    crate::timeout_ops::Timeouts::image_download_large().as_secs()
                ));
            }
        };

        if exposure_abort_generation(camera_id).await != acquisition_generation {
            self.app_state.publish_imaging_event(
                ImagingEvent::ExposureComplete { success: false },
                EventSeverity::Info,
            );
            return Err("Exposure cancelled".to_string());
        }

        tracing::info!(
            "[EXPOSURE] Download complete: {}x{} ({} pixels)",
            native_image.width,
            native_image.height,
            native_image.data.len()
        );

        // Validate downloaded image data to catch corrupted/bad frames early
        // This prevents cascading failures in autofocus, plate solving, etc.
        {
            // Convert to nightshade_imaging ImageData for validation
            let img_for_validation = nightshade_imaging::ImageData::from_u16(
                native_image.width,
                native_image.height,
                1, // channels
                &native_image.data,
            );

            tracing::debug!("[EXPOSURE] Starting image validation...");

            // Ask the sensor where it clips. Saturation is meaningless without a
            // ceiling, and no constant can supply one: a driver that
            // right-justifies a 12-bit sensor clips at 4095 and an 8-bit
            // container (the SVBony RAW8 connect fallback) at 255, both far
            // under any 16-bit threshold, so without this every clipped frame
            // off those cameras passes in silence. Best-effort by design — a
            // driver that cannot answer its own status must not cost us the
            // frame, so failure just leaves the validator on the frame's own
            // clipping evidence.
            let sensor_max_adu = match api_get_camera_status(camera_id.to_string()).await {
                Ok(status) => Some(status.max_adu).filter(|&max_adu| max_adu > 0),
                Err(e) => {
                    tracing::debug!(
                        "[EXPOSURE] No sensor ceiling from {camera_id} ({e}); \
                         judging saturation from the frame alone"
                    );
                    None
                }
            };

            // Use comprehensive validation - bias frames (very short exposures) are allowed to have uniform data
            let is_bias_frame = duration_secs < 0.1; // Bias frames are typically < 100ms
            let validation = nightshade_imaging::validate_image_comprehensive(
                &img_for_validation,
                nightshade_imaging::ImageValidationOptions {
                    expected_width: Some(native_image.width),
                    expected_height: Some(native_image.height),
                    is_bias_frame,
                    sensor_max_adu,
                    ..Default::default()
                },
            );

            tracing::debug!(
                "[EXPOSURE] Validation complete: valid={}",
                validation.is_valid
            );

            // Log validation warnings (don't fail, just inform user via logging)
            for warning in &validation.warnings {
                tracing::warn!("[CAMERA] Image validation warning: {}", warning);
            }

            // Fail on validation errors (corrupted/unusable images)
            if !validation.is_valid {
                let error_msg = validation.errors.join("; ");
                tracing::error!("[CAMERA] {IMAGE_VALIDATION_FAILED_PREFIX}{error_msg}");
                self.app_state.publish_imaging_event(
                    ImagingEvent::ExposureComplete { success: false },
                    EventSeverity::Error,
                );
                return Err(format!("{IMAGE_VALIDATION_FAILED_PREFIX}{error_msg}"));
            }
        }
        let (sensor_type, bayer_offset) = match &native_image.bayer_pattern {
            Some(pattern) => {
                let offset = match pattern {
                    nightshade_native::camera::BayerPattern::Rggb => (0, 0),
                    nightshade_native::camera::BayerPattern::Grbg => (1, 0),
                    nightshade_native::camera::BayerPattern::Gbrg => (0, 1),
                    nightshade_native::camera::BayerPattern::Bggr => (1, 1),
                };
                (Some("Color".to_string()), Some(offset))
            }
            None => (Some("Monochrome".to_string()), None),
        };

        // Store image in unified storage for UI access
        // This is critical - the Flutter UI calls api_get_last_image() to display captures
        {
            let is_color = bayer_offset.is_some();

            // Create ImageData for stretching
            let channels = if is_color { 3 } else { 1 };
            let image = nightshade_imaging::ImageData::from_u16(
                native_image.width,
                native_image.height,
                channels,
                &native_image.data,
            );

            // Apply auto-stretch to create display-ready data
            let display_data_raw = if is_color {
                // Color: debayer and stretch
                // Get bayer pattern from offset
                let bayer_pattern = match bayer_offset {
                    Some((0, 0)) => nightshade_imaging::BayerPattern::RGGB,
                    Some((1, 0)) => nightshade_imaging::BayerPattern::GRBG,
                    Some((0, 1)) => nightshade_imaging::BayerPattern::GBRG,
                    Some((1, 1)) => nightshade_imaging::BayerPattern::BGGR,
                    _ => nightshade_imaging::BayerPattern::RGGB, // Default
                };
                let rgb_data = nightshade_imaging::debayer_to_rgb16(
                    &native_image.data,
                    native_image.width,
                    native_image.height,
                    bayer_pattern,
                    nightshade_imaging::DebayerAlgorithm::Bilinear,
                );

                // Auto-stretch RGB
                use rayon::prelude::*;
                let rgb_pixels: Vec<f64> =
                    rgb_data.par_iter().map(|&v| v as f64 / 65535.0).collect();
                let mut sorted = rgb_pixels.clone();
                // Why: f64::partial_cmp is required because
                // f64 is PartialOrd, not Ord (NaN). Pixel data is already
                // bounded to [0.0, 1.0] by the `v / 65535.0` normalisation
                // above, so NaN cannot occur — the fallback is purely a
                // language requirement to satisfy the closure signature.
                sorted.par_sort_unstable_by(|a, b| {
                    a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal)
                });
                if sorted.is_empty() {
                    return Err("Empty image data for median calculation".to_string());
                }
                let median = median_from_sorted_f64(&sorted)
                    .ok_or_else(|| "Empty image data for median calculation".to_string())?;
                let unified_params = nightshade_imaging::StretchParams {
                    shadows: (median - 0.1).max(0.0),
                    highlights: (median + 0.3).min(1.0),
                    midtones: 0.5,
                };

                nightshade_imaging::apply_stretch_rgb(
                    &rgb_data,
                    native_image.width,
                    native_image.height,
                    &unified_params,
                )
            } else {
                // Grayscale: auto-stretch to u8
                let stretch_params = nightshade_imaging::auto_stretch_stf(&image);
                nightshade_imaging::apply_stretch(&image, &stretch_params)
            };

            // Calculate stats and histogram from pre-RGBA data
            let stats = nightshade_imaging::calculate_stats_u16(&image);
            let stars = nightshade_imaging::detect_stars(
                &image,
                &nightshade_imaging::StarDetectionConfig::default(),
            );
            let star_count = stars.len() as u32;
            // Per-frame median eccentricity from the same detected stars.
            // Fails closed (None) when too few reliable stars — never faked.
            let median_eccentricity = nightshade_imaging::frame_eccentricity(&stars);

            let mut histogram = vec![0u32; 256];
            for &pixel in &display_data_raw {
                histogram[pixel as usize] += 1;
            }

            // Convert to RGBA for Flutter rendering (parallel, fast in Rust)
            let display_data = crate::api::display_data_to_rgba(&display_data_raw, is_color);

            // Create and store the display result
            let display_result = CapturedImageResult {
                width: native_image.width,
                height: native_image.height,
                display_data,
                histogram,
                stats: ImageStatsResult {
                    min: stats.min,
                    max: stats.max,
                    mean: stats.mean,
                    median: stats.median,
                    std_dev: stats.std_dev,
                    hfr: None,
                    fwhm: None,
                    eccentricity: median_eccentricity,
                    star_count,
                },
                exposure_time: duration_secs,
                timestamp: chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
                is_color,
            };

            let raw_info = RawImageInfo {
                width: native_image.width,
                height: native_image.height,
                data: native_image.data.clone(),
                sensor_type: sensor_type.clone(),
                bayer_offset,
            };

            store_captured_image_atomically(camera_id, display_result, raw_info).await;
            tracing::info!("Stored image in unified storage for UI display");
        }

        // Publish success event
        self.app_state.publish_imaging_event(
            ImagingEvent::ExposureComplete { success: true },
            EventSeverity::Info,
        );

        // Why: log-only formatting; "unknown" when the
        // camera SDK did not surface a sensor-type string matches the UI
        // label used in the Equipment panel.
        tracing::info!(
            "Exposure complete: {}x{} image, {} sensor",
            native_image.width,
            native_image.height,
            sensor_type.as_deref().unwrap_or("unknown")
        );

        // Convert to sequencer ImageData
        Ok(ImageData {
            width: native_image.width,
            height: native_image.height,
            data: native_image.data,
            bits_per_pixel: native_image.bits_per_pixel,
            exposure_secs: if native_image.metadata.exposure_time > 0.0 {
                native_image.metadata.exposure_time
            } else {
                duration_secs
            },
            // Blindly wrapping in Some() meant an unreadable gain/offset (which
            // the Alpaca/INDI paths recorded as a placeholder) presented as a real
            // measurement and short-circuited `image_data.gain.or(config.gain)`
            // downstream, so the placeholder beat the operator's configured value
            // and was written into the frame's FITS header. Mapping the
            // unknown marker back to None restores the intended fallback.
            gain: crate::device_manager::ops::camera::camera_setting_or_unknown(
                native_image.metadata.gain,
            ),
            offset: crate::device_manager::ops::camera::camera_setting_or_unknown(
                native_image.metadata.offset,
            ),
            temperature: native_image.metadata.temperature,
            filter: None,
            timestamp: native_image.metadata.timestamp.timestamp(),
            sensor_type,
            bayer_offset,
        })
    }

    async fn camera_abort_exposure(&self, camera_id: &str) -> DeviceResult<()> {
        tracing::info!("Aborting exposure on camera {}", camera_id);

        mark_camera_exposure_aborted(camera_id).await;
        get_device_manager()
            .camera_abort_exposure(camera_id)
            .await
            .map_err(|e| format!("Abort failed: {}", e))
    }

    async fn camera_set_cooler(
        &self,
        camera_id: &str,
        enabled: bool,
        target_temp: f64,
    ) -> DeviceResult<()> {
        tracing::info!(
            "Camera {} cooler: enabled={}, target={}°C",
            camera_id,
            enabled,
            target_temp
        );

        // Emit cooling event
        if enabled {
            self.app_state.publish_event(create_event_auto_id(
                EventSeverity::Info,
                EventCategory::Equipment,
                EventPayload::Equipment(EquipmentEvent::CameraCoolingStarted { target_temp }),
            ));
        } else {
            self.app_state.publish_event(create_event_auto_id(
                EventSeverity::Info,
                EventCategory::Equipment,
                EventPayload::Equipment(EquipmentEvent::CameraWarmingStarted),
            ));
        }

        api_set_camera_cooler(camera_id.to_string(), enabled as u8, Some(target_temp))
            .await
            .map_err(|e| format!("Cooler control failed: {}", e))
    }

    async fn camera_get_temperature(&self, camera_id: &str) -> DeviceResult<f64> {
        let status = api_get_camera_status(camera_id.to_string())
            .await
            .map_err(|e| format!("Failed to get camera status: {}", e))?;

        status
            .sensor_temp
            .ok_or_else(|| "Temperature not available".to_string())
    }

    async fn camera_get_cooler_power(&self, camera_id: &str) -> DeviceResult<f64> {
        let status = api_get_camera_status(camera_id.to_string())
            .await
            .map_err(|e| format!("Failed to get camera status: {}", e))?;

        status
            .cooler_power
            .ok_or_else(|| "Cooler power not available".to_string())
    }

    async fn camera_get_pixel_size_um(&self, camera_id: &str) -> DeviceResult<Option<(f64, f64)>> {
        let status = api_get_camera_status(camera_id.to_string())
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
        tracing::info!("Moving focuser {} to position {}", focuser_id, position);

        // Emit focuser move started event
        self.app_state.publish_event(create_event_auto_id(
            EventSeverity::Info,
            EventCategory::Equipment,
            EventPayload::Equipment(EquipmentEvent::FocuserMoveStarted {
                target_position: position,
            }),
        ));

        let result = api_focuser_move_to(focuser_id.to_string(), position)
            .await
            .map_err(|e| format!("Focuser move failed: {}", e));

        if result.is_ok() {
            self.app_state.publish_event(create_event_auto_id(
                EventSeverity::Info,
                EventCategory::Equipment,
                EventPayload::Equipment(EquipmentEvent::FocuserMoveCompleted { position }),
            ));
        }

        result
    }

    async fn focuser_get_position(&self, focuser_id: &str) -> DeviceResult<i32> {
        get_device_manager()
            .focuser_get_position(focuser_id)
            .await
            .map_err(|e| format!("Get position failed: {}", e))
    }

    async fn focuser_is_moving(&self, focuser_id: &str) -> DeviceResult<bool> {
        get_device_manager()
            .focuser_is_moving(focuser_id)
            .await
            .map_err(|e| format!("Is moving failed: {}", e))
    }

    async fn focuser_get_temperature(&self, focuser_id: &str) -> DeviceResult<Option<f64>> {
        get_device_manager()
            .focuser_get_temp(focuser_id)
            .await
            .map_err(|e| format!("Get temperature failed: {}", e))
    }

    async fn focuser_halt(&self, focuser_id: &str) -> DeviceResult<()> {
        get_device_manager()
            .focuser_halt(focuser_id)
            .await
            .map_err(|e| format!("Halt failed: {}", e))
    }

    // =========================================================================
    // FILTER WHEEL OPERATIONS
    // =========================================================================

    async fn filterwheel_set_position(&self, fw_id: &str, position: i32) -> DeviceResult<()> {
        // Get current position for the event
        // Why: from_position is purely informational
        // for the FilterChanging event payload. If the current position
        // read fails (filter wheel mid-move, or wheel just reconnected
        // and hasn't homed yet), `-1` is the documented "position unknown"
        // sentinel consumed by the UI. The actual move-to-position call
        // below propagates its own errors via `.map_err`.
        let from_position = get_device_manager()
            .filter_wheel_get_position(fw_id)
            .await
            .unwrap_or(-1);

        // Emit filter changing event
        self.app_state.publish_event(create_event_auto_id(
            EventSeverity::Info,
            EventCategory::Equipment,
            EventPayload::Equipment(EquipmentEvent::FilterChanging {
                from_position,
                to_position: position,
                filter_name: None, // Will be populated by UI if available
            }),
        ));

        let result = get_device_manager()
            .filter_wheel_set_position(fw_id, position)
            .await
            .map_err(|e| format!("Set position failed: {}", e));

        if result.is_ok() {
            self.app_state.publish_event(create_event_auto_id(
                EventSeverity::Info,
                EventCategory::Equipment,
                EventPayload::Equipment(EquipmentEvent::FilterChanged {
                    position,
                    filter_name: None,
                }),
            ));
        }

        result
    }

    async fn filterwheel_get_position(&self, fw_id: &str) -> DeviceResult<i32> {
        get_device_manager()
            .filter_wheel_get_position(fw_id)
            .await
            .map_err(|e| format!("Get position failed: {}", e))
    }

    async fn filterwheel_get_names(&self, fw_id: &str) -> DeviceResult<Vec<String>> {
        let (_, names) = get_device_manager()
            .filter_wheel_get_config(fw_id)
            .await
            .map_err(|e| format!("Get names failed: {}", e))?;
        Ok(names)
    }

    async fn filterwheel_set_filter_by_name(&self, fw_id: &str, name: &str) -> DeviceResult<i32> {
        let names = self.filterwheel_get_names(fw_id).await?;

        // Find the filter position by name (case-insensitive)
        let index = find_filter_match(&names, name)
            .ok_or_else(|| format!("Filter '{}' not found", name))?;

        // Pass Nightshade's canonical 0-based index for EVERY driver. The INDI
        // path (DeviceManager::filter_wheel_set_position -> IndiFilterWheel::
        // set_position) already takes a 0-based index and converts it to the
        // driver's native wire slot (0- or 1-based, auto-detected). The previous
        // INDI-only `index + 1` therefore double-counted the slot base, shifting
        // every filter by one and running the last filter off the end of the wheel.
        let position = index as i32;

        self.filterwheel_set_position(fw_id, position).await?;
        Ok(position)
    }

    // =========================================================================
    // ROTATOR OPERATIONS
    // =========================================================================

    async fn rotator_move_to(&self, rotator_id: &str, angle: f64) -> DeviceResult<()> {
        tracing::info!("Moving rotator {} to {}°", rotator_id, angle);

        // Emit rotator move started event
        self.app_state.publish_event(create_event_auto_id(
            EventSeverity::Info,
            EventCategory::Equipment,
            EventPayload::Equipment(EquipmentEvent::RotatorMoveStarted {
                target_angle: angle,
            }),
        ));

        let result = api_rotator_move_to(rotator_id.to_string(), angle)
            .await
            .map_err(|e| format!("Rotator move failed: {}", e));

        if result.is_ok() {
            self.app_state.publish_event(create_event_auto_id(
                EventSeverity::Info,
                EventCategory::Equipment,
                EventPayload::Equipment(EquipmentEvent::RotatorMoveCompleted { angle }),
            ));
        }

        result
    }

    async fn rotator_move_relative(&self, rotator_id: &str, delta: f64) -> DeviceResult<()> {
        tracing::info!("Moving rotator {} by {}°", rotator_id, delta);

        api_rotator_move_relative(rotator_id.to_string(), delta)
            .await
            .map_err(|e| format!("Rotator move relative failed: {}", e))
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
            .map_err(|e| format!("Halt failed: {}", e))
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
            .map_err(|e| format!("Failed to get guiding status: {}", e))?;

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
        tracing::info!("Starting guiding");

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

        // The optics, so the solver is told the field scale instead of hunting
        // for it. With `focal_length` and the pixel pitch left as None, ASTAP
        // gets a header with no scale information and falls back to sweeping
        // the field of view downward from ~9.5°. Observed live on a 0.37°
        // field: one run reached the bottom rung and solved in 0.3 s (still
        // warning "scale was inaccurate"), and the next three never converged
        // and exited non-zero on all five centering attempts. Same code, same
        // catalogs, same sensor — the only variable was whether the blind
        // sweep happened to land.
        //
        // Both values are measured, not assumed: the focal length is the
        // operator's own profile entry and the pitch is what the camera
        // reports. A device that reports neither contributes no card and the
        // solver behaves exactly as it did before.
        let mut focal_length_mm: Option<f64> = None;
        let mut pixel_size: Option<(f64, f64)> = None;
        let mut binning = (1, 1);
        if let Some(profile) = crate::get_state().get_profile().await {
            focal_length_mm = Some(profile.telescope_focal_length)
                .filter(|focal| focal.is_finite() && *focal > 0.0);

            if let Some(camera_id) = profile.camera_id.as_deref() {
                match get_camera_status(camera_id.to_string()).await {
                    Ok(status) => {
                        // 0.0 is a driver saying "I don't know", not a pitch.
                        if status.pixel_size_x > 0.0 && status.pixel_size_y > 0.0 {
                            pixel_size = Some((status.pixel_size_x, status.pixel_size_y));
                        }
                        if status.bin_x > 0 && status.bin_y > 0 {
                            binning = (status.bin_x, status.bin_y);
                        }
                    }
                    Err(e) => tracing::debug!(
                        "Plate solve: camera '{}' status unavailable ({}); solving without a \
                         pixel-scale hint",
                        camera_id,
                        e
                    ),
                }
            }
        }

        // A blind scale sweep is not an error and logs no warning of its own,
        // so without this line the fast reliable case and the slow unreliable
        // one look identical afterwards.
        match (focal_length_mm, pixel_size) {
            (Some(focal), Some((pitch_x, _))) => tracing::info!(
                "Plate solve scale hint: focal length {:.1} mm, pixel pitch {:.2} um \
                 ({:.2}\"/px unbinned)",
                focal,
                pitch_x,
                206.264_806 * pitch_x / focal
            ),
            _ => tracing::warn!(
                "Plate solve has no field-scale hint (focal length {}, pixel pitch {}); the \
                 solver must search for the scale, which is slower and can fail on a field it \
                 would otherwise solve. Set the telescope focal length on the active equipment \
                 profile.",
                focal_length_mm.map_or_else(|| "unknown".to_string(), |v| format!("{v:.1} mm")),
                pixel_size.map_or_else(|| "unknown".to_string(), |(x, _)| format!("{x:.2} um")),
            ),
        }

        // Save the image data to the temp file first
        let header = FitsWriteHeader {
            object_name: Some("Plate Solve".to_string()),
            exposure_time: image_data.exposure_secs,
            capture_timestamp: chrono::Utc::now()
                .to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
            frame_type: "Light".to_string(),
            filter: image_data.filter.clone(),
            gain: image_data.gain,
            offset: image_data.offset,
            ccd_temp: image_data.temperature,
            ra: hint_ra.map(|r| r / 15.0),
            dec: hint_dec,
            altitude: None,
            telescope: None,
            instrument: None,
            observer: None,
            bin_x: binning.0,
            bin_y: binning.1,
            focal_length: focal_length_mm,
            aperture: None,
            pixel_size_x: pixel_size.map(|(x, _)| x),
            pixel_size_y: pixel_size.map(|(_, y)| y),
            site_latitude: None,
            site_longitude: None,
            site_elevation: None,
        };

        api_save_fits_file(
            temp_path.clone(),
            image_data.width,
            image_data.height,
            image_data.data.clone(),
            header,
        )
        .await
        .map_err(|e| format!("Failed to save temp FITS for plate solve: {}", e))?;

        // Use the near solve if we have hints, otherwise blind solve.
        // Why: 5.0° search radius is the Nightshade
        // default for "near solve" when the caller does not specify a
        // scale hint — matches the plate-solve UI slider default.
        let result = if let (Some(ra), Some(dec)) = (hint_ra, hint_dec) {
            api_plate_solve_near(temp_path.clone(), ra, dec, hint_scale.unwrap_or(5.0), None).await
        } else {
            api_plate_solve_blind(temp_path.clone(), None).await
        };

        // Clean up temp file
        let _ = std::fs::remove_file(&temp_path);

        result
            .map(|r| PlateSolveResult {
                ra_degrees: r.ra,
                dec_degrees: r.dec,
                pixel_scale: r.pixel_scale,
                rotation: r.rotation,
                success: r.success,
            })
            .map_err(|e| format!("Plate solve failed: {}", e))
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

    async fn polar_align_update(&self, result: &PolarAlignResult) -> DeviceResult<()> {
        tracing::info!(
            "Polar Align Update: Alt {:.1}', Az {:.1}'",
            result.altitude_error,
            result.azimuth_error
        );

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
        // Calculate Local Sidereal Time
        let now = chrono::Utc::now();
        let jd = julian_day(&now);
        let lst = local_sidereal_time(jd, lon);

        // Calculate hour angle
        let ha = lst - ra_hours;
        let ha_rad = (ha * 15.0_f64).to_radians();
        let dec_rad = dec_degrees.to_radians();
        let lat_rad = lat.to_radians();

        // Calculate altitude
        let sin_alt = lat_rad.sin() * dec_rad.sin() + lat_rad.cos() * dec_rad.cos() * ha_rad.cos();
        sin_alt.asin().to_degrees()
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

        // Use DeviceManager which handles all driver types (ASCOM, Alpaca, INDI, Native)
        match get_device_manager().safety_is_safe(&device_id).await {
            Ok(is_safe) => {
                tracing::info!(
                    "Safety monitor {} reports: {}",
                    device_id,
                    if is_safe { "SAFE" } else { "UNSAFE" }
                );
                Ok(is_safe)
            }

            Err(e) => {
                tracing::error!("Failed to check safety monitor {}: {} - returning error for fail-mode handling", device_id, e);
                Err(format!("Safety check failed for {}: {}", device_id, e))
            }
        }
    }

    /// Trust-patch §2: feed HumidityThreshold triggers from the configured
    /// weather device. See the trait rustdoc for Ok(None) vs Err semantics.
    async fn weather_get_humidity(&self, weather_id: Option<&str>) -> DeviceResult<Option<f64>> {
        let device_id = match weather_id {
            Some(id) => id.to_string(),
            None => {
                let profile = self.app_state.get_profile().await;
                match profile.and_then(|p| p.weather_id) {
                    Some(id) => id,
                    None => return Ok(None),
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
        use nightshade_imaging::{detect_stars, StarDetectionConfig};

        // Convert to nightshade_imaging::ImageData
        let img = nightshade_imaging::ImageData::from_u16(
            image_data.width,
            image_data.height,
            1,
            &image_data.data,
        );

        let config = StarDetectionConfig::default();
        let stars = detect_stars(&img, &config);

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
        use nightshade_imaging::{detect_stars, StarDetectionConfig};

        // Convert to nightshade_imaging::ImageData
        let img = nightshade_imaging::ImageData::from_u16(
            image_data.width,
            image_data.height,
            1,
            &image_data.data,
        );

        let config = StarDetectionConfig::default();
        let stars = detect_stars(&img, &config);

        // Convert to (x, y, hfr) tuples
        let result: Vec<(f64, f64, f64)> = stars.iter().map(|s| (s.x, s.y, s.hfr)).collect();

        Ok(result)
    }

    async fn measure_frame_eccentricity(
        &self,
        image_data: &ImageData,
    ) -> DeviceResult<Option<f64>> {
        use nightshade_imaging::{detect_stars, frame_eccentricity, StarDetectionConfig};

        let img = nightshade_imaging::ImageData::from_u16(
            image_data.width,
            image_data.height,
            1,
            &image_data.data,
        );

        let config = StarDetectionConfig::default();
        let stars = detect_stars(&img, &config);

        // frame_eccentricity fails closed (returns None) when too few reliable
        // stars are present — never a fabricated value.
        Ok(frame_eccentricity(&stars))
    }

    // =========================================================================
    // COVER CALIBRATOR (FLAT PANEL) OPERATIONS
    // =========================================================================

    async fn cover_calibrator_open_cover(&self, device_id: &str) -> DeviceResult<()> {
        api_cover_calibrator_open_cover(device_id.to_string())
            .await
            .map_err(|e| format!("Open cover failed: {}", e))
    }

    async fn cover_calibrator_close_cover(&self, device_id: &str) -> DeviceResult<()> {
        api_cover_calibrator_close_cover(device_id.to_string())
            .await
            .map_err(|e| format!("Close cover failed: {}", e))
    }

    async fn cover_calibrator_halt_cover(&self, device_id: &str) -> DeviceResult<()> {
        api_cover_calibrator_halt_cover(device_id.to_string())
            .await
            .map_err(|e| format!("Halt cover failed: {}", e))
    }

    async fn cover_calibrator_calibrator_on(
        &self,
        device_id: &str,
        brightness: i32,
    ) -> DeviceResult<()> {
        api_cover_calibrator_calibrator_on(device_id.to_string(), brightness)
            .await
            .map_err(|e| format!("Calibrator on failed: {}", e))
    }

    async fn cover_calibrator_calibrator_off(&self, device_id: &str) -> DeviceResult<()> {
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

// =============================================================================
// FACTORY FUNCTION
// =============================================================================

/// Create a unified DeviceOps instance for the sequencer
///
/// This is the recommended way to get a DeviceOps implementation.
/// It uses the unified implementation that routes through the bridge API.
pub fn create_unified_device_ops() -> Arc<dyn nightshade_sequencer::DeviceOps> {
    Arc::new(UnifiedDeviceOps::new(crate::api::get_state().clone()))
}

/// Create a unified DeviceOps instance with a specific app state
pub fn create_unified_device_ops_with_state(
    app_state: SharedAppState,
) -> Arc<dyn nightshade_sequencer::DeviceOps> {
    Arc::new(UnifiedDeviceOps::new(app_state))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::get_device_manager;
    use crate::device::{DeviceInfo, DeviceType, DriverType};
    use crate::device_manager::DeviceManager;
    use nightshade_native::{
        CameraCapabilities, CameraState, CameraStatus, ExposureParams, ImageData, ImageMetadata,
        NativeCamera, NativeDevice, NativeError, NativeVendor, ReadoutMode, SensorInfo, SubFrame,
        VendorFeatures,
    };
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    };

    #[derive(Debug)]
    struct InstantCompleteCamera {
        id: String,
        name: String,
        vendor: NativeVendor,
        exposure_checked: Arc<AtomicUsize>,
        connected: bool,
    }

    impl InstantCompleteCamera {
        fn new(id: String, exposure_checked: Arc<AtomicUsize>) -> Self {
            Self {
                id: id.clone(),
                name: "Instant Complete Camera".to_string(),
                vendor: NativeVendor::Other("Test".to_string()),
                exposure_checked,
                connected: true,
            }
        }
    }

    #[async_trait::async_trait]
    impl NativeDevice for InstantCompleteCamera {
        fn id(&self) -> &str {
            &self.id
        }

        fn name(&self) -> &str {
            &self.name
        }

        fn vendor(&self) -> NativeVendor {
            self.vendor.clone()
        }

        fn is_connected(&self) -> bool {
            self.connected
        }

        async fn connect(&mut self) -> Result<(), NativeError> {
            self.connected = true;
            Ok(())
        }

        async fn disconnect(&mut self) -> Result<(), NativeError> {
            self.connected = false;
            Ok(())
        }
    }

    #[async_trait::async_trait]
    impl NativeCamera for InstantCompleteCamera {
        fn capabilities(&self) -> CameraCapabilities {
            CameraCapabilities::default()
        }

        async fn get_status(&self) -> Result<CameraStatus, NativeError> {
            Ok(CameraStatus {
                state: CameraState::Idle,
                sensor_temp: None,
                cooler_power: None,
                target_temp: None,
                cooler_on: false,
                gain: 0,
                offset: 0,
                bin_x: 1,
                bin_y: 1,
                exposure_remaining: None,
            })
        }

        async fn start_exposure(&mut self, _params: ExposureParams) -> Result<(), NativeError> {
            Ok(())
        }

        async fn abort_exposure(&mut self) -> Result<(), NativeError> {
            Ok(())
        }

        async fn is_exposure_complete(&self) -> Result<bool, NativeError> {
            self.exposure_checked.fetch_add(1, Ordering::SeqCst);
            Ok(true)
        }

        async fn download_image(&mut self) -> Result<ImageData, NativeError> {
            Ok(ImageData {
                width: 2,
                height: 2,
                data: vec![100, 200, 300, 400],
                bits_per_pixel: 16,
                bayer_pattern: None,
                metadata: ImageMetadata {
                    exposure_time: 0.5,
                    gain: 0,
                    offset: 0,
                    bin_x: 1,
                    bin_y: 1,
                    temperature: None,
                    timestamp: chrono::Utc::now(),
                    subframe: None,
                    readout_mode: None,
                    vendor_data: VendorFeatures::default(),
                },
            })
        }

        async fn set_cooler(
            &mut self,
            _enabled: bool,
            _target_temp: Option<f64>,
        ) -> Result<(), NativeError> {
            Ok(())
        }

        async fn get_temperature(&self) -> Result<f64, NativeError> {
            Ok(0.0)
        }

        async fn get_cooler_power(&self) -> Result<f64, NativeError> {
            Ok(0.0)
        }

        async fn set_gain(&mut self, _gain: i32) -> Result<(), NativeError> {
            Ok(())
        }

        async fn get_gain(&self) -> Result<i32, NativeError> {
            Ok(0)
        }

        async fn set_offset(&mut self, _offset: i32) -> Result<(), NativeError> {
            Ok(())
        }

        async fn get_offset(&self) -> Result<i32, NativeError> {
            Ok(0)
        }

        async fn set_binning(&mut self, _bin_x: i32, _bin_y: i32) -> Result<(), NativeError> {
            Ok(())
        }

        async fn get_binning(&self) -> Result<(i32, i32), NativeError> {
            Ok((1, 1))
        }

        async fn set_subframe(&mut self, _subframe: Option<SubFrame>) -> Result<(), NativeError> {
            Ok(())
        }

        fn get_sensor_info(&self) -> SensorInfo {
            SensorInfo {
                width: 2,
                height: 2,
                pixel_size_x: 1.0,
                pixel_size_y: 1.0,
                max_adu: 65535,
                bit_depth: 16,
                color: false,
                bayer_pattern: None,
            }
        }

        async fn get_readout_modes(&self) -> Result<Vec<ReadoutMode>, NativeError> {
            Ok(Vec::new())
        }

        async fn set_readout_mode(&mut self, _mode: &ReadoutMode) -> Result<(), NativeError> {
            Ok(())
        }

        async fn get_vendor_features(&self) -> Result<VendorFeatures, NativeError> {
            Ok(VendorFeatures::default())
        }

        async fn get_gain_range(&self) -> Result<(i32, i32), NativeError> {
            Err(NativeError::NotSupported)
        }

        async fn get_offset_range(&self) -> Result<(i32, i32), NativeError> {
            Err(NativeError::NotSupported)
        }
    }

    async fn cleanup_test_camera(mgr: &Arc<DeviceManager>, device_id: &str) {
        mgr.unregister_device(device_id).await;
        let mut native_cameras = mgr.native_cameras.write().await;
        native_cameras.remove(device_id);
    }

    #[tokio::test]
    async fn exposure_polling_short_circuits_when_complete() {
        let mgr = get_device_manager();
        let device_id = "native:test_camera_polling".to_string();
        let exposure_checked = Arc::new(AtomicUsize::new(0));

        let info = DeviceInfo {
            id: device_id.clone(),
            name: "Test Camera".to_string(),
            device_type: DeviceType::Camera,
            driver_type: DriverType::Native,
            description: "Test camera".to_string(),
            driver_version: "test".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: "Test Camera".to_string(),
        };

        mgr.register_device(info, false).await;
        {
            let mut native_cameras = mgr.native_cameras.write().await;
            native_cameras.insert(
                device_id.clone(),
                Box::new(InstantCompleteCamera::new(
                    device_id.clone(),
                    Arc::clone(&exposure_checked),
                )),
            );
        }

        let ops = UnifiedDeviceOps::new(crate::api::get_state().clone());
        let device_id_for_exposure = device_id.clone();
        let timed_result =
            tokio::time::timeout(std::time::Duration::from_millis(100), async move {
                ops.camera_start_exposure(&device_id_for_exposure, 0.5, None, None, 1, 1)
                    .await
            })
            .await;
        cleanup_test_camera(mgr, &device_id).await;

        let result = match timed_result {
            Ok(result) => result,
            Err(_) => {
                panic!("Expected exposure to complete without waiting when already complete");
            }
        };

        assert!(
            result.is_ok(),
            "Exposure should succeed when complete immediately"
        );
        assert!(
            exposure_checked.load(Ordering::SeqCst) > 0,
            "Exposure status should be checked at least once"
        );
    }

    #[tokio::test]
    async fn exposure_polling_times_out_when_driver_never_completes() {
        let poll_count = Arc::new(AtomicUsize::new(0));
        let result = wait_for_camera_exposure_complete(
            "native:test_hung_camera",
            300.0,
            std::time::Duration::from_millis(20),
            exposure_abort_generation("native:test_hung_camera").await,
            crate::api::get_state(),
            || {
                let poll_count = Arc::clone(&poll_count);
                async move {
                    poll_count.fetch_add(1, Ordering::SeqCst);
                    Ok(false)
                }
            },
        )
        .await;

        let err = result.expect_err("hung exposure polling should time out");
        assert!(
            err.contains("did not complete within"),
            "unexpected timeout error: {err}"
        );
        assert!(
            poll_count.load(Ordering::SeqCst) > 0,
            "exposure status should be polled before timing out"
        );
    }

    /// regression: the live `UnifiedDeviceOps` must OVERRIDE
    /// `device_is_connected` / `connect_device`. The `DeviceOps` trait
    /// defaults return `Err("… not supported by this driver")`, which made
    /// every device-disconnect recovery attempt fail instantly on the live
    /// path (the single most common unattended-night failure mode was
    /// unrecoverable). This asserts the overrides delegate to the
    /// `DeviceManager` rather than inheriting the defaults.
    #[tokio::test]
    async fn reconnect_overrides_are_wired_not_trait_default() {
        let ops = UnifiedDeviceOps::new(crate::api::get_state().clone());

        // Unknown device: the override consults the DeviceManager and reports
        // Ok(false). The trait default would instead return Err("not
        // supported"), so Ok(false) proves the override is in place.
        let connected = ops.device_is_connected("native:does_not_exist").await;
        assert_eq!(
            connected,
            Ok(false),
            "device_is_connected must be overridden (Ok(false) for an unknown \
             device), not the trait-default Err"
        );

        // connect_device on an unknown id errors, but it must be a real
        // DeviceManager "not found" error — NOT the trait-default
        // "connect_device not supported by this driver".
        let connect = ops.connect_device("native:does_not_exist").await;
        assert!(
            connect.is_err(),
            "connecting an unknown device should error"
        );
        let msg = connect.unwrap_err();
        assert!(
            !msg.contains("not supported by this driver"),
            "connect_device must be overridden; got the trait-default error: {msg}"
        );
    }
}

#[cfg(test)]
mod pointing_tests {
    use super::{
        altitude_degrees, build_rich_header, context_altitude_pointing, MountPointing,
        UnifiedDeviceOps,
    };
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
            "ns_unifiedops_{}_{}_{}",
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
    /// `Polaris_1_0001.fits` came out of `save_fits`, which is
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
        let ops = UnifiedDeviceOps::new(app_state);

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
        let ops = UnifiedDeviceOps::new(app_state);

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
