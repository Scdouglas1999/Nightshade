//! Light-frame normalization to a reference frame.
//!
//! Before a population of aligned sub-frames is integrated into a master, every
//! frame must be brought onto the *reference frame's* photometric scale. This
//! matters for two reasons:
//!
//! 1. **Rejection correctness.** Pixel-rejection algorithms (sigma-clip,
//!    Winsorized-sigma, linear-fit-clip) compare each frame's value for a pixel
//!    against the population at that pixel. If one frame has a higher background
//!    (passing cloud, moonrise, light pollution drift) or a different
//!    multiplicative gain (transparency change, slightly different exposure),
//!    its *signal* looks like an outlier and the rejector throws away good data.
//!    Normalizing first means the only thing that differs between frames at a
//!    given pixel is noise + genuine transients (satellites, planes, cosmic
//!    rays) — exactly what rejection should catch.
//!
//! 2. **Unbiased combination.** A weighted mean of frames that disagree on
//!    offset/scale produces a master with a biased background and a compressed
//!    dynamic range. Normalizing puts them on a common footing first.
//!
//! This is the role of PixInsight's `ImageIntegration` normalization (additive
//! + scale) and, for gradient drift through a night, its `LocalNormalization`.
//!
//! ## Model
//!
//! Each frame `f` is mapped onto the reference `r` by an affine relation
//!
//! ```text
//!     f_norm(p) = scale · f(p) + offset
//! ```
//!
//! solved so that, over the pixels both frames validly cover (excluding stars,
//! saturation, NaNs, and zero-coverage borders), `f_norm` best matches `r`:
//!
//! - **Multiplicative `scale`** — the ratio of the reference's signal spread to
//!   the frame's signal spread, estimated robustly from a least-squares line
//!   fit of reference-vs-frame pixel pairs (a robust slope, not the noisy
//!   per-pixel ratio). This corrects transparency / exposure differences.
//! - **Additive `offset`** — chosen so the frame's (scaled) background lands on
//!   the reference background. This corrects skyglow / light-pollution drift.
//!
//! The fit deliberately samples the **shared low-to-mid signal** (sky +
//! faint nebulosity), not the bright stars: stars saturate, vary in PSF between
//! frames, and would dominate a naive least-squares fit while telling us
//! nothing about the sky pedestal we actually need to match.
//!
//! ## Optional local (grid) normalization
//!
//! A single global `(scale, offset)` cannot remove a *gradient* that changes
//! across the night (the moon climbing, a light dome rotating). For that, an
//! optional coarse grid of local `(scale, offset)` coefficients is fitted —
//! one per cell over a `grid_rows × grid_cols` lattice — and bilinearly
//! interpolated per pixel when applied. This is the `LocalNormalization`
//! analogue. It is **off by default** (global is correct for stable skies and
//! avoids over-fitting low-signal cells); callers enable it for the
//! "long night / moving moon" preset.
//!
//! ## Honest limits (per the design doc's "made honest, not functional" bar)
//!
//! The robust-fit constants (sigma-clip κ for the pair fit, the star/saturation
//! exclusion percentile, the minimum sample count per local cell) are
//! defensible defaults, not values tuned against a corpus of real sub sets.
//! They are exposed as knobs. The algorithm itself — robust additive+scale fit,
//! coverage/NaN exclusion, bilinearly-interpolated local grid — is
//! deterministic and unit-tested on synthetic frames here.

/// Marks, per pixel, whether a frame contributes a valid sample.
///
/// After registration warps a sub onto the reference grid, the border pixels
/// that mapped outside the source frame carry no real data (the resampler
/// zero-fills them). Those pixels must be excluded from the normalization fit —
/// otherwise the frame's "background" is contaminated by a band of zeros and
/// the offset is pulled toward black. A `CoverageMask` records which output
/// pixels have genuine source support.
///
/// `valid.len()` must equal `width × height` (one flag per pixel, channel-
/// independent — coverage is a geometric property of the warp, the same for
/// every channel). When a caller has no coverage information (e.g. the frame
/// was not warped), [`CoverageMask::full`] treats every pixel as valid.
#[derive(Debug, Clone)]
pub struct CoverageMask {
    width: usize,
    height: usize,
    valid: Vec<bool>,
}

impl CoverageMask {
    /// Build a mask from an explicit per-pixel validity vector.
    ///
    /// Returns `None` if `valid.len() != width × height`.
    pub fn new(width: usize, height: usize, valid: Vec<bool>) -> Option<Self> {
        if valid.len() != width.checked_mul(height)? {
            return None;
        }
        Some(Self {
            width,
            height,
            valid,
        })
    }

