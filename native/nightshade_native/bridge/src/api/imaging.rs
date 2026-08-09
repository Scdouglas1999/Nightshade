// split from monolithic api.rs
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs.
//
// # `as`-cast policy
//
// This file is the FFI surface for imaging; numeric casts cluster into:
// - **Sensor-dimension widening** (`u32 as usize`, `u32 as f64`): >=32-bit
//   usize on every target; f64 mantissa fits any real sensor's pixel count.
// - **Bin / gain / exposure config** (`f64 as u16` or `u32 as f64`): bounded
//   by camera-driver advertised ranges. Saturation per Rust 1.45 spec matches
//   the "clamp out-of-range UI value" intent at the FFI boundary.
// - **Simulator math** (synthetic exposure path): pixel counts and star
//   counts are bounded by simulator config; the previously-overflowing
//   `width * height` allocations were hardened in W12 with explicit
//   `checked_mul` and `u64` promotion (see `simulate_*` helpers below).
// - **Histogram indexing** (`pixel as usize`): pixel is u16; usize on every
//   target trivially holds 65536 entries.
//
// Sites with their own `Why:` comment override the module-level reasoning.
//
// # `unwrap_or` policy
//
// Three documented patterns appear in this file:
//
// 1. **Float partial_cmp in sort** — `a.partial_cmp(b).unwrap_or(Ordering::Equal)`.
//    Required because `f32`/`f64` are `PartialOrd`, not `Ord`, due to NaN.
//    Treating NaN as `Equal` keeps the sort stable; HFR/SNR computation
//    upstream already filters out NaN before this point, so the fallback is
//    only protective.
// 2. **`SystemTime::elapsed().unwrap_or(Duration::ZERO)`** — `elapsed()`
//    only errors when the monotonic clock went backwards (a system-clock
//    adjustment). Reporting "0 elapsed" is the standard recovery and our
//    timing dashboards already skip the resulting outlier frame.
// 3. **Optional config defaults** — `config.min_hfr.unwrap_or(1.0)`,
//    `config.min_snr.unwrap_or(5.0)`, `config.max_sharpness.unwrap_or(0.95)`,
//    `BITPIX.unwrap_or(16)`, `extension().unwrap_or("fits")`. These are the
//    documented Nightshade-default science thresholds and FITS-format
//    fallback used when the FFI caller passes a minimal config. The same
//    defaults are surfaced in the science-quality UI as the placeholders.
// 4. **`min().unwrap_or(0)` / `max().unwrap_or(0)`** — empty image stripe
//    would already have failed validation upstream; `0` here is unreachable
//    but cheaper than `expect`. The `&min == &max == 0` produces a flat
//    histogram which the renderer handles gracefully.
//
// Hard-error paths (FFI deserialisation failures, missing-device errors)
// remain `Result<_, String>` propagation; no error class is silenced.
use crate::adaptive_polling::{AdaptivePoller, PollerPreset};
use crate::device::*;
use crate::device_manager::DeviceManager;
use crate::error::*;
use crate::event::*;
use crate::state::*;
use crate::storage::{AppSettings, ObserverLocation};
use crate::unified_device_ops::create_unified_device_ops;
use nightshade_imaging::{
    calculate_airmass, validate_fits_header, validate_image, write_fits, BayerPattern,
    DebayerAlgorithm, FitsHeader, ImageData,
};
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::sync::RwLock;
// Sibling-module items via the parent's pub use re-exports.
use super::*;

// =============================================================================
// Camera Exposure & Image Capture
// =============================================================================

/// Global cancellation token for autofocus
pub(crate) static AUTOFOCUS_CANCEL_TOKEN: OnceLock<Arc<AtomicBool>> = OnceLock::new();

pub(crate) fn get_autofocus_cancel_token() -> &'static Arc<AtomicBool> {
    // OnceLock is immutable after initialization, so reuse one persistent token
    // and reset its flag between autofocus runs.
    AUTOFOCUS_CANCEL_TOKEN.get_or_init(|| Arc::new(AtomicBool::new(false)))
}

/// Autofocus configuration for API
#[derive(Debug, Clone)]
pub struct AutofocusConfigApi {
    pub exposure_time: f64,
    pub step_size: i32,
    pub steps_out: i32,
    pub method: String, // "VCurve", "Hyperbolic", "Parabolic"
    pub binning: i32,
    pub gain: Option<i32>,
    pub offset: Option<i32>,
    pub number_of_attempts: u32,
    pub exposures_per_point: u32,
    pub r_squared_threshold: f64,
    pub outer_crop_ratio: f64,
    pub inner_crop_ratio: f64,
    pub use_brightest_n_stars: u32,
    pub focuser_settle_time_ms: u64,
    pub backlash_comp_method: String,
    pub backlash_in: i32,
    pub backlash_out: i32,
}

/// A single focus data point (position and HFR)
#[derive(Debug, Clone)]
pub struct FocusDataPoint {
    pub position: i32,
    pub hfr: f64,
    pub fwhm: Option<f64>,
    pub star_count: u32,
}

/// Autofocus result containing all data for display and analysis
#[derive(Debug, Clone)]
pub struct AutofocusResultApi {
    pub best_position: i32,
    pub best_hfr: f64,
    pub focus_data: Vec<FocusDataPoint>,
    pub method: String,
    pub temperature: Option<f64>,
    pub timestamp: i64,
    pub curve_fit_quality: f64,
    pub backlash_applied: bool,
}

/// Run autofocus
pub async fn api_run_autofocus(
    device_id: String, // Focuser ID
    camera_id: String,
    config: AutofocusConfigApi,
) -> Result<AutofocusResultApi, NightshadeError> {
    tracing::info!(
        "Starting autofocus with camera {} and focuser {}",
        camera_id,
        device_id
    );

    if !config.exposure_time.is_finite() || config.exposure_time <= 0.0 {
        return Err(NightshadeError::InvalidParameter(
            "autofocus exposure time must be finite and positive".to_string(),
        ));
    }
    if config.step_size <= 0 || !(1..=50).contains(&config.steps_out) {
        return Err(NightshadeError::InvalidParameter(
            "autofocus step size must be positive and steps out must be 1..50".to_string(),
        ));
    }
    if !(1..=4).contains(&config.binning)
        || !(1..=10).contains(&config.number_of_attempts)
        || !(1..=20).contains(&config.exposures_per_point)
    {
        return Err(NightshadeError::InvalidParameter(
            "autofocus binning, attempts, or exposures-per-point is out of range".to_string(),
        ));
    }
    if !config.r_squared_threshold.is_finite()
        || !(0.0..=1.0).contains(&config.r_squared_threshold)
        || !config.outer_crop_ratio.is_finite()
        || !config.inner_crop_ratio.is_finite()
        || config.outer_crop_ratio <= 0.0
        || config.outer_crop_ratio > 1.0
        || config.inner_crop_ratio < 0.0
        || config.inner_crop_ratio >= config.outer_crop_ratio
    {
        return Err(NightshadeError::InvalidParameter(
            "autofocus R²/crop settings are invalid".to_string(),
        ));
    }
    if config.focuser_settle_time_ms > 10_000 || config.backlash_in < 0 || config.backlash_out < 0 {
        return Err(NightshadeError::InvalidParameter(
            "autofocus settle/backlash settings are out of range".to_string(),
        ));
    }
    if config.gain.is_some_and(|gain| gain < 0) || config.offset.is_some_and(|offset| offset < 0) {
        return Err(NightshadeError::InvalidParameter(
            "autofocus gain and offset cannot be negative".to_string(),
        ));
    }

    use nightshade_sequencer::instructions::{
        execute_autofocus_admitted, try_admit_autofocus_run, InstructionContext,
    };
    use nightshade_sequencer::{AutofocusConfig, AutofocusMethod, Binning, NodeStatus};
    use serde::Deserialize;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[derive(Debug, Deserialize)]
    struct LegacyAutofocusPayload {
        best_position: i32,
        best_hfr: f64,
        r_squared: f64,
        focus_data: Vec<(i32, f64)>,
    }

    let autofocus_guard = try_admit_autofocus_run().ok_or_else(|| NightshadeError::DeviceBusy {
        device_id: device_id.clone(),
        current_operation: "autofocus".to_string(),
    })?;

    // Reset cancellation token only after admission. A rejected second Start
    // must never clear the active run's pending cancellation request.
    let cancel_token = get_autofocus_cancel_token();
    cancel_token.store(false, Ordering::Relaxed);

    // Store the method string for result
    let method_str = config.method.clone();

    // Map method string to enum
    let method = match config.method.as_str() {
        "Hyperbolic" => AutofocusMethod::Hyperbolic,
        "Parabolic" => AutofocusMethod::Quadratic,
        _ => AutofocusMethod::VCurve,
    };

    // Map binning
    let binning = match config.binning {
        2 => Binning::Two,
        3 => Binning::Three,
        4 => Binning::Four,
        _ => Binning::One,
    };

    let backlash_enabled = !config
        .backlash_comp_method
        .trim()
        .eq_ignore_ascii_case("none");
    let af_config = AutofocusConfig {
        exposure_duration: config.exposure_time,
        step_size: config.step_size,
        steps_out: config.steps_out as u32,
        method,
        binning,
        filter: None, // Optional: add filter support
        gain: config.gain,
        offset: config.offset,
        max_duration_secs: 600.0,
        number_of_attempts: config.number_of_attempts,
        exposures_per_point: config.exposures_per_point,
        r_squared_threshold: config.r_squared_threshold,
        outer_crop_ratio: config.outer_crop_ratio,
        inner_crop_ratio: config.inner_crop_ratio,
        use_brightest_n_stars: config.use_brightest_n_stars,
        focuser_settle_time_ms: config.focuser_settle_time_ms,
        backlash_compensation: if backlash_enabled {
            config.backlash_in
        } else {
            0
        },
        backlash_out_compensation: if backlash_enabled {
            config.backlash_out
        } else {
            0
        },
        ..AutofocusConfig::default()
    };

    // Create context - use UnifiedDeviceOps which routes through DeviceManager
    let device_ops = create_unified_device_ops();

    // Try to get focuser temperature before autofocus
    let temperature = device_ops
        .focuser_get_temperature(&device_id)
        .await
        .ok()
        .flatten();

    // spawn an executor-event bridge so instruction-level
    // emergencies (FITS-save failures from the autofocus V-curve frames, etc.)
    // reach the same NightshadeEvent stream Dart subscribes to. Without this
    // the user only sees a generic "autofocus failed" return code with no
    // hint that the underlying problem was a write error or drive disconnect.
    // The original sender lives on the stack for the duration of the call;
    // the cloned handle is moved into `InstructionContext::event_tx`. When the
    // function returns and the binding is dropped, the background bridge task
    // exits naturally.
    let event_tx =
        crate::util::executor_event_bridge::spawn_executor_event_bridge(get_state().clone());
    let progress_focuser_id = device_id.clone();

    let ctx = InstructionContext {
        // One-shot bridge capture: no producing sequence node.
        node_id: String::new(),
        target_ra: None,
        target_dec: None,
        target_name: None,
        target_rotation: None,
        current_filter: None,
        current_binning: Binning::One,
        cancellation_token: cancel_token.clone(),
        camera_id: Some(camera_id),
        mount_id: None,
        focuser_id: Some(device_id),
        filterwheel_id: None,
        dome_id: None,
        rotator_id: None,
        cover_calibrator_id: None,
        save_path: None,
        latitude: None,
        longitude: None,
        device_ops,
        trigger_state: None,
        filter_focus_offsets: std::collections::HashMap::new(),
        event_tx: Some(event_tx.clone()),
        recovery_request_tx: None,
        // Image Grading: standalone autofocus from the API does
        // not save FITS frames, so empty FITS-metadata defaults are
        // honest here. The InstructionContext fields exist to be passed
        // through to execute_exposure; execute_autofocus ignores them.
        session_id: String::new(),
        target_id: None,
        mosaic_panel: None,
        current_filter_index: None,
        set_temp_c: None,
        bayer_pattern: None,
        observer_name: None,
        site_elevation_m: None,
        camera_make: None,
        camera_model: None,
        telescope_name: None,
        telescope_focal_length_mm: None,
        telescope_aperture_mm: None,
        last_plate_solve: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
        hfr_baseline: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
        hfr_baseline_samples: std::sync::Arc::new(tokio::sync::RwLock::new(Vec::new())),
        consecutive_rejects: std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0)),
        frames_accepted: std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0)),
        frames_rejected: std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0)),
        default_quality_check: None,
        reject_folder_path: None,
        // defect map state. Standalone autofocus from
        // the API does not save FITS frames so this is unused; pass an
        // empty slot to satisfy the struct contract.
        defect_map_apply: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
        // Forensics: standalone autofocus doesn't grade frames.
        forensics_history: std::sync::Arc::new(tokio::sync::RwLock::new(
            std::collections::VecDeque::new(),
        )),
        current_sky_brightness_mag: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
        cloud_motion_snapshot: std::sync::Arc::new(tokio::sync::RwLock::new(
            nightshade_sequencer::CloudMotionSnapshot::default(),
        )),
        current_wind_kph: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
        current_sensor_temp_c: std::sync::Arc::new(tokio::sync::RwLock::new(None)),
        // Replay Debug — one-shot bridge API doesn't emit decisions.
        decision_tx: None,
        active_sequence_run_id: std::sync::Arc::new(parking_lot::RwLock::new(None)),
        // Standalone autofocus from the API is not driven by the node-runtime
        // disconnect-retry loop, so this one-shot context owns a fresh,
        // unshared flag (no recovery driver observes it here).
        device_disconnect_recovery_pending: std::sync::Arc::new(
            std::sync::atomic::AtomicBool::new(false),
        ),
        // Dual-rig — standalone autofocus runs with no secondary coordination.
        dither_barrier: None,
    };

    let progress_fn = |_: f64, detail: String| {
        if !detail.contains("\"type\":\"autofocus_progress\"") {
            return;
        }
        get_state().publish_equipment_event(
            EquipmentEvent::PropertyChanged {
                device_type: "focuser".to_string(),
                device_id: progress_focuser_id.clone(),
                property: "AutofocusProgress".to_string(),
                value: detail,
            },
            EventSeverity::Info,
        );
    };

    let result =
        execute_autofocus_admitted(&af_config, &ctx, Some(&progress_fn), autofocus_guard).await;

    // Get current timestamp
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    match result.status {
        NodeStatus::Success => {
            let data = result.data.ok_or_else(|| {
                NightshadeError::OperationFailed(
                    "Autofocus completed without a result payload".to_string(),
                )
            })?;

            // Canonical payload (nightshade_sequencer::AutofocusResult)
            if let Ok(af_result) =
                serde_json::from_value::<nightshade_sequencer::AutofocusResult>(data.clone())
            {
                let focus_data: Vec<FocusDataPoint> = af_result
                    .data_points
                    .iter()
                    .map(|dp| FocusDataPoint {
                        position: dp.position,
                        hfr: dp.hfr,
                        fwhm: dp.fwhm,
                        star_count: dp.star_count,
                    })
                    .collect();

                return Ok(AutofocusResultApi {
                    best_position: af_result.best_position,
                    best_hfr: af_result.best_hfr,
                    focus_data,
                    method: method_str,
                    temperature: af_result.temperature_celsius.or(temperature),
                    timestamp,
                    curve_fit_quality: af_result.curve_fit_quality,
                    backlash_applied: af_result.backlash_applied,
                });
            }

            // Backward compatibility for legacy tuple payloads
            if let Ok(legacy) = serde_json::from_value::<LegacyAutofocusPayload>(data.clone()) {
                let focus_data = legacy
                    .focus_data
                    .into_iter()
                    .map(|(position, hfr)| FocusDataPoint {
                        position,
                        hfr,
                        fwhm: None,
                        star_count: 0,
                    })
                    .collect();
                return Ok(AutofocusResultApi {
                    best_position: legacy.best_position,
                    best_hfr: legacy.best_hfr,
                    focus_data,
                    method: method_str,
                    temperature,
                    timestamp,
                    curve_fit_quality: legacy.r_squared,
                    backlash_applied: false,
                });
            }

            Err(NightshadeError::OperationFailed(
                "Autofocus completed but returned an unrecognized payload format".to_string(),
            ))
        }
        NodeStatus::Failure => Err(NightshadeError::OperationFailed(
            result.message.unwrap_or("Autofocus failed".to_string()),
        )),
        NodeStatus::Cancelled => Err(NightshadeError::Cancelled),
        _ => Err(NightshadeError::OperationFailed(
            "Unknown error".to_string(),
        )),
    }
}

/// Cancel autofocus
pub async fn api_cancel_autofocus() -> Result<(), NightshadeError> {
    tracing::info!("Cancelling autofocus...");
    let cancel_token = get_autofocus_cancel_token();
    cancel_token.store(true, Ordering::Relaxed);
    Ok(())
}

// =============================================================================
// Camera Exposure & Image Capture
// =============================================================================

/// Captured image result containing display-ready data
#[derive(Debug, Clone)]
pub struct CapturedImageResult {
    pub width: u32,
    pub height: u32,
    pub display_data: Vec<u8>, // Always RGBA (width*height*4), alpha=255
    pub histogram: Vec<u32>,   // 256-bin histogram (computed from pre-RGBA pixel values)
    pub stats: ImageStatsResult,
    pub exposure_time: f64,
    pub timestamp: String,
    pub is_color: bool, // true if source was color (RGB), false if grayscale — retained for stretch/analysis paths
}

/// Convert grayscale (1 byte/pixel) or RGB (3 bytes/pixel) display data to RGBA (4 bytes/pixel).
/// Uses rayon for parallel conversion on large images.
pub(crate) fn display_data_to_rgba(data: &[u8], is_color: bool) -> Vec<u8> {
    if is_color {
        // RGB -> RGBA
        let num_pixels = data.len() / 3;
        let mut rgba = vec![0u8; num_pixels * 4];
        rgba.par_chunks_exact_mut(4)
            .zip(data.par_chunks_exact(3))
            .for_each(|(dst, src)| {
                dst[0] = src[0]; // R
                dst[1] = src[1]; // G
                dst[2] = src[2]; // B
                dst[3] = 255; // A
            });
        rgba
    } else {
        // Grayscale -> RGBA
        let num_pixels = data.len();
        let mut rgba = vec![0u8; num_pixels * 4];
        rgba.par_chunks_exact_mut(4)
            .zip(data.par_iter())
            .for_each(|(dst, &gray)| {
                dst[0] = gray; // R
                dst[1] = gray; // G
                dst[2] = gray; // B
                dst[3] = 255; // A
            });
        rgba
    }
}

/// Image statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageStatsResult {
    pub min: f64,
    pub max: f64,
    pub mean: f64,
    pub median: f64,
    pub std_dev: f64,
    pub hfr: Option<f64>,
    /// Per-frame median star eccentricity (0.0 = round, →1.0 = trailed).
    /// `None` when too few reliable stars to honestly measure — never a
    /// fabricated value.
    pub eccentricity: Option<f64>,
    pub fwhm: Option<f64>,
    pub star_count: u32,
}

/// Raw image info with metadata - used by sequencer for actual image analysis
/// This preserves the original 16-bit sensor data needed for HFR calculation, plate solving, etc.
#[derive(Debug, Clone)]
pub struct RawImageInfo {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u16>,                   // Raw 16-bit sensor data
    pub sensor_type: Option<String>,      // "Monochrome" or "Color"
    pub bayer_offset: Option<(i32, i32)>, // Bayer pattern offset for color sensors
}

/// Unified captured image data - contains all image data for atomic updates
/// This ensures the UI never sees inconsistent state between raw data and display data
#[derive(Debug, Clone)]
pub struct CapturedImageData {
    /// Display-ready image result (8-bit for UI)
    pub display: CapturedImageResult,
    /// Raw 16-bit image info with metadata (for FITS saving, HFR, etc.)
    pub raw_info: RawImageInfo,
}

/// Per-device image storage capacity.
///
/// Why 50: A typical 4-hour imaging session at 30s exposures produces ~480 frames,
/// but the storage is keyed by device-id, not by frame, so each connected camera
/// occupies one slot. 50 covers any realistic rig (1-5 cameras) with generous
/// headroom for transient reconnections that rotate the device-id (e.g. USB
/// re-enumeration appending a new serial suffix). At ~24 MB per u16 frame
/// (4144x2822 sensors), the cap holds worst-case ~1.2 GB which keeps 16 GB
/// laptops safe under prolonged sessions.
pub(crate) const UNIFIED_IMAGE_STORAGE_CAPACITY: usize = 50;

/// Per-device image storage - keyed by device ID to support multi-camera operation.
///
/// Each camera's image data is stored independently, preventing race conditions
/// where concurrent cameras could overwrite each other's captured images.
///
/// Bounded with an LRU policy so unique device-ids accumulated over long sessions
/// (USB re-enumeration, network device churn) cannot leak raw u16 buffers
/// indefinitely. On eviction the oldest-touched entry is dropped and a debug
/// trace is emitted; see `store_captured_image_atomically`.
pub(crate) static UNIFIED_IMAGE_STORAGE: OnceLock<
    Arc<tokio::sync::Mutex<lru::LruCache<String, CapturedImageData>>>,
> = OnceLock::new();

pub(crate) fn get_unified_image_storage(
) -> &'static Arc<tokio::sync::Mutex<lru::LruCache<String, CapturedImageData>>> {
    UNIFIED_IMAGE_STORAGE.get_or_init(|| {
        let cap = std::num::NonZeroUsize::new(UNIFIED_IMAGE_STORAGE_CAPACITY)
            .expect("UNIFIED_IMAGE_STORAGE_CAPACITY must be non-zero");
        Arc::new(tokio::sync::Mutex::new(lru::LruCache::new(cap)))
    })
}

/// Store captured image data atomically for a specific device
/// This ensures all image-related data (display, raw, metadata) is updated together,
/// preventing race conditions where the UI could see inconsistent state.
///
/// If the cache is at capacity and `device_id` is not already present, the
/// least-recently-used entry is evicted. Evictions emit a `tracing::debug!`
/// trace so memory pressure on long sessions is observable.
pub(crate) async fn store_captured_image_atomically(
    device_id: &str,
    display: CapturedImageResult,
    raw_info: RawImageInfo,
) {
    let mut storage = get_unified_image_storage().lock().await;
    let value = CapturedImageData { display, raw_info };
    if let Some((evicted_id, _evicted)) = storage.push(device_id.to_string(), value) {
        if evicted_id != device_id {
            tracing::debug!(
                "UNIFIED_IMAGE_STORAGE: evicted LRU entry for device_id={} (cap={})",
                evicted_id,
                UNIFIED_IMAGE_STORAGE_CAPACITY
            );
        }
    }
}

/// Start a camera exposure
/// Returns progress updates via events, final image available via api_get_last_image
/// Public bridge entry point. Gain/offset are explicit (`i32`) here so the
/// generated FFI signature stays stable; this delegates to
/// [`camera_start_exposure_opt`] with `Some(..)`, commanding both values
/// exactly as before.
pub async fn api_camera_start_exposure(
    device_id: String,
    duration_secs: f64,
    gain: i32,
    offset: i32,
    bin_x: i32,
    bin_y: i32,
) -> Result<(), NightshadeError> {
    camera_start_exposure_opt(
        device_id,
        duration_secs,
        Some(gain),
        Some(offset),
        bin_x,
        bin_y,
    )
    .await
}

/// Start an exposure without collapsing omitted controls to zero and with the
/// complete per-frame geometry/frame-type contract.
#[allow(clippy::too_many_arguments)]
pub async fn api_camera_start_exposure_configured(
    device_id: String,
    duration_secs: f64,
    gain: Option<i32>,
    offset: Option<i32>,
    bin_x: i32,
    bin_y: i32,
    start_x: Option<u32>,
    start_y: Option<u32>,
    width: Option<u32>,
    height: Option<u32>,
    frame_type: String,
) -> Result<(), NightshadeError> {
    let supplied = [
        start_x.is_some(),
        start_y.is_some(),
        width.is_some(),
        height.is_some(),
    ];
    let subframe = if supplied.iter().all(|value| *value) {
        let width = width.expect("checked above");
        let height = height.expect("checked above");
        if width == 0 || height == 0 {
            return Err(NightshadeError::InvalidParameter(
                "Camera subframe width and height must be positive".to_string(),
            ));
        }
        Some(nightshade_sequencer::CameraSubframe {
            start_x: start_x.expect("checked above"),
            start_y: start_y.expect("checked above"),
            width,
            height,
        })
    } else if supplied.iter().any(|value| *value) {
        return Err(NightshadeError::InvalidParameter(
            "Camera subframe requires start_x, start_y, width, and height together".to_string(),
        ));
    } else {
        None
    };

    camera_start_exposure_configured_opt(
        device_id,
        duration_secs,
        gain,
        offset,
        bin_x,
        bin_y,
        subframe,
        nightshade_native::camera::FrameType::from_str_lenient(&frame_type),
    )
    .await
}

/// Start a camera exposure with *optional* gain/offset.
///
/// `None` means "leave the camera's current gain/offset unchanged": it is
/// threaded through to the device layer (which skips the setter for `None`)
/// and is NOT collapsed to `0`, which on drivers that honor it would actively
/// command a gain/offset of zero. Internal callers that carry the documented
/// "camera default" semantics (e.g. polar alignment) use this directly.
pub(crate) async fn camera_start_exposure_opt(
    device_id: String,
    duration_secs: f64,
    gain: Option<i32>,
    offset: Option<i32>,
    bin_x: i32,
    bin_y: i32,
) -> Result<(), NightshadeError> {
    camera_start_exposure_configured_opt(
        device_id,
        duration_secs,
        gain,
        offset,
        bin_x,
        bin_y,
        None,
        nightshade_native::camera::FrameType::Light,
    )
    .await
}

/// Turn a `DeviceOps` capture error into the narrowest `NightshadeError` that
/// still describes it.
///
/// Why this exists: `camera_start_exposure_configured` reports every failure as
/// a bare `String`, and mapping the lot to [`NightshadeError::OperationFailed`]
/// made the headless API answer HTTP 500 `internal_error` for outcomes that are
/// neither internal nor faults. Observed on the rig with a real ASI1600MM: a
/// daylight frame came back completely saturated and the API returned
///
/// ```text
/// HTTP 500 {"error":"internal_error","message":"Image validation failed: Image
/// is completely saturated (min value 65224 >= 65024) - significantly reduce
/// exposure time or gain"}
/// ```
///
/// The camera had worked perfectly and the message was already actionable; only
/// the envelope was wrong, and a client with retry-on-5xx would have retried a
/// request that can only fail again. Frames rejected by validation now become
/// [`NightshadeError::ExposureFailed`], which the headless mapper renders as 422.
/// Everything else keeps falling through to `OperationFailed` (HTTP 500), so
/// genuine driver and transport faults are unaffected.
fn classify_exposure_failure(device_id: &str, error: String) -> NightshadeError {
    match error.strip_prefix(crate::unified_device_ops::IMAGE_VALIDATION_FAILED_PREFIX) {
        Some(reason) => NightshadeError::ExposureFailed {
            camera_id: device_id.to_string(),
            reason: reason.to_string(),
        },
        None => NightshadeError::OperationFailed(error),
    }
}

/// Terminate a simulated exposure the operator aborted.
///
/// Mirrors what the real path does after its own generation check: park the
/// sensor, publish a FAILED completion so nothing downstream treats the
/// abandoned frame as a keeper, and report the cancellation to the caller.
async fn sim_exposure_cancelled() -> Result<(), NightshadeError> {
    {
        let mut camera = get_sim_camera().write().await;
        camera.status.state = CameraState::Idle;
    }
    get_state().publish_imaging_event(
        ImagingEvent::ExposureComplete { success: false },
        EventSeverity::Info,
    );
    tracing::info!("Exposure cancelled");
    Err(NightshadeError::OperationFailed(
        "Exposure cancelled".to_string(),
    ))
}

