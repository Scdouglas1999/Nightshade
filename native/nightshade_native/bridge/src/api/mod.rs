//! Public API exposed to Dart via flutter_rust_bridge
//!
//! This module contains all the functions that can be called from Dart.
//! Each function is marked with the appropriate flutter_rust_bridge attributes.
//!
//! CQ-W3-API-RS (audit-rust §9 / audit-arch §1.2): mid-split state.
//! Foundation sections (init, event_stream, discovery, connection, heartbeat,
//! api_version) AND device-control sections (camera, mount, focuser,
//! filter_wheel, dome, switch, cover_calibrator, simulation) have been
//! extracted to dedicated submodules. The remainder of the original api.rs
//! is still inline below; Commit C extracts imaging/sequencer/ancillary.

use crate::adaptive_polling::{AdaptivePoller, PollerPreset};
use crate::device::*;
use crate::devices::DeviceManager;
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

/// Global application state singleton
static APP_STATE: OnceLock<SharedAppState> = OnceLock::new();

/// Get or initialize the global application state
#[flutter_rust_bridge::frb(ignore)]
pub fn get_state() -> &'static SharedAppState {
    APP_STATE.get_or_init(AppState::new)
}

/// Global device manager singleton
static DEVICE_MANAGER: OnceLock<Arc<DeviceManager>> = OnceLock::new();

/// Get or initialize the global device manager
#[flutter_rust_bridge::frb(ignore)]
pub fn get_device_manager() -> &'static Arc<DeviceManager> {
    DEVICE_MANAGER.get_or_init(|| DeviceManager::new(get_state().clone()))
}

// =============================================================================
// Unified Discovery Cache (ASCOM + Alpaca + Native + INDI)
// =============================================================================

/// Unified cache for ALL discovered devices across every discovery source.
/// When `api_discover_devices()` is called for any device type, the first call
/// runs full discovery for all sources (ASCOM, Alpaca, Native, INDI) and caches
/// every result. Subsequent calls within the TTL just filter by device_type.
pub(crate) struct DiscoveryCache {
    /// All discovered devices from every source, unfiltered
    pub(crate) all_devices: Vec<DeviceInfo>,
    /// When the cache was last populated
    pub(crate) timestamp: Instant,
}

/// Global unified discovery cache
static DISCOVERY_CACHE: OnceLock<Mutex<Option<DiscoveryCache>>> = OnceLock::new();

// =============================================================================
// Event Stream Overflow Tracking
// =============================================================================

/// Global counter for total events dropped across all event streams.
/// This is incremented when a receiver falls behind and events are skipped.
pub(crate) static TOTAL_DROPPED_EVENTS: AtomicU64 = AtomicU64::new(0);
pub(crate) static TEMP_FITS_FILE_COUNTER: AtomicU64 = AtomicU64::new(0);

/// How long to cache unified discovery results (60 seconds)
pub(crate) const DISCOVERY_CACHE_TTL: Duration = Duration::from_secs(60);

/// Get or initialize the discovery cache
pub(crate) fn get_discovery_cache() -> &'static Mutex<Option<DiscoveryCache>> {
    DISCOVERY_CACHE.get_or_init(|| Mutex::new(None))
}

/// Discovery state to prevent concurrent discovery operations
static DISCOVERY_IN_PROGRESS: OnceLock<Mutex<bool>> = OnceLock::new();

pub(crate) fn get_discovery_lock() -> &'static Mutex<bool> {
    DISCOVERY_IN_PROGRESS.get_or_init(|| Mutex::new(false))
}

pub(crate) fn create_unique_temp_fits_path(prefix: &str) -> std::path::PathBuf {
    let counter = TEMP_FITS_FILE_COUNTER.fetch_add(1, Ordering::Relaxed);
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    std::env::temp_dir().join(format!(
        "{}_{}_{}_{}.fits",
        prefix,
        std::process::id(),
        timestamp,
        counter
    ))
}

/// Invalidate the unified discovery cache, forcing fresh discovery on next call.
/// Also invalidates the native SDK discovery cache so vendor SDKs are re-queried.
/// Called when user explicitly requests a rescan.
pub async fn api_invalidate_discovery_cache() {
    // Invalidate the unified cache
    let mut cache = get_discovery_cache().lock().await;
    *cache = None;
    // Also invalidate the native vendor SDK cache so it re-queries all SDKs
    nightshade_native::invalidate_discovery_cache().await;
    tracing::info!("Discovery cache invalidated");
}

// =============================================================================
// Foundation submodules (CQ-W3-API-RS:GroupA — audit-rust §9)
// =============================================================================

mod api_version;
mod connection;
mod discovery;
mod event_stream;
mod heartbeat;
mod init;

pub use api_version::*;
pub use connection::*;
pub use discovery::*;
pub use event_stream::*;
pub use heartbeat::*;
pub use init::*;

// Device-control submodules (CQ-W3-API-RS:GroupB — audit-rust §9)
mod devices;
pub use devices::*;

// =============================================================================
// Pending extraction (Commit C): the rest of the original api.rs body
// follows verbatim below. Items are still resolved via the imports at the
// head of this file.
// =============================================================================

// =============================================================================
// Camera Exposure & Image Capture
// =============================================================================

/// Global cancellation token for autofocus
static AUTOFOCUS_CANCEL_TOKEN: OnceLock<Arc<AtomicBool>> = OnceLock::new();

fn get_autofocus_cancel_token() -> &'static Arc<AtomicBool> {
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
    pub is_color: bool, // true if source was color (RGB), false if grayscale â€” retained for stretch/analysis paths
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
const UNIFIED_IMAGE_STORAGE_CAPACITY: usize = 50;

/// Per-device image storage - keyed by device ID to support multi-camera operation.
///
/// Each camera's image data is stored independently, preventing race conditions
/// where concurrent cameras could overwrite each other's captured images.
///
/// Bounded with an LRU policy so unique device-ids accumulated over long sessions
/// (USB re-enumeration, network device churn) cannot leak raw u16 buffers
/// indefinitely. On eviction the oldest-touched entry is dropped and a debug
/// trace is emitted; see `store_captured_image_atomically`.
static UNIFIED_IMAGE_STORAGE: OnceLock<
    Arc<tokio::sync::Mutex<lru::LruCache<String, CapturedImageData>>>,
> = OnceLock::new();