    /// A mask in which every pixel is valid (no coverage restriction).
    pub fn full(width: usize, height: usize) -> Self {
        Self {
            width,
            height,
            valid: vec![true; width * height],
        }
    }

    /// Derive a coverage mask from a warped frame's pixel values, treating any
    /// pixel that is exactly zero **and** finite as uncovered.
    ///
    /// This matches the resampler's zero-fill-on-out-of-bounds convention
    /// (`registration::warp_frame`). It is a convenience for callers that only
    /// have the warped buffer; callers that have an explicit per-pixel coverage
    /// count from the resampler should prefer [`CoverageMask::new`] since a
    /// genuinely-black covered sky pixel is vanishingly rare but not impossible.
    pub fn from_zero_fill(frame: &[f64], width: usize, height: usize) -> Self {
        let valid = frame
            .iter()
            .map(|&v| v.is_finite() && v != 0.0)
            .collect::<Vec<_>>();
        Self {
            width,
            height,
            valid,
        }
    }

    #[inline]
    fn is_valid(&self, index: usize) -> bool {
        self.valid.get(index).copied().unwrap_or(false)
    }

    /// Whether the pixel at flat row-major `index` (= `y·width + x`) had valid
    /// source support. Out-of-range indices are treated as uncovered. This is
    /// the public accessor used by batch integration to skip pixels a given
    /// frame did not cover after warping.
    #[inline]
    pub fn is_valid_at(&self, index: usize) -> bool {
        self.is_valid(index)
    }

    /// Width in pixels.
    pub fn width(&self) -> usize {
        self.width
    }

    /// Height in pixels.
    pub fn height(&self) -> usize {
        self.height
    }
}

/// Which normalization model to fit.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum NormMode {
    /// A single global additive+multiplicative pair for the whole frame.
    /// Correct for stable skies; the safe default.
    #[default]
    Global,
    /// A coarse `rows × cols` grid of local additive+multiplicative pairs,
    /// bilinearly interpolated per pixel. Corrects gradient drift across the
    /// night at the cost of more parameters; use only with enough signal.
    Local { rows: usize, cols: usize },
}

/// Tunables for the normalization fit. [`Default`] is a robust global fit.
#[derive(Debug, Clone)]
pub struct NormalizationConfig {
    /// Global vs. local grid model.
    pub mode: NormMode,
    /// Upper percentile (0..1) of the *reference* signal above which pixels are
    /// excluded from the fit as "stars / bright structure". The fit should be
    /// driven by the sky pedestal and faint signal, not saturated stars whose
    /// PSF differs frame-to-frame. Default 0.92.
    pub high_reject_percentile: f64,
    /// Sigma-clip threshold (κ) for the iterated robust line fit on the sampled
    /// pixel pairs. Pairs whose residual exceeds κ·σ are dropped and the fit is
    /// repeated. Default 2.5.
    pub clip_kappa: f64,
    /// Number of robust-refit iterations. Default 3.
    pub clip_iterations: usize,
    /// Minimum number of valid sample pairs required to fit a model (global) or
    /// a single local cell. Below this the fit falls back to identity (global)
    /// or to the global coefficients (local cell). Default 64.
    pub min_samples: usize,
}

impl Default for NormalizationConfig {
    fn default() -> Self {
        Self {
            mode: NormMode::Global,
            high_reject_percentile: 0.92,
            clip_kappa: 2.5,
            clip_iterations: 3,
            min_samples: 64,
        }
    }
}

/// A fitted local grid of `(scale, offset)` coefficients.
///
/// Coefficients sit at the **centres** of a `rows × cols` lattice of cells over
/// the frame. Applying the grid bilinearly interpolates between the four
/// surrounding cell centres for each pixel, so the correction varies smoothly
/// across the frame with no cell-boundary discontinuities.
#[derive(Debug, Clone, PartialEq)]
pub struct LocalGrid {
    /// Lattice rows.
    pub rows: usize,
    /// Lattice columns.
    pub cols: usize,
    /// Per-cell multiplicative scale, row-major (`rows × cols`).
    pub scale: Vec<f64>,
    /// Per-cell additive offset, row-major (`rows × cols`).
    pub offset: Vec<f64>,
}

