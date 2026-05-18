// CQ-W3-API-RS: split from monolithic api.rs (audit-rust §9 / audit-arch §1.2)
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs (audit-rust §9).
//
// # `as`-cast policy (audit-rust §1.4)
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
// # `unwrap_or` policy (audit-rust §4.3)
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
use crate::filter_matching::find_filter_match;
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

    use nightshade_sequencer::instructions::{execute_autofocus, InstructionContext};
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

    // Reset cancellation token
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

    let af_config = AutofocusConfig {
        exposure_duration: config.exposure_time,
        step_size: config.step_size,
        steps_out: config.steps_out as u32,
        method,
        binning,
        filter: None, // Optional: add filter support
        max_duration_secs: 600.0,
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

    // Wave 1.5 Pack A: spawn an executor-event bridge so instruction-level
    // emergencies (FITS-save failures from the autofocus V-curve frames, etc.)
    // reach the same NightshadeEvent stream Dart subscribes to. Without this
    // the user only sees a generic "autofocus failed" return code with no
    // hint that the underlying problem was a write error or drive disconnect.
    // The original sender lives on the stack for the duration of the call;
    // the cloned handle is moved into `InstructionContext::event_tx`. When the
    // function returns and the binding is dropped, the background bridge task
    // exits naturally.
    let event_tx = crate::util::executor_event_bridge::spawn_executor_event_bridge(
        get_state().clone(),
    );
    let ctx = InstructionContext {
        target_ra: None,
        target_dec: None,
        target_name: None,
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
    };

    // Execute (no progress callback when called directly from API)
    let result = execute_autofocus(&af_config, &ctx, None).await;

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
pub async fn api_camera_start_exposure(
    device_id: String,
    duration_secs: f64,
    gain: i32,
    offset: i32,
    bin_x: i32,
    bin_y: i32,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Starting {}s exposure with gain={}, offset={}, bin={}x{}",
        duration_secs,
        gain,
        offset,
        bin_x,
        bin_y
    );

    // Check if simulator or real device
    if device_id.starts_with("sim_") {
        // Simulator path (existing code)
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

        // Update camera state to reading
        {
            let mut camera = get_sim_camera().write().await;
            camera.status.state = CameraState::Reading;
        }

        // Generate simulated image
        let sensor_width = 4144 / bin_x as u32;
        let sensor_height = 2822 / bin_y as u32;

        let (raw_data, display_data_raw, histogram, stats, star_count) =
            generate_simulated_image(sensor_width, sensor_height, gain, duration_secs);

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
                hfr: Some(2.5 + (rand::random::<f64>() - 0.5) * 0.5), // Simulated HFR
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
            .camera_start_exposure(
                &device_id,
                duration_secs,
                Some(gain),
                Some(offset),
                bin_x,
                bin_y,
            )
            .await
            .map_err(|e| NightshadeError::OperationFailed(e.to_string()))?;

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

            // 3. Auto-stretch RGB (unified params for simplicity)
            let rgb_pixels: Vec<f64> = rgb_data.par_iter().map(|&v| v as f64 / 65535.0).collect();
            let mut sorted = rgb_pixels.clone();
            // Use unwrap_or for float comparison to handle NaN safely
            // NaN values are treated as equal to avoid panics
            sorted
                .par_sort_unstable_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
            if sorted.is_empty() {
                return Err(NightshadeError::ImageError(
                    "Empty image data for median calculation".to_string(),
                ));
            }
            let median = median_from_sorted_f64(&sorted).ok_or_else(|| {
                NightshadeError::ImageError("Empty image data for median calculation".to_string())
            })?;
            let unified_params = nightshade_imaging::StretchParams {
                shadows: (median - 0.1).max(0.0),
                highlights: (median + 0.3).min(1.0),
                midtones: 0.5,
            };

            // 4. Apply stretch to convert RGB u16 -> RGB u8
            display_data_raw = nightshade_imaging::apply_stretch_rgb(
                &rgb_data,
                seq_image.width,
                seq_image.height,
                &unified_params,
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
        tracing::info!(
            "Star detection: {} stars found, median HFR: {:?}",
            star_count,
            median_hfr
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
    tracing::info!("API: api_get_last_image called for device: {}", device_id);
    let mut storage = get_unified_image_storage().lock().await;
    match storage.get(&device_id) {
        Some(data) => {
            tracing::info!(
                "API: Returning stored image {}x{}, display_data size: {} bytes",
                data.display.width,
                data.display.height,
                data.display.display_data.len()
            );
            Ok(data.display.clone())
        }
        None => {
            tracing::warn!("API: No image available for device: {}", device_id);
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
        let mut camera = get_sim_camera().write().await;
        camera.status.state = CameraState::Idle;
        tracing::info!("Exposure cancelled");
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.camera_abort_exposure(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Generate a simulated star field image
pub(crate) fn generate_simulated_image(
    width: u32,
    height: u32,
    gain: i32,
    exposure_time: f64,
) -> (
    Vec<u16>,
    Vec<u8>,
    Vec<u32>,
    nightshade_imaging::ImageStats,
    u32,
) {
    let mut rng = rand::thread_rng();
    // Why: simulation code; width/height are u32 inputs from a controlled test path
    // (`generate_simulated_exposure_data` is only invoked with small fake-camera sizes
    // <= ~16M pixels). Promote to u64 anyway for overflow safety.
    let pixel_count =
        usize::try_from((width as u64).saturating_mul(height as u64)).unwrap_or(usize::MAX);

    // Create raw 16-bit image data
    let mut raw_data: Vec<u16> = vec![0u16; pixel_count];

    // Background level based on gain and exposure
    let base_background = 500 + (gain as f64 * 5.0 + exposure_time * 10.0) as u16;
    let noise_level = (50.0 + gain as f64 * 0.5) as u16;

    // Fill with background + noise
    for pixel in &mut raw_data {
        let noise = (rng.gen::<f64>() * noise_level as f64) as i32;
        *pixel = (base_background as i32 + noise - noise_level as i32 / 2).clamp(0, 65535) as u16;
    }

    // Add stars (more with longer exposure)
    let num_stars = (100.0 + exposure_time * 50.0).min(500.0) as u32;
    let mut star_count = 0u32;

    for _ in 0..num_stars {
        let x = rng.gen_range(5..width - 5);
        let y = rng.gen_range(5..height - 5);
        let brightness = rng.gen_range(5000u16..60000u16);
        let size = rng.gen_range(1.5f64..4.0f64);

        // Draw Gaussian star profile
        let radius = (size * 3.0) as i32;
        for dy in -radius..=radius {
            for dx in -radius..=radius {
                let px = (x as i32 + dx) as u32;
                let py = (y as i32 + dy) as u32;

                if px < width && py < height {
                    let dist_sq = (dx * dx + dy * dy) as f64;
                    let sigma_sq = size * size;
                    let intensity = brightness as f64 * (-dist_sq / (2.0 * sigma_sq)).exp();

                    let idx = (py * width + px) as usize;
                    raw_data[idx] = (raw_data[idx] as f64 + intensity).min(65535.0) as u16;
                }
            }
        }
        star_count += 1;
    }

    // Add some hot pixels
    for _ in 0..20 {
        let idx = rng.gen_range(0..pixel_count);
        raw_data[idx] = rng.gen_range(40000u16..65535u16);
    }

    // Create ImageData for stats calculation
    let image_bytes: Vec<u8> = raw_data.iter().flat_map(|&val| val.to_le_bytes()).collect();

    let image_data = nightshade_imaging::ImageData {
        width,
        height,
        channels: 1,
        pixel_type: nightshade_imaging::PixelType::U16,
        data: image_bytes.clone(),
    };

    // Calculate stats
    let stats = nightshade_imaging::calculate_stats_u16(&image_data);

    // Auto stretch for display
    let stretch_params = nightshade_imaging::auto_stretch_stf(&image_data);
    let display_data = nightshade_imaging::apply_stretch(&image_data, &stretch_params);

    // Calculate histogram from display data
    let mut histogram = vec![0u32; 256];
    for &pixel in &display_data {
        histogram[pixel as usize] += 1;
    }

    (raw_data, display_data, histogram, stats, star_count)
}

/// Internal random utilities - not exposed to Dart FFI
#[flutter_rust_bridge::frb(ignore)]
pub mod rand {
    use std::time::{SystemTime, UNIX_EPOCH};

    // Note: Range is NOT re-exported because FRB generates invalid code for Range<Self>
    // The gen_range function is marked as ignored by FRB anyway

    #[flutter_rust_bridge::frb(ignore)]
    pub fn random<T: RandomValue>() -> T {
        T::random()
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub trait RandomValue {
        fn random() -> Self;
    }

    #[flutter_rust_bridge::frb(ignore)]
    impl RandomValue for f64 {
        fn random() -> Self {
            // Use unwrap_or with a fallback value to avoid panic
            // SystemTime::now() can fail if system clock is set before UNIX_EPOCH
            let seed = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or(std::time::Duration::from_secs(0))
                .as_nanos() as u64;
            // Simple LCG - even with seed=0, this produces valid output
            let x = seed
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            (x as f64) / (u64::MAX as f64)
        }
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub struct Rng {
        pub state: u64,
    }

    #[flutter_rust_bridge::frb(ignore)]
    impl Rng {
        pub fn gen<T: RandomValue>(&mut self) -> T {
            T::random()
        }

        pub fn gen_range<T: RandomRange>(&mut self, range: std::ops::Range<T>) -> T {
            // Use unwrap_or with a fallback to avoid panic on clock issues
            let seed = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or(std::time::Duration::from_secs(0))
                .as_nanos() as u64;
            self.state = self
                .state
                .wrapping_mul(6364136223846793005)
                .wrapping_add(seed);
            T::in_range(self.state, range)
        }
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub trait RandomRange: Sized {
        fn in_range(seed: u64, range: std::ops::Range<Self>) -> Self;
    }

    #[flutter_rust_bridge::frb(ignore)]
    impl RandomRange for u32 {
        fn in_range(seed: u64, range: std::ops::Range<Self>) -> Self {
            let span = range.end - range.start;
            range.start + (seed as u32 % span)
        }
    }

    #[flutter_rust_bridge::frb(ignore)]
    impl RandomRange for u16 {
        fn in_range(seed: u64, range: std::ops::Range<Self>) -> Self {
            let span = range.end - range.start;
            range.start + (seed as u16 % span)
        }
    }

    #[flutter_rust_bridge::frb(ignore)]
    impl RandomRange for f64 {
        fn in_range(seed: u64, range: std::ops::Range<Self>) -> Self {
            let t = (seed as f64) / (u64::MAX as f64);
            range.start + t * (range.end - range.start)
        }
    }

    #[flutter_rust_bridge::frb(ignore)]
    impl RandomRange for usize {
        fn in_range(seed: u64, range: std::ops::Range<Self>) -> Self {
            let span = range.end - range.start;
            range.start + (seed as usize % span)
        }
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub fn thread_rng() -> Rng {
        // Use unwrap_or with a fallback to avoid panic on clock issues
        let seed = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or(std::time::Duration::from_secs(0))
            .as_nanos() as u64;
        Rng { state: seed }
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
            .map(|chunk| u16::from_be_bytes([chunk[0], chunk[1]]) as f64)
            .collect::<Vec<f64>>(),
        nightshade_imaging::PixelType::U32 => image_data
            .data
            .chunks_exact(4)
            .map(|chunk| u32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]) as f64)
            .collect::<Vec<f64>>(),
        nightshade_imaging::PixelType::F32 => image_data
            .data
            .chunks_exact(4)
            .map(|chunk| f32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]) as f64)
            .collect::<Vec<f64>>(),
        nightshade_imaging::PixelType::F64 => image_data
            .data
            .chunks_exact(8)
            .map(|chunk| {
                f64::from_be_bytes([
                    chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6], chunk[7],
                ])
            })
            .collect::<Vec<f64>>(),
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
            hfr: None,
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

pub(crate) fn median_from_sorted_f64(sorted: &[f64]) -> Option<f64> {
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
            hfr: None,
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

/// Header data for FITS file writing
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

    // Target coordinates and airmass
    if let Some(ra) = header_data.ra {
        header.set_float("RA", ra);
    }
    if let Some(dec) = header_data.dec {
        header.set_float("DEC", dec);
    }
    if let Some(altitude) = header_data.altitude {
        // Why: airmass returns Err for below-horizon inputs (audit §6.14). Surface
        // that as an OperationFailed so the caller knows the frame metadata was
        // attempted with an invalid altitude rather than silently writing a
        // sentinel value or omitting the keyword.
        let airmass = calculate_airmass(altitude).map_err(|e| {
            NightshadeError::OperationFailed(format!(
                "Cannot compute AIRMASS for altitude {}°: {}",
                altitude, e
            ))
        })?;
        header.set_float("AIRMASS", airmass);
    }

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

    // Target coordinates and airmass
    if let Some(ra) = header_data.ra {
        header.set_float("RA", ra);
    }
    if let Some(dec) = header_data.dec {
        header.set_float("DEC", dec);
    }
    if let Some(altitude) = header_data.altitude {
        // Why: airmass returns Err for below-horizon inputs (audit §6.14). Surface
        // that as an OperationFailed so the caller knows the frame metadata was
        // attempted with an invalid altitude rather than silently writing a
        // sentinel value or omitting the keyword.
        let airmass = calculate_airmass(altitude).map_err(|e| {
            NightshadeError::OperationFailed(format!(
                "Cannot compute AIRMASS for altitude {}°: {}",
                altitude, e
            ))
        })?;
        header.set_float("AIRMASS", airmass);
    }

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
        hfr: None,
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
                .map(|chunk| u16::from_be_bytes([chunk[0], chunk[1]]))
                .collect::<Vec<u16>>()
        }
        nightshade_imaging::PixelType::U32 => {
            // Convert u32 to u16 (downscale)
            image_data
                .data
                .chunks_exact(4)
                .map(|chunk| {
                    let val = u32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
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
                    let val = f32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
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
                    let val = f64::from_be_bytes([
                        chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6],
                        chunk[7],
                    ]);
                    (val.clamp(0.0, 1.0) * 65535.0) as u16
                })
                .collect::<Vec<u16>>()
        }
    };

    let width = image_data.width;
    let height = image_data.height;

    // Calculate downscale factor
    let scale = ((width.max(height) as f32) / max_size as f32).ceil() as u32;
    let scale = scale.max(1);

    // Downscale image
    let new_width = width / scale;
    let new_height = height / scale;
    let mut downscaled = Vec::with_capacity((new_width * new_height) as usize);

    for y in 0..new_height {
        for x in 0..new_width {
            let src_x = x * scale;
            let src_y = y * scale;
            let idx = (src_y * width + src_x) as usize;
            if idx < data_u16.len() {
                downscaled.push(data_u16[idx]);
            } else {
                downscaled.push(0);
            }
        }
    }

    // Auto-stretch for display
    let stretched = crate::imaging_ops::auto_stretch_image(new_width, new_height, downscaled);

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
}

impl Default for ApiLiveStackingConfig {
    fn default() -> Self {
        Self {
            sigma_clip_enabled: true,
            sigma_clip_threshold: 2.5,
            max_match_stars: 100,
            match_radius_px: 50.0,
            match_flux_tolerance: 0.7,
            min_matched_pairs: 5,
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
