# Post-Session Image Processing — Technical Design & Decomposition

- **Date:** 2026-06-07
- **Branch:** `roadmap/planetarium-atlas-and-perf`
- **Status:** Design (no implementation yet)
- **North star:** PixInsight-grade integration quality, advanced manual settings with smart defaults, and **multi-night master accumulation** (keep adding new captured subs to an existing master over time).

---

## 0. Scope & Philosophy

Today Nightshade has a strong *live* path (`LiveStacker`, Stack-and-Share) but the *finishing* path is thin: rigid-only registration, incremental sigma-clip only, no per-sub weighting, no normalization, no 16-bit linear master output, no master accumulation, no cohesive "review the night" surface. This document designs the **batch, offline, post-session integration** pipeline that runs *after* a sub-collection exists (one session, one target, possibly across nights) and produces an archival-quality linear master plus a review UI.

Two pipelines coexist on purpose and must **not** be merged:

| Pipeline | Engine | Use | Quality target |
|---|---|---|---|
| **Live** (existing) | `imaging/src/stacking.rs::LiveStacker` | EAA, sequencer `LiveStackingNode`, Stack-and-Share preview | fast, online, single-pass |
| **Post-session** (this design) | new `imaging/src/integration/` modules | morning report, archival master, accumulation | best-effort, multi-pass, batch |

The live engine is a process-wide singleton (see `StackAndShareService` / `LiveStackBusyException`). The post-session engine is **stateless per call** (no singleton) so it can run in an isolate without clobbering a live session.

Reuse, do not rewrite: `ImageData` / `PixelType` (`imaging/src/lib.rs`), `detect_stars` / `DetectedStar` / `frame_eccentricity` / `CameraNoiseModel` / `calculate_stats_u16` (`imaging/src/stats.rs`), `calibrate_frame` and friends (`imaging/src/calibration.rs`), `build_defect_map` / `DefectMap` / `correct_frame_u16` (`imaging/src/defect_map.rs`), `combine_master_frames` (`imaging/src/stacking.rs`), `write_fits` / `read_fits` / `FitsHeader` / `add_wcs_headers` (`imaging/src/fits.rs`), `debayer_cfa_to_rgb` (`imaging/src/stacking.rs`).

---

## 1. Native algorithm modules

New subtree: `native/nightshade_native/imaging/src/integration/` with a `mod.rs` re-exporting the public surface. Each file is single-responsibility, `rayon`-parallel like `calibration.rs`, and unit-tested with synthetic frames (the project idiom — see synthetic-PSF tests in `stats.rs` and the calibration tests).

### 1.1 `integration/align.rs` — advanced star alignment

Supersedes the rigid-only path in `stacking.rs` (`compute_affine_transform`, `apply_transform_bilinear`, `match_stars`). The live engine keeps its rigid path; this module is the high-quality replacement used by batch integration.

**Detection.** Reuse `detect_stars` on the `detection_plane` (luminance proxy for RGB) but tighten for registration: SNR-thresholded, saturation-rejected, edge-margin-rejected, and capped to the brightest `N` (default 200) by flux. Add **flux-weighted centroid refinement** (intensity-weighted barycenter in a small window) and a per-star **PSF sanity gate** (reject stars whose `frame_eccentricity`-style axis ratio implies a hot pixel or trail) to get sub-pixel, outlier-free control points.

**Matching — geometric-invariant, robust to rotation/scale/flip.** Replace nearest-neighbour-by-flux (`match_stars`) with a **triangle/quad asterism matcher** (the astrometry.net / PixInsight StarAlignment approach):

- Build the *k* (default 8) nearest neighbours of each reference star; form **quads** (4-star groups) and compute a **scale/rotation/translation/flip-invariant hash** (the 4-point geometric hash: order the 4 stars, normalise by the most-distant pair, encode the inner two as `(xc, yd)` — invariant under similarity *and* mirror because we canonicalise handedness explicitly).
- Hash reference quads into a spatial bucket map; for each target quad look up matching reference quads by hash distance; each hash agreement votes for a set of star-pair correspondences.
- This is **robust to large rotation, modest scale change, and meridian-flip mirroring** with no prior — exactly the cases rigid NN-flux matching fails on.
- Fallback: if the camera reports no flip and a plate-solve WCS exists for both frames (`WcsInfo` in `fits.rs`), seed correspondences from sky coordinates first (fast path), then refine with quads.