/// The result of fitting a normalization of one frame to a reference.
///
/// `scale`/`offset` are always present (the global fit, or the population-mean
/// of the local cells); `local` is `Some` only for [`NormMode::Local`].
#[derive(Debug, Clone, PartialEq)]
pub struct NormalizationCoeffs {
    /// Global multiplicative scale: `f_norm = scale · f + offset`.
    pub scale: f64,
    /// Global additive offset.
    pub offset: f64,
    /// Optional local grid (interpolated per pixel when applied).
    pub local: Option<LocalGrid>,
    /// Number of valid sample pairs the global fit used (post-clipping), for
    /// diagnostics / confidence reporting.
    pub samples_used: usize,
}

impl NormalizationCoeffs {
    /// The identity normalization (`scale = 1`, `offset = 0`, no local grid).
    /// Returned when there is too little overlapping signal to fit honestly.
    pub fn identity() -> Self {
        Self {
            scale: 1.0,
            offset: 0.0,
            local: None,
            samples_used: 0,
        }
    }
}

/// Errors from the normalization fit. These are *expected* shape mismatches the
/// caller passed in, surfaced loudly rather than producing a garbage fit.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum NormalizationError {
    /// `frame` and `reference` differ in length.
    #[error("frame ({frame}) and reference ({reference}) pixel counts differ")]
    LengthMismatch { frame: usize, reference: usize },
    /// The coverage mask does not describe a `width × height` buffer matching
    /// the supplied pixel count.
    #[error("coverage mask ({mask}) does not match pixel count ({pixels})")]
    MaskMismatch { mask: usize, pixels: usize },
    /// A local grid was requested with a zero dimension.
    #[error("local normalization grid must have non-zero rows and cols")]
    EmptyGrid,
}

// =============================================================================
// Public API
// =============================================================================

/// Estimate the normalization that maps `frame` onto `reference`'s photometric
/// scale.
///
/// `frame` and `reference` are single-channel planes of identical length
/// (`width × height`); for RGB the caller normalizes each channel against the
/// matching reference channel (the coefficients are per-channel by construction
/// because gain/skyglow can differ between channels). `mask` marks the pixels
/// `frame` validly covers (border pixels that warped out of the source are
/// excluded). Non-finite pixels in either buffer are always excluded.
///
/// Returns [`NormalizationCoeffs::identity`] if too few valid, in-range pairs
/// survive the exclusions to fit honestly (a deliberate fail-safe, never a
/// fabricated transform).
pub fn estimate_normalization(
    frame: &[f64],
    reference: &[f64],
    mask: &CoverageMask,
    width: usize,
    height: usize,
    cfg: &NormalizationConfig,
) -> Result<NormalizationCoeffs, NormalizationError> {
    if frame.len() != reference.len() {
        return Err(NormalizationError::LengthMismatch {
            frame: frame.len(),
            reference: reference.len(),
        });
    }
    let pixels = width.saturating_mul(height);
    if frame.len() != pixels {
        return Err(NormalizationError::LengthMismatch {
            frame: frame.len(),
            reference: pixels,
        });
    }
    if mask.valid.len() != pixels {
        return Err(NormalizationError::MaskMismatch {
            mask: mask.valid.len(),
            pixels,
        });
    }
    if let NormMode::Local { rows, cols } = cfg.mode {
        if rows == 0 || cols == 0 {
            return Err(NormalizationError::EmptyGrid);
        }
    }

    // The high-signal exclusion threshold is computed once on the reference, so
    // every cell (global or local) excludes the same bright structure.
    let high_cut = high_signal_cutoff(reference, mask, cfg.high_reject_percentile);

    // Always fit the global model first: it is the fallback for sparse local
    // cells and the reported scalar coefficients.
    let global = fit_global(frame, reference, mask, high_cut, cfg);

    let local = match cfg.mode {
        NormMode::Global => None,
        NormMode::Local { rows, cols } => Some(fit_local_grid(
            frame, reference, mask, width, height, rows, cols, high_cut, &global, cfg,
        )),
    };

    Ok(NormalizationCoeffs {
        scale: global.scale,
        offset: global.offset,
        local,
        samples_used: global.samples_used,
    })
}

/// Apply previously-estimated coefficients to a frame in place.
///
/// For [`NormalizationCoeffs`] without a local grid this is the global affine
/// map `f ← scale·f + offset`. With a local grid, the per-pixel `(scale,
/// offset)` is bilinearly interpolated from the cell-centre lattice. Non-finite
/// pixels are left untouched (they carry no signal to correct and propagating
/// NaN through the integration is handled there).
pub fn apply_normalization(
    frame: &mut [f64],
    coeffs: &NormalizationCoeffs,
    width: usize,
    height: usize,
) {
    match &coeffs.local {
        None => {
            for v in frame.iter_mut() {
                if v.is_finite() {
                    *v = coeffs.scale * *v + coeffs.offset;
                }
            }
        }
        Some(grid) => apply_local_grid(frame, grid, width, height),
    }
}