fn get_unified_image_storage(
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
                    "Odd byte count in image data â€” cannot convert to u16 pixels".to_string(),
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
fn generate_simulated_image(
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
    let pixel_count = (width * height) as usize;

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
// Session Management
// =============================================================================

/// Get current session state
pub async fn api_get_session_state() -> SessionState {
    get_state().get_session().await
}

/// Start a new imaging session
pub async fn api_start_session(
    target_name: Option<String>,
    ra: Option<f64>,
    dec: Option<f64>,
) -> Result<(), NightshadeError> {
    get_state().start_session(target_name, ra, dec).await;
    tracing::info!("Session started");
    Ok(())
}

/// End the current session
pub async fn api_end_session() -> Result<(), NightshadeError> {
    get_state().end_session().await;
    tracing::info!("Session ended");
    Ok(())
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

fn image_data_to_linear_f64(image_data: &ImageData) -> Vec<f64> {
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

fn percentile_sorted(sorted_values: &[f64], p: f64) -> f64 {
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

fn percentile(values: &[f64], p: f64) -> f64 {
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

fn median(values: &[f64]) -> f64 {
    percentile(values, 0.5)
}

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

fn mad(values: &[f64], median_value: f64) -> f64 {
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

fn compute_quality_maps_from_linear_data(
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
// REAL PLATE SOLVING
// =============================================================================

/// Plate solve result
#[derive(Debug, Clone)]
pub struct PlateSolveResult {
    pub success: bool,
    pub ra: f64,           // degrees
    pub dec: f64,          // degrees
    pub pixel_scale: f64,  // arcsec/pixel
    pub rotation: f64,     // degrees, East of North
    pub field_width: f64,  // degrees
    pub field_height: f64, // degrees
    pub solve_time_secs: f64,
    pub error: Option<String>,
}

/// Check if a plate solver is available
#[flutter_rust_bridge::frb(sync)]
pub fn api_is_plate_solver_available() -> bool {
    nightshade_imaging::is_solver_available()
}

/// Get the path to the installed plate solver
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_plate_solver_path() -> Option<String> {
    nightshade_imaging::get_solver_path().map(|p| p.to_string_lossy().to_string())
}

/// Plate solve an image file (blind solve)
pub async fn api_plate_solve_blind(file_path: String) -> Result<PlateSolveResult, NightshadeError> {
    use std::path::Path;

    tracing::info!("Blind plate solving: {}", file_path);

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    // Run actual plate solve using ASTAP
    let result = nightshade_imaging::blind_solve(path);

    Ok(PlateSolveResult {
        success: result.success,
        ra: result.ra,
        dec: result.dec,
        pixel_scale: result.pixel_scale,
        rotation: result.rotation,
        field_width: result.field_width,
        field_height: result.field_height,
        solve_time_secs: result.solve_time_secs,
        error: result.error,
    })
}

/// Plate solve an image with hint coordinates
pub async fn api_plate_solve_near(
    file_path: String,
    hint_ra: f64,
    hint_dec: f64,
    search_radius: f64,
) -> Result<PlateSolveResult, NightshadeError> {
    use std::path::Path;

    tracing::info!(
        "Plate solving near RA:{:.2}Â°, Dec:{:.2}Â°: {}",
        hint_ra,
        hint_dec,
        file_path
    );

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    // Run actual plate solve using ASTAP with hints
    let result = nightshade_imaging::solve_near(path, hint_ra, hint_dec, search_radius);

    Ok(PlateSolveResult {
        success: result.success,
        ra: result.ra,
        dec: result.dec,
        pixel_scale: result.pixel_scale,
        rotation: result.rotation,
        field_width: result.field_width,
        field_height: result.field_height,
        solve_time_secs: result.solve_time_secs,
        error: result.error,
    })
}

// =============================================================================
// PLATE SOLVER UX (detection / verification / config)
// =============================================================================

/// Detection snapshot returned to the settings UI. Contains everything
/// needed to render the "ASTAP detected at /path/to/astap.exe (catalog: V17
/// to mag 17)" status banner without further FFI round-trips.
#[derive(Debug, Clone)]
pub struct PlateSolverDetection {
    /// Detected ASTAP executable path. `None` when ASTAP is not installed.
    pub astap_path: Option<String>,
    /// Detected `solve-field` path. `None` when astrometry.net is not
    /// installed.
    pub astrometry_path: Option<String>,
    /// Detected ASTAP star catalog. `None` when ASTAP was detected but no
    /// catalog could be located (the user must point us at one).
    pub catalog_name: Option<String>,
    /// Approximate magnitude limit the detected catalog covers (e.g. 17.0
    /// for V17). `None` when the catalog flavour isn't recognised.
    pub catalog_magnitude_limit: Option<f32>,
    /// Directory containing the detected catalog.
    pub catalog_path: Option<String>,
}

/// Detailed information about a verified solver binary. See
/// `api_platesolve_verify`.
#[derive(Debug, Clone)]
pub struct PlateSolverInfo {
    /// Absolute path of the verified binary.
    pub path: String,
    /// `"ASTAP"`, `"Astrometry.net"`, or `"Unknown"`.
    pub flavour: String,
    /// First non-empty line of the binary's `--help` output, useful for
    /// surfacing the build version in the settings UI.
    pub version_line: String,
}

/// Persisted plate-solver UX configuration. Mirrors `storage::PlateSolverPreference`
/// 1:1; lives in this module so flutter_rust_bridge can generate Dart
/// bindings without exporting the storage internals.
#[derive(Debug, Clone)]
pub struct PlateSolverConfigPayload {
    pub astap_path: String,
    pub astrometry_path: String,
    pub catalog_path: String,
    pub solver_choice: String,
}

impl PlateSolverConfigPayload {
    fn into_pref(self) -> crate::storage::PlateSolverPreference {
        crate::storage::PlateSolverPreference {
            astap_path: self.astap_path,
            astrometry_path: self.astrometry_path,
            catalog_path: self.catalog_path,
            solver_choice: self.solver_choice,
        }
    }
}

impl From<crate::storage::PlateSolverPreference> for PlateSolverConfigPayload {
    fn from(pref: crate::storage::PlateSolverPreference) -> Self {
        Self {
            astap_path: pref.astap_path,
            astrometry_path: pref.astrometry_path,
            catalog_path: pref.catalog_path,
            solver_choice: pref.solver_choice,
        }
    }
}

/// Detect installed plate solvers and catalogs. Honours the user-configured
/// override paths from the persisted plate-solver preference, if any. Does
/// not run the binaries â€” that's `api_platesolve_verify`.
#[flutter_rust_bridge::frb(sync)]
pub fn api_platesolve_detect() -> Result<PlateSolverDetection, NightshadeError> {
    use std::path::Path;

    // Why: first-run / no-saved-prefs is the dominant case â€” return defaults
    // so detection still scans standard install paths. A storage IO error
    // here is non-fatal because the only state read is overlay-on-defaults;
    // the user can still set explicit paths in the Plate Solving settings.
    let pref = crate::state::get_platesolver_preference()
        .unwrap_or_else(|_| crate::storage::PlateSolverPreference::default());

    let configured_astap = if pref.astap_path.is_empty() {
        None
    } else {
        Some(pref.astap_path.clone())
    };
    let configured_astrometry = if pref.astrometry_path.is_empty() {
        None
    } else {
        Some(pref.astrometry_path.clone())
    };
    let configured_catalog = if pref.catalog_path.is_empty() {
        None
    } else {
        Some(pref.catalog_path.clone())
    };

    // Probing involves filesystem reads which are fast but blocking. The
    // function is sync â€” callers can wrap it if they need it off the UI
    // isolate.
    nightshade_imaging::invalidate_solver_availability_cache();

    let astap_path = nightshade_imaging::find_astap_with_override(
        configured_astap.as_deref().map(Path::new),
    );
    let astrometry_path = nightshade_imaging::find_astrometry_with_override(
        configured_astrometry.as_deref().map(Path::new),
    );

    let catalog = nightshade_imaging::detect_astap_catalog(
        astap_path.as_deref(),
        configured_catalog.as_deref().map(Path::new),
    );

    Ok(PlateSolverDetection {
        astap_path: astap_path.map(|p| p.to_string_lossy().to_string()),
        astrometry_path: astrometry_path.map(|p| p.to_string_lossy().to_string()),
        catalog_name: catalog.as_ref().and_then(|c| {
            if c.name.is_empty() {
                None
            } else {
                Some(c.name.clone())
            }
        }),
        catalog_magnitude_limit: catalog.as_ref().and_then(|c| c.magnitude_limit),
        catalog_path: catalog.as_ref().map(|c| c.path.to_string_lossy().to_string()),
    })
}

/// Run the supplied solver binary with `--help` to confirm it's healthy.
/// Returns a `PlateSolverInfo` with the detected flavour and version banner,
/// or a `NightshadeError` if the binary is missing / fails to spawn / exits
/// with non-zero status and empty output.
#[flutter_rust_bridge::frb(sync)]
pub fn api_platesolve_verify(executable_path: String) -> Result<PlateSolverInfo, NightshadeError> {
    use std::path::Path;
    let path = Path::new(&executable_path);
    match nightshade_imaging::verify_solver(path) {
        Ok(info) => Ok(PlateSolverInfo {
            path: info.path.to_string_lossy().to_string(),
            flavour: info.flavour,
            version_line: info.version_line,
        }),
        Err(e) => Err(NightshadeError::OperationFailed(e.to_string())),
    }
}

/// Read the persisted plate-solver configuration. Falls back to defaults if
/// the storage was never written.
#[flutter_rust_bridge::frb(sync)]
pub fn api_platesolve_get_config() -> Result<PlateSolverConfigPayload, NightshadeError> {
    let pref = crate::state::get_platesolver_preference()
        .map_err(NightshadeError::OperationFailed)?;
    Ok(pref.into())
}

/// Persist a new plate-solver configuration. Invalidates the solver
/// availability cache so the next `api_is_plate_solver_available()` call
/// re-probes the filesystem with the new paths.
#[flutter_rust_bridge::frb(sync)]
pub fn api_platesolve_set_config(
    config: PlateSolverConfigPayload,
) -> Result<(), NightshadeError> {
    let pref = config.into_pref();
    crate::state::save_platesolver_preference(&pref).map_err(NightshadeError::OperationFailed)?;
    nightshade_imaging::invalidate_solver_availability_cache();
    Ok(())
}

// =============================================================================
// REAL PHD2 GUIDING INTEGRATION
// =============================================================================

/// PHD2 connection state
#[derive(Debug, Clone)]
pub struct Phd2Status {
    pub connected: bool,
    pub state: String, // "Disconnected", "Connected", "Calibrating", "Guiding", "Looping", "Paused"
    pub rms_ra: f64,
    pub rms_dec: f64,
    pub rms_total: f64,
    pub snr: f64,
    pub star_mass: f64,
    pub pixel_scale: f64,
}

/// PHD2 calibration data
#[derive(Debug, Clone)]
pub struct Phd2CalibrationData {
    /// Whether the mount is calibrated
    pub is_calibrated: bool,
    /// RA axis rotation angle (degrees)
    pub ra_angle: Option<f64>,
    /// Dec axis rotation angle (degrees)
    pub dec_angle: Option<f64>,
    /// RA guide rate (pixels/second)
    pub ra_rate: Option<f64>,
    /// Dec guide rate (pixels/second)
    pub dec_rate: Option<f64>,
}

/// PHD2 star image data
#[derive(Debug, Clone)]
pub struct Phd2StarImage {
    /// Frame number
    pub frame: u32,
    /// Image width in pixels
    pub width: u32,
    /// Image height in pixels
    pub height: u32,
    /// Star centroid X position
    pub star_x: f64,
    /// Star centroid Y position
    pub star_y: f64,
    /// Raw pixel data (16-bit grayscale as bytes)
    pub pixels: Vec<u8>,
}

/// PHD2 Brain algorithm parameter
#[derive(Debug, Clone)]
pub struct Phd2AlgoParam {
    /// Parameter name
    pub name: String,
    /// Parameter value
    pub value: f64,
}

/// Check if PHD2 is running
#[flutter_rust_bridge::frb(sync)]
pub fn api_is_phd2_running() -> bool {
    nightshade_imaging::is_phd2_running()
}

/// Static PHD2 client storage
static PHD2_CLIENT: OnceLock<Arc<RwLock<Option<nightshade_imaging::Phd2Client>>>> = OnceLock::new();

#[flutter_rust_bridge::frb(ignore)]
pub fn get_phd2_storage() -> &'static Arc<RwLock<Option<nightshade_imaging::Phd2Client>>> {
    PHD2_CLIENT.get_or_init(|| Arc::new(RwLock::new(None)))
}

#[flutter_rust_bridge::frb(ignore)]
pub async fn get_active_guider_id_for_ops() -> Option<String> {
    if let Some(profile_guider) = get_state().get_profile_device_id(DeviceType::Guider).await {
        return Some(profile_guider);
    }
    if get_state()
        .is_device_connected(DeviceType::Guider, crate::builtin_guider::device_id())
        .await
    {
        return Some(crate::builtin_guider::device_id().to_string());
    }
    if get_state()
        .is_device_connected(DeviceType::Guider, "phd2_guider")
        .await
    {
        return Some("phd2_guider".to_string());
    }
    get_state()
        .get_devices(DeviceType::Guider)
        .await
        .into_iter()
        .map(|device| device.id)
        .next()
}

/// Connect to PHD2
pub async fn api_phd2_connect(
    host: Option<String>,
    port: Option<u16>,
) -> Result<(), NightshadeError> {
    let host = host.unwrap_or_else(|| "127.0.0.1".to_string());
    let port = port.unwrap_or(4400);

    tracing::info!("Connecting to PHD2 at {}:{}", host, port);

    let mut client = nightshade_imaging::Phd2Client::new(&host, port);

    // Set up event callback to forward PHD2 events to the main event stream.
    // This callback runs on the PHD2 reader std::thread, NOT on the tokio runtime.
    // It publishes to the broadcast channel which is picked up by api_event_stream.
    client.set_event_callback(move |event| {
        let subscriber_count = get_state().event_bus.subscriber_count();
        tracing::info!(
            "PHD2 event callback received: {:?} (event bus subscribers: {})",
            std::mem::discriminant(&event),
            subscriber_count
        );

        let guiding_event = match event {
            nightshade_imaging::Phd2Event::GuideStep(ref frame) => {
                tracing::info!(
                    "PHD2 GuideStep: RA={:.3}, Dec={:.3}, SNR={:.1}",
                    frame.ra_distance,
                    frame.dec_distance,
                    frame.snr
                );
                // Forward guide step correction data
                let event_id = get_state().publish_guiding_event(
                    GuidingEvent::Correction {
                        ra: frame.ra_distance,
                        dec: frame.dec_distance,
                        ra_raw: frame.ra_distance,
                        dec_raw: frame.dec_distance,
                    },
                    EventSeverity::Info,
                );
                tracing::info!("PHD2: Published Correction event (id={})", event_id);
                // Also forward guide stats (SNR and star mass)
                let stats_id = get_state().publish_guiding_event(
                    GuidingEvent::GuideStats {
                        snr: frame.snr,
                        star_mass: frame.star_mass,
                    },
                    EventSeverity::Info,
                );
                tracing::info!("PHD2: Published GuideStats event (id={})", stats_id);
                return;
            }
            nightshade_imaging::Phd2Event::StateChanged(state) => {
                tracing::info!("PHD2 state changed: {:?}", state);
                match state {
                    nightshade_imaging::Phd2State::Guiding => GuidingEvent::GuidingStarted,
                    nightshade_imaging::Phd2State::Connected => GuidingEvent::GuidingStopped,
                    nightshade_imaging::Phd2State::Disconnected => GuidingEvent::Disconnected,
                    nightshade_imaging::Phd2State::Paused => GuidingEvent::Paused,
                    nightshade_imaging::Phd2State::LostLock => GuidingEvent::LostStar,
                    nightshade_imaging::Phd2State::Looping => GuidingEvent::Looping,
                    nightshade_imaging::Phd2State::Calibrating => GuidingEvent::Calibrating,
                    nightshade_imaging::Phd2State::Settling => GuidingEvent::Settling,
                    // Why: PHD2 occasionally introduces new app-states; we
                    // forward the raw name as a generic `Disconnected` event
                    // (the safest superset for sequencer logic) but the
                    // warning is already emitted upstream in
                    // `parse_phd2_app_state`. Surfacing the literal string in
                    // the GuidingEvent stream would require extending the
                    // FFI enum, which is out of scope here.
                    nightshade_imaging::Phd2State::Unknown(raw) => {
                        tracing::warn!(
                            "PHD2: unrecognised state {:?} bubbled into bridge â€” \
                             treating as Disconnected for guiding-event mapping",
                            raw
                        );
                        GuidingEvent::Disconnected
                    }
                }
            }
            nightshade_imaging::Phd2Event::StarLost => GuidingEvent::LostStar,
            nightshade_imaging::Phd2Event::StarSelected { x, y } => {
                GuidingEvent::StarSelected { x, y }
            }
            nightshade_imaging::Phd2Event::SettleBegin => GuidingEvent::Settling,
            nightshade_imaging::Phd2Event::SettleDone {
                total_frames: _,
                dropped_frames: _,
            } => GuidingEvent::Settled { rms: 0.0 },
            nightshade_imaging::Phd2Event::CalibrationComplete => {
                tracing::info!("PHD2: Calibration complete");
                GuidingEvent::CalibrationComplete
            }
            nightshade_imaging::Phd2Event::Disconnected => GuidingEvent::Disconnected,
            nightshade_imaging::Phd2Event::Alert {
                message,
                alert_type,
            } => {
                tracing::warn!("PHD2 Alert [{}]: {}", alert_type, message);
                return; // Alerts are not forwarded as GuidingEvent
            }
            nightshade_imaging::Phd2Event::Error(msg) => {
                tracing::error!("PHD2 Error: {}", msg);
                return; // Errors are not forwarded as GuidingEvent
            }
        };

        let severity = match &guiding_event {
            GuidingEvent::LostStar | GuidingEvent::Disconnected => EventSeverity::Warning,
            _ => EventSeverity::Info,
        };

        let event_id = get_state().publish_guiding_event(guiding_event.clone(), severity);
        tracing::info!(
            "PHD2: Published {:?} to event bus (event_id={}, subscribers={})",
            guiding_event,
            event_id,
            subscriber_count
        );
    });

    client
        .connect()
        .map_err(|e| NightshadeError::connection_failed("phd2_guider", format!("PHD2: {}", e)))?;

    // Store the client
    let mut storage = get_phd2_storage().write().await;
    *storage = Some(client);

    // Register PHD2 as a connected guider device in AppState
    // This ensures api_get_connected_devices() returns the guider
    let phd2_device_info = DeviceInfo {
        id: "phd2_guider".to_string(),
        name: "PHD2".to_string(),
        device_type: DeviceType::Guider,
        driver_type: DriverType::Native,
        description: format!("PHD2 Guiding at {}:{}", host, port),
        driver_version: String::new(),
        serial_number: None,
        unique_id: None,
        display_name: "PHD2 Guiding".to_string(),
    };
    get_state()
        .register_device(phd2_device_info, ConnectionState::Connected)
        .await;

    // Publish event
    get_state().publish_guiding_event(GuidingEvent::Connected, EventSeverity::Info);

    Ok(())
}

/// Disconnect from PHD2
pub async fn api_phd2_disconnect() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    if let Some(mut client) = storage.take() {
        client.disconnect();
    }

    // Remove PHD2 from connected devices in AppState
    get_state()
        .remove_device(DeviceType::Guider, "phd2_guider")
        .await;

    get_state().publish_guiding_event(GuidingEvent::Disconnected, EventSeverity::Info);

    Ok(())
}

/// Start guiding in PHD2
pub async fn api_phd2_start_guiding(
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .guide(settle_pixels, settle_time, settle_timeout)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to start guiding: {}", e)))?;

    get_state().publish_guiding_event(GuidingEvent::GuidingStarted, EventSeverity::Info);

    Ok(())
}

/// Stop guiding in PHD2
pub async fn api_phd2_stop_guiding() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .stop_capture()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to stop guiding: {}", e)))?;

    get_state().publish_guiding_event(GuidingEvent::GuidingStopped, EventSeverity::Info);

    Ok(())
}

/// Dither in PHD2
pub async fn api_phd2_dither(
    amount: f64,
    ra_only: u8,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    let ra_only_bool = ra_only != 0;
    client
        .dither(
            amount,
            ra_only_bool,
            settle_pixels,
            settle_time,
            settle_timeout,
        )
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to dither: {}", e)))?;

    get_state().publish_guiding_event(
        GuidingEvent::DitherStarted { pixels: amount },
        EventSeverity::Info,
    );

    Ok(())
}

/// Get PHD2 status
pub async fn api_phd2_get_status() -> Result<Phd2Status, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    let state = client.get_app_state().map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get PHD2 state: {}", e))
    })?;

    let pixel_scale = client.get_pixel_scale().unwrap_or(0.0);

    // Why: forward the raw PHD2 state name when unrecognised so the desktop
    // UI can render "PHD2 says: GuidingPaused" instead of pretending
    // everything is fine. Known variants stay as &'static str literals;
    // Unknown owns its String, so we convert to String at the join point.
    let state_str: String = match state {
        nightshade_imaging::Phd2State::Disconnected => "Disconnected".to_string(),
        nightshade_imaging::Phd2State::Connected => "Connected".to_string(),
        nightshade_imaging::Phd2State::Calibrating => "Calibrating".to_string(),
        nightshade_imaging::Phd2State::Guiding => "Guiding".to_string(),
        nightshade_imaging::Phd2State::Looping => "Looping".to_string(),
        nightshade_imaging::Phd2State::Paused => "Paused".to_string(),
        nightshade_imaging::Phd2State::Settling => "Settling".to_string(),
        nightshade_imaging::Phd2State::LostLock => "LostLock".to_string(),
        nightshade_imaging::Phd2State::Unknown(raw) => raw,
    };

    Ok(Phd2Status {
        connected: true,
        state: state_str,
        rms_ra: 0.0, // Would need to track from events
        rms_dec: 0.0,
        rms_total: 0.0,
        snr: 0.0,
        star_mass: 0.0,
        pixel_scale,
    })
}

/// Get PHD2 star image with metadata
pub async fn api_phd2_get_star_image(size: u32) -> Result<Phd2StarImage, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    let image_data = client.get_star_image_data(size).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get star image: {}", e))
    })?;

    Ok(Phd2StarImage {
        frame: image_data.frame,
        width: image_data.width,
        height: image_data.height,
        star_x: image_data.star_x,
        star_y: image_data.star_y,
        pixels: image_data.pixels,
    })
}

/// Get PHD2 algorithm parameter names for an axis
pub async fn api_phd2_get_algo_param_names(axis: String) -> Result<Vec<String>, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client.get_algo_param_names(&axis).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get algo param names: {}", e))
    })
}

/// Get PHD2 algorithm parameter value
pub async fn api_phd2_get_algo_param(axis: String, name: String) -> Result<f64, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .get_algo_param(&axis, &name)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to get algo param: {}", e)))
}

/// Set PHD2 algorithm parameter value
pub async fn api_phd2_set_algo_param(
    axis: String,
    name: String,
    value: f64,
) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .set_algo_param(&axis, &name, value)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to set algo param: {}", e)))
}

/// Get all PHD2 algorithm parameters for an axis
pub async fn api_phd2_get_all_algo_params(
    axis: String,
) -> Result<Vec<Phd2AlgoParam>, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    let params = client.get_all_algo_params(&axis).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get all algo params: {}", e))
    })?;

    Ok(params
        .into_iter()
        .map(|p| Phd2AlgoParam {
            name: p.name,
            value: p.value,
        })
        .collect())
}

/// Pause or resume PHD2 guiding
pub async fn api_phd2_set_paused(paused: bool) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .set_paused(paused)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to set paused: {}", e)))?;

    get_state().publish_guiding_event(
        if paused {
            GuidingEvent::Paused
        } else {
            GuidingEvent::Resumed
        },
        EventSeverity::Info,
    );

    Ok(())
}

/// Clear PHD2 calibration
pub async fn api_phd2_clear_calibration(which: String) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client.clear_calibration(&which).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to clear calibration: {}", e))
    })
}

/// Flip PHD2 calibration (after meridian flip)
pub async fn api_phd2_flip_calibration() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .flip_calibration()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to flip calibration: {}", e)))
}

/// Get PHD2 calibration data
/// Returns calibration info including whether calibrated and calibration parameters
pub async fn api_phd2_get_calibration_data() -> Result<Phd2CalibrationData, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    // Get calibration data for both axes - "both" returns combined info
    let result = client.get_calibration_data("both").map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get calibration data: {}", e))
    })?;

    // PHD2 returns null if not calibrated, otherwise returns calibration parameters
    let is_calibrated = !result.is_null();

    // Extract calibration parameters if available
    let (ra_angle, dec_angle, ra_rate, dec_rate) = if is_calibrated {
        let xangle = result.get("xAngle").and_then(|v| v.as_f64());
        let yangle = result.get("yAngle").and_then(|v| v.as_f64());
        let xrate = result.get("xRate").and_then(|v| v.as_f64());
        let yrate = result.get("yRate").and_then(|v| v.as_f64());
        (xangle, yangle, xrate, yrate)
    } else {
        (None, None, None, None)
    };

    Ok(Phd2CalibrationData {
        is_calibrated,
        ra_angle,
        dec_angle,
        ra_rate,
        dec_rate,
    })
}