#[allow(clippy::too_many_arguments)]
pub(crate) async fn camera_start_exposure_configured_opt(
    device_id: String,
    duration_secs: f64,
    gain: Option<i32>,
    offset: Option<i32>,
    bin_x: i32,
    bin_y: i32,
    subframe: Option<nightshade_sequencer::CameraSubframe>,
    frame_type: nightshade_native::camera::FrameType,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Starting {}s exposure with gain={:?}, offset={:?}, bin={}x{}",
        duration_secs,
        gain,
        offset,
        bin_x,
        bin_y
    );

    // Check if simulator or real device
    if device_id.starts_with("sim_") {
        // Simulator path (existing code)
        // Same abort ledger the real path uses, so `api_camera_cancel_exposure`
        // means the same thing on both. Without it the simulated exposure ran
        // to full duration after the operator aborted, then published
        // ExposureComplete{success:true} and stored the frame — the one
        // failure mode a simulator must not have, because it makes an abort
        // that is broken look like an abort that works.
        let acquisition_generation =
            crate::unified_device_ops::exposure_abort_generation(&device_id).await;
        // Update camera state to exposing
        {
            let mut camera = get_sim_camera().write().await;
            camera.status.state = CameraState::Exposing;
        }

        // Publish exposure started event
        get_state().publish_imaging_event(
            ImagingEvent::ExposureStarted {
                duration_secs,
                frame_type: crate::device::FrameType::Light,
            },
            EventSeverity::Info,
        );

        // Simulate exposure with progress updates using adaptive polling
        // This reduces CPU overhead for long simulated exposures while maintaining
        // responsiveness for progress updates
        let start_time = std::time::Instant::now();
        let duration = std::time::Duration::from_secs_f64(duration_secs);
        let mut poller: AdaptivePoller<String> =
            AdaptivePoller::from_preset(PollerPreset::Exposure);

        while start_time.elapsed() < duration {
            if crate::unified_device_ops::exposure_abort_generation(&device_id).await
                != acquisition_generation
            {
                return sim_exposure_cancelled().await;
            }

            let progress = start_time.elapsed().as_secs_f64() / duration_secs;
            let progress_bucket = format!("{:.1}", progress); // Bucket progress for change detection

            get_state().publish_imaging_event(
                ImagingEvent::ExposureProgress {
                    progress,
                    remaining_secs: duration_secs - start_time.elapsed().as_secs_f64(),
                },
                EventSeverity::Info,
            );

            // Adaptive polling: backs off when progress isn't changing significantly
            let poll_interval = poller.tick(&progress_bucket);
            tokio::time::sleep(poll_interval).await;
        }

        // An abort landing during the last poll interval must still discard the
        // frame: storing it would put an exposure the operator gave up on into
        // the gallery and the session's frame count.
        if crate::unified_device_ops::exposure_abort_generation(&device_id).await
            != acquisition_generation
        {
            return sim_exposure_cancelled().await;
        }

        // Update camera state to reading
        {
            let mut camera = get_sim_camera().write().await;
            camera.status.state = CameraState::Reading;
        }

        // Render the frame through THE simulated-capture renderer — the same one
        // the sequencer's DeviceManager download uses.
        //
        // This branch used to call a local `generate_simulated_image()` that
        // painted `rand::thread_rng()` stars at random positions. It was not a
        // cosmetic difference: two consecutive captures at an IDENTICAL mount
        // pointing shared zero of their 40 brightest stars, and ASTAP (D05
        // installed, correct hint) detected 151 stars in one and still answered
        // `No solution found!` at every FOV from 9.5 deg down to 0.4 deg. So
        // everything downstream of a solve — Slew & Center, framing, mosaic
        // tiles, meridian-flip recentre, polar alignment — could never be
        // exercised from the Imaging screen, while the sequencer path solved
        // fine. One renderer now serves both.
        //
        // The simulator commands no real hardware, so an unspecified (None)
        // gain falls back to 0 for brightness math.
        let sim_gain = gain.unwrap_or(0);
        // The geometry the camera ADVERTISES, not a second hardcoded sensor.
        // These were 4144x2822 while `get_camera_status` reported SIM_W x SIM_H
        // (1920x1080), so the Framing screen drew an FOV box 2.16x too narrow
        // for the frames the same camera was delivering, and no measurement
        // taken through the manual-capture path could be compared with one from
        // the sequencer path.
        let (advertised_width, advertised_height, sim_pixel_size, sim_offset, sim_max_adu) = {
            let camera = get_sim_camera().read().await;
            (
                camera.status.sensor_width,
                camera.status.sensor_height,
                camera.status.pixel_size_x,
                camera.status.offset,
                camera.status.max_adu,
            )
        };
        let sim_frame =
            crate::sim_capture::render_sim_frame(crate::sim_capture::SimCaptureRequest {
                exposure_secs: duration_secs,
                sensor_width: advertised_width.max(1),
                sensor_height: advertised_height.max(1),
                pixel_size_um: sim_pixel_size,
                gain: sim_gain,
                offset: offset.unwrap_or(sim_offset),
                bin_x: bin_x.max(1) as u32,
                bin_y: bin_y.max(1) as u32,
                subframe: subframe
                    .as_ref()
                    .map(|roi| (roi.start_x, roi.start_y, roi.width, roi.height)),
                frame_type,
                max_adu: sim_max_adu.clamp(1, u32::from(u16::MAX)) as u16,
            })
            .await;
        // Binning and subframing both change the delivered geometry, so take it
        // from the renderer rather than re-deriving it here — the two used to
        // disagree.
        let (sensor_width, sensor_height) = (sim_frame.width, sim_frame.height);
        let raw_data = sim_frame.data;

        // Measure the simulated frame with the SAME code the real-camera branch
        // uses. The old branch reported `2.5 + random()` as HFR and
        // `0.15 + random()` as eccentricity — numbers that tracked nothing, so
        // an autofocus or guiding regression could not show up in them.
        let image_bytes: Vec<u8> = raw_data.iter().flat_map(|&val| val.to_le_bytes()).collect();
        let image = nightshade_imaging::ImageData {
            width: sensor_width,
            height: sensor_height,
            channels: 1,
            pixel_type: nightshade_imaging::PixelType::U16,
            data: image_bytes,
        };
        let stats = nightshade_imaging::calculate_stats_u16(&image);
        let stretch_params = nightshade_imaging::auto_stretch_stf(&image);
        let display_data_raw = nightshade_imaging::apply_stretch(&image, &stretch_params);
        let mut histogram = vec![0u32; 256];
        for &pixel in &display_data_raw {
            histogram[pixel as usize] += 1;
        }
        let stars = nightshade_imaging::detect_stars(
            &image,
            &nightshade_imaging::StarDetectionConfig::default(),
        );
        let star_count = stars.len() as u32;
        let median_of = |values: &mut Vec<f64>| -> Option<f64> {
            if values.is_empty() {
                return None;
            }
            values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
            Some(values[values.len() / 2])
        };
        // Top 50% brightest, capped at 50 — mirrors the real-camera branch.
        let sample = (stars.len() / 2).clamp(1, 50);
        let mut hfrs: Vec<f64> = stars
            .iter()
            .take(sample)
            .map(|s| s.hfr)
            .filter(|&h| h > 0.0 && h < 20.0)
            .collect();
        let median_hfr = median_of(&mut hfrs);
        let mut fwhms: Vec<f64> = stars
            .iter()
            .take(sample)
            .map(|s| s.fwhm)
            .filter(|&f| f > 0.0 && f < 20.0)
            .collect();
        let median_fwhm = median_of(&mut fwhms);
        // Fails closed (None) when too few reliable stars — never fabricated.
        let median_eccentricity = nightshade_imaging::frame_eccentricity(&stars);
        tracing::info!(
            "Simulated capture: {}x{}, {} stars detected, median HFR: {:?}, median ecc: {:?}",
            sensor_width,
            sensor_height,
            star_count,
            median_hfr,
            median_eccentricity
        );

        // Convert grayscale display data to RGBA for Flutter rendering
        let display_data = display_data_to_rgba(&display_data_raw, false);

        // Store all image data atomically to prevent race conditions
        // This ensures the UI never sees inconsistent state between raw and display data
        let display_result = CapturedImageResult {
            width: sensor_width,
            height: sensor_height,
            display_data,
            histogram,
            stats: ImageStatsResult {
                min: stats.min,
                max: stats.max,
                mean: stats.mean,
                median: stats.median,
                std_dev: stats.std_dev,
                hfr: median_hfr,
                eccentricity: median_eccentricity,
                fwhm: median_fwhm,
                star_count,
            },
            exposure_time: duration_secs,
            timestamp: chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S").to_string(),
            is_color: false, // Simulated images are grayscale
        };

        let raw_info = RawImageInfo {
            width: sensor_width,
            height: sensor_height,
            data: raw_data,
            sensor_type: Some("Monochrome".to_string()), // Simulated camera is mono
            bayer_offset: None,
        };

        store_captured_image_atomically(&device_id, display_result, raw_info).await;

        // Update camera state back to idle
        {
            let mut camera = get_sim_camera().write().await;
            camera.status.state = CameraState::Idle;
        }

        // Publish exposure complete event
        get_state().publish_imaging_event(
            ImagingEvent::ExposureComplete { success: true },
            EventSeverity::Info,
        );

        tracing::info!("Exposure complete");
        Ok(())
    } else {
        // Real camera path - use UnifiedDeviceOps which routes through DeviceManager
        // Events (ExposureStarted, ExposureProgress, ExposureComplete) are published by UnifiedDeviceOps
        let device_ops = create_unified_device_ops();

        // Start exposure and get raw data (blocks until complete, events published by UnifiedDeviceOps)
        let seq_image = device_ops
            .camera_start_exposure_configured(
                &device_id,
                duration_secs,
                // Already Option: None leaves the driver's current value
                // untouched instead of forcing it to 0.
                gain,
                offset,
                bin_x,
                bin_y,
                subframe,
                frame_type.as_str(),
            )
            .await
            .map_err(|e| classify_exposure_failure(&device_id, e))?;

        // Convert SeqImageData to ImageData for processing
        let image = ImageData::from_u16(seq_image.width, seq_image.height, 1, &seq_image.data);

        // DIAGNOSTIC: Log raw data statistics to debug mid-gray image issue
        {
            let raw_data = &seq_image.data;
            if !raw_data.is_empty() {
                let min_val = raw_data.iter().min().copied().unwrap_or(0);
                let max_val = raw_data.iter().max().copied().unwrap_or(0);
                let sum: u64 = raw_data.iter().map(|&v| v as u64).sum();
                let mean_val = sum / raw_data.len() as u64;
                let unique_vals: std::collections::HashSet<_> =
                    raw_data.iter().take(10000).collect();
                tracing::info!(
                    "[DIAGNOSTIC] Raw image data: size={}, min={}, max={}, mean={}, unique_sample_count={}",
                    raw_data.len(), min_val, max_val, mean_val, unique_vals.len()
                );
                if max_val == min_val {
                    tracing::error!("[DIAGNOSTIC] WARNING: All pixels have same value! Data appears uniform/invalid.");
                } else if max_val < 100 {
                    tracing::warn!("[DIAGNOSTIC] WARNING: Max value is very low ({}), image may be underexposed or data corrupted.", max_val);
                } else if min_val > 60000 {
                    tracing::warn!("[DIAGNOSTIC] WARNING: Min value is very high ({}), image may be saturated.", min_val);
                }
            } else {
                tracing::error!("[DIAGNOSTIC] WARNING: Raw data is empty!");
            }
        }

        // Automatic color detection from camera metadata
        let is_color =
            seq_image.sensor_type.as_deref() == Some("Color") && seq_image.bayer_offset.is_some();

        // Determine Bayer pattern from offsets (if color)
        let bayer_pattern = if is_color {
            match seq_image.bayer_offset {
                Some((0, 0)) => BayerPattern::RGGB, // RGGB
                Some((1, 0)) => BayerPattern::GRBG, // GRBG
                Some((0, 1)) => BayerPattern::GBRG, // GBRG
                Some((1, 1)) => BayerPattern::BGGR, // BGGR
                _ => BayerPattern::RGGB,            // Default
            }
        } else {
            BayerPattern::RGGB // Doesn't matter for mono
        };

        let display_data_raw: Vec<u8>;

        if is_color {
            // Color debayering path
            let algorithm = DebayerAlgorithm::Bilinear;

            tracing::info!("Debayering color image with pattern {:?}", bayer_pattern);

            // 2. Debayer to RGB16 (if color)
            // Safe conversion from u8 buffer to u16 values
            if image.data.len() % 2 != 0 {
                return Err(NightshadeError::ImageError(
                    "Odd byte count in image data — cannot convert to u16 pixels".to_string(),
                ));
            }
            let u16_data: Vec<u16> = image
                .data
                .chunks_exact(2)
                .map(|b| u16::from_ne_bytes([b[0], b[1]]))
                .collect();

            let mut rgb_data = nightshade_imaging::debayer_to_rgb16(
                &u16_data,
                seq_image.width,
                seq_image.height,
                bayer_pattern,
                algorithm,
            );

            // 2.5. Apply Auto White Balance (Histogram Peak Alignment)
            apply_auto_white_balance(&mut rgb_data);

            // 3. Auto-stretch RGB via the real STF engine (IMG-audit fix).
            //
            // Previously this path hard-coded `shadows = median - 0.1`,
            // `highlights = median + 0.3`, `midtones = 0.5` — a crude
            // percentile-tracking heuristic that ignored noise scale. Mono
            // captures used the proper MAD-based PixInsight STF
            // (`auto_stretch_stf`); color captures got this fallback. Result:
            // color cameras rendered with a perceptibly worse curve.
            //
            // Default to Unlinked (PixInsight's default): per-channel
            // independent STF maximizes per-channel contrast. The user can
            // still re-stretch with linked channels via the Dart-side
            // `AutoStretchSettings.linkedChannels` flag once auto-stretch is
            // explicitly enabled (see `auto_stretch_provider.dart`).
            //
            // # Degenerate-input contract ("errors are a feature")
            //
            // `auto_stretch_rgb_with_mode` returns `StretchParams::default()`
            // (shadows=0, highlights=1, midtones=0.5 — the identity MTF)
            // when a channel has MAD = 0 (constant data) or is empty. The
            // downstream `apply_stretch_rgb_per_channel` then emits an
            // identity stretch for that channel — never the old heuristic,
            // never a silent black frame. The previous fallback path that
            // erroneously errored on empty `sorted` is now unreachable
            // because the validation happens inside the imaging crate.
            let (r_params, g_params, b_params) = nightshade_imaging::auto_stretch_rgb_with_mode(
                &rgb_data,
                seq_image.width,
                seq_image.height,
                nightshade_imaging::RgbStretchMode::Unlinked,
            );

            tracing::info!(
                "[DIAGNOSTIC] RGB STF params (Unlinked): R(s={:.4}, h={:.4}, m={:.4}) \
                G(s={:.4}, h={:.4}, m={:.4}) B(s={:.4}, h={:.4}, m={:.4})",
                r_params.shadows,
                r_params.highlights,
                r_params.midtones,
                g_params.shadows,
                g_params.highlights,
                g_params.midtones,
                b_params.shadows,
                b_params.highlights,
                b_params.midtones,
            );

            // 4. Apply per-channel STF to convert RGB u16 -> RGB u8.
            display_data_raw = nightshade_imaging::apply_stretch_rgb_per_channel(
                &rgb_data,
                seq_image.width,
                seq_image.height,
                &r_params,
                &g_params,
                &b_params,
            );
        } else {
            // Grayscale: auto-stretch to u8
            let stretch_params = nightshade_imaging::auto_stretch_stf(&image);
            tracing::info!(
                "[DIAGNOSTIC] Stretch params: shadows={:.6}, highlights={:.6}, midtones={:.6}",
                stretch_params.shadows,
                stretch_params.highlights,
                stretch_params.midtones
            );
            display_data_raw = nightshade_imaging::apply_stretch(&image, &stretch_params);

            // Check display data distribution
            let display_min = display_data_raw.iter().min().copied().unwrap_or(0);
            let display_max = display_data_raw.iter().max().copied().unwrap_or(0);
            let display_sum: u64 = display_data_raw.iter().map(|&v| v as u64).sum();
            let display_mean = display_sum / display_data_raw.len() as u64;
            tracing::info!(
                "[DIAGNOSTIC] Display data after stretch: min={}, max={}, mean={}",
                display_min,
                display_max,
                display_mean
            );
        }

        // Calculate statistics
        let stats = nightshade_imaging::calculate_stats_u16(&image);
        let stars = nightshade_imaging::detect_stars(
            &image,
            &nightshade_imaging::StarDetectionConfig::default(),
        );
        let star_count = stars.len() as u32;

        // Compute median HFR from detected stars (top 50% brightest, capped at 50)
        let median_hfr = if !stars.is_empty() {
            let count = (stars.len() / 2).clamp(1, 50);
            let mut hfrs: Vec<f64> = stars
                .iter()
                .take(count)
                .map(|s| s.hfr)
                .filter(|&h| h > 0.0 && h < 20.0)
                .collect();
            if hfrs.is_empty() {
                None
            } else {
                hfrs.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                Some(hfrs[hfrs.len() / 2])
            }
        } else {
            None
        };
        // Compute median FWHM from detected stars (top 50% brightest, capped at 50)
        let median_fwhm = if !stars.is_empty() {
            let count = (stars.len() / 2).clamp(1, 50);
            let mut fwhms: Vec<f64> = stars
                .iter()
                .take(count)
                .map(|s| s.fwhm)
                .filter(|&f| f > 0.0 && f < 20.0)
                .collect();
            if fwhms.is_empty() {
                None
            } else {
                fwhms.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                Some(fwhms[fwhms.len() / 2])
            }
        } else {
            None
        };
        // Per-frame median eccentricity from the same detected stars. Fails
        // closed (None) when too few reliable stars — never fabricated.
        let median_eccentricity = nightshade_imaging::frame_eccentricity(&stars);
        tracing::info!(
            "Star detection: {} stars found, median HFR: {:?}, median ecc: {:?}",
            star_count,
            median_hfr,
            median_eccentricity
        );

        // Calculate histogram from pre-RGBA display data (256 bins for u8 pixel values)
        let mut histogram = vec![0u32; 256];
        for &pixel in &display_data_raw {
            histogram[pixel as usize] += 1;
        }

        // Convert to RGBA for Flutter rendering (parallel, fast in Rust)
        let display_data = display_data_to_rgba(&display_data_raw, is_color);

        // Store all image data atomically to prevent race conditions
        // This ensures the UI never sees inconsistent state between raw and display data
        let display_result = CapturedImageResult {
            width: seq_image.width,
            height: seq_image.height,
            display_data,
            histogram,
            stats: ImageStatsResult {
                min: stats.min,
                max: stats.max,
                mean: stats.mean,
                median: stats.median,
                std_dev: stats.std_dev,
                hfr: median_hfr,
                eccentricity: median_eccentricity,
                fwhm: median_fwhm,
                star_count,
            },
            exposure_time: duration_secs,
            timestamp: chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S").to_string(),
            is_color,
        };

        let raw_info = RawImageInfo {
            width: seq_image.width,
            height: seq_image.height,
            data: seq_image.data.clone(),
            sensor_type: seq_image.sensor_type.clone(),
            bayer_offset: seq_image.bayer_offset,
        };

        store_captured_image_atomically(&device_id, display_result, raw_info).await;

        // Note: ExposureComplete event is published by UnifiedDeviceOps
        tracing::info!(
            "Real camera exposure complete, {} stars detected",
            star_count
        );
        Ok(())
    }
}

/// Get the last captured image for a specific device (display-ready format)
/// Reads from per-device atomic storage to ensure consistency with raw data
pub async fn api_get_last_image(device_id: String) -> Result<CapturedImageResult, NightshadeError> {
    // Log at debug: dashboards/companions POLL this every few seconds for a
    // preview, so INFO-per-call was the single largest source of log volume, and
    // "no image yet" is a NORMAL pre-capture state that the typed
    // `NoImageAvailable` error already reports to the caller — a WARN for it
    // flooded the log with non-problems (130 in one session).
    tracing::debug!("API: api_get_last_image called for device: {}", device_id);
    let mut storage = get_unified_image_storage().lock().await;
    match storage.get(&device_id) {
        Some(data) => {
            tracing::debug!(
                "API: Returning stored image {}x{}, display_data size: {} bytes",
                data.display.width,
                data.display.height,
                data.display.display_data.len()
            );
            Ok(data.display.clone())
        }
        None => {
            tracing::debug!("API: No image available for device: {}", device_id);
            Err(NightshadeError::NoImageAvailable)
        }
    }
}

/// Get the last captured raw image data (u16) for a specific device
/// This is used for saving FITS files with original bit depth
/// Reads from per-device atomic storage to ensure consistency with display data
pub async fn api_get_last_raw_image_data(device_id: String) -> Result<Vec<u16>, NightshadeError> {
    let mut storage = get_unified_image_storage().lock().await;
    storage
        .get(&device_id)
        .map(|data| data.raw_info.data.clone())
        .ok_or(NightshadeError::NoImageAvailable)
}

/// Get the last captured raw image info with full metadata for a specific device
/// This is used by the sequencer for HFR calculation, plate solving, and other analysis
/// that requires original 16-bit sensor data (not display-stretched 8-bit data)
/// Reads from per-device atomic storage to ensure consistency with display data
#[flutter_rust_bridge::frb(ignore)]
pub async fn get_last_raw_image_info(
    device_id: &str,
) -> Result<Option<RawImageInfo>, NightshadeError> {
    let mut storage = get_unified_image_storage().lock().await;
    Ok(storage.get(device_id).map(|data| data.raw_info.clone()))
}

/// Clear stored image data for a specific device
/// This is used to free memory when a camera is disconnected or when explicitly requested
pub async fn api_clear_device_image(device_id: String) -> Result<(), NightshadeError> {
    tracing::info!("API: Clearing stored image for device: {}", device_id);
    let mut storage = get_unified_image_storage().lock().await;
    storage.pop(&device_id);
    Ok(())
}

/// Cancel current exposure
pub async fn api_camera_cancel_exposure(device_id: String) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        // Invalidating the acquisition is what actually stops the simulated
        // exposure: setting the state to Idle alone left the exposure future
        // sleeping to full duration, so a 30 s light aborted at 24 s still
        // "completed" 7 s later. The in-flight exposure sees the new generation
        // and takes `sim_exposure_cancelled`, which parks the sensor.
        crate::unified_device_ops::mark_camera_exposure_aborted(&device_id).await;
        tracing::info!("Exposure cancelled");
        Ok(())
    } else {
        // Route real devices through DeviceManager
        crate::unified_device_ops::mark_camera_exposure_aborted(&device_id).await;
        let mgr = get_device_manager();
        mgr.camera_abort_exposure(&device_id)
            .await
            .map_err(NightshadeError::from)
    }
}

// =============================================================================
// REAL FITS FILE OPERATIONS
// =============================================================================

/// Result from reading a FITS file
#[derive(Debug, Clone)]
pub struct FitsReadResult {
    pub width: u32,
    pub height: u32,
    pub bitpix: i32,
    pub display_data: Vec<u8>, // Always RGBA (width*height*4), alpha=255
    pub histogram: Vec<u32>,
    pub stats: ImageStatsResult,
    pub object_name: Option<String>,
    pub exposure_time: Option<f64>,
    pub filter: Option<String>,
    pub ra: Option<f64>,
    pub dec: Option<f64>,
    pub date_obs: Option<String>,
    pub bayer_pattern: Option<String>,
}

/// Result from reading FITS file linear pixel data.
/// This is intended for scientific workflows that require unstretched values.
#[derive(Debug, Clone)]
pub struct FitsLinearReadResult {
    pub width: u32,
    pub height: u32,
    pub bitpix: i32,
    pub linear_data: Vec<f64>,
    pub object_name: Option<String>,
    pub exposure_time: Option<f64>,
    pub filter: Option<String>,
    pub ra: Option<f64>,
    pub dec: Option<f64>,
    pub date_obs: Option<String>,
    pub bayer_pattern: Option<String>,
}

/// Frame-level quality metrics for Science visualizations.
#[derive(Debug, Clone)]
pub struct QualityFrameMetricsApi {
    pub median: f64,
    pub mean: f64,
    pub std_dev: f64,
    pub mad: f64,
    pub background: f64,
    pub noise: f64,
    pub snr: f64,
    pub dynamic_range_p1_p99: f64,
    pub low_clip_percent: f64,
    pub high_clip_percent: f64,
    pub uniformity_cv: f64,
    pub gradient_x: f64,
    pub gradient_y: f64,
    pub processing_tier: String,
    pub processing_ms: u32,
}

/// Tile-level quality metrics for Science overlays/surfaces.
#[derive(Debug, Clone)]
pub struct QualityTileMetricApi {
    pub layer_type: String,
    pub tile_row: u32,
    pub tile_col: u32,
    pub sample_count: u32,
    pub value: f64,
    pub p05: f64,
    pub p50: f64,
    pub p95: f64,
    pub aux_value: f64,
}

/// Result container for quality map computation endpoints.
#[derive(Debug, Clone)]
pub struct QualityMapsResultApi {
    pub frame: QualityFrameMetricsApi,
    pub tiles: Vec<QualityTileMetricApi>,
}

/// Decode an [`ImageData`] byte buffer into linear `f64` samples.
///
/// `ImageData.data` is an in-memory host-endian (little-endian) buffer, NOT the
/// big-endian wire format of a FITS file: every producer in the imaging crate
/// writes it with `to_le_bytes` (`fits.rs` after BZERO/BSCALE scaling, the
/// camera drivers, `processing.rs`) and every other consumer reads it back with
/// `from_le_bytes` (`ImageData::as_u16`/`as_f32`, `calibration.rs`,
/// `background_extraction.rs::read_pixel`). Decoding big-endian here byte-swaps
/// every sample, which does not merely scale the data — it destroys the star
/// field (a 440 ADU background reads as 47105 and a 40614 ADU star as 42654,
/// i.e. stars come back DARKER than the sky), so downstream star detection finds
/// nothing at all.
pub(crate) fn image_data_to_linear_f64(image_data: &ImageData) -> Vec<f64> {
    match image_data.pixel_type {
        nightshade_imaging::PixelType::U8 => image_data
            .data
            .iter()
            .map(|&value| value as f64)
            .collect::<Vec<f64>>(),
        nightshade_imaging::PixelType::U16 => image_data
            .data
            .chunks_exact(2)
            .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]) as f64)
            .collect::<Vec<f64>>(),
        nightshade_imaging::PixelType::U32 => image_data
            .data
            .chunks_exact(4)
            .map(|chunk| u32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]) as f64)
            .collect::<Vec<f64>>(),
        nightshade_imaging::PixelType::F32 => image_data
            .data
            .chunks_exact(4)
            .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]) as f64)
            .collect::<Vec<f64>>(),
        nightshade_imaging::PixelType::F64 => image_data
            .data
            .chunks_exact(8)
            .map(|chunk| {
                f64::from_le_bytes([
                    chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6], chunk[7],
                ])
            })
            .collect::<Vec<f64>>(),
    }
}

#[cfg(test)]
mod linear_decode_tests {
    use super::image_data_to_linear_f64;
    use nightshade_imaging::{ImageData, PixelType};

    /// The star field survives a write_fits -> read_fits -> decode round trip.
    /// A big-endian decode passes none of these: 440 ADU reads back as 47105 and
    /// the 40614 ADU star as 42654, inverting the contrast so star detection
    /// finds nothing.
    #[test]
    fn round_trips_u16_fits_pixels_through_the_linear_decoder() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("roundtrip.fits");

        let mut image = ImageData::new(4, 4, 1, PixelType::U16);
        // A sky background with one bright star, i.e. the values from the
        // Stack & Share repro.
        let samples: [u16; 16] = [
            440, 441, 439, 440, 440, 40614, 12000, 440, 441, 9000, 3000, 440, 440, 440, 441, 439,
        ];
        for (i, &value) in samples.iter().enumerate() {
            image.data[i * 2..i * 2 + 2].copy_from_slice(&value.to_le_bytes());
        }

        let header = nightshade_imaging::FitsHeader::new();
        nightshade_imaging::write_fits(&path, &image, &header).unwrap();

        let (read_back, _) = nightshade_imaging::read_fits(&path).unwrap();
        let linear = image_data_to_linear_f64(&read_back);

        assert_eq!(linear.len(), samples.len());
        for (i, &expected) in samples.iter().enumerate() {
            assert_eq!(
                linear[i], expected as f64,
                "pixel {i} decoded as {} but the file holds {expected}",
                linear[i]
            );
        }
    }

    /// Every other consumer in the imaging crate reads `ImageData.data` with
    /// `from_le_bytes`; this decoder must agree with them, or the same buffer
    /// yields two different images depending on which path touches it.
    #[test]
    fn agrees_with_image_data_native_accessors() {
        let mut image = ImageData::new(2, 1, 1, PixelType::U16);
        image.data[0..2].copy_from_slice(&440u16.to_le_bytes());
        image.data[2..4].copy_from_slice(&40614u16.to_le_bytes());

        let linear = image_data_to_linear_f64(&image);
        let native = image.as_u16().unwrap();

        assert_eq!(linear, vec![native[0] as f64, native[1] as f64]);
        assert_eq!(linear, vec![440.0, 40614.0]);
    }

    #[test]
    fn round_trips_f32_pixels() {
        let mut image = ImageData::new(2, 1, 1, PixelType::F32);
        image.data[0..4].copy_from_slice(&1.5f32.to_le_bytes());
        image.data[4..8].copy_from_slice(&(-2.25f32).to_le_bytes());

        assert_eq!(image_data_to_linear_f64(&image), vec![1.5, -2.25]);
    }
}