// =============================================================================
// Global fit
// =============================================================================

/// A bare global fit result (no local grid).
#[derive(Debug, Clone, Copy)]
struct GlobalFit {
    scale: f64,
    offset: f64,
    samples_used: usize,
}

impl GlobalFit {
    fn identity() -> Self {
        Self {
            scale: 1.0,
            offset: 0.0,
            samples_used: 0,
        }
    }
}

/// Collect the `(frame, reference)` value pairs that are valid samples for the
/// fit: both finite, covered by the mask, and below the bright-structure cutoff.
fn collect_pairs(
    frame: &[f64],
    reference: &[f64],
    indices: impl Iterator<Item = usize>,
    mask: &CoverageMask,
    high_cut: f64,
) -> Vec<(f64, f64)> {
    let mut pairs = Vec::new();
    for i in indices {
        if !mask.is_valid(i) {
            continue;
        }
        let f = frame[i];
        let r = reference[i];
        if !f.is_finite() || !r.is_finite() {
            continue;
        }
        // Exclude bright structure (stars) judged on the reference so the same
        // pixels are excluded for every frame compared against it.
        if r > high_cut {
            continue;
        }
        pairs.push((f, r));
    }
    pairs
}

/// Fit the global `(scale, offset)` over the whole frame.
fn fit_global(
    frame: &[f64],
    reference: &[f64],
    mask: &CoverageMask,
    high_cut: f64,
    cfg: &NormalizationConfig,
) -> GlobalFit {
    let pairs = collect_pairs(frame, reference, 0..frame.len(), mask, high_cut);
    match fit_robust_line(&pairs, cfg) {
        Some((scale, offset, used)) => GlobalFit {
            scale,
            offset,
            samples_used: used,
        },
        None => GlobalFit::identity(),
    }
}

/// Iterated, sigma-clipped least-squares line fit `r ≈ scale·f + offset`.
///
/// We regress *reference on frame* so that applying `scale·f + offset` yields a
/// value on the reference's scale. The fit is robustified by κ-sigma clipping:
/// fit, compute residual σ, drop pairs beyond κ·σ, refit — this rejects the
/// residual stars / hot pixels / transients that survived the percentile cut.
///
/// Returns `None` (→ identity) if fewer than `cfg.min_samples` pairs survive or
/// the frame values have no spread (a flat frame cannot determine a slope).
fn fit_robust_line(pairs: &[(f64, f64)], cfg: &NormalizationConfig) -> Option<(f64, f64, usize)> {
    if pairs.len() < cfg.min_samples {
        return None;
    }

    let mut kept: Vec<(f64, f64)> = pairs.to_vec();

    let mut last: Option<(f64, f64)> = None;
    for _ in 0..cfg.clip_iterations.max(1) {
        if kept.len() < cfg.min_samples {
            break;
        }
        let (scale, offset) = ordinary_least_squares(&kept)?;
        last = Some((scale, offset));

        // Residual σ of the current fit.
        let residuals: Vec<f64> = kept
            .iter()
            .map(|&(f, r)| r - (scale * f + offset))
            .collect();
        let sigma = std_dev(&residuals);
        if sigma <= f64::MIN_POSITIVE {
            break; // perfect fit; nothing left to clip
        }

        let limit = cfg.clip_kappa.max(0.0) * sigma;
        let before = kept.len();
        kept = kept
            .iter()
            .copied()
            .zip(residuals.iter())
            .filter(|(_, &res)| res.abs() <= limit)
            .map(|(pair, _)| pair)
            .collect();

        if kept.len() == before {
            break; // converged: no further pairs clipped
        }
    }

    // Refit on the final retained set for the reported coefficients.
    let final_fit = if kept.len() >= cfg.min_samples {
        ordinary_least_squares(&kept).or(last)
    } else {
        last
    };

    final_fit.map(|(scale, offset)| (scale, offset, kept.len()))
}