**Transform estimation — RANSAC over a model hierarchy.** From the candidate correspondences, fit with **RANSAC** (random minimal-sample consensus, inlier threshold default 2.0 px, adaptive iteration count from estimated inlier ratio):

- `TransformModel::Similarity` (4 dof: translation + rotation + uniform scale) — minimal sample 2 pairs.
- `TransformModel::Affine` (6 dof) — minimal sample 3 pairs; **default** for most rigs (handles small differential field rotation + plate-scale drift).
- `TransformModel::Homography` (8 dof, projective) — minimal sample 4 pairs; for wide fields / uncorrected optics.
- `TransformModel::ThinPlateSpline { control_points }` — **optional distortion correction** layered *after* a global affine/homography: TPS warp fit to the inlier residuals (regularised, λ default auto from residual scatter) to soak up field curvature / differential refraction. This is the PixInsight "distortion correction" knob.

After RANSAC, **refine** the model with a full least-squares fit over all inliers (Levenberg–Marquardt for homography/TPS; closed-form normal equations for similarity/affine). Report inlier count, RMS residual, peak residual, and the chosen model.

```rust
pub enum TransformModel { Similarity, Affine, Homography, ThinPlateSpline }

pub struct AlignmentResult {
    pub transform: GeometricTransform, // forward map src->ref
    pub model: TransformModel,
    pub inliers: u32,
    pub total_pairs: u32,
    pub rms_residual_px: f64,
    pub peak_residual_px: f64,
}

pub struct GeometricTransform { /* 3x3 homogeneous matrix + optional TPS warp field */ }
impl GeometricTransform {
    pub fn inverse_map(&self, dst_x: f64, dst_y: f64) -> (f64, f64); // for resampling
}

pub fn align_frame(
    reference: &AlignmentReference, // pre-detected ref stars + dims
    frame: &ImageData,
    cfg: &AlignmentConfig,
) -> Result<AlignmentResult, AlignError>;
```

**Resampling — `integration/resample.rs`.** Reverse-map each output pixel through `inverse_map` and interpolate the source with a selectable kernel:

- `Resampler::Bilinear` (fast, live-parity).
- `Resampler::CatmullRom` (cubic, default — good sharpness/ringing tradeoff).
- `Resampler::Lanczos { a }` (a=3 default, **highest quality**, the PixInsight default for registration; windowed-sinc separable kernel).

All resamplers clamp to image bounds, track a **per-output-pixel coverage mask** (0 where the source mapped outside the frame — fed to integration so edges that only some frames cover are weighted/rejected correctly), and operate per-channel in `f64` to avoid intermediate quantisation. Separable Lanczos/Catmull-Rom is `rayon`-parallel over output rows.

### 1.2 `integration/weighting.rs` — per-sub frame weighting

Computes a scalar weight per sub so the best subs dominate the master (PixInsight "image weighting"). Inputs are cheap to derive from primitives already present:

- **Noise estimation:** robust per-frame σ via the **MAD of the residual after a 3×3 median** (k-sigma-robust, matches PixInsight's noise evaluator intent) — new helper, or reuse `CameraNoiseModel` + `calculate_stats_u16` background where available.
- **SNR:** `(median_signal - background) / noise`.
- **FWHM / HFR:** median of detected-star HFR (reuse `calculate_median_hfr` in `stats.rs`).
- **Eccentricity:** `frame_eccentricity(&stars)` (already in `stats.rs`).
- **Star count** and **background level** (transparency/skyglow proxy).

```rust
pub struct FrameQuality {
    pub noise: f64, pub snr: f64, pub fwhm: f64,
    pub eccentricity: Option<f64>, pub star_count: u32, pub background: f64,
}
pub enum WeightFormula { Snr, SnrSquared, FwhmInverse, Custom { snr_pow, fwhm_pow, ecc_pow } }
pub fn frame_weight(q: &FrameQuality, ref_q: &FrameQuality, f: &WeightFormula) -> f64;
```

Default formula mirrors PixInsight's *PSF Signal Weight* spirit: `w ∝ SNR² · (fwhm_ref/fwhm)^a · (1-ecc)^b`, normalised so the best sub = 1.0. Weights also drive a **quality-gate auto-cull** (drop subs below a percentile / above an FWHM multiple) surfaced as a recommendation, not silently applied.

### 1.3 `integration/normalize.rs` — light-frame normalization

Brings every aligned sub onto the reference's photometric scale **before** integration (essential for correct rejection — un-normalised frames make sigma-clip reject signal):

- **Additive (background) match:** estimate background per frame (robust low-percentile / iterative-clipped mean) and subtract the offset to the reference background.
- **Multiplicative (scale) match:** ratio of reference-to-frame signal estimated from a robust linear fit of frame-vs-reference pixels over a shared sample mask (excludes stars/saturation/zero-coverage).
- **Optional local normalization:** a coarse grid (default 8×8) of additive+multiplicative coefficients, bilinearly interpolated per pixel, to correct **gradient drift** between subs (sky gradient changing through the night) — the PixInsight LocalNormalization analogue. Off by default (global), on for "long night / moving moon" smart preset.

```rust
pub struct NormalizationCoeffs { pub scale: f64, pub offset: f64, pub local_grid: Option<Grid> }
pub fn estimate_normalization(frame: &[f64], reference: &[f64], mask: &CoverageMask, mode: NormMode) -> NormalizationCoeffs;
pub fn apply_normalization(frame: &mut [f64], c: &NormalizationCoeffs, w: u32, h: u32);
```

### 1.4 `integration/integrate.rs` — advanced batch integration

The core difference from `LiveStacker`: **batch over the whole aligned, normalized, weighted population** (a column of samples per output pixel), enabling rejection algorithms that need the full distribution. Memory-bounded by **row-band streaming** (process H/bands rows at a time, reading each aligned sub's band; never hold all subs in RAM — critical for 50×60MP subs).

Combination + rejection (all weighted by per-sub weights and per-pixel coverage):

- `Combine::Mean`, `Combine::Median`.
- `Reject::None`.
- `Reject::SigmaClip { low, high }` (batch, iterated to convergence — unlike the live online clip).
- `Reject::WinsorizedSigmaClip { low, high }` (replaces outliers with the clip bound before computing σ — robust default for ≥15 subs).
- `Reject::LinearFitClip { low, high }` (fit a line to the sorted samples, reject by residual — PixInsight's best-for-many-subs algorithm; default for ≥25 subs).
- `Reject::PercentileClip { low, high }` (best for few subs, <8).
- `Reject::MinMax { n_low, n_high }`.

Outputs the integrated `ImageData` (**`PixelType::F32` linear**, the archival format) **plus**:

- A **per-pixel rejection map** (count of rejected samples / fraction) — surfaced in the UI as a "where did rejection bite" overlay (satellite trails, planes, cosmic rays show up here).
- A **per-pixel coverage map** (how many subs contributed) — drizzle/edge diagnostics.
- Final integration metadata (algorithm, params, effective frame count, total integration seconds, mean weight).

```rust
pub struct IntegrationConfig {
    pub combine: Combine, pub reject: Reject,
    pub weighting: WeightFormula, pub normalization: NormMode,
    pub resampler: Resampler, pub model: TransformModel,
    pub generate_rejection_map: bool,
}
pub struct IntegrationOutput {
    pub master: ImageData,        // F32 linear
    pub rejection_map: Option<ImageData>,
    pub coverage_map: Option<ImageData>,
    pub stats: IntegrationStats,
    pub per_frame: Vec<FrameIntegrationRecord>, // weight, residual, accepted/rejected + reason
}
pub fn integrate_lights(refs: &[AlignedSubHandle], cfg: &IntegrationConfig, progress: &dyn Fn(f32)) -> Result<IntegrationOutput, IntegrationError>;
```

### 1.5 `integration/drizzle.rs` — variable-pixel linear reconstruction (Drizzle)

Optional, for well-dithered, under-sampled data. Implements **classic Drizzle** (Fruchter & Hook): map each input pixel as a shrunken "drop" (pixfrac default 0.9) through the inverse `GeometricTransform` onto a finer output grid (scale default 2.0), accumulating drop-area-weighted flux into an output buffer and a weight buffer, final = flux/weight. Requires per-sub `GeometricTransform` (from §1.1) and per-sub weight. Gated behind `enable_drizzle` (off by default; smart preset enables it only when dithering + under-sampling are detected from the sub metadata). Memory via the same row-band streaming.

### 1.6 `integration/master.rs` — accumulating IntegratedMaster (multi-night)

The headline feature: a **serializable running master** you can keep adding subs to across nights, without re-reading old subs.

Key insight: a **weighted mean** is exactly accumulable — store running sums, add new subs, finalize by division. Rejection is the hard part; we use a **two-tier model** that keeps accumulation exact for the mean while still rejecting outliers:

- **Per-pixel running state (streaming, exact for weighted mean + variance):**
  - `sum_w` (Σ weight), `sum_wx` (Σ weight·value), `sum_wx2` (Σ weight·value²) → finalize = `sum_wx/sum_w`; running variance available for noise/SNR readout.
  - `coverage` (contributing sub count), `rejected_count`.
- **Outlier handling on accumulation:** each new sub is normalized to the **frozen normalization reference** stored in the master, then each pixel is **rejected against the current running mean ± k·running σ** (an online robust clip, same spirit as `LiveStacker::accumulate_pixels` but persisted). This is *not* identical to a full batch re-clip, but it is the standard accumulation tradeoff and is honest about it (the master records `accumulation_mode`).
- **Normalization reference is frozen at master creation** (the first night's reference frame's background+scale), so every later night is brought onto the same photometric footing — the thing that makes cross-night accumulation valid.
- **Geometric reference is frozen too** (the master's WCS / reference star list); later subs align to it.

```rust
pub struct IntegratedMaster {
    pub version: u32,
    pub width: u32, pub height: u32, pub channels: u32,
    pub accumulation_mode: AccumulationMode, // RunningWeightedMean { clip }
    pub norm_reference: NormalizationReference, // frozen background+scale + optional WCS
    pub geom_reference: GeometryReference,      // frozen ref stars / WCS for alignment
    pub state: PerPixelAccumulator,             // sum_w, sum_wx, sum_wx2, coverage, rejected
    pub metadata: MasterMetadata,               // filters, total integration s, frame count, per-night log
}
impl IntegratedMaster {
    pub fn create(reference: &ImageData, cfg: &MasterCreateConfig) -> Result<Self, MasterError>;
    pub fn add_frames(&mut self, frames: &[ImageData], qualities: &[FrameQuality]) -> Result<AddReport, MasterError>;
    pub fn finalize(&self) -> ImageData; // F32 linear master
    pub fn serialize(&self) -> Vec<u8>;  // versioned, like DefectMap::serialize
    pub fn deserialize(bytes: &[u8]) -> Result<Self, MasterError>;
}
```

**Persistence:** finalized master → `write_fits` (we extend with F32 output, §1.8) carrying full provenance in `FitsHeader` (`HISTORY` cards already supported); the *resumable accumulator state* → a **sidecar** `.nsmaster` file (the `serialize` blob, versioned exactly like `DefectMap::serialize`/`deserialize` in `defect_map.rs`). Re-opening reads the sidecar to keep accumulating; the FITS is the shareable artifact.

### 1.7 `integration/calibration_ext.rs` — calibration completeness

Closes the calibration gaps next to the existing `calibration.rs` (which only *applies* masters) and `defect_map.rs` (which already builds defect maps and corrects):

- **Master flat build:** `build_master_flat(flats, bias_or_darkflat) -> MasterFrame` — bias/dark-flat-subtract each flat, then `combine_master_frames(..., MasterFrameKind::Flat, CombineMethod::SigmaClip, F32)` (reuse existing combine!) and **normalize to mean 1.0** so `divide_flat` (already in `calibration.rs`) works. This is the missing master-flat builder.
- **Cosmetic / hot-cold pixel correction:** reuse `build_defect_map` + `correct_frame_u16` (`defect_map.rs`) directly; expose a per-light "cosmetic correction" step in the integration pre-pass. Add a **transient cosmic-ray hint** (sigma-rejection map from integration already catches these — no separate per-frame CR pass needed for stacks ≥ a few subs).
- **Defect map source:** build once from the master dark (or a dedicated bad-pixel scan) via existing `build_defect_map`; persist to `defect_map_table.dart` (already exists).

### 1.8 FITS F32 master output (small extension to `fits.rs`)

`write_fits` currently writes 16-bit. Add `write_fits_f32(path, &ImageData /*F32*/, &FitsHeader)` (BITPIX=-32, BZERO=0/BSCALE=1, IEEE float big-endian per FITS spec) so linear masters survive without quantisation. `read_fits` already returns `(ImageData, FitsHeader)`; extend its BITPIX handling to read -32 if not already present. This is the only change to an existing native file.

---

## 2. Minimal FFI surface (JSON-in / JSON-out)

To keep `flutter_rust_bridge` regeneration churn tiny (regen is heavyweight — needs LLVM 21 + MSVC 14.44 + WinKit per `docs/FRB_TROUBLESHOOTING.md`), add **exactly three** new bridge functions to `bridge/src/api/imaging.rs`, all `String -> Result<String, String>` with `serde_json` payloads. New config fields then never trigger a regen (same trick the live stacker uses for node config per MEMORY.md).

```rust
// bridge/src/api/imaging.rs

/// One-shot batch integration of a sub list into a linear FITS master.
/// args: { lights:[{path,weight_hint?}], calibration:{dark?,flat?,bias?,defect_map?},
///         settings:{align, weighting, normalization, integration, drizzle?},
///         reference:{path|auto}, output:{master_fits_path, rejection_map_path?, preview_png_path?} }
/// returns: { master_path, preview_path?, rejection_map_path?, stats:{...}, per_frame:[{path,weight,residual,accepted,reason?}] }
pub fn api_integrate_session(args_json: String) -> Result<String, String>;

/// Multi-night accumulation. op = create | add | finalize | info.
/// create: { op:"create", reference_path, settings, sidecar_path, master_fits_path }
/// add:    { op:"add", sidecar_path, lights:[...], calibration:{...} }
/// finalize:{ op:"finalize", sidecar_path, master_fits_path, preview_png_path? }
/// returns: { sidecar_path, master_path?, preview_path?, frame_count, total_integration_s, coverage_stats }
pub fn api_master_accumulate(args_json: String) -> Result<String, String>;

/// Save an in-memory F32/U16 buffer as a 16-bit or float FITS master with provenance.
/// (Convenience for paths where the buffer is already in Dart; integration paths
///  write the FITS natively and just return the path, so this is for re-export.)
pub fn api_save_fits_master(args_json: String) -> Result<String, String>;
```

Progress is reported through the **existing event stream** (`bridge/src/api/event_stream.rs`) as integration-progress events (phase + 0..1), so the long-running calls don't need a streaming FFI return. These run on a background thread in the bridge (the bridge already does this for other long ops) so the Dart isolate is not blocked.

**Regen impact:** 3 new functions, no new structs across the boundary → one regen, then all future knobs ride in the JSON. Regen command (from `native/nightshade_native`, env per `docs/FRB_TROUBLESHOOTING.md`): `flutter_rust_bridge_codegen generate`.

---

## 3. Dart layer (`packages/nightshade_core/`)

### 3.1 `IntegrationSettings` model — `lib/src/models/imaging/integration_settings.dart`

Immutable value type (freezed-style like existing models) holding **every advanced knob with smart defaults**, plus named presets:

```dart
class IntegrationSettings {
  // Alignment
  final TransformModel model;          // default: affine
  final Resampler resampler;           // default: lanczos3
  final double ransacThresholdPx;      // 2.0
  final bool distortionCorrection;     // false (TPS)
  final int maxRefStars;               // 200
  // Weighting
  final WeightFormula weighting;       // snrSquared
  final bool autoCull; final double cullPercentile; // true, p10
  // Normalization
  final NormMode normalization;        // global (additive+scale)
  // Integration
  final Combine combine;               // mean
  final Reject reject;                 // AUTO -> chosen by frame count
  final double rejectLow, rejectHigh;  // 3.0 / 3.0 (sigma family)
  final bool generateRejectionMap;     // true
  // Drizzle
  final bool drizzle; final double pixfrac, dropScale; // false / 0.9 / 2.0

  factory IntegrationSettings.smartDefaults({required int subCount, required bool dithered, required bool underSampled, required bool osc});
  static const presets = { 'quick', 'balanced', 'maximumQuality', 'fewSubs', 'longNightGradient' };
}
```

**Smart-default logic** (the "smart" in the brief): reject algorithm auto-selected by sub count (`<8 → percentileClip`, `8–24 → winsorizedSigma`, `≥25 → linearFitClip`); drizzle on only when `dithered && underSampled`; local normalization on for `longNightGradient`; resampler `lanczos3` unless `subCount` is huge and the user picks `quick`.

### 3.2 `PostSessionIntegrationService` — `lib/src/services/post_session_integration_service.dart`

Mirrors `StackAndShareService` idiom but targets the **batch** engine and is **not** gated by the live singleton (different native entry point). Pipeline:

1. **Select** accepted subs via the existing `StackLightSelector.selectForSession` / `selectForTarget` (`stack_light_selector.dart`) — already supports multi-night and honours accepted/quality gates. Reuse verbatim.
2. **Calibrate match** via existing `CalibrationService` + `DarkLibraryService.findBestMatch` (`calibration_service.dart`, `dark_library_service.dart`) for the dark; resolve master flat from the **new `FlatLibrary`** (§3.4) by filter/optics/temperature; bias/defect-map from settings/library.
3. **Build the JSON args** (sub paths + calibration master paths + `IntegrationSettings.toJson()` + reference choice + output paths under the session folder via `naming.rs` conventions).
4. **Invoke** `apiIntegrateSession(argsJson)` on an isolate; stream progress events to a `ValueNotifier`/`Stream` for the UI.
5. **Persist:** write an `integrated_masters` row (§3.4) with master FITS path, preview PNG path, settings JSON, per-frame records, stats; optionally also a `stacked_results` row for back-compat with the existing viewer.

It produces a **16-bit/float linear FITS master** (the gap called out in current state) *and* a stretched preview PNG (reuse the auto-stretch path used by `StackAndShareService`).

### 3.3 `MasterAccumulationService` — `lib/src/services/master_accumulation_service.dart`

Drives `apiMasterAccumulate`:

- `createMaster(targetId, referenceSub, settings)` → `op:create`, stores sidecar path + `integrated_masters` row (status `accumulating`).
- `addNight(masterId, newSubs)` → selects new accepted subs **not already folded in** (track folded sub ids in a join table `integrated_master_frames`), calibrates, calls `op:add`, updates frame count / total integration seconds / per-night log.
- `finalizeMaster(masterId)` → `op:finalize`, writes the shareable FITS + preview, flips status to `finalized` (re-openable for more `add`s).

Idempotency + dedup: the `integrated_master_frames` join (master_id, image_id) prevents double-counting a sub across runs (echoes the cross-stream dedup concern in MEMORY.md).

### 3.4 New DB tables (drift, `lib/src/database/tables/` + DAOs, registered in `database.dart`)

Follow the `DarkLibrary` idiom exactly (indices, `@DataClassName`, `withDefault`). Bump `schemaVersion` (currently 40 in `database.dart`) and add a migration step.

- **`integrated_masters`** — `id`, `targetId?`, `name`, `masterFitsPath`, `previewPngPath?`, `sidecarPath?` (null once finalized-only), `status` (`accumulating`/`finalized`), `channels`, `width`, `height`, `frameCount`, `totalIntegrationSeconds`, `filter?`, `settingsJson`, `statsJson`, `rejectionMapPath?`, `createdAt`, `updatedAt`. Indices on `targetId`, `status`, `createdAt`.
- **`integrated_master_frames`** (join) — `id`, `masterId`, `imageId` (FK → `captured_images`), `weight`, `alignmentResidualPx`, `accepted`, `rejectionReason?`, `foldedAt`. Unique index `(masterId, imageId)` for dedup.
- **`flat_library`** — mirrors `dark_library`: `id`, `filePath` (master flat FITS), `filter`, `opticalTrainId?`/`equipmentProfileId?`, `temperature?`, `gain`, `offset`, `binX/binY`, `width/height`, `panelOrSkyFlat`, `masterFrameCount`, `createdAt`. `findBestMatch(filter, optics, temp, gain, bin)` DAO method analogous to `DarkLibraryDao.findBestMatch`. (Note `flat_history.dart` already exists for the *exposure planner*; this is the missing **master-flat artifact library** — distinct concern.)

Reuse `captured_images` / `ImagesDao` for sub metadata, accept/reject, and per-sub quality columns (HFR, ecc, etc.) — no change needed there.

### 3.5 `FlatLibraryService` + master-flat build — `lib/src/services/flat_library_service.dart`

Parallels `dark_library_service.dart` (`createMasterDark` median-combine in an isolate). `createMasterFlat(flats, biasOrDarkFlat, meta)` calls the native master-flat build (via a small extension to `api_combine_master_frames`, or a `FLAT`-kind path already supported by `combine_master_frames`), normalizes to mean 1.0, writes FITS, inserts a `flat_library` row. Closes the "no master-flat / no flat auto-match" gap.

---

## 4. UI (`packages/nightshade_app/`) — design-system (`nightshade_ui`) idiom throughout

### 4.1 Session Review / Morning Report — `lib/screens/session_review/session_review_screen.dart`

The cohesive "review the night" surface (the current biggest gap). One screen, panelled with `NightshadeCard`:

- **Sub gallery + cull rail** — promote and reuse the existing `screens/analytics/widgets/image_thumbnail_strip.dart` (quality badges, HFR chip, accept/reject context menu via `ImagesDao`) from its dialog into a first-class panel; add **blink mode** (cycle subs at N fps to spot clouds/satellites/bad subs by eye — a long-requested missing feature) and multi-select cull.
- **Per-sub detail** — reuse `screens/sequencer/widgets/run_dashboard/frame_detail_dialog.dart` (`showForFrame(imageId)`), but **lift the reject-only restriction** so it opens for any sub (accepted or rejected) with preview + metrics + forensics.
- **Per-sub field-quality heatmap** — reuse `optical_train_diagnostics_service.dart` + `PsfFieldMap`/`AstrometryResidualVectors` widgets (`screens/diagnostics/psf_field_map.dart`, `residual_vector.dart`) at **per-sub granularity** (inputs are already per-sub) so the user sees tilt/collimation per frame and across the night.
- **Finished master viewer** — reuse `screens/stack_result/widgets/astro_image_viewer.dart` (per-channel STF stretch, zoom/pan) to display the integrated master + a **rejection-map overlay toggle** (from §1.4) and a coverage overlay.
- **Re-integrate** — a button that re-runs `PostSessionIntegrationService` with edited settings (after culling) without re-capturing.

### 4.2 Advanced integration settings panel — `lib/screens/session_review/widgets/integration_settings_panel.dart`

`IntegrationSettings` editor: a **preset dropdown** (smart defaults front-and-center) with an "Advanced" expander revealing every knob (model, resampler, weighting, normalization mode, reject algorithm + sigmas, drizzle pixfrac/scale, distortion correction). Each control has a one-line rationale tooltip. The panel shows the **auto-chosen reject algorithm** for the current sub count so the smart default is transparent, and a live "this will use N of M subs after cull" readout.

### 4.3 Master library / accumulation UI — `lib/screens/session_review/widgets/master_library_panel.dart` (+ a tab in Analytics)

Lists `integrated_masters` (preview thumb, target, filter, total integration time, frame count, status). Actions: **open**, **finalize**, **add tonight's subs** (drives `MasterAccumulationService.addNight`), **re-finalize**. A per-master detail shows the per-night fold log and a growth curve (total integration time vs date) — the multi-night accumulation story made visible.

### 4.4 Auto-process-at-run-end hook

In the sequencer run-completion path (where the run dashboard / `session_report_dialog.dart` already fires at end of night), add an opt-in **"auto-integrate at end of run"** setting: on run completion, if enabled, kick `PostSessionIntegrationService` (or `MasterAccumulationService.addNight` when the target has an active accumulating master) in the background and surface the result in the Morning Report. This makes the master "just be there" in the morning — the unattended-night ethos.

---

## 5. Build order, gates, and PI-grade honesty

Each phase is independently committable and **must pass its gate before commit** (revert-on-red discipline). Native gate = `cargo test -p nightshade_imaging` + `cargo clippy -p nightshade_imaging --all-features -- -D warnings`. Dart gate = `flutter analyze` (0 err/warn in changed files) + targeted `flutter test`. FRB phase additionally needs a successful regen + full-workspace build.

| Phase | Deliverable | Gate |
|---|---|---|
| **P0** | `fits.rs` F32 write/read; `integration/` skeleton + `mod.rs` | imaging `cargo test` + clippy; round-trip F32 FITS test |
| **P1** | `align.rs` (detection refine + quad matcher + RANSAC similarity/affine/homography) + `resample.rs` (bilinear/Catmull/Lanczos) | synthetic frames: known rotation/scale/flip recovered within RMS < 0.3 px; resampler kernel unit tests |
| **P2** | `weighting.rs` + `normalize.rs` | synthetic SNR/FWHM weights monotone; normalization brings two scaled/offset frames into agreement < 1% |
| **P3** | `integrate.rs` (batch combine + all reject algos + maps, row-band streaming) | synthetic: injected hot column/trail rejected; weighted-mean correctness vs analytic; memory bounded |
| **P4** | `master.rs` accumulation (create/add/finalize/serialize) + sidecar round-trip | accumulate-in-3-batches == single-batch weighted mean within float ε; serialize/deserialize identity |
| **P5** | `calibration_ext.rs` master-flat build + defect-map cosmetic wiring; `drizzle.rs` | master-flat normalizes to mean 1.0; drizzle on dithered synthetic improves sampling |
| **P6** | FFI: 3 JSON functions + regen | regen clean; workspace build; bridge JSON contract tests |
| **P7** | Dart: `IntegrationSettings`, `PostSessionIntegrationService`, DB tables + migration, `FlatLibraryService`, `MasterAccumulationService` | `flutter analyze` clean; service unit tests (mock seam like `stacking_engine_seam.dart`); migration test |
| **P8** | UI: Session Review screen + settings panel + master library + auto-hook | `flutter analyze`; widget tests; golden for the new screen |
| **P9** | TPS distortion correction + local normalization grid (advanced extras) | synthetic curved-field recovery; local-norm gradient removal |

**Realistically PI-grade now (algorithmically sound, deterministic, unit-testable on synthetic data):**
- Quad-asterism matching + RANSAC similarity/affine/homography (this is the documented astrometry.net/PixInsight approach).
- Lanczos/Catmull-Rom resampling, weighted batch integration with Winsorized-sigma / linear-fit / percentile rejection, rejection/coverage maps.
- Weighted-mean master accumulation (exact, provably accumulable).
- Master-flat build (reuses the already-tested `combine_master_frames`) and defect/cosmetic correction (reuses tested `defect_map.rs`).

**Needs real-data tuning before claiming parity (honest deferrals — flag, don't fake):**
- **Noise/weight evaluator constants** — the SNR/FWHM/ecc weight exponents and the auto-cull percentiles need tuning against real sub sets; ship defensible defaults, expose the knobs, revisit with real frames (matches the "made honest, not functional" lesson in MEMORY.md).
- **TPS distortion + local normalization** — algorithmically correct but the regularisation λ / grid resolution need real wide-field data; ship behind off-by-default presets (P9).
- **Drizzle** — correct reconstruction, but pixfrac/scale sweet spots and the "is it actually under-sampled + dithered" auto-detector need on-sky validation; off by default.
- **Accumulation rejection vs full batch re-clip** — running online clip is the accepted accumulation tradeoff, not bit-identical to re-integrating every night's full population; the master records `accumulation_mode` so the UI can offer a "full re-integrate from archived subs" path when subs are still on disk.

---

## 6. Files touched / created (summary)

**New native** (`native/nightshade_native/imaging/src/integration/`): `mod.rs`, `align.rs`, `resample.rs`, `weighting.rs`, `normalize.rs`, `integrate.rs`, `drizzle.rs`, `master.rs`, `calibration_ext.rs`.
**Edited native:** `imaging/src/fits.rs` (F32 write/read), `imaging/src/lib.rs` (module wiring), `bridge/src/api/imaging.rs` (3 FFI fns), bridge event-stream progress events.
**New Dart core:** `models/imaging/integration_settings.dart`, `services/post_session_integration_service.dart`, `services/master_accumulation_service.dart`, `services/flat_library_service.dart`, `database/tables/{integrated_masters,integrated_master_frames,flat_library}.dart` + DAOs; `database/database.dart` registration + migration (schemaVersion 40 → 41).
**Reused Dart core (no rewrite):** `services/stack_light_selector.dart`, `services/calibration_service.dart`, `services/dark_library_service.dart`, auto-stretch path, `daos/images_dao.dart`, `daos/stacked_results_dao.dart`.
**New/edited app UI:** `screens/session_review/` (screen + `integration_settings_panel.dart`, `master_library_panel.dart`), promote `analytics/widgets/image_thumbnail_strip.dart` + add blink/multi-select, lift reject-only gate in `sequencer/widgets/run_dashboard/frame_detail_dialog.dart`, reuse `stack_result/widgets/astro_image_viewer.dart` + `diagnostics/{psf_field_map,residual_vector}.dart`, auto-integrate hook in the run-completion path.