/// Read a FITS file from disk
pub async fn api_read_fits_file(file_path: String) -> Result<FitsReadResult, NightshadeError> {
    use std::path::Path;

    tracing::info!("Reading FITS file: {}", file_path);

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    // Read the actual FITS file
    let (image_data, header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    // Extract header keywords
    let object_name = header.get_string("OBJECT").map(|s| s.to_string());
    let exposure_time = header.get_float("EXPTIME");
    let filter = header.get_string("FILTER").map(|s| s.to_string());
    let ra = header.get_float("RA");
    let dec = header.get_float("DEC");
    let date_obs = header.get_string("DATE-OBS").map(|s| s.to_string());
    let bitpix = header.get_int("BITPIX").unwrap_or(16) as i32;
    let bayer_pattern = header.get_string("BAYERPAT").map(|s| s.to_string());

    // Calculate statistics
    let stats = nightshade_imaging::calculate_stats_u16(&image_data);

    // Auto stretch for display
    let stretch_params = nightshade_imaging::auto_stretch_stf(&image_data);
    let display_data_raw = nightshade_imaging::apply_stretch(&image_data, &stretch_params);

    // Calculate histogram from pre-RGBA data
    let mut histogram = vec![0u32; 256];
    for &pixel in &display_data_raw {
        histogram[pixel as usize] += 1;
    }

    // Convert grayscale to RGBA for Flutter rendering
    let display_data = display_data_to_rgba(&display_data_raw, false);

    tracing::info!(
        "FITS file loaded: {}x{}, {} pixels",
        image_data.width,
        image_data.height,
        image_data.width * image_data.height
    );

    Ok(FitsReadResult {
        width: image_data.width,
        height: image_data.height,
        bitpix,
        display_data,
        histogram,
        stats: ImageStatsResult {
            min: stats.min,
            max: stats.max,
            mean: stats.mean,
            median: stats.median,
            std_dev: stats.std_dev,
            // This load path does not run star detection, so neither HFR nor
            // eccentricity is measured here — honest None, not a fabricated 0.
            hfr: None,
            eccentricity: None,
            fwhm: None,
            star_count: 0,
        },
        object_name,
        exposure_time,
        filter,
        ra,
        dec,
        date_obs,
        bayer_pattern,
    })
}

// =============================================================================
// FITS header keyword update (science writeback)
// =============================================================================

/// A single keyword to inject (or overwrite) on an existing FITS file.
///
/// Exactly one of `string_value`, `int_value`, `float_value` must be `Some`.
/// The remaining fields must be `None`. The Rust side validates this and
/// returns an `InvalidParameters` error rather than guessing — silent
/// fallbacks would let a caller bury a typo and have the keyword vanish.
#[derive(Debug, Clone)]
pub struct FitsKeywordUpdate {
    /// FITS keyword. Uppercased on insert. Must be 1..=8 ASCII chars per the
    /// FITS Standard (4.4.2.1); longer keys are rejected at write time.
    pub keyword: String,
    /// Optional inline comment ("/ comment" segment of the value card).
    pub comment: Option<String>,
    pub string_value: Option<String>,
    pub int_value: Option<i64>,
    pub float_value: Option<f64>,
}

/// Update (overwrite or inject) one or more keywords on an existing FITS file.
///
/// Implementation: reads the full file into memory, mutates the header in
/// place, writes the result to a sibling `<filename>.nshatmp` file, then
/// atomically renames it over the original. If any step fails the original
/// file is left untouched.
///
/// This is the writeback mechanism used by `ScienceProcessingService` to
/// stamp `MAGZP`, `MAGZPERR`, `TRANSPAR`, etc. back onto captured frames so
/// that PixInsight / AstroPixelProcessor / Siril can read Nightshade's
/// science products without going through our database.
pub async fn api_update_fits_keywords(
    file_path: String,
    updates: Vec<FitsKeywordUpdate>,
) -> Result<(), NightshadeError> {
    use std::path::Path;

    if updates.is_empty() {
        return Ok(());
    }

    // Validate every update first — fail fast before touching disk.
    for u in &updates {
        let provided = [
            u.string_value.is_some(),
            u.int_value.is_some(),
            u.float_value.is_some(),
        ]
        .iter()
        .filter(|x| **x)
        .count();
        if provided != 1 {
            return Err(NightshadeError::InvalidParameter(format!(
                "FITS keyword update for `{}` must set exactly one of \
                string_value/int_value/float_value (got {})",
                u.keyword, provided
            )));
        }
        if u.keyword.is_empty() || u.keyword.len() > 8 {
            return Err(NightshadeError::InvalidParameter(format!(
                "FITS keyword `{}` must be 1..=8 ASCII chars (FITS 4.4.2.1)",
                u.keyword
            )));
        }
        if !u
            .keyword
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
        {
            return Err(NightshadeError::InvalidParameter(format!(
                "FITS keyword `{}` contains illegal characters",
                u.keyword
            )));
        }
    }

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    let (image_data, mut header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    for u in &updates {
        let key = u.keyword.to_uppercase();
        if let Some(ref s) = u.string_value {
            header.set_string(&key, s);
        } else if let Some(i) = u.int_value {
            header.set_int(&key, i);
        } else if let Some(f) = u.float_value {
            header.set_float(&key, f);
        }
        if let Some(ref c) = u.comment {
            header.set_comment(&key, c);
        }
    }

    // Atomic write: temp sibling, then rename. Why: a half-written FITS file
    // is worse than no writeback at all — astronomers would lose the original
    // capture data. The rename is atomic on Windows and POSIX when source and
    // destination are on the same filesystem (which they are by construction).
    let tmp_path = {
        let mut p = path.to_path_buf();
        let mut ext = p.extension().map(|e| e.to_owned()).unwrap_or_default();
        ext.push(".nshatmp");
        p.set_extension(ext);
        p
    };
    nightshade_imaging::write_fits(&tmp_path, &image_data, &header)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to write FITS: {}", e)))?;
    std::fs::rename(&tmp_path, path).map_err(|e| {
        // Best-effort cleanup if rename failed.
        let _ = std::fs::remove_file(&tmp_path);
        NightshadeError::IoError(format!("Failed to atomically replace FITS: {}", e))
    })?;

    tracing::info!("Updated {} FITS keyword(s) on {}", updates.len(), file_path);
    Ok(())
}

/// Read a FITS file and return unstretched linear pixel values for science analysis.
pub async fn api_read_fits_linear_data(
    file_path: String,
) -> Result<FitsLinearReadResult, NightshadeError> {
    use std::path::Path;

    tracing::info!("Reading FITS linear data: {}", file_path);

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    let (image_data, header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    let object_name = header.get_string("OBJECT").map(|s| s.to_string());
    let exposure_time = header.get_float("EXPTIME");
    let filter = header.get_string("FILTER").map(|s| s.to_string());
    let ra = header.get_float("RA");
    let dec = header.get_float("DEC");
    let date_obs = header.get_string("DATE-OBS").map(|s| s.to_string());
    let bitpix = header.get_int("BITPIX").unwrap_or(16) as i32;
    let bayer_pattern = header.get_string("BAYERPAT").map(|s| s.to_string());
    let linear_data = image_data_to_linear_f64(&image_data);

    Ok(FitsLinearReadResult {
        width: image_data.width,
        height: image_data.height,
        bitpix,
        linear_data,
        object_name,
        exposure_time,
        filter,
        ra,
        dec,
        date_obs,
        bayer_pattern,
    })
}

pub(crate) fn percentile_sorted(sorted_values: &[f64], p: f64) -> f64 {
    if sorted_values.is_empty() {
        return 0.0;
    }
    let q = p.clamp(0.0, 1.0);
    let pos = ((sorted_values.len() - 1) as f64) * q;
    let lo = pos.floor() as usize;
    let hi = pos.ceil() as usize;
    if lo == hi {
        return sorted_values[lo];
    }
    let t = pos - lo as f64;
    sorted_values[lo] * (1.0 - t) + sorted_values[hi] * t
}

pub(crate) fn percentile(values: &[f64], p: f64) -> f64 {
    let mut sorted = values
        .iter()
        .copied()
        .filter(|value| value.is_finite())
        .collect::<Vec<_>>();
    if sorted.is_empty() {
        return 0.0;
    }
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    percentile_sorted(&sorted, p)
}

pub(crate) fn median(values: &[f64]) -> f64 {
    percentile(values, 0.5)
}

pub(crate) fn mad(values: &[f64], median_value: f64) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    let deviations = values
        .iter()
        .copied()
        .filter(|value| value.is_finite())
        .map(|value| (value - median_value).abs())
        .collect::<Vec<_>>();
    median(&deviations)
}

pub(crate) fn compute_quality_maps_from_linear_data(
    width: usize,
    height: usize,
    linear_data: &[f64],
    grid_rows: u32,
    grid_cols: u32,
    low_clip_adu: u32,
    high_clip_adu: u32,
    processing_tier: &str,
) -> Result<QualityMapsResultApi, NightshadeError> {
    if width == 0 || height == 0 {
        return Err(NightshadeError::InvalidInput(
            "Image dimensions must be non-zero".to_string(),
        ));
    }

    let expected = width.saturating_mul(height);
    if linear_data.len() < expected {
        return Err(NightshadeError::InvalidInput(format!(
            "Linear buffer too small: {} < {}",
            linear_data.len(),
            expected
        )));
    }

    let rows = grid_rows.clamp(2, 128) as usize;
    let cols = grid_cols.clamp(2, 128) as usize;
    let low_clip = low_clip_adu as f64;
    let high_clip = high_clip_adu as f64;

    let mut tile_metrics = Vec::with_capacity(rows * cols * 5);
    let mut tile_medians = Vec::with_capacity(rows * cols);
    let mut tile_noises = Vec::with_capacity(rows * cols);
    let mut tile_p05 = Vec::with_capacity(rows * cols);
    let mut tile_p95 = Vec::with_capacity(rows * cols);
    let mut tile_grad_x = Vec::with_capacity(rows * cols);
    let mut tile_grad_y = Vec::with_capacity(rows * cols);

    let mut global_count: usize = 0;
    let mut global_sum = 0.0;
    let mut global_sum_sq = 0.0;
    let mut global_low_clip: usize = 0;
    let mut global_high_clip: usize = 0;

    let image_mid_x = width / 2;
    let image_mid_y = height / 2;

    for row in 0..rows {
        let y_start = (row * height) / rows;
        let mut y_end = ((row + 1) * height) / rows;
        if y_end <= y_start {
            y_end = (y_start + 1).min(height);
        }

        for col in 0..cols {
            let x_start = (col * width) / cols;
            let mut x_end = ((col + 1) * width) / cols;
            if x_end <= x_start {
                x_end = (x_start + 1).min(width);
            }

            let mut samples = Vec::new();
            let mut sum = 0.0;
            let mut sum_sq = 0.0;
            let mut tile_low_clip: usize = 0;
            let mut tile_high_clip: usize = 0;
            let mut left_sum = 0.0;
            let mut right_sum = 0.0;
            let mut top_sum = 0.0;
            let mut bottom_sum = 0.0;
            let mut left_count: usize = 0;
            let mut right_count: usize = 0;
            let mut top_count: usize = 0;
            let mut bottom_count: usize = 0;

            for y in y_start..y_end {
                let is_top = y < image_mid_y;
                let row_base = y * width;
                for x in x_start..x_end {
                    let value = linear_data[row_base + x];
                    if !value.is_finite() {
                        continue;
                    }

                    samples.push(value);
                    sum += value;
                    sum_sq += value * value;
                    global_sum += value;
                    global_sum_sq += value * value;
                    global_count += 1;

                    if value <= low_clip {
                        tile_low_clip += 1;
                        global_low_clip += 1;
                    }
                    if value >= high_clip {
                        tile_high_clip += 1;
                        global_high_clip += 1;
                    }

                    if x < image_mid_x {
                        left_sum += value;
                        left_count += 1;
                    } else {
                        right_sum += value;
                        right_count += 1;
                    }

                    if is_top {
                        top_sum += value;
                        top_count += 1;
                    } else {
                        bottom_sum += value;
                        bottom_count += 1;
                    }
                }
            }

            if samples.is_empty() {
                continue;
            }

            samples.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

            let count = samples.len();
            let count_f64 = count as f64;
            let mean_value = sum / count_f64;
            let variance = ((sum_sq / count_f64) - (mean_value * mean_value)).max(0.0);
            let std_dev = variance.sqrt();
            let p05 = percentile_sorted(&samples, 0.05);
            let p50 = percentile_sorted(&samples, 0.50);
            let p95 = percentile_sorted(&samples, 0.95);
            let cv = if mean_value.abs() < 1e-6 {
                0.0
            } else {
                std_dev / mean_value.abs()
            };
            let low_clip_percent = 100.0 * (tile_low_clip as f64) / count_f64;
            let high_clip_percent = 100.0 * (tile_high_clip as f64) / count_f64;
            let snr = if std_dev <= 0.0 {
                0.0
            } else {
                mean_value / std_dev
            };

            let left_mean = if left_count == 0 {
                mean_value
            } else {
                left_sum / left_count as f64
            };
            let right_mean = if right_count == 0 {
                mean_value
            } else {
                right_sum / right_count as f64
            };
            let top_mean = if top_count == 0 {
                mean_value
            } else {
                top_sum / top_count as f64
            };
            let bottom_mean = if bottom_count == 0 {
                mean_value
            } else {
                bottom_sum / bottom_count as f64
            };
            let grad_x = right_mean - left_mean;
            let grad_y = bottom_mean - top_mean;
            let grad_mag = (grad_x * grad_x + grad_y * grad_y).sqrt();

            tile_medians.push(p50);
            tile_noises.push(std_dev);
            tile_p05.push(p05);
            tile_p95.push(p95);
            tile_grad_x.push(grad_x);
            tile_grad_y.push(grad_y);

            let tile_row = row as u32;
            let tile_col = col as u32;
            let sample_count = count.min(u32::MAX as usize) as u32;
            tile_metrics.push(QualityTileMetricApi {
                layer_type: "uniformity".to_string(),
                tile_row,
                tile_col,
                sample_count,
                value: cv,
                p05,
                p50,
                p95,
                aux_value: grad_mag,
            });
            tile_metrics.push(QualityTileMetricApi {
                layer_type: "clip_low".to_string(),
                tile_row,
                tile_col,
                sample_count,
                value: low_clip_percent,
                p05: low_clip_percent,
                p50: low_clip_percent,
                p95: low_clip_percent,
                aux_value: tile_low_clip as f64,
            });
            tile_metrics.push(QualityTileMetricApi {
                layer_type: "clip_high".to_string(),
                tile_row,
                tile_col,
                sample_count,
                value: high_clip_percent,
                p05: high_clip_percent,
                p50: high_clip_percent,
                p95: high_clip_percent,
                aux_value: tile_high_clip as f64,
            });
            tile_metrics.push(QualityTileMetricApi {
                layer_type: "background".to_string(),
                tile_row,
                tile_col,
                sample_count,
                value: p50,
                p05,
                p50,
                p95,
                aux_value: std_dev,
            });
            tile_metrics.push(QualityTileMetricApi {
                layer_type: "snr".to_string(),
                tile_row,
                tile_col,
                sample_count,
                value: snr,
                p05: 0.0,
                p50: snr,
                p95: snr,
                aux_value: std_dev,
            });
        }
    }

    let safe_count = global_count.max(1) as f64;
    let global_mean = global_sum / safe_count;
    let global_std_dev = ((global_sum_sq / safe_count) - (global_mean * global_mean))
        .max(0.0)
        .sqrt();
    let median_value = if tile_medians.is_empty() {
        0.0
    } else {
        median(&tile_medians)
    };
    let mad_value = if tile_medians.is_empty() {
        0.0
    } else {
        mad(&tile_medians, median_value)
    };
    let background = if tile_medians.is_empty() {
        global_mean
    } else {
        median(&tile_medians)
    };
    let noise = if tile_noises.is_empty() {
        global_std_dev
    } else {
        median(&tile_noises)
    };
    let snr = if noise <= 0.0 {
        0.0
    } else {
        global_mean / noise
    };
    let p1 = if tile_p05.is_empty() {
        0.0
    } else {
        percentile(&tile_p05, 0.2)
    };
    let p99 = if tile_p95.is_empty() {
        0.0
    } else {
        percentile(&tile_p95, 0.8)
    };
    let dynamic_range = (p99 - p1).max(0.0);
    let gradient_x = if tile_grad_x.is_empty() {
        0.0
    } else {
        tile_grad_x.iter().sum::<f64>() / tile_grad_x.len() as f64
    };
    let gradient_y = if tile_grad_y.is_empty() {
        0.0
    } else {
        tile_grad_y.iter().sum::<f64>() / tile_grad_y.len() as f64
    };

    Ok(QualityMapsResultApi {
        frame: QualityFrameMetricsApi {
            median: median_value,
            mean: global_mean,
            std_dev: global_std_dev,
            mad: mad_value,
            background,
            noise,
            snr,
            dynamic_range_p1_p99: dynamic_range,
            low_clip_percent: 100.0 * (global_low_clip as f64) / safe_count,
            high_clip_percent: 100.0 * (global_high_clip as f64) / safe_count,
            uniformity_cv: if background.abs() < 1e-6 {
                0.0
            } else {
                global_std_dev / background.abs()
            },
            gradient_x,
            gradient_y,
            processing_tier: processing_tier.to_string(),
            processing_ms: 0,
        },
        tiles: tile_metrics,
    })
}

/// Compute quality maps from the last captured image in memory for a device.
pub async fn api_compute_last_capture_quality_maps(
    device_id: String,
    grid_rows: u32,
    grid_cols: u32,
    low_clip_adu: u32,
    high_clip_adu: u32,
) -> Result<QualityMapsResultApi, NightshadeError> {
    let started = Instant::now();
    let raw_info = get_last_raw_image_info(&device_id)
        .await?
        .ok_or(NightshadeError::NoImageAvailable)?;

    // Why: raw_info.width/height are u32; widening to usize via `as` is value-preserving
    // on every Tier 1 target. raw_info.data is Vec<u16>; widening u16 -> f64 is lossless
    // (53-bit mantissa easily holds 16-bit values).
    let width = raw_info.width as usize;
    let height = raw_info.height as usize;
    let linear_data = raw_info
        .data
        .iter()
        .map(|value| *value as f64)
        .collect::<Vec<_>>();

    let mut result = compute_quality_maps_from_linear_data(
        width,
        height,
        &linear_data,
        grid_rows,
        grid_cols,
        low_clip_adu,
        high_clip_adu,
        "live",
    )?;
    // Why: as_millis() returns u128; we clamp to u32::MAX first then cast, so the
    // value cannot exceed u32::MAX. u128 -> u32 with clamped value is safe.
    result.frame.processing_ms = started.elapsed().as_millis().min(u32::MAX as u128) as u32;
    Ok(result)
}

/// Compute quality maps directly from a FITS file.
pub async fn api_compute_fits_quality_maps(
    file_path: String,
    grid_rows: u32,
    grid_cols: u32,
    low_clip_adu: u32,
    high_clip_adu: u32,
) -> Result<QualityMapsResultApi, NightshadeError> {
    use std::path::Path;

    let started = Instant::now();
    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;
    let linear_data = image_data_to_linear_f64(&image_data);

    let mut result = compute_quality_maps_from_linear_data(
        image_data.width as usize,
        image_data.height as usize,
        &linear_data,
        grid_rows,
        grid_cols,
        low_clip_adu,
        high_clip_adu,
        "deferred",
    )?;
    result.frame.processing_ms = started.elapsed().as_millis().min(u32::MAX as u128) as u32;
    Ok(result)
}

#[cfg(test)]
mod quality_map_tests {
    use super::compute_quality_maps_from_linear_data;

    fn approx_eq(actual: f64, expected: f64, tolerance: f64) {
        assert!(
            (actual - expected).abs() <= tolerance,
            "expected {expected}, got {actual} (tol={tolerance})"
        );
    }

    #[test]
    fn computes_expected_clip_metrics_for_uniform_black_frame() {
        let data = vec![0.0; 16];
        let result =
            compute_quality_maps_from_linear_data(4, 4, &data, 2, 2, 0, 65535, "live").unwrap();

        approx_eq(result.frame.low_clip_percent, 100.0, 1e-9);
        approx_eq(result.frame.high_clip_percent, 0.0, 1e-9);
        assert_eq!(result.frame.processing_tier, "live");
        assert_eq!(result.tiles.len(), 20); // 2x2 tiles * 5 layers
    }

    #[test]
    fn computes_expected_clip_metrics_for_ramp_frame() {
        let data = (0..16).map(|value| value as f64).collect::<Vec<_>>();
        let result =
            compute_quality_maps_from_linear_data(4, 4, &data, 2, 2, 0, 15, "deferred").unwrap();

        // One sample clipped low (0), one clipped high (15) out of 16 total.
        approx_eq(result.frame.low_clip_percent, 6.25, 1e-9);
        approx_eq(result.frame.high_clip_percent, 6.25, 1e-9);
        assert_eq!(result.frame.processing_tier, "deferred");
        assert_eq!(result.tiles.len(), 20);
    }
}

/// FITS header for writing

// =============================================================================
// STAR DETECTION AND IMAGE ANALYSIS
// =============================================================================

/// Detected star information
#[derive(Debug, Clone)]
pub struct DetectedStarInfo {
    pub x: f64,
    pub y: f64,
    pub flux: f64,
    pub hfr: f64,
    pub fwhm: f64,
    pub peak: f64,
    pub background: f64,
    pub snr: f64,
    /// Eccentricity: 0 = perfect circle, 1 = line (elongated)
    pub eccentricity: f64,
    /// Sharpness: ratio of peak to spread - hot pixels have high sharpness
    pub sharpness: f64,
}

/// Star detection result
#[derive(Debug, Clone)]
pub struct StarDetectionResultApi {
    pub stars: Vec<DetectedStarInfo>,
    pub star_count: u32,
    pub median_hfr: f64,
    pub median_fwhm: f64,
    pub median_snr: f64,
    /// Per-frame median star eccentricity (0.0 = round, →1.0 = trailed).
    /// `None` when too few reliable stars to honestly measure.
    pub median_eccentricity: Option<f64>,
    pub background: f64,
    pub noise: f64,
}

/// Star detection configuration
#[derive(Debug, Clone)]
#[flutter_rust_bridge::frb]
pub struct StarDetectionConfigApi {
    pub detection_sigma: f64,
    pub min_area: u32,
    pub max_area: u32,
    pub max_eccentricity: f64,
    pub saturation_limit: u32,
    pub hfr_radius: u32,
    /// Minimum HFR to be considered a real star (filters hot pixels)
    pub min_hfr: Option<f64>,
    /// Minimum SNR to be considered a valid detection
    pub min_snr: Option<f64>,
    /// Maximum sharpness (filters hot pixels which have very high sharpness)
    pub max_sharpness: Option<f64>,
}

impl Default for StarDetectionConfigApi {
    fn default() -> Self {
        Self {
            detection_sigma: 5.0,
            min_area: 9,
            max_area: 10000,
            max_eccentricity: 0.7,
            saturation_limit: 60000,
            hfr_radius: 20,
            min_hfr: Some(1.0), // Real stars have HFR > ~1.0; hot pixels < 0.8
            min_snr: Some(5.0), // Modest SNR threshold - real stars in short subs can be faint
            max_sharpness: Some(0.95), // Only reject extreme hot pixels (sharpness ~1.0)
        }
    }
}

/// Detect stars in a FITS file
pub async fn api_detect_stars_in_file(
    file_path: String,
    config: Option<StarDetectionConfigApi>,
) -> Result<StarDetectionResultApi, NightshadeError> {
    use std::path::Path;

    tracing::info!("Detecting stars in: {}", file_path);

    let path = Path::new(&file_path);
    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    let config = config.unwrap_or_default();
    let detection_config = nightshade_imaging::StarDetectionConfig {
        detection_sigma: config.detection_sigma,
        min_area: config.min_area,
        max_area: config.max_area,
        max_eccentricity: config.max_eccentricity,
        saturation_limit: config.saturation_limit as u16,
        hfr_radius: config.hfr_radius,
        min_hfr: config.min_hfr.unwrap_or(1.0),
        min_snr: config.min_snr.unwrap_or(5.0),
        max_sharpness: config.max_sharpness.unwrap_or(0.95),
        noise_model: None,
    };

    let result = nightshade_imaging::detect_stars_with_stats(&image_data, &detection_config);

    let stars: Vec<DetectedStarInfo> = result
        .stars
        .iter()
        .map(|s| DetectedStarInfo {
            x: s.x,
            y: s.y,
            flux: s.flux,
            hfr: s.hfr,
            fwhm: s.fwhm,
            peak: s.peak,
            background: s.background,
            snr: s.snr,
            eccentricity: s.eccentricity,
            sharpness: s.sharpness,
        })
        .collect();

    tracing::info!(
        "Detected {} stars, median HFR: {:.2}",
        result.star_count,
        result.median_hfr
    );

    Ok(StarDetectionResultApi {
        stars,
        star_count: result.star_count,
        median_hfr: result.median_hfr,
        median_fwhm: result.median_fwhm,
        median_snr: result.median_snr,
        median_eccentricity: result.median_eccentricity,
        background: result.background,
        noise: result.noise,
    })
}

/// Star crop data for UI display
#[derive(Debug, Clone)]
pub struct StarCropApi {
    /// Base64-encoded grayscale pixel data
    pub pixels_base64: String,
    /// Width of the crop
    pub width: u32,
    /// Height of the crop
    pub height: u32,
    /// HFR of this star
    pub hfr: f64,
    /// SNR of this star
    pub snr: f64,
}

/// Get star crops from the last captured image for a device
///
/// This extracts the top N brightest stars from the last image and returns
/// cropped 80x80 pixel regions centered on each star, auto-stretched for display.
/// Used by the autofocus UI to show star crops for visual feedback.
pub async fn api_get_star_crops_from_last_image(
    device_id: String,
    max_crops: u32,
) -> Result<Vec<StarCropApi>, NightshadeError> {
    use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};

    tracing::info!(
        "API: api_get_star_crops_from_last_image for device: {}, max_crops: {}",
        device_id,
        max_crops
    );

    // Get the last raw image for this device
    let mut storage = get_unified_image_storage().lock().await;
    let image_data = storage
        .get(&device_id)
        .ok_or(NightshadeError::NoImageAvailable)?;

    // Convert to imaging format
    let img = nightshade_imaging::ImageData::from_u16(
        image_data.raw_info.width,
        image_data.raw_info.height,
        1,
        &image_data.raw_info.data,
    );

    // Detect stars
    let config = nightshade_imaging::StarDetectionConfig::default();
    let stars = nightshade_imaging::detect_stars(&img, &config);

    if stars.is_empty() {
        tracing::info!("No stars detected for star crop extraction");
        return Ok(vec![]);
    }

    // Extract top star crops (80x80 pixels each)
    let crops = nightshade_imaging::extract_top_star_crops(&img, &stars, max_crops as usize, 80);

    // Convert to API format
    let result: Vec<StarCropApi> = crops
        .iter()
        .map(|crop| StarCropApi {
            pixels_base64: BASE64.encode(&crop.pixels),
            width: crop.width,
            height: crop.height,
            hfr: crop.hfr,
            snr: crop.snr,
        })
        .collect();

    tracing::info!("Extracted {} star crops", result.len());
    Ok(result)
}

/// Calculate HFR for a FITS file
pub async fn api_calculate_hfr(file_path: String) -> Result<Option<f64>, NightshadeError> {
    use std::path::Path;

    let path = Path::new(&file_path);
    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    Ok(nightshade_imaging::calculate_median_hfr(&image_data))
}

/// Calculate histogram for a FITS file
pub async fn api_calculate_histogram(
    file_path: String,
    _bins: u32,
    logarithmic: u8,
) -> Result<Vec<f32>, NightshadeError> {
    use std::path::Path;

    let path = Path::new(&file_path);
    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    let logarithmic_bool = logarithmic != 0;
    let histogram = nightshade_imaging::calculate_display_histogram(&image_data, logarithmic_bool);
    Ok(histogram)
}

/// Stretch parameters for manual control
#[derive(Debug, Clone)]
pub struct StretchParamsApi {
    pub shadows: f64,
    pub highlights: f64,
    pub midtones: f64,
}

/// Auto-calculate stretch parameters for an image
pub async fn api_calculate_auto_stretch(
    file_path: String,
) -> Result<StretchParamsApi, NightshadeError> {
    use std::path::Path;

    let path = Path::new(&file_path);
    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    let params = nightshade_imaging::auto_stretch_stf(&image_data);

    Ok(StretchParamsApi {
        shadows: params.shadows,
        highlights: params.highlights,
        midtones: params.midtones,
    })
}

/// Apply stretch to a FITS file and return display data
pub async fn api_apply_stretch(
    file_path: String,
    params: StretchParamsApi,
) -> Result<Vec<u8>, NightshadeError> {
    use std::path::Path;

    let path = Path::new(&file_path);
    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    let stretch_params = nightshade_imaging::StretchParams {
        shadows: params.shadows,
        highlights: params.highlights,
        midtones: params.midtones,
    };

    let display_data_raw = nightshade_imaging::apply_stretch(&image_data, &stretch_params);
    // Convert grayscale to RGBA for Flutter rendering
    Ok(display_data_to_rgba(&display_data_raw, false))
}

// =============================================================================
// DEBAYERING (COLOR CAMERAS)
// =============================================================================

/// Bayer pattern type
#[derive(Debug, Clone, Copy)]
pub enum BayerPatternApi {
    RGGB,
    BGGR,
    GRBG,
    GBRG,
}

/// Debayer algorithm
#[derive(Debug, Clone, Copy)]
pub enum DebayerAlgorithmApi {
    Bilinear,
    VNG,
    SuperPixel,
}

/// Debayer a raw FITS image and return RGB display data
/// Debayer a raw FITS file and return RGB display data
pub async fn api_debayer_fits_file(
    file_path: String,
    pattern: BayerPatternApi,
    algorithm: DebayerAlgorithmApi,
) -> Result<Vec<u8>, NightshadeError> {
    use std::path::Path;

    let path = Path::new(&file_path);
    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    let bayer_pattern = match pattern {
        BayerPatternApi::RGGB => nightshade_imaging::BayerPattern::RGGB,
        BayerPatternApi::BGGR => nightshade_imaging::BayerPattern::BGGR,
        BayerPatternApi::GRBG => nightshade_imaging::BayerPattern::GRBG,
        BayerPatternApi::GBRG => nightshade_imaging::BayerPattern::GBRG,
    };

    let debayer_alg = match algorithm {
        DebayerAlgorithmApi::Bilinear => nightshade_imaging::DebayerAlgorithm::Bilinear,
        DebayerAlgorithmApi::VNG => nightshade_imaging::DebayerAlgorithm::VNG,
        DebayerAlgorithmApi::SuperPixel => nightshade_imaging::DebayerAlgorithm::SuperPixel,
    };

    let rgb_image = nightshade_imaging::debayer(
        &image_data.data,
        image_data.width,
        image_data.height,
        bayer_pattern,
        debayer_alg,
    );

    // Return RGBA8 for Flutter display
    Ok(rgb_image.to_rgba8())
}

// =============================================================================
// XISF FILE SUPPORT
// =============================================================================

/// XISF file read result
#[derive(Debug, Clone)]
pub struct XisfReadResult {
    pub width: u32,
    pub height: u32,
    pub channels: u32,
    pub display_data: Vec<u8>, // Always RGBA (width*height*4), alpha=255
    pub histogram: Vec<u32>,
    pub stats: ImageStatsResult,
    pub properties: Vec<(String, String)>,
}

/// Read an XISF file
pub async fn api_read_xisf_file(file_path: String) -> Result<XisfReadResult, NightshadeError> {
    use std::path::Path;

    tracing::info!("Reading XISF file: {}", file_path);

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    let (image_data, metadata) = nightshade_imaging::read_xisf(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read XISF: {}", e)))?;

    // Calculate statistics
    let stats = nightshade_imaging::calculate_stats_u16(&image_data);

    // Auto stretch for display
    let stretch_params = nightshade_imaging::auto_stretch_stf(&image_data);
    let display_data_raw = nightshade_imaging::apply_stretch(&image_data, &stretch_params);

    // Calculate histogram from pre-RGBA data
    let mut histogram = vec![0u32; 256];
    for &pixel in &display_data_raw {
        histogram[pixel as usize] += 1;
    }

    // Convert grayscale to RGBA for Flutter rendering
    let display_data = display_data_to_rgba(&display_data_raw, false);

    // Convert properties to strings
    let properties: Vec<(String, String)> = metadata
        .properties
        .iter()
        .map(|(k, v)| (k.clone(), format!("{:?}", v)))
        .chain(
            metadata
                .fits_keywords
                .iter()
                .map(|(k, v)| (k.clone(), v.clone())),
        )
        .collect();

    tracing::info!(
        "XISF file loaded: {}x{}x{}",
        image_data.width,
        image_data.height,
        image_data.channels
    );

    Ok(XisfReadResult {
        width: image_data.width,
        height: image_data.height,
        channels: image_data.channels,
        display_data,
        histogram,
        stats: ImageStatsResult {
            min: stats.min,
            max: stats.max,
            mean: stats.mean,
            median: stats.median,
            std_dev: stats.std_dev,
            // XISF load runs no star detection: honest None for both.
            hfr: None,
            eccentricity: None,
            fwhm: None,
            star_count: 0,
        },
        properties,
    })
}

/// Save image as XISF
pub async fn api_save_xisf_file(
    file_path: String,
    width: u32,
    height: u32,
    data: Vec<u16>,
    properties: Vec<(String, String)>,
) -> Result<(), NightshadeError> {
    use std::path::Path;

    tracing::info!("Saving XISF file: {}", file_path);

    let image_data = nightshade_imaging::ImageData::from_u16(width, height, 1, &data);

    let mut metadata = nightshade_imaging::XisfMetadata::default();
    for (key, value) in properties {
        metadata.fits_keywords.insert(key, value);
    }

    let path = Path::new(&file_path);
    nightshade_imaging::write_xisf(path, &image_data, &metadata)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to write XISF: {}", e)))?;

    tracing::info!("XISF file saved: {}", file_path);
    Ok(())
}

/// Save image as TIFF (16-bit preserving)
pub async fn api_save_tiff_file(
    file_path: String,
    width: u32,
    height: u32,
    data: Vec<u16>,
) -> Result<(), NightshadeError> {
    use std::path::Path;

    tracing::info!("Saving TIFF file: {}", file_path);

    let image_data = nightshade_imaging::ImageData::from_u16(width, height, 1, &data);

    let path = Path::new(&file_path);
    nightshade_imaging::write_tiff(path, &image_data)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to write TIFF: {}", e)))?;

    tracing::info!("TIFF file saved: {}", file_path);
    Ok(())
}

/// Save image as PNG (16-bit preserving, lossless)
pub async fn api_save_png_file(
    file_path: String,
    width: u32,
    height: u32,
    data: Vec<u16>,
) -> Result<(), NightshadeError> {
    use std::path::Path;

    tracing::info!("Saving PNG file: {}", file_path);

    let image_data = nightshade_imaging::ImageData::from_u16(width, height, 1, &data);

    let path = Path::new(&file_path);
    nightshade_imaging::write_png(path, &image_data)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to write PNG: {}", e)))?;

    tracing::info!("PNG file saved: {}", file_path);
    Ok(())
}

/// Save image as JPEG (8-bit, lossy - for previews)
pub async fn api_save_jpeg_file(
    file_path: String,
    width: u32,
    height: u32,
    data: Vec<u16>,
    quality: u8,
) -> Result<(), NightshadeError> {
    use std::path::Path;

    tracing::info!("Saving JPEG file: {} (quality: {})", file_path, quality);

    let image_data = nightshade_imaging::ImageData::from_u16(width, height, 1, &data);

    let path = Path::new(&file_path);
    nightshade_imaging::write_jpeg(path, &image_data, quality)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to write JPEG: {}", e)))?;

    tracing::info!("JPEG file saved: {}", file_path);
    Ok(())
}

/// Save an 8-bit RGBA buffer as a PNG, preserving color and alpha losslessly.
///
/// Unlike [`api_save_png_file`] (which takes a mono `u16` buffer and is meant
/// for raw/linear single-channel data), this accepts an already-finalized
/// 8-bit RGBA image — the auto-stretched result the share-card / export path
/// produces. Routing that through the mono path would discard color, and
/// round-tripping it through the Dart `image` package re-encodes/re-decodes the
/// pixels unnecessarily. The alpha channel is written verbatim so transparent
/// regions (e.g. a watermark composited with partial opacity) survive.
///
/// The caller guarantees `rgba.len() == width * height * 4`. A mismatch is a
/// programming error upstream (wrong stride, truncated buffer); we surface it
/// as [`NightshadeError::ImageError`] rather than silently truncating or
/// padding, which would write a corrupt/garbage image that looks plausible.
pub async fn api_save_rgba_png_file(
    file_path: String,
    width: u32,
    height: u32,
    rgba: Vec<u8>,
) -> Result<(), NightshadeError> {
    use image::RgbaImage;
    use std::path::Path;

    tracing::info!("Saving RGBA PNG file: {} ({}x{})", file_path, width, height);

    let expected = (width as usize)
        .checked_mul(height as usize)
        .and_then(|px| px.checked_mul(4))
        .ok_or_else(|| {
            NightshadeError::ImageError(format!(
                "RGBA PNG dimensions overflow: {}x{}",
                width, height
            ))
        })?;
    if rgba.len() != expected {
        return Err(NightshadeError::ImageError(format!(
            "RGBA PNG buffer length mismatch: got {} bytes, expected {} for {}x{}x4",
            rgba.len(),
            expected,
            width,
            height
        )));
    }

    let image: RgbaImage = RgbaImage::from_raw(width, height, rgba).ok_or_else(|| {
        NightshadeError::ImageError(format!(
            "Failed to build {}x{} RGBA image buffer",
            width, height
        ))
    })?;

    let path = Path::new(&file_path);
    image
        .save(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to write RGBA PNG: {}", e)))?;

    tracing::info!("RGBA PNG file saved: {}", file_path);
    Ok(())
}

/// Save an 8-bit RGBA buffer as a JPEG, flattening alpha onto black.
///
/// Companion to [`api_save_rgba_png_file`] for the lossy export path. JPEG has
/// no alpha channel, so we explicitly composite each pixel over an opaque black
/// background (`out = src * alpha / 255`) and encode the resulting RGB. Doing
/// the flatten here — rather than handing `Rgba8` straight to the encoder,
/// which would treat the buffer as fully opaque RGB and ignore alpha entirely —
/// keeps transparent regions rendering as black instead of leaking whatever
/// stale color bytes happen to sit under a transparent pixel.
///
/// Length validation matches [`api_save_rgba_png_file`]: a mismatch is an
/// upstream bug and is surfaced as [`NightshadeError::ImageError`].
pub async fn api_save_rgba_jpeg_file(
    file_path: String,
    width: u32,
    height: u32,
    rgba: Vec<u8>,
    quality: u8,
) -> Result<(), NightshadeError> {
    use image::{ImageEncoder, RgbImage};
    use std::fs::File;
    use std::io::BufWriter;
    use std::path::Path;

    tracing::info!(
        "Saving RGBA JPEG file: {} ({}x{}, quality: {})",
        file_path,
        width,
        height,
        quality
    );

    let expected = (width as usize)
        .checked_mul(height as usize)
        .and_then(|px| px.checked_mul(4))
        .ok_or_else(|| {
            NightshadeError::ImageError(format!(
                "RGBA JPEG dimensions overflow: {}x{}",
                width, height
            ))
        })?;
    if rgba.len() != expected {
        return Err(NightshadeError::ImageError(format!(
            "RGBA JPEG buffer length mismatch: got {} bytes, expected {} for {}x{}x4",
            rgba.len(),
            expected,
            width,
            height
        )));
    }

    // Flatten RGBA onto an opaque black background -> packed RGB8.
    let pixel_count = (width as usize) * (height as usize);
    let mut rgb = Vec::with_capacity(pixel_count * 3);
    for px in rgba.chunks_exact(4) {
        // `px` is [r, g, b, a]; composite over black: out = src * a / 255.
        let a = px[3] as u32;
        rgb.push(((px[0] as u32 * a) / 255) as u8);
        rgb.push(((px[1] as u32 * a) / 255) as u8);
        rgb.push(((px[2] as u32 * a) / 255) as u8);
    }

    let rgb_image: RgbImage = RgbImage::from_raw(width, height, rgb).ok_or_else(|| {
        NightshadeError::ImageError(format!(
            "Failed to build {}x{} RGB image buffer",
            width, height
        ))
    })?;

    let path = Path::new(&file_path);
    let file = File::create(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to create JPEG file: {}", e)))?;
    let writer = BufWriter::new(file);
    let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(writer, quality);
    encoder
        .write_image(rgb_image.as_raw(), width, height, image::ColorType::Rgb8)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to encode RGBA JPEG: {}", e)))?;

    tracing::info!("RGBA JPEG file saved: {}", file_path);
    Ok(())
}

#[cfg(test)]
mod rgba_save_tests {
    use super::{api_save_rgba_jpeg_file, api_save_rgba_png_file};
    use crate::error::NightshadeError;

    /// A deterministic 2x2 RGBA image: red (opaque), green (opaque),
    /// blue (opaque), and a half-transparent white pixel.
    fn fixture_2x2() -> Vec<u8> {
        vec![
            255, 0, 0, 255, // (0,0) red
            0, 255, 0, 255, // (1,0) green
            0, 0, 255, 255, // (0,1) blue
            255, 255, 255, 128, // (1,1) white @ 50% alpha
        ]
    }

    #[tokio::test]
    async fn writes_rgba_png_and_round_trips_color_and_alpha() {
        let dir = tempfile::tempdir().expect("create temp dir");
        let path = dir.path().join("share_card.png");

        api_save_rgba_png_file(path.to_string_lossy().into_owned(), 2, 2, fixture_2x2())
            .await
            .expect("RGBA PNG should write successfully");

        // Read it back through the image crate and assert geometry + channels.
        let decoded = image::open(&path).expect("decoded PNG should open");
        let rgba = decoded.to_rgba8();
        assert_eq!(rgba.width(), 2);
        assert_eq!(rgba.height(), 2);
        // RgbaImage is 4 channels by construction.
        assert_eq!(rgba.as_raw().len(), 2 * 2 * 4);

        // Color is preserved verbatim (PNG is lossless and keeps alpha).
        assert_eq!(rgba.get_pixel(0, 0).0, [255, 0, 0, 255]);
        assert_eq!(rgba.get_pixel(1, 0).0, [0, 255, 0, 255]);
        assert_eq!(rgba.get_pixel(0, 1).0, [0, 0, 255, 255]);
        assert_eq!(rgba.get_pixel(1, 1).0, [255, 255, 255, 128]);
    }

    #[tokio::test]
    async fn writes_rgba_jpeg_flattening_alpha_onto_black() {
        let dir = tempfile::tempdir().expect("create temp dir");
        let path = dir.path().join("share_card.jpg");

        api_save_rgba_jpeg_file(path.to_string_lossy().into_owned(), 2, 2, fixture_2x2(), 90)
            .await
            .expect("RGBA JPEG should write successfully");

        let decoded = image::open(&path).expect("decoded JPEG should open");
        let rgb = decoded.to_rgb8();
        assert_eq!(rgb.width(), 2);
        assert_eq!(rgb.height(), 2);
        // JPEG has no alpha channel.
        assert_eq!(rgb.as_raw().len(), 2 * 2 * 3);

        // The half-transparent white pixel composited over black is ~mid-gray
        // (255 * 128 / 255 = 128 per channel). JPEG is lossy, so allow slack.
        let flattened = rgb.get_pixel(1, 1).0;
        for channel in flattened {
            assert!(
                (channel as i32 - 128).abs() <= 24,
                "flattened white@50% should be ~128 per channel, got {:?}",
                flattened
            );
        }
    }

    #[tokio::test]
    async fn short_png_buffer_is_rejected() {
        let dir = tempfile::tempdir().expect("create temp dir");
        let path = dir.path().join("bad.png");

        // 2x2 needs 16 bytes; provide 12 (a "short" buffer).
        let err = api_save_rgba_png_file(path.to_string_lossy().into_owned(), 2, 2, vec![0u8; 12])
            .await
            .expect_err("short RGBA buffer must be rejected, not silently truncated");

        assert!(matches!(err, NightshadeError::ImageError(_)));
        // Nothing should have been written for an invalid input.
        assert!(
            !path.exists(),
            "no file should be created on validation failure"
        );
    }

    #[tokio::test]
    async fn short_jpeg_buffer_is_rejected() {
        let dir = tempfile::tempdir().expect("create temp dir");
        let path = dir.path().join("bad.jpg");

        let err =
            api_save_rgba_jpeg_file(path.to_string_lossy().into_owned(), 2, 2, vec![0u8; 12], 85)
                .await
                .expect_err("short RGBA buffer must be rejected, not silently truncated");

        assert!(matches!(err, NightshadeError::ImageError(_)));
        assert!(
            !path.exists(),
            "no file should be created on validation failure"
        );
    }
}

// =============================================================================
// FILE NAMING PATTERNS
// =============================================================================

/// Frame type for file naming
#[derive(Debug, Clone, Copy)]
pub enum FrameTypeApi {
    Light,
    Dark,
    Flat,
    Bias,
    DarkFlat,
    Snapshot,
}

/// Generate a filename from pattern and context
pub async fn api_generate_filename(
    pattern: String,
    base_dir: String,
    target: Option<String>,
    filter: Option<String>,
    exposure_time: f64,
    frame_type: FrameTypeApi,
    frame_number: u32,
    gain: Option<i32>,
    offset: Option<i32>,
    temperature: Option<f64>,
    binning_x: u32,
    binning_y: u32,
    camera: Option<String>,
    telescope: Option<String>,
    extension: String,
) -> String {
    let frame_type_impl = match frame_type {
        FrameTypeApi::Light => nightshade_imaging::FrameType::Light,
        FrameTypeApi::Dark => nightshade_imaging::FrameType::Dark,
        FrameTypeApi::Flat => nightshade_imaging::FrameType::Flat,
        FrameTypeApi::Bias => nightshade_imaging::FrameType::Bias,
        FrameTypeApi::DarkFlat => nightshade_imaging::FrameType::DarkFlat,
        FrameTypeApi::Snapshot => nightshade_imaging::FrameType::Snapshot,
    };

    let mut context = nightshade_imaging::NamingContext::new()
        .with_current_time()
        .with_exposure(exposure_time)
        .with_frame_type(frame_type_impl)
        .with_frame_number(frame_number)
        .with_binning(binning_x, binning_y);

    if let Some(t) = target {
        context = context.with_target(t);
    }
    if let Some(f) = filter {
        context = context.with_filter(f);
    }
    if let Some(g) = gain {
        context = context.with_gain(g);
    }
    if let Some(o) = offset {
        context = context.with_offset(o);
    }
    if let Some(t) = temperature {
        context = context.with_temperature(t);
    }
    if let Some(c) = camera {
        context = context.with_camera(c);
    }
    if let Some(t) = telescope {
        context = context.with_telescope(t);
    }

    let naming_pattern = nightshade_imaging::NamingPattern::new(pattern)
        .with_base_dir(base_dir)
        .with_extension(extension);

    naming_pattern
        .generate(&context)
        .to_string_lossy()
        .to_string()
}

/// Get the next frame number for a directory
pub async fn api_get_next_frame_number(
    base_dir: String,
    pattern: String,
    target: Option<String>,
    filter: Option<String>,
    frame_type: FrameTypeApi,
) -> u32 {
    use std::path::Path;

    let frame_type_impl = match frame_type {
        FrameTypeApi::Light => nightshade_imaging::FrameType::Light,
        FrameTypeApi::Dark => nightshade_imaging::FrameType::Dark,
        FrameTypeApi::Flat => nightshade_imaging::FrameType::Flat,
        FrameTypeApi::Bias => nightshade_imaging::FrameType::Bias,
        FrameTypeApi::DarkFlat => nightshade_imaging::FrameType::DarkFlat,
        FrameTypeApi::Snapshot => nightshade_imaging::FrameType::Snapshot,
    };

    let mut context = nightshade_imaging::NamingContext::new().with_frame_type(frame_type_impl);

    if let Some(t) = target {
        context = context.with_target(t);
    }
    if let Some(f) = filter {
        context = context.with_filter(f);
    }

    let naming_pattern = nightshade_imaging::NamingPattern::new(pattern);
    let base_path = Path::new(&base_dir);

    nightshade_imaging::scan_for_next_frame_number(base_path, &naming_pattern, &context)
}

// =============================================================================
// FITS File Saving
// =============================================================================

/// Header data for FITS file writing.
///
/// Public FRB-exposed surface. Kept frozen at the original 22 fields so
/// Dart consumers (Dart-driven snapshot saves, network-backend FITS writes)
/// don't need a coordinated FRB regen.
///
/// Image Grading: the sequencer's per-frame save path uses
/// [`FitsWriteHeaderRich`] instead, which carries every extended keyword
/// (focuser position, rotator angle, guide RMS, plate-solve, mosaic
/// panel, etc.). The rich path is internal — not exposed via FRB — so
/// sequencer-driven saves can grow the FITS surface without disrupting
/// Dart-side FRB schema.
#[derive(Debug, Clone)]
pub struct FitsWriteHeader {
    pub object_name: Option<String>,
    pub exposure_time: f64,
    pub capture_timestamp: String,
    pub frame_type: String,
    pub filter: Option<String>,
    pub gain: Option<i32>,
    pub offset: Option<i32>,
    pub ccd_temp: Option<f64>,
    pub ra: Option<f64>,
    pub dec: Option<f64>,
    pub altitude: Option<f64>,
    pub telescope: Option<String>,
    pub instrument: Option<String>,
    pub observer: Option<String>,
    pub bin_x: i32,
    pub bin_y: i32,
    pub focal_length: Option<f64>,
    pub aperture: Option<f64>,
    pub pixel_size_x: Option<f64>,
    pub pixel_size_y: Option<f64>,
    pub site_latitude: Option<f64>,
    pub site_longitude: Option<f64>,
    pub site_elevation: Option<f64>,
}

/// Image Grading: internal FITS-header bundle used by the
/// sequencer's per-frame save path. Carries every field the standard
/// astrophotography FITS header expects PLUS the Nightshade-specific
/// session / mosaic / plate-solve keywords.
///
/// Not FRB-exposed: only Rust code (the sequencer's `save_fits` impl in
/// `real_device_ops.rs` / `unified_device_ops.rs` / `sequencer_ops.rs`)
/// constructs this. Dart callers continue to use the simpler
/// [`FitsWriteHeader`] for ad-hoc snapshot saves.
#[derive(Debug, Clone, Default)]
pub struct FitsWriteHeaderRich {
    pub object_name: Option<String>,
    pub exposure_time: f64,
    pub capture_timestamp: String,
    pub frame_type: String,
    pub filter: Option<String>,
    /// 1-based filter wheel position (FITS `FILTPOS`).
    pub filter_position: Option<i32>,
    pub gain: Option<i32>,
    pub offset: Option<i32>,
    pub ccd_temp: Option<f64>,
    /// Cooler target temperature in °C (FITS `SET-TEMP`).
    pub set_temp: Option<f64>,
    pub ra: Option<f64>,
    pub dec: Option<f64>,
    pub altitude: Option<f64>,
    pub telescope: Option<String>,
    pub instrument: Option<String>,
    pub observer: Option<String>,
    pub bin_x: i32,
    pub bin_y: i32,
    pub focal_length: Option<f64>,
    pub aperture: Option<f64>,
    pub pixel_size_x: Option<f64>,
    pub pixel_size_y: Option<f64>,
    pub site_latitude: Option<f64>,
    pub site_longitude: Option<f64>,
    pub site_elevation: Option<f64>,
    // -------------------------------------------------------------------
    // Image Grading additions — populated from FrameContext.
    // -------------------------------------------------------------------
    /// Focuser absolute position (FITS `FOCUSPOS`).
    pub focuser_position: Option<i32>,
    /// Focuser temperature in °C (FITS `FOCTEMP`).
    pub focuser_temperature: Option<f64>,
    /// Rotator mechanical angle in degrees (FITS `ROTATPOS`).
    pub rotator_angle: Option<f64>,
    /// Total guiding RMS in arcseconds (FITS `GUIDERMS`).
    pub guide_rms_arcsec: Option<f64>,
    /// Plate-solved RA in hours (FITS `SOLVED-RA`).
    pub solved_ra_hours: Option<f64>,
    /// Plate-solved Dec in degrees (FITS `SOLVED-DEC`).
    pub solved_dec_degrees: Option<f64>,
    /// Solved pixel scale in arcsec/pixel (FITS `PIXSCALE`).
    pub plate_solve_pixel_scale_arcsec: Option<f64>,
    /// Solved field rotation in degrees (FITS `CROTA1` and `CROTA2`).
    pub plate_solve_rotation_deg: Option<f64>,
    /// Bayer pattern ("RGGB", "BGGR", etc.) (FITS `BAYERPAT`).
    pub bayer_pattern: Option<String>,
    /// Nightshade session identifier (FITS `NS-SESID`).
    pub session_id: Option<String>,
    /// 1-based frame index within the burst (FITS `NS-FIDX`).
    pub frame_index: Option<u32>,
    /// Total planned frames in the burst (FITS `NS-NPLN`).
    pub total_planned_frames: Option<u32>,
    /// Mosaic identification (FITS `NS-MOSNM`).
    pub mosaic_name: Option<String>,
    /// 0-based mosaic panel index (FITS `NS-PIDX`).
    pub mosaic_panel_index: Option<i32>,
    /// Mosaic panel row (FITS `NS-PROW`).
    pub mosaic_panel_row: Option<i32>,
    /// Mosaic panel column (FITS `NS-PCOL`).
    pub mosaic_panel_column: Option<i32>,
    /// Mosaic total panel count (FITS `NS-NPAN`).
    pub mosaic_total_panels: Option<i32>,
    // -------------------------------------------------------------------
    // per-frame defect-map correction provenance.
    // Emitted as a FITS HISTORY card so the calibration trace is visible
    // in any FITS viewer (PixInsight, APP, NINA's image viewer, ds9).
    // `None` => no correction was applied (no map configured, or skipped
    // due to camera/sensor mismatch).
    // -------------------------------------------------------------------
    pub defect_map_correction: Option<nightshade_sequencer::scheduling::DefectMapCorrectionRecord>,
    // -------------------------------------------------------------------
    // Science — photometric FITS keywords.
    //
    //   * OBJCAT   - target catalogue designation
    //   * REFSTARS - comma-separated reference star catalogue IDs
    //   * MJD-OBS  - Modified Julian Date at exposure midpoint
    //   * INSTRMAG - instrumental magnitude (live-reduced)
    //   * DIFFMAG  - differential magnitude (against references)
    //   * FWHM     - measured FWHM in arcseconds
    //   * SNR      - measured target SNR
    //
    // All fields are Option<_> so non-photometry captures omit the
    // keywords entirely.
    // -------------------------------------------------------------------
    pub photometry_object_catalog: Option<String>,
    pub photometry_reference_stars: Option<String>,
    pub photometry_mjd_obs: Option<f64>,
    pub photometry_instrumental_mag: Option<f64>,
    pub photometry_differential_mag: Option<f64>,
    pub photometry_fwhm_arcsec: Option<f64>,
    pub photometry_snr: Option<f64>,
    /// Dual-rig — optical-train / camera attribution for multi-camera
    /// sessions (FITS `NS-RIG`). `None` for the single-rig case.
    pub rig_label: Option<String>,
}

impl From<FitsWriteHeader> for FitsWriteHeaderRich {
    fn from(h: FitsWriteHeader) -> Self {
        Self {
            object_name: h.object_name,
            exposure_time: h.exposure_time,
            capture_timestamp: h.capture_timestamp,
            frame_type: h.frame_type,
            filter: h.filter,
            filter_position: None,
            gain: h.gain,
            offset: h.offset,
            ccd_temp: h.ccd_temp,
            set_temp: None,
            ra: h.ra,
            dec: h.dec,
            altitude: h.altitude,
            telescope: h.telescope,
            instrument: h.instrument,
            observer: h.observer,
            bin_x: h.bin_x,
            bin_y: h.bin_y,
            focal_length: h.focal_length,
            aperture: h.aperture,
            pixel_size_x: h.pixel_size_x,
            pixel_size_y: h.pixel_size_y,
            site_latitude: h.site_latitude,
            site_longitude: h.site_longitude,
            site_elevation: h.site_elevation,
            ..Default::default()
        }
    }
}

impl FitsWriteHeaderRich {
    /// Build from a sequencer `FrameContext`. Pure data shuffling — no
    /// I/O, used by the sequencer-driven save paths in the bridge.
    ///
    /// FRB regen: this helper is consumed only by Rust callers
    /// (sequencer-driven `save_fits`). FRB picks up `&FrameContext` in the
    /// signature and tries to expose `FrameContext` as a Dart opaque type,
    /// which fails because `nightshade_sequencer::scheduling::FrameContext`
    /// isn't imported in `frb_generated.rs`. Tagging the helper with
    /// `frb(ignore)` keeps it Rust-only and unblocks the generator.
    #[flutter_rust_bridge::frb(ignore)]
    pub fn from_frame_context(ctx: &nightshade_sequencer::scheduling::FrameContext) -> Self {
        let instrument = match (ctx.camera_make.as_deref(), ctx.camera_model.as_deref()) {
            (Some(make), Some(model)) => Some(format!("{} {}", make, model)),
            (Some(s), None) | (None, Some(s)) => Some(s.to_string()),
            (None, None) => None,
        };

        // Where the telescope WAS, falling back to where the sequence meant to
        // be — the same preference `build_rich_header` applies for the
        // sequencer's own save path, applied here so the two other
        // `DeviceOps::save_fits` impls (real_device_ops, unified_device_ops),
        // which build the header from the context and nothing else, agree with
        // it. Taken as a PAIR rather than field by field: half a mount
        // pointing and half a target's is a coordinate that was never true of
        // anything, and the altitude below is derived from the mount's.
        let (ra, dec) = match ctx.mount_ra_hours.zip(ctx.mount_dec_degrees) {
            Some((mount_ra, mount_dec)) => (Some(mount_ra), Some(mount_dec)),
            None => (ctx.target_ra_hours, ctx.target_dec_degrees),
        };

        Self {
            object_name: ctx.target_name.clone(),
            exposure_time: ctx.duration_secs,
            // DATE-OBS is the START of the observation. This was `Utc::now()`,
            // sampled here while building the header -- which runs after
            // readout -- so every sequenced frame's DATE-OBS was late by
            // exactly its own EXPTIME. Fall back to now() only when the
            // capture path genuinely did not record a start, which is still
            // wrong but no worse than before and never silently absent.
            capture_timestamp: ctx
                .exposure_started_at
                .unwrap_or_else(chrono::Utc::now)
                .format("%Y-%m-%dT%H:%M:%S")
                .to_string(),
            frame_type: ctx.frame_type.clone(),
            filter: ctx.filter_name.clone(),
            filter_position: ctx.filter_index,
            gain: ctx.gain,
            offset: ctx.offset,
            ccd_temp: ctx.sensor_temp_c,
            set_temp: ctx.set_temp_c,
            ra,
            dec,
            // The altitude the sequencer derived from that same pointing, in
            // the same breath it read it. This was hardcoded `None` under a
            // comment saying `FrameContext` carried no altitude — true when it
            // was written, false since the mount telemetry moved into the
            // context (`mount_altitude_deg`). Dropping it here is what left
            // sequenced frames with neither OBJCTALT nor AIRMASS: extinction
            // correction needs one of them, and neither can be recovered later
            // from a file that recorded only where the scope pointed.
            altitude: ctx.mount_altitude_deg,
            telescope: ctx.telescope_name.clone(),
            instrument,
            observer: ctx.observer_name.clone(),
            bin_x: ctx.binning_x as i32,
            bin_y: ctx.binning_y as i32,
            focal_length: ctx.telescope_focal_length_mm,
            aperture: ctx.telescope_aperture_mm,
            // The unbinned pitch the camera reported for this frame. This was
            // hardcoded `None`, so every sequenced sub carried FOCALLEN and
            // APTDIA but no XPIXSZ/YPIXSZ and ASTAP, PixInsight and AstroBin
            // could not derive its plate scale from the file alone — the
            // manual-snapshot path had already been fixed to write them, which
            // left two frames of the same rig disagreeing about the sensor.
            // The writer below multiplies by XBINNING/YBINNING, which is why
            // the context carries the unbinned value.
            pixel_size_x: ctx.camera_pixel_size_x_um,
            pixel_size_y: ctx.camera_pixel_size_y_um,
            site_latitude: ctx.site_latitude_deg,
            site_longitude: ctx.site_longitude_deg,
            site_elevation: ctx.site_elevation_m,
            focuser_position: ctx.focuser_position,
            focuser_temperature: ctx.focuser_temperature_c,
            rotator_angle: ctx.rotator_angle_deg,
            guide_rms_arcsec: ctx.guide_rms_arcsec,
            solved_ra_hours: ctx.plate_solve_ra_hours,
            solved_dec_degrees: ctx.plate_solve_dec_degrees,
            plate_solve_pixel_scale_arcsec: ctx.plate_solve_pixel_scale_arcsec,
            plate_solve_rotation_deg: ctx.plate_solve_rotation_deg,
            bayer_pattern: ctx.bayer_pattern.clone(),
            session_id: Some(ctx.session_id.clone()).filter(|s| !s.is_empty()),
            frame_index: Some(ctx.frame_index),
            total_planned_frames: ctx.total_planned_frames,
            mosaic_name: ctx.mosaic_panel.as_ref().map(|p| p.mosaic_name.clone()),
            mosaic_panel_index: ctx.mosaic_panel.as_ref().map(|p| p.panel_index),
            mosaic_panel_row: ctx.mosaic_panel.as_ref().map(|p| p.row),
            mosaic_panel_column: ctx.mosaic_panel.as_ref().map(|p| p.column),
            mosaic_total_panels: ctx.mosaic_panel.as_ref().map(|p| p.total_panels),
            defect_map_correction: ctx.defect_map_correction.clone(),
            // Science — photometric metadata. The
            // SciencePhotometryInstruction stamps these onto the
            // FrameContext just before the FITS save call.
            photometry_object_catalog: ctx.photometry_object_catalog.clone(),
            photometry_reference_stars: ctx
                .photometry_reference_stars
                .as_ref()
                .map(|refs| refs.join(",")),
            photometry_mjd_obs: ctx.photometry_mjd_obs,
            photometry_instrumental_mag: ctx.photometry_instrumental_mag,
            photometry_differential_mag: ctx.photometry_differential_mag,
            photometry_fwhm_arcsec: ctx.photometry_fwhm_arcsec,
            photometry_snr: ctx.photometry_snr,
            // Dual-rig — carry the rig attribution into the FITS header.
            rig_label: ctx.rig_label.clone(),
        }
    }
}

/// Format a signed sexagesimal angle as `±DD MM SS.SS`, the space-separated
/// form MaxIm DL / N.I.N.A. write for `OBJCTRA` / `OBJCTDEC`.
#[flutter_rust_bridge::frb(ignore)]
fn format_sexagesimal(value: f64, signed: bool) -> String {
    let negative = value < 0.0;
    let mut total_seconds = value.abs() * 3600.0;
    // Round to 1/100 s first so a value like 7.9999999 h renders as 08 00 00.00
    // instead of 07 59 60.00.
    total_seconds = (total_seconds * 100.0).round() / 100.0;
    let units = (total_seconds / 3600.0).floor();
    let minutes = ((total_seconds - units * 3600.0) / 60.0).floor();
    let seconds = total_seconds - units * 3600.0 - minutes * 60.0;
    let sign = if signed {
        if negative {
            "-"
        } else {
            "+"
        }
    } else if negative {
        "-"
    } else {
        ""
    };
    format!(
        "{}{:02} {:02} {:05.2}",
        sign, units as i64, minutes as i64, seconds
    )
}

/// Write the pointing keywords for a frame.
///
/// Nightshade carries RA in **hours** everywhere internally (the ASCOM
/// `RightAscension` convention) while Dec is in degrees. The numeric FITS
/// `RA` card, however, is degrees by universal convention — PixInsight,
/// Siril, ASTAP, AstroImageJ and astrometry.net all read it that way — so
/// passing the hour value straight through mis-located every frame by 15x
/// in RA. Convert here, at the one boundary where the unit changes, and
/// also emit the unambiguous sexagesimal `OBJCTRA`/`OBJCTDEC` pair that
/// MaxIm DL and N.I.N.A. write.
#[flutter_rust_bridge::frb(ignore)]
fn set_pointing_keywords(header: &mut FitsHeader, ra_hours: Option<f64>, dec_degrees: Option<f64>) {
    if let Some(ra) = ra_hours {
        if ra.is_finite() {
            header.set_float("RA", ra * 15.0);
            header.set_string("OBJCTRA", &format_sexagesimal(ra, false));
        }
    }
    if let Some(dec) = dec_degrees {
        if dec.is_finite() {
            header.set_float("DEC", dec);
            header.set_string("OBJCTDEC", &format_sexagesimal(dec, true));
        }
    }
}

/// Write the `OBJCTALT` altitude card and the `AIRMASS` derived from it,
/// omitting either when it cannot be stated truthfully.
///
/// The two are gated differently because they are different kinds of number.
/// `OBJCTALT` is the measurement: a parked mount really is at −9.9°, and that
/// is a fact about the frame worth recording. `AIRMASS` is an atmosphere model
/// evaluated at that altitude, and it is undefined below the horizon.
///
/// Recording the altitude and not only the airmass is what makes a frame
/// re-reducible. Airmass is lossy in the direction that matters: the published
/// formulae disagree by ~20% at the horizon (Pickering 38.7 vs Young 31.7 at
/// h=0°), so a photometry pipeline that wants to apply its own extinction
/// model cannot recover the altitude the writer started from. Every mainstream
/// capture app records it for that reason — N.I.N.A. and SGP as `OBJCTALT`,
/// MaxIm DL as `CENTALT` — so a Nightshade file without it is one a
/// photometry workflow can tell apart from every other app's.
///
/// AIRMASS itself is a convenience keyword — every stacker works without it —
/// but [`calculate_airmass`] deliberately refuses sub-horizon altitudes, and
/// darks and flats are by definition taken parked or capped (Alt < 0). The
/// previous code propagated that refusal with `?`, which aborted the entire
/// FITS write and destroyed the frame: the thumbnail landed on disk and the
/// science data did not. Losing an optional keyword is always better than
/// losing the exposure, so warn and skip the card instead.
#[flutter_rust_bridge::frb(ignore)]
fn set_horizon_keywords(header: &mut FitsHeader, altitude_degrees: Option<f64>) {
    let Some(altitude) = altitude_degrees else {
        return;
    };
    // A non-finite altitude is a broken read, not a pointing, so neither card
    // is written — same rule `set_pointing_keywords` applies to RA/DEC.
    if !altitude.is_finite() {
        return;
    }
    header.set_float("OBJCTALT", altitude);
    match calculate_airmass(altitude) {
        Ok(airmass) => header.set_float("AIRMASS", airmass),
        Err(e) => tracing::warn!(
            "Omitting AIRMASS from FITS header: cannot compute for altitude {}°: {}. \
             The frame itself, and its OBJCTALT card, are unaffected.",
            altitude,
            e
        ),
    }
}

/// Save image data to FITS file
pub async fn api_save_fits_file(
    file_path: String,
    width: u32,
    height: u32,
    data: Vec<u16>,
    header_data: FitsWriteHeader,
) -> Result<(), NightshadeError> {
    tracing::info!("Saving FITS file to: {}", file_path);

    // Create ImageData
    let image = ImageData::from_u16(width, height, 1, &data);

    // Validate image data
    let validation = validate_image(&image, Some(width), Some(height));
    if !validation.is_valid {
        tracing::warn!("Image validation failed: {:?}", validation.errors);
    }
    for warning in &validation.warnings {
        tracing::warn!("Image validation warning: {}", warning);
    }

    // Create FitsHeader
    let mut header = FitsHeader::new();

    // Core observation metadata
    header.set_float("EXPTIME", header_data.exposure_time);
    header.set_string("DATE-OBS", &header_data.capture_timestamp);
    header.set_string("IMAGETYP", &header_data.frame_type);

    if let Some(name) = header_data.object_name {
        header.set_string("OBJECT", &name);
    }
    if let Some(filter) = header_data.filter {
        header.set_string("FILTER", &filter);
    }

    // Camera settings.
    // Why: gain/offset/bin_{x,y} are i32; widening to i64 (sign-extended) is always safe.
    if let Some(gain) = header_data.gain {
        header.set_int("GAIN", gain as i64);
    }
    if let Some(offset) = header_data.offset {
        header.set_int("OFFSET", offset as i64);
    }
    if let Some(temp) = header_data.ccd_temp {
        header.set_float("CCD-TEMP", temp);
    }

    header.set_int("XBINNING", header_data.bin_x as i64);
    header.set_int("YBINNING", header_data.bin_y as i64);

    // Pixel size information
    if let Some(pixel_x) = header_data.pixel_size_x {
        header.set_float("PIXSIZE1", pixel_x);
        header.set_float("XPIXSZ", pixel_x * header_data.bin_x as f64);
    }
    if let Some(pixel_y) = header_data.pixel_size_y {
        header.set_float("PIXSIZE2", pixel_y);
        header.set_float("YPIXSZ", pixel_y * header_data.bin_y as f64);
    }

    // Telescope/optics information
    if let Some(focal_length) = header_data.focal_length {
        header.set_float("FOCALLEN", focal_length);
    }
    if let Some(aperture) = header_data.aperture {
        header.set_float("APTDIA", aperture);
    }
    if let Some(telescope) = header_data.telescope {
        header.set_string("TELESCOP", &telescope);
    }
    if let Some(instrument) = header_data.instrument {
        header.set_string("INSTRUME", &instrument);
    }

    // Observer information
    if let Some(observer) = header_data.observer {
        header.set_string("OBSERVER", &observer);
    }

    // Observer location
    if let Some(lat) = header_data.site_latitude {
        header.set_float("SITELAT", lat);
    }
    if let Some(long) = header_data.site_longitude {
        header.set_float("SITELONG", long);
    }
    if let Some(elev) = header_data.site_elevation {
        header.set_float("SITEELEV", elev);
    }

    // Target coordinates + horizon coordinates. RA arrives in hours and
    // leaves in degrees; OBJCTALT/AIRMASS are optional and never fatal (see
    // helpers above).
    set_pointing_keywords(&mut header, header_data.ra, header_data.dec);
    set_horizon_keywords(&mut header, header_data.altitude);

    // Validate header completeness
    let header_validation = validate_fits_header(&header);
    for warning in &header_validation.warnings {
        tracing::debug!("FITS header warning: {}", warning);
    }

    // Ensure directory exists
    if let Some(parent) = std::path::Path::new(&file_path).parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            NightshadeError::OperationFailed(format!("Failed to create directory: {}", e))
        })?;
    }

    // Write file
    // write_fits is blocking, so execute it in spawn_blocking.

    let path = std::path::PathBuf::from(file_path);

    tokio::task::spawn_blocking(move || write_fits(&path, &image, &header))
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("Task join error: {}", e)))?
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to write FITS: {}", e)))?;

    Ok(())
}