/// Closed-form ordinary least squares for `y ≈ a·x + b`.
///
/// Returns `None` if `x` has no variance (degenerate, slope undetermined).
fn ordinary_least_squares(pairs: &[(f64, f64)]) -> Option<(f64, f64)> {
    let n = pairs.len() as f64;
    if n < 2.0 {
        return None;
    }
    let (mut sx, mut sy, mut sxx, mut sxy) = (0.0, 0.0, 0.0, 0.0);
    for &(x, y) in pairs {
        sx += x;
        sy += y;
        sxx += x * x;
        sxy += x * y;
    }
    let denom = n * sxx - sx * sx;
    if denom.abs() < f64::EPSILON {
        return None;
    }
    let scale = (n * sxy - sx * sy) / denom;
    let offset = (sy - scale * sx) / n;
    if !scale.is_finite() || !offset.is_finite() {
        return None;
    }
    Some((scale, offset))
}

// =============================================================================
// Local grid fit + apply
// =============================================================================

/// Fit a `rows × cols` grid of local `(scale, offset)` coefficients.
///
/// Each cell fits its own robust line over the pixels whose centre falls in
/// that cell. Cells with too few valid samples fall back to the global fit so a
/// low-signal corner never injects a wild local correction.
#[allow(clippy::too_many_arguments)]
fn fit_local_grid(
    frame: &[f64],
    reference: &[f64],
    mask: &CoverageMask,
    width: usize,
    height: usize,
    rows: usize,
    cols: usize,
    high_cut: f64,
    global: &GlobalFit,
    cfg: &NormalizationConfig,
) -> LocalGrid {
    let mut scale = vec![global.scale; rows * cols];
    let mut offset = vec![global.offset; rows * cols];

    for cell_row in 0..rows {
        // Pixel row span for this cell (centre-aligned cells tile the frame).
        let y0 = cell_row * height / rows;
        let y1 = ((cell_row + 1) * height / rows).max(y0 + 1).min(height);
        for cell_col in 0..cols {
            let x0 = cell_col * width / cols;
            let x1 = ((cell_col + 1) * width / cols).max(x0 + 1).min(width);

            let indices = (y0..y1).flat_map(|y| (x0..x1).map(move |x| y * width + x));
            let pairs = collect_pairs(frame, reference, indices, mask, high_cut);

            if let Some((s, o, _)) = fit_robust_line(&pairs, cfg) {
                let idx = cell_row * cols + cell_col;
                scale[idx] = s;
                offset[idx] = o;
            }
            // else: cell keeps the global coefficients it was seeded with.
        }
    }

    LocalGrid {
        rows,
        cols,
        scale,
        offset,
    }
}

/// Apply a local grid by bilinearly interpolating cell-centre coefficients.
fn apply_local_grid(frame: &mut [f64], grid: &LocalGrid, width: usize, height: usize) {
    if grid.rows == 0 || grid.cols == 0 || width == 0 || height == 0 {
        return;
    }

    for y in 0..height {
        // Map pixel y to a fractional cell-centre coordinate. Cell `c` spans
        // pixel rows `[c·H/rows, (c+1)·H/rows)`; its centre is at the midpoint.
        let gy = grid_coord(y, height, grid.rows);
        for x in 0..width {
            let idx = y * width + x;
            let v = frame[idx];
            if !v.is_finite() {
                continue;
            }
            let gx = grid_coord(x, width, grid.cols);
            let (s, o) = bilinear_coeffs(grid, gx, gy);
            frame[idx] = s * v + o;
        }
    }
}

/// Convert a pixel coordinate to the fractional cell-centre coordinate along one
/// axis: cell centres sit at integer values `0..n-1`, and a pixel at a cell
/// centre maps exactly to that integer. Pixels outside the first/last centre
/// clamp (no extrapolation of the correction beyond the fitted lattice).
fn grid_coord(pixel: usize, extent: usize, cells: usize) -> f64 {
    if cells <= 1 {
        return 0.0;
    }
    // Centre of cell c (in pixel units): (c + 0.5) · extent / cells - 0.5.
    // Invert to get the fractional cell coordinate g such that
    // pixel = (g + 0.5) · extent / cells - 0.5.
    let g = (pixel as f64 + 0.5) * cells as f64 / extent as f64 - 0.5;
    g.clamp(0.0, (cells - 1) as f64)
}

