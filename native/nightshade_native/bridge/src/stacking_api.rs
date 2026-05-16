//! Live stacking bridge API
//!
//! Exposes the live stacking engine to Dart via flutter_rust_bridge.
//! Uses a global singleton LiveStacker protected by a Mutex.

use nightshade_imaging::stacking::{LiveStackConfig, LiveStacker, StackingStats};
use nightshade_imaging::{read_image, ImageData, StarDetectionConfig};
use std::sync::Mutex;
use std::sync::OnceLock;

/// Global live stacker instance
static LIVE_STACKER: OnceLock<Mutex<Option<LiveStacker>>> = OnceLock::new();

fn get_stacker_lock() -> &'static Mutex<Option<LiveStacker>> {
    LIVE_STACKER.get_or_init(|| Mutex::new(None))
}

/// Acquire the stacker mutex with poison recovery.
///
/// # `unwrap_or` policy (audit-rust §4.3)
///
/// If a previous holder panicked, the mutex becomes poisoned. Rather than
/// making all future stacking calls fail permanently, we recover the inner
/// data (which may be in an inconsistent state) and clear it, logging a
/// warning so the issue is visible.
fn acquire_stacker() -> std::sync::MutexGuard<'static, Option<LiveStacker>> {
    get_stacker_lock().lock().unwrap_or_else(|poisoned| {
        tracing::warn!(
            "Live stacker mutex was poisoned (a previous operation panicked); recovering"
        );
        poisoned.into_inner()
    })
}

/// Statistics returned to Dart about the stacking session
#[derive(Debug, Clone)]
pub struct LiveStackingStatsApi {
    pub stacked_frame_count: u32,
    pub total_frames_attempted: u32,
    pub rejected_alignment_failures: u32,
    pub avg_matched_pairs: f64,
    pub avg_alignment_residual: f64,
    pub total_sigma_rejected_pixels: u64,
}

impl From<StackingStats> for LiveStackingStatsApi {
    fn from(s: StackingStats) -> Self {
        Self {
            stacked_frame_count: s.stacked_frame_count,
            total_frames_attempted: s.total_frames_attempted,
            rejected_alignment_failures: s.rejected_alignment_failures,
            avg_matched_pairs: s.avg_matched_pairs,
            avg_alignment_residual: s.avg_alignment_residual,
            total_sigma_rejected_pixels: s.total_sigma_rejected_pixels,
        }
    }
}

/// Configuration parameters exposed to Dart for stacking setup
#[derive(Debug, Clone)]
pub struct LiveStackingConfigApi {
    pub sigma_clip_enabled: bool,
    pub sigma_clip_threshold: f64,
    pub max_match_stars: u32,
    pub match_radius_px: f64,
    pub match_flux_tolerance: f64,
    pub min_matched_pairs: u32,
}