/// Image Grading: save FITS with the rich (~40-keyword) header
/// bundle. Used by the sequencer's per-frame save path. Not FRB-exposed —
/// Dart callers continue to use [`api_save_fits_file`] / [`FitsWriteHeader`].
///
/// Writes every keyword the standard astrophotography workflow expects
/// (NINA / SGP / APP / PixInsight / ASTAP all read these), plus the
/// Nightshade-specific `NS-*` keywords for session / mosaic / frame
/// accounting. Missing optional fields are silently omitted — never
/// substituted with sentinel values.
pub async fn save_fits_file_rich(
    file_path: String,
    width: u32,
    height: u32,
    data: Vec<u16>,
    header_data: FitsWriteHeaderRich,
) -> Result<(), NightshadeError> {
    tracing::info!("Saving rich-header FITS file to: {}", file_path);

    let image = ImageData::from_u16(width, height, 1, &data);

    let validation = validate_image(&image, Some(width), Some(height));
    if !validation.is_valid {
        tracing::warn!("Image validation failed: {:?}", validation.errors);
    }
    for warning in &validation.warnings {
        tracing::warn!("Image validation warning: {}", warning);
    }

    let mut header = FitsHeader::new();

    // ------------------------------------------------------------------
    // Core observation metadata.
    // ------------------------------------------------------------------
    header.set_float("EXPTIME", header_data.exposure_time);
    header.set_string("DATE-OBS", &header_data.capture_timestamp);
    header.set_string("IMAGETYP", &header_data.frame_type);

    if let Some(name) = &header_data.object_name {
        header.set_string("OBJECT", name);
    }
    if let Some(filter) = &header_data.filter {
        header.set_string("FILTER", filter);
    }
    if let Some(pos) = header_data.filter_position {
        header.set_int("FILTPOS", pos as i64);
    }

    // ------------------------------------------------------------------
    // Camera / sensor configuration.
    // ------------------------------------------------------------------
    if let Some(gain) = header_data.gain {
        header.set_int("GAIN", gain as i64);
    }
    if let Some(offset) = header_data.offset {
        header.set_int("OFFSET", offset as i64);
    }
    if let Some(temp) = header_data.ccd_temp {
        header.set_float("CCD-TEMP", temp);
    }
    if let Some(set_temp) = header_data.set_temp {
        header.set_float("SET-TEMP", set_temp);
    }

    header.set_int("XBINNING", header_data.bin_x as i64);
    header.set_int("YBINNING", header_data.bin_y as i64);

    if let Some(pixel_x) = header_data.pixel_size_x {
        header.set_float("PIXSIZE1", pixel_x);
        header.set_float("XPIXSZ", pixel_x * header_data.bin_x as f64);
    }
    if let Some(pixel_y) = header_data.pixel_size_y {
        header.set_float("PIXSIZE2", pixel_y);
        header.set_float("YPIXSZ", pixel_y * header_data.bin_y as f64);
    }

    if let Some(bayer) = &header_data.bayer_pattern {
        header.set_string("BAYERPAT", bayer);
    }

    // ------------------------------------------------------------------
    // Telescope / optics identification.
    // ------------------------------------------------------------------
    if let Some(focal_length) = header_data.focal_length {
        header.set_float("FOCALLEN", focal_length);
    }
    if let Some(aperture) = header_data.aperture {
        header.set_float("APTDIA", aperture);
    }
    if let Some(telescope) = &header_data.telescope {
        header.set_string("TELESCOP", telescope);
    }
    if let Some(instrument) = &header_data.instrument {
        header.set_string("INSTRUME", instrument);
    }

    // ------------------------------------------------------------------
    // Observer / site.
    // ------------------------------------------------------------------
    if let Some(observer) = &header_data.observer {
        header.set_string("OBSERVER", observer);
    }
    if let Some(lat) = header_data.site_latitude {
        header.set_float("SITELAT", lat);
    }
    if let Some(long) = header_data.site_longitude {
        header.set_float("SITELONG", long);
    }
    if let Some(elev) = header_data.site_elevation {
        header.set_float("SITEELEV", elev);
    }

    // ------------------------------------------------------------------
    // Target coordinates + horizon coordinates. RA arrives in hours and
    // leaves in degrees; OBJCTALT/AIRMASS are optional and never fatal (see
    // helpers above).
    // ------------------------------------------------------------------
    set_pointing_keywords(&mut header, header_data.ra, header_data.dec);
    set_horizon_keywords(&mut header, header_data.altitude);

    // ------------------------------------------------------------------
    // Image Grading: live device telemetry.
    // ------------------------------------------------------------------
    if let Some(pos) = header_data.focuser_position {
        header.set_int("FOCUSPOS", pos as i64);
    }
    if let Some(t) = header_data.focuser_temperature {
        header.set_float("FOCTEMP", t);
    }
    if let Some(angle) = header_data.rotator_angle {
        header.set_float("ROTATPOS", angle);
    }
    if let Some(rms) = header_data.guide_rms_arcsec {
        header.set_float("GUIDERMS", rms);
    }

    // ------------------------------------------------------------------
    // Plate-solve result. SOLVED-RA / SOLVED-DEC are Nightshade
    // conventions consumed by re-stacking workflows that want to
    // compare the commanded pointing (RA/DEC) against where the field
    // actually landed.
    // ------------------------------------------------------------------
    // Plate-solve result. FITS keywords are capped at 8 characters; we use
    // `SOLVRA` / `SOLVDEC` (Nightshade convention, also used by Voyager and
    // some PixInsight imports) plus the standard `PIXSCALE`.
    if let Some(ra) = header_data.solved_ra_hours {
        header.set_float("SOLVRA", ra);
    }
    if let Some(dec) = header_data.solved_dec_degrees {
        header.set_float("SOLVDEC", dec);
    }
    if let Some(scale) = header_data.plate_solve_pixel_scale_arcsec {
        header.set_float("PIXSCALE", scale);
    }
    if let Some(rot) = header_data.plate_solve_rotation_deg {
        // CROTA1 and CROTA2 are the WCS-standard field-rotation keywords;
        // every stacker reads at least one of them. Setting both follows
        // NINA's convention so PI / APP pick it up without configuration.
        header.set_float("CROTA1", rot);
        header.set_float("CROTA2", rot);
    }

    // ------------------------------------------------------------------
    // Nightshade-specific session / frame / mosaic accounting (NS-*).
    // ------------------------------------------------------------------
    if let Some(session_id) = &header_data.session_id {
        header.set_string("NS-SESID", session_id);
    }
    if let Some(idx) = header_data.frame_index {
        header.set_int("NS-FIDX", idx as i64);
    }
    if let Some(total) = header_data.total_planned_frames {
        header.set_int("NS-NPLN", total as i64);
    }
    if let Some(name) = &header_data.mosaic_name {
        // MOSAIC=1 is the boolean "this frame is part of a mosaic"
        // flag, kept as an integer keyword for maximum reader
        // compatibility (some tools refuse BOOLEAN FITS values).
        header.set_int("MOSAIC", 1);
        header.set_string("NS-MOSNM", name);
    }
    if let Some(idx) = header_data.mosaic_panel_index {
        // 1-based for human readability in viewers (panel 1, 2, 3 ...)
        // while keeping the original 0-based index in NS-PIDX for the
        // re-import path.
        header.set_int("PANELIDX", (idx + 1) as i64);
        header.set_int("NS-PIDX", idx as i64);
    }
    if let Some(row) = header_data.mosaic_panel_row {
        header.set_int("PANELROW", row as i64);
        header.set_int("NS-PROW", row as i64);
    }
    if let Some(col) = header_data.mosaic_panel_column {
        header.set_int("PANELCOL", col as i64);
        header.set_int("NS-PCOL", col as i64);
    }
    if let Some(total) = header_data.mosaic_total_panels {
        header.set_int("NS-NPAN", total as i64);
    }
    // Dual-rig — optical-train / camera attribution for multi-camera sessions.
    // Omitted for the single-rig case so existing frames are unchanged.
    if let Some(rig) = &header_data.rig_label {
        header.set_string("NS-RIG", rig);
    }

    // ------------------------------------------------------------------
    // defect-map correction HISTORY card. When the
    // sequencer applied a defect map to this frame, record the
    // provenance so re-stacking workflows know the cosmetic correction
    // has already been done (and can skip re-applying it).
    // ------------------------------------------------------------------
    if let Some(record) = &header_data.defect_map_correction {
        let history = format!(
            "Nightshade applied defect map v1 for camera {}: corrected {} of {} \
             defective pixels with {}x{} kernel using {} replacement.",
            record.camera_id,
            record.corrected_count,
            record.defect_count,
            record.kernel_diameter,
            record.kernel_diameter,
            record.method,
        );
        header.add_history(&history);
    }

    // ------------------------------------------------------------------
    // Science — photometric metadata. Stamped when the frame
    // was captured by the SciencePhotometryInstruction. Non-photometric
    // captures omit every keyword.
    // ------------------------------------------------------------------
    if let Some(catalog) = &header_data.photometry_object_catalog {
        if !catalog.is_empty() {
            header.set_string("OBJCAT", catalog);
        }
    }
    if let Some(refs) = &header_data.photometry_reference_stars {
        if !refs.is_empty() {
            // FITS keyword values are 70 chars after the equals sign;
            // the joined reference-star list can exceed that, so we
            // store it on a CONTINUE-style card as a comment. For
            // ergonomic readability via FITS viewers we use a single
            // REFSTARS card and truncate beyond 68 characters (the
            // standard one-card payload).
            let truncated = if refs.len() > 68 {
                format!("{}...", &refs[..65])
            } else {
                refs.clone()
            };
            header.set_string("REFSTARS", &truncated);
        }
    }
    if let Some(mjd) = header_data.photometry_mjd_obs {
        header.set_float("MJD-OBS", mjd);
    }
    if let Some(mag) = header_data.photometry_instrumental_mag {
        header.set_float("INSTRMAG", mag);
    }
    if let Some(mag) = header_data.photometry_differential_mag {
        header.set_float("DIFFMAG", mag);
    }
    if let Some(fwhm) = header_data.photometry_fwhm_arcsec {
        header.set_float("FWHM", fwhm);
    }
    if let Some(snr) = header_data.photometry_snr {
        header.set_float("SNR", snr);
    }

    // ------------------------------------------------------------------
    // Validate header completeness — warnings only; we never refuse to
    // write a frame because of a missing nice-to-have keyword.
    // ------------------------------------------------------------------
    let header_validation = validate_fits_header(&header);
    for warning in &header_validation.warnings {
        tracing::debug!("FITS header warning: {}", warning);
    }

    if let Some(parent) = std::path::Path::new(&file_path).parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            NightshadeError::OperationFailed(format!("Failed to create directory: {}", e))
        })?;
    }

    let path = std::path::PathBuf::from(file_path);

    tokio::task::spawn_blocking(move || write_fits(&path, &image, &header))
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("Task join error: {}", e)))?
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to write FITS: {}", e)))?;

    Ok(())
}