/// Bilinearly interpolate `(scale, offset)` at fractional grid coordinate
/// `(gx, gy)` where integer coordinates address cell centres.
fn bilinear_coeffs(grid: &LocalGrid, gx: f64, gy: f64) -> (f64, f64) {
    let x0 = gx.floor() as usize;
    let y0 = gy.floor() as usize;
    let x1 = (x0 + 1).min(grid.cols - 1);
    let y1 = (y0 + 1).min(grid.rows - 1);
    let fx = gx - x0 as f64;
    let fy = gy - y0 as f64;

    let at = |r: usize, c: usize| -> (f64, f64) {
        let i = r * grid.cols + c;
        (grid.scale[i], grid.offset[i])
    };

    let (s00, o00) = at(y0, x0);
    let (s10, o10) = at(y0, x1);
    let (s01, o01) = at(y1, x0);
    let (s11, o11) = at(y1, x1);

    let lerp = |a: f64, b: f64, t: f64| a + (b - a) * t;
    let s = lerp(lerp(s00, s10, fx), lerp(s01, s11, fx), fy);
    let o = lerp(lerp(o00, o10, fx), lerp(o01, o11, fx), fy);
    (s, o)
}

// =============================================================================
// Robust-statistics helpers
// =============================================================================

/// The reference value above which a pixel is treated as bright structure and
/// excluded from the fit. Computed as the `percentile` quantile of the *valid,
/// finite* reference pixels. Falls back to `+∞` (exclude nothing) when there is
/// no valid signal to rank.
fn high_signal_cutoff(reference: &[f64], mask: &CoverageMask, percentile: f64) -> f64 {
    let mut vals: Vec<f64> = reference
        .iter()
        .enumerate()
        .filter(|(i, v)| mask.is_valid(*i) && v.is_finite())
        .map(|(_, v)| *v)
        .collect();
    if vals.is_empty() {
        return f64::INFINITY;
    }
    vals.sort_by(f64::total_cmp);
    let p = percentile.clamp(0.0, 1.0);
    let rank = ((vals.len() - 1) as f64 * p).round() as usize;
    vals[rank.min(vals.len() - 1)]
}