/// Find a guide star automatically
pub async fn api_phd2_find_star() -> Result<(f64, f64), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .find_star()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to find star: {}", e)))
}

/// Set guide star lock position
pub async fn api_phd2_set_lock_position(
    x: f64,
    y: f64,
    exact: bool,
) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client.set_lock_position(x, y, exact).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to set lock position: {}", e))
    })
}

/// Get current guide star lock position
pub async fn api_phd2_get_lock_position() -> Result<(f64, f64), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client.get_lock_position().map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get lock position: {}", e))
    })
}

/// Start looping exposures (without guiding)
pub async fn api_phd2_loop() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .loop_exposures()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to start looping: {}", e)))
}

/// Deselect the current guide star
pub async fn api_phd2_deselect_star() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .deselect_star()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to deselect star: {}", e)))
}

/// Get PHD2 guide exposure time (ms)
pub async fn api_phd2_get_exposure() -> Result<u32, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .get_exposure()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to get exposure: {}", e)))
}

/// Set PHD2 guide exposure time (ms)
pub async fn api_phd2_set_exposure(exposure_ms: u32) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .set_exposure(exposure_ms)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to set exposure: {}", e)))
}

/// Get current PHD2 profile name
pub async fn api_phd2_get_profile() -> Result<String, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .get_profile()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to get profile: {}", e)))
}

/// Launch PHD2 application
pub fn api_launch_phd2() -> Result<(), NightshadeError> {
    nightshade_imaging::launch_phd2()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to launch PHD2: {}", e)))
}

pub async fn api_guider_start_guiding(
    device_id: String,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_start_guiding(settle_pixels, settle_time, settle_timeout).await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::start_guiding(settle_pixels, settle_time, settle_timeout)
            .await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_stop(device_id: String) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_stop_guiding().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::stop().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_dither(
    device_id: String,
    amount: f64,
    ra_only: u8,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_dither(amount, ra_only, settle_pixels, settle_time, settle_timeout).await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::dither(
            amount,
            ra_only != 0,
            settle_pixels,
            settle_time,
            settle_timeout,
        )
        .await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_loop(device_id: String) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_loop().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::loop_exposures().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_find_star(device_id: String) -> Result<(f64, f64), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_find_star().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::find_star().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_set_lock_position(
    device_id: String,
    x: f64,
    y: f64,
    exact: bool,
) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_set_lock_position(x, y, exact).await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::set_lock_position(x, y).await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_get_lock_position(
    device_id: String,
) -> Result<(f64, f64), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_get_lock_position().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::get_lock_position().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_deselect_star(device_id: String) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_deselect_star().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::deselect_star().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_get_star_image(
    device_id: String,
    size: u32,
) -> Result<Phd2StarImage, NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_get_star_image(size).await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::get_star_image(size).await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_get_status(device_id: String) -> Result<Phd2Status, NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_get_status().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::get_status().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

// =============================================================================
// BUILT-IN GUIDER CONFIGURATION
// =============================================================================

/// Get the current built-in guider configuration.
/// Returns a flat struct with all configurable parameters.
pub async fn api_builtin_guider_get_config() -> Result<BuiltinGuiderConfig, NightshadeError> {
    let config = crate::builtin_guider::get_config().await;
    Ok(BuiltinGuiderConfig {
        exposure_secs: config.exposure_secs,
        gain: config.gain,
        offset: config.offset,
        binning: config.binning,
        calibration_ms: config.calibration_ms,
        settle_sleep_ms: config.settle_sleep_ms,
        min_pulse_ms: config.min_pulse_ms,
        max_pulse_ms: config.max_pulse_ms,
    })
}

/// Set the built-in guider configuration.
/// Can be called while guiding is active; changes apply to subsequent frames.
pub async fn api_builtin_guider_set_config(
    exposure_secs: f64,
    gain: i32,
    offset: i32,
    binning: i32,
    calibration_ms: u32,
    settle_sleep_ms: u64,
    min_pulse_ms: f64,
    max_pulse_ms: f64,
) -> Result<(), NightshadeError> {
    let config = crate::builtin_guider::GuiderConfig {
        exposure_secs,
        gain,
        offset,
        binning,
        calibration_ms,
        settle_sleep_ms,
        min_pulse_ms,
        max_pulse_ms,
    };
    crate::builtin_guider::set_config(config).await;
    Ok(())
}

/// FRB-friendly struct for the built-in guider configuration.
#[derive(Clone, Debug)]
pub struct BuiltinGuiderConfig {
    pub exposure_secs: f64,
    pub gain: i32,
    pub offset: i32,
    pub binning: i32,
    pub calibration_ms: u32,
    pub settle_sleep_ms: u64,
    pub min_pulse_ms: f64,
    pub max_pulse_ms: f64,
}

// =============================================================================
// SEQUENCER API
// =============================================================================

use nightshade_sequencer::{
    mosaic::calculate_mosaic_panels, mosaic::MosaicPanel, AutofocusConfig, AutofocusMethod,
    Binning, CenterConfig, CoolConfig, DelayConfig, DitherConfig, DitherPattern, ExecutorEvent,
    ExecutorState, ExposureConfig, FilterConfig, LoopCondition, LoopConfig, MosaicConfig,
    NodeDefinition, NodeStatus, NodeType, NotificationConfig, NotificationLevel, RotatorConfig,
    ScriptConfig, SequenceDefinition, SequenceProgress, SlewConfig, TargetGroupConfig,
    TargetHeaderConfig, TwilightType, WaitTimeConfig, WarmConfig,
};

/// Get the global sequence executor instance
fn get_sequence_executor(
) -> &'static std::sync::Arc<tokio::sync::RwLock<nightshade_sequencer::SequenceExecutor>> {
    nightshade_sequencer::get_executor()
}

/// Sequencer state for Flutter
#[derive(Debug, Clone)]
pub struct SequencerState {
    pub state: String,
    pub current_node_id: Option<String>,
    pub current_node_name: Option<String>,
    pub total_exposures: u32,
    pub completed_exposures: u32,
    pub total_integration_secs: f64,
    pub elapsed_secs: f64,
    pub estimated_remaining_secs: Option<f64>,
    pub current_target: Option<String>,
    pub current_filter: Option<String>,
    pub message: Option<String>,
}

impl From<SequenceProgress> for SequencerState {
    fn from(p: SequenceProgress) -> Self {
        let state_str = match p.state {
            ExecutorState::Idle => "idle",
            ExecutorState::Running => "running",
            ExecutorState::Paused => "paused",
            ExecutorState::Stopping => "stopping",
            ExecutorState::Cancelled => "cancelled",
            ExecutorState::Completed => "completed",
            ExecutorState::Failed => "failed",
        };
        Self {
            state: state_str.to_string(),
            current_node_id: p.current_node_id,
            current_node_name: p.current_node_name,
            total_exposures: p.total_exposures,
            completed_exposures: p.completed_exposures,
            total_integration_secs: p.total_integration_secs,
            elapsed_secs: p.elapsed_secs,
            estimated_remaining_secs: p.estimated_remaining_secs,
            current_target: p.current_target,
            current_filter: p.current_filter,
            message: p.message,
        }
    }
}

/// Sequence definition for Flutter
#[derive(Debug, Clone)]
pub struct SequenceDefinitionApi {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub nodes: Vec<NodeDefinitionApi>,
    pub root_node_id: Option<String>,
}

/// Node definition for Flutter
#[derive(Debug, Clone)]
pub struct NodeDefinitionApi {
    pub id: String,
    pub name: String,
    pub node_type: String,
    pub enabled: bool,
    pub children: Vec<String>,
    pub config_json: String,
}

impl From<&NodeDefinition> for NodeDefinitionApi {
    fn from(n: &NodeDefinition) -> Self {
        let node_type = match &n.node_type {
            NodeType::TargetGroup(_) => "target_group",
            NodeType::TargetHeader(_) => "target_header",
            NodeType::Loop(_) => "loop",
            NodeType::Parallel(_) => "parallel",
            NodeType::Conditional(_) => "conditional",
            NodeType::Recovery(_) => "recovery",
            NodeType::SlewToTarget(_) => "slew",
            NodeType::CenterTarget(_) => "center",
            NodeType::TakeExposure(_) => "exposure",
            NodeType::Autofocus(_) => "autofocus",
            NodeType::Dither(_) => "dither",
            NodeType::ChangeFilter(_) => "filter_change",
            NodeType::CoolCamera(_) => "cool_camera",
            NodeType::WarmCamera(_) => "warm_camera",
            NodeType::PolarAlignment(_) => "polar_alignment",
            NodeType::MoveRotator(_) => "rotator",
            NodeType::Park => "park",
            NodeType::Unpark => "unpark",
            NodeType::WaitForTime(_) => "wait_time",
            NodeType::Delay(_) => "delay",
            NodeType::Notification(_) => "notification",
            NodeType::RunScript(_) => "script",
            NodeType::MeridianFlip(_) => "meridian_flip",
            NodeType::OpenDome(_) => "open_dome",
            NodeType::CloseDome(_) => "close_dome",
            NodeType::ParkDome(_) => "park_dome",
            NodeType::StartGuiding(_) => "start_guiding",
            NodeType::StopGuiding => "stop_guiding",
            NodeType::TemperatureCompensation(_) => "temperature_compensation",
            NodeType::Mosaic(_) => "mosaic",
            NodeType::FlatWizard(_) => "flat_wizard",
            NodeType::OpenCover(_) => "open_cover",
            NodeType::CloseCover(_) => "close_cover",
            NodeType::CalibratorOn(_) => "calibrator_on",
            NodeType::CalibratorOff(_) => "calibrator_off",
        };

        let config_json = match serde_json::to_string(&n.node_type) {
            Ok(json) => json,
            Err(e) => {
                tracing::error!("Failed to serialize node type for node '{}': {}", n.id, e);
                format!("{{\"error\":\"serialization failed: {}\"}}", e)
            }
        };

        Self {
            id: n.id.clone(),
            name: n.name.clone(),
            node_type: node_type.to_string(),
            enabled: n.enabled,
            children: n.children.clone(),
            config_json,
        }
    }
}

/// Load a sequence from JSON
pub async fn api_sequencer_load_json(json: String) -> Result<(), NightshadeError> {
    tracing::info!("Loading sequence from JSON");

    let definition: SequenceDefinition = serde_json::from_str(&json).map_err(|e| {
        NightshadeError::InvalidInput(format!("Failed to parse sequence JSON: {}", e))
    })?;

    let mut executor = get_sequence_executor().write().await;
    executor
        .load_sequence(definition)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to load sequence: {}", e)))?;

    tracing::info!("Sequence loaded successfully");
    Ok(())
}

/// Load a sequence from a definition struct
pub async fn api_sequencer_load(definition: SequenceDefinitionApi) -> Result<(), NightshadeError> {
    tracing::info!("Loading sequence: {}", definition.name);

    // Convert API nodes to internal nodes
    let nodes: Result<Vec<NodeDefinition>, NightshadeError> = definition
        .nodes
        .iter()
        .map(|n| {
            let node_type: NodeType = serde_json::from_str(&n.config_json).map_err(|e| {
                NightshadeError::InvalidInput(format!("Invalid node config: {}", e))
            })?;

            Ok(NodeDefinition {
                id: n.id.clone(),
                name: n.name.clone(),
                node_type,
                enabled: n.enabled,
                children: n.children.clone(),
            })
        })
        .collect();

    let internal_definition = SequenceDefinition {
        id: definition.id,
        name: definition.name,
        description: definition.description,
        nodes: nodes?,
        root_node_id: definition.root_node_id,
        metadata: std::collections::HashMap::new(),
    };

    let mut executor = get_sequence_executor().write().await;
    executor
        .load_sequence(internal_definition)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to load sequence: {}", e)))?;

    Ok(())
}

/// Start the sequence executor
pub async fn api_sequencer_start() -> Result<(), NightshadeError> {
    tracing::info!("Starting sequence execution");

    let mut executor = get_sequence_executor().write().await;
    executor.start().await.map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to start sequence: {}", e))
    })?;

    // Publish event
    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::Sequencer,
        EventPayload::Sequencer(SequencerEvent::Started {
            sequence_name: "Sequence".to_string(),
        }),
    ));

    Ok(())
}

/// Pause the sequence executor
pub async fn api_sequencer_pause() -> Result<(), NightshadeError> {
    tracing::info!("Pausing sequence execution");

    let executor = get_sequence_executor().read().await;
    executor.pause().await.map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to pause sequence: {}", e))
    })?;

    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::Sequencer,
        EventPayload::Sequencer(SequencerEvent::Paused),
    ));

    Ok(())
}

/// Resume the sequence executor
pub async fn api_sequencer_resume() -> Result<(), NightshadeError> {
    tracing::info!("Resuming sequence execution");

    let executor = get_sequence_executor().read().await;
    executor.resume().await.map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to resume sequence: {}", e))
    })?;

    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::Sequencer,
        EventPayload::Sequencer(SequencerEvent::Resumed),
    ));

    Ok(())
}

/// Stop the sequence executor
pub async fn api_sequencer_stop() -> Result<(), NightshadeError> {
    tracing::info!("Stopping sequence execution");

    let mut executor = get_sequence_executor().write().await;
    executor
        .stop()
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to stop sequence: {}", e)))?;

    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::Sequencer,
        EventPayload::Sequencer(SequencerEvent::Stopped),
    ));

    Ok(())
}

/// Skip to the next instruction
pub async fn api_sequencer_skip() -> Result<(), NightshadeError> {
    tracing::info!("Skipping current instruction");

    let executor = get_sequence_executor().read().await;
    executor
        .skip()
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to skip: {}", e)))?;

    Ok(())
}

/// Reset the sequence executor
pub async fn api_sequencer_reset() -> Result<(), NightshadeError> {
    tracing::info!("Resetting sequence executor");

    let mut executor = get_sequence_executor().write().await;
    executor.reset().await;

    Ok(())
}

/// Get the current sequencer state
pub async fn api_sequencer_get_state() -> SequencerState {
    let executor = get_sequence_executor().read().await;
    let progress = executor.get_progress();
    SequencerState::from(progress)
}

/// Subscribe to sequencer events and forward them to the main event stream
pub async fn api_sequencer_subscribe_events() -> Result<(), NightshadeError> {
    // Validate the executor is reachable before spawning the supervisor so a
    // bad caller still gets an error synchronously. Drop the lock immediately
    // â€” the supervisor takes a fresh one on every restart.
    {
        let _executor = get_sequence_executor().read().await;
    }
    let state = get_state().clone();

    tracing::info!("[EVENT_SUB] Sequencer event subscription started");

    // The event bridge MUST stay alive for the lifetime of the UI; losing
    // it silently means the user sees zero sequencer updates with no error.
    // Supervise with restart-on-panic and exponential backoff.
    crate::util::supervisor::spawn_supervised_restart(
        "sequencer_event_bridge",
        crate::util::supervisor::RestartPolicy::DEFAULT,
        move || {
            let state = state.clone();
            async move {
                let mut rx = {
                    let executor = get_sequence_executor().read().await;
                    executor.subscribe()
                };
                tracing::info!("[EVENT_SUB] Event listener task spawned");
                run_sequencer_event_loop(&mut rx, &state).await;
            }
        },
        Some(|msg: &str| {
            tracing::error!(
                target: "supervisor",
                "sequencer_event_bridge exhausted restart budget; UI will stop receiving sequencer events. Last panic: {msg}"
            );
        }),
    );

    Ok(())
}