/// Save FITS file directly from the last captured image stored in Rust
/// This eliminates the need to transfer raw pixel data across the FFI boundary
/// by using the image data already stored from the last exposure.
///
/// Returns an error if no image has been captured yet for the specified device.
pub async fn api_save_fits_from_last_capture(
    device_id: String,
    file_path: String,
    header_data: FitsWriteHeader,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Saving FITS from last capture for device {} to: {}",
        device_id,
        file_path
    );

    // Get the stored raw image data for this device
    let mut storage = get_unified_image_storage().lock().await;
    let captured_data = storage.get(&device_id).ok_or_else(|| {
        NightshadeError::OperationFailed(format!(
            "No captured image available for device {}. Please capture an image first.",
            device_id
        ))
    })?;

    // Clone the data we need so we can release the lock before the blocking write
    let width = captured_data.raw_info.width;
    let height = captured_data.raw_info.height;
    let data = captured_data.raw_info.data.clone();
    drop(storage); // Release the lock

    // Now save using the existing logic
    tracing::info!("Saving {}x{} image ({} pixels)", width, height, data.len());

    // Create ImageData
    let image = ImageData::from_u16(width, height, 1, &data);

    // Validate image data
    let validation = validate_image(&image, Some(width), Some(height));
    if !validation.is_valid {
        tracing::warn!("Image validation failed: {:?}", validation.errors);
    }
    for warning in &validation.warnings {
        tracing::warn!("Image validation warning: {}", warning);
    }

    // Create FitsHeader
    let mut header = FitsHeader::new();

    // Core observation metadata
    header.set_float("EXPTIME", header_data.exposure_time);
    header.set_string("DATE-OBS", &header_data.capture_timestamp);
    header.set_string("IMAGETYP", &header_data.frame_type);

    if let Some(name) = header_data.object_name {
        header.set_string("OBJECT", &name);
    }
    if let Some(filter) = header_data.filter {
        header.set_string("FILTER", &filter);
    }

    // Camera settings.
    // Why: gain/offset/bin_{x,y} are i32; widening to i64 (sign-extended) is always safe.
    if let Some(gain) = header_data.gain {
        header.set_int("GAIN", gain as i64);
    }
    if let Some(offset) = header_data.offset {
        header.set_int("OFFSET", offset as i64);
    }
    if let Some(temp) = header_data.ccd_temp {
        header.set_float("CCD-TEMP", temp);
    }

    header.set_int("XBINNING", header_data.bin_x as i64);
    header.set_int("YBINNING", header_data.bin_y as i64);

    // Pixel size information
    if let Some(pixel_x) = header_data.pixel_size_x {
        header.set_float("PIXSIZE1", pixel_x);
        header.set_float("XPIXSZ", pixel_x * header_data.bin_x as f64);
    }
    if let Some(pixel_y) = header_data.pixel_size_y {
        header.set_float("PIXSIZE2", pixel_y);
        header.set_float("YPIXSZ", pixel_y * header_data.bin_y as f64);
    }

    // Telescope/optics information
    if let Some(focal_length) = header_data.focal_length {
        header.set_float("FOCALLEN", focal_length);
    }
    if let Some(aperture) = header_data.aperture {
        header.set_float("APTDIA", aperture);
    }
    if let Some(telescope) = header_data.telescope {
        header.set_string("TELESCOP", &telescope);
    }
    if let Some(instrument) = header_data.instrument {
        header.set_string("INSTRUME", &instrument);
    }

    // Observer information
    if let Some(observer) = header_data.observer {
        header.set_string("OBSERVER", &observer);
    }

    // Observer location
    if let Some(lat) = header_data.site_latitude {
        header.set_float("SITELAT", lat);
    }
    if let Some(long) = header_data.site_longitude {
        header.set_float("SITELONG", long);
    }
    if let Some(elev) = header_data.site_elevation {
        header.set_float("SITEELEV", elev);
    }

    // Target coordinates + horizon coordinates. RA arrives in hours and
    // leaves in degrees; OBJCTALT/AIRMASS are optional and never fatal (see
    // helpers above).
    set_pointing_keywords(&mut header, header_data.ra, header_data.dec);
    set_horizon_keywords(&mut header, header_data.altitude);

    // Validate header completeness
    let header_validation = validate_fits_header(&header);
    for warning in &header_validation.warnings {
        tracing::debug!("FITS header warning: {}", warning);
    }

    // Ensure directory exists
    if let Some(parent) = std::path::Path::new(&file_path).parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            NightshadeError::OperationFailed(format!("Failed to create directory: {}", e))
        })?;
    }

    // Write file using spawn_blocking
    let path = std::path::PathBuf::from(file_path);

    tokio::task::spawn_blocking(move || write_fits(&path, &image, &header))
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("Task join error: {}", e)))?
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to write FITS: {}", e)))?;

    tracing::info!("FITS file saved successfully from last capture");
    Ok(())
}

// =============================================================================
// Image Processing
// =============================================================================

/// Calculate image statistics
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_image_stats(
    width: u32,
    height: u32,
    data: Vec<u16>,
) -> Result<ImageStatsResult, NightshadeError> {
    let stats = crate::imaging_ops::get_image_stats(width, height, data);
    Ok(ImageStatsResult {
        min: stats.min,
        max: stats.max,
        mean: stats.mean,
        median: stats.median,
        std_dev: stats.std_dev,
        // Basic-stats path runs no star detection: honest None for both.
        hfr: None,
        eccentricity: None,
        fwhm: None,
        star_count: 0,
    })
}

/// Auto-stretch image for display
#[flutter_rust_bridge::frb(sync)]
pub fn api_auto_stretch_image(
    width: u32,
    height: u32,
    data: Vec<u16>,
) -> Result<Vec<u8>, NightshadeError> {
    Ok(crate::imaging_ops::auto_stretch_image(width, height, data))
}

/// Auto-stretch an interleaved RGB16 image for display.
///
/// The colour counterpart to [`api_auto_stretch_image`]: `data` is
/// `width * height * 3` u16 samples (interleaved R,G,B) and each channel is
/// stretched with its own PixInsight MAD-based STF ("Unlinked" mode). Returns
/// RGBA8 (4 bytes per pixel, alpha=255). OSC live-stacking / Stack-and-Share
/// display delegates here so the STF lives in one place (Rust) rather than being
/// reimplemented in Dart.
#[flutter_rust_bridge::frb(sync)]
pub fn api_auto_stretch_color_image(
    width: u32,
    height: u32,
    data: Vec<u16>,
) -> Result<Vec<u8>, NightshadeError> {
    Ok(crate::imaging_ops::auto_stretch_color_image(
        width, height, data,
    ))
}

/// Debayer image
#[flutter_rust_bridge::frb(sync)]
pub fn api_debayer_image(
    width: u32,
    height: u32,
    data: Vec<u16>,
    pattern_str: String,
    algo_str: String,
) -> Result<Vec<u8>, NightshadeError> {
    let pattern = BayerPattern::from_str(&pattern_str).ok_or_else(|| {
        NightshadeError::InvalidParameter(format!("Invalid bayer pattern: {}", pattern_str))
    })?;

    let algorithm = match algo_str.to_lowercase().as_str() {
        "bilinear" => DebayerAlgorithm::Bilinear,
        "vng" => DebayerAlgorithm::VNG,
        "superpixel" => DebayerAlgorithm::SuperPixel,
        _ => DebayerAlgorithm::Bilinear,
    };

    Ok(crate::imaging_ops::debayer_image(
        width, height, data, pattern, algorithm,
    ))
}

/// Generate thumbnail from FITS file
/// Returns JPEG-encoded thumbnail data (~512x512 pixels)
#[flutter_rust_bridge::frb(sync)]
pub fn api_generate_fits_thumbnail(
    file_path: String,
    max_size: u32,
) -> Result<Vec<u8>, NightshadeError> {
    use nightshade_imaging::read_fits;
    use std::path::Path;

    // Read FITS file
    let path = Path::new(&file_path);
    let (image_data, _header) = read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {:?}", e)))?;

    let width = image_data.width;
    let height = image_data.height;
    let channels = image_data.channels as usize;
    if width == 0 || height == 0 {
        return Err(NightshadeError::ImageError(format!(
            "Cannot generate thumbnail for empty FITS image {}x{}",
            width, height
        )));
    }
    if channels == 0 {
        return Err(NightshadeError::ImageError(
            "Cannot generate thumbnail for FITS image with zero channels".to_string(),
        ));
    }
    if max_size == 0 {
        return Err(NightshadeError::InvalidParameter(
            "Thumbnail max_size must be greater than zero".to_string(),
        ));
    }

    let pixel_count = (width as usize)
        .checked_mul(height as usize)
        .ok_or_else(|| {
            NightshadeError::ImageError(format!(
                "FITS image dimensions overflow: {}x{}",
                width, height
            ))
        })?;
    let sample_count = pixel_count.checked_mul(channels).ok_or_else(|| {
        NightshadeError::ImageError(format!(
            "FITS sample count overflows for {}x{} image with {} channels",
            width, height, channels
        ))
    })?;
    let expected_bytes = sample_count
        .checked_mul(image_data.pixel_type.byte_size())
        .ok_or_else(|| {
            NightshadeError::ImageError(format!(
                "FITS buffer size overflows for {} samples",
                sample_count
            ))
        })?;
    if image_data.data.len() != expected_bytes {
        return Err(NightshadeError::ImageError(format!(
            "Invalid FITS buffer length: expected {} bytes, got {}",
            expected_bytes,
            image_data.data.len()
        )));
    }

    // Convert to u16 data
    let data_u16 = match image_data.pixel_type {
        nightshade_imaging::PixelType::U8 => {
            // Convert u8 to u16
            image_data
                .data
                .iter()
                .map(|&b| (b as u16) << 8)
                .collect::<Vec<u16>>()
        }
        nightshade_imaging::PixelType::U16 => {
            // Already u16, convert bytes to u16 values
            image_data
                .data
                .chunks_exact(2)
                .map(|chunk| u16::from_le_bytes([chunk[0], chunk[1]]))
                .collect::<Vec<u16>>()
        }
        nightshade_imaging::PixelType::U32 => {
            // Convert u32 to u16 (downscale)
            image_data
                .data
                .chunks_exact(4)
                .map(|chunk| {
                    let val = u32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                    (val >> 16) as u16 // Take high 16 bits
                })
                .collect::<Vec<u16>>()
        }
        nightshade_imaging::PixelType::F32 => {
            // Convert f32 to u16 (scale 0.0-1.0 to 0-65535)
            image_data
                .data
                .chunks_exact(4)
                .map(|chunk| {
                    let val = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                    (val.clamp(0.0, 1.0) * 65535.0) as u16
                })
                .collect::<Vec<u16>>()
        }
        nightshade_imaging::PixelType::F64 => {
            // Convert f64 to u16 (scale 0.0-1.0 to 0-65535)
            image_data
                .data
                .chunks_exact(8)
                .map(|chunk| {
                    let val = f64::from_le_bytes([
                        chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6],
                        chunk[7],
                    ]);
                    (val.clamp(0.0, 1.0) * 65535.0) as u16
                })
                .collect::<Vec<u16>>()
        }
    };

    // Calculate downscale factor
    let max_dimension = width.max(height);
    let scale = (max_dimension / max_size + u32::from(max_dimension % max_size != 0)).max(1);

    // Downscale image
    let new_width = (width / scale).max(1);
    let new_height = (height / scale).max(1);
    let thumbnail_pixels = (new_width as usize)
        .checked_mul(new_height as usize)
        .ok_or_else(|| {
            NightshadeError::ImageError(format!(
                "Thumbnail dimensions overflow: {}x{}",
                new_width, new_height
            ))
        })?;
    let expected_rgba_bytes = thumbnail_pixels.checked_mul(4).ok_or_else(|| {
        NightshadeError::ImageError(format!(
            "Thumbnail RGBA buffer size overflows for {} pixels",
            thumbnail_pixels
        ))
    })?;
    let mut downscaled = Vec::new();
    downscaled
        .try_reserve_exact(thumbnail_pixels)
        .map_err(|e| {
            NightshadeError::ImageError(format!(
                "Failed to allocate {}-pixel thumbnail: {}",
                thumbnail_pixels, e
            ))
        })?;

    for y in 0..new_height {
        for x in 0..new_width {
            let src_x = x * scale;
            let src_y = y * scale;
            let pixel_idx = (src_y as usize)
                .checked_mul(width as usize)
                .and_then(|row| row.checked_add(src_x as usize))
                .ok_or_else(|| {
                    NightshadeError::ImageError("FITS pixel index overflow".to_string())
                })?;
            let sample_idx = pixel_idx.checked_mul(channels).ok_or_else(|| {
                NightshadeError::ImageError("FITS sample index overflow".to_string())
            })?;
            let sample_end = sample_idx.checked_add(channels).ok_or_else(|| {
                NightshadeError::ImageError("FITS sample index overflow".to_string())
            })?;
            let samples = data_u16.get(sample_idx..sample_end).ok_or_else(|| {
                NightshadeError::ImageError(format!(
                    "FITS pixel {} falls outside its validated sample buffer",
                    pixel_idx
                ))
            })?;
            if let [r, g, b, ..] = samples {
                let r = *r as u32;
                let g = *g as u32;
                let b = *b as u32;
                downscaled.push(((77 * r + 150 * g + 29 * b + 128) >> 8) as u16);
            } else {
                let value = samples.first().copied().ok_or_else(|| {
                    NightshadeError::ImageError(format!(
                        "FITS pixel {} has no channel samples",
                        pixel_idx
                    ))
                })?;
                downscaled.push(value);
            }
        }
    }

    // Auto-stretch for display
    let stretched_rgba = crate::imaging_ops::auto_stretch_image(new_width, new_height, downscaled);
    if stretched_rgba.len() != expected_rgba_bytes {
        return Err(NightshadeError::ImageError(format!(
            "Invalid stretched thumbnail length: expected {} bytes, got {}",
            expected_rgba_bytes,
            stretched_rgba.len()
        )));
    }
    let stretched: Vec<u8> = stretched_rgba.chunks_exact(4).map(|rgba| rgba[0]).collect();
    if stretched.len() != thumbnail_pixels {
        return Err(NightshadeError::ImageError(format!(
            "Invalid grayscale thumbnail length: expected {} bytes, got {}",
            thumbnail_pixels,
            stretched.len()
        )));
    }

    // Encode as JPEG
    use image::{GrayImage, ImageEncoder};
    use std::io::Cursor;

    let gray_img = GrayImage::from_raw(new_width, new_height, stretched).ok_or_else(|| {
        NightshadeError::ImageError("Failed to create grayscale image".to_string())
    })?;

    let mut jpeg_data = Vec::new();
    let mut cursor = Cursor::new(&mut jpeg_data);
    let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut cursor, 85);
    encoder
        .write_image(
            gray_img.as_raw(),
            new_width,
            new_height,
            image::ColorType::L8,
        )
        .map_err(|e| NightshadeError::ImageError(format!("JPEG encoding failed: {}", e)))?;

    Ok(jpeg_data)
}

/// Apply Auto White Balance using Histogram Peak Alignment
/// This aligns the background sky peak of R and B channels to the G channel
pub(crate) fn apply_auto_white_balance(image: &mut [u16]) {
    if image.len() % 3 != 0 {
        return;
    }

    let mut hist_r = vec![0u32; 65536];
    let mut hist_g = vec![0u32; 65536];
    let mut hist_b = vec![0u32; 65536];

    // 1. Compute histograms
    for chunk in image.chunks(3) {
        hist_r[chunk[0] as usize] += 1;
        hist_g[chunk[1] as usize] += 1;
        hist_b[chunk[2] as usize] += 1;
    }

    // 2. Find peaks (modes), ignoring bottom 1% to avoid clipping noise
    // A simple mode might be noisy, so let's find the max bin
    // We start searching from a small offset to avoid black clipping
    let start_idx = 100; // arbitrary small offset

    let get_peak = |hist: &[u32]| -> u16 {
        let mut max_count = 0;
        let mut peak_idx = 0;
        for (i, &count) in hist.iter().enumerate().skip(start_idx) {
            if count > max_count {
                max_count = count;
                peak_idx = i;
            }
        }
        peak_idx as u16
    };

    let peak_r = get_peak(&hist_r);
    let peak_g = get_peak(&hist_g);
    let peak_b = get_peak(&hist_b);

    tracing::info!("AWB Peaks: R={}, G={}, B={}", peak_r, peak_g, peak_b);

    if peak_r == 0 || peak_g == 0 || peak_b == 0 {
        tracing::warn!("AWB failed: peak is 0");
        return;
    }

    // 3. Calculate scaling factors to align to Green
    let target = peak_g as f32;
    let scale_r = target / peak_r as f32;
    let scale_b = target / peak_b as f32;

    tracing::info!("AWB Scales: R={:.3}, B={:.3}", scale_r, scale_b);

    // 4. Apply scaling
    // Use parallel iterator for speed if possible, but slice is mutable
    // Rayon's par_chunks_mut is perfect
    use rayon::prelude::*;
    image.par_chunks_mut(3).for_each(|pixel| {
        // R
        pixel[0] = (pixel[0] as f32 * scale_r).min(65535.0) as u16;
        // G (unchanged)
        // B
        pixel[2] = (pixel[2] as f32 * scale_b).min(65535.0) as u16;
    });
}

// =============================================================================
// INDI Autofocus
// =============================================================================

/// INDI autofocus configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IndiAutofocusConfigApi {
    pub method: String, // "vcurve", "quadratic", "hyperbolic"
    pub step_size: i32,
    pub steps_out: u32,
    pub exposure_duration: f64,
    pub backlash_compensation: i32,
    pub use_temperature_prediction: bool,
    pub max_star_count_change: Option<f64>,
    pub outlier_rejection_sigma: f64,
    pub binning: i32,
    pub move_timeout_secs: u64,
    pub settling_time_ms: u64,
}

impl Default for IndiAutofocusConfigApi {
    fn default() -> Self {
        Self {
            method: "vcurve".to_string(),
            step_size: 100,
            steps_out: 7,
            exposure_duration: 3.0,
            backlash_compensation: 50,
            use_temperature_prediction: true,
            max_star_count_change: Some(0.5),
            outlier_rejection_sigma: 3.0,
            binning: 1,
            move_timeout_secs: 120,
            settling_time_ms: 500,
        }
    }
}

/// INDI autofocus result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IndiAutofocusResultApi {
    pub best_position: i32,
    pub best_hfr: f64,
    pub curve_fit_quality: f64,
    pub method_used: String,
    pub data_points: Vec<FocusDataPointApi>,
    pub temperature_celsius: Option<f64>,
    pub backlash_applied: bool,
    pub success: bool,
    pub error_message: Option<String>,
}

/// Focus data point for autofocus curve
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FocusDataPointApi {
    pub position: i32,
    pub hfr: f64,
    pub fwhm: Option<f64>,
    pub star_count: u32,
}