/// Sample standard deviation (population form; the divisor is `n`, which is the
/// right normalization for a residual scatter estimate used only to set a clip
/// threshold). Returns 0 for fewer than two values.
fn std_dev(values: &[f64]) -> f64 {
    let n = values.len();
    if n < 2 {
        return 0.0;
    }
    let mean = values.iter().sum::<f64>() / n as f64;
    let var = values.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / n as f64;
    var.sqrt()
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    /// Build a deterministic synthetic reference plane: a smooth sky pedestal
    /// plus a few bright "stars" plus low-amplitude deterministic noise.
    fn synthetic_reference(width: usize, height: usize) -> Vec<f64> {
        let mut v = vec![0.0; width * height];
        for y in 0..height {
            for x in 0..width {
                let i = y * width + x;
                // Smooth pedestal with a gentle gradient so a real sky is modelled.
                let pedestal = 1000.0 + 0.5 * x as f64 + 0.3 * y as f64;
                // Deterministic zero-mean noise.
                let n = ((i.wrapping_mul(2654435761) >> 8) % 1000) as f64 / 1000.0 - 0.5;
                v[i] = pedestal + n * 20.0;
            }
        }
        // A handful of bright stars (excluded by the percentile cut in the fit).
        for &(sx, sy) in &[(5usize, 5usize), (20, 12), (12, 22), (28, 28)] {
            if sy < height && sx < width {
                v[sy * width + sx] = 60000.0;
            }
        }
        v
    }

    #[test]
    fn recovers_known_offset_and_scale() {
        let (w, h) = (32usize, 32usize);
        let reference = synthetic_reference(w, h);

        // Construct a frame that is the reference under a KNOWN affine map:
        //   reference = TRUE_SCALE · frame + TRUE_OFFSET
        // so the *frame* is reference inverted: frame = (reference - off)/scale.
        let true_scale = 1.35;
        let true_offset = -180.0;
        let frame: Vec<f64> = reference
            .iter()
            .map(|&r| (r - true_offset) / true_scale)
            .collect();

        let mask = CoverageMask::full(w, h);
        let cfg = NormalizationConfig::default();
        let coeffs = estimate_normalization(&frame, &reference, &mask, w, h, &cfg).unwrap();

        // The fit maps frame -> reference, so it should recover (true_scale, true_offset).
        assert!(
            (coeffs.scale - true_scale).abs() < 1e-3,
            "scale {} should be ~{}",
            coeffs.scale,
            true_scale
        );
        assert!(
            (coeffs.offset - true_offset).abs() < 1.0,
            "offset {} should be ~{}",
            coeffs.offset,
            true_offset
        );

        // Applying the coefficients should bring the frame back onto the reference.
        let mut normalized = frame.clone();
        apply_normalization(&mut normalized, &coeffs, w, h);
        // Compare on the sky pixels (exclude the injected bright stars where the
        // inverse-then-forward round trip is exact anyway).
        let mut max_err = 0.0f64;
        for (n, r) in normalized.iter().zip(reference.iter()) {
            max_err = max_err.max((n - r).abs());
        }
        assert!(
            max_err < 1e-6,
            "normalized frame should match reference to float precision, max err {}",
            max_err
        );
    }

    #[test]
    fn identity_frame_recovers_unit_scale_zero_offset() {
        let (w, h) = (24usize, 24usize);
        let reference = synthetic_reference(w, h);
        let frame = reference.clone();
        let mask = CoverageMask::full(w, h);

        let coeffs = estimate_normalization(
            &frame,
            &reference,
            &mask,
            w,
            h,
            &NormalizationConfig::default(),
        )
        .unwrap();
        assert!((coeffs.scale - 1.0).abs() < 1e-6, "scale {}", coeffs.scale);
        assert!(coeffs.offset.abs() < 1e-6, "offset {}", coeffs.offset);
    }

    #[test]
    fn excludes_nan_and_uncovered_border_pixels() {
        let (w, h) = (32usize, 32usize);
        let reference = synthetic_reference(w, h);

        let true_scale = 0.8;
        let true_offset = 250.0;
        let mut frame: Vec<f64> = reference
            .iter()
            .map(|&r| (r - true_offset) / true_scale)
            .collect();

        // Mark the first two columns as uncovered (warp border) AND poison them
        // with values that would wreck the fit if they were included.
        let mut valid = vec![true; w * h];
        for y in 0..h {
            for x in 0..2 {
                let i = y * w + x;
                valid[i] = false;
                frame[i] = 0.0; // zero-fill, the resampler's out-of-bounds value
            }
        }
        // Also inject a NaN into a covered pixel; it must be skipped, not poison
        // the fit or the apply step.
        let nan_idx = (h / 2) * w + (w / 2);
        frame[nan_idx] = f64::NAN;

        let mask = CoverageMask::new(w, h, valid).unwrap();
        let coeffs = estimate_normalization(
            &frame,
            &reference,
            &mask,
            w,
            h,
            &NormalizationConfig::default(),
        )
        .unwrap();

        // Despite the poisoned border and NaN, the true affine relation is
        // recovered from the covered, finite pixels.
        assert!(
            (coeffs.scale - true_scale).abs() < 1e-2,
            "scale {} should be ~{}",
            coeffs.scale,
            true_scale
        );
        assert!(
            (coeffs.offset - true_offset).abs() < 5.0,
            "offset {} should be ~{}",
            coeffs.offset,
            true_offset
        );

        // The NaN pixel must remain NaN after apply (left untouched), proving it
        // was excluded rather than silently turned into a finite value.
        let mut normalized = frame.clone();
        apply_normalization(&mut normalized, &coeffs, w, h);
        assert!(
            normalized[nan_idx].is_nan(),
            "NaN pixel must be left untouched by apply"
        );
    }

    #[test]
    fn too_few_samples_falls_back_to_identity() {
        // A tiny frame with fewer valid pixels than min_samples must not fabricate
        // a transform — it returns identity.
        let (w, h) = (4usize, 4usize);
        let reference = vec![1000.0; w * h];
        let frame = vec![500.0; w * h];
        let mask = CoverageMask::full(w, h);

        let coeffs = estimate_normalization(
            &frame,
            &reference,
            &mask,
            w,
            h,
            &NormalizationConfig::default(),
        )
        .unwrap();
        // Flat frames have no slope information AND too few samples -> identity.
        assert_eq!(coeffs, NormalizationCoeffs::identity());
    }

    #[test]
    fn rejects_length_mismatch() {
        let mask = CoverageMask::full(2, 2);
        let err = estimate_normalization(
            &[1.0, 2.0, 3.0],
            &[1.0, 2.0, 3.0, 4.0],
            &mask,
            2,
            2,
            &NormalizationConfig::default(),
        )
        .unwrap_err();
        assert!(matches!(err, NormalizationError::LengthMismatch { .. }));
    }

    #[test]
    fn rejects_mask_mismatch() {
        // Mask describes 2x2 but pixels describe 3x3.
        let mask = CoverageMask::full(2, 2);
        let frame = vec![0.0; 9];
        let reference = vec![0.0; 9];
        let err = estimate_normalization(
            &frame,
            &reference,
            &mask,
            3,
            3,
            &NormalizationConfig::default(),
        )
        .unwrap_err();
        assert!(matches!(err, NormalizationError::MaskMismatch { .. }));
    }

    #[test]
    fn local_grid_corrects_a_cross_frame_gradient() {
        // The frame differs from the reference by a gradient in the OFFSET that
        // a single global offset cannot remove: model a light dome brightening
        // toward one edge through the night. Local normalization should remove
        // it far better than global.
        let (w, h) = (64usize, 64usize);
        let reference = synthetic_reference(w, h);

        // frame = reference + added_gradient (so to recover reference we must
        // SUBTRACT a spatially-varying offset — exactly the local job). The
        // gradient is large vs. the ~6 ADU sky noise floor so the local
        // advantage is unambiguous (a global single offset cannot follow it).
        let added = |x: usize, _y: usize| -> f64 { 1200.0 * (x as f64 / w as f64) };
        let frame: Vec<f64> = reference
            .iter()
            .enumerate()
            .map(|(i, &r)| {
                let x = i % w;
                let y = i / w;
                r + added(x, y)
            })
            .collect();

        let mask = CoverageMask::full(w, h);

        // Global fit: best single offset, leaves a residual gradient.
        let global = estimate_normalization(
            &frame,
            &reference,
            &mask,
            w,
            h,
            &NormalizationConfig::default(),
        )
        .unwrap();
        let mut global_norm = frame.clone();
        apply_normalization(&mut global_norm, &global, w, h);
        let global_err = sky_rms(&global_norm, &reference, w, h);

        // Local fit: a grid that follows the gradient.
        let local_cfg = NormalizationConfig {
            mode: NormMode::Local { rows: 6, cols: 6 },
            ..NormalizationConfig::default()
        };
        let local = estimate_normalization(&frame, &reference, &mask, w, h, &local_cfg).unwrap();
        assert!(local.local.is_some(), "local mode must produce a grid");
        let mut local_norm = frame.clone();
        apply_normalization(&mut local_norm, &local, w, h);
        let local_err = sky_rms(&local_norm, &reference, w, h);

        // Local must beat global, and crucially must reach the irreducible
        // sky-noise floor (~6 ADU RMS for this synthetic) — proving the gradient
        // itself was removed, not merely reduced. Global cannot follow a
        // spatially-varying offset with one coefficient pair, so it sits well
        // above the floor.
        assert!(
            local_err < global_err,
            "local normalization (RMS {local_err}) should beat global (RMS {global_err}) on a gradient"
        );
        assert!(
            local_err < 7.0,
            "local residual {local_err} should be at the ~6 ADU sky-noise floor"
        );
        assert!(
            global_err > local_err + 1.0,
            "global residual {global_err} should sit clearly above the noise floor (local {local_err})"
        );
    }

    /// RMS difference over the sky pixels (exclude the injected bright stars,
    /// whose values are huge and would swamp the metric).
    fn sky_rms(a: &[f64], b: &[f64], _w: usize, _h: usize) -> f64 {
        let mut sum = 0.0;
        let mut n = 0usize;
        for (x, y) in a.iter().zip(b.iter()) {
            if *y < 50000.0 {
                sum += (x - y).powi(2);
                n += 1;
            }
        }
        if n == 0 {
            0.0
        } else {
            (sum / n as f64).sqrt()
        }
    }

    #[test]
    fn local_grid_reduces_to_global_on_uniform_data() {
        // With no spatial variation, the local grid should produce essentially
        // the same correction as global everywhere (every cell fits the same
        // line), so applying it matches the reference just as well.
        let (w, h) = (48usize, 48usize);
        let reference = synthetic_reference(w, h);
        let true_scale = 1.1;
        let true_offset = -90.0;
        let frame: Vec<f64> = reference
            .iter()
            .map(|&r| (r - true_offset) / true_scale)
            .collect();
        let mask = CoverageMask::full(w, h);

        let cfg = NormalizationConfig {
            mode: NormMode::Local { rows: 4, cols: 4 },
            ..NormalizationConfig::default()
        };
        let coeffs = estimate_normalization(&frame, &reference, &mask, w, h, &cfg).unwrap();
        let mut normalized = frame.clone();
        apply_normalization(&mut normalized, &coeffs, w, h);
        let err = sky_rms(&normalized, &reference, w, h);
        assert!(
            err < 1.0,
            "local norm on uniform data should match reference closely, RMS {err}"
        );
    }
}
