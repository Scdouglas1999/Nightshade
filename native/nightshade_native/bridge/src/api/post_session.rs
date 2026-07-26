//! Post-session (offline / batch) image-processing FFI surface.
//!
//! This module exposes the committed native batch-integration pipeline
//! (`nightshade_imaging::{registration, frame_weighting, normalization,
//! integration, master_accumulation, calibration_masters}`) to Dart through a
//! **minimal, JSON-in / JSON-out** boundary.
//!
//! Why JSON and not typed FFI structs: regenerating `flutter_rust_bridge`
//! bindings is heavyweight (needs LLVM + MSVC + WinKit, see
//! `docs/FRB_TROUBLESHOOTING.md`). Every knob added later — new rejection
//! algorithm, new resampler, drizzle params — then rides inside the JSON payload
//! and never triggers another regen. This is the same trick the live stacker
//! uses for node config (per project memory). The boundary is exactly four
//! `String -> Result<String, String>` functions:
//!
//! * [`api_integrate_session`] — one-shot batch integration → linear FITS master.
//! * [`api_master_accumulate`] — multi-night accumulating master (create / add /
//!   finalize / info).
//! * [`api_build_master_flat`] — build a unit-mean master flat from raw flats.
//! * [`api_save_fits_master`] — re-export an in-memory buffer as a FITS master.
//!
//! These are **stateless per call** (no process-wide singleton): the post-session
//! engine can run in a Dart isolate without clobbering a live stacking session
//! (which *is* a singleton). The calls are CPU-bound and synchronous; the Dart
//! side runs them off the UI isolate.

use nightshade_imaging::calibration_masters::{
    build_master_flat, cosmetic_correct_transient, CosmeticConfig, MasterFlatConfig,
};
use nightshade_imaging::frame_weighting::{
    accumulation_weights, analyze_frame_quality, weight_frames, CullPolicy, FrameQuality,
    FrameQualityConfig, WeightFormula,
};
use nightshade_imaging::integration::{
    integrate_frames, Combine, IntegrationConfig, IntegrationFrame, Reject,
};
use nightshade_imaging::master_accumulation::{
    frame_buffer_for_master, AccumulationMode, IntegratedMaster, MasterCreateConfig, OnlineClip,
};
use nightshade_imaging::normalization::{
    apply_normalization, estimate_normalization, CoverageMask, NormMode, NormalizationConfig,
};
use nightshade_imaging::registration::{
    register_frame, Interpolator, RegistrationConfig, TransformKind, TransformModel,
};
use nightshade_imaging::stacking::{CombineMethod, MasterOutputType};
use nightshade_imaging::{
    add_wcs_headers, apply_stretch, apply_stretch_rgb_per_channel, auto_stretch_rgb_with_mode,
    auto_stretch_stf, read_fits, read_image, write_fits, FitsHeader, ImageData, PixelType,
    RgbStretchMode, WcsInfo,
};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::api::get_state;
use crate::event::{EventSeverity, ImagingEvent};

// =============================================================================
// Integration progress events
// =============================================================================

/// Overall fraction at the *start* of each integration phase. The fraction
/// reported during a phase interpolates from its own entry up to the next
/// phase's entry, so the bar advances smoothly across the whole run.
const FRACTION_CALIBRATE: f32 = 0.0;
const FRACTION_REGISTER: f32 = 0.20;
const FRACTION_WEIGHT: f32 = 0.60;
const FRACTION_NORMALIZE: f32 = 0.62;
const FRACTION_INTEGRATE: f32 = 0.80;
const FRACTION_INTEGRATE_DONE: f32 = 0.92;
const FRACTION_WRITE: f32 = 0.95;
const FRACTION_DONE: f32 = 1.0;

/// Publish a single [`ImagingEvent::IntegrationProgress`] on the global event
/// bus so Dart can drive a progress bar for the offline integration pipeline.
///
/// Cheap by construction: it only clones a short phase string and touches the
/// `Arc<EventBus>` broadcast sender (non-blocking, no-ops with no receivers).
/// [`api_integrate_session`] runs on FRB's `wrap_normal` worker thread (not the
/// Dart UI isolate), so emitting from inside the orchestration loops is safe.
/// Callers must emit per *phase boundary* (and per *frame* inside the register
/// loop) — never per pixel.
fn emit_integration_progress(
    phase: &str,
    fraction: f32,
    frames_done: Option<u32>,
    frames_total: Option<u32>,
) {
    get_state().publish_imaging_event(
        ImagingEvent::IntegrationProgress {
            phase: phase.to_string(),
            fraction: fraction.clamp(0.0, 1.0),
            frames_done,
            frames_total,
        },
        EventSeverity::Info,
    );
}

// =============================================================================
// JSON request / response contracts
// =============================================================================

/// Calibration master paths applied to every light before registration.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct CalibrationArgs {
    /// Master dark FITS/XISF path, or `None`/empty to skip.
    dark: Option<String>,
    /// Master flat (unit-mean) path, or `None`/empty to skip.
    flat: Option<String>,
    /// Master bias path, or `None`/empty to skip.
    bias: Option<String>,
    /// Apply self-derived cosmetic (hot/cold transient) correction per light.
    cosmetic_correction: bool,
}

/// Star-detection sensitivity overrides for registration.
///
/// The production `StarDetectionConfig::default()` is tuned for real CCD frames.
/// These optional overrides let callers loosen the hot-pixel / SNR / sharpness
/// gates for unusual data (very short subs, undersampled optics, or synthetic
/// frames) — the PixInsight StarDetector "sensitivity" analogue. Each `0`/unset
/// field keeps the production default for that knob.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct DetectionArgs {
    /// Detection σ above background (default 5.0).
    detection_sigma: f64,
    /// Minimum connected-component area in px (default 9).
    min_area: u32,
    /// Maximum star eccentricity to accept (default 0.7).
    max_eccentricity: f64,
    /// Minimum HFR in px (default 1.0).
    min_hfr: f64,
    /// Minimum SNR (default 5.0).
    min_snr: f64,
    /// Maximum sharpness, 0..1 (default 0.95; raise toward 1.0 to keep
    /// tight/idealised PSFs the hot-pixel gate would otherwise reject).
    max_sharpness: f64,
}

/// Alignment / registration knobs (subset of [`RegistrationConfig`]).
#[derive(Debug, Clone, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct AlignArgs {
    /// `"similarity"` | `"affine"` | `"homography"`.
    model: String,
    /// `"bilinear"` | `"catmullRom"` | `"lanczos3"`.
    resampler: String,
    /// RANSAC inlier threshold in reference pixels.
    ransac_threshold_px: f64,
    /// Brightest-N stars used to build matching descriptors.
    max_ref_stars: usize,
    /// Optional star-detection sensitivity overrides.
    detection: DetectionArgs,
}

impl Default for AlignArgs {
    fn default() -> Self {
        Self {
            model: "affine".to_string(),
            resampler: "lanczos3".to_string(),
            ransac_threshold_px: 2.0,
            max_ref_stars: 60,
            detection: DetectionArgs::default(),
        }
    }
}

/// Per-sub weighting knobs.
#[derive(Debug, Clone, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct WeightingArgs {
    /// Whether weighting is applied at all (off ⇒ every contributing sub = 1.0).
    enabled: bool,
    /// `"snr"` | `"snrSquared"` | `"fwhmInverse"` | `"custom"`.
    formula: String,
    /// Exponents used only when `formula == "custom"`.
    snr_pow: f64,
    fwhm_pow: f64,
    ecc_pow: f64,
}

impl Default for WeightingArgs {
    fn default() -> Self {
        Self {
            enabled: true,
            formula: "snrSquared".to_string(),
            snr_pow: 2.0,
            fwhm_pow: 1.0,
            ecc_pow: 1.0,
        }
    }
}

/// Normalization knobs.
#[derive(Debug, Clone, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct NormalizationArgs {
    /// Whether normalization to the reference is applied at all.
    enabled: bool,
    /// `"global"` | `"local"`.
    mode: String,
    /// Local-grid rows/cols, used only when `mode == "local"`.
    local_rows: usize,
    local_cols: usize,
}

impl Default for NormalizationArgs {
    fn default() -> Self {
        Self {
            enabled: true,
            mode: "global".to_string(),
            local_rows: 8,
            local_cols: 8,
        }
    }
}

/// Integration (combine + rejection) knobs.
#[derive(Debug, Clone, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct IntegrationArgs {
    /// `"mean"` | `"median"`.
    combine: String,
    /// `"auto"` | `"none"` | `"sigmaClip"` | `"winsorizedSigma"` |
    /// `"linearFit"` | `"percentile"` | `"minMax"`.
    ///
    /// `"auto"` picks by sub count (PixInsight-style): `<8 → percentile`,
    /// `8–24 → winsorizedSigma`, `≥25 → linearFit`.
    reject: String,
    /// Low/high thresholds. Sigma-family: κ in σ. Percentile: fraction in (0,1).
    reject_low: f64,
    reject_high: f64,
    /// Min/max counts, used only when `reject == "minMax"`.
    min_max_low: usize,
    min_max_high: usize,
    /// Emit the per-pixel rejection-count map alongside the master.
    generate_rejection_map: bool,
    /// `"f32"` (archival linear, default) | `"u16"`.
    output_bit_depth: String,
}

impl Default for IntegrationArgs {
    fn default() -> Self {
        Self {
            combine: "mean".to_string(),
            reject: "auto".to_string(),
            reject_low: 3.0,
            reject_high: 3.0,
            min_max_low: 1,
            min_max_high: 1,
            generate_rejection_map: true,
            output_bit_depth: "f32".to_string(),
        }
    }
}

/// The full settings block for [`api_integrate_session`].
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct IntegrationSettingsArgs {
    align: AlignArgs,
    weighting: WeightingArgs,
    normalization: NormalizationArgs,
    integration: IntegrationArgs,
}

/// Output paths for [`api_integrate_session`].
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct OutputArgs {
    /// Where to write the 16-bit/float linear FITS master (required).
    master_fits_path: String,
    /// Optional stretched preview PNG path.
    preview_png_path: Option<String>,
    /// Optional per-pixel rejection-count map FITS path.
    rejection_map_path: Option<String>,
    /// Optional stretched PNG sibling for the rejection-count overlay.
    rejection_map_preview_path: Option<String>,
}

/// Top-level request for [`api_integrate_session`].
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct IntegrateSessionArgs {
    /// Light-frame paths (FITS/XISF/etc.), in any order.
    light_paths: Vec<String>,
    /// Reference choice: a path among `light_paths`, or `"auto"`/empty for the
    /// highest-quality sub.
    reference: Option<String>,
    /// Per-light exposure seconds, aligned to `light_paths`. Used only to report
    /// `totalIntegrationSec`. Empty ⇒ unknown (reported as 0).
    exposures_sec: Vec<f64>,
    calibration: CalibrationArgs,
    settings: IntegrationSettingsArgs,
    output: OutputArgs,
}

/// Per-frame record returned to Dart for the cull UI.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct PerFrameRecord {
    path: String,
    /// Normalized integration weight in (0, 1], or 0 if the frame was dropped.
    weight: f64,
    /// RMS registration residual (reference px), or null if not registered.
    rms_residual_px: Option<f64>,
    /// Whether the frame contributed to the master.
    accepted: bool,
    /// Human-readable reason when `accepted == false`.
    reason: Option<String>,
    /// Per-sub signal-to-noise proxy from this sub's own [`FrameQuality`]
    /// (measured on the aligned luminance plane), or null when the sub could
    /// not be registered + measured. Persisted by the Dart side for the Night
    /// Doctor after a morning integration.
    snr: Option<f64>,
    /// Per-sub robust noise σ (ADU) from this sub's own [`FrameQuality`], or
    /// null when not measured. **Load-bearing for the morning report:** the
    /// marginal-SNR optimizer (`integration_curve`) skips any sub whose
    /// `noise <= 0` from the SNR sums, so without surfacing this the whole
    /// improvement curve collapses to zero (signal·noise = 0, variance = 0) and
    /// `target_snr` anchors to 0. The Dart `_analyzeAndStoreCurve` threads this
    /// into the `qualities` map it hands `apiAnalyzeNight`.
    noise: Option<f64>,
    /// Per-sub sky-background level (ADU) from this sub's own [`FrameQuality`],
    /// or null when not measured. Surfaced alongside `noise` so the optimizer's
    /// quality descriptors are complete (the optimizer reads `noise`/`snr`; the
    /// extras keep the morning-report record faithful).
    background: Option<f64>,
    /// Per-sub detected star count from this sub's own [`FrameQuality`], or null
    /// when not measured (transparency / depth proxy carried to the report).
    star_count: Option<u32>,
    /// Per-sub median star FWHM in px (focus / seeing proxy), or null when not
    /// measured.
    fwhm: Option<f64>,
    /// Per-sub median star eccentricity (0 = round, →1 = trailed), or null when
    /// too few reliable stars were available to measure it honestly.
    eccentricity: Option<f64>,
    /// The fitted **source→reference** registration transform, as the row-major
    /// 3×3 homogeneous matrix flattened to 9 elements `[m00, m01, m02, m10, m11,
    /// m12, m20, m21, m22]` — the exact wire shape `DrizzleFrameArgs.transform`
    /// (`finishing_combine.rs`) consumes. `null` only when the sub failed
    /// registration (and so contributes nothing to a drizzle stack). Surfaced so
    /// the Dart drizzle flow can feed each accepted sub's raw, un-resampled
    /// pixels + its transform to `api_drizzle_integrate`.
    transform: Option<Vec<f64>>,
    /// The transform family (`"similarity"` / `"affine"` / `"homography"`),
    /// purely informational; `null` when [`transform`] is `null`.
    transform_kind: Option<String>,
}