impl Default for LiveStackingConfigApi {
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

impl From<LiveStackingConfigApi> for LiveStackConfig {
    fn from(api: LiveStackingConfigApi) -> Self {
        LiveStackConfig {
            sigma_clip_threshold: api.sigma_clip_threshold,
            sigma_clip_enabled: api.sigma_clip_enabled,
            // Why (audit-rust §1.4): live-stacking config values are u32
            // UI-bounded (max_match_stars ≤ 10_000, min_matched_pairs ≤
            // ~100); u32 → usize widening on every supported target.
            max_match_stars: api.max_match_stars as usize,
            match_radius_px: api.match_radius_px,
            match_flux_tolerance: api.match_flux_tolerance,
            min_matched_pairs: api.min_matched_pairs as usize,
            star_detection: StarDetectionConfig {
                detection_sigma: 4.0,
                min_snr: 8.0,
                ..StarDetectionConfig::default()
            },
        }
    }
}

// =============================================================================
// Public API functions (exposed to Dart via flutter_rust_bridge)
// =============================================================================

/// Start live stacking by loading a reference image from a file path.
///
/// This initializes the stacker with the given image as the reference frame.
/// All subsequent frames will be aligned to this reference.
pub fn stacking_start(
    reference_image_path: String,
    config: LiveStackingConfigApi,
) -> Result<LiveStackingStatsApi, String> {
    tracing::info!(
        "Starting live stacking with reference: {}",
        reference_image_path
    );

    let path = std::path::Path::new(&reference_image_path);
    let read_result =
        read_image(path).map_err(|e| format!("Failed to read reference image: {}", e))?;

    let native_config: LiveStackConfig = config.into();
    let stacker = LiveStacker::new(&read_result.image, native_config)
        .map_err(|e| format!("Failed to initialize stacker: {}", e))?;

    let stats = stacker.get_stats();

    let mut guard = acquire_stacker();
    *guard = Some(stacker);

    tracing::info!("Live stacking started successfully");
    Ok(stats.into())
}

/// Start live stacking from raw image data (width, height, u16 pixel data).
///
/// This is used when the reference frame is already in memory (e.g. from a capture).
pub fn stacking_start_from_data(
    width: u32,
    height: u32,
    data: Vec<u16>,
    config: LiveStackingConfigApi,
) -> Result<LiveStackingStatsApi, String> {
    tracing::info!(
        "Starting live stacking from data: {}x{} ({} pixels)",
        width,
        height,
        data.len()
    );

    let image = ImageData::from_u16(width, height, 1, &data);
    let native_config: LiveStackConfig = config.into();
    let stacker = LiveStacker::new(&image, native_config)
        .map_err(|e| format!("Failed to initialize stacker: {}", e))?;

    let stats = stacker.get_stats();

    let mut guard = acquire_stacker();
    *guard = Some(stacker);

    tracing::info!("Live stacking started successfully from data");
    Ok(stats.into())
}

/// Add a frame to the live stack by file path.
///
/// Returns the u16 pixel data of the current stacked result, along with dimensions.
/// The stacked result can be displayed directly as a preview.
pub fn stacking_add_frame(image_path: String) -> Result<LiveStackingAddFrameResult, String> {
    tracing::info!("Adding frame to stack: {}", image_path);

    let path = std::path::Path::new(&image_path);
    let read_result = read_image(path).map_err(|e| format!("Failed to read frame image: {}", e))?;

    let mut guard = acquire_stacker();

    let stacker = guard
        .as_mut()
        .ok_or_else(|| "Live stacker not initialized. Call stacking_start first.".to_string())?;

    let result_image = stacker.add_frame(&read_result.image)?;

    let result_u16 = result_image
        .as_u16()
        .ok_or_else(|| "Failed to convert stacked result to u16".to_string())?;

    Ok(LiveStackingAddFrameResult {
        width: result_image.width,
        height: result_image.height,
        data: result_u16,
        stats: stacker.get_stats().into(),
    })
}

/// Add a frame to the live stack from raw u16 pixel data.
pub fn stacking_add_frame_from_data(
    width: u32,
    height: u32,
    data: Vec<u16>,
) -> Result<LiveStackingAddFrameResult, String> {
    tracing::debug!("Adding frame from data to stack: {}x{}", width, height);

    let image = ImageData::from_u16(width, height, 1, &data);

    let mut guard = acquire_stacker();

    let stacker = guard
        .as_mut()
        .ok_or_else(|| "Live stacker not initialized. Call stacking_start first.".to_string())?;

    let result_image = stacker.add_frame(&image)?;

    let result_u16 = result_image
        .as_u16()
        .ok_or_else(|| "Failed to convert stacked result to u16".to_string())?;

    Ok(LiveStackingAddFrameResult {
        width: result_image.width,
        height: result_image.height,
        data: result_u16,
        stats: stacker.get_stats().into(),
    })
}

/// Result from adding a frame to the stack
#[derive(Debug, Clone)]
pub struct LiveStackingAddFrameResult {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u16>,
    pub stats: LiveStackingStatsApi,
}

/// Get the current stacked result without adding a frame.
pub fn stacking_get_result() -> Result<LiveStackingAddFrameResult, String> {
    let guard = acquire_stacker();

    let stacker = guard
        .as_ref()
        .ok_or_else(|| "Live stacker not initialized".to_string())?;

    let result_image = stacker.get_current_stack();

    let result_u16 = result_image
        .as_u16()
        .ok_or_else(|| "Failed to convert stacked result to u16".to_string())?;

    Ok(LiveStackingAddFrameResult {
        width: result_image.width,
        height: result_image.height,
        data: result_u16,
        stats: stacker.get_stats().into(),
    })
}

/// Get the current stacking statistics.
pub fn stacking_get_stats() -> Result<LiveStackingStatsApi, String> {
    let guard = acquire_stacker();

    let stacker = guard
        .as_ref()
        .ok_or_else(|| "Live stacker not initialized".to_string())?;

    Ok(stacker.get_stats().into())
}

/// Reset the live stacker, clearing all accumulated data but keeping the reference frame.
pub fn stacking_reset() -> Result<(), String> {
    let mut guard = acquire_stacker();

    let stacker = guard
        .as_mut()
        .ok_or_else(|| "Live stacker not initialized".to_string())?;

    stacker.reset();
    tracing::info!("Live stacker reset");
    Ok(())
}

/// Stop live stacking and release all resources.
pub fn stacking_stop() -> Result<(), String> {
    let mut guard = acquire_stacker();

    if guard.is_none() {
        return Err("Live stacker not initialized".to_string());
    }

    *guard = None;
    tracing::info!("Live stacker stopped and resources released");
    Ok(())
}

/// Check if live stacking is currently active.
#[flutter_rust_bridge::frb(sync)]
pub fn stacking_is_active() -> bool {
    acquire_stacker().is_some()
}

/// Get the current frame count.
///
/// # `unwrap_or` policy (audit-rust §4.3)
///
/// No stacker initialised yet → 0 frames. The UI uses this to render the
/// "Stacked: N frames" badge; absent stacker = no badge, matching the
/// "stacking session not started" state.
#[flutter_rust_bridge::frb(sync)]
pub fn stacking_frame_count() -> u32 {
    acquire_stacker()
        .as_ref()
        .map(|s| s.frame_count())
        .unwrap_or(0)
}
