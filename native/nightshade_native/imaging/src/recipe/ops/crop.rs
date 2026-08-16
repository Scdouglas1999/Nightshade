//! Rectangular crop, with an auto-proposal from the coverage map registration
//! leaves behind.
//!
//! Registration warps every frame onto a reference grid, so a stack's edges are
//! a ragged band where only some frames contributed — or none did, leaving the
//! integrator's fill value. Cropping that band away is the last linear-stage
//! step: it changes geometry, so the astrometry travels with it.
//!
//! # Astrometry
//!
//! The crop moves the image origin, which moves the WCS reference pixel by the
//! same amount and nothing else. `CRVAL`, the `CD` matrix and any SIP terms
//! describe the plate, not the framing, and are carried through untouched;
//! `NAXIS1`/`NAXIS2`/`NAXIS3` follow the new geometry.
//!
//! # Preview scale
//!
//! `x`, `y`, `width` and `height` are pixels at full resolution. A preview
//! renders over a downsampled level, so the rect is mapped by
//! [`OpContext::scale`]: the origin floors and the far edge ceils, so the
//! previewed region never shows less than the full render does. The rect is
//! intersected with the image, because that rounding can push the far edge one
//! pixel past the level's own size.

use rayon::prelude::*;
use serde_json::{json, Value};

use crate::recipe::{DarkroomOp, OpContext, OpError, OpImage, OpStage, Params};

/// Largest coordinate or extent, in pixels. No sensor reaches it; it exists so a
/// hand-edited recipe cannot ask for a rect that overflows the geometry maths.
const COORD_MAX: u32 = 1_000_000;

/// Crops a rectangle out of linear data and moves the astrometry with it.
pub struct CropV1;

/// One step's validated parameters, in pixels at full resolution.
struct Settings {
    /// Left edge.
    x: u32,
    /// Top edge.
    y: u32,
    /// Width.
    width: u32,
    /// Height.
    height: u32,
}

impl DarkroomOp for CropV1 {
    fn id(&self) -> &'static str {
        "crop"
    }

    fn version(&self) -> u32 {
        1
    }

    fn stage(&self) -> OpStage {
        OpStage::Linear
    }

    fn validate_params(&self, params: &Value) -> Result<(), OpError> {
        self.read_settings(params).map(|_| ())
    }

    fn apply(&self, image: &OpImage, params: &Value, ctx: &OpContext) -> Result<OpImage, OpError> {
        let settings = self.read_settings(params)?;
        ctx.check_cancel()?;

        let width = image.width() as usize;
        let height = image.height() as usize;
        let channels = image.channels() as usize;
        let scale = ctx.scale();

        let x0 = (settings.x as f64 * scale).floor() as usize;
        let y0 = (settings.y as f64 * scale).floor() as usize;
        if x0 >= width || y0 >= height {
            return Err(OpError::Failed {
                op_id: self.id(),
                op_version: self.version(),
                reason: format!(
                    "crop origin ({}, {}) lies outside the {width}x{height} image at render level {}",
                    settings.x,
                    settings.y,
                    ctx.level()
                ),
            });
        }
        let x1 = (((settings.x as f64 + settings.width as f64) * scale).ceil() as usize).min(width);
        let y1 =
            (((settings.y as f64 + settings.height as f64) * scale).ceil() as usize).min(height);
        if x1 <= x0 || y1 <= y0 {
            return Err(OpError::Failed {
                op_id: self.id(),
                op_version: self.version(),
                reason: format!(
                    "crop rect {}x{} at ({}, {}) is empty at render level {}",
                    settings.width,
                    settings.height,
                    settings.x,
                    settings.y,
                    ctx.level()
                ),
            });
        }

        let out_width = x1 - x0;
        let out_height = y1 - y0;
        let out_row = out_width * channels;
        let source_row = width * channels;
        let source = image.data();
        let mut out = vec![0.0_f32; out_row * out_height];
        out.par_chunks_exact_mut(out_row)
            .enumerate()
            .for_each(|(y, row)| {
                if ctx.cancel_requested() {
                    return;
                }
                let start = (y + y0) * source_row + x0 * channels;
                row.copy_from_slice(&source[start..start + out_row]);
            });
        ctx.check_cancel()?;

        let mut cropped =
            image.with_geometry(out_width as u32, out_height as u32, channels as u32, out)?;
        cropped.translate_reference_pixel(x0 as f64, y0 as f64);
        Ok(cropped)
    }
}