/// Run INDI autofocus routine
///
/// # Arguments
/// * `camera_id` - INDI camera device ID (format: "indi:host:port:device_name")
/// * `focuser_id` - INDI focuser device ID (format: "indi:host:port:device_name")
/// * `config` - Autofocus configuration
///
/// # Returns
/// Autofocus result with best focus position and curve data
pub async fn api_run_indi_autofocus(
    camera_id: String,
    focuser_id: String,
    config: IndiAutofocusConfigApi,
) -> Result<IndiAutofocusResultApi, NightshadeError> {
    tracing::info!(
        "Starting INDI autofocus: camera={}, focuser={}, method={}",
        camera_id,
        focuser_id,
        config.method
    );

    // Validate device IDs are INDI
    if !camera_id.starts_with("indi:") || !focuser_id.starts_with("indi:") {
        return Err(NightshadeError::InvalidParameter(
            "Both camera and focuser must be INDI devices".to_string(),
        ));
    }

    // Get INDI clients for camera and focuser
    let device_manager = get_device_manager();

    let camera_client = device_manager
        .get_indi_client(&camera_id)
        .await
        .ok_or_else(|| {
            NightshadeError::NotConnected(format!("INDI camera not connected: {}", camera_id))
        })?;

    let focuser_client = device_manager
        .get_indi_client(&focuser_id)
        .await
        .ok_or_else(|| {
            NightshadeError::NotConnected(format!("INDI focuser not connected: {}", focuser_id))
        })?;

    // Extract device names from IDs (format: "indi:host:port:device_name")
    let camera_parts: Vec<&str> = camera_id.split(':').collect();
    let camera_device_name = camera_parts[3..].join(":");

    let focuser_parts: Vec<&str> = focuser_id.split(':').collect();
    let focuser_device_name = focuser_parts[3..].join(":");

    // Create INDI camera and focuser wrappers
    let camera = Arc::new(nightshade_indi::IndiCamera::new(
        camera_client,
        &camera_device_name,
    ));

    let focuser = Arc::new(nightshade_indi::IndiFocuser::new(
        focuser_client,
        &focuser_device_name,
    ));

    // Convert config
    let method = match config.method.as_str() {
        "vcurve" => nightshade_indi::autofocus::AutofocusMethod::VCurve,
        "quadratic" => nightshade_indi::autofocus::AutofocusMethod::Quadratic,
        "hyperbolic" => nightshade_indi::autofocus::AutofocusMethod::Hyperbolic,
        _ => nightshade_indi::autofocus::AutofocusMethod::VCurve,
    };

    let af_config = nightshade_indi::autofocus::IndiAutofocusConfig {
        method,
        step_size: config.step_size,
        steps_out: config.steps_out,
        exposure_duration: config.exposure_duration,
        backlash_compensation: config.backlash_compensation,
        use_temperature_prediction: config.use_temperature_prediction,
        max_star_count_change: config.max_star_count_change,
        outlier_rejection_sigma: config.outlier_rejection_sigma,
        binning: config.binning,
        move_timeout_secs: config.move_timeout_secs,
        settling_time_ms: config.settling_time_ms,
    };

    // Create autofocus engine
    let autofocus = nightshade_indi::autofocus::IndiAutofocus::new(camera, focuser, af_config);

    // Run autofocus
    let result = autofocus
        .run()
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("INDI autofocus failed: {}", e)))?;

    // Convert result
    let method_str = match result.method_used {
        nightshade_indi::autofocus::AutofocusMethod::VCurve => "vcurve",
        nightshade_indi::autofocus::AutofocusMethod::Quadratic => "quadratic",
        nightshade_indi::autofocus::AutofocusMethod::Hyperbolic => "hyperbolic",
    };

    let data_points: Vec<FocusDataPointApi> = result
        .data_points
        .iter()
        .map(|dp| FocusDataPointApi {
            position: dp.position,
            hfr: dp.hfr,
            fwhm: dp.fwhm,
            star_count: dp.star_count,
        })
        .collect();

    Ok(IndiAutofocusResultApi {
        best_position: result.best_position,
        best_hfr: result.best_hfr,
        curve_fit_quality: result.curve_fit_quality,
        method_used: method_str.to_string(),
        data_points,
        temperature_celsius: result.temperature_celsius,
        backlash_applied: result.backlash_applied,
        success: result.success,
        error_message: result.error_message,
    })
}

// =============================================================================
// Image Calibration
// =============================================================================

/// Calibrate an image file using dark, flat, and/or bias calibration frames.
///
/// Loads the light frame and any provided calibration frames from disk,
/// applies the calibration pipeline, and saves the result to `output_path`.
///
/// The calibration order is:
/// 1. Subtract bias from dark and flat (if bias provided)
/// 2. Subtract dark from light
/// 3. Divide light by normalized flat
///
/// Any calibration frame path can be empty/None to skip that correction.
pub fn api_calibrate_image_file(
    light_path: String,
    dark_path: Option<String>,
    flat_path: Option<String>,
    bias_path: Option<String>,
    output_path: String,
) -> Result<(), NightshadeError> {
    use nightshade_imaging::{calibration, read_image, write_fits, FitsHeader, ImageFormat};
    use std::path::Path;

    // Load light frame
    let light_result = read_image(Path::new(&light_path)).map_err(|e| {
        NightshadeError::ImageError(format!(
            "Failed to read light frame '{}': {}",
            light_path, e
        ))
    })?;

    // Load optional calibration frames
    let dark = match &dark_path {
        Some(p) if !p.is_empty() => {
            let result = read_image(Path::new(p)).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to read dark frame '{}': {}", p, e))
            })?;
            Some(result.image)
        }
        _ => None,
    };

    let flat = match &flat_path {
        Some(p) if !p.is_empty() => {
            let result = read_image(Path::new(p)).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to read flat frame '{}': {}", p, e))
            })?;
            Some(result.image)
        }
        _ => None,
    };

    let bias = match &bias_path {
        Some(p) if !p.is_empty() => {
            let result = read_image(Path::new(p)).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to read bias frame '{}': {}", p, e))
            })?;
            Some(result.image)
        }
        _ => None,
    };

    // Run calibration pipeline
    let calibrated = calibration::calibrate_frame(
        &light_result.image,
        dark.as_ref(),
        flat.as_ref(),
        bias.as_ref(),
    )
    .map_err(|e| NightshadeError::ImageError(format!("Calibration failed: {}", e)))?;

    // Save calibrated image, preserving original format
    let out = Path::new(&output_path);
    let ext = out.extension().and_then(|e| e.to_str()).unwrap_or("fits");
    let out_format = ImageFormat::from_extension(ext).unwrap_or(ImageFormat::Fits);

    match out_format {
        ImageFormat::Fits => {
            // Carry over header from original light, add calibration note
            let mut header = FitsHeader::new();
            for (key, value) in &light_result.header {
                header.set_string(key, value);
            }
            header.set_string("CALSTAT", "calibrated by Nightshade");
            if let Some(ref path) = dark_path {
                if !path.is_empty() {
                    header.set_string("DARKFILE", path);
                }
            }
            if let Some(ref path) = flat_path {
                if !path.is_empty() {
                    header.set_string("FLATFILE", path);
                }
            }
            if let Some(ref path) = bias_path {
                if !path.is_empty() {
                    header.set_string("BIASFILE", path);
                }
            }

            write_fits(out, &calibrated, &header).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to write calibrated FITS: {:?}", e))
            })?;
        }
        ImageFormat::Xisf => {
            nightshade_imaging::write_xisf(
                out,
                &calibrated,
                &nightshade_imaging::XisfMetadata::default(),
            )
            .map_err(|e| {
                NightshadeError::ImageError(format!("Failed to write calibrated XISF: {:?}", e))
            })?;
        }
        ImageFormat::Tiff => {
            nightshade_imaging::write_tiff(out, &calibrated).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to write calibrated TIFF: {}", e))
            })?;
        }
        ImageFormat::Png => {
            nightshade_imaging::write_png(out, &calibrated).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to write calibrated PNG: {}", e))
            })?;
        }
        _ => {
            // Default to FITS for unsupported output formats
            let header = FitsHeader::new();
            write_fits(out, &calibrated, &header).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to write calibrated file: {:?}", e))
            })?;
        }
    }

    tracing::info!(
        "Calibrated image saved to: {} (dark={}, flat={}, bias={})",
        output_path,
        dark_path
            .as_ref()
            .map_or("none", |p| if p.is_empty() { "none" } else { p.as_str() }),
        flat_path
            .as_ref()
            .map_or("none", |p| if p.is_empty() { "none" } else { p.as_str() }),
        bias_path
            .as_ref()
            .map_or("none", |p| if p.is_empty() { "none" } else { p.as_str() }),
    );

    Ok(())
}

/// Calibrate raw pixel data in memory (u16).
///
/// Takes pixel data directly rather than file paths. Returns calibrated pixel data.
/// All frames must have the same dimensions and be single-channel u16.
#[flutter_rust_bridge::frb(sync)]
pub fn api_calibrate_image_data(
    width: u32,
    height: u32,
    light_data: Vec<u16>,
    dark_data: Option<Vec<u16>>,
    flat_data: Option<Vec<u16>>,
    bias_data: Option<Vec<u16>>,
) -> Result<Vec<u16>, NightshadeError> {
    use nightshade_imaging::{calibration, ImageData};

    let light = ImageData::from_u16(width, height, 1, &light_data);

    let dark = dark_data.map(|d| ImageData::from_u16(width, height, 1, &d));
    let flat = flat_data.map(|f| ImageData::from_u16(width, height, 1, &f));
    let bias = bias_data.map(|b| ImageData::from_u16(width, height, 1, &b));

    let calibrated =
        calibration::calibrate_frame(&light, dark.as_ref(), flat.as_ref(), bias.as_ref())
            .map_err(|e| NightshadeError::ImageError(format!("Calibration failed: {}", e)))?;

    calibrated.as_u16().ok_or_else(|| {
        NightshadeError::ImageError(
            "Failed to extract u16 pixel data from calibrated image".to_string(),
        )
    })
}

// =============================================================================
// Live Stacking API
// =============================================================================

/// Live stacking configuration exposed to Dart
pub struct ApiLiveStackingConfig {
    pub sigma_clip_enabled: bool,
    pub sigma_clip_threshold: f64,
    pub max_match_stars: u32,
    pub match_radius_px: f64,
    pub match_flux_tolerance: f64,
    pub min_matched_pairs: u32,
    /// Sensor acquisition mode: `"mono"`, `"osc"`, or `"auto"` (case-insensitive).
    ///
    /// - `mono` — frames are single-channel luminance; never debayered.
    /// - `osc` — frames are a Bayer CFA mosaic that *must* be debayered to RGB;
    ///   an unresolvable pattern is a hard error (no silent mono-fallback that
    ///   would scramble the colour mosaic).
    /// - `auto` — debayer only when the frame actually carries Bayer geometry
    ///   (or `bayer_pattern` is supplied); otherwise treat as mono.
    ///
    /// Defaults to `"mono"` so existing callers keep the historic single-channel
    /// behaviour byte-for-byte.
    pub sensor_mode: String,
    /// Explicit Bayer pattern override (`"RGGB"`/`"BGGR"`/`"GRBG"`/`"GBRG"`,
    /// case-insensitive). When `None`, OSC/auto sessions fall back to the pattern
    /// the reference frame declares via its FITS `BAYERPAT` geometry. An
    /// unrecognised string is a hard error.
    pub bayer_pattern: Option<String>,
    /// Demosaic quality: `"bilinear"`, `"vng"`, or `"superpixel"`
    /// (case-insensitive). Defaults to `"bilinear"`. An unrecognised value is a
    /// hard error rather than a silent best-guess.
    pub demosaic_quality: String,
}

impl Default for ApiLiveStackingConfig {
    fn default() -> Self {
        // Mirror `LiveStackingConfigApi::default()` so the FRB wrapper and the
        // underlying bridge config agree on the monochrome baseline.
        Self {
            sigma_clip_enabled: true,
            sigma_clip_threshold: 2.5,
            max_match_stars: 100,
            match_radius_px: 50.0,
            match_flux_tolerance: 0.7,
            min_matched_pairs: 5,
            sensor_mode: "mono".to_string(),
            bayer_pattern: None,
            demosaic_quality: "bilinear".to_string(),
        }
    }
}

/// Live stacking statistics returned to Dart
pub struct ApiLiveStackingStats {
    pub stacked_frame_count: u32,
    pub total_frames_attempted: u32,
    pub rejected_alignment_failures: u32,
    pub avg_matched_pairs: f64,
    pub avg_alignment_residual: f64,
    pub total_sigma_rejected_pixels: u64,
}

/// Result from adding a frame to the live stack
pub struct ApiLiveStackingResult {
    pub width: u32,
    pub height: u32,
    /// Channel count of the stacked result: `1` for a monochrome session, `3`
    /// for an OSC/colour session. The Dart side uses this to interpret `data` as
    /// a single luminance plane vs interleaved RGB16.
    pub channels: u32,
    pub data: Vec<u16>,
    pub stats: ApiLiveStackingStats,
}

pub(crate) fn convert_config(
    config: ApiLiveStackingConfig,
) -> crate::stacking_api::LiveStackingConfigApi {
    crate::stacking_api::LiveStackingConfigApi {
        sigma_clip_enabled: config.sigma_clip_enabled,
        sigma_clip_threshold: config.sigma_clip_threshold,
        max_match_stars: config.max_match_stars,
        match_radius_px: config.match_radius_px,
        match_flux_tolerance: config.match_flux_tolerance,
        min_matched_pairs: config.min_matched_pairs,
        // OSC fields pass straight through. Validation of the string values
        // (sensor mode / Bayer pattern / demosaic quality) happens loudly inside
        // `LiveStackConfig::try_from`, so an invalid value surfaces as an error
        // to the caller rather than being silently normalised here.
        sensor_mode: config.sensor_mode,
        bayer_pattern: config.bayer_pattern,
        demosaic_quality: config.demosaic_quality,
    }
}

pub(crate) fn convert_stats(
    stats: crate::stacking_api::LiveStackingStatsApi,
) -> ApiLiveStackingStats {
    ApiLiveStackingStats {
        stacked_frame_count: stats.stacked_frame_count,
        total_frames_attempted: stats.total_frames_attempted,
        rejected_alignment_failures: stats.rejected_alignment_failures,
        avg_matched_pairs: stats.avg_matched_pairs,
        avg_alignment_residual: stats.avg_alignment_residual,
        total_sigma_rejected_pixels: stats.total_sigma_rejected_pixels,
    }
}

pub(crate) fn convert_result(
    result: crate::stacking_api::LiveStackingAddFrameResult,
) -> ApiLiveStackingResult {
    ApiLiveStackingResult {
        width: result.width,
        height: result.height,
        channels: result.channels,
        data: result.data,
        stats: convert_stats(result.stats),
    }
}

/// Start live stacking with a reference image file.
///
/// All subsequent frames will be aligned to this reference.
pub fn api_stacking_start(
    reference_image_path: String,
    config: ApiLiveStackingConfig,
) -> Result<ApiLiveStackingStats, NightshadeError> {
    let result = crate::stacking_api::stacking_start(reference_image_path, convert_config(config))
        .map_err(|e| NightshadeError::ImageError(e))?;
    Ok(convert_stats(result))
}

/// Start live stacking from raw pixel data in memory.
pub fn api_stacking_start_from_data(
    width: u32,
    height: u32,
    data: Vec<u16>,
    config: ApiLiveStackingConfig,
) -> Result<ApiLiveStackingStats, NightshadeError> {
    let result =
        crate::stacking_api::stacking_start_from_data(width, height, data, convert_config(config))
            .map_err(|e| NightshadeError::ImageError(e))?;
    Ok(convert_stats(result))
}

/// Add a frame to the live stack from a file path.
///
/// Returns the current stacked result.
pub fn api_stacking_add_frame(
    image_path: String,
) -> Result<ApiLiveStackingResult, NightshadeError> {
    let result = crate::stacking_api::stacking_add_frame(image_path)
        .map_err(|e| NightshadeError::ImageError(e))?;
    Ok(convert_result(result))
}

/// Add a frame to the live stack from raw pixel data.
pub fn api_stacking_add_frame_from_data(
    width: u32,
    height: u32,
    data: Vec<u16>,
) -> Result<ApiLiveStackingResult, NightshadeError> {
    let result = crate::stacking_api::stacking_add_frame_from_data(width, height, data)
        .map_err(|e| NightshadeError::ImageError(e))?;
    Ok(convert_result(result))
}

/// Get the current stacked result without adding a frame.
pub fn api_stacking_get_result() -> Result<ApiLiveStackingResult, NightshadeError> {
    let result =
        crate::stacking_api::stacking_get_result().map_err(|e| NightshadeError::ImageError(e))?;
    Ok(convert_result(result))
}

/// Get the current stacking statistics.
pub fn api_stacking_get_stats() -> Result<ApiLiveStackingStats, NightshadeError> {
    let result =
        crate::stacking_api::stacking_get_stats().map_err(|e| NightshadeError::ImageError(e))?;
    Ok(convert_stats(result))
}

/// Reset the live stacker, clearing accumulated data but keeping the reference.
pub fn api_stacking_reset() -> Result<(), NightshadeError> {
    crate::stacking_api::stacking_reset().map_err(|e| NightshadeError::ImageError(e))
}

/// Stop live stacking and release all resources.
pub fn api_stacking_stop() -> Result<(), NightshadeError> {
    crate::stacking_api::stacking_stop().map_err(|e| NightshadeError::ImageError(e))
}

/// Check if live stacking is currently active.
#[flutter_rust_bridge::frb(sync)]
pub fn api_stacking_is_active() -> bool {
    crate::stacking_api::stacking_is_active()
}

/// Get the current stacked frame count.
#[flutter_rust_bridge::frb(sync)]
pub fn api_stacking_frame_count() -> u32 {
    crate::stacking_api::stacking_frame_count()
}

// =============================================================================
// Defect-Map / Bad-Pixel Cosmetic Correction API
// =============================================================================

/// Status of a stored defect map for a given camera / sensor / temperature.
pub struct ApiDefectMapStatus {
    pub camera_id: String,
    pub width: u32,
    pub height: u32,
    pub temperature_bucket_decicelsius: i16,
    pub defective_pixel_count: u32,
    pub last_rebuilt_unix_seconds: i64,
    pub apply_during_capture: bool,
    pub stored_on_disk: bool,
}

pub(crate) fn defect_maps_root() -> std::path::PathBuf {
    // Why: NIGHTSHADE_DATA_DIR is the standard per-platform application
    // data path set by the Flutter shell on launch (see main_headless.dart
    // and the FFI bridge startup). The temp_dir fallback exists for unit
    // tests and for headless invocations where the env var hasn't been
    // populated yet — for those callers the defect maps are session-scoped
    // and don't need to survive a reboot. Production hosts hit the env-var
    // branch first.
    let base = std::env::var_os("NIGHTSHADE_DATA_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::env::temp_dir().join("nightshade"));
    base.join("defect_maps")
}

pub(crate) fn sanitize_camera_id(camera_id: &str) -> String {
    camera_id
        .chars()
        .map(|c| match c {
            'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' => c,
            _ => '_',
        })
        .collect()
}

pub(crate) fn defect_map_path(
    camera_id: &str,
    width: u32,
    height: u32,
    bucket_decicelsius: i16,
) -> std::path::PathBuf {
    defect_maps_root().join(format!(
        "{}_{}x{}_{:+05}.ndm",
        sanitize_camera_id(camera_id),
        width,
        height,
        bucket_decicelsius
    ))
}

/// Tracks whether the user has enabled per-capture defect correction for
/// each camera_id. The bool is the toggle state; the runtime cache of the
/// map itself is loaded on demand by the capture pipeline.
pub(crate) static DEFECT_APPLY_FLAGS: OnceLock<Mutex<HashMap<String, bool>>> = OnceLock::new();

pub(crate) fn defect_apply_flags() -> &'static Mutex<HashMap<String, bool>> {
    DEFECT_APPLY_FLAGS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Build a defect map for a camera from a set of dark frames provided as
/// FITS/XISF file paths. Frames must all share dimensions and pixel type.
///
/// The resulting map is written to disk under
/// `$NIGHTSHADE_DATA_DIR/defect_maps/` keyed by camera id, sensor size and
/// temperature bucket, and the status is returned.
pub async fn api_defect_map_build(
    camera_id: String,
    dark_frame_paths: Vec<String>,
    sensor_temperature_celsius: f64,
) -> Result<ApiDefectMapStatus, NightshadeError> {
    if camera_id.trim().is_empty() {
        return Err(NightshadeError::InvalidParameter(
            "camera_id is empty".to_string(),
        ));
    }
    if dark_frame_paths.len() < nightshade_imaging::defect_map::MIN_CONSISTENCY_FRAMES {
        return Err(NightshadeError::InvalidParameter(format!(
            "defect map build requires at least {} dark frames; got {}",
            nightshade_imaging::defect_map::MIN_CONSISTENCY_FRAMES,
            dark_frame_paths.len()
        )));
    }

    let darks: Vec<ImageData> = tokio::task::spawn_blocking(move || {
        let mut frames = Vec::with_capacity(dark_frame_paths.len());
        for path in &dark_frame_paths {
            let result = nightshade_imaging::read_image(std::path::Path::new(path))
                .map_err(|e| format!("failed to read {}: {}", path, e))?;
            frames.push(result.image);
        }
        Ok::<_, String>(frames)
    })
    .await
    .map_err(|e| NightshadeError::ImageError(format!("join error reading darks: {}", e)))?
    .map_err(NightshadeError::ImageError)?;

    let bucket = nightshade_imaging::defect_map::bucket_temperature(sensor_temperature_celsius);
    let dark_refs: Vec<&ImageData> = darks.iter().collect();
    let map = nightshade_imaging::defect_map::build_defect_map(&dark_refs, bucket)
        .map_err(|e| NightshadeError::ImageError(e.to_string()))?;

    let path = defect_map_path(&camera_id, map.width, map.height, bucket);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            NightshadeError::ImageError(format!(
                "failed to create defect map directory {}: {}",
                parent.display(),
                e
            ))
        })?;
    }
    map.write_to_file(&path)
        .map_err(|e| NightshadeError::ImageError(e.to_string()))?;

    let apply_during_capture = {
        // Why: absence of a flag for this camera id is the canonical "off"
        // state — apply-during-capture is opt-in and the map is only written
        // when the user toggles it on for a specific (camera, temperature)
        // pair. No need to surface this as an error.
        let flags = defect_apply_flags().lock().await;
        flags.get(&camera_id).copied().unwrap_or(false)
    };

    Ok(ApiDefectMapStatus {
        camera_id,
        width: map.width,
        height: map.height,
        temperature_bucket_decicelsius: bucket,
        defective_pixel_count: map.defective_count(),
        last_rebuilt_unix_seconds: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0),
        apply_during_capture,
        stored_on_disk: true,
    })
}

/// Toggle whether the defect map for this camera is applied to lights
/// during capture. The map must already exist on disk for the toggle to
/// take effect at the next capture; this call only updates the user's
/// preference.
pub async fn api_defect_map_apply(
    camera_id: String,
    apply_during_capture: bool,
) -> Result<(), NightshadeError> {
    if camera_id.trim().is_empty() {
        return Err(NightshadeError::InvalidParameter(
            "camera_id is empty".to_string(),
        ));
    }
    let mut flags = defect_apply_flags().lock().await;
    flags.insert(camera_id, apply_during_capture);
    Ok(())
}

/// Delete the defect map stored on disk for the given camera, sensor
/// dimensions and temperature bucket. Also resets the apply-during-
/// capture flag for that camera.
pub async fn api_defect_map_clear(
    camera_id: String,
    width: u32,
    height: u32,
    sensor_temperature_celsius: f64,
) -> Result<(), NightshadeError> {
    if camera_id.trim().is_empty() {
        return Err(NightshadeError::InvalidParameter(
            "camera_id is empty".to_string(),
        ));
    }
    let bucket = nightshade_imaging::defect_map::bucket_temperature(sensor_temperature_celsius);
    let path = defect_map_path(&camera_id, width, height, bucket);
    if path.exists() {
        std::fs::remove_file(&path).map_err(|e| {
            NightshadeError::ImageError(format!(
                "failed to delete defect map {}: {}",
                path.display(),
                e
            ))
        })?;
    }
    let mut flags = defect_apply_flags().lock().await;
    flags.remove(&camera_id);
    Ok(())
}

/// push the active defect-map application state to the
/// running sequencer.
///
/// When `enabled == true`, the bridge loads the `.ndm` file for
/// `(camera_id, width, height, sensor_temperature_celsius)` from disk
/// (returning an error if no map exists), wraps it in a
/// `DefectMapApplyState` along with the configured method + kernel +
/// save-original flag, and pushes the state via
/// `executor.update_defect_map(Some(state))`. When `enabled == false`,
/// `None` is pushed (the sequencer disables per-frame correction).
///
/// Method / kernel come from the user's settings (validated here so a
/// bad combination is rejected at the FFI boundary rather than at
/// per-frame application time).
pub async fn api_sequencer_apply_defect_map(
    camera_id: String,
    width: u32,
    height: u32,
    sensor_temperature_celsius: f64,
    enabled: bool,
    method: String,
    kernel_diameter: u8,
    save_original: bool,
) -> Result<(), NightshadeError> {
    if camera_id.trim().is_empty() {
        return Err(NightshadeError::InvalidParameter(
            "camera_id is empty".to_string(),
        ));
    }

    if !enabled {
        // Clear the live state. Also reset the apply flag so a future
        // `api_defect_map_get_status` call honestly reflects the off
        // state.
        {
            let mut flags = defect_apply_flags().lock().await;
            flags.insert(camera_id.clone(), false);
        }
        let mut executor = crate::api::sequencer::get_sequence_executor().write().await;
        executor.update_defect_map(None).await;
        tracing::info!(
            "Defect map application disabled for camera {} (no map pushed to sequencer)",
            camera_id
        );
        return Ok(());
    }

    let kernel = nightshade_imaging::defect_map::KernelSize::from_diameter(kernel_diameter)
        .ok_or_else(|| {
            NightshadeError::InvalidParameter(format!(
                "kernel_diameter must be 3, 5, or 7; got {}",
                kernel_diameter
            ))
        })?;
    let method_parsed = nightshade_imaging::defect_map::CorrectionMethod::from_wire(&method);

    let bucket = nightshade_imaging::defect_map::bucket_temperature(sensor_temperature_celsius);
    let path = defect_map_path(&camera_id, width, height, bucket);
    if !path.exists() {
        return Err(NightshadeError::InvalidParameter(format!(
            "No defect map stored for camera={} {}x{} at {} deci-celsius; \
             build one before enabling apply-during-capture.",
            camera_id, width, height, bucket,
        )));
    }
    let map = nightshade_imaging::defect_map::DefectMap::read_from_file(&path)
        .map_err(|e| NightshadeError::ImageError(e.to_string()))?;

    // Mirror the persisted apply flag so `get_status` round-trips the
    // user's preference correctly.
    {
        let mut flags = defect_apply_flags().lock().await;
        flags.insert(camera_id.clone(), true);
    }

    let state = nightshade_sequencer::DefectMapApplyState {
        camera_id: camera_id.clone(),
        map: std::sync::Arc::new(map),
        method: method_parsed,
        kernel,
        save_original,
    };

    let mut executor = crate::api::sequencer::get_sequence_executor().write().await;
    executor.update_defect_map(Some(state)).await;
    tracing::info!(
        "Defect map application enabled for camera {} ({}x{}, bucket={} dC) method={}, kernel={}, save_original={}",
        camera_id,
        width,
        height,
        bucket,
        method,
        kernel_diameter,
        save_original,
    );
    Ok(())
}

/// Look up the status of the stored defect map for a camera at the given
/// sensor size and temperature. Returns `Ok(None)` if no map is stored
/// for that combination.
pub async fn api_defect_map_get_status(
    camera_id: String,
    width: u32,
    height: u32,
    sensor_temperature_celsius: f64,
) -> Result<Option<ApiDefectMapStatus>, NightshadeError> {
    if camera_id.trim().is_empty() {
        return Err(NightshadeError::InvalidParameter(
            "camera_id is empty".to_string(),
        ));
    }
    let bucket = nightshade_imaging::defect_map::bucket_temperature(sensor_temperature_celsius);
    let path = defect_map_path(&camera_id, width, height, bucket);
    if !path.exists() {
        return Ok(None);
    }
    let map = nightshade_imaging::defect_map::DefectMap::read_from_file(&path)
        .map_err(|e| NightshadeError::ImageError(e.to_string()))?;
    let metadata = std::fs::metadata(&path).map_err(|e| {
        NightshadeError::ImageError(format!(
            "failed to stat defect map {}: {}",
            path.display(),
            e
        ))
    })?;
    let last_rebuilt = metadata
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let apply_during_capture = {
        // Why: absence of a flag for this camera id is the canonical "off"
        // state — apply-during-capture is opt-in and the map is only written
        // when the user toggles it on for a specific (camera, temperature)
        // pair. No need to surface this as an error.
        let flags = defect_apply_flags().lock().await;
        flags.get(&camera_id).copied().unwrap_or(false)
    };

    Ok(Some(ApiDefectMapStatus {
        camera_id,
        width: map.width,
        height: map.height,
        temperature_bucket_decicelsius: map.temperature_bucket_decicelsius,
        defective_pixel_count: map.defective_count(),
        last_rebuilt_unix_seconds: last_rebuilt,
        apply_during_capture,
        stored_on_disk: true,
    }))
}

#[cfg(test)]
mod unified_image_storage_tests {
    use super::{
        get_unified_image_storage, store_captured_image_atomically, CapturedImageResult,
        ImageStatsResult, RawImageInfo, UNIFIED_IMAGE_STORAGE_CAPACITY,
    };

    fn fixture_display() -> CapturedImageResult {
        CapturedImageResult {
            width: 1,
            height: 1,
            display_data: vec![0, 0, 0, 255],
            histogram: vec![0u32; 256],
            stats: ImageStatsResult {
                min: 0.0,
                max: 0.0,
                mean: 0.0,
                median: 0.0,
                std_dev: 0.0,
                hfr: None,
                eccentricity: None,
                fwhm: None,
                star_count: 0,
            },
            exposure_time: 0.1,
            timestamp: "test".to_string(),
            is_color: false,
        }
    }

    fn fixture_raw(marker: u16) -> RawImageInfo {
        RawImageInfo {
            width: 1,
            height: 1,
            data: vec![marker],
            sensor_type: Some("Monochrome".to_string()),
            bayer_offset: None,
        }
    }

    // Why a single test rather than two: `UNIFIED_IMAGE_STORAGE` is a
    // process-global `OnceLock`. Cargo runs tests in parallel threads inside
    // the same process, so two tests that both `clear()` and re-insert into
    // the same cache would race. We fold both assertions (LRU eviction order
    // and overwrite-doesn't-grow) into one test phased by `clear()` calls.
    #[tokio::test]
    async fn enforces_lru_cap_and_fifo_eviction() {
        // Phase 1: insert 60 entries — 10 over the capacity of 50 — and
        // verify the oldest 10 are evicted in FIFO order. Compile-time check
        // that the insert count is strictly greater than the capacity so the
        // FIFO assertions below are meaningful.
        const INSERT_COUNT: usize = 60;
        const _: () = assert!(
            INSERT_COUNT > UNIFIED_IMAGE_STORAGE_CAPACITY,
            "test only meaningful when insert count exceeds capacity",
        );

        {
            let mut storage = get_unified_image_storage().lock().await;
            storage.clear();
        }

        let key_for = |i: usize| format!("test-cq-w1-unified-img:{i:03}");

        for i in 0..INSERT_COUNT {
            store_captured_image_atomically(&key_for(i), fixture_display(), fixture_raw(i as u16))
                .await;
        }

        {
            let storage = get_unified_image_storage().lock().await;

            assert_eq!(
                storage.len(),
                UNIFIED_IMAGE_STORAGE_CAPACITY,
                "LRU should cap at {UNIFIED_IMAGE_STORAGE_CAPACITY} entries"
            );

            // First (INSERT_COUNT - CAPACITY) entries must have been evicted in
            // FIFO order; the remaining CAPACITY entries are the most-recent ones.
            let evicted_upper_bound = INSERT_COUNT - UNIFIED_IMAGE_STORAGE_CAPACITY;
            for i in 0..evicted_upper_bound {
                assert!(
                    !storage.contains(&key_for(i)),
                    "key {} should have been evicted (FIFO)",
                    key_for(i)
                );
            }
            for i in evicted_upper_bound..INSERT_COUNT {
                assert!(
                    storage.contains(&key_for(i)),
                    "key {} should still be present",
                    key_for(i)
                );
            }
        }

        // Phase 2: writing the same key multiple times must not grow the cache.
        {
            let mut storage = get_unified_image_storage().lock().await;
            storage.clear();
        }

        let key = "test-cq-w1-unified-img:overwrite";
        for marker in 0..5u16 {
            store_captured_image_atomically(key, fixture_display(), fixture_raw(marker)).await;
        }

        let mut storage = get_unified_image_storage().lock().await;
        assert_eq!(storage.len(), 1, "overwrites must not grow the cache");
        let entry = storage.get(key).expect("entry must be present");
        assert_eq!(
            entry.raw_info.data,
            vec![4u16],
            "last write must win for an existing key"
        );
    }
}

// ============================================================================
// Image Grading: round-trip test for the rich-header save path.
// ============================================================================