/// Inner event-loop body for [`api_sequencer_subscribe_events`].
/// Pulled out so the supervisor factory can call it on every restart.
async fn run_sequencer_event_loop(
    rx: &mut tokio::sync::broadcast::Receiver<ExecutorEvent>,
    state: &SharedAppState,
) {
    loop {
        let event = match rx.recv().await {
            Ok(ev) => ev,
            Err(tokio::sync::broadcast::error::RecvError::Lagged(skipped)) => {
                tracing::warn!(
                    "[EVENT_SUB] Lagged behind sequencer; skipped {} events",
                    skipped
                );
                continue;
            }
            Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                tracing::info!("[EVENT_SUB] Sequencer event channel closed; bridge exiting");
                return;
            }
        };
        {
            tracing::debug!(
                "[EVENT_SUB] Received event: {:?}",
                std::mem::discriminant(&event)
            );
            let nightshade_event = match &event {
                ExecutorEvent::StateChanged(s) => {
                    let _state_str = match s {
                        ExecutorState::Running => "running",
                        ExecutorState::Paused => "paused",
                        ExecutorState::Cancelled => "cancelled",
                        ExecutorState::Completed => "completed",
                        _ => continue,
                    };
                    Some(create_event_auto_id(
                        EventSeverity::Info,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(match s {
                            ExecutorState::Paused => SequencerEvent::Paused,
                            ExecutorState::Cancelled => SequencerEvent::Stopped,
                            ExecutorState::Completed => SequencerEvent::Completed,
                            _ => continue,
                        }),
                    ))
                }
                ExecutorEvent::NodeStarted { id, name } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::NodeStarted {
                        node_id: id.clone(),
                        node_type: name.clone(),
                    }),
                )),
                ExecutorEvent::NodeCompleted { id, status } => {
                    let status_str = match status {
                        NodeStatus::Success => "success",
                        NodeStatus::Failure => "failed",
                        NodeStatus::Skipped => "skipped",
                        _ => "failed",
                    };
                    let severity = match status {
                        NodeStatus::Failure => EventSeverity::Warning,
                        _ => EventSeverity::Info,
                    };
                    Some(create_event_auto_id(
                        severity,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::NodeCompleted {
                            node_id: id.clone(),
                            status: status_str.to_string(),
                        }),
                    ))
                }
                ExecutorEvent::ProgressUpdated(progress) => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::Progress {
                        current: progress.completed_exposures,
                        total: progress.total_exposures,
                    }),
                )),
                ExecutorEvent::SequenceCompleted => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::Completed),
                )),
                ExecutorEvent::SequenceFailed { error } => Some(create_event_auto_id(
                    EventSeverity::Error,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::Error {
                        message: error.clone(),
                    }),
                )),
                ExecutorEvent::ExposureStarted {
                    frame,
                    total,
                    filter,
                    duration_secs,
                } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::ExposureStarted {
                        frame: *frame,
                        total: *total,
                        filter: filter.clone(),
                        duration_secs: *duration_secs,
                    }),
                )),
                ExecutorEvent::ExposureCompleted {
                    frame,
                    total,
                    duration_secs,
                } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::ExposureCompleted {
                        frame: *frame,
                        total: *total,
                        duration_secs: *duration_secs,
                    }),
                )),
                ExecutorEvent::TargetStarted { name, ra, dec } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::TargetChanged {
                        target_name: name.clone(),
                        ra: Some(*ra),
                        dec: Some(*dec),
                    }),
                )),
                ExecutorEvent::TargetCompleted { name } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::TargetCompleted {
                        target_name: name.clone(),
                    }),
                )),
                ExecutorEvent::NodeProgress {
                    node_id,
                    instruction,
                    progress_percent,
                    detail,
                } => {
                    tracing::info!(
                        "[EVENT_SUB] NodeProgress received: node={}, instruction={}, progress={}%",
                        node_id,
                        instruction,
                        progress_percent
                    );
                    Some(create_event_auto_id(
                        EventSeverity::Info,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::InstructionProgress {
                            node_id: node_id.clone(),
                            instruction: instruction.clone(),
                            progress_percent: *progress_percent,
                            detail: detail.clone(),
                        }),
                    ))
                }
                ExecutorEvent::Error { message } => Some(create_event_auto_id(
                    EventSeverity::Error,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::Error {
                        message: message.clone(),
                    }),
                )),
                ExecutorEvent::TriggerFired {
                    trigger_id,
                    trigger_name,
                    action,
                } => {
                    tracing::info!(
                        "Trigger fired: {} ({}) - {}",
                        trigger_name,
                        trigger_id,
                        action
                    );
                    Some(create_event_auto_id(
                        EventSeverity::Info,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::TriggerFired {
                            trigger_id: trigger_id.clone(),
                            trigger_name: trigger_name.clone(),
                            action: action.clone(),
                        }),
                    ))
                }
                ExecutorEvent::RuntimeConfigUpdated { what } => {
                    // Audit Â§1.8: surface runtime-config updates as a generic
                    // sequencer Error event with informational severity so the
                    // existing UI subscriber sees the change without needing
                    // a new typed payload (a typed payload would require an
                    // FRB regen).
                    tracing::info!("[EVENT_SUB] Runtime config updated: {}", what);
                    Some(create_event_auto_id(
                        EventSeverity::Info,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::Error {
                            message: format!("Runtime config updated: {}", what),
                        }),
                    ))
                }
            };

            if let Some(e) = nightshade_event {
                state.publish_event(e);
            }
        }
    }
}