impl CropV1 {
    /// Read and range-check one step's payload. `validate_params` and `apply`
    /// share this, so the two can never disagree about a default.
    ///
    /// `width` and `height` are required: the whole image is a different size at
    /// every master, so "the whole image" is not a constant a default could
    /// freeze.
    fn read_settings(&self, params: &Value) -> Result<Settings, OpError> {
        let p = Params::new(self, params)?;
        p.allow(&["x", "y", "width", "height"])?;
        Ok(Settings {
            x: p.u32_or("x", 0..=COORD_MAX, 0)?,
            y: p.u32_or("y", 0..=COORD_MAX, 0)?,
            width: p.u32_required("width", 1..=COORD_MAX)?,
            height: p.u32_required("height", 1..=COORD_MAX)?,
        })
    }
}

/// A crop rectangle in pixels, in the coordinate system of the image it was
/// proposed from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CropRect {
    /// Left edge.
    pub x: u32,
    /// Top edge.
    pub y: u32,
    /// Width.
    pub width: u32,
    /// Height.
    pub height: u32,
}

impl CropRect {
    /// The step parameter object this rectangle describes.
    pub fn to_params(&self) -> Value {
        json!({
            "x": self.x,
            "y": self.y,
            "width": self.width,
            "height": self.height,
        })
    }
}

/// Which edge of the working rectangle a shrink step removes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Edge {
    /// The first row.
    Top,
    /// The last row.
    Bottom,
    /// The first column.
    Left,
    /// The last column.
    Right,
}

/// Propose the largest fully covered rectangle in `image`.
///
/// A pixel is **covered** when every one of its channels is finite and at least
/// one is not exactly zero. Registration writes `NaN` or the integrator's zero
/// fill outside a frame's own footprint, while a genuine sky sample in linear
/// ADU sits on a pedestal and is never exactly zero, so the two are separable
/// without a threshold.
///
/// The proposal starts at the whole frame and repeatedly removes whichever edge
/// row or column carries the smallest covered fraction, stopping once all four
/// edges are wholly covered. Ties resolve top, bottom, left, right. Returns
/// `None` when no rectangle survives, which is what an entirely uncovered frame
/// deserves — never a fabricated rect.
///
/// The rectangle is in `image`'s own pixels. `crop@1` reads its parameters at
/// full resolution, so the proposal is made from the full-resolution master.
pub fn auto_rect(image: &OpImage) -> Option<CropRect> {
    let width = image.width() as usize;
    let height = image.height() as usize;
    let channels = image.channels() as usize;

    let covered: Vec<bool> = image
        .data()
        .par_chunks_exact(channels)
        .map(|pixel| {
            pixel.iter().all(|value| value.is_finite()) && pixel.iter().any(|value| *value != 0.0)
        })
        .collect();

    let (mut x0, mut x1) = (0usize, width);
    let (mut y0, mut y1) = (0usize, height);
    loop {
        if x1 <= x0 || y1 <= y0 {
            return None;
        }
        let row_span = x1 - x0;
        let column_span = y1 - y0;
        let candidates = [
            (
                row_covered(&covered, width, y0, x0, x1),
                row_span,
                Edge::Top,
            ),
            (
                row_covered(&covered, width, y1 - 1, x0, x1),
                row_span,
                Edge::Bottom,
            ),
            (
                column_covered(&covered, width, x0, y0, y1),
                column_span,
                Edge::Left,
            ),
            (
                column_covered(&covered, width, x1 - 1, y0, y1),
                column_span,
                Edge::Right,
            ),
        ];
        if candidates
            .iter()
            .all(|(covered_count, span, _)| covered_count == span)
        {
            break;
        }

        let mut worst = candidates[0];
        for candidate in candidates.iter().skip(1) {
            if (candidate.0 as u64) * (worst.1 as u64) < (worst.0 as u64) * (candidate.1 as u64) {
                worst = *candidate;
            }
        }
        match worst.2 {
            Edge::Top => y0 += 1,
            Edge::Bottom => y1 -= 1,
            Edge::Left => x0 += 1,
            Edge::Right => x1 -= 1,
        }
    }

    Some(CropRect {
        x: x0 as u32,
        y: y0 as u32,
        width: (x1 - x0) as u32,
        height: (y1 - y0) as u32,
    })
}

/// Covered pixels in row `y` between columns `x0` and `x1`.
fn row_covered(covered: &[bool], width: usize, y: usize, x0: usize, x1: usize) -> usize {
    covered[y * width + x0..y * width + x1]
        .iter()
        .filter(|value| **value)
        .count()
}

/// Covered pixels in column `x` between rows `y0` and `y1`.
fn column_covered(covered: &[bool], width: usize, x: usize, y0: usize, y1: usize) -> usize {
    (y0..y1).filter(|y| covered[y * width + x]).count()
}

#[cfg(test)]
#[path = "crop_tests.rs"]
mod crop_tests;