/// Flatten a [`TransformModel`] into the row-major 9-element wire array the
/// drizzle frame contract (`DrizzleFrameArgs.transform`) consumes.
fn transform_to_row_major(t: &TransformModel) -> Vec<f64> {
    let m = &t.matrix;
    vec![
        m[0][0], m[0][1], m[0][2], m[1][0], m[1][1], m[1][2], m[2][0], m[2][1], m[2][2],
    ]
}

/// The wire token for a [`TransformKind`] (matches `build_alignment` parsing in
/// `finishing_combine.rs`).
fn transform_kind_wire(kind: TransformKind) -> &'static str {
    match kind {
        TransformKind::Similarity => "similarity",
        TransformKind::Affine => "affine",
        TransformKind::Homography => "homography",
    }
}

/// Response for [`api_integrate_session`].
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct IntegrateSessionResult {
    master_fits_path: String,
    preview_path: Option<String>,
    rejection_map_path: Option<String>,
    rejection_map_preview_path: Option<String>,
    frames_integrated: usize,
    frames_rejected: usize,
    total_integration_sec: f64,
    /// Mean inlier RMS residual across the registered subs (reference px).
    rms_residual: f64,
    width: u32,
    height: u32,
    channels: u32,
    per_frame_stats: Vec<PerFrameRecord>,
}

// =============================================================================
// Public FFI entry points
// =============================================================================