/// Stream of sequencer events (separate from main event stream for real-time progress)
#[flutter_rust_bridge::frb(ignore)]
pub fn api_sequencer_event_stream() -> impl futures::Stream<Item = String> {
    let rx = {
        let executor = get_sequence_executor().blocking_read();
        executor.subscribe()
    };

    async_stream::stream! {
        let mut rx = rx;
        loop {
            match rx.recv().await {
                Ok(event) => {
                    if let Ok(json) = serde_json::to_string(&event) {
                        yield json;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    // Update the global dropped event counter
                    let previous_total = TOTAL_DROPPED_EVENTS.fetch_add(n, Ordering::Relaxed);
                    let new_total = previous_total + n;

                    tracing::warn!(
                        "[SEQUENCER_EVENT_STREAM] Event stream lagged! Skipped {} events (total dropped: {}). \
                        Consider increasing buffer size or optimizing event handling.",
                        n, new_total
                    );
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    break;
                }
            }
        }
    }
}

// =============================================================================
// SEQUENCER CHECKPOINT / CRASH RECOVERY
// =============================================================================

/// Checkpoint info returned to Dart
#[derive(Debug, Clone)]
pub struct CheckpointInfoApi {
    pub sequence_name: String,
    pub timestamp: String,
    pub completed_exposures: u32,
    pub completed_integration_secs: f64,
    pub can_resume: bool,
    pub age_seconds: i64,
}

/// Set the checkpoint directory for crash recovery
pub async fn api_sequencer_set_checkpoint_dir(path: String) -> Result<(), NightshadeError> {
    tracing::info!("Setting checkpoint directory to: {}", path);
    let mut executor = get_sequence_executor().write().await;
    executor.set_checkpoint_dir(path);
    Ok(())
}

/// Check if a recoverable checkpoint exists
pub fn api_sequencer_has_checkpoint() -> bool {
    let executor = get_sequence_executor().blocking_read();
    executor.has_recoverable_checkpoint()
}

/// Get info about the current checkpoint
pub fn api_sequencer_get_checkpoint_info() -> Option<CheckpointInfoApi> {
    let executor = get_sequence_executor().blocking_read();
    executor
        .get_checkpoint_info()
        .map(|info| CheckpointInfoApi {
            sequence_name: info.sequence_name,
            timestamp: info.timestamp.to_rfc3339(),
            completed_exposures: info.completed_exposures,
            completed_integration_secs: info.completed_integration_secs,
            can_resume: info.can_resume,
            age_seconds: info.age_seconds,
        })
}

/// Resume sequence from checkpoint
pub async fn api_sequencer_resume_from_checkpoint() -> Result<(), NightshadeError> {
    tracing::info!("Resuming sequence from checkpoint");
    let mut executor = get_sequence_executor().write().await;

    // Set up device ops before resume - use UnifiedDeviceOps which routes through DeviceManager
    let ops = create_unified_device_ops();
    executor.set_device_ops(ops);

    executor
        .resume_from_checkpoint()
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Save current execution state as checkpoint
pub async fn api_sequencer_save_checkpoint() -> Result<(), NightshadeError> {
    tracing::info!("Saving checkpoint");
    let executor = get_sequence_executor().read().await;
    executor
        .save_checkpoint()
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Clear/discard checkpoint (call when sequence completes normally or user discards)
pub fn api_sequencer_clear_checkpoint() -> Result<(), NightshadeError> {
    tracing::info!("Clearing checkpoint");
    let executor = get_sequence_executor().blocking_read();
    executor
        .clear_checkpoint()
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set simulation mode (use mock devices instead of real hardware)
pub async fn api_sequencer_set_simulation_mode(enabled: bool) -> Result<(), NightshadeError> {
    tracing::info!("Setting sequencer simulation mode: {}", enabled);
    let mut executor = get_sequence_executor().write().await;

    // Production/release artifacts must not execute simulated hardware paths.
    if enabled && !cfg!(debug_assertions) {
        return Err(NightshadeError::NotSupported {
            device_id: "sequencer".to_string(),
            operation: "set_simulation_mode(true)".to_string(),
        });
    }

    if enabled {
        // Use NullDeviceOps for simulation
        executor.set_device_ops(std::sync::Arc::new(nightshade_sequencer::NullDeviceOps));
    } else {
        // Use UnifiedDeviceOps which routes through DeviceManager for real hardware
        let ops = create_unified_device_ops();
        executor.set_device_ops(ops);
    }

    Ok(())
}

/// Set connected devices for the sequencer
pub async fn api_sequencer_set_devices(
    camera_id: Option<String>,
    mount_id: Option<String>,
    focuser_id: Option<String>,
    filterwheel_id: Option<String>,
    rotator_id: Option<String>,
    filter_names: Option<Vec<String>>,
    filter_focus_offsets: Option<std::collections::HashMap<String, i32>>,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Setting sequencer devices: camera={:?}, mount={:?}, focuser={:?}, filterwheel={:?}, rotator={:?}, filter_names={:?}, filter_focus_offsets={:?}",
        camera_id, mount_id, focuser_id, filterwheel_id, rotator_id, filter_names, filter_focus_offsets
    );
    let filterwheel_for_names = filterwheel_id.clone();
    {
        let mut executor = get_sequence_executor().write().await;
        executor.set_devices(camera_id, mount_id, focuser_id, filterwheel_id, rotator_id);
        if let Some(offsets) = filter_focus_offsets {
            executor.set_filter_focus_offsets(offsets);
        }
    }

    if let Some(names) = filter_names {
        if names.is_empty() {
            return Err(NightshadeError::InvalidParameter(
                "filter_names was provided but empty; provide at least one name or pass null."
                    .to_string(),
            ));
        }

        let filterwheel_id = filterwheel_for_names.ok_or_else(|| {
            NightshadeError::InvalidParameter(
                "filter_names was provided but filterwheel_id is null. Provide a filter wheel ID before setting filter names."
                    .to_string(),
            )
        })?;

        let mgr = get_device_manager();
        mgr.filter_wheel_set_filter_names(&filterwheel_id, names)
            .await
            .map_err(|e| {
                NightshadeError::OperationFailed(format!(
                    "Failed to apply filter names to '{}': {}",
                    filterwheel_id, e
                ))
            })?;
    }

    Ok(())
}

/// Set the safety fail mode for the sequencer.
/// This determines behavior when safety devices fail or are unavailable:
/// - "fail_closed": Treat unavailable safety data as unsafe (enforced)
/// - "fail_open"/"warn_only": accepted for backward compatibility and coerced to fail_closed
pub async fn api_sequencer_set_safety_fail_mode(mode: String) -> Result<(), NightshadeError> {
    use nightshade_sequencer::SafetyFailMode;

    let mode_lower = mode.to_lowercase();
    let fail_mode = match mode_lower.as_str() {
        "fail_closed" | "failclosed" => SafetyFailMode::FailClosed,
        "fail_open" | "failopen" | "warn_only" | "warnonly" => {
            tracing::warn!(
                "Safety fail mode '{}' requested, but strict fail-closed is enforced; using fail_closed",
                mode
            );
            SafetyFailMode::FailClosed
        }
        _ => {
            return Err(NightshadeError::InvalidParameter(format!(
                "Invalid safety fail mode: '{}'. Must be 'fail_closed' (legacy aliases: 'fail_open', 'warn_only').",
                mode
            )));
        }
    };

    tracing::info!("Setting sequencer safety fail mode: {:?}", fail_mode);
    let mut executor = get_sequence_executor().write().await;
    executor.set_safety_fail_mode(fail_mode);

    Ok(())
}

/// Set the save path for sequencer images.
/// This is the base directory where captured images will be saved.
/// If not set (or set to None), images will NOT be saved to disk.
pub async fn api_sequencer_set_save_path(path: Option<String>) -> Result<(), NightshadeError> {
    let path_display = path.as_deref().unwrap_or("<none>");
    tracing::info!("Setting sequencer save path: {}", path_display);

    let mut executor = get_sequence_executor().write().await;
    executor.set_save_path(path.map(std::path::PathBuf::from));

    Ok(())
}

// =============================================================================
// SEQUENCER RUNTIME SETTINGS PROPAGATION
// =============================================================================

/// Update dither configuration at runtime while a sequence is running or paused.
/// The updated values are stored on the executor and will be used by subsequent
/// trigger-initiated dithers and checkpoint resumes.
pub async fn api_sequencer_update_dither_config(
    pixels: f64,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
    ra_only: bool,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Updating sequencer dither config: pixels={}, settle_pixels={}, settle_time={}, settle_timeout={}, ra_only={}",
        pixels, settle_pixels, settle_time, settle_timeout, ra_only
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_dither_config(pixels, settle_pixels, settle_time, settle_timeout, ra_only);
    Ok(())
}

/// Update observer location at runtime while a sequence is running or paused.
/// Updates the executor's stored latitude/longitude so altitude-based triggers
/// use the correct location on their next evaluation.
pub async fn api_sequencer_update_location(
    latitude: Option<f64>,
    longitude: Option<f64>,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Updating sequencer location: lat={:?}, lon={:?}",
        latitude,
        longitude
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_location(latitude, longitude);
    Ok(())
}

/// Update filter focus offsets at runtime while a sequence is running or paused.
/// Updates the executor's stored offsets so subsequent filter changes apply
/// the correct focus compensation.
pub async fn api_sequencer_update_filter_offsets(
    offsets: std::collections::HashMap<String, i32>,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Updating sequencer filter focus offsets: {} entries",
        offsets.len()
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_filter_offsets(offsets);
    Ok(())
}

// =============================================================================
// SEQUENCER NODE FACTORY - Create nodes programmatically
// =============================================================================

fn serialize_node_definition(node: &NodeDefinition) -> Result<String, NightshadeError> {
    serde_json::to_string(node).map_err(|e| {
        NightshadeError::SerializationError(format!(
            "Failed to serialize node '{}' ({}): {}",
            node.name, node.id, e
        ))
    })
}

fn serialize_sequence_definition(
    definition: &SequenceDefinition,
) -> Result<String, NightshadeError> {
    serde_json::to_string(definition).map_err(|e| {
        NightshadeError::SerializationError(format!(
            "Failed to serialize sequence '{}' ({}): {}",
            definition.name, definition.id, e
        ))
    })
}

/// Create an exposure node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_exposure_node(
    id: String,
    name: String,
    duration_secs: f64,
    count: u32,
    filter: Option<String>,
    filter_index: Option<i32>,
    gain: Option<i32>,
    offset: Option<i32>,
    binning: i32,
    dither_every: Option<u32>,
) -> Result<String, NightshadeError> {
    let binning_enum = match binning {
        1 => Binning::One,
        2 => Binning::Two,
        3 => Binning::Three,
        4 => Binning::Four,
        _ => Binning::One,
    };

    let config = ExposureConfig {
        duration_secs,
        count,
        filter,
        filter_index,
        gain,
        offset,
        binning: binning_enum,
        dither_every,
        dither_pixels: 5.0,
        dither_settle_pixels: 1.5,
        dither_settle_time: 30.0,
        dither_settle_timeout: 120.0,
        dither_ra_only: false,
        save_to: None,
        triggers: Vec::new(),
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::TakeExposure(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a slew node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_slew_node(
    id: String,
    name: String,
    use_target_coords: u8,
    custom_ra: Option<f64>,
    custom_dec: Option<f64>,
) -> Result<String, NightshadeError> {
    let config = SlewConfig {
        use_target_coords: use_target_coords != 0,
        custom_ra,
        custom_dec,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::SlewToTarget(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a center node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_center_node(
    id: String,
    name: String,
    use_target_coords: u8,
    accuracy_arcsec: f64,
    max_attempts: u32,
    exposure_duration: f64,
) -> Result<String, NightshadeError> {
    let config = CenterConfig {
        use_target_coords: use_target_coords != 0,
        custom_ra: None,
        custom_dec: None,
        accuracy_arcsec,
        max_attempts,
        exposure_duration,
        filter: None,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::CenterTarget(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create an autofocus node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_autofocus_node(
    id: String,
    name: String,
    step_size: i32,
    steps_out: u32,
    exposure_duration: f64,
    method: String,
) -> Result<String, NightshadeError> {
    let method_enum = match method.as_str() {
        "vcurve" => AutofocusMethod::VCurve,
        "quadratic" => AutofocusMethod::Quadratic,
        "hyperbolic" => AutofocusMethod::Hyperbolic,
        _ => AutofocusMethod::VCurve,
    };

    let config = AutofocusConfig {
        method: method_enum,
        step_size,
        steps_out,
        exposure_duration,
        filter: None,
        binning: Binning::One,
        max_duration_secs: 600.0,
        ..AutofocusConfig::default()
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Autofocus(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a filter change node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_filter_node(
    id: String,
    name: String,
    filter_name: String,
) -> Result<String, NightshadeError> {
    let config = FilterConfig {
        filter_name,
        filter_index: None,
        timeout_secs: None, // Use default timeout
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::ChangeFilter(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a target group node configuration (legacy - use target_header instead)
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_target_group_node(
    id: String,
    name: String,
    target_name: String,
    ra_hours: f64,
    dec_degrees: f64,
    rotation: Option<f64>,
    min_altitude: Option<f64>,
    max_altitude: Option<f64>,
    priority: i32,
    children: Vec<String>,
) -> Result<String, NightshadeError> {
    let config = TargetGroupConfig {
        target_name,
        ra_hours,
        dec_degrees,
        rotation,
        min_altitude,
        max_altitude,
        priority,
        ..Default::default()
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::TargetGroup(config),
        enabled: true,
        children,
    };

    serialize_node_definition(&node)
}

/// Create a target header node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_target_header_node(
    id: String,
    name: String,
    target_name: String,
    ra_hours: f64,
    dec_degrees: f64,
    rotation: Option<f64>,
    min_altitude: Option<f64>,
    max_altitude: Option<f64>,
    priority: i32,
    start_after: Option<i64>,
    end_before: Option<i64>,
    mosaic_panel_json: Option<String>,
    children: Vec<String>,
) -> Result<String, NightshadeError> {
    let mosaic_panel = mosaic_panel_json
        .map(|json| {
            serde_json::from_str(&json).map_err(|e| {
                NightshadeError::SerializationError(format!(
                    "Invalid target header mosaic panel JSON: {}",
                    e
                ))
            })
        })
        .transpose()?;

    let config = TargetHeaderConfig {
        target_name,
        ra_hours,
        dec_degrees,
        rotation,
        min_altitude,
        max_altitude,
        priority,
        start_after,
        end_before,
        mosaic_panel,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::TargetHeader(config),
        enabled: true,
        children,
    };

    serialize_node_definition(&node)
}

/// Create a loop node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_loop_node(
    id: String,
    name: String,
    iterations: Option<u32>,
    condition: String,
    children: Vec<String>,
) -> Result<String, NightshadeError> {
    let condition_enum = match condition.as_str() {
        "count" => LoopCondition::Count,
        "until_time" => LoopCondition::UntilTime,
        "altitude_below" => LoopCondition::AltitudeBelow,
        "altitude_above" => LoopCondition::AltitudeAbove,
        "integration_time" => LoopCondition::IntegrationTime,
        _ => LoopCondition::Count,
    };

    let config = LoopConfig {
        iterations,
        condition: condition_enum,
        condition_value: None,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Loop(config),
        enabled: true,
        children,
    };

    serialize_node_definition(&node)
}

/// Create a delay node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_delay_node(
    id: String,
    name: String,
    seconds: f64,
) -> Result<String, NightshadeError> {
    let config = DelayConfig { seconds };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Delay(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a park node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_park_node(id: String, name: String) -> Result<String, NightshadeError> {
    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Park,
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create an unpark node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_unpark_node(id: String, name: String) -> Result<String, NightshadeError> {
    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Unpark,
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a cool camera node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_cool_camera_node(
    id: String,
    name: String,
    target_temp: f64,
    duration_mins: Option<f64>,
) -> Result<String, NightshadeError> {
    let config = CoolConfig {
        target_temp,
        duration_mins,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::CoolCamera(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a warm camera node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_warm_camera_node(
    id: String,
    name: String,
    rate_per_min: f64,
    target_temp: Option<f64>,
) -> Result<String, NightshadeError> {
    let config = WarmConfig {
        rate_per_min,
        target_temp,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::WarmCamera(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a dither node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_dither_node(
    id: String,
    name: String,
    pixels: f64,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
    ra_only: u8,
) -> Result<String, NightshadeError> {
    let config = DitherConfig {
        pixels,
        settle_pixels,
        settle_time,
        settle_timeout,
        ra_only: ra_only != 0,
        pattern: DitherPattern::default(),
        grid_size: 3,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Dither(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a wait time node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_wait_time_node(
    id: String,
    name: String,
    wait_until: Option<i64>,
    twilight_type: Option<String>,
) -> Result<String, NightshadeError> {
    let twilight = twilight_type.and_then(|t| match t.as_str() {
        "civil" => Some(TwilightType::Civil),
        "nautical" => Some(TwilightType::Nautical),
        "astronomical" => Some(TwilightType::Astronomical),
        _ => None,
    });

    let config = WaitTimeConfig {
        wait_until,
        wait_for_twilight: twilight,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::WaitForTime(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a notification node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_notification_node(
    id: String,
    name: String,
    title: String,
    message: String,
    level: String,
) -> Result<String, NightshadeError> {
    let level_enum = match level.as_str() {
        "info" => NotificationLevel::Info,
        "warning" => NotificationLevel::Warning,
        "error" => NotificationLevel::Error,
        "success" => NotificationLevel::Success,
        _ => NotificationLevel::Info,
    };

    let config = NotificationConfig {
        title,
        message,
        level: level_enum,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Notification(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a script node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_script_node(
    id: String,
    name: String,
    script_path: String,
    arguments: Vec<String>,
    timeout_secs: Option<u32>,
) -> Result<String, NightshadeError> {
    let config = ScriptConfig {
        script_path,
        arguments,
        timeout_secs,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::RunScript(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a rotator node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_rotator_node(
    id: String,
    name: String,
    target_angle: f64,
    relative: u8,
) -> Result<String, NightshadeError> {
    let config = RotatorConfig {
        target_angle,
        relative: relative != 0,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::MoveRotator(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Build a complete sequence definition from nodes
#[flutter_rust_bridge::frb(sync)]
pub fn api_build_sequence(
    id: String,
    name: String,
    description: Option<String>,
    node_jsons: Vec<String>,
    root_node_id: Option<String>,
) -> Result<String, NightshadeError> {
    let nodes: Result<Vec<NodeDefinition>, NightshadeError> = node_jsons
        .iter()
        .enumerate()
        .map(|(index, json)| {
            serde_json::from_str(json).map_err(|e| {
                NightshadeError::SerializationError(format!(
                    "Failed to deserialize node_jsons[{}]: {}",
                    index, e
                ))
            })
        })
        .collect();

    let definition = SequenceDefinition {
        id,
        name,
        description,
        nodes: nodes?,
        root_node_id,
        metadata: std::collections::HashMap::new(),
    };

    serialize_sequence_definition(&definition)
}

#[cfg(test)]
mod sequencer_node_factory_tests {
    use super::{
        api_build_sequence, api_create_filter_node, api_create_target_header_node, NodeDefinition,
        SequenceDefinition,
    };

    #[test]
    fn build_sequence_returns_error_for_invalid_node_json() {
        let err = api_build_sequence(
            "seq-1".to_string(),
            "Test".to_string(),
            None,
            vec!["{not-json}".to_string()],
            None,
        )
        .expect_err("invalid node JSON should be rejected");

        assert!(err
            .to_string()
            .contains("Failed to deserialize node_jsons[0]"));
    }

    #[test]
    fn target_header_rejects_invalid_mosaic_panel_json() {
        let err = api_create_target_header_node(
            "node-1".to_string(),
            "Target".to_string(),
            "M31".to_string(),
            0.5,
            41.0,
            None,
            None,
            None,
            1,
            None,
            None,
            Some("{invalid}".to_string()),
            vec![],
        )
        .expect_err("invalid mosaic JSON should be rejected");

        assert!(err
            .to_string()
            .contains("Invalid target header mosaic panel JSON"));
    }

    #[test]
    fn build_sequence_preserves_valid_nodes() {
        let filter_json =
            api_create_filter_node("node-1".to_string(), "Filter".to_string(), "L".to_string())
                .expect("filter node should serialize");

        let sequence_json = api_build_sequence(
            "seq-1".to_string(),
            "Test".to_string(),
            None,
            vec![filter_json],
            Some("node-1".to_string()),
        )
        .expect("valid sequence should serialize");

        let sequence: SequenceDefinition =
            serde_json::from_str(&sequence_json).expect("sequence JSON should deserialize");
        assert_eq!(sequence.nodes.len(), 1);

        let node: &NodeDefinition = &sequence.nodes[0];
        assert_eq!(node.id, "node-1");
    }
}

// =============================================================================
// Mosaic Calculation
// =============================================================================

/// Result structure for mosaic panel calculations (FFI-safe)
#[derive(Debug, Clone)]
pub struct MosaicPanelResult {
    pub ra_hours: f64,
    pub dec_degrees: f64,
    pub panel_index: u32,
    pub row: u32,
    pub col: u32,
}

impl From<MosaicPanel> for MosaicPanelResult {
    fn from(panel: MosaicPanel) -> Self {
        Self {
            ra_hours: panel.ra_hours,
            dec_degrees: panel.dec_degrees,
            panel_index: panel.panel_index,
            row: panel.row,
            col: panel.col,
        }
    }
}

/// Calculate mosaic panel positions given center coordinates and configuration
///
/// # Arguments
/// * `center_ra` - Center RA in hours (0-24)
/// * `center_dec` - Center Dec in degrees (-90 to +90)
/// * `panel_width_arcmin` - Panel width in arcminutes
/// * `panel_height_arcmin` - Panel height in arcminutes
/// * `overlap_percent` - Overlap percentage (0-50)
/// * `rotation` - Rotation angle in degrees
/// * `panels_horizontal` - Number of horizontal panels
/// * `panels_vertical` - Number of vertical panels
///
/// # Returns
/// Vector of MosaicPanelResult with calculated RA/Dec for each panel
#[flutter_rust_bridge::frb(sync)]
pub fn api_calculate_mosaic_panels(
    center_ra: f64,
    center_dec: f64,
    panel_width_arcmin: f64,
    panel_height_arcmin: f64,
    overlap_percent: f64,
    rotation: f64,
    panels_horizontal: u32,
    panels_vertical: u32,
) -> Vec<MosaicPanelResult> {
    let config = MosaicConfig {
        center_ra,
        center_dec,
        panel_width_arcmin,
        panel_height_arcmin,
        overlap_percent,
        rotation,
        panels_horizontal,
        panels_vertical,
        ..MosaicConfig::default()
    };

    calculate_mosaic_panels(&config)
        .into_iter()
        .map(MosaicPanelResult::from)
        .collect()
}

/// Calculate total mosaic coverage area in square degrees
#[flutter_rust_bridge::frb(sync)]
pub fn api_calculate_mosaic_area(
    panel_width_arcmin: f64,
    panel_height_arcmin: f64,
    panels_horizontal: u32,
    panels_vertical: u32,
) -> f64 {
    let total_width_arcmin = panel_width_arcmin * panels_horizontal as f64;
    let total_height_arcmin = panel_height_arcmin * panels_vertical as f64;
    // Return in square degrees
    (total_width_arcmin / 60.0) * (total_height_arcmin / 60.0)
}

/// Estimate total imaging time for mosaic in seconds
///
/// # Arguments
/// * `total_panels` - Total number of panels
/// * `exposure_secs` - Exposure time per frame
/// * `exposures_per_panel` - Number of exposures per panel
/// * `overhead_per_panel_secs` - Overhead per panel (slew, center, settle) - defaults to 60s if 0
#[flutter_rust_bridge::frb(sync)]
pub fn api_estimate_mosaic_time(
    total_panels: u32,
    exposure_secs: f64,
    exposures_per_panel: u32,
    overhead_per_panel_secs: f64,
) -> f64 {
    let overhead = if overhead_per_panel_secs <= 0.0 {
        60.0
    } else {
        overhead_per_panel_secs
    };
    let time_per_panel = exposure_secs * exposures_per_panel as f64 + overhead;
    total_panels as f64 * time_per_panel
}

/// Calculate altitude for a target at a specific time and observer location
///
/// # Arguments
/// * `ra_hours` - Right Ascension in hours (0-24)
/// * `dec_degrees` - Declination in degrees (-90 to +90)
/// * `latitude` - Observer's latitude in degrees (-90 to +90, positive is north)
/// * `longitude` - Observer's longitude in degrees (-180 to +180, positive is east)
/// * `time_unix_millis` - UTC time as Unix timestamp in milliseconds
///
/// # Returns
/// Altitude in degrees above the horizon (-90 to +90)
#[flutter_rust_bridge::frb(sync)]
pub fn api_calculate_altitude(
    ra_hours: f64,
    dec_degrees: f64,
    latitude: f64,
    longitude: f64,
    time_unix_millis: i64,
) -> f64 {
    use chrono::{TimeZone, Utc};

    // Convert Unix milliseconds to DateTime<Utc>
    let time = Utc
        .timestamp_millis_opt(time_unix_millis)
        .single()
        .unwrap_or_else(|| Utc::now());

    nightshade_sequencer::meridian::calculate_altitude(
        ra_hours,
        dec_degrees,
        latitude,
        longitude,
        time,
    )
}

// =============================================================================
// Polar Alignment
// =============================================================================

use std::sync::atomic::{AtomicBool as PolarAtomicBool, Ordering as PolarOrdering};

/// Track whether polar alignment is running
static POLAR_ALIGN_RUNNING: OnceLock<PolarAtomicBool> = OnceLock::new();
static POLAR_ALIGN_CANCEL: OnceLock<PolarAtomicBool> = OnceLock::new();

fn get_polar_align_flag() -> &'static PolarAtomicBool {
    POLAR_ALIGN_RUNNING.get_or_init(|| PolarAtomicBool::new(false))
}

fn get_polar_align_cancel() -> &'static PolarAtomicBool {
    POLAR_ALIGN_CANCEL.get_or_init(|| PolarAtomicBool::new(false))
}

/// Emit a polar alignment status update (JSON-serializable for Dart)
fn emit_polar_status(status: &str, phase: &str, point: i32) {
    tracing::info!(
        "Polar alignment: {} (phase={}, point={})",
        status,
        phase,
        point
    );
    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::PolarAlignment,
        EventPayload::PolarAlignmentStatus(PolarAlignmentStatus {
            status: status.to_string(),
            phase: phase.to_string(),
            point,
        }),
    ));
}

/// Emit polar alignment error update
fn emit_polar_error(
    az: f64,
    alt: f64,
    total: f64,
    cur_ra: f64,
    cur_dec: f64,
    tgt_ra: f64,
    tgt_dec: f64,
) {
    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::PolarAlignment,
        EventPayload::PolarAlignment(PolarAlignmentEvent {
            azimuth_error: az,
            altitude_error: alt,
            total_error: total,
            current_ra: cur_ra,
            current_dec: cur_dec,
            target_ra: tgt_ra,
            target_dec: tgt_dec,
        }),
    ));
}

/// Emit polar alignment image for UI display
/// Encodes the display data to JPEG for efficient transmission
fn emit_polar_image(
    image: &CapturedImageResult,
    point: i32,
    phase: &str,
    solved_ra: Option<f64>,
    solved_dec: Option<f64>,
) {
    use image::ImageEncoder;

    // Encode display_data (RGBA) to JPEG
    let mut buffer = Vec::new();
    {
        let mut cursor = std::io::Cursor::new(&mut buffer);
        let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut cursor, 85);
        if let Err(e) = encoder.write_image(
            &image.display_data,
            image.width as u32,
            image.height as u32,
            image::ColorType::Rgba8,
        ) {
            tracing::warn!("Failed to encode polar alignment image: {}", e);
            return;
        }
    }
    let color_type = image::ColorType::Rgba8;
    let jpeg_data = buffer;

    tracing::debug!(
        "Emitting polar alignment image: {}x{}, {:?}, point={}, phase={}, solved={:?}",
        image.width,
        image.height,
        color_type,
        point,
        phase,
        solved_ra.is_some()
    );

    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::PolarAlignment,
        EventPayload::PolarAlignmentImage(PolarAlignmentImageEvent {
            image_data: jpeg_data,
            width: image.width as u32,
            height: image.height as u32,
            solved_ra,
            solved_dec,
            point,
            phase: phase.to_string(),
        }),
    ));
}

/// Start three-point polar alignment
///
/// This initiates the polar alignment process which will:
/// 1. Capture 3 images at different mount rotations
/// 2. Plate solve each image
/// 3. Calculate the center of rotation
/// 4. Enter adjustment mode with real-time error updates
///
/// Note: Requires connected camera and mount devices.
pub async fn api_start_polar_alignment(
    exposure_time: f64,
    step_size: f64,
    binning: i32,
    is_north: bool,
    manual_rotation: bool,
    rotate_east: bool,
    gain: Option<i32>,
    offset: Option<i32>,
    solve_timeout: Option<f64>,
    start_from_current: Option<bool>,
    auto_complete_threshold: Option<f64>,
) -> Result<(), NightshadeError> {
    // Check if already running
    if get_polar_align_flag().load(PolarOrdering::Relaxed) {
        return Err(NightshadeError::OperationFailed(
            "Polar alignment already running".to_string(),
        ));
    }

    get_polar_align_flag().store(true, PolarOrdering::Relaxed);
    get_polar_align_cancel().store(false, PolarOrdering::Relaxed);

    tracing::info!(
        "Starting polar alignment: exposure={}s, step={}Â°, binning={}, north={}, manual={}, east={}",
        exposure_time, step_size, binning, is_north, manual_rotation, rotate_east
    );

    // Get connected devices using existing API
    let connected = api_get_connected_devices().await;

    // Find connected camera
    let camera_id = connected
        .iter()
        .find(|d| d.device_type == DeviceType::Camera)
        .map(|d| d.id.clone());

    // Find connected mount
    let mount_id = connected
        .iter()
        .find(|d| d.device_type == DeviceType::Mount)
        .map(|d| d.id.clone());

    let camera_id = camera_id.ok_or_else(|| {
        get_polar_align_flag().store(false, PolarOrdering::Relaxed);
        NightshadeError::DeviceNotFound("No camera connected".to_string())
    })?;

    let mount_id = mount_id.ok_or_else(|| {
        get_polar_align_flag().store(false, PolarOrdering::Relaxed);
        NightshadeError::DeviceNotFound("No mount connected".to_string())
    })?;

    // Spawn background task for polar alignment
    let gain_val = gain.unwrap_or(0);
    let offset_val = offset.unwrap_or(0);
    let solve_timeout_val = solve_timeout.unwrap_or(60.0);
    let start_from_current_val = start_from_current.unwrap_or(true);
    let auto_complete_threshold_val = auto_complete_threshold.unwrap_or(1.0); // Default 1 arcminute

    crate::util::supervisor::spawn_supervised_oneshot(
        "polar_align_monitor",
        async move {
            let result = run_polar_alignment(
                camera_id,
                mount_id,
                exposure_time,
                step_size,
                binning,
                is_north,
                manual_rotation,
                rotate_east,
                start_from_current_val,
                gain_val,
                offset_val,
                solve_timeout_val,
                auto_complete_threshold_val,
            )
            .await;

            if let Err(e) = result {
                tracing::error!("Polar alignment failed: {}", e);
                emit_polar_status(&format!("Error: {}", e), "error", 0);
            }

            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
        },
        // If the polar-align task panics, the busy flag would otherwise
        // remain stuck `true` forever and the user could never restart it.
        // Clear the flag and surface the panic via the status channel.
        Some(|panic_msg: &str| {
            emit_polar_status(
                &format!("Polar alignment crashed: {panic_msg}"),
                "error",
                0,
            );
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
        }),
    );

    Ok(())
}

/// Internal function to run the polar alignment process
async fn run_polar_alignment(
    camera_id: String,
    mount_id: String,
    exposure_time: f64,
    step_size: f64,
    binning: i32,
    is_north: bool,
    manual_rotation: bool,
    rotate_east: bool,
    start_from_current: bool,
    gain: i32,
    offset: i32,
    solve_timeout_secs: f64,
    auto_complete_threshold: f64,
) -> Result<(), String> {
    if !start_from_current {
        return Err(
            "Polar alignment with start_from_current=false is not supported by this workflow"
                .to_string(),
        );
    }

    let mut solved_points: Vec<(f64, f64)> = Vec::new();

    // Phase 1: Capture and solve 3 points
    for point in 1..=3 {
        // Check for cancellation
        if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
            emit_polar_status("Cancelled by user", "idle", 0);
            return Ok(());
        }

        emit_polar_status(
            &format!("Capturing point {}/3...", point),
            "measuring",
            point as i32,
        );

        // Capture image using existing API
        // api_camera_start_exposure(device_id, duration_secs, gain, offset, bin_x, bin_y)
        api_camera_start_exposure(
            camera_id.clone(),
            exposure_time,
            gain,
            offset,
            binning,
            binning,
        )
        .await
        .map_err(|e| format!("Failed to capture: {:?}", e))?;

        if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
            emit_polar_status("Cancelled by user", "idle", 0);
            return Ok(());
        }

        emit_polar_status(
            &format!("Plate solving point {}/3...", point),
            "measuring",
            point as i32,
        );

        // Get the captured image
        let image = api_get_last_image(camera_id.clone())
            .await
            .map_err(|e| format!("Failed to get image: {:?}", e))?;

        // Emit polar alignment image (before plate solve, no coordinates yet)
        emit_polar_image(&image, point as i32, "measuring", None, None);

        // Save temp file for plate solving
        let temp_path = create_unique_temp_fits_path(&format!("polar_align_point_{}", point));
        let temp_path_str = temp_path.to_string_lossy().to_string();

        // Write FITS file for plate solving
        if let Err(e) = write_temp_fits_for_solve(&image, &temp_path_str) {
            return Err(format!("Failed to write temp FITS: {}", e));
        }

        // Plate solve with configurable timeout
        let solve_future = api_plate_solve_blind(temp_path_str.clone());
        let solve_result = match tokio::time::timeout(
            tokio::time::Duration::from_secs_f64(solve_timeout_secs),
            solve_future,
        )
        .await
        {
            Ok(Ok(result)) => result,
            Ok(Err(e)) => {
                let _ = std::fs::remove_file(&temp_path);
                return Err(format!("Plate solve error: {:?}", e));
            }
            Err(_) => {
                let _ = std::fs::remove_file(&temp_path);
                return Err(format!(
                    "Plate solve timed out after {:.1} seconds for point {}",
                    solve_timeout_secs, point
                ));
            }
        };

        // Clean up temp file
        let _ = std::fs::remove_file(&temp_path);

        if solve_result.success {
            let ra_degrees = solve_result.ra * 15.0; // RA hours to degrees
            solved_points.push((ra_degrees, solve_result.dec));
            tracing::info!(
                "Point {} solved: RA={:.4}h ({:.4}Â°), Dec={:.4}Â°",
                point,
                solve_result.ra,
                ra_degrees,
                solve_result.dec
            );

            // Emit image again with plate solve coordinates
            emit_polar_image(
                &image,
                point as i32,
                "measuring",
                Some(ra_degrees),
                Some(solve_result.dec),
            );
        } else {
            return Err(format!(
                "Plate solve failed for point {}: {:?}",
                point, solve_result.error
            ));
        }

        // Rotate mount for next point (if not last point)
        if point < 3 {
            if manual_rotation {
                emit_polar_status(
                    &format!("Rotate mount {}Â° and wait...", step_size as i32),
                    "measuring",
                    point as i32,
                );
                // Wait for user to rotate manually
                tokio::time::sleep(tokio::time::Duration::from_secs(15)).await;
            } else {
                emit_polar_status(
                    &format!("Slewing to point {}...", point + 1),
                    "measuring",
                    point as i32,
                );

                // Calculate new position (in degrees)
                // Safe to get last() because we just pushed to solved_points above
                let (current_ra_deg, current_dec) = match solved_points.last() {
                    Some(coords) => coords,
                    None => {
                        return Err("No solved points available for slew calculation".to_string());
                    }
                };
                let move_amount = if rotate_east { step_size } else { -step_size };
                let target_ra_deg = (current_ra_deg + move_amount + 360.0) % 360.0;

                // Slew mount (API takes RA in hours, Dec in degrees)
                api_mount_slew_to_coordinates(mount_id.clone(), target_ra_deg / 15.0, *current_dec)
                    .await
                    .map_err(|e| format!("Failed to slew: {:?}", e))?;

                // Wait for slew to complete
                tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
            }
        }
    }

    // Phase 2: Calculate center of rotation
    emit_polar_status("Calculating polar alignment error...", "adjusting", 3);

    let (mut center_ra, mut center_dec) = calculate_rotation_center(&solved_points);
    let pole_dec = if is_north { 90.0 } else { -90.0 };

    tracing::info!(
        "Rotation center: RA={:.4}Â°, Dec={:.4}Â°",
        center_ra,
        center_dec
    );

    // Geometric validation: check if calculated center is within 15Â° of expected pole
    let dec_diff = (center_dec - pole_dec).abs();
    if dec_diff > 15.0 {
        let error_msg = format!(
            "Calculated rotation center (Dec={:.2}Â°) is {:.1}Â° away from expected pole (Dec={:.0}Â°). \
            This suggests poor plate solves or insufficient mount rotation. \
            Please ensure: 1) Clear view of pole area, 2) Mount rotates at least {}Â° between points, \
            3) Plate solving is accurate. Try increasing step size or checking camera focus.",
            center_dec, dec_diff, pole_dec, step_size
        );
        tracing::error!("{}", error_msg);
        emit_polar_status(&format!("Error: {}", error_msg), "error", 0);
        return Err(error_msg);
    }

    // Phase 3: Adjustment loop - continuously update error with rolling recalculation
    emit_polar_status("Adjustment mode - make corrections", "adjusting", 0);

    // Auto-complete timer: tracks when error first dropped below threshold
    let mut auto_complete_start: Option<std::time::Instant> = None;
    const AUTO_COMPLETE_DURATION_SECS: u64 = 3;

    let mut consecutive_failures = 0;
    const MAX_FAILURES: i32 = 5;

    loop {
        if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
            emit_polar_status("Stopped", "idle", 0);
            return Ok(());
        }

        // Capture and solve to get current position
        emit_polar_status("Capturing...", "adjusting", 0);
        if let Err(e) = api_camera_start_exposure(
            camera_id.clone(),
            exposure_time,
            gain,
            offset,
            binning,
            binning,
        )
        .await
        {
            consecutive_failures += 1;
            tracing::warn!("Capture failed in adjustment loop: {:?}", e);
            emit_polar_status(
                &format!(
                    "Capture failed: {:?} (retry {}/{})",
                    e, consecutive_failures, MAX_FAILURES
                ),
                "adjusting",
                0,
            );
            if consecutive_failures >= MAX_FAILURES {
                return Err(format!(
                    "Too many consecutive failures ({}) in adjustment loop",
                    MAX_FAILURES
                ));
            }
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
            continue;
        }

        if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
            emit_polar_status("Stopped", "idle", 0);
            return Ok(());
        }

        // Get the captured image
        let image = match api_get_last_image(camera_id.clone()).await {
            Ok(img) => img,
            Err(e) => {
                consecutive_failures += 1;
                tracing::warn!("Failed to get image in adjustment loop: {:?}", e);
                emit_polar_status(
                    &format!(
                        "Image retrieval failed (retry {}/{})",
                        consecutive_failures, MAX_FAILURES
                    ),
                    "adjusting",
                    0,
                );
                if consecutive_failures >= MAX_FAILURES {
                    return Err(format!(
                        "Too many consecutive failures ({}) in adjustment loop",
                        MAX_FAILURES
                    ));
                }
                tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                continue;
            }
        };

        // Emit polar alignment image (adjustment phase, no coordinates yet)
        emit_polar_image(&image, 0, "adjusting", None, None);

        let temp_path = create_unique_temp_fits_path("polar_align_adjust");
        let temp_path_str = temp_path.to_string_lossy().to_string();

        if let Err(e) = write_temp_fits_for_solve(&image, &temp_path_str) {
            consecutive_failures += 1;
            tracing::warn!("Failed to write temp FITS: {}", e);
            emit_polar_status(
                &format!(
                    "FITS write failed (retry {}/{})",
                    consecutive_failures, MAX_FAILURES
                ),
                "adjusting",
                0,
            );
            if consecutive_failures >= MAX_FAILURES {
                return Err(format!(
                    "Too many consecutive failures ({}) in adjustment loop",
                    MAX_FAILURES
                ));
            }
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
            continue;
        }

        emit_polar_status("Solving...", "adjusting", 0);

        // Plate solve with 30 second timeout (shorter for adjustment loop)
        let solve_future = api_plate_solve_blind(temp_path_str.clone());
        let solve_result =
            match tokio::time::timeout(tokio::time::Duration::from_secs(30), solve_future).await {
                Ok(Ok(result)) => {
                    let _ = std::fs::remove_file(&temp_path);
                    result
                }
                Ok(Err(e)) => {
                    let _ = std::fs::remove_file(&temp_path);
                    consecutive_failures += 1;
                    tracing::warn!("Plate solve error in adjustment loop: {:?}", e);
                    emit_polar_status(
                        &format!(
                            "Solve failed: {:?} (retry {}/{})",
                            e, consecutive_failures, MAX_FAILURES
                        ),
                        "adjusting",
                        0,
                    );
                    if consecutive_failures >= MAX_FAILURES {
                        return Err(format!(
                            "Too many consecutive failures ({}) in adjustment loop",
                            MAX_FAILURES
                        ));
                    }
                    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                    continue;
                }
                Err(_) => {
                    let _ = std::fs::remove_file(&temp_path);
                    consecutive_failures += 1;
                    tracing::warn!("Plate solve timed out in adjustment loop");
                    emit_polar_status(
                        &format!(
                            "Solve timed out (retry {}/{})",
                            consecutive_failures, MAX_FAILURES
                        ),
                        "adjusting",
                        0,
                    );
                    if consecutive_failures >= MAX_FAILURES {
                        return Err(format!(
                            "Too many consecutive failures ({}) in adjustment loop",
                            MAX_FAILURES
                        ));
                    }
                    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                    continue;
                }
            };

        if solve_result.success {
            // Reset failure counter on success
            consecutive_failures = 0;

            let ra_degrees = solve_result.ra * 15.0; // hours to degrees

            // Emit image again with plate solve coordinates
            emit_polar_image(
                &image,
                0,
                "adjusting",
                Some(ra_degrees),
                Some(solve_result.dec),
            );

            // Rolling 3-point recalculation: add new point and keep only last 3
            solved_points.push((ra_degrees, solve_result.dec));
            if solved_points.len() > 3 {
                solved_points.remove(0); // Remove oldest point to maintain sliding window
            }

            // Recalculate rotation center from updated points (requires at least 3 points)
            if solved_points.len() >= 3 {
                let (new_center_ra, new_center_dec) = calculate_rotation_center(&solved_points);
                center_ra = new_center_ra;
                center_dec = new_center_dec;
                tracing::debug!(
                    "Updated rotation center: RA={:.4}Â°, Dec={:.4}Â°",
                    center_ra,
                    center_dec
                );
            }

            // Calculate error relative to recalculated pole position
            let alt_error = (pole_dec - center_dec) * 60.0; // arcminutes
            let az_error = (0.0 - center_ra) * center_dec.to_radians().cos() * 60.0;
            let total_error = (az_error.powi(2) + alt_error.powi(2)).sqrt();

            // Auto-complete logic: check if error is below threshold
            if total_error <= auto_complete_threshold {
                match auto_complete_start {
                    Some(start_time) => {
                        let elapsed = start_time.elapsed();
                        if elapsed.as_secs() >= AUTO_COMPLETE_DURATION_SECS {
                            // Error has been below threshold for required duration
                            tracing::info!(
                                "Polar alignment complete! Total error {:.2} arcmin below threshold {:.2} for {} seconds",
                                total_error, auto_complete_threshold, AUTO_COMPLETE_DURATION_SECS
                            );
                            emit_polar_status(
                                &format!(
                                    "Complete! Error {:.2}' below threshold for {}s",
                                    total_error, AUTO_COMPLETE_DURATION_SECS
                                ),
                                "complete",
                                0,
                            );
                            emit_polar_error(
                                az_error,
                                alt_error,
                                total_error,
                                ra_degrees,
                                solve_result.dec,
                                center_ra,
                                center_dec,
                            );
                            return Ok(());
                        } else {
                            // Still within threshold, update status with countdown
                            let remaining = AUTO_COMPLETE_DURATION_SECS - elapsed.as_secs();
                            emit_polar_status(
                                &format!("Below threshold - completing in {}s...", remaining),
                                "adjusting",
                                0,
                            );
                        }
                    }
                    None => {
                        // First time below threshold, start timer
                        auto_complete_start = Some(std::time::Instant::now());
                        tracing::info!(
                            "Error {:.2} arcmin dropped below threshold {:.2}, starting auto-complete timer",
                            total_error, auto_complete_threshold
                        );
                        emit_polar_status(
                            &format!(
                                "Below threshold - completing in {}s...",
                                AUTO_COMPLETE_DURATION_SECS
                            ),
                            "adjusting",
                            0,
                        );
                    }
                }
            } else {
                // Error above threshold, reset timer if it was running
                if auto_complete_start.is_some() {
                    tracing::debug!(
                        "Error {:.2} arcmin went back above threshold {:.2}, resetting auto-complete timer",
                        total_error, auto_complete_threshold
                    );
                    auto_complete_start = None;
                }
                emit_polar_status("Adjusting - make corrections", "adjusting", 0);
            }

            emit_polar_error(
                az_error,
                alt_error,
                total_error,
                ra_degrees,
                solve_result.dec,
                center_ra,
                center_dec,
            );
        } else {
            consecutive_failures += 1;
            // Failed solve means we can't track error, reset auto-complete timer
            auto_complete_start = None;
            emit_polar_status(
                &format!(
                    "Solve unsuccessful (retry {}/{})",
                    consecutive_failures, MAX_FAILURES
                ),
                "adjusting",
                0,
            );
            if consecutive_failures >= MAX_FAILURES {
                return Err(format!(
                    "Too many consecutive failures ({}) in adjustment loop",
                    MAX_FAILURES
                ));
            }
        }

        // Brief pause before next update
        tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
    }
}

/// Helper to write a temp FITS file for plate solving
fn write_temp_fits_for_solve(image: &CapturedImageResult, path: &str) -> Result<(), String> {
    use nightshade_imaging::{write_fits, FitsHeader, ImageData, PixelType};
    use std::path::Path;

    // Convert RGBA display_data to grayscale 16-bit for FITS plate solving.
    // display_data is always RGBA (4 bytes per pixel).
    let raw_bytes: Vec<u8> = if image.is_color {
        // For color RGBA, convert to grayscale (luminance) and scale to 16-bit
        image
            .display_data
            .chunks(4)
            .flat_map(|rgba| {
                let lum = ((rgba[0] as u32 + rgba[1] as u32 + rgba[2] as u32) / 3) as u16 * 256;
                lum.to_le_bytes().to_vec()
            })
            .collect()
    } else {
        // For grayscale RGBA, take the R channel (all RGB channels are the same) and scale to 16-bit
        image
            .display_data
            .chunks(4)
            .flat_map(|rgba| {
                let scaled = (rgba[0] as u16) * 256;
                scaled.to_le_bytes().to_vec()
            })
            .collect()
    };

    let mut image_data = ImageData::new(
        image.width as u32,
        image.height as u32,
        1, // grayscale
        PixelType::U16,
    );
    image_data.data = raw_bytes;

    let header = FitsHeader::new();

    write_fits(Path::new(path), &image_data, &header)
        .map_err(|e| format!("FITS write error: {:?}", e))
}

/// Calculate the center of rotation from 3 solved points using 3D plane fitting
fn calculate_rotation_center(points: &[(f64, f64)]) -> (f64, f64) {
    if points.len() < 3 {
        return (0.0, 90.0);
    }

    // Convert spherical (RA, Dec) to Cartesian unit vectors
    let vectors: Vec<(f64, f64, f64)> = points
        .iter()
        .map(|(ra, dec)| {
            let ra_rad = ra.to_radians();
            let dec_rad = dec.to_radians();
            (
                dec_rad.cos() * ra_rad.cos(),
                dec_rad.cos() * ra_rad.sin(),
                dec_rad.sin(),
            )
        })
        .collect();

    // The three points define a plane. The rotation axis is the normal to this plane.
    let p1 = vectors[0];
    let p2 = vectors[1];
    let p3 = vectors[2];

    let v1 = (p2.0 - p1.0, p2.1 - p1.1, p2.2 - p1.2);
    let v2 = (p3.0 - p1.0, p3.1 - p1.1, p3.2 - p1.2);

    // Cross product for normal
    let nx = v1.1 * v2.2 - v1.2 * v2.1;
    let ny = v1.2 * v2.0 - v1.0 * v2.2;
    let nz = v1.0 * v2.1 - v1.1 * v2.0;

    // Normalize
    let mag = (nx * nx + ny * ny + nz * nz).sqrt();
    if mag < 1e-9 {
        return (0.0, 90.0);
    }

    let nx = nx / mag;
    let ny = ny / mag;
    let nz = nz / mag;

    // Convert back to RA/Dec
    let center_dec_rad = nz.asin();
    let mut center_ra_rad = ny.atan2(nx);

    if center_ra_rad < 0.0 {
        center_ra_rad += 2.0 * std::f64::consts::PI;
    }

    (center_ra_rad.to_degrees(), center_dec_rad.to_degrees())
}

/// Stop the polar alignment process
pub async fn api_stop_polar_alignment() -> Result<(), NightshadeError> {
    if !get_polar_align_flag().load(PolarOrdering::Relaxed) {
        return Ok(()); // Already stopped
    }

    // Signal cancellation
    get_polar_align_cancel().store(true, PolarOrdering::Relaxed);

    tracing::info!("Stopping polar alignment");

    // Give the background task time to clean up
    tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;

    get_polar_align_flag().store(false, PolarOrdering::Relaxed);

    emit_polar_status("Stopped", "idle", 0);

    Ok(())
}

// =============================================================================
// All-Sky Polar Alignment (Sharpcap-style)
// =============================================================================

/// Polar alignment mode selector.
///
/// The traditional `ThreePoint` mode (TPPA) requires a clear view of the
/// celestial pole region. `AllSky` mode performs Sharpcap-style polar
/// alignment from any point in the sky using a single solved frame plus
/// live drift feedback.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PolarAlignmentMode {
    /// Three-Point Polar Alignment â€” requires pole region visible.
    ThreePoint,
    /// Sharpcap-style all-sky polar alignment â€” works from any sky direction.
    AllSky,
}

/// Start all-sky polar alignment.
///
/// Unlike TPPA this routine does not require the celestial pole region to
/// be visible. It takes a single exposure anywhere in the sky, plate-solves
/// it to anchor a baseline, then re-solves every `iteration_cadence_secs`
/// to measure drift relative to that baseline. From the drift signature
/// and the observer's geographic location it recovers the polar-axis
/// azimuth and altitude error.
///
/// # Arguments
/// * `exposure_time` â€” exposure duration per frame, seconds.
/// * `solve_timeout` â€” plate-solve timeout per frame, seconds.
/// * `binning` â€” camera binning factor (1, 2, or 4 typical).
/// * `is_north` â€” northern hemisphere observer flag.
/// * `acceptance_threshold_arcsec` â€” alignment auto-completes when the
///   total error stays below this for 3 seconds (default 30â€³ = good for
///   ~3-minute unguided subs).
/// * `iteration_cadence_secs` â€” re-solve cadence (default 3s).
/// * `gain`, `offset` â€” optional camera parameters.
///
/// # Errors
/// Returns `NightshadeError::OperationFailed` if a plate solver is not
/// available (the user must install ASTAP), if no camera/mount is
/// connected, or if the observer location is not configured.
pub async fn api_start_all_sky_polar_alignment(
    exposure_time: f64,
    solve_timeout: f64,
    binning: i32,
    is_north: bool,
    acceptance_threshold_arcsec: f64,
    iteration_cadence_secs: f64,
    gain: Option<i32>,
    offset: Option<i32>,
) -> Result<(), NightshadeError> {
    use nightshade_sequencer::all_sky_polar::{
        perform_all_sky_polar_alignment, AllSkyPolarAlignConfig, PolarAlignError,
    };
    use nightshade_sequencer::{Binning, InstructionContext};

    // Reject re-entrant starts.
    if get_polar_align_flag().load(PolarOrdering::Relaxed) {
        return Err(NightshadeError::OperationFailed(
            "Polar alignment already running".to_string(),
        ));
    }

    // Fail loudly if the plate solver isn't installed â€” the all-sky
    // algorithm is plate-solve-only by design.
    if !nightshade_imaging::is_solver_available() {
        return Err(NightshadeError::OperationFailed(
            "Plate solver required â€” install ASTAP and re-run all-sky polar alignment"
                .to_string(),
        ));
    }

    get_polar_align_flag().store(true, PolarOrdering::Relaxed);
    get_polar_align_cancel().store(false, PolarOrdering::Relaxed);

    tracing::info!(
        "Starting all-sky polar alignment: exposure={}s, threshold={}\", cadence={}s, north={}",
        exposure_time,
        acceptance_threshold_arcsec,
        iteration_cadence_secs,
        is_north
    );

    // Resolve connected devices.
    let connected = api_get_connected_devices().await;
    let camera_id = connected
        .iter()
        .find(|d| d.device_type == DeviceType::Camera)
        .map(|d| d.id.clone())
        .ok_or_else(|| {
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
            NightshadeError::DeviceNotFound("No camera connected".to_string())
        })?;
    let mount_id = connected
        .iter()
        .find(|d| d.device_type == DeviceType::Mount)
        .map(|d| d.id.clone())
        .ok_or_else(|| {
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
            NightshadeError::DeviceNotFound("No mount connected".to_string())
        })?;

    // Observer location is mandatory for the horizontal-frame projection.
    let location = get_state()
        .get_observer_location()
        .map_err(|e| {
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
            NightshadeError::OperationFailed(format!("Failed to read observer location: {}", e))
        })?
        .ok_or_else(|| {
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
            NightshadeError::OperationFailed(
                "Observer latitude/longitude is required for all-sky polar alignment".to_string(),
            )
        })?;

    let config = AllSkyPolarAlignConfig {
        exposure_time,
        solve_timeout,
        gain,
        offset,
        binning: Some(binning),
        is_north,
        acceptance_threshold_arcsec,
        iteration_cadence_secs,
    };

    // Spawn the alignment task. Errors are emitted on the polar alignment
    // event stream so the UI can present them clearly.
    let cancel_flag = Arc::new(AtomicBool::new(false));
    let cancel_flag_outer = cancel_flag.clone();

    // Bridge between the global cancel flag (set by `api_stop_polar_alignment`)
    // and the per-task cancellation token used by InstructionContext.
    tokio::spawn(async move {
        loop {
            if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
                cancel_flag_outer.store(true, Ordering::Relaxed);
                break;
            }
            if !get_polar_align_flag().load(PolarOrdering::Relaxed) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(250)).await;
        }
    });

    let device_ops = create_unified_device_ops();

    tokio::spawn(async move {
        let ctx = InstructionContext {
            target_ra: None,
            target_dec: None,
            target_name: None,
            current_filter: None,
            current_binning: Binning::One,
            cancellation_token: cancel_flag,
            camera_id: Some(camera_id.clone()),
            mount_id: Some(mount_id.clone()),
            focuser_id: None,
            filterwheel_id: None,
            rotator_id: None,
            dome_id: None,
            cover_calibrator_id: None,
            save_path: None,
            latitude: Some(location.latitude),
            longitude: Some(location.longitude),
            device_ops,
            trigger_state: None,
            filter_focus_offsets: std::collections::HashMap::new(),
        };

        let status_cb = |status: String, _progress: Option<f64>| {
            emit_polar_status(&status, "adjusting", 0);
        };
        let image_cb = |image_data: nightshade_sequencer::PolarAlignmentImageData| {
            get_state().publish_event(create_event_auto_id(
                EventSeverity::Info,
                EventCategory::PolarAlignment,
                EventPayload::PolarAlignmentImage(PolarAlignmentImageEvent {
                    image_data: image_data.image_data,
                    width: image_data.width,
                    height: image_data.height,
                    solved_ra: image_data.solved_ra,
                    solved_dec: image_data.solved_dec,
                    point: image_data.point,
                    phase: image_data.phase,
                }),
            ));
        };
        let error_cb = |result: &nightshade_sequencer::PolarAlignResult| {
            emit_polar_error(
                result.azimuth_error,
                result.altitude_error,
                result.total_error,
                result.current_ra,
                result.current_dec,
                result.target_ra,
                result.target_dec,
            );
        };

        let result =
            perform_all_sky_polar_alignment(&config, &ctx, status_cb, image_cb, error_cb).await;

        match result {
            Ok(()) => {
                emit_polar_status("All-sky polar alignment complete", "complete", 0);
            }
            Err(PolarAlignError::Cancelled) => {
                emit_polar_status("Stopped", "idle", 0);
            }
            Err(PolarAlignError::SolverUnavailable) => {
                emit_polar_status(
                    "Plate solver required â€” install ASTAP and re-run all-sky polar alignment",
                    "error",
                    0,
                );
                tracing::error!(
                    "All-sky polar alignment aborted: plate solver not available"
                );
            }
            Err(e) => {
                emit_polar_status(&format!("Error: {}", e), "error", 0);
                tracing::error!("All-sky polar alignment failed: {}", e);
            }
        }

        get_polar_align_flag().store(false, PolarOrdering::Relaxed);
    });

    Ok(())
}

// =============================================================================
// Equipment Profiles
// =============================================================================

/// Initialize profile storage
#[flutter_rust_bridge::frb(sync)]
pub fn api_init_profile_storage(storage_path: String) -> Result<(), NightshadeError> {
    crate::state::init_profile_storage(std::path::PathBuf::from(storage_path))
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get all equipment profiles
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_profiles() -> Result<Vec<EquipmentProfile>, NightshadeError> {
    get_state()
        .load_profiles()
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Save an equipment profile
#[flutter_rust_bridge::frb(sync)]
pub fn api_save_profile(profile: EquipmentProfile) -> Result<(), NightshadeError> {
    get_state()
        .save_profile_to_storage(&profile)
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Delete an equipment profile
#[flutter_rust_bridge::frb(sync)]
pub fn api_delete_profile(profile_id: String) -> Result<(), NightshadeError> {
    get_state()
        .delete_profile_from_storage(&profile_id)
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Load a profile and set as active
pub async fn api_load_profile(profile_id: String) -> Result<(), NightshadeError> {
    get_state()
        .load_and_set_profile(&profile_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get the currently active profile
pub async fn api_get_active_profile() -> Result<Option<EquipmentProfile>, NightshadeError> {
    Ok(get_state().get_profile().await)
}

// =============================================================================
// Settings & Location
// =============================================================================

/// Initialize settings storage and load observer location into memory
#[flutter_rust_bridge::frb(sync)]
pub fn api_init_settings_storage(storage_path: String) -> Result<(), NightshadeError> {
    let path = std::path::PathBuf::from(storage_path);
    crate::state::init_settings_storage(path.clone())
        .map_err(|e| NightshadeError::OperationFailed(e))?;
    // Plate-solver preferences share the settings directory. Errors here are
    // not fatal â€” the API falls back to in-memory defaults if storage is
    // unavailable â€” but a hard failure to initialise still surfaces.
    crate::state::init_platesolver_storage(path)
        .map_err(|e| NightshadeError::OperationFailed(e))?;

    // Load observer location from persisted settings into in-memory state
    // This ensures the sequencer and other Rust components have access to location
    get_state().load_observer_location_from_settings();

    Ok(())
}

/// Get application settings
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_settings() -> Result<AppSettings, NightshadeError> {
    get_state()
        .get_settings()
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Update application settings
#[flutter_rust_bridge::frb(sync)]
pub fn api_update_settings(settings: AppSettings) -> Result<(), NightshadeError> {
    get_state()
        .update_settings(&settings)
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get observer location
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_location() -> Result<Option<ObserverLocation>, NightshadeError> {
    get_state()
        .get_observer_location()
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set observer location
#[flutter_rust_bridge::frb(sync)]
pub fn api_set_location(location: Option<ObserverLocation>) -> Result<(), NightshadeError> {
    match &location {
        Some(loc) => {
            tracing::info!(
                "[API] api_set_location called with lat={}, lon={}, elev={}",
                loc.latitude,
                loc.longitude,
                loc.elevation
            );
        }
        None => {
            tracing::info!("[API] api_set_location called with None");
        }
    }
    let result = get_state().set_observer_location(location);
    match &result {
        Ok(_) => {
            tracing::debug!("[API] api_set_location succeeded");
        }
        Err(ref e) => {
            tracing::error!("[API] api_set_location failed: {}", e);
        }
    }
    result.map_err(|e| NightshadeError::OperationFailed(e))
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

    // Camera settings
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
        // Why: airmass returns Err for below-horizon inputs (audit Â§6.14). Surface
        // that as an OperationFailed so the caller knows the frame metadata was
        // attempted with an invalid altitude rather than silently writing a
        // sentinel value or omitting the keyword.
        let airmass = calculate_airmass(altitude).map_err(|e| {
            NightshadeError::OperationFailed(format!(
                "Cannot compute AIRMASS for altitude {}Â°: {}",
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

    // Camera settings
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
        // Why: airmass returns Err for below-horizon inputs (audit Â§6.14). Surface
        // that as an OperationFailed so the caller knows the frame metadata was
        // attempted with an invalid altitude rather than silently writing a
        // sentinel value or omitting the keyword.
        let airmass = calculate_airmass(altitude).map_err(|e| {
            NightshadeError::OperationFailed(format!(
                "Cannot compute AIRMASS for altitude {}Â°: {}",
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
fn apply_auto_white_balance(image: &mut [u16]) {
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
// DEVICE CAPABILITY REPORTING API
// =============================================================================

/// Get capabilities for any device by its device ID.
///
/// This function queries the actual device to determine what features it supports.
/// The result varies by device type (camera, mount, focuser, filter wheel).
///
/// # Arguments
/// * `device_id` - The full device ID string (e.g., "ascom:ASCOM.Camera.Simulator")
///
/// # Returns
/// * `DeviceCapabilities` - An enum containing the appropriate capability struct
///
/// # Errors
/// * Returns error if device type is unsupported or device cannot be queried
pub async fn api_get_device_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::DeviceCapabilities, NightshadeError> {
    crate::device_capabilities::get_device_capabilities(&device_id).await
}

/// Get camera capabilities for a specific camera device.
///
/// This is a convenience wrapper that returns only camera capabilities.
///
/// # Arguments
/// * `device_id` - The camera device ID
///
/// # Returns
/// * `CameraCapabilities` - Camera-specific capability information
pub async fn api_get_camera_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::CameraCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Camera(c) => Ok(c),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a camera",
        )),
    }
}

/// Get mount capabilities for a specific mount device.
///
/// This is a convenience wrapper that returns only mount capabilities.
///
/// # Arguments
/// * `device_id` - The mount/telescope device ID
///
/// # Returns
/// * `MountCapabilities` - Mount-specific capability information
pub async fn api_get_mount_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::MountCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Mount(m) => Ok(m),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a mount",
        )),
    }
}

/// Get focuser capabilities for a specific focuser device.
///
/// This is a convenience wrapper that returns only focuser capabilities.
///
/// # Arguments
/// * `device_id` - The focuser device ID
///
/// # Returns
/// * `FocuserCapabilities` - Focuser-specific capability information
pub async fn api_get_focuser_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::FocuserCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Focuser(f) => Ok(f),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a focuser",
        )),
    }
}

/// Get filter wheel capabilities for a specific filter wheel device.
///
/// This is a convenience wrapper that returns only filter wheel capabilities.
///
/// # Arguments
/// * `device_id` - The filter wheel device ID
///
/// # Returns
/// * `FilterWheelCapabilities` - Filter wheel-specific capability information
pub async fn api_get_filterwheel_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::FilterWheelCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::FilterWheel(fw) => Ok(fw),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a filter wheel",
        )),
    }
}

/// Get rotator capabilities for a specific rotator device.
///
/// This is a convenience wrapper that returns only rotator capabilities.
///
/// # Arguments
/// * `device_id` - The rotator device ID
///
/// # Returns
/// * `RotatorCapabilities` - Rotator-specific capability information
pub async fn api_get_rotator_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::RotatorCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Rotator(r) => Ok(r),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a rotator",
        )),
    }
}

/// Get dome capabilities for a specific dome device.
///
/// This is a convenience wrapper that returns only dome capabilities.
///
/// # Arguments
/// * `device_id` - The dome device ID
///
/// # Returns
/// * `DomeCapabilities` - Dome-specific capability information
pub async fn api_get_dome_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::DomeCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Dome(d) => Ok(d),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a dome",
        )),
    }
}

/// Get cover calibrator capabilities for a specific cover calibrator device.
///
/// This is a convenience wrapper that returns only cover calibrator capabilities.
///
/// # Arguments
/// * `device_id` - The cover calibrator device ID
///
/// # Returns
/// * `CoverCalibratorCapabilities` - Cover calibrator-specific capability information
pub async fn api_get_cover_calibrator_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::CoverCalibratorCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::CoverCalibrator(cc) => Ok(cc),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a cover calibrator",
        )),
    }
}

/// Get weather capabilities for a specific weather/observing conditions device.
///
/// This is a convenience wrapper that returns only weather capabilities.
///
/// # Arguments
/// * `device_id` - The weather device ID
///
/// # Returns
/// * `WeatherCapabilities` - Weather-specific capability information
pub async fn api_get_weather_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::WeatherCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Weather(w) => Ok(w),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a weather station",
        )),
    }
}

/// Get safety monitor capabilities for a specific safety monitor device.
///
/// This is a convenience wrapper that returns only safety monitor capabilities.
///
/// # Arguments
/// * `device_id` - The safety monitor device ID
///
/// # Returns
/// * `SafetyMonitorCapabilities` - Safety monitor-specific capability information
pub async fn api_get_safety_monitor_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::SafetyMonitorCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::SafetyMonitor(sm) => Ok(sm),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a safety monitor",
        )),
    }
}

/// Get switch capabilities for a specific switch device.
///
/// This is a convenience wrapper that returns only switch capabilities.
///
/// # Arguments
/// * `device_id` - The switch device ID
///
/// # Returns
/// * `SwitchCapabilities` - Switch-specific capability information
pub async fn api_get_switch_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::SwitchCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Switch(s) => Ok(s),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a switch",
        )),
    }
}

// =============================================================================
// DEVICE QUIRKS
// =============================================================================

/// Information about a known device quirk, suitable for UI display.
pub struct QuirkInfo {
    /// Quirk category (e.g. "Temperature", "Timing", "Discovery")
    pub category: String,
    /// Human-readable description of the quirk
    pub description: String,
}

/// Get known quirks for a connected device.
///
/// Returns a list of known device characteristics and workarounds that are
/// automatically applied. This information can be displayed in the equipment
/// screen to inform users about device-specific behaviors.
///
/// # Arguments
/// * `device_id` - The device identifier (e.g., "native:zwo:ASI294MC Pro")
///
/// # Returns
/// * `Vec<QuirkInfo>` - List of quirks with categories and descriptions
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_device_quirks(device_id: String) -> Vec<QuirkInfo> {
    let quirks = nightshade_native::quirks::get_quirks_for_device(&device_id);
    quirks
        .into_iter()
        .map(|q| QuirkInfo {
            category: q.category().to_string(),
            description: q.description(),
        })
        .collect()
}

// =============================================================================
// QHY DISCOVERY CONTROL
// =============================================================================

/// Check if QHY camera discovery is enabled.
///
/// QHY discovery can be disabled if the QHY SDK causes crashes or hangs on the
/// user's system. When disabled, QHY cameras will not appear in device discovery.
///
/// # Returns
/// * `true` - QHY discovery is enabled (default)
/// * `false` - QHY discovery is disabled
#[flutter_rust_bridge::frb(sync)]
pub fn api_is_qhy_discovery_enabled() -> bool {
    nightshade_native::vendor::qhy::is_qhy_discovery_enabled()
}

/// Enable or disable QHY camera discovery.
///
/// Use this function to disable QHY discovery if it causes problems:
/// - SDK crashes during enumeration
/// - Discovery hangs and never completes
/// - Conflicts with other camera SDKs
///
/// When disabled:
/// - `discover_devices()` returns empty for QHY cameras/filter wheels
/// - Existing QHY camera connections are not affected
/// - The setting persists for the session but resets on restart
///
/// # Arguments
/// * `enabled` - Whether to enable QHY discovery
///
/// # Example Use Cases
/// 1. Disable if QHY SDK not installed to speed up discovery
/// 2. Disable if QHY SDK crashes on this system
/// 3. Disable temporarily to troubleshoot conflicts
#[flutter_rust_bridge::frb(sync)]
pub fn api_set_qhy_discovery_enabled(enabled: bool) {
    nightshade_native::vendor::qhy::set_qhy_discovery_enabled(enabled);
}

/// Get information about QHY SDK availability and discovery status.
///
/// # Returns
/// * `QhyDiscoveryStatus` - Status information about QHY discovery
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_qhy_discovery_status() -> QhyDiscoveryStatus {
    QhyDiscoveryStatus {
        sdk_available: nightshade_native::vendor::qhy::is_sdk_available(),
        discovery_enabled: nightshade_native::vendor::qhy::is_qhy_discovery_enabled(),
        timeout_ms: get_qhy_discovery_timeout_ms(),
    }
}

/// Helper to get the QHY discovery timeout from quirks
fn get_qhy_discovery_timeout_ms() -> u64 {
    use nightshade_native::quirks::{get_quirks_for_vendor, DiscoveryQuirk, Quirk};
    use nightshade_native::NativeVendor;

    let quirks = get_quirks_for_vendor(&NativeVendor::Qhy);
    for quirk in quirks {
        if let Quirk::Discovery(DiscoveryQuirk::DiscoveryTimeoutMs(timeout)) = quirk {
            return timeout;
        }
    }
    10000 // Default timeout
}

/// Status information about QHY discovery
#[derive(Debug, Clone)]
pub struct QhyDiscoveryStatus {
    /// Whether the QHY SDK DLL/SO was loaded successfully
    pub sdk_available: bool,
    /// Whether QHY discovery is currently enabled
    pub discovery_enabled: bool,
    /// The timeout for discovery operations in milliseconds
    pub timeout_ms: u64,
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

fn convert_config(config: ApiLiveStackingConfig) -> crate::stacking_api::LiveStackingConfigApi {
    crate::stacking_api::LiveStackingConfigApi {
        sigma_clip_enabled: config.sigma_clip_enabled,
        sigma_clip_threshold: config.sigma_clip_threshold,
        max_match_stars: config.max_match_stars,
        match_radius_px: config.match_radius_px,
        match_flux_tolerance: config.match_flux_tolerance,
        min_matched_pairs: config.min_matched_pairs,
    }
}

fn convert_stats(stats: crate::stacking_api::LiveStackingStatsApi) -> ApiLiveStackingStats {
    ApiLiveStackingStats {
        stacked_frame_count: stats.stacked_frame_count,
        total_frames_attempted: stats.total_frames_attempted,
        rejected_alignment_failures: stats.rejected_alignment_failures,
        avg_matched_pairs: stats.avg_matched_pairs,
        avg_alignment_residual: stats.avg_alignment_residual,
        total_sigma_rejected_pixels: stats.total_sigma_rejected_pixels,
    }
}

fn convert_result(
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

fn defect_maps_root() -> std::path::PathBuf {
    // Why: NIGHTSHADE_DATA_DIR is the standard per-platform application
    // data path set by the Flutter shell on launch (see main_headless.dart
    // and the FFI bridge startup). The temp_dir fallback exists for unit
    // tests and for headless invocations where the env var hasn't been
    // populated yet â€” for those callers the defect maps are session-scoped
    // and don't need to survive a reboot. Production hosts hit the env-var
    // branch first.
    let base = std::env::var_os("NIGHTSHADE_DATA_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::env::temp_dir().join("nightshade"));
    base.join("defect_maps")
}

fn sanitize_camera_id(camera_id: &str) -> String {
    camera_id
        .chars()
        .map(|c| match c {
            'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' => c,
            _ => '_',
        })
        .collect()
}

fn defect_map_path(
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
static DEFECT_APPLY_FLAGS: OnceLock<Mutex<HashMap<String, bool>>> = OnceLock::new();

fn defect_apply_flags() -> &'static Mutex<HashMap<String, bool>> {
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
        // state â€” apply-during-capture is opt-in and the map is only written
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
        // state â€” apply-during-capture is opt-in and the map is only written
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
        // Phase 1: insert 60 entries â€” 10 over the capacity of 50 â€” and
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