#[cfg(test)]
mod rich_header_tests {
    use super::{save_fits_file_rich, FitsWriteHeaderRich};
    use nightshade_imaging::read_fits;
    use nightshade_sequencer::scheduling::FrameContext;
    use nightshade_sequencer::MosaicPanelInfo;
    use std::path::{Path, PathBuf};

    /// A scratch directory that deletes itself when the test ends.
    /// `Drop` rather than the trailing `remove_file` calls these tests used to
    /// finish with: a trailing cleanup never runs while a panic unwinds, so a
    /// FAILING test used to leave its FITS behind — drop still runs.
    struct TempDir(PathBuf);

    impl std::ops::Deref for TempDir {
        type Target = Path;
        fn deref(&self) -> &Path {
            &self.0
        }
    }

    // Deref alone does not satisfy a generic `AsRef<Path>` bound, which several
    // call sites here rely on.
    impl AsRef<Path> for TempDir {
        fn as_ref(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            // Best-effort: a test asserting on a half-removed tree should fail
            // on its own assertion, not on cleanup.
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn temp_scratch_dir(tag: &str) -> TempDir {
        let p = std::env::temp_dir().join(format!(
            "ns_rich_{}_{}_{}",
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

    /// End-to-end: build a FrameContext with every meaningful field set,
    /// route it through `save_fits_file_rich`, then read the FITS back from
    /// disk and assert every keyword survived.
    ///
    /// This is the "production-finished" gate the audit asks for: open the
    /// file in a reader and see all the new keywords populated.
    #[tokio::test]
    async fn fits_round_trip_preserves_all_frame_context_keywords() {
        // 8x8 image with arbitrary pixel data so the FITS writer has
        // something to write. Pixel data is not what we're testing.
        let width = 8u32;
        let height = 8u32;
        let pixels = (0..(width * height) as u16).collect::<Vec<u16>>();

        let scratch = temp_scratch_dir("round_trip");
        let temp_path = scratch.join("frame.fits");

        // Build a FrameContext with every field set so we can
        // verify each one survives the round-trip.
        let mut ctx = FrameContext::new_light("session-uuid-abc", 2, 2, 60.0, 7);
        ctx.target_id = Some("tgt-42".to_string());
        ctx.target_name = Some("M31".to_string());
        ctx.target_ra_hours = Some(0.7123);
        ctx.target_dec_degrees = Some(41.269);
        ctx.filter_name = Some("Ha".to_string());
        ctx.filter_index = Some(5);
        ctx.gain = Some(100);
        ctx.offset = Some(50);
        ctx.total_planned_frames = Some(20);
        ctx.sensor_temp_c = Some(-10.5);
        ctx.set_temp_c = Some(-10.0);
        ctx.focuser_position = Some(25_400);
        ctx.focuser_temperature_c = Some(12.3);
        ctx.rotator_angle_deg = Some(123.7);
        ctx.guide_rms_arcsec = Some(0.78);
        ctx.plate_solve_ra_hours = Some(0.7124);
        ctx.plate_solve_dec_degrees = Some(41.2691);
        ctx.plate_solve_pixel_scale_arcsec = Some(1.42);
        ctx.plate_solve_rotation_deg = Some(-1.3);
        ctx.bayer_pattern = Some("RGGB".to_string());
        ctx.mosaic_panel = Some(MosaicPanelInfo {
            mosaic_name: "M31 Wide".to_string(),
            panel_index: 2,
            total_panels: 9,
            row: 1,
            column: 2,
        });
        ctx.observer_name = Some("Test Observer".to_string());
        ctx.site_latitude_deg = Some(40.7128);
        ctx.site_longitude_deg = Some(-74.0060);
        ctx.site_elevation_m = Some(50.0);
        ctx.camera_make = Some("ZWO".to_string());
        ctx.camera_model = Some("ASI2600MM Pro".to_string());
        ctx.telescope_name = Some("Askar 65PHQ".to_string());
        ctx.telescope_focal_length_mm = Some(416.0);
        ctx.telescope_aperture_mm = Some(65.0);
        ctx.camera_pixel_size_x_um = Some(3.76);
        ctx.camera_pixel_size_y_um = Some(3.76);

        let header = FitsWriteHeaderRich::from_frame_context(&ctx);

        save_fits_file_rich(
            temp_path.to_string_lossy().to_string(),
            width,
            height,
            pixels,
            header,
        )
        .await
        .expect("rich FITS save should succeed");

        let (_image, parsed) = read_fits(&temp_path).expect("FITS read-back should succeed");

        // Core observation metadata.
        assert_eq!(parsed.get_string("OBJECT"), Some("M31"));
        assert_eq!(parsed.get_string("FILTER"), Some("Ha"));
        assert_eq!(parsed.get_int("FILTPOS"), Some(5));
        assert_eq!(parsed.get_string("IMAGETYP"), Some("Light"));
        assert_eq!(parsed.get_float("EXPTIME"), Some(60.0));
        // Bayer pattern.
        assert_eq!(parsed.get_string("BAYERPAT"), Some("RGGB"));

        // Camera settings.
        assert_eq!(parsed.get_int("GAIN"), Some(100));
        assert_eq!(parsed.get_int("OFFSET"), Some(50));
        assert_eq!(parsed.get_int("XBINNING"), Some(2));
        assert_eq!(parsed.get_int("YBINNING"), Some(2));
        assert_eq!(parsed.get_float("SET-TEMP"), Some(-10.0));
        // CCD-TEMP set from ctx.sensor_temp_c.
        assert_eq!(parsed.get_float("CCD-TEMP"), Some(-10.5));

        // Telescope / equipment.
        assert_eq!(parsed.get_string("TELESCOP"), Some("Askar 65PHQ"));
        // INSTRUME is "<make> <model>" when both are present.
        assert_eq!(parsed.get_string("INSTRUME"), Some("ZWO ASI2600MM Pro"));
        assert_eq!(parsed.get_float("FOCALLEN"), Some(416.0));
        assert_eq!(parsed.get_float("APTDIA"), Some(65.0));
        // Pixel pitch, scaled by the binning this frame was taken at — FOCALLEN
        // without it is not enough for a stacker to derive the plate scale, and
        // these were hardcoded absent on every sequenced frame.
        let xpixsz = parsed.get_float("XPIXSZ").expect("XPIXSZ card");
        let ypixsz = parsed.get_float("YPIXSZ").expect("YPIXSZ card");
        assert!(
            (xpixsz - 7.52).abs() < 1e-6 && (ypixsz - 7.52).abs() < 1e-6,
            "a 3.76 um sensor binned 2x2 has 7.52 um effective pixels, \
             got {xpixsz} x {ypixsz}"
        );

        // Observer + site.
        assert_eq!(parsed.get_string("OBSERVER"), Some("Test Observer"));
        assert_eq!(parsed.get_float("SITELAT"), Some(40.7128));
        assert_eq!(parsed.get_float("SITELONG"), Some(-74.0060));
        assert_eq!(parsed.get_float("SITEELEV"), Some(50.0));

        // Target coordinates. `target_ra_hours` is hours; the numeric FITS
        // RA card is degrees, so the writer multiplies by 15.
        let ra_deg = parsed.get_float("RA").expect("RA card");
        assert!(
            (ra_deg - 0.7123 * 15.0).abs() < 1e-6,
            "RA must be written in degrees, got {ra_deg}"
        );
        assert_eq!(parsed.get_float("DEC"), Some(41.269));
        // Unambiguous sexagesimal pair (MaxIm / N.I.N.A. convention).
        assert_eq!(parsed.get_string("OBJCTRA"), Some("00 42 44.28"));
        assert_eq!(parsed.get_string("OBJCTDEC"), Some("+41 16 08.40"));

        // Live device telemetry — the audit's key complaint that these
        // weren't being written.
        assert_eq!(parsed.get_int("FOCUSPOS"), Some(25_400));
        assert_eq!(parsed.get_float("FOCTEMP"), Some(12.3));
        assert_eq!(parsed.get_float("ROTATPOS"), Some(123.7));
        assert_eq!(parsed.get_float("GUIDERMS"), Some(0.78));

        // Plate-solve results. FITS keywords are capped at 8 chars so we
        // use SOLVRA/SOLVDEC.
        assert_eq!(parsed.get_float("SOLVRA"), Some(0.7124));
        assert_eq!(parsed.get_float("SOLVDEC"), Some(41.2691));
        assert_eq!(parsed.get_float("PIXSCALE"), Some(1.42));
        assert_eq!(parsed.get_float("CROTA1"), Some(-1.3));
        assert_eq!(parsed.get_float("CROTA2"), Some(-1.3));

        // Nightshade-specific session / frame accounting.
        assert_eq!(parsed.get_string("NS-SESID"), Some("session-uuid-abc"));
        assert_eq!(parsed.get_int("NS-FIDX"), Some(7));
        assert_eq!(parsed.get_int("NS-NPLN"), Some(20));

        // Mosaic — the audit's most-specific complaint: mosaic_panel
        // existed in config but was never written to FITS headers.
        assert_eq!(parsed.get_int("MOSAIC"), Some(1));
        assert_eq!(parsed.get_string("NS-MOSNM"), Some("M31 Wide"));
        // PANELIDX is 1-based for human readability; NS-PIDX preserves
        // the 0-based form for re-import.
        assert_eq!(parsed.get_int("PANELIDX"), Some(3));
        assert_eq!(parsed.get_int("NS-PIDX"), Some(2));
        assert_eq!(parsed.get_int("PANELROW"), Some(1));
        assert_eq!(parsed.get_int("NS-PROW"), Some(1));
        assert_eq!(parsed.get_int("PANELCOL"), Some(2));
        assert_eq!(parsed.get_int("NS-PCOL"), Some(2));
        assert_eq!(parsed.get_int("NS-NPAN"), Some(9));
    }

    /// A monochrome capture should NOT emit a BAYERPAT keyword (writing
    /// one would tell PixInsight to debayer the mono frame as if it were
    /// OSC, producing colour artefacts on what is just a luminance frame).
    #[tokio::test]
    async fn monochrome_capture_omits_bayer_pattern() {
        let width = 4u32;
        let height = 4u32;
        let pixels = vec![0u16; (width * height) as usize];

        let scratch = temp_scratch_dir("mono");
        let temp_path = scratch.join("frame.fits");

        let mut ctx = FrameContext::new_light("s", 1, 1, 30.0, 1);
        ctx.target_name = Some("FocusTest".to_string());
        // bayer_pattern is None — mono camera.
        let header = FitsWriteHeaderRich::from_frame_context(&ctx);
        save_fits_file_rich(
            temp_path.to_string_lossy().to_string(),
            width,
            height,
            pixels,
            header,
        )
        .await
        .expect("mono FITS save should succeed");

        let (_image, parsed) = read_fits(&temp_path).expect("FITS read-back");
        assert_eq!(
            parsed.get_string("BAYERPAT"),
            None,
            "monochrome captures must NOT emit BAYERPAT"
        );
    }

    /// Absent optional fields must be omitted, not stamped with sentinel
    /// values. This is the audit's silent-fallback rule applied to FITS
    /// writing: writing CCD-TEMP=-273.15 for "no temperature" lies to
    /// downstream tools.
    #[tokio::test]
    async fn missing_optional_fields_are_omitted_not_zeroed() {
        let width = 4u32;
        let height = 4u32;
        let pixels = vec![0u16; (width * height) as usize];

        let scratch = temp_scratch_dir("omit");
        let temp_path = scratch.join("frame.fits");

        let ctx = FrameContext::new_light("sess", 1, 1, 10.0, 1);
        // Nothing else set — every optional field stays None.
        let header = FitsWriteHeaderRich::from_frame_context(&ctx);
        save_fits_file_rich(
            temp_path.to_string_lossy().to_string(),
            width,
            height,
            pixels,
            header,
        )
        .await
        .expect("FITS save should succeed");

        let (_image, parsed) = read_fits(&temp_path).expect("FITS read-back");
        // Every optional keyword must be absent.
        for absent_key in &[
            "OBJECT", "FILTER", "FILTPOS", "GAIN", "OFFSET", "CCD-TEMP", "SET-TEMP", "FOCUSPOS",
            "ROTATPOS", "GUIDERMS", "SOLVRA", "SOLVDEC", "PIXSCALE", "CROTA1", "BAYERPAT",
            "MOSAIC", "PANELIDX", "NS-MOSNM", "OBSERVER", "SITELAT", "TELESCOP", "INSTRUME",
            "FOCALLEN", "APTDIA",
        ] {
            let s = parsed.get_string(absent_key);
            let i = parsed.get_int(absent_key);
            let f = parsed.get_float(absent_key);
            assert!(
                s.is_none() && i.is_none() && f.is_none(),
                "{} should be absent for an unset FrameContext field (got string={:?} int={:?} float={:?})",
                absent_key,
                s,
                i,
                f
            );
        }

        // SESSIONID is also omitted when session_id is the empty string
        // (the rich-header builder maps empty -> None).
        let mut empty_ctx = FrameContext::new_light("", 1, 1, 10.0, 1);
        empty_ctx.session_id = String::new();
        let header_empty = FitsWriteHeaderRich::from_frame_context(&empty_ctx);
        assert!(
            header_empty.session_id.is_none(),
            "empty session_id should be normalised to None"
        );
    }

    /// Regression: a below-horizon altitude used to abort the whole FITS
    /// write via `?` on `calculate_airmass`, so the thumbnail landed on
    /// disk and the science frame did not. Darks and flats are taken
    /// parked/capped (Alt < 0) by definition, so this destroyed entire
    /// calibration runs. AIRMASS is optional: omit it, keep the frame.
    #[tokio::test]
    async fn below_horizon_altitude_still_writes_the_frame() {
        let width = 4u32;
        let height = 4u32;
        let pixels = vec![7u16; (width * height) as usize];

        let scratch = temp_scratch_dir("below_horizon");
        let temp_path = scratch.join("parked.fits");

        let ctx = FrameContext::new_light("sess", 1, 1, 3.0, 1);
        let mut header = FitsWriteHeaderRich::from_frame_context(&ctx);
        // Mount parked: the exact altitude the sim mount reports.
        header.altitude = Some(-9.9);

        save_fits_file_rich(
            temp_path.to_string_lossy().to_string(),
            width,
            height,
            pixels,
            header,
        )
        .await
        .expect("a parked mount must not stop the frame from being saved");

        assert!(
            temp_path.exists(),
            "FITS file must exist on disk for a below-horizon capture"
        );
        let (_image, parsed) = read_fits(&temp_path).expect("FITS read-back");
        assert_eq!(
            parsed.get_float("AIRMASS"),
            None,
            "AIRMASS must be omitted (not faked) when it cannot be computed"
        );
        // The altitude is a measurement, not a model output: the mount really
        // was at -9.9°, and a dark that records where the scope was parked is
        // more useful than one that records nothing. Only the derived quantity
        // is undefined down there.
        let recorded = parsed
            .get_float("OBJCTALT")
            .expect("OBJCTALT records the altitude even below the horizon");
        assert!(
            (recorded - (-9.9)).abs() < 0.01,
            "OBJCTALT should be -9.9, got {recorded}"
        );
    }

    /// Above the horizon the AIRMASS card is still written, so omission is
    /// genuinely conditional rather than a blanket removal.
    #[tokio::test]
    async fn above_horizon_altitude_writes_airmass() {
        let width = 4u32;
        let height = 4u32;
        let pixels = vec![1u16; (width * height) as usize];

        let scratch = temp_scratch_dir("above_horizon");
        let temp_path = scratch.join("high.fits");

        let ctx = FrameContext::new_light("sess", 1, 1, 3.0, 1);
        let mut header = FitsWriteHeaderRich::from_frame_context(&ctx);
        header.altitude = Some(78.98);

        save_fits_file_rich(
            temp_path.to_string_lossy().to_string(),
            width,
            height,
            pixels,
            header,
        )
        .await
        .expect("FITS save should succeed");

        let (_image, parsed) = read_fits(&temp_path).expect("FITS read-back");
        let airmass = parsed.get_float("AIRMASS").expect("AIRMASS card");
        assert!(
            (airmass - 1.0185).abs() < 0.001,
            "AIRMASS at Alt 78.98° should be ~1.0185, got {airmass}"
        );
    }

    /// A sequenced frame has to record where in the sky it was taken, not just
    /// where the mount was pointed.
    ///
    /// This drives the production line: a `FrameContext` carrying exactly the
    /// telemetry the sequencer stamps onto one (`instructions.rs` reads the
    /// mount's coordinates and derives alt/az from the site in the same
    /// breath), through the real `from_frame_context` and the real writer, and
    /// reads the cards back off disk. `from_frame_context` used to hardcode
    /// `altitude: None`, so every frame the sequencer wrote through
    /// `real_device_ops` or `unified_device_ops` lost both keywords —
    /// extinction correction has nothing to work from, and the altitude cannot
    /// be reconstructed later because the file does not say when, where, or at
    /// what it was pointed all at once.
    #[tokio::test]
    async fn sequenced_frame_records_where_in_the_sky_it_was_taken() {
        let width = 4u32;
        let height = 4u32;
        let pixels = vec![3u16; (width * height) as usize];

        let scratch = temp_scratch_dir("horizon_coords");
        let temp_path = scratch.join("sequenced.fits");

        let mut ctx = FrameContext::new_light("sess", 1, 1, 120.0, 1);
        // Where the sequence MEANT to be...
        ctx.target_ra_hours = Some(5.5);
        ctx.target_dec_degrees = Some(-5.4);
        // ...and where the mount actually was when the shutter opened, with
        // the altitude the sequencer derived from that pointing and the site.
        ctx.mount_ra_hours = Some(5.4917);
        ctx.mount_dec_degrees = Some(-5.39);
        ctx.mount_altitude_deg = Some(30.0);

        let header = FitsWriteHeaderRich::from_frame_context(&ctx);
        save_fits_file_rich(
            temp_path.to_string_lossy().to_string(),
            width,
            height,
            pixels,
            header,
        )
        .await
        .expect("FITS save should succeed");

        let (_image, parsed) = read_fits(&temp_path).expect("FITS read-back");

        let recorded_alt = parsed
            .get_float("OBJCTALT")
            .expect("a sequenced frame must record the altitude it was taken at");
        assert!(
            (recorded_alt - 30.0).abs() < 0.01,
            "OBJCTALT should be the mount's 30.0°, got {recorded_alt}"
        );

        // Physics, not a re-run of the formula: at 30° altitude the zenith
        // angle is 60°, so the plane-parallel path is sec 60° = 2.0 exactly.
        // A real (curved, refracting) atmosphere is always a slightly SHORTER
        // path than that, by a few tenths of a percent at this altitude.
        let airmass = parsed
            .get_float("AIRMASS")
            .expect("AIRMASS follows from a recorded altitude");
        let plane_parallel = 1.0 / (60.0_f64).to_radians().cos();
        assert!(
            airmass < plane_parallel,
            "AIRMASS {airmass} at 30° altitude is not below the plane-parallel \
             ceiling {plane_parallel}"
        );
        assert!(
            plane_parallel - airmass < 0.02,
            "AIRMASS {airmass} at 30° altitude is {:.4} below sec z — far more \
             curvature than a real atmosphere has",
            plane_parallel - airmass
        );

        // The pointing cards describe the same instant as the altitude: the
        // mount's coordinates, not the target's nominal ones. RA leaves in
        // degrees.
        let ra_deg = parsed.get_float("RA").expect("RA card");
        assert!(
            (ra_deg - 5.4917 * 15.0).abs() < 1e-6,
            "RA should be the mount's 5.4917h in degrees, got {ra_deg}"
        );
        let dec_deg = parsed.get_float("DEC").expect("DEC card");
        assert!(
            (dec_deg - (-5.39)).abs() < 1e-6,
            "DEC should be the mount's -5.39°, got {dec_deg}"
        );
    }

    /// Hardie (1962), for cross-checking the AIRMASS card against a formula
    /// this codebase does not implement. A polynomial in sec z, from different
    /// data and a different era than either Pickering or Young, and the
    /// reduction every photoelectric photometry paper used for three decades:
    ///
    ///   X = sec z − 0.0018167(sec z − 1) − 0.002875(sec z − 1)²
    ///              − 0.0008083(sec z − 1)³
    ///
    /// Hardie, R. H. 1962. "Photoelectric Reductions", in *Astronomical
    /// Techniques*, ed. W. A. Hiltner (University of Chicago Press), p. 180.
    /// Stated valid to z ≈ 80° (h ≥ 10°); it diverges rapidly below that.
    fn hardie_1962_airmass(altitude_degrees: f64) -> f64 {
        let sec_z = 1.0 / (90.0 - altitude_degrees).to_radians().cos();
        let d = sec_z - 1.0;
        sec_z - 0.0018167 * d - 0.002875 * d * d - 0.0008083 * d * d * d
    }

    /// Pin the AIRMASS card against a published formula rather than against
    /// itself.
    ///
    /// This value goes into files users publish and hand to other people's
    /// reduction pipelines, so the thing worth asserting is not "Pickering was
    /// transcribed correctly" — a typo'd Pickering is still self-consistent —
    /// but "an outside reducer computing airmass their own way gets our
    /// number". Hardie is that outside reducer: a different functional form
    /// fitted to different data, agreeing here to better than 0.02 airmass
    /// (0.005 mag at a typical k = 0.25) across its whole validity range.
    ///
    /// This is the shape of check that catches a formula that has quietly
    /// stopped being the one it is named after — like the copy in the
    /// sequencer's photometry gate that added Pickering's refraction term to
    /// sin(h) instead of to h, and was wrong by a factor of nearly three at
    /// 10° altitude while still looking like Pickering's formula on the page.
    #[test]
    fn airmass_agrees_with_hardie_1962_over_its_published_range() {
        let mut worst = (0.0_f64, 0.0_f64);
        let mut h = 10.0_f64;
        while h <= 90.0 {
            let ours = nightshade_imaging::calculate_airmass(h).expect("above the horizon");
            let delta = (ours - hardie_1962_airmass(h)).abs();
            if delta > worst.1 {
                worst = (h, delta);
            }
            h += 0.25;
        }
        assert!(
            worst.1 < 0.02,
            "AIRMASS disagrees with Hardie 1962 by {:.4} airmass at h={:.2}° \
             (ours {:.5}, Hardie {:.5}); the card no longer means what an \
             outside photometry reduction will assume it means",
            worst.1,
            worst.0,
            nightshade_imaging::calculate_airmass(worst.0).unwrap(),
            hardie_1962_airmass(worst.0),
        );
    }

    /// The properties any airmass must have, over the whole sky, independent
    /// of which formula produced it:
    ///
    ///   * ≥ 1 — the zenith is the shortest path through the atmosphere, so
    ///     nothing can be shorter.
    ///   * strictly increasing toward the horizon — a lower target looks
    ///     through more air, always.
    ///   * ≤ sec z — a curved atmosphere is a shorter path than the flat one
    ///     the plane-parallel approximation assumes, so sec z is a hard
    ///     ceiling.
    ///
    /// The hand-rolled copy this consolidation deleted from the photometry
    /// gate violated the first two: it peaked at 2.02 near 10° altitude, then
    /// *decreased* toward the horizon, and reported 0.86 at 1°. Nothing
    /// checked shape, so it survived for as long as it existed.
    #[test]
    fn airmass_is_physical_over_the_whole_sky() {
        let mut previous: Option<(f64, f64)> = None;
        let mut h = 0.0_f64;
        while h <= 89.75 {
            let x = nightshade_imaging::calculate_airmass(h).expect("h >= 0 is above the horizon");
            assert!(
                x >= 1.0,
                "airmass {x} at h={h}° is below 1.0 — shorter than the zenith path"
            );
            let sec_z = 1.0 / (90.0 - h).to_radians().cos();
            assert!(
                x <= sec_z,
                "airmass {x} at h={h}° exceeds the plane-parallel ceiling sec z = {sec_z}"
            );
            if let Some((prev_h, prev_x)) = previous {
                assert!(
                    x < prev_x,
                    "airmass rose with altitude: {prev_x} at {prev_h}° -> {x} at {h}°"
                );
            }
            previous = Some((h, x));
            h += 0.25;
        }
    }

    /// Bound the one place the implementation is not continuous.
    ///
    /// `calculate_airmass` hands over from Young 1994 to Pickering 2002 at
    /// exactly 10° altitude, and the two disagree there, so airmass takes a
    /// small step UP as altitude increases across the seam — a local violation
    /// of the monotonicity the sweep above checks, invisible at that sweep's
    /// 0.25° resolution because the real gradient (0.13/0.25°) is four times
    /// larger than the step.
    ///
    /// It is left in place rather than smoothed away: 0.035 airmass is 0.009
    /// mag at a typical k = 0.25, at an altitude no photometry gate admits
    /// (the default cut-off is 2.5 airmass, ~24°), and the alternative is
    /// changing the AIRMASS of every frame the app has ever written. What is
    /// not acceptable is for it to grow silently, so it is measured here.
    #[test]
    fn young_to_pickering_handover_step_stays_small() {
        let below = nightshade_imaging::calculate_airmass(9.9999).expect("above the horizon");
        let at = nightshade_imaging::calculate_airmass(10.0).expect("above the horizon");
        let step = at - below;
        assert!(
            (0.0..0.05).contains(&step),
            "the Young/Pickering handover at 10° now steps by {step:.4} airmass \
             ({below} just below, {at} at the seam)"
        );
    }

    /// The AIRMASS a frame records and the airmass the scheduler used to pick
    /// its target must be one number.
    ///
    /// Read off disk on one side, called live on the other — so this fails if
    /// either the writer or `scheduling::astronomy` grows its own formula
    /// again. They previously disagreed below 10° altitude, where the writer
    /// switches to Young 1994 and the scheduler's private copy did not: 31.7
    /// against 38.7 at the horizon, either of which could end up in a file
    /// somebody publishes.
    #[tokio::test]
    async fn airmass_card_agrees_with_the_scheduler_that_chose_the_target() {
        let width = 2u32;
        let height = 2u32;
        let scratch = temp_scratch_dir("airmass_parity");

        for altitude in [80.0_f64, 45.0, 24.0, 12.0, 6.0, 1.0] {
            let temp_path = scratch.join(format!("alt_{altitude}.fits"));
            let ctx = FrameContext::new_light("sess", 1, 1, 5.0, 1);
            let mut header = FitsWriteHeaderRich::from_frame_context(&ctx);
            header.altitude = Some(altitude);

            save_fits_file_rich(
                temp_path.to_string_lossy().to_string(),
                width,
                height,
                vec![0u16; (width * height) as usize],
                header,
            )
            .await
            .expect("FITS save should succeed");

            let (_image, parsed) = read_fits(&temp_path).expect("FITS read-back");
            let written = parsed.get_float("AIRMASS").expect("AIRMASS card");
            let scheduled = nightshade_sequencer::scheduling::airmass(altitude);
            assert!(
                (written - scheduled).abs() < 1e-9,
                "at {altitude}° the file records airmass {written} but the scheduler \
                 scored the target at {scheduled}"
            );
        }
    }

    /// Unit pin: RA is carried internally in hours but the numeric FITS RA
    /// card is degrees. Without this conversion every frame pointed
    /// PixInsight / Siril / ASTAP / astrometry.net 15x off in RA.
    #[tokio::test]
    async fn ra_is_written_in_degrees_not_hours() {
        let width = 4u32;
        let height = 4u32;
        let pixels = vec![0u16; (width * height) as usize];

        let scratch = temp_scratch_dir("ra_units");
        let temp_path = scratch.join("pointing.fits");

        let mut ctx = FrameContext::new_light("sess", 1, 1, 3.0, 1);
        // The exact pointing from the audit repro: 08h00m / +40°.
        ctx.target_ra_hours = Some(8.0);
        ctx.target_dec_degrees = Some(40.0);
        let header = FitsWriteHeaderRich::from_frame_context(&ctx);

        save_fits_file_rich(
            temp_path.to_string_lossy().to_string(),
            width,
            height,
            pixels,
            header,
        )
        .await
        .expect("FITS save should succeed");

        let (_image, parsed) = read_fits(&temp_path).expect("FITS read-back");
        assert_eq!(
            parsed.get_float("RA"),
            Some(120.0),
            "RA(deg) must equal 15 x mount hours"
        );
        assert_eq!(parsed.get_float("DEC"), Some(40.0));
        assert_eq!(parsed.get_string("OBJCTRA"), Some("08 00 00.00"));
        assert_eq!(parsed.get_string("OBJCTDEC"), Some("+40 00 00.00"));
    }

    /// Negative declinations must keep their sign in the sexagesimal card.
    #[test]
    fn sexagesimal_formatting_handles_sign_and_rounding() {
        assert_eq!(super::format_sexagesimal(8.0, false), "08 00 00.00");
        assert_eq!(super::format_sexagesimal(40.0, true), "+40 00 00.00");
        assert_eq!(
            super::format_sexagesimal(-5.5083333333, true),
            "-05 30 30.00"
        );
        // 7.99999999 h must not render as 07 59 60.00.
        assert_eq!(
            super::format_sexagesimal(7.999_999_99, false),
            "08 00 00.00"
        );
    }
}

// =============================================================================
// Master calibration frame combination (IMG-)
// =============================================================================
//
// Why this lives here: master-frame combine is a sibling of the existing
// `api_calibrate_image_*` and `api_defect_map_build` entry points — both
// operate on a list of FITS/XISF inputs and write a single calibration
// product to disk. Dart-side `dark_library_service.dart::_medianCombine`
// is the legacy isolate path we are superseding; new code (and the OTA
// flat / bias library that will follow) calls these instead.

/// Combine method exposed across the FFI surface.
///
/// Dart sends a tag string ("MEAN", "MEDIAN", "SIGMA_CLIP") with optional
/// sigma parameters. We deliberately use a flat struct rather than a
/// tagged enum here because flutter_rust_bridge handles plain structs
/// with optional fields cleanly across both Dart isolates and the new
/// codec path.
pub struct ApiCombineMethod {
    /// "MEAN" | "MEDIAN" | "SIGMA_CLIP" (case-insensitive)
    pub method: String,
    /// Kappa threshold for sigma clip; required for SIGMA_CLIP, ignored otherwise.
    pub sigma_kappa: Option<f64>,
    /// Number of clip iterations; required for SIGMA_CLIP, ignored otherwise.
    pub sigma_iterations: Option<u32>,
}

/// Result returned from a master-frame build.
pub struct ApiMasterFrameResult {
    /// Where the master FITS was written.
    pub output_path: String,
    /// "BIAS" | "DARK" | "FLAT"
    pub kind: String,
    /// "U16" | "F32"
    pub output_type: String,
    /// How many input frames contributed.
    pub frame_count: u32,
    /// String rendering of the combine method actually used.
    pub method: String,
    /// Width of the resulting master in pixels.
    pub width: u32,
    /// Height of the resulting master in pixels.
    pub height: u32,
    /// Channel count of the resulting master.
    pub channels: u32,
    /// Pre-normalisation mean of the combined master.
    pub input_mean: f64,
    /// Post-normalisation mean (equals `input_mean` for bias/dark, 1.0 / 32768 for flat).
    pub output_mean: f64,
}

fn parse_master_kind(
    s: &str,
) -> Result<nightshade_imaging::stacking::MasterFrameKind, NightshadeError> {
    match s.trim().to_ascii_uppercase().as_str() {
        "BIAS" => Ok(nightshade_imaging::stacking::MasterFrameKind::Bias),
        "DARK" => Ok(nightshade_imaging::stacking::MasterFrameKind::Dark),
        "FLAT" => Ok(nightshade_imaging::stacking::MasterFrameKind::Flat),
        other => Err(NightshadeError::InvalidParameter(format!(
            "unknown master frame kind '{}': expected BIAS, DARK, or FLAT",
            other
        ))),
    }
}

fn parse_output_type(
    s: &str,
) -> Result<nightshade_imaging::stacking::MasterOutputType, NightshadeError> {
    match s.trim().to_ascii_uppercase().as_str() {
        "U16" => Ok(nightshade_imaging::stacking::MasterOutputType::U16),
        "F32" => Ok(nightshade_imaging::stacking::MasterOutputType::F32),
        other => Err(NightshadeError::InvalidParameter(format!(
            "unknown master output type '{}': expected U16 or F32",
            other
        ))),
    }
}

fn parse_combine_method(
    m: &ApiCombineMethod,
) -> Result<nightshade_imaging::stacking::CombineMethod, NightshadeError> {
    use nightshade_imaging::stacking::CombineMethod;
    match m.method.trim().to_ascii_uppercase().as_str() {
        "MEAN" => Ok(CombineMethod::Mean),
        "MEDIAN" => Ok(CombineMethod::Median),
        "SIGMA_CLIP" | "SIGMACLIP" => {
            let kappa = m.sigma_kappa.ok_or_else(|| {
                NightshadeError::InvalidParameter("SIGMA_CLIP requires sigma_kappa".to_string())
            })?;
            let iterations = m.sigma_iterations.ok_or_else(|| {
                NightshadeError::InvalidParameter(
                    "SIGMA_CLIP requires sigma_iterations".to_string(),
                )
            })?;
            Ok(CombineMethod::SigmaClip { kappa, iterations })
        }
        other => Err(NightshadeError::InvalidParameter(format!(
            "unknown combine method '{}': expected MEAN, MEDIAN, or SIGMA_CLIP",
            other
        ))),
    }
}

/// Combine a set of calibration frames into a single master and write it
/// to disk as FITS.
///
/// Inputs:
/// - `input_paths`: paths to each constituent calibration frame. All must
///   exist, share dimensions/channels/pixel type, and be readable by the
///   normal Nightshade image reader (FITS/XISF/PNG/TIFF/etc).
/// - `kind`: "BIAS" | "DARK" | "FLAT" — controls normalisation (flats only).
/// - `method`: combine algorithm + parameters; see `ApiCombineMethod`.
/// - `output_type`: "U16" | "F32" — pixel type of the produced master.
/// - `output_path`: where to write the FITS master.
///
/// Errors:
/// - Empty input list, mismatched dimensions/channels/pixel types, or any
///   read failure surfaces as `NightshadeError::ImageError`/`InvalidParameter`.
///   No silent fallback to a partial result.
pub async fn api_combine_master_frames(
    input_paths: Vec<String>,
    kind: String,
    method: ApiCombineMethod,
    output_type: String,
    output_path: String,
) -> Result<ApiMasterFrameResult, NightshadeError> {
    if input_paths.is_empty() {
        return Err(NightshadeError::InvalidParameter(
            "api_combine_master_frames: input_paths is empty".to_string(),
        ));
    }
    if output_path.trim().is_empty() {
        return Err(NightshadeError::InvalidParameter(
            "api_combine_master_frames: output_path is empty".to_string(),
        ));
    }

    let kind_enum = parse_master_kind(&kind)?;
    let method_enum = parse_combine_method(&method)?;
    let output_type_enum = parse_output_type(&output_type)?;

    // Frame I/O and the combine itself run on a blocking pool — they are
    // CPU-bound and allocate proportional to (frames * pixels), so we keep
    // them off the tokio worker threads. Mirrors `api_defect_map_build`.
    let paths_clone = input_paths.clone();
    let frames: Vec<ImageData> = tokio::task::spawn_blocking(move || {
        let mut out = Vec::with_capacity(paths_clone.len());
        for path in &paths_clone {
            let result = nightshade_imaging::read_image(std::path::Path::new(path))
                .map_err(|e| format!("failed to read {}: {}", path, e))?;
            out.push(result.image);
        }
        Ok::<_, String>(out)
    })
    .await
    .map_err(|e| {
        NightshadeError::ImageError(format!("join error reading master frame inputs: {}", e))
    })?
    .map_err(NightshadeError::ImageError)?;

    let combine_kind = kind_enum;
    let combine_method = method_enum;
    let combine_output_type = output_type_enum;
    let master = tokio::task::spawn_blocking(move || {
        nightshade_imaging::stacking::combine_master_frames(
            &frames,
            combine_kind,
            combine_method,
            combine_output_type,
        )
    })
    .await
    .map_err(|e| NightshadeError::ImageError(format!("join error combining frames: {}", e)))?
    .map_err(NightshadeError::ImageError)?;

    // Write the master as FITS with rich provenance so downstream tooling
    // (and humans inspecting the file) know exactly how it was produced.
    let out_path = std::path::PathBuf::from(&output_path);
    if let Some(parent) = out_path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent).map_err(|e| {
                NightshadeError::ImageError(format!(
                    "failed to create output directory {}: {}",
                    parent.display(),
                    e
                ))
            })?;
        }
    }

    let mut header = FitsHeader::new();
    let kind_str = master.kind.as_str();
    header.set_string("IMAGETYP", kind_str);
    header.set_string("FRAMETYP", "MASTER");
    header.set_string("CALSTAT", &format!("Nightshade master {}", kind_str));
    header.set_int("NFRAMES", master.frame_count as i64);
    header.set_string("COMBMETH", &master.method.as_str());
    header.set_string(
        "MASTRTYP",
        match master.output_type {
            nightshade_imaging::stacking::MasterOutputType::U16 => "U16",
            nightshade_imaging::stacking::MasterOutputType::F32 => "F32",
        },
    );
    // FITS keywords are capped at 8 chars (see `fits::is_valid_keyword`).
    header.set_float("INMEAN", master.input_mean);
    header.set_float("OUTMEAN", master.output_mean);

    let master_image_for_write = master.image.clone();
    let out_path_for_write = out_path.clone();
    tokio::task::spawn_blocking(move || {
        write_fits(&out_path_for_write, &master_image_for_write, &header).map_err(|e| {
            format!(
                "failed to write master FITS {}: {:?}",
                out_path_for_write.display(),
                e
            )
        })
    })
    .await
    .map_err(|e| NightshadeError::ImageError(format!("join error writing master: {}", e)))?
    .map_err(NightshadeError::ImageError)?;

    tracing::info!(
        "Wrote master {} ({} frames, {}) to {}",
        kind_str,
        master.frame_count,
        master.method.as_str(),
        output_path
    );

    Ok(ApiMasterFrameResult {
        output_path,
        kind: kind_str.to_string(),
        output_type: match master.output_type {
            nightshade_imaging::stacking::MasterOutputType::U16 => "U16".to_string(),
            nightshade_imaging::stacking::MasterOutputType::F32 => "F32".to_string(),
        },
        frame_count: master.frame_count,
        method: master.method.as_str(),
        width: master.image.width,
        height: master.image.height,
        channels: master.image.channels,
        input_mean: master.input_mean,
        output_mean: master.output_mean,
    })
}

// ============================================================================
// FITS keyword update round-trip test
// ============================================================================

#[cfg(test)]
mod exposure_failure_classification_tests {
    use super::classify_exposure_failure;
    use crate::error::NightshadeError;
    use crate::unified_device_ops::IMAGE_VALIDATION_FAILED_PREFIX;