/// One-shot batch integration of a sub list into a linear FITS master.
///
/// Pipeline: optional calibration (dark/flat/bias) + cosmetic correction →
/// star-based registration to a reference → per-channel normalization →
/// per-sub quality weighting → batch integration with pixel rejection →
/// 16-bit/float linear FITS master + stretched preview PNG.
///
/// `args_json` is an [`IntegrateSessionArgs`]; the result is an
/// [`IntegrateSessionResult`]. All failure modes (no subs, unreadable frame,
/// no consistent geometry, write failure) surface as `Err(String)` — never a
/// silent partial stack.
pub fn api_integrate_session(args_json: String) -> Result<String, String> {
    let args: IntegrateSessionArgs =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid integrate args: {e}"))?;
    let result = integrate_session(args)?;
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

/// Multi-night accumulating master. `op` selects the operation:
///
/// * `create`   `{ op, referencePath, sidecarPath, masterFitsPath?, settings?, filter?, target? }`
/// * `add`      `{ op, sidecarPath, lightPaths[], exposuresSec?, calibration?, settings? }`
/// * `finalize` `{ op, sidecarPath, masterFitsPath, previewPngPath? }`
/// * `info`     `{ op, sidecarPath }`
///
/// Returns a [`MasterAccumulateResult`]. The running accumulator state lives in
/// the `.nsmaster` sidecar; the FITS is the shareable artifact written on
/// `finalize` (and re-finalizable after more `add`s).
pub fn api_master_accumulate(args_json: String) -> Result<String, String> {
    let op: MasterOp =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid accumulate args: {e}"))?;
    let result = match op.op.as_str() {
        "create" => master_create(&args_json)?,
        "add" => master_add(&args_json)?,
        "finalize" => master_finalize(&args_json)?,
        "info" => master_info(&args_json)?,
        other => {
            return Err(format!(
                "unknown master op '{other}'; expected create/add/finalize/info"
            ))
        }
    };
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

/// Build a unit-mean master flat from raw flats (+ optional bias / dark-flat
/// pedestal) and write it as a FITS master, wrapping
/// [`build_master_flat`](nightshade_imaging::calibration_masters::build_master_flat).
///
/// `args_json` is a [`BuildMasterFlatArgs`]; the result is a
/// [`BuildMasterFlatResult`].
pub fn api_build_master_flat(args_json: String) -> Result<String, String> {
    let args: BuildMasterFlatArgs =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid flat args: {e}"))?;
    let result = build_master_flat_impl(args)?;
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

/// Re-export an in-memory pixel buffer as a 16-bit or float FITS master with
/// provenance. The integration paths already write the FITS natively, so this
/// is for re-export from Dart-held buffers.
///
/// `args_json` is a [`SaveFitsMasterArgs`]; the result is a
/// [`SaveFitsMasterResult`].
pub fn api_save_fits_master(args_json: String) -> Result<String, String> {
    let args: SaveFitsMasterArgs =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid save args: {e}"))?;
    let result = save_fits_master_impl(args)?;
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

// =============================================================================
// api_integrate_session implementation
// =============================================================================

/// A light frame loaded, calibrated, and ready to register: kept around so the
/// reference can be picked after every sub's quality is known.
#[flutter_rust_bridge::frb(ignore)]
struct LoadedLight {
    path: String,
    image: ImageData,
    exposure_sec: f64,
}

fn integrate_session(args: IntegrateSessionArgs) -> Result<IntegrateSessionResult, String> {
    if args.light_paths.is_empty() {
        return Err("no light frames supplied".to_string());
    }
    if args.output.master_fits_path.trim().is_empty() {
        return Err("output.masterFitsPath is required".to_string());
    }

    // --- Load calibration masters once (shared across all lights). ---
    let dark = load_optional_master(&args.calibration.dark, "dark")?;
    let flat = load_optional_master(&args.calibration.flat, "flat")?;
    let bias = load_optional_master(&args.calibration.bias, "bias")?;

    // --- Load + calibrate every light. ---
    let total_lights = args.light_paths.len() as u32;
    emit_integration_progress(
        "calibrating",
        FRACTION_CALIBRATE,
        Some(0),
        Some(total_lights),
    );
    let mut loaded: Vec<LoadedLight> = Vec::with_capacity(args.light_paths.len());
    for (i, path) in args.light_paths.iter().enumerate() {
        let read =
            read_image(Path::new(path)).map_err(|e| format!("failed to read '{path}': {e}"))?;
        let mut image = read.image;
        if image.pixel_type != PixelType::U16 {
            return Err(format!(
                "light '{path}' is {:?}; registration requires U16 (debayer/convert first)",
                image.pixel_type
            ));
        }
        if dark.is_some() || flat.is_some() || bias.is_some() {
            image = nightshade_imaging::calibration::calibrate_frame(
                &image,
                dark.as_ref(),
                flat.as_ref(),
                bias.as_ref(),
            )
            .map_err(|e| format!("calibration of '{path}' failed: {e}"))?;
        }
        if args.calibration.cosmetic_correction {
            // Self-derived hot/cold transient repair (cosmic rays, residual hot
            // pixels). Operates per-channel in place; the report is advisory.
            let _ = cosmetic_correct_transient(&mut image, CosmeticConfig::default());
        }
        let exposure_sec = args.exposures_sec.get(i).copied().unwrap_or(0.0);
        loaded.push(LoadedLight {
            path: path.clone(),
            image,
            exposure_sec,
        });
        // Calibrate phase spans 0.0..0.20 across all lights.
        let done = (i + 1) as u32;
        let frac = if total_lights > 0 {
            FRACTION_REGISTER * (done as f32 / total_lights as f32)
        } else {
            FRACTION_REGISTER
        };
        emit_integration_progress("calibrating", frac, Some(done), Some(total_lights));
    }

    // --- Choose the reference frame. ---
    let q_cfg = FrameQualityConfig::default();
    let ref_index = choose_reference(&args.reference, &loaded, &q_cfg)?;
    let reference = &loaded[ref_index].image;
    let width = reference.width;
    let height = reference.height;
    let channels = reference.channels;
    let locations = (width as usize) * (height as usize);
    let chan = channels as usize;

    // --- Register every light onto the reference. ---
    let reg_cfg = build_registration_config(&args.settings.align)?;

    // Per-frame outputs, aligned to `loaded`.
    struct Registered {
        path: String,
        // f64 channel-interleaved aligned pixels on the reference grid.
        pixels: Vec<f64>,
        coverage: CoverageMask,
        rms_residual_px: Option<f64>,
        exposure_sec: f64,
        // Quality measured on the *aligned* luminance plane.
        quality: Option<FrameQuality>,
        accepted: bool,
        reason: Option<String>,
        // Source→reference homogeneous transform fitted during registration
        // (identity for the reference). `None` only when registration failed.
        // Surfaced to Dart so the drizzle flow can deposit each sub's raw,
        // un-resampled pixels onto the finer output grid using this transform.
        transform: Option<TransformModel>,
    }

    emit_integration_progress(
        "registering",
        FRACTION_REGISTER,
        Some(0),
        Some(total_lights),
    );
    let mut registered: Vec<Registered> = Vec::with_capacity(loaded.len());
    for (i, light) in loaded.iter().enumerate() {
        // Register phase spans 0.20..0.60; emit per frame (cheap), never per
        // pixel. Emitted at the top so both the reference (`continue`) and the
        // matched branches report uniform per-frame progress.
        let done = (i + 1) as u32;
        let frac = if total_lights > 0 {
            FRACTION_REGISTER
                + (FRACTION_WEIGHT - FRACTION_REGISTER) * (done as f32 / total_lights as f32)
        } else {
            FRACTION_WEIGHT
        };
        emit_integration_progress("registering", frac, Some(done), Some(total_lights));

        if i == ref_index {
            // The reference aligns to itself by identity; flatten directly.
            let pixels = image_to_f64(&light.image);
            let coverage = CoverageMask::full(width as usize, height as usize);
            let quality = aligned_quality(&light.image, &q_cfg);
            registered.push(Registered {
                path: light.path.clone(),
                pixels,
                coverage,
                rms_residual_px: Some(0.0),
                exposure_sec: light.exposure_sec,
                quality,
                accepted: true,
                reason: None,
                transform: Some(TransformModel::identity()),
            });
            continue;
        }

        match register_frame(reference, &light.image, &reg_cfg) {
            Ok(reg) => {
                let pixels = image_to_f64(&reg.aligned);
                let coverage = CoverageMask::from_zero_fill(
                    &derive_luma_f64(&pixels, locations, chan),
                    width as usize,
                    height as usize,
                );
                let quality = aligned_quality(&reg.aligned, &q_cfg);
                registered.push(Registered {
                    path: light.path.clone(),
                    pixels,
                    coverage,
                    rms_residual_px: Some(reg.stats.rms_residual_px),
                    exposure_sec: light.exposure_sec,
                    quality,
                    accepted: true,
                    reason: None,
                    transform: Some(reg.transform),
                });
            }
            Err(e) => {
                // A sub that cannot be registered is dropped (not fatal): the
                // rest of the night still integrates. Recorded honestly so the
                // UI can show why.
                registered.push(Registered {
                    path: light.path.clone(),
                    pixels: Vec::new(),
                    coverage: CoverageMask::full(0, 0),
                    rms_residual_px: None,
                    exposure_sec: light.exposure_sec,
                    quality: None,
                    accepted: false,
                    reason: Some(format!("registration failed: {e}")),
                    transform: None,
                });
            }
        }
    }

    // --- Weight the accepted subs. ---
    let accepted_idx: Vec<usize> = registered
        .iter()
        .enumerate()
        .filter(|(_, r)| r.accepted && r.quality.is_some())
        .map(|(i, _)| i)
        .collect();
    if accepted_idx.is_empty() {
        return Err("no subs could be registered + measured; nothing to integrate".to_string());
    }

    emit_integration_progress("weighting", FRACTION_WEIGHT, None, None);
    let weights: Vec<f64> = if args.settings.weighting.enabled {
        let qualities: Vec<FrameQuality> = accepted_idx
            .iter()
            .map(|&i| registered[i].quality.expect("filtered to Some"))
            .collect();
        let formula = build_weight_formula(&args.settings.weighting)?;
        let report = weight_frames(&qualities, &formula, &CullPolicy::default())
            .ok_or_else(|| "weighting produced no result".to_string())?;
        report.frames.iter().map(|f| f.weight).collect()
    } else {
        vec![1.0; accepted_idx.len()]
    };

    // --- Reference luminance for normalization (the anchor). ---
    // Use the *registered* reference buffer (already on the grid).
    let ref_reg_pos = accepted_idx
        .iter()
        .position(|&i| i == ref_index)
        .ok_or_else(|| "reference frame was dropped during registration".to_string())?;
    let ref_pixels = registered[ref_index].pixels.clone();

    // --- Normalize each accepted sub to the reference, per channel. ---
    let norm_total = accepted_idx.len() as u32;
    emit_integration_progress("normalizing", FRACTION_NORMALIZE, Some(0), Some(norm_total));
    if args.settings.normalization.enabled {
        let norm_cfg = build_normalization_config(&args.settings.normalization)?;
        // Per-channel reference planes (borrowed once).
        let ref_planes: Vec<Vec<f64>> = (0..chan)
            .map(|ch| extract_channel(&ref_pixels, locations, chan, ch))
            .collect();
        for (pos, &i) in accepted_idx.iter().enumerate() {
            // Normalize phase spans 0.62..0.80; emit per accepted sub (cheap),
            // emitted at the top so the reference (`continue`) frame still
            // advances the bar.
            let done = (pos + 1) as u32;
            let frac = if norm_total > 0 {
                FRACTION_NORMALIZE
                    + (FRACTION_INTEGRATE - FRACTION_NORMALIZE) * (done as f32 / norm_total as f32)
            } else {
                FRACTION_INTEGRATE
            };
            emit_integration_progress("normalizing", frac, Some(done), Some(norm_total));

            if i == ref_index {
                continue;
            }
            let coverage = registered[i].coverage.clone();
            for (ch, ref_plane) in ref_planes.iter().enumerate() {
                let mut plane = extract_channel(&registered[i].pixels, locations, chan, ch);
                let coeffs = estimate_normalization(
                    &plane,
                    ref_plane,
                    &coverage,
                    width as usize,
                    height as usize,
                    &norm_cfg,
                )
                .map_err(|e| format!("normalization of '{}' failed: {e}", registered[i].path))?;
                apply_normalization(&mut plane, &coeffs, width as usize, height as usize);
                write_channel(&mut registered[i].pixels, locations, chan, ch, &plane);
            }
        }
    }
    let _ = ref_reg_pos; // reference normalizes to identity; kept for clarity.

    // --- Integrate. ---
    let sub_count = accepted_idx.len();
    let int_cfg = build_integration_config(&args.settings.integration, sub_count)?;
    let frames: Vec<IntegrationFrame<'_>> = accepted_idx
        .iter()
        .zip(weights.iter())
        .map(|(&i, &w)| IntegrationFrame {
            pixels: &registered[i].pixels,
            weight: w,
            coverage: Some(&registered[i].coverage),
        })
        .collect();

    // `integrate_frames` has no inner progress callback, so bracket it: 0.80
    // before, 0.92 after.
    emit_integration_progress("integrating", FRACTION_INTEGRATE, None, None);
    let output = integrate_frames(&frames, width, height, channels, &int_cfg)
        .map_err(|e| format!("integration failed: {e}"))?;
    emit_integration_progress("integrating", FRACTION_INTEGRATE_DONE, None, None);

    // --- Write the master FITS. ---
    emit_integration_progress("writing", FRACTION_WRITE, None, None);
    let master_path = Path::new(&args.output.master_fits_path);
    ensure_parent_dir(master_path)?;
    // Carry the reference frame's plate-solved WCS into the master so the mosaic
    // stitcher can place this panel without a post-hoc solve. Best-effort: a
    // reference with no WCS leaves the master WCS-less (the stitch gates it out).
    let reference_wcs = reference_wcs_from_fits(&loaded[ref_index].path);
    let header = build_master_header(
        sub_count,
        &args.settings.integration,
        reference_wcs.as_ref(),
    );
    write_fits(master_path, &output.master, &header)
        .map_err(|e| format!("failed to write master FITS: {e:?}"))?;

    // --- Optional rejection map FITS. ---
    let rejection_map_path = if let (Some(p), Some(map)) = (
        args.output.rejection_map_path.as_ref(),
        output.rejection_map.as_ref(),
    ) {
        if !p.trim().is_empty() {
            let path = Path::new(p);
            ensure_parent_dir(path)?;
            let mut h = FitsHeader::new();
            h.set_string("IMAGETYP", "REJECTION_MAP");
            h.add_history("Nightshade post-session rejection-count map");
            write_fits(path, map, &h)
                .map_err(|e| format!("failed to write rejection map: {e:?}"))?;
            Some(p.clone())
        } else {
            None
        }
    } else {
        None
    };

    // --- Optional stretched rejection-map PNG. ---
    // Flutter cannot decode the scientific FITS map directly. Keep that FITS
    // for inspection and emit a real image sibling for Session Review.
    let rejection_map_preview_path = if let (Some(p), Some(map)) = (
        args.output.rejection_map_preview_path.as_ref(),
        output.rejection_map.as_ref(),
    ) {
        if !p.trim().is_empty() {
            match write_preview_png(map, Path::new(p)) {
                Ok(()) => Some(p.clone()),
                Err(e) => {
                    tracing::warn!(
                        path = %p,
                        error = %e,
                        "rejection preview PNG write failed; keeping master and FITS map"
                    );
                    None
                }
            }
        } else {
            None
        }
    } else {
        None
    };

    // --- Optional stretched preview PNG. ---
    let preview_path = if let Some(p) = args.output.preview_png_path.as_ref() {
        if !p.trim().is_empty() {
            write_preview_png(&output.master, Path::new(p))?;
            Some(p.clone())
        } else {
            None
        }
    } else {
        None
    };
    // Final boundary: the master (and optional preview) are on disk.
    emit_integration_progress("preview", FRACTION_DONE, None, None);

    // --- Assemble per-frame stats + aggregate residual. ---
    // Map normalized weights back to the accepted frames by position.
    let mut weight_by_index: std::collections::HashMap<usize, f64> =
        std::collections::HashMap::new();
    for (pos, &i) in accepted_idx.iter().enumerate() {
        weight_by_index.insert(i, weights[pos]);
    }

    let mut per_frame_stats = Vec::with_capacity(registered.len());
    let mut residual_sum = 0.0;
    let mut residual_n = 0usize;
    let mut total_integration_sec = 0.0;
    let mut frames_rejected = 0usize;
    for (i, r) in registered.iter().enumerate() {
        let weight = weight_by_index.get(&i).copied().unwrap_or(0.0);
        if r.accepted {
            if let Some(rms) = r.rms_residual_px {
                if i != ref_index {
                    residual_sum += rms;
                    residual_n += 1;
                }
            }
            total_integration_sec += r.exposure_sec;
        } else {
            frames_rejected += 1;
        }
        // Thread this sub's own measured FrameQuality into the record so the
        // Dart side can persist per-sub snr/fwhm/eccentricity (the v42
        // `integrated_master_frames` columns the Night Doctor reads). Quality is
        // `None` only for subs that failed registration/measurement.
        per_frame_stats.push(PerFrameRecord {
            path: r.path.clone(),
            weight,
            rms_residual_px: r.rms_residual_px,
            accepted: r.accepted,
            reason: r.reason.clone(),
            snr: r.quality.map(|q| q.snr),
            // Surface the same measured quality the optimizer needs: `noise`
            // (its variance term) plus the background/star_count context. Without
            // `noise` the Dart morning-report curve is structurally dead.
            noise: r.quality.map(|q| q.noise),
            background: r.quality.map(|q| q.background),
            star_count: r.quality.map(|q| q.star_count),
            fwhm: r.quality.map(|q| q.fwhm),
            eccentricity: r.quality.and_then(|q| q.eccentricity),
            transform: r.transform.as_ref().map(transform_to_row_major),
            transform_kind: r
                .transform
                .as_ref()
                .map(|t| transform_kind_wire(t.kind).to_string()),
        });
    }
    let rms_residual = if residual_n > 0 {
        residual_sum / residual_n as f64
    } else {
        0.0
    };

    Ok(IntegrateSessionResult {
        master_fits_path: args.output.master_fits_path.clone(),
        preview_path,
        rejection_map_path,
        rejection_map_preview_path,
        frames_integrated: output.stats.frames_integrated,
        frames_rejected,
        total_integration_sec,
        rms_residual,
        width,
        height,
        channels,
        per_frame_stats,
    })
}

// =============================================================================
// api_master_accumulate implementation
// =============================================================================

#[derive(Debug, Clone, Deserialize)]
#[flutter_rust_bridge::frb(ignore)]
struct MasterOp {
    op: String,
}

/// Settings carried on master `create` (subset that must be frozen for the
/// master's lifetime).
#[derive(Debug, Clone, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct MasterSettingsArgs {
    /// Online-clip thresholds (σ). `None` ⇒ pure running mean (no rejection,
    /// exactly equal to a single-batch weighted mean).
    online_clip_low: Option<f64>,
    online_clip_high: Option<f64>,
}

impl Default for MasterSettingsArgs {
    fn default() -> Self {
        Self {
            online_clip_low: Some(4.0),
            online_clip_high: Some(4.0),
        }
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct MasterCreateArgs {
    reference_path: String,
    sidecar_path: String,
    settings: MasterSettingsArgs,
    filter: Option<String>,
    target: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct MasterAddArgs {
    sidecar_path: String,
    light_paths: Vec<String>,
    exposures_sec: Vec<f64>,
    /// ISO date / session id for the fold log.
    label: String,
    calibration: CalibrationArgs,
    settings: IntegrationSettingsArgs,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct MasterFinalizeArgs {
    sidecar_path: String,
    master_fits_path: String,
    preview_png_path: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct MasterInfoArgs {
    sidecar_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct MasterAccumulateResult {
    sidecar_path: String,
    master_path: Option<String>,
    preview_path: Option<String>,
    frame_count: usize,
    total_integration_sec: f64,
    width: u32,
    height: u32,
    channels: u32,
    /// Frames added in this call (0 for create/finalize/info).
    frames_added: usize,
    /// Samples rejected by the online clip in this call.
    rejected: u64,
    /// Per-frame integration weight for the frames folded in THIS `add` call, in
    /// `lightPaths` order (empty for create/finalize/info). The Dart side
    /// persists these so the multi-night growth/best-night intelligence has real
    /// per-sub weights instead of nulls.
    #[serde(default)]
    frame_weights: Vec<f64>,
}

fn master_create(args_json: &str) -> Result<MasterAccumulateResult, String> {
    let args: MasterCreateArgs =
        serde_json::from_str(args_json).map_err(|e| format!("invalid create args: {e}"))?;
    if args.reference_path.trim().is_empty() || args.sidecar_path.trim().is_empty() {
        return Err("create requires referencePath and sidecarPath".to_string());
    }
    let read = read_image(Path::new(&args.reference_path))
        .map_err(|e| format!("failed to read reference '{}': {e}", args.reference_path))?;
    let reference = read.image;

    let clip = match (
        args.settings.online_clip_low,
        args.settings.online_clip_high,
    ) {
        (Some(low), Some(high)) => Some(OnlineClip { low, high }),
        _ => None,
    };
    let cfg = MasterCreateConfig {
        mode: AccumulationMode::RunningWeightedMean { clip },
        filter: args.filter.clone(),
        target: args.target.clone(),
    };
    let master = IntegratedMaster::create(&reference, &cfg)
        .map_err(|e| format!("master create failed: {e}"))?;

    let sidecar = Path::new(&args.sidecar_path);
    ensure_parent_dir(sidecar)?;
    std::fs::write(sidecar, master.serialize())
        .map_err(|e| format!("failed to write sidecar: {e}"))?;

    // Persist the U16 registration reference next to the sidecar. The committed
    // accumulation state freezes the *geometry* + photometric baseline but not a
    // reference *image*, and the running mean is empty until the first fold — so
    // every `add` aligns its subs against this frozen companion frame, keeping
    // cross-night geometry consistent regardless of fold order.
    let ref_companion = reference_companion_path(sidecar);
    let ref_u16 = ensure_u16(&reference);
    write_fits(&ref_companion, &ref_u16, &{
        let mut h = FitsHeader::new();
        h.set_string("IMAGETYP", "MASTER_REF");
        h
    })
    .map_err(|e| format!("failed to write reference companion: {e:?}"))?;

    Ok(MasterAccumulateResult {
        sidecar_path: args.sidecar_path,
        master_path: None,
        preview_path: None,
        frame_count: master.metadata.total_frames,
        total_integration_sec: master.metadata.total_integration_seconds,
        width: master.geometry.width,
        height: master.geometry.height,
        channels: master.geometry.channels,
        frames_added: 0,
        rejected: 0,
        frame_weights: Vec::new(),
    })
}

fn master_add(args_json: &str) -> Result<MasterAccumulateResult, String> {
    let args: MasterAddArgs =
        serde_json::from_str(args_json).map_err(|e| format!("invalid add args: {e}"))?;
    if args.sidecar_path.trim().is_empty() {
        return Err("add requires sidecarPath".to_string());
    }
    if args.light_paths.is_empty() {
        return Err("add requires at least one light".to_string());
    }

    let sidecar = Path::new(&args.sidecar_path);
    let bytes = std::fs::read(sidecar).map_err(|e| format!("failed to read sidecar: {e}"))?;
    let mut master =
        IntegratedMaster::deserialize(&bytes).map_err(|e| format!("corrupt sidecar: {e}"))?;

    let geom = master.geometry.clone();
    let width = geom.width;
    let height = geom.height;
    let channels = geom.channels;
    let locations = (width as usize) * (height as usize);
    let chan = channels as usize;

    // Load + calibrate masters once.
    let dark = load_optional_master(&args.calibration.dark, "dark")?;
    let flat = load_optional_master(&args.calibration.flat, "flat")?;
    let bias = load_optional_master(&args.calibration.bias, "bias")?;

    // Register against the frozen reference companion written at `create` (the
    // running mean is empty until the first fold, so we cannot use it as the
    // alignment anchor — and using a frozen anchor keeps every night's geometry
    // mutually consistent regardless of fold order).
    let ref_companion = reference_companion_path(sidecar);
    let ref_image = read_image(&ref_companion)
        .map(|r| r.image)
        .map_err(|e| {
            format!(
                "failed to read reference companion '{}': {e} (was the master created with this build?)",
                ref_companion.display()
            )
        })?;

    let reg_cfg = build_registration_config(&args.settings.align)?;
    let q_cfg = FrameQualityConfig::default();

    // Build the per-sub aligned + normalized f64 buffers and weights.
    let mut buffers: Vec<Vec<f64>> = Vec::new();
    let mut coverages: Vec<CoverageMask> = Vec::new();
    let mut qualities: Vec<FrameQuality> = Vec::new();
    let mut exposures: Vec<f64> = Vec::new();

    let norm_cfg = if args.settings.normalization.enabled {
        Some(build_normalization_config(&args.settings.normalization)?)
    } else {
        None
    };
    let ref_planes: Option<Vec<Vec<f64>>> = norm_cfg.as_ref().map(|_| {
        let ref_f64 = image_to_f64(&ref_image);
        (0..chan)
            .map(|ch| extract_channel(&ref_f64, locations, chan, ch))
            .collect()
    });

    for (i, path) in args.light_paths.iter().enumerate() {
        let read =
            read_image(Path::new(path)).map_err(|e| format!("failed to read '{path}': {e}"))?;
        let mut image = read.image;
        if image.pixel_type != PixelType::U16 {
            return Err(format!(
                "light '{path}' is {:?}; expected U16",
                image.pixel_type
            ));
        }
        if dark.is_some() || flat.is_some() || bias.is_some() {
            image = nightshade_imaging::calibration::calibrate_frame(
                &image,
                dark.as_ref(),
                flat.as_ref(),
                bias.as_ref(),
            )
            .map_err(|e| format!("calibration of '{path}' failed: {e}"))?;
        }
        if args.calibration.cosmetic_correction {
            let _ = cosmetic_correct_transient(&mut image, CosmeticConfig::default());
        }

        let reg = register_frame(&ref_image, &image, &reg_cfg)
            .map_err(|e| format!("registration of '{path}' failed: {e}"))?;
        // Geometry guard: aligned frame must match the master grid.
        frame_buffer_for_master(i, &reg.aligned, &geom).map_err(|e| format!("'{path}': {e}"))?;

        let mut pixels = image_to_f64(&reg.aligned);
        let coverage = CoverageMask::from_zero_fill(
            &derive_luma_f64(&pixels, locations, chan),
            width as usize,
            height as usize,
        );

        if let (Some(cfg), Some(planes)) = (norm_cfg.as_ref(), ref_planes.as_ref()) {
            for (ch, ref_plane) in planes.iter().enumerate() {
                let mut plane = extract_channel(&pixels, locations, chan, ch);
                let coeffs = estimate_normalization(
                    &plane,
                    ref_plane,
                    &coverage,
                    width as usize,
                    height as usize,
                    cfg,
                )
                .map_err(|e| format!("normalization of '{path}' failed: {e}"))?;
                apply_normalization(&mut plane, &coeffs, width as usize, height as usize);
                write_channel(&mut pixels, locations, chan, ch, &plane);
            }
        }

        let quality = aligned_quality(&reg.aligned, &q_cfg)
            .ok_or_else(|| format!("could not measure quality of '{path}'"))?;

        buffers.push(pixels);
        coverages.push(coverage);
        qualities.push(quality);
        exposures.push(args.exposures_sec.get(i).copied().unwrap_or(0.0));
    }

    // Weight each fold's subs on a fixed, population-independent quality scale
    // (`accumulation_weights`, anchored on `FrameQuality::neutral`) rather than
    // renormalizing every night to its own best sub. The accumulating master
    // sums weights across folds, so a per-fold max-normalization (`weight_frames`)
    // would reset each night's best sub to 1.0 and erase real cross-night quality
    // differences — a uniformly worse night would contribute as much weight as a
    // pristine one. Anchoring on a fixed reference keeps the weights comparable
    // across folds while leaving a single-night master unchanged (a weighted mean
    // is invariant to a global weight rescale).
    let weights: Vec<f64> = if args.settings.weighting.enabled {
        let formula = build_weight_formula(&args.settings.weighting)?;
        accumulation_weights(&qualities, &formula)
    } else {
        vec![1.0; qualities.len()]
    };

    let frames: Vec<IntegrationFrame<'_>> = buffers
        .iter()
        .zip(coverages.iter())
        .zip(weights.iter())
        .map(|((px, cov), &w)| IntegrationFrame {
            pixels: px,
            weight: w,
            coverage: Some(cov),
        })
        .collect();

    let label = if args.label.trim().is_empty() {
        "fold".to_string()
    } else {
        args.label.clone()
    };
    let report = master
        .add_frames(&frames, &exposures, &label)
        .map_err(|e| format!("add_frames failed: {e}"))?;

    std::fs::write(sidecar, master.serialize())
        .map_err(|e| format!("failed to write sidecar: {e}"))?;

    Ok(MasterAccumulateResult {
        sidecar_path: args.sidecar_path,
        master_path: None,
        preview_path: None,
        frame_count: master.metadata.total_frames,
        total_integration_sec: master.metadata.total_integration_seconds,
        width,
        height,
        channels,
        frames_added: report.frames_added,
        rejected: report.rejected,
        frame_weights: weights,
    })
}

fn master_finalize(args_json: &str) -> Result<MasterAccumulateResult, String> {
    let args: MasterFinalizeArgs =
        serde_json::from_str(args_json).map_err(|e| format!("invalid finalize args: {e}"))?;
    if args.sidecar_path.trim().is_empty() || args.master_fits_path.trim().is_empty() {
        return Err("finalize requires sidecarPath and masterFitsPath".to_string());
    }
    let bytes =
        std::fs::read(&args.sidecar_path).map_err(|e| format!("failed to read sidecar: {e}"))?;
    let master =
        IntegratedMaster::deserialize(&bytes).map_err(|e| format!("corrupt sidecar: {e}"))?;

    let image = master.finalize();
    let master_path = Path::new(&args.master_fits_path);
    ensure_parent_dir(master_path)?;
    let mut header = FitsHeader::new();
    header.set_string("IMAGETYP", "MASTER_LIGHT");
    header.set_string("FRAMETYP", "MASTER");
    header.set_string("CALSTAT", "Nightshade accumulating master");
    header.set_int("NFRAMES", master.metadata.total_frames as i64);
    header.set_float("EXPTIME", master.metadata.total_integration_seconds);
    if let Some(f) = &master.metadata.filter {
        header.set_string("FILTER", f);
    }
    if let Some(t) = &master.metadata.target {
        header.set_string("OBJECT", t);
    }
    header.add_history(&format!(
        "Accumulated from {} frames across {} folds",
        master.metadata.total_frames,
        master.metadata.folds.len()
    ));
    write_fits(master_path, &image, &header)
        .map_err(|e| format!("failed to write master: {e:?}"))?;

    let preview_path = if let Some(p) = args.preview_png_path.as_ref() {
        if !p.trim().is_empty() {
            write_preview_png(&image, Path::new(p))?;
            Some(p.clone())
        } else {
            None
        }
    } else {
        None
    };

    Ok(MasterAccumulateResult {
        sidecar_path: args.sidecar_path,
        master_path: Some(args.master_fits_path),
        preview_path,
        frame_count: master.metadata.total_frames,
        total_integration_sec: master.metadata.total_integration_seconds,
        width: master.geometry.width,
        height: master.geometry.height,
        channels: master.geometry.channels,
        frames_added: 0,
        rejected: 0,
        frame_weights: Vec::new(),
    })
}

fn master_info(args_json: &str) -> Result<MasterAccumulateResult, String> {
    let args: MasterInfoArgs =
        serde_json::from_str(args_json).map_err(|e| format!("invalid info args: {e}"))?;
    let bytes =
        std::fs::read(&args.sidecar_path).map_err(|e| format!("failed to read sidecar: {e}"))?;
    let master =
        IntegratedMaster::deserialize(&bytes).map_err(|e| format!("corrupt sidecar: {e}"))?;
    Ok(MasterAccumulateResult {
        sidecar_path: args.sidecar_path,
        master_path: None,
        preview_path: None,
        frame_count: master.metadata.total_frames,
        total_integration_sec: master.metadata.total_integration_seconds,
        width: master.geometry.width,
        height: master.geometry.height,
        channels: master.geometry.channels,
        frames_added: 0,
        rejected: 0,
        frame_weights: Vec::new(),
    })
}

/// Path of the frozen registration-reference companion FITS written next to a
/// master sidecar at `create` and read back on every `add`.
fn reference_companion_path(sidecar: &Path) -> std::path::PathBuf {
    let mut p = sidecar.to_path_buf();
    // `<sidecar>.ref.fits` — appended (not extension-replaced) so distinct
    // sidecars never collide and the link to the sidecar stays obvious.
    let name = sidecar
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "master".to_string());
    p.set_file_name(format!("{name}.ref.fits"));
    p
}

/// Ensure an image is U16 for the U16-only registration path. F32 frames are
/// rescaled from their finite min..max into 0..65535 (registration uses star
/// *positions* only, so the absolute scaling is irrelevant — the per-night
/// normalization against the frozen baseline restores photometry).
fn ensure_u16(image: &ImageData) -> ImageData {
    if image.pixel_type == PixelType::U16 {
        return image.clone();
    }
    to_u16_for_preview(image)
}

// =============================================================================
// api_build_master_flat implementation
// =============================================================================

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct BuildMasterFlatArgs {
    /// Raw flat-frame paths.
    flat_paths: Vec<String>,
    /// Optional master bias (short flats) or master dark-flat (long flats) path.
    bias_or_dark_flat: Option<String>,
    /// `"f32"` (default, lossless unit-mean) | `"u16"` (mean 32768).
    output_bit_depth: String,
    /// `"sigmaClip"` (default) | `"median"` | `"mean"`.
    method: String,
    /// Sigma-clip κ / iterations, used only when `method == "sigmaClip"`.
    sigma_kappa: f64,
    sigma_iterations: u32,
    /// Output FITS path (required).
    output_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct BuildMasterFlatResult {
    output_path: String,
    frame_count: u32,
    /// Pre-normalization mean (illumination level).
    input_mean: f64,
    /// Post-normalization mean (≈ unit-mean target).
    output_mean: f64,
    width: u32,
    height: u32,
    channels: u32,
    output_bit_depth: String,
}

fn build_master_flat_impl(args: BuildMasterFlatArgs) -> Result<BuildMasterFlatResult, String> {
    if args.flat_paths.is_empty() {
        return Err("no flat frames supplied".to_string());
    }
    if args.output_path.trim().is_empty() {
        return Err("output_path is required".to_string());
    }

    let flats: Vec<ImageData> = args
        .flat_paths
        .iter()
        .map(|p| {
            read_image(Path::new(p))
                .map(|r| r.image)
                .map_err(|e| format!("failed to read flat '{p}': {e}"))
        })
        .collect::<Result<_, _>>()?;

    let pedestal = load_optional_master(&args.bias_or_dark_flat, "bias/dark-flat")?;

    let output_type = match args.output_bit_depth.trim().to_ascii_lowercase().as_str() {
        "" | "f32" => MasterOutputType::F32,
        "u16" => MasterOutputType::U16,
        other => return Err(format!("unknown output bit depth '{other}'")),
    };
    let method = match args.method.trim().to_ascii_lowercase().as_str() {
        "" | "sigmaclip" | "sigma_clip" => CombineMethod::SigmaClip {
            kappa: if args.sigma_kappa > 0.0 {
                args.sigma_kappa
            } else {
                3.0
            },
            iterations: if args.sigma_iterations > 0 {
                args.sigma_iterations
            } else {
                5
            },
        }, // sigma_iterations is u32 (see SigmaClip below)
        "median" => CombineMethod::Median,
        "mean" => CombineMethod::Mean,
        other => return Err(format!("unknown combine method '{other}'")),
    };

    let config = MasterFlatConfig {
        method,
        output_type,
    };
    let master = build_master_flat(&flats, pedestal.as_ref(), config)
        .map_err(|e| format!("master-flat build failed: {e}"))?;

    let out_path = Path::new(&args.output_path);
    ensure_parent_dir(out_path)?;
    let mut header = FitsHeader::new();
    header.set_string("IMAGETYP", "FLAT");
    header.set_string("FRAMETYP", "MASTER");
    header.set_string("CALSTAT", "Nightshade master flat");
    header.set_int("NFRAMES", master.frame_count as i64);
    // FITS keywords are capped at 8 chars (see `fits::is_valid_keyword`).
    header.set_float("INMEAN", master.input_mean);
    header.set_float("OUTMEAN", master.output_mean);
    write_fits(out_path, &master.image, &header)
        .map_err(|e| format!("failed to write flat: {e:?}"))?;

    Ok(BuildMasterFlatResult {
        output_path: args.output_path,
        frame_count: master.frame_count,
        input_mean: master.input_mean,
        output_mean: master.output_mean,
        width: master.image.width,
        height: master.image.height,
        channels: master.image.channels,
        output_bit_depth: match output_type {
            MasterOutputType::F32 => "f32".to_string(),
            MasterOutputType::U16 => "u16".to_string(),
        },
    })
}

// =============================================================================
// api_save_fits_master implementation
// =============================================================================

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct SaveFitsMasterArgs {
    width: u32,
    height: u32,
    channels: u32,
    /// `"f32"` | `"u16"`.
    pixel_type: String,
    /// F32 sample buffer (channel-interleaved) when `pixelType == "f32"`.
    f32_data: Vec<f32>,
    /// U16 sample buffer (channel-interleaved) when `pixelType == "u16"`.
    u16_data: Vec<u16>,
    output_path: String,
    /// Optional provenance header cards (key → string value).
    object: Option<String>,
    filter: Option<String>,
    frame_count: Option<i64>,
    total_integration_sec: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct SaveFitsMasterResult {
    output_path: String,
    width: u32,
    height: u32,
    channels: u32,
    pixel_type: String,
}

fn save_fits_master_impl(args: SaveFitsMasterArgs) -> Result<SaveFitsMasterResult, String> {
    if args.output_path.trim().is_empty() {
        return Err("output_path is required".to_string());
    }
    if args.width == 0 || args.height == 0 || args.channels == 0 {
        return Err("width/height/channels must be > 0".to_string());
    }
    let expected = (args.width as usize) * (args.height as usize) * (args.channels as usize);

    let (image, pt) = match args.pixel_type.trim().to_ascii_lowercase().as_str() {
        "f32" => {
            if args.f32_data.len() != expected {
                return Err(format!(
                    "f32Data has {} samples but width×height×channels = {}",
                    args.f32_data.len(),
                    expected
                ));
            }
            (
                ImageData::from_f32(args.width, args.height, args.channels, &args.f32_data),
                "f32",
            )
        }
        "u16" => {
            if args.u16_data.len() != expected {
                return Err(format!(
                    "u16Data has {} samples but width×height×channels = {}",
                    args.u16_data.len(),
                    expected
                ));
            }
            (
                ImageData::from_u16(args.width, args.height, args.channels, &args.u16_data),
                "u16",
            )
        }
        other => return Err(format!("unknown pixel type '{other}'; expected f32 or u16")),
    };

    let out_path = Path::new(&args.output_path);
    ensure_parent_dir(out_path)?;
    let mut header = FitsHeader::new();
    header.set_string("IMAGETYP", "MASTER_LIGHT");
    header.set_string("FRAMETYP", "MASTER");
    header.set_string("CALSTAT", "Nightshade master (re-export)");
    if let Some(o) = &args.object {
        header.set_string("OBJECT", o);
    }
    if let Some(f) = &args.filter {
        header.set_string("FILTER", f);
    }
    if let Some(n) = args.frame_count {
        header.set_int("NFRAMES", n);
    }
    if let Some(s) = args.total_integration_sec {
        header.set_float("EXPTIME", s);
    }
    write_fits(out_path, &image, &header)
        .map_err(|e| format!("failed to write FITS master: {e:?}"))?;

    Ok(SaveFitsMasterResult {
        output_path: args.output_path,
        width: args.width,
        height: args.height,
        channels: args.channels,
        pixel_type: pt.to_string(),
    })
}

// =============================================================================
// Shared helpers
// =============================================================================

/// Read an optional calibration master by path. Empty / `None` → `Ok(None)`.
fn load_optional_master(path: &Option<String>, label: &str) -> Result<Option<ImageData>, String> {
    match path {
        Some(p) if !p.trim().is_empty() => {
            let read = read_image(Path::new(p))
                .map_err(|e| format!("failed to read {label} master '{p}': {e}"))?;
            Ok(Some(read.image))
        }
        _ => Ok(None),
    }
}

/// Pick the reference frame index: an explicit path among the loaded lights, or
/// (for `"auto"`/empty) the highest-quality sub by an SNR·sharpness·roundness
/// composite measured on the *un-aligned* light.
fn choose_reference(
    reference: &Option<String>,
    loaded: &[LoadedLight],
    q_cfg: &FrameQualityConfig,
) -> Result<usize, String> {
    if let Some(r) = reference {
        let r = r.trim();
        if !r.is_empty() && !r.eq_ignore_ascii_case("auto") {
            return loaded
                .iter()
                .position(|l| l.path == r)
                .ok_or_else(|| format!("reference '{r}' is not among the supplied lights"));
        }
    }
    // Auto: highest composite quality.
    let mut best_index = 0usize;
    let mut best_score = f64::NEG_INFINITY;
    for (i, l) in loaded.iter().enumerate() {
        let score = match aligned_quality(&l.image, q_cfg) {
            Some(q) => {
                let round = q.eccentricity.map(|e| (1.0 - e).max(0.0)).unwrap_or(1.0);
                let sharp = if q.fwhm > 0.0 { 1.0 / q.fwhm } else { 0.0 };
                q.snr.max(0.0) * sharp * round
            }
            None => f64::NEG_INFINITY,
        };
        if score > best_score {
            best_score = score;
            best_index = i;
        }
    }
    Ok(best_index)
}

/// Measure [`FrameQuality`] on an image, deriving a luminance plane for RGB so
/// the metric is channel-agnostic (the weighting + reference math expects a
/// single plane).
fn aligned_quality(image: &ImageData, cfg: &FrameQualityConfig) -> Option<FrameQuality> {
    if image.channels <= 1 {
        return analyze_frame_quality(image, cfg);
    }
    // Average channels into a luminance plane.
    let data = image.as_u16()?;
    let locations = (image.width as usize) * (image.height as usize);
    let chan = image.channels as usize;
    if data.len() != locations * chan {
        return None;
    }
    let mut luma = vec![0u16; locations];
    for (loc, out) in luma.iter_mut().enumerate() {
        let mut sum = 0u32;
        for ch in 0..chan {
            sum += data[loc * chan + ch] as u32;
        }
        *out = (sum / chan as u32) as u16;
    }
    let plane = ImageData::from_u16(image.width, image.height, 1, &luma);
    analyze_frame_quality(&plane, cfg)
}

/// Flatten an [`ImageData`] (U16 or F32) into a channel-interleaved f64 buffer.
fn image_to_f64(image: &ImageData) -> Vec<f64> {
    match image.pixel_type {
        PixelType::U16 => image
            .as_u16()
            .map(|v| v.into_iter().map(|x| x as f64).collect())
            .unwrap_or_default(),
        PixelType::F32 => image
            .as_f32()
            .map(|v| v.into_iter().map(|x| x as f64).collect())
            .unwrap_or_default(),
        _ => Vec::new(),
    }
}

/// Derive a per-location luminance buffer (mean of channels) from a
/// channel-interleaved f64 buffer — used to build the zero-fill coverage mask.
fn derive_luma_f64(pixels: &[f64], locations: usize, channels: usize) -> Vec<f64> {
    if channels == 1 {
        return pixels.to_vec();
    }
    let mut luma = vec![0.0f64; locations];
    for (loc, out) in luma.iter_mut().enumerate() {
        let mut sum = 0.0;
        for ch in 0..channels {
            sum += pixels[loc * channels + ch];
        }
        *out = sum / channels as f64;
    }
    luma
}

/// Extract one channel plane from a channel-interleaved f64 buffer.
fn extract_channel(pixels: &[f64], locations: usize, channels: usize, ch: usize) -> Vec<f64> {
    let mut out = vec![0.0f64; locations];
    for (loc, o) in out.iter_mut().enumerate() {
        *o = pixels[loc * channels + ch];
    }
    out
}

/// Write one channel plane back into a channel-interleaved f64 buffer.
fn write_channel(pixels: &mut [f64], locations: usize, channels: usize, ch: usize, plane: &[f64]) {
    for loc in 0..locations {
        pixels[loc * channels + ch] = plane[loc];
    }
}

fn build_registration_config(a: &AlignArgs) -> Result<RegistrationConfig, String> {
    let transform_kind = match a.model.trim().to_ascii_lowercase().as_str() {
        "similarity" => TransformKind::Similarity,
        "" | "affine" => TransformKind::Affine,
        "homography" => TransformKind::Homography,
        other => return Err(format!("unknown align model '{other}'")),
    };
    let interpolator = match a.resampler.trim().to_ascii_lowercase().as_str() {
        "bilinear" => Interpolator::Bilinear,
        "catmullrom" | "catmull_rom" => Interpolator::CatmullRom,
        "" | "lanczos3" | "lanczos" => Interpolator::Lanczos3,
        other => return Err(format!("unknown resampler '{other}'")),
    };
    let mut cfg = RegistrationConfig {
        transform_kind,
        interpolator,
        ..RegistrationConfig::default()
    };
    if a.ransac_threshold_px > 0.0 {
        cfg.ransac_threshold_px = a.ransac_threshold_px;
    }
    if a.max_ref_stars > 0 {
        cfg.max_stars_for_matching = a.max_ref_stars;
    }
    apply_detection_overrides(&mut cfg.star_detection, &a.detection);
    Ok(cfg)
}

/// Apply non-zero star-detection overrides onto a base [`StarDetectionConfig`],
/// leaving each unset (zero) knob at its production default.
fn apply_detection_overrides(cfg: &mut nightshade_imaging::StarDetectionConfig, d: &DetectionArgs) {
    if d.detection_sigma > 0.0 {
        cfg.detection_sigma = d.detection_sigma;
    }
    if d.min_area > 0 {
        cfg.min_area = d.min_area;
    }
    if d.max_eccentricity > 0.0 {
        cfg.max_eccentricity = d.max_eccentricity;
    }
    if d.min_hfr > 0.0 {
        cfg.min_hfr = d.min_hfr;
    }
    if d.min_snr > 0.0 {
        cfg.min_snr = d.min_snr;
    }
    if d.max_sharpness > 0.0 {
        cfg.max_sharpness = d.max_sharpness;
    }
}

fn build_weight_formula(a: &WeightingArgs) -> Result<WeightFormula, String> {
    Ok(match a.formula.trim().to_ascii_lowercase().as_str() {
        "snr" => WeightFormula::Snr,
        "" | "snrsquared" | "snr_squared" => WeightFormula::SnrSquared,
        "fwhminverse" | "fwhm_inverse" => WeightFormula::FwhmInverse,
        "custom" => WeightFormula::Custom {
            snr_pow: a.snr_pow,
            fwhm_pow: a.fwhm_pow,
            ecc_pow: a.ecc_pow,
        },
        other => return Err(format!("unknown weight formula '{other}'")),
    })
}

fn build_normalization_config(a: &NormalizationArgs) -> Result<NormalizationConfig, String> {
    let mode = match a.mode.trim().to_ascii_lowercase().as_str() {
        "" | "global" => NormMode::Global,
        "local" => {
            if a.local_rows == 0 || a.local_cols == 0 {
                return Err("local normalization requires localRows and localCols > 0".to_string());
            }
            NormMode::Local {
                rows: a.local_rows,
                cols: a.local_cols,
            }
        }
        other => return Err(format!("unknown normalization mode '{other}'")),
    };
    Ok(NormalizationConfig {
        mode,
        ..NormalizationConfig::default()
    })
}

fn build_integration_config(
    a: &IntegrationArgs,
    sub_count: usize,
) -> Result<IntegrationConfig, String> {
    let combine = match a.combine.trim().to_ascii_lowercase().as_str() {
        "" | "mean" => Combine::Mean,
        "median" => Combine::Median,
        other => return Err(format!("unknown combine '{other}'")),
    };
    let reject = match a.reject.trim().to_ascii_lowercase().as_str() {
        "auto" | "" => auto_reject(sub_count, a.reject_low, a.reject_high),
        "none" => Reject::None,
        "sigmaclip" | "sigma_clip" => Reject::SigmaClip {
            low: a.reject_low,
            high: a.reject_high,
        },
        "winsorizedsigma" | "winsorized_sigma" | "winsorizedsigmaclip" => {
            Reject::WinsorizedSigmaClip {
                low: a.reject_low,
                high: a.reject_high,
            }
        }
        "linearfit" | "linear_fit" | "linearfitclip" => Reject::LinearFitClip {
            low: a.reject_low,
            high: a.reject_high,
        },
        "percentile" | "percentileclip" => Reject::PercentileClip {
            low: a.reject_low,
            high: a.reject_high,
        },
        "minmax" | "min_max" => Reject::MinMax {
            n_low: a.min_max_low,
            n_high: a.min_max_high,
        },
        other => return Err(format!("unknown reject algorithm '{other}'")),
    };
    let output_type = match a.output_bit_depth.trim().to_ascii_lowercase().as_str() {
        "" | "f32" => PixelType::F32,
        "u16" => PixelType::U16,
        other => return Err(format!("unknown output bit depth '{other}'")),
    };
    Ok(IntegrationConfig {
        combine,
        reject,
        output_type,
        generate_rejection_map: a.generate_rejection_map,
        generate_weight_map: false,
        min_coverage: 1,
    })
}

/// Smart reject-algorithm selection by sub count (PixInsight-style):
/// `<8 → percentile`, `8–24 → winsorized-σ`, `≥25 → linear-fit`.
fn auto_reject(sub_count: usize, low: f64, high: f64) -> Reject {
    if sub_count < 8 {
        // Percentile bounds are fractions; map the sigma-style inputs to a
        // sensible default trim band when in "auto" mode.
        Reject::PercentileClip {
            low: 0.2,
            high: 0.1,
        }
    } else if sub_count < 25 {
        Reject::WinsorizedSigmaClip { low, high }
    } else {
        Reject::LinearFitClip { low, high }
    }
}

fn build_master_header(
    sub_count: usize,
    int_args: &IntegrationArgs,
    reference_wcs: Option<&WcsInfo>,
) -> FitsHeader {
    let mut header = FitsHeader::new();
    header.set_string("IMAGETYP", "MASTER_LIGHT");
    header.set_string("FRAMETYP", "MASTER");
    header.set_string("CALSTAT", "Nightshade post-session integration");
    header.set_int("NFRAMES", sub_count as i64);
    // FITS keywords are capped at 8 chars (see `fits::is_valid_keyword`).
    header.set_string("COMBMETH", &int_args.combine);
    header.set_string("REJECTM", &int_args.reject);
    header.add_history(&format!(
        "Integrated {sub_count} subs (combine={}, reject={})",
        int_args.combine, int_args.reject
    ));
    // Carry the registration reference's WCS into the master so the mosaic
    // stitcher's `wcs_from_header` succeeds *without* a post-hoc plate solve. The
    // integration output lives on the reference's pixel grid (every sub is
    // resampled onto it), so the reference's CRVAL/CRPIX/CD matrix describes the
    // master 1:1. Absent on the reference → left absent here; the project-service
    // cluster gates WCS-less panels out of the stitch.
    if let Some(wcs) = reference_wcs {
        add_wcs_headers(&mut header, wcs);
        header.add_history("WCS carried from registration reference frame");
    }
    header
}

/// Read the **registration reference** frame's WCS straight from its FITS
/// header, so the integrated master can carry it (see [`build_master_header`]).
///
/// Best-effort by construction: a reference that is not a FITS file, is
/// unreadable, or simply carries no astrometry yields `None` — integration still
/// produces a master, just without a stamped WCS (the stitcher then gates that
/// panel out). Mirrors the stitcher's `mosaic::wcs_from_header`: prefer an
/// explicit `CD1_1..CD2_2` matrix, fall back to the older `CDELT1/2` (+ optional
/// `CROTA2`) convention, and default `CRPIX` to the geometric centre.
fn reference_wcs_from_fits(path: &str) -> Option<WcsInfo> {
    // Only FITS carries a typed WCS header through this reader path; other
    // formats (XISF/RAW) flatten keywords lossily, so we don't attempt them.
    let ext = Path::new(path)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if ext != "fits" && ext != "fit" && ext != "fts" {
        return None;
    }
    let (_image, header) = read_fits(Path::new(path)).ok()?;

    let crval1 = header.get_float("CRVAL1")?;
    let crval2 = header.get_float("CRVAL2")?;
    let naxis1 = header.get_int("NAXIS1").unwrap_or(0) as f64;
    let naxis2 = header.get_int("NAXIS2").unwrap_or(0) as f64;
    let crpix1 = header
        .get_float("CRPIX1")
        .unwrap_or_else(|| naxis1 / 2.0 + 0.5);
    let crpix2 = header
        .get_float("CRPIX2")
        .unwrap_or_else(|| naxis2 / 2.0 + 0.5);

    // --- Prefer an explicit CD matrix. ---
    if let (Some(cd1_1), Some(cd2_2)) = (header.get_float("CD1_1"), header.get_float("CD2_2")) {
        return Some(WcsInfo {
            crval1,
            crval2,
            crpix1,
            crpix2,
            cd1_1,
            cd1_2: header.get_float("CD1_2").unwrap_or(0.0),
            cd2_1: header.get_float("CD2_1").unwrap_or(0.0),
            cd2_2,
        });
    }

    // --- Fall back to CDELT + CROTA2 (older WCS convention). ---
    let cdelt1 = header.get_float("CDELT1")?;
    let cdelt2 = header.get_float("CDELT2")?;
    let crota2 = header.get_float("CROTA2").unwrap_or(0.0).to_radians();
    let cos_r = crota2.cos();
    let sin_r = crota2.sin();
    Some(WcsInfo {
        crval1,
        crval2,
        crpix1,
        crpix2,
        cd1_1: cdelt1 * cos_r,
        cd1_2: -cdelt2 * sin_r,
        cd2_1: cdelt1 * sin_r,
        cd2_2: cdelt2 * cos_r,
    })
}

/// Write a stretched 8-bit preview PNG of a (U16 or F32) master.
///
/// F32 masters are first rescaled into U16 (preserving relative tone) so the
/// existing STF auto-stretch + `apply_stretch` path applies; the result is an
/// 8-bit (mono) or interleaved-RGB PNG written via the `image` crate.
///
/// `pub(crate)` so the sibling drizzle path ([`crate::api::finishing_combine`])
/// can emit the same stretched preview alongside its drizzled master FITS rather
/// than re-implementing the stretch.
pub(crate) fn write_preview_png(master: &ImageData, path: &Path) -> Result<(), String> {
    ensure_parent_dir(path)?;
    let u16_master = to_u16_for_preview(master);

    let width = u16_master.width;
    let height = u16_master.height;
    let channels = u16_master.channels;

    if channels == 1 {
        let params = auto_stretch_stf(&u16_master);
        let eight = apply_stretch(&u16_master, &params);
        let img = image::GrayImage::from_raw(width, height, eight)
            .ok_or_else(|| "failed to build preview buffer".to_string())?;
        img.save(path)
            .map_err(|e| format!("failed to write preview PNG: {e}"))
    } else if channels == 3 {
        let rgb = u16_master
            .as_u16()
            .ok_or_else(|| "RGB preview requires u16 master".to_string())?;
        let (r, g, b) = auto_stretch_rgb_with_mode(&rgb, width, height, RgbStretchMode::Linked);
        let eight = apply_stretch_rgb_per_channel(&rgb, width, height, &r, &g, &b);
        let img: image::RgbImage = image::ImageBuffer::from_raw(width, height, eight)
            .ok_or_else(|| "failed to build RGB preview buffer".to_string())?;
        img.save(path)
            .map_err(|e| format!("failed to write preview PNG: {e}"))
    } else {
        Err(format!("unsupported channel count {channels} for preview"))
    }
}

/// Convert any master into a U16 image for the auto-stretch preview path.
/// U16 is passed through; F32 is rescaled from its finite min..max into 0..65535.
fn to_u16_for_preview(master: &ImageData) -> ImageData {
    if master.pixel_type == PixelType::U16 {
        return master.clone();
    }
    let data = master.as_f32().unwrap_or_default();
    if data.is_empty() {
        return ImageData::from_u16(master.width, master.height, master.channels, &[]);
    }
    let mut lo = f64::INFINITY;
    let mut hi = f64::NEG_INFINITY;
    for &v in &data {
        let v = v as f64;
        if v.is_finite() {
            lo = lo.min(v);
            hi = hi.max(v);
        }
    }
    let u16data: Vec<u16> = if !lo.is_finite() || !hi.is_finite() || hi <= lo {
        vec![0u16; data.len()]
    } else {
        let range = hi - lo;
        data.iter()
            .map(|&v| {
                let n = ((v as f64 - lo) / range).clamp(0.0, 1.0);
                (n * 65535.0).round() as u16
            })
            .collect()
    };
    ImageData::from_u16(master.width, master.height, master.channels, &u16data)
}

fn ensure_parent_dir(path: &Path) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("failed to create directory {}: {e}", parent.display()))?;
        }
    }
    Ok(())
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use nightshade_imaging::read_fits;
    use std::path::PathBuf;

    /// A scratch directory that deletes itself when the test ends.
    /// `Drop` rather than the trailing `remove_file` calls these tests used to
    /// finish with: the leak was worst exactly when a test FAILED, and a
    /// trailing cleanup never runs while a panic unwinds — drop does.
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

    /// Unique scratch directory so parallel test runs don't collide.
    fn temp_dir(prefix: &str) -> TempDir {
        let n = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let p = std::env::temp_dir().join(format!("ns_ps_{prefix}_{}_{n}", std::process::id()));
        std::fs::create_dir_all(&p).unwrap();
        TempDir(p)
    }

    /// Deterministic, well-separated bright stars for a `size`x`size` frame —
    /// mirrors the registration module's synthetic field so the quad matcher has
    /// distinctive asterisms to lock onto.
    fn base_stars(size: f64) -> Vec<(f64, f64, f64)> {
        vec![
            (size * 0.18, size * 0.22, 9000.0),
            (size * 0.72, size * 0.16, 12000.0),
            (size * 0.40, size * 0.55, 15000.0),
            (size * 0.83, size * 0.61, 8000.0),
            (size * 0.27, size * 0.78, 11000.0),
            (size * 0.61, size * 0.84, 10000.0),
            (size * 0.52, size * 0.33, 13000.0),
            (size * 0.12, size * 0.62, 9500.0),
            (size * 0.90, size * 0.40, 7000.0),
            (size * 0.35, size * 0.12, 8500.0),
        ]
    }

    /// A dense, regular grid of equal-brightness stars (peak `6000 * k`) so a
    /// meaningful fraction of pixels sit in the bright tail — this makes the
    /// 95th-percentile SNR proxy responsive to overall brightness `k` (a sparse
    /// field leaves the 95th percentile in the background, brightness-blind).
    fn grid_stars(size: f64, k: f64) -> Vec<(f64, f64, f64)> {
        let step = 12.0;
        let mut out = Vec::new();
        let mut y = step;
        while y < size - step {
            let mut x = step;
            while x < size - step {
                out.push((x, y, 6000.0 * k));
                x += step;
            }
            y += step;
        }
        out
    }

    /// Render a synthetic mono U16 star field with Gaussian PSFs over a flat,
    /// lightly-noised sky.
    fn render_field(size: u32, stars: &[(f64, f64, f64)], background: f64) -> ImageData {
        render_field_psf(size, stars, background, 1.6)
    }

    /// As [`render_field`] but with a configurable PSF width `sigma` (px) — a
    /// larger `sigma` blurs the stars (worse focus/seeing ⇒ larger measured
    /// FWHM ⇒ lower integration weight).
    fn render_field_psf(
        size: u32,
        stars: &[(f64, f64, f64)],
        background: f64,
        sigma: f64,
    ) -> ImageData {
        let w = size as usize;
        let h = size as usize;
        let mut pixels = vec![0f64; w * h];
        for (i, p) in pixels.iter_mut().enumerate() {
            let n = ((i.wrapping_mul(2654435761) >> 8) % 1000) as f64 / 1000.0;
            *p = background + (n - 0.5) * 6.0;
        }
        let two_sigma_sq = 2.0 * sigma * sigma;
        let radius = (sigma * 4.0).ceil() as i64;
        for &(sx, sy, peak) in stars {
            let cx = sx.round() as i64;
            let cy = sy.round() as i64;
            for dy in -radius..=radius {
                for dx in -radius..=radius {
                    let x = cx + dx;
                    let y = cy + dy;
                    if x < 0 || y < 0 || x as usize >= w || y as usize >= h {
                        continue;
                    }
                    let ddx = x as f64 - sx;
                    let ddy = y as f64 - sy;
                    let g = peak * (-(ddx * ddx + ddy * ddy) / two_sigma_sq).exp();
                    pixels[y as usize * w + x as usize] += g;
                }
            }
        }
        let u16data: Vec<u16> = pixels
            .iter()
            .map(|v| v.round().clamp(0.0, 65535.0) as u16)
            .collect();
        ImageData::from_u16(size, size, 1, &u16data)
    }

    /// Shift star positions by (dx, dy), keeping them in-frame.
    fn shift_stars(stars: &[(f64, f64, f64)], dx: f64, dy: f64) -> Vec<(f64, f64, f64)> {
        stars.iter().map(|&(x, y, f)| (x + dx, y + dy, f)).collect()
    }

    fn write_field_fits(path: &Path, image: &ImageData) {
        let mut h = FitsHeader::new();
        h.set_string("IMAGETYP", "LIGHT");
        write_fits(path, image, &h).expect("write synthetic light");
    }

    /// Relaxed star-detection overrides for clean synthetic Gaussian PSFs (the
    /// production default detector deliberately rejects idealised single-peak
    /// Gaussians — see the registration module's own test config). This is the
    /// real, user-exposed `align.detection` knob, not a test backdoor.
    fn synthetic_align() -> serde_json::Value {
        serde_json::json!({
            "model": "similarity",
            "resampler": "bilinear",
            "detection": {
                "detectionSigma": 3.0,
                "minArea": 1,
                "maxEccentricity": 1.0,
                "minHfr": 0.5,
                "minSnr": 3.0,
                "maxSharpness": 1.0
            }
        })
    }

    /// End-to-end: three slightly-shifted synthetic subs integrate into a linear
    /// FITS master + preview PNG, and the per-frame stats report all three
    /// accepted.
    #[test]
    fn integrate_session_produces_master_and_preview() {
        let dir = temp_dir("integrate_session_produces_master_and_preview");
        let size = 256u32;
        let stars = base_stars(size as f64);
        let mut light_paths = Vec::new();
        let shifts = [(0.0, 0.0), (3.0, -2.0), (-2.0, 4.0)];
        for (i, (dx, dy)) in shifts.iter().enumerate() {
            let field = render_field(size, &shift_stars(&stars, *dx, *dy), 200.0);
            let p = dir.join(format!("light{i}.fits"));
            write_field_fits(&p, &field);
            light_paths.push(p.to_string_lossy().to_string());
        }
        let master_path = dir.join("master.fits");
        let preview_path = dir.join("preview.png");
        let rejection_path = dir.join("rejection.fits");
        let rejection_preview_path = dir.join("rejection_preview.png");

        let args = serde_json::json!({
            "lightPaths": light_paths,
            "reference": "auto",
            "exposuresSec": [60.0, 60.0, 60.0],
            "settings": {
                "align": synthetic_align(),
                "integration": { "reject": "auto", "outputBitDepth": "f32" }
            },
            "output": {
                "masterFitsPath": master_path.to_string_lossy(),
                "previewPngPath": preview_path.to_string_lossy(),
                "rejectionMapPath": rejection_path.to_string_lossy(),
                "rejectionMapPreviewPath": rejection_preview_path.to_string_lossy()
            }
        });

        let resp = api_integrate_session(args.to_string()).expect("integration should succeed");
        let result: IntegrateSessionResult = serde_json::from_str(&resp).unwrap();

        assert_eq!(
            result.frames_integrated, 3,
            "all three subs should integrate"
        );
        assert_eq!(result.frames_rejected, 0);
        assert_eq!(result.width, size);
        assert_eq!(result.height, size);
        assert_eq!(result.channels, 1);
        assert!((result.total_integration_sec - 180.0).abs() < 1e-6);
        assert_eq!(result.per_frame_stats.len(), 3);

        // The master is a real, readable F32 linear FITS of the right geometry.
        let (master_img, _h) = read_fits(master_path.as_path()).expect("read master");
        assert_eq!(master_img.pixel_type, PixelType::F32);
        assert_eq!(master_img.width, size);
        assert_eq!(master_img.height, size);
        assert!(preview_path.exists(), "preview PNG should be written");
        assert!(rejection_path.exists(), "rejection FITS should be written");
        assert!(
            rejection_preview_path.exists(),
            "rejection preview PNG should be written"
        );
        assert_eq!(
            result.rejection_map_preview_path.as_deref(),
            Some(rejection_preview_path.to_string_lossy().as_ref())
        );
        let rejection_preview =
            image::open(&rejection_preview_path).expect("decode rejection preview");
        assert_eq!(rejection_preview.width(), size);
        assert_eq!(rejection_preview.height(), size);
    }

    /// Write a synthetic light whose FITS header carries a plate-solved WCS
    /// (CRVAL/CRPIX + an explicit CD matrix), so the reference-WCS carry-over can
    /// be exercised end-to-end.
    fn write_field_fits_with_wcs(path: &Path, image: &ImageData, wcs: &WcsInfo) {
        let mut h = FitsHeader::new();
        h.set_string("IMAGETYP", "LIGHT");
        add_wcs_headers(&mut h, wcs);
        write_fits(path, image, &h).expect("write synthetic light with WCS");
    }

    /// The integrated master must carry the **registration reference**'s WCS in
    /// its FITS header so the mosaic stitcher can place the panel without a
    /// post-hoc plate solve. Without the carry-over the master has NO WCS and
    /// `read_fits` finds no CRVAL/CD keywords — this test fails.
    #[test]
    fn integrate_session_stamps_reference_wcs_into_master() {
        let dir = temp_dir("integrate_session_stamps_reference_wcs_into_master");
        let size = 256u32;
        let stars = base_stars(size as f64);
        // A representative plate-solved panel WCS: ~1.5 arcsec/px, small rotation.
        let ref_wcs = WcsInfo::from_plate_solve(83.822, -5.391, 12.0, 1.5, size, size);

        let mut light_paths = Vec::new();
        let shifts = [(0.0, 0.0), (3.0, -2.0), (-2.0, 4.0)];
        for (i, (dx, dy)) in shifts.iter().enumerate() {
            let field = render_field(size, &shift_stars(&stars, *dx, *dy), 200.0);
            let p = dir.join(format!("wcslight{i}.fits"));
            // Only the reference (sub 0, selected explicitly below) carries WCS.
            if i == 0 {
                write_field_fits_with_wcs(&p, &field, &ref_wcs);
            } else {
                write_field_fits(&p, &field);
            }
            light_paths.push(p.to_string_lossy().to_string());
        }
        let master_path = dir.join("wcsmaster.fits");

        let args = serde_json::json!({
            "lightPaths": light_paths,
            // Pin the reference to the WCS-bearing sub so the carry-over is
            // deterministic regardless of measured quality.
            "reference": light_paths[0],
            "exposuresSec": [60.0, 60.0, 60.0],
            "settings": {
                "align": synthetic_align(),
                "integration": { "reject": "auto", "outputBitDepth": "f32" }
            },
            "output": { "masterFitsPath": master_path.to_string_lossy() }
        });

        let resp = api_integrate_session(args.to_string()).expect("integration should succeed");
        let result: IntegrateSessionResult = serde_json::from_str(&resp).unwrap();
        assert_eq!(result.frames_integrated, 3);

        // Read the master back: it must carry the reference's WCS, so the
        // stitcher's `wcs_from_header` (CRVAL1/2 + CD matrix) succeeds. FITS cards
        // serialize floats at finite precision, so compare with a tolerance tight
        // enough to prove it's the reference's WCS (sub-arcsec on a ~1.5"/px CD,
        // sub-µdeg on RA/Dec), not a default or invented one.
        let (_master_img, h) = read_fits(master_path.as_path()).expect("read master");
        let near = |key: &str, want: f64| {
            let got = h
                .get_float(key)
                .unwrap_or_else(|| panic!("master is missing WCS keyword {key}"));
            assert!(
                (got - want).abs() <= want.abs() * 1e-9 + 1e-12,
                "{key}: master {got} != reference {want}"
            );
        };
        near("CRVAL1", ref_wcs.crval1);
        near("CRVAL2", ref_wcs.crval2);
        near("CRPIX1", ref_wcs.crpix1);
        near("CRPIX2", ref_wcs.crpix2);
        near("CD1_1", ref_wcs.cd1_1);
        near("CD1_2", ref_wcs.cd1_2);
        near("CD2_1", ref_wcs.cd2_1);
        near("CD2_2", ref_wcs.cd2_2);
        assert_eq!(h.get_string("CTYPE1"), Some("RA---TAN"));
    }

    /// A reference frame with NO astrometry must leave the master WCS-less (the
    /// project-service cluster gates such panels out of the stitch) — the
    /// carry-over must never invent a WCS.
    #[test]
    fn integrate_session_leaves_master_wcs_absent_when_reference_has_none() {
        let dir = temp_dir("integrate_session_leaves_master_wcs_absent_when_reference_has_none");
        let size = 256u32;
        let stars = base_stars(size as f64);
        let mut light_paths = Vec::new();
        let shifts = [(0.0, 0.0), (3.0, -2.0), (-2.0, 4.0)];
        for (i, (dx, dy)) in shifts.iter().enumerate() {
            let field = render_field(size, &shift_stars(&stars, *dx, *dy), 200.0);
            let p = dir.join(format!("nowcslight{i}.fits"));
            write_field_fits(&p, &field); // no WCS on any sub
            light_paths.push(p.to_string_lossy().to_string());
        }
        let master_path = dir.join("nowcsmaster.fits");
        let args = serde_json::json!({
            "lightPaths": light_paths,
            "reference": light_paths[0],
            "exposuresSec": [60.0, 60.0, 60.0],
            "settings": {
                "align": synthetic_align(),
                "integration": { "reject": "auto", "outputBitDepth": "f32" }
            },
            "output": { "masterFitsPath": master_path.to_string_lossy() }
        });
        api_integrate_session(args.to_string()).expect("integration should succeed");

        let (_img, h) = read_fits(master_path.as_path()).expect("read master");
        assert_eq!(
            h.get_float("CRVAL1"),
            None,
            "no WCS to carry → none stamped"
        );
        assert_eq!(h.get_float("CD1_1"), None);
    }

    /// Multi-night accumulation: create -> add -> finalize round-trips through
    /// the sidecar and yields a finalized master with the accumulated count.
    #[test]
    fn master_accumulate_create_add_finalize() {
        let dir = temp_dir("master_accumulate_create_add_finalize");
        let size = 256u32;
        let stars = base_stars(size as f64);

        let ref_field = render_field(size, &stars, 200.0);
        let ref_path = dir.join("ref.fits");
        write_field_fits(&ref_path, &ref_field);

        let sidecar = dir.join("master.nsmaster");
        let create = serde_json::json!({
            "op": "create",
            "referencePath": ref_path.to_string_lossy(),
            "sidecarPath": sidecar.to_string_lossy(),
            "filter": "L"
        });
        let r = api_master_accumulate(create.to_string()).expect("create");
        let cr: MasterAccumulateResult = serde_json::from_str(&r).unwrap();
        assert_eq!(cr.frame_count, 0, "create folds no frames");
        assert_eq!(cr.channels, 1);

        let mut light_paths = Vec::new();
        for (i, (dx, dy)) in [(0.0f64, 0.0f64), (2.0, -3.0)].iter().enumerate() {
            let field = render_field(size, &shift_stars(&stars, *dx, *dy), 200.0);
            let p = dir.join(format!("add{i}.fits"));
            write_field_fits(&p, &field);
            light_paths.push(p.to_string_lossy().to_string());
        }
        let add = serde_json::json!({
            "op": "add",
            "sidecarPath": sidecar.to_string_lossy(),
            "lightPaths": light_paths,
            "exposuresSec": [60.0, 60.0],
            "label": "2026-06-07",
            "settings": { "align": synthetic_align() }
        });
        let r = api_master_accumulate(add.to_string()).expect("add");
        let ar: MasterAccumulateResult = serde_json::from_str(&r).unwrap();
        assert_eq!(ar.frames_added, 2, "both subs fold in");
        assert_eq!(ar.frame_count, 2);
        assert!((ar.total_integration_sec - 120.0).abs() < 1e-6);

        let master_path = dir.join("acc_master.fits");
        let finalize = serde_json::json!({
            "op": "finalize",
            "sidecarPath": sidecar.to_string_lossy(),
            "masterFitsPath": master_path.to_string_lossy()
        });
        let r = api_master_accumulate(finalize.to_string()).expect("finalize");
        let fr: MasterAccumulateResult = serde_json::from_str(&r).unwrap();
        assert_eq!(fr.frame_count, 2);
        assert_eq!(
            fr.master_path.as_deref(),
            Some(master_path.to_string_lossy().as_ref())
        );

        let (img, _h) = read_fits(master_path.as_path()).expect("read accumulated master");
        assert_eq!(img.pixel_type, PixelType::F32);
        assert_eq!(img.width, size);
    }

    /// IMG-001 regression: folding a good-seeing night and then a uniformly
    /// worse-seeing (blurrier ⇒ larger-FWHM) night into the accumulating master
    /// must give the good night strictly more *total* weight. The old per-fold
    /// max-normalization (`weight_frames`) reset each night's best sub to 1.0,
    /// making the two folds' total weights near-equal regardless of cross-night
    /// quality; `accumulation_weights` anchors both folds on a fixed scale so the
    /// worse night contributes proportionally less.
    #[test]
    fn accumulate_weights_better_night_more_than_worse_night() {
        let dir = temp_dir("accumulate_weights_better_night_more_than_worse_night");
        let size = 256u32;
        let stars = base_stars(size as f64);

        // A dense star grid so the bright-tail SNR proxy (95th-percentile signal
        // over background) actually tracks star brightness — with only a handful
        // of stars the 95th percentile sits in the background and is brightness-
        // blind. The asterism from `base_stars` is overlaid so the quad matcher
        // still has distinctive anchors to register against.
        let mut field_stars = grid_stars(size as f64, 1.0);
        field_stars.extend_from_slice(&stars);

        // Reference frame defines the master grid/anchor (bright, like night A).
        let ref_field = render_field(size, &field_stars, 200.0);
        let ref_path = dir.join("img001_ref.fits");
        write_field_fits(&ref_path, &ref_field);

        let sidecar = dir.join("img001_master.nsmaster");
        let create = serde_json::json!({
            "op": "create",
            "referencePath": ref_path.to_string_lossy(),
            "sidecarPath": sidecar.to_string_lossy(),
            "filter": "L"
        });
        api_master_accumulate(create.to_string()).expect("create");

        // Helper: render two slightly-shifted subs whose stars are scaled to
        // brightness `k`, write them, fold them in, return this fold's weights.
        let fold = |k: f64, label: &str, tag: &str| -> Vec<f64> {
            let mut paths = Vec::new();
            for (i, (dx, dy)) in [(0.0f64, 0.0f64), (2.0, -3.0)].iter().enumerate() {
                let mut night = grid_stars(size as f64, k);
                night.extend_from_slice(&stars);
                let field = render_field(size, &shift_stars(&night, *dx, *dy), 200.0);
                let p = dir.join(format!("{tag}{i}.fits"));
                write_field_fits(&p, &field);
                paths.push(p.to_string_lossy().to_string());
            }
            let add = serde_json::json!({
                "op": "add",
                "sidecarPath": sidecar.to_string_lossy(),
                "lightPaths": paths,
                "exposuresSec": [60.0, 60.0],
                "label": label,
                "settings": { "align": synthetic_align() }
            });
            let r = api_master_accumulate(add.to_string()).expect("add fold");
            let res: MasterAccumulateResult = serde_json::from_str(&r).unwrap();
            assert_eq!(res.frames_added, 2, "both subs of '{label}' must fold in");
            res.frame_weights
        };

        // Night A: full-brightness subs (high SNR). Night B: uniformly dimmer ⇒
        // lower SNR ⇒ lower per-sub quality on every sub.
        let w_a = fold(1.0, "night-A", "img001_a");
        let w_b = fold(0.45, "night-B", "img001_b");

        let sum_a: f64 = w_a.iter().sum();
        let sum_b: f64 = w_b.iter().sum();
        assert!(sum_a > 0.0 && sum_b > 0.0, "weights must be positive");
        assert!(
            sum_a > sum_b * 1.3,
            "the better-seeing night must carry meaningfully more total weight across folds: A={sum_a} ({w_a:?}) B={sum_b} ({w_b:?})"
        );
    }

    /// Master-flat build normalizes to unit mean and writes a readable FITS.
    #[test]
    fn build_master_flat_unit_mean() {
        let dir = temp_dir("build_master_flat_unit_mean");
        let size = 48u32;
        let len = (size * size) as usize;
        let mut flat_paths = Vec::new();
        for i in 0..5u32 {
            let data: Vec<u16> = (0..len)
                .map(|p| {
                    let x = (p % size as usize) as f64 / size as f64;
                    (20000.0 + 8000.0 * x + i as f64 * 50.0) as u16
                })
                .collect();
            let img = ImageData::from_u16(size, size, 1, &data);
            let p = dir.join(format!("flat{i}.fits"));
            let mut h = FitsHeader::new();
            h.set_string("IMAGETYP", "FLAT");
            write_fits(&p, &img, &h).unwrap();
            flat_paths.push(p.to_string_lossy().to_string());
        }
        let out = dir.join("master_flat.fits");
        let args = serde_json::json!({
            "flatPaths": flat_paths,
            "outputBitDepth": "f32",
            "method": "median",
            "outputPath": out.to_string_lossy()
        });
        let r = api_build_master_flat(args.to_string()).expect("flat build");
        let res: BuildMasterFlatResult = serde_json::from_str(&r).unwrap();
        assert_eq!(res.frame_count, 5);
        assert!(
            (res.output_mean - 1.0).abs() < 0.05,
            "output mean {} not ~1.0",
            res.output_mean
        );

        let (img, _h) = read_fits(out.as_path()).unwrap();
        assert_eq!(img.pixel_type, PixelType::F32);
    }

    /// save_fits_master re-exports a buffer with the declared geometry/type.
    #[test]
    fn save_fits_master_round_trips() {
        let dir = temp_dir("save_fits_master_round_trips");
        let size = 16u32;
        let len = (size * size) as usize;
        let f32_data: Vec<f32> = (0..len).map(|i| i as f32 * 0.5).collect();
        let out = dir.join("export.fits");
        let args = serde_json::json!({
            "width": size,
            "height": size,
            "channels": 1,
            "pixelType": "f32",
            "f32Data": f32_data,
            "outputPath": out.to_string_lossy(),
            "object": "M42"
        });
        let r = api_save_fits_master(args.to_string()).expect("save");
        let res: SaveFitsMasterResult = serde_json::from_str(&r).unwrap();
        assert_eq!(res.pixel_type, "f32");
        let (img, h) = read_fits(out.as_path()).unwrap();
        assert_eq!(img.pixel_type, PixelType::F32);
        assert_eq!(img.width, size);
        assert_eq!(h.get_string("OBJECT"), Some("M42"));
    }

    /// Bad JSON and unknown ops surface as errors, never a silent success.
    #[test]
    fn invalid_inputs_error() {
        assert!(api_integrate_session("not json".to_string()).is_err());
        assert!(api_integrate_session(r#"{"lightPaths":[]}"#.to_string()).is_err());
        assert!(api_master_accumulate(r#"{"op":"bogus"}"#.to_string()).is_err());
    }

    /// REGRESSION (senior review blocker #5 — "morning report intelligence is
    /// structurally dead"): every accepted sub MUST surface a positive, finite
    /// `noise` (and `snr`) so the downstream marginal-SNR optimizer
    /// (`integration_curve`, which skips any `noise <= 0` sub from its variance
    /// sums) produces a real, non-zero improvement curve rather than the all-zero
    /// curve the old record — which omitted `noise` entirely, defaulting it to 0
    /// across the FFI — guaranteed.
    ///
    /// This drives the REAL pipeline both ways: `api_integrate_session` measures
    /// the per-sub `FrameQuality`, and then the exact `qualities` map the Dart
    /// `_analyzeAndStoreCurve` builds from these records is fed to the REAL
    /// `api_analyze_night`. The assertions (positive, monotone-non-decreasing
    /// curve; non-zero `target_snr`) fail with the old (noise-less) record and
    /// pass once `noise` rides through — no scripted fake curve can mask it.
    #[test]
    fn per_frame_noise_drives_a_positive_optimizer_curve() {
        let dir = temp_dir("per_frame_noise_drives_a_positive_optimizer_curve");
        use crate::api::finishing_analyze::api_analyze_night;

        let size = 256u32;
        let stars = base_stars(size as f64);
        let mut light_paths = Vec::new();
        let shifts = [(0.0, 0.0), (3.0, -2.0), (-2.0, 4.0), (1.0, 1.0)];
        for (i, (dx, dy)) in shifts.iter().enumerate() {
            let field = render_field(size, &shift_stars(&stars, *dx, *dy), 200.0);
            let p = dir.join(format!("noise_light{i}.fits"));
            write_field_fits(&p, &field);
            light_paths.push(p.to_string_lossy().to_string());
        }
        let master_path = dir.join("noise_master.fits");

        let args = serde_json::json!({
            "lightPaths": light_paths,
            "reference": "auto",
            "exposuresSec": [60.0, 60.0, 60.0, 60.0],
            "settings": {
                "align": synthetic_align(),
                "integration": { "reject": "auto", "outputBitDepth": "f32" }
            },
            "output": { "masterFitsPath": master_path.to_string_lossy() }
        });

        let resp = api_integrate_session(args.to_string()).expect("integration should succeed");
        let result: IntegrateSessionResult = serde_json::from_str(&resp).unwrap();

        // Every accepted sub carries a positive, finite noise + snr — the inputs
        // the optimizer's variance sums need. (Pre-fix: `noise` did not exist on
        // the record, so it crossed the FFI as 0 and killed the curve.)
        let accepted: Vec<&PerFrameRecord> = result
            .per_frame_stats
            .iter()
            .filter(|r| r.accepted)
            .collect();
        assert!(accepted.len() >= 2, "need ≥2 accepted subs to form a curve");
        for r in &accepted {
            let noise = r.noise.expect("accepted sub must surface measured noise");
            assert!(
                noise.is_finite() && noise > 0.0,
                "noise must be positive: {noise}"
            );
            let snr = r.snr.expect("accepted sub must surface measured snr");
            assert!(
                snr.is_finite() && snr >= 0.0,
                "snr must be finite/non-negative: {snr}"
            );
        }

        // Build the exact `qualities` payload the Dart `_analyzeAndStoreCurve`
        // sends (snr + noise + background + starCount + fwhm/eccentricity), and
        // drive the REAL optimizer through `api_analyze_night`.
        let qualities: Vec<serde_json::Value> = accepted
            .iter()
            .map(|r| {
                let mut q = serde_json::Map::new();
                q.insert("snr".into(), serde_json::json!(r.snr.unwrap()));
                q.insert("noise".into(), serde_json::json!(r.noise.unwrap()));
                if let Some(bg) = r.background {
                    q.insert("background".into(), serde_json::json!(bg));
                }
                if let Some(sc) = r.star_count {
                    q.insert("starCount".into(), serde_json::json!(sc));
                }
                if let Some(f) = r.fwhm {
                    q.insert("fwhm".into(), serde_json::json!(f));
                }
                if let Some(e) = r.eccentricity {
                    q.insert("eccentricity".into(), serde_json::json!(e));
                }
                serde_json::Value::Object(q)
            })
            .collect();
        let weights: Vec<f64> = accepted.iter().map(|r| r.weight.max(0.001)).collect();
        let exposures: Vec<f64> = vec![60.0; accepted.len()];

        let night_args = serde_json::json!({
            "qualities": qualities,
            "weights": weights,
            "exposuresS": exposures,
        });
        let night_resp =
            api_analyze_night(night_args.to_string()).expect("analyze_night should succeed");
        let night: serde_json::Value = serde_json::from_str(&night_resp).unwrap();

        let points = night["curve"].as_array().expect("curve points array");
        assert_eq!(
            points.len(),
            accepted.len(),
            "one curve point per accepted sub"
        );

        // The curve is POSITIVE and monotone-non-decreasing in SNR (more subs
        // never lowers the predicted stack SNR), and the full-night anchor SNR is
        // strictly > 0 — the value Dart persists as `target_snr`.
        let mut prev = -1.0_f64;
        for (i, p) in points.iter().enumerate() {
            let snr = p["snr"].as_f64().expect("point snr");
            assert!(
                snr.is_finite() && snr > 0.0,
                "curve point {i} snr must be > 0: {snr}"
            );
            assert!(
                snr + 1e-9 >= prev,
                "curve must be monotone-non-decreasing at point {i}: {snr} < {prev}"
            );
            prev = snr;
        }
        let target_snr = points.last().unwrap()["snr"].as_f64().unwrap();
        assert!(
            target_snr > 0.0,
            "target_snr (full-night anchor) must be non-zero, got {target_snr}"
        );
    }
}