    /// Verbatim message observed from a real ZWO ASI1600MM-Cool exposed in
    /// daylight; it used to surface as HTTP 500 `internal_error`.
    const SATURATED: &str = "Image is completely saturated (min value 65224 >= 65024) - significantly reduce exposure time or gain";

    #[test]
    fn validation_rejection_becomes_exposure_failed() {
        let err = classify_exposure_failure(
            "native:zwo:0",
            format!("{IMAGE_VALIDATION_FAILED_PREFIX}{SATURATED}"),
        );

        match err {
            NightshadeError::ExposureFailed { camera_id, reason } => {
                assert_eq!(camera_id, "native:zwo:0");
                // The actionable reason must survive intact — it is what the
                // operator reads to know what to change.
                assert_eq!(reason, SATURATED);
            }
            other => panic!("expected ExposureFailed, got {other:?}"),
        }
    }

    #[test]
    fn driver_faults_stay_operation_failed() {
        // Anything that is not a validation rejection must keep mapping to
        // OperationFailed so real faults still answer HTTP 500.
        for raw in [
            "SDK error: Failed to call method StartExposure",
            "Device not connected: native:zwo:0",
            "Exposure cancelled",
            // Near-miss: the marker must be a prefix, not a substring.
            "wrapped: Image validation failed: something",
        ] {
            match classify_exposure_failure("native:zwo:0", raw.to_string()) {
                NightshadeError::OperationFailed(msg) => assert_eq!(msg, raw),
                other => panic!("expected OperationFailed for {raw:?}, got {other:?}"),
            }
        }
    }

    /// DATE-OBS must be when the shutter OPENED.
    ///
    /// It was sampled with `Utc::now()` while building the header, which runs
    /// after readout, so every sequenced frame recorded a DATE-OBS late by
    /// exactly its own EXPTIME -- measured live as a 30 s exposure starting
    /// 14:04:37 and claiming 14:05:09. Photometry, occultation timing and
    /// astrometry all read DATE-OBS as the start, so this silently shifted
    /// every measurement by half to one exposure length.
    #[test]
    fn date_obs_is_the_exposure_start_not_the_readout_time() {
        use chrono::TimeZone;

        let started = chrono::Utc
            .with_ymd_and_hms(2026, 8, 1, 14, 4, 37)
            .single()
            .expect("valid instant");

        let mut ctx = nightshade_sequencer::scheduling::FrameContext::new_light(
            "session".to_string(),
            1,
            1,
            30.0,
            1,
        );
        ctx.exposure_started_at = Some(started);

        let header = crate::FitsWriteHeaderRich::from_frame_context(&ctx);

        assert_eq!(
            header.capture_timestamp, "2026-08-01T14:04:37",
            "DATE-OBS must be the start of the exposure"
        );
        assert!(
            !header.capture_timestamp.starts_with("2026-08-01T14:05"),
            "DATE-OBS must not be the readout time (start + EXPTIME)"
        );
    }

    /// A frame whose start time was never recorded must not silently claim the
    /// current clock as its observation time without that being obvious.
    #[test]
    fn date_obs_without_a_recorded_start_falls_back_to_now() {
        let ctx = nightshade_sequencer::scheduling::FrameContext::new_light(
            "session".to_string(),
            1,
            1,
            5.0,
            1,
        );
        assert!(ctx.exposure_started_at.is_none());

        let header = crate::FitsWriteHeaderRich::from_frame_context(&ctx);
        let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S").to_string();
        assert_eq!(
            header.capture_timestamp[..13],
            now[..13],
            "fallback should be the current hour, not an empty or sentinel value"
        );
    }

    #[test]
    fn empty_validation_reason_still_classifies() {
        // `validation.errors.join("; ")` can only be empty if the error list was
        // empty, but the classifier must not depend on the reason being present.
        match classify_exposure_failure(
            "ascom:ASCOM.Simulator.Camera",
            IMAGE_VALIDATION_FAILED_PREFIX.to_string(),
        ) {
            NightshadeError::ExposureFailed { camera_id, reason } => {
                assert_eq!(camera_id, "ascom:ASCOM.Simulator.Camera");
                assert!(reason.is_empty());
            }
            other => panic!("expected ExposureFailed, got {other:?}"),
        }
    }
}

#[cfg(test)]
mod fits_keyword_update_tests {
    use super::{
        api_update_fits_keywords, save_fits_file_rich, FitsKeywordUpdate, FitsWriteHeaderRich,
    };
    use nightshade_imaging::read_fits;
    use nightshade_sequencer::scheduling::FrameContext;
    use std::path::{Path, PathBuf};

    /// A scratch directory that deletes itself when the test ends.
    /// `Drop` rather than the trailing `remove_file` calls these tests used to
    /// finish with: a trailing cleanup never runs while a panic unwinds, so a
    /// FAILING test used to leave its FITS behind — drop still runs.
    struct TempDir(PathBuf);

    impl std::ops::Deref for TempDir {
        type Target = Path;
        fn deref(&self) -> &Path {
            &self.0
        }
    }

    // Deref alone does not satisfy a generic `AsRef<Path>` bound, which several
    // call sites here rely on.
    impl AsRef<Path> for TempDir {
        fn as_ref(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            // Best-effort: a test asserting on a half-removed tree should fail
            // on its own assertion, not on cleanup.
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn temp_fits_dir(tag: &str) -> TempDir {
        let p = std::env::temp_dir().join(format!(
            "ns_kw_{}_{}_{}",
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

    async fn write_baseline_fits(path: &std::path::Path) {
        let width = 4u32;
        let height = 4u32;
        let pixels = vec![0u16; (width * height) as usize];
        let ctx = FrameContext::new_light("sess", 1, 1, 10.0, 1);
        let header = FitsWriteHeaderRich::from_frame_context(&ctx);
        save_fits_file_rich(
            path.to_string_lossy().to_string(),
            width,
            height,
            pixels,
            header,
        )
        .await
        .expect("baseline FITS save should succeed");
    }

    #[tokio::test]
    async fn injects_science_keywords_round_trip() {
        let scratch = temp_fits_dir("inject");
        let path = scratch.join("frame.fits");
        write_baseline_fits(&path).await;

        let updates = vec![
            FitsKeywordUpdate {
                keyword: "MAGZP".to_string(),
                comment: Some("Photometric zero point [mag]".to_string()),
                string_value: None,
                int_value: None,
                float_value: Some(24.317),
            },
            FitsKeywordUpdate {
                keyword: "MAGZPERR".to_string(),
                comment: Some("MAGZP 1-sigma uncertainty".to_string()),
                string_value: None,
                int_value: None,
                float_value: Some(0.041),
            },
            FitsKeywordUpdate {
                keyword: "MAGZPSRC".to_string(),
                comment: Some("Catalog used for MAGZP".to_string()),
                string_value: Some("GAIA-DR3".to_string()),
                int_value: None,
                float_value: None,
            },
            FitsKeywordUpdate {
                keyword: "TRANSPAR".to_string(),
                comment: Some("Atmospheric transparency [%]".to_string()),
                string_value: None,
                int_value: None,
                float_value: Some(92.0),
            },
        ];

        api_update_fits_keywords(path.to_string_lossy().to_string(), updates)
            .await
            .expect("keyword update should succeed");

        let (_image, parsed) = read_fits(&path).expect("FITS read-back");
        assert_eq!(parsed.get_float("MAGZP"), Some(24.317));
        assert_eq!(parsed.get_float("MAGZPERR"), Some(0.041));
        assert_eq!(parsed.get_string("MAGZPSRC"), Some("GAIA-DR3"));
        assert_eq!(parsed.get_float("TRANSPAR"), Some(92.0));
        // Existing keywords are preserved.
        assert_eq!(
            parsed.get_string("IMAGETYP").map(str::to_uppercase),
            Some("LIGHT".to_string())
        );
    }

    #[tokio::test]
    async fn overwrites_existing_keyword_value() {
        let scratch = temp_fits_dir("overwrite");
        let path = scratch.join("frame.fits");
        write_baseline_fits(&path).await;

        // First write 1.0, then overwrite with 24.5; the second value must win.
        for value in &[1.0_f64, 24.5_f64] {
            api_update_fits_keywords(
                path.to_string_lossy().to_string(),
                vec![FitsKeywordUpdate {
                    keyword: "MAGZP".to_string(),
                    comment: None,
                    string_value: None,
                    int_value: None,
                    float_value: Some(*value),
                }],
            )
            .await
            .expect("update should succeed");
        }
        let (_image, parsed) = read_fits(&path).expect("FITS read-back");
        assert_eq!(parsed.get_float("MAGZP"), Some(24.5));
    }

    #[tokio::test]
    async fn rejects_keywords_with_multiple_value_types() {
        let scratch = temp_fits_dir("multi");
        let path = scratch.join("frame.fits");
        write_baseline_fits(&path).await;

        let result = api_update_fits_keywords(
            path.to_string_lossy().to_string(),
            vec![FitsKeywordUpdate {
                keyword: "MAGZP".to_string(),
                comment: None,
                string_value: Some("bad".to_string()),
                int_value: None,
                float_value: Some(1.0),
            }],
        )
        .await;
        assert!(result.is_err(), "must reject ambiguous value");
    }

    #[tokio::test]
    async fn rejects_oversize_keyword() {
        let scratch = temp_fits_dir("oversize");
        let path = scratch.join("frame.fits");
        write_baseline_fits(&path).await;

        let result = api_update_fits_keywords(
            path.to_string_lossy().to_string(),
            vec![FitsKeywordUpdate {
                keyword: "TOOLONGKEY".to_string(), // 10 chars; FITS max 8
                comment: None,
                string_value: None,
                int_value: None,
                float_value: Some(1.0),
            }],
        )
        .await;
        assert!(result.is_err(), "must reject >8 char keyword");
    }

    #[tokio::test]
    async fn missing_file_returns_io_error() {
        let result = api_update_fits_keywords(
            "/definitely/not/a/real/file.fits".to_string(),
            vec![FitsKeywordUpdate {
                keyword: "MAGZP".to_string(),
                comment: None,
                string_value: None,
                int_value: None,
                float_value: Some(1.0),
            }],
        )
        .await;
        assert!(result.is_err(), "missing file must surface an error");
    }
}

#[cfg(test)]
mod sim_exposure_tests {
    use super::*;

    /// The Imaging screen's capture must paint the sky the mount is on.
    ///
    /// THE regression guard for this file's half of the two-paths defect. The
    /// sequencer's DeviceManager download rendered the catalogue field while
    /// THIS path — `POST /api/camera/expose`, which is what the Imaging screen
    /// calls — took a `device_id.starts_with("sim_")` shortcut into a
    /// `rand::thread_rng()` star painter. Measured on the release build before
    /// the fix: two captures at an identical pointing shared zero of their 40
    /// brightest stars, and ASTAP found 151 stars and still answered
    /// `No solution found!` at every FOV from 9.5 deg to 0.4 deg.
    ///
    /// Deliberately asserted on `camera_start_exposure_configured_opt` — the
    /// production call site — and not on the renderer, because the renderer was
    /// never the broken part. Point this path back at a random generator and
    /// the centre-star assertion fails: a random field has no reason to put a
    /// star on the tangent point.
    ///
    /// Needs no astap binary and no star database: it synthesises its own area
    /// file and drives the real parser, index, projection and renderer.
    #[tokio::test]
    async fn the_manual_capture_path_renders_the_catalogue_sky() {
        use crate::api::devices::simulation::{get_sim_camera, get_sim_mount};

        let _serialized = crate::api::devices::simulation::sim_singleton_test_lock()
            .lock()
            .await;

        // A grid of catalogue stars centred on the pointing, spaced ~90 px at
        // the simulated rig's 0.776"/px so the detector resolves them apart.
        let ra_hours = 5.59_f64;
        let dec_deg = -5.39_f64;
        let ra_deg = ra_hours * 15.0;
        let step_deg =
            90.0 * crate::sim_capture::sim_plate_scale_arcsec_per_px(
                3.76,
                crate::sim_capture::SIM_DEFAULT_FOCAL_LENGTH_MM,
            ) / 3600.0;
        let mut stars = Vec::new();
        for row in -4i32..=4 {
            for col in -8i32..=8 {
                stars.push((
                    ra_deg + f64::from(col) * step_deg / dec_deg.to_radians().cos(),
                    dec_deg + f64::from(row) * step_deg,
                    9.0 + f64::from((row + col).rem_euclid(5)),
                ));
            }
        }
        let catalog = tempfile::TempDir::new().unwrap();
        crate::sim_sky::astap_integration::write_synthetic_area(
            &catalog.path().join("d05_0001.1476"),
            &stars,
        );

        // Exactly what the Plate Solving settings screen writes. The store is
        // shared and process-lifetime on purpose — see
        // `sim_capture::shared_platesolver_store`.
        crate::sim_capture::shared_platesolver_store();
        let previous = crate::state::get_platesolver_preference().unwrap_or_default();
        crate::state::save_platesolver_preference(&crate::storage::PlateSolverPreference {
            catalog_path: catalog.path().to_string_lossy().to_string(),
            ..previous.clone()
        })
        .expect("save plate-solver preference");

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.connected = true;
            mount.status.right_ascension = ra_hours;
            mount.status.declination = dec_deg;
        }
        // So the field sits where the projection puts it rather than where an
        // earlier test's accumulated drift left it.
        crate::api::devices::simulation::reset_sim_guide_offset().await;
        get_sim_camera().write().await.status.connected = true;

        let device_id = "sim_manual_capture_sky".to_string();
        let capture = camera_start_exposure_configured_opt(
            device_id.clone(),
            1.0,
            Some(100),
            Some(10),
            1,
            1,
            None,
            nightshade_native::camera::FrameType::Light,
        )
        .await;

        let raw = get_last_raw_image_info(&device_id).await;

        // Put the singletons back before asserting, so a failure here does not
        // leave a catalogue sky armed for every other simulator test.
        get_sim_mount().write().await.status.connected = false;
        get_sim_camera().write().await.status.connected = false;
        let _ = crate::state::save_platesolver_preference(&previous);
        let _ = api_clear_device_image(device_id).await;

        capture.expect("simulated exposure should complete");
        let raw = raw
            .expect("raw image lookup should succeed")
            .expect("a raw frame should be stored");

        let data = nightshade_imaging::ImageData::from_u16(raw.width, raw.height, 1, &raw.data);
        let found = nightshade_imaging::detect_stars_with_stats(
            &data,
            &nightshade_imaging::StarDetectionConfig::default(),
        );
        assert!(
            found.stars.len() > 60,
            "the manual-capture frame carried {} stars; the catalogue grid holds {}, so the \
             sky view never reached this path",
            found.stars.len(),
            stars.len()
        );

        // Placed by the projection, not merely present: the grid's centre star
        // sits at the tangent point, which lands on the sensor's centre pixel at
        // any plate scale. A randomly scattered field fails this.
        let centre_x = f64::from(raw.width) / 2.0;
        let centre_y = f64::from(raw.height) / 2.0;
        let nearest = found
            .stars
            .iter()
            .map(|star| (star.x - centre_x).hypot(star.y - centre_y))
            .fold(f64::MAX, f64::min);
        assert!(
            nearest < 12.0,
            "nearest star to the frame centre is {nearest:.1} px away; the Imaging screen is \
             not rendering the field the mount is pointing at"
        );
    }

    /// HFR and eccentricity must be measured, not invented.
    ///
    /// This path reported `Some(2.5 + random())` as HFR and
    /// `Some(0.15 + random())` as eccentricity for every simulated frame, so
    /// the numbers moved when nothing about the optics had, and an autofocus or
    /// guiding regression could not show up in them. They now come from the
    /// same `detect_stars` the real-camera branch uses.
    #[tokio::test]
    async fn simulated_frame_stats_track_focus_instead_of_a_random_draw() {
        use crate::api::devices::simulation::{get_sim_camera, get_sim_focuser};

        let _serialized = crate::api::devices::simulation::sim_singleton_test_lock()
            .lock()
            .await;
        get_sim_camera().write().await.status.connected = true;

        async fn hfr_at_focus(position: i32, device_id: &str) -> Option<f64> {
            {
                let mut focuser = get_sim_focuser().write().await;
                focuser.status.connected = true;
                focuser.status.position = position;
            }
            camera_start_exposure_configured_opt(
                device_id.to_string(),
                1.0,
                Some(100),
                Some(10),
                1,
                1,
                None,
                nightshade_native::camera::FrameType::Light,
            )
            .await
            .expect("simulated exposure should complete");
            let frame = api_get_last_image(device_id.to_string())
                .await
                .expect("a frame should be stored");
            frame.stats.hfr
        }

        let device_id = "sim_focus_stats_probe";
        let sharp = hfr_at_focus(crate::sim_frame::SIM_TRUE_FOCUS, device_id).await;
        let defocused = hfr_at_focus(crate::sim_frame::SIM_TRUE_FOCUS + 150, device_id).await;

        get_sim_focuser().write().await.status.connected = false;
        get_sim_camera().write().await.status.connected = false;
        let _ = api_clear_device_image(device_id.to_string()).await;

        let sharp = sharp.expect("an in-focus frame should yield a measurable HFR");
        let defocused = defocused.expect("a defocused frame should yield a measurable HFR");
        assert!(
            defocused > sharp * 1.2,
            "HFR must grow with defocus: in-focus {sharp:.2} px vs defocused {defocused:.2} px. \
             A fabricated `2.5 + random()` tracks nothing and would fail here."
        );
    }

    /// The simulated camera must deliver the sensor it advertises.
    ///
    /// The manual-capture path generated 4144x2822 while `get_camera_status`
    /// reported SIM_W x SIM_H (1920x1080). Two surfaces of one app then
    /// disagreed about one connected camera: the Imaging toolbar and the FITS
    /// said 4144x2822, while the Framing sidebar sized its FOV box from the
    /// advertised 1920x1080 and drew it 2.16x too narrow.
    #[tokio::test]
    async fn simulated_frame_matches_the_advertised_sensor() {
        let device_id = "sim_geometry_probe".to_string();

        camera_start_exposure_configured_opt(
            device_id.clone(),
            0.01,
            Some(100),
            Some(10),
            1,
            1,
            None,
            nightshade_native::camera::FrameType::Light,
        )
        .await
        .expect("simulated exposure should complete");

        let (advertised_w, advertised_h) = {
            let camera = get_sim_camera().read().await;
            (camera.status.sensor_width, camera.status.sensor_height)
        };
        let frame = api_get_last_image(device_id)
            .await
            .expect("a frame should be stored");

        assert_eq!(
            (frame.width, frame.height),
            (advertised_w, advertised_h),
            "the delivered frame must have the geometry the camera advertised"
        );
    }

    /// Aborting a simulated exposure must actually stop it.
    ///
    /// The cancel path only set the sensor state to Idle, so the exposure
    /// future slept on to full duration and then published
    /// ExposureComplete{success:true} and stored the frame. A 30 s light
    /// aborted at 24 s still "completed" 7 s later.
    #[tokio::test]
    async fn cancelling_a_simulated_exposure_stops_it_and_stores_nothing() {
        let device_id = "sim_cancel_probe".to_string();
        api_clear_device_image(device_id.clone())
            .await
            .expect("clearing an empty slot is a no-op");

        let cancel_id = device_id.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(300)).await;
            api_camera_cancel_exposure(cancel_id)
                .await
                .expect("cancel should be accepted");
        });

        let started = std::time::Instant::now();
        let result = camera_start_exposure_configured_opt(
            device_id.clone(),
            30.0,
            Some(100),
            Some(10),
            1,
            1,
            None,
            nightshade_native::camera::FrameType::Light,
        )
        .await;
        let elapsed = started.elapsed();

        assert!(
            result.is_err(),
            "a cancelled exposure must not report success"
        );
        assert!(
            elapsed < std::time::Duration::from_secs(5),
            "the exposure kept integrating for {:?} of its 30 s after the abort",
            elapsed
        );
        assert!(
            api_get_last_image(device_id).await.is_err(),
            "an aborted exposure must not store a frame"
        );
    }

    /// The operator's actual requirement, end to end: a frame captured FROM THE
    /// IMAGING SCREEN solves against the real ASTAP binary at the pointing the
    /// mount reports.
    ///
    /// `the_manual_capture_path_renders_the_catalogue_sky` above proves the
    /// geometry with a synthetic catalogue and no external binary, so it can run
    /// on CI. It does not prove the frame is SOLVABLE, and "solvable" is the
    /// whole point of the defect: Slew & Center, framing, mosaic tiles,
    /// meridian-flip recentre and polar alignment all call a solver, not a star
    /// detector. The sequencer's download path has had that proof
    /// (`a_downloaded_simulator_frame_solves_at_the_mounts_pointing`); this path
    /// — the one the Imaging screen uses — did not, which is precisely how it
    /// stayed broken while the other path looked fine.
    ///
    /// Ignored by default because it needs `astap_cli` and a star database:
    ///
    /// ```text
    /// NIGHTSHADE_SIM_SKY_ASTAP_DIR=~/.local/share/nightshade-audit/astap/bin \
    ///   cargo test -p nightshade_bridge --lib manual_capture_frame_solves -- --ignored --nocapture
    /// ```
    #[tokio::test]
    #[ignore = "needs astap_cli and a star database; see the doc comment to run it"]
    async fn a_manual_capture_frame_solves_at_the_mounts_pointing() {
        use crate::api::devices::simulation::{get_sim_camera, get_sim_mount};
        use crate::sim_sky::astap_integration::{astap_dir, read_crval, write_fits, PIXEL_UM};

        let _serialized = crate::api::devices::simulation::sim_singleton_test_lock()
            .lock()
            .await;
        let dir = astap_dir();
        let binary = dir.join("astap_cli");
        assert!(
            binary.exists(),
            "no astap_cli in {dir:?}; set NIGHTSHADE_SIM_SKY_ASTAP_DIR"
        );

        // Exactly what the Plate Solving settings screen writes, pointed at the
        // same database ASTAP will match against.
        crate::sim_capture::shared_platesolver_store();
        let previous = crate::state::get_platesolver_preference().unwrap_or_default();
        crate::state::save_platesolver_preference(&crate::storage::PlateSolverPreference {
            astap_path: binary.to_string_lossy().to_string(),
            catalog_path: dir.to_string_lossy().to_string(),
            ..previous.clone()
        })
        .expect("save plate-solver preference");

        // M42, and a mount that says so.
        let ra_hours = 5.59_f64;
        let dec_deg = -5.39_f64;
        {
            let mut mount = get_sim_mount().write().await;
            mount.status.connected = true;
            mount.status.right_ascension = ra_hours;
            mount.status.declination = dec_deg;
        }
        crate::api::devices::simulation::reset_sim_guide_offset().await;
        get_sim_camera().write().await.status.connected = true;

        let device_id = "sim_manual_capture_solve".to_string();
        let capture = camera_start_exposure_configured_opt(
            device_id.clone(),
            0.3,
            None,
            None,
            1,
            1,
            None,
            nightshade_native::camera::FrameType::Light,
        )
        .await;
        let raw = get_last_raw_image_info(&device_id).await;

        // Put the singletons back before asserting, so a failure here does not
        // leave a catalogue sky armed for every other simulator test.
        get_sim_mount().write().await.status.connected = false;
        get_sim_camera().write().await.status.connected = false;
        let _ = crate::state::save_platesolver_preference(&previous);
        let _ = api_clear_device_image(device_id).await;

        capture.expect("simulated exposure should complete");
        let raw = raw
            .expect("raw image lookup should succeed")
            .expect("a raw frame should be stored");

        let scratch = tempfile::TempDir::new().unwrap();
        let path = scratch.path().join("manual_capture.fits");
        write_fits(
            &path,
            &raw.data,
            ra_hours,
            dec_deg,
            crate::sim_capture::SIM_DEFAULT_FOCAL_LENGTH_MM,
        );
        let base = path.with_extension("");
        let scale = crate::sim_capture::sim_plate_scale_arcsec_per_px(
            PIXEL_UM,
            crate::sim_capture::SIM_DEFAULT_FOCAL_LENGTH_MM,
        );
        let fov_h_deg = scale * f64::from(raw.height) / 3600.0;
        let output = std::process::Command::new(&binary)
            .args([
                "-f".into(),
                path.to_string_lossy().to_string(),
                "-r".into(),
                "10".into(),
                "-fov".into(),
                format!("{fov_h_deg:.4}"),
                "-ra".into(),
                format!("{ra_hours:.5}"),
                "-spd".into(),
                format!("{:.5}", dec_deg + 90.0),
                "-d".into(),
                dir.to_string_lossy().to_string(),
                "-o".into(),
                base.to_string_lossy().to_string(),
                "-wcs".into(),
            ])
            .output()
            .expect("run astap_cli");

        let (solved_ra, solved_dec) = read_crval(&base).unwrap_or_else(|| {
            panic!(
                "the Imaging screen's captured frame did not solve:\n{}",
                String::from_utf8_lossy(&output.stdout).trim()
            )
        });
        let error_arcsec = ((solved_ra - ra_hours * 15.0) * dec_deg.to_radians().cos())
            .hypot(solved_dec - dec_deg)
            * 3600.0;
        println!("manual-capture frame solved, centre error {error_arcsec:.1}\"");
        assert!(
            error_arcsec < scale,
            "solved centre {error_arcsec:.1}\" from the mount's pointing, over one \
             {scale:.2}\" pixel"
        );
    }
}
