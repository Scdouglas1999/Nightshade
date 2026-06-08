//! Post-session **combination** FFI surface — drizzle integration and
//! narrowband channel combine.
//!
//! This module exposes two committed native finishing primitives
//! (`nightshade_imaging::{drizzle, channel_combine}`) to Dart through the same
//! **JSON-in / JSON-out** boundary the rest of the post-session surface uses
//! (see [`crate::api::post_session`] for the canonical template and the
//! rationale). Every knob — drizzle scale / pixfrac / kernel, palette name,
//! custom weight tables — rides inside the JSON payload, so adding one never
//! triggers a `flutter_rust_bridge` regen. The boundary is exactly two
//! `String -> Result<String, String>` functions:
//!
//! * [`api_drizzle_integrate`] — variable-pixel linear reconstruction (drizzle)
//!   of a population of already-registered frames onto a finer output grid,
//!   with an RGB / Bayer-CFA mode, producing a linear `F32` master plus an
//!   optional per-pixel coverage map.
//! * [`api_combine_channels`] — linear narrowband palette combine (SHO / HOO /
//!   custom weights) of single-channel masters into a 3-channel `F32` RGB
//!   composite.
//!
//! These are **stateless per call** (no process-wide singleton) and CPU-bound;
//! the Dart side runs them off the UI isolate. As everywhere in the
//! post-session surface, every failure mode (no frames, unreadable FITS,
//! geometry mismatch, bad parameters, write failure) surfaces as `Err(String)`
//! — never a silent partial result.

use nightshade_imaging::channel_combine::{combine_channels, hoo_palette, sho_palette};
use nightshade_imaging::drizzle::{
    bayer_drizzle_integrate, drizzle_integrate, BayerDrizzleFrame, DrizzleConfig, DrizzleFrame,
    DrizzleKernel,
};
use nightshade_imaging::registration::{TransformKind, TransformModel};
use nightshade_imaging::{
    read_bayer_geometry, read_fits, write_fits, FitsHeader, ImageData, PixelType,
};
use serde::{Deserialize, Serialize};
use std::path::Path;

// =============================================================================
// api_drizzle_integrate — JSON contracts
// =============================================================================

/// One frame's contribution to a drizzle integration.
///
/// `transform` is the **row-major 3×3** homogeneous matrix mapping this frame's
/// pixel coordinates onto the **reference grid** (source → reference, the same
/// convention as [`nightshade_imaging::registration::TransformModel`]). It is
/// supplied as a flat 9-element array `[m00, m01, m02, m10, m11, m12, m20, m21,
/// m22]`. `weight` is the scalar quality weight applied to every drop from this
/// frame.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct DrizzleFrameArgs {
    /// FITS path of the (registered) frame to drizzle. For Bayer mode this is
    /// the raw, **un-debayered** single-channel CFA mosaic.
    fits_path: String,
    /// Row-major 3×3 source→reference transform, flattened to 9 elements.
    transform: Vec<f64>,
    /// Scalar quality weight for every drop from this frame (`<= 0` ⇒ skipped).
    weight: f64,
}

/// Drizzle tunables (subset of [`DrizzleConfig`]). Each unset field falls back
/// to the [`DrizzleConfig::default`] (2× drizzle, `pixfrac = 0.9`, square
/// kernel).
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct DrizzleConfigArgs {
    /// Linear output/input scale factor (`> 0`). `0`/unset ⇒ default `2.0`.
    scale: f64,
    /// Drop-shrink fraction in `(0, 1]`. `0`/unset ⇒ default `0.9`.
    pixfrac: f64,
    /// `"square"` (default) | `"point"` | `"gaussian"`. Empty ⇒ square.
    kernel: String,
}

/// Top-level request for [`api_drizzle_integrate`].
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct DrizzleIntegrateArgs {
    /// The frames to drizzle (each with its source→reference transform).
    frames: Vec<DrizzleFrameArgs>,
    /// Reference-grid width in pixels (the output grid is `ceil(ref_w · scale)`).
    ref_w: u32,
    /// Reference-grid height in pixels.
    ref_h: u32,
    /// Drizzle tunables (optional; defaults applied per field).
    config: DrizzleConfigArgs,
    /// When `true`, treat every input as a raw single-channel CFA mosaic and run
    /// **Bayer drizzle** into a 3-channel RGB master (no debayer interpolation).
    /// The Bayer pattern is read from each frame's FITS header (`BAYERPAT` +
    /// `XBAYROFF`/`YBAYROFF`).
    bayer: bool,
    /// Output FITS path for the linear `F32` master (required).
    output_fits: String,
    /// Optional output FITS path for the per-pixel coverage (drizzle weight) map.
    coverage_fits: Option<String>,
}

/// Response for [`api_drizzle_integrate`].
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct DrizzleIntegrateResult {
    /// Path the `F32` master was written to.
    output_path: String,
    /// Path the coverage map was written to, when requested.
    coverage_path: Option<String>,
    /// Output master width (`ceil(ref_w · scale)`).
    out_width: u32,
    /// Output master height (`ceil(ref_h · scale)`).
    out_height: u32,
    /// Output master channel count (1 or 3 for the RGB warp; always 3 for Bayer).
    channels: u32,
}

// =============================================================================
// api_combine_channels — JSON contracts
// =============================================================================

/// Top-level request for [`api_combine_channels`].
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct CombineChannelsArgs {
    /// Single-channel linear master FITS paths, in palette order.
    inputs: Vec<String>,
    /// Per-input `[r, g, b]` weight triples. Required unless `palette` is set;
    /// when both are given, `palette` wins and these are ignored.
    weights: Option<Vec<[f64; 3]>>,
    /// `"sho"` (S II→R, Hα→G, O III→B) | `"hoo"` (Hα→R, O III→G+B). When set,
    /// the canonical palette weight table is used and the input count must match
    /// the palette (3 for SHO, 2 for HOO).
    palette: Option<String>,
    /// Output FITS path for the 3-channel `F32` RGB composite (required).
    output_fits: String,
}

/// Response for [`api_combine_channels`].
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct CombineChannelsResult {
    /// Path the `F32` RGB composite was written to.
    output_path: String,
    /// Composite width in pixels.
    width: u32,
    /// Composite height in pixels.
    height: u32,
}

// =============================================================================
// Public FFI entry points
// =============================================================================

/// Drizzle (variable-pixel linear reconstruction) a population of registered
/// frames onto a `scale`× output grid.
///
/// Each frame is read from FITS, its 3×3 source→reference transform is rebuilt
/// into a [`TransformModel`], and its pixels are deposited as `pixfrac`-shrunk
/// drops via [`drizzle_integrate`] (RGB / mono) or [`bayer_drizzle_integrate`]
/// (raw CFA mosaic → 3-channel RGB, when `bayer == true`). The reconstructed
/// `F32` master is written to `output_fits`; when `coverage_fits` is given the
/// per-pixel drizzle-weight map is written there too.
///
/// `args_json` is a [`DrizzleIntegrateArgs`]; the result is a
/// [`DrizzleIntegrateResult`]. Every failure (no frames, unreadable frame,
/// missing Bayer header in Bayer mode, geometry mismatch, bad parameters, write
/// failure) surfaces as `Err(String)` — never a silent partial stack.
pub fn api_drizzle_integrate(args_json: String) -> Result<String, String> {
    let args: DrizzleIntegrateArgs =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid drizzle args: {e}"))?;
    let result = drizzle_integrate_impl(args)?;
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

/// Linearly combine single-channel narrowband masters into a 3-channel `F32`
/// RGB composite, wrapping [`combine_channels`].
///
/// When `palette` is `"sho"`/`"hoo"` the canonical weight table
/// ([`sho_palette`]/[`hoo_palette`]) is used; otherwise the explicit per-input
/// `[r, g, b]` `weights` are applied. The composite is written to `output_fits`.
///
/// `args_json` is a [`CombineChannelsArgs`]; the result is a
/// [`CombineChannelsResult`].
pub fn api_combine_channels(args_json: String) -> Result<String, String> {
    let args: CombineChannelsArgs =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid combine args: {e}"))?;
    let result = combine_channels_impl(args)?;
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

// =============================================================================
// api_drizzle_integrate implementation
// =============================================================================

fn drizzle_integrate_impl(
    args: DrizzleIntegrateArgs,
) -> Result<DrizzleIntegrateResult, String> {
    if args.frames.is_empty() {
        return Err("no frames to drizzle".to_string());
    }
    if args.output_fits.trim().is_empty() {
        return Err("outputFits is required".to_string());
    }
    if args.ref_w == 0 || args.ref_h == 0 {
        return Err("refW and refH must both be > 0".to_string());
    }

    let cfg = build_drizzle_config(&args.config)?;

    // The native `DrizzleFrame`/`BayerDrizzleFrame` borrow their pixel buffer
    // and transform by reference (`&'a [f64]`, `&'a TransformModel`). We must
    // therefore materialise the owned `Vec<f64>` buffers and owned
    // `TransformModel`s into vectors that outlive the borrowed frame slice — so
    // the `&[f64]` stays valid for the whole `*_integrate` call. We build the
    // owned storage first, then borrow from it in a second pass.
    let mut buffers: Vec<Vec<f64>> = Vec::with_capacity(args.frames.len());
    let mut transforms: Vec<TransformModel> = Vec::with_capacity(args.frames.len());
    let mut dims: Vec<(u32, u32, u32)> = Vec::with_capacity(args.frames.len());
    let mut patterns: Vec<nightshade_imaging::BayerPattern> =
        Vec::with_capacity(args.frames.len());

    for fa in &args.frames {
        if fa.fits_path.trim().is_empty() {
            return Err("a drizzle frame has an empty fitsPath".to_string());
        }
        let (image, header) = read_fits(Path::new(&fa.fits_path))
            .map_err(|e| format!("failed to read '{}': {e:?}", fa.fits_path))?;
        let transform = transform_from_row_major(&fa.transform)
            .map_err(|e| format!("frame '{}': {e}", fa.fits_path))?;

        if args.bayer {
            // Raw CFA mode: the mosaic must be a single-channel buffer, and the
            // Bayer pattern is read from the typed FITS header. We refuse to
            // guess a pattern (mis-coloured reconstruction otherwise).
            if image.channels != 1 {
                return Err(format!(
                    "Bayer drizzle requires a single-channel CFA mosaic, but '{}' has {} channels",
                    fa.fits_path, image.channels
                ));
            }
            let geometry = read_bayer_geometry(&header).ok_or_else(|| {
                format!(
                    "'{}' has no BAYERPAT header; cannot Bayer-drizzle a frame without a CFA pattern",
                    fa.fits_path
                )
            })?;
            patterns.push(geometry.effective);
        }

        buffers.push(decode_image_f64(&image, &fa.fits_path)?);
        dims.push((image.width, image.height, image.channels));
        transforms.push(transform);
    }

    let output = if args.bayer {
        let frames: Vec<BayerDrizzleFrame> = buffers
            .iter()
            .zip(dims.iter())
            .zip(transforms.iter())
            .zip(patterns.iter())
            .zip(args.frames.iter())
            .map(|((((mosaic, &(w, h, _c)), transform), &pattern), fa)| BayerDrizzleFrame {
                mosaic,
                width: w,
                height: h,
                pattern,
                transform,
                weight: fa.weight,
            })
            .collect();
        bayer_drizzle_integrate(&frames, args.ref_w, args.ref_h, &cfg)
            .map_err(|e| format!("Bayer drizzle failed: {e}"))?
    } else {
        let frames: Vec<DrizzleFrame> = buffers
            .iter()
            .zip(dims.iter())
            .zip(transforms.iter())
            .zip(args.frames.iter())
            .map(|(((pixels, &(w, h, c)), transform), fa)| DrizzleFrame {
                pixels,
                width: w,
                height: h,
                channels: c,
                transform,
                weight: fa.weight,
            })
            .collect();
        drizzle_integrate(&frames, args.ref_w, args.ref_h, &cfg)
            .map_err(|e| format!("drizzle failed: {e}"))?
    };

    // --- Write the F32 master. ---
    let master_path = Path::new(&args.output_fits);
    ensure_parent_dir(master_path)?;
    let mut header = FitsHeader::new();
    header.set_string("IMAGETYP", "MASTER_LIGHT");
    header.set_string("FRAMETYP", "MASTER");
    header.set_string("CALSTAT", "Nightshade drizzle master");
    header.set_int("NFRAMES", args.frames.len() as i64);
    header.set_float("DRZSCALE", cfg.scale);
    header.set_float("PIXFRAC", cfg.pixfrac);
    header.set_string("DRZKERN", kernel_name(cfg.kernel));
    header.add_history(if args.bayer {
        "Nightshade Bayer-CFA drizzle integration"
    } else {
        "Nightshade drizzle integration"
    });
    write_fits(master_path, &output.master, &header)
        .map_err(|e| format!("failed to write drizzle master: {e:?}"))?;

    // --- Optional coverage map FITS. ---
    let coverage_path = match args.coverage_fits.as_ref() {
        Some(p) if !p.trim().is_empty() => {
            let path = Path::new(p);
            ensure_parent_dir(path)?;
            let mut h = FitsHeader::new();
            h.set_string("IMAGETYP", "COVERAGE_MAP");
            h.add_history("Nightshade drizzle per-pixel coverage (drizzle weight) map");
            write_fits(path, &output.coverage, &h)
                .map_err(|e| format!("failed to write coverage map: {e:?}"))?;
            Some(p.clone())
        }
        _ => None,
    };

    Ok(DrizzleIntegrateResult {
        output_path: args.output_fits,
        coverage_path,
        out_width: output.master.width,
        out_height: output.master.height,
        channels: output.master.channels,
    })
}

/// Build a [`DrizzleConfig`] from the JSON args, applying the
/// [`DrizzleConfig::default`] for any unset (`0`/empty) field. Out-of-range
/// values are left for the native `validate()` to reject with a descriptive
/// error.
fn build_drizzle_config(a: &DrizzleConfigArgs) -> Result<DrizzleConfig, String> {
    let mut cfg = DrizzleConfig::default();
    if a.scale > 0.0 {
        cfg.scale = a.scale;
    }
    if a.pixfrac > 0.0 {
        cfg.pixfrac = a.pixfrac;
    }
    cfg.kernel = match a.kernel.trim().to_ascii_lowercase().as_str() {
        "" | "square" => DrizzleKernel::Square,
        "point" => DrizzleKernel::Point,
        "gaussian" => DrizzleKernel::Gaussian,
        other => return Err(format!("unknown drizzle kernel '{other}'")),
    };
    Ok(cfg)
}

/// The FITS-header token for a drizzle kernel (for the `DRZKERN` provenance card).
fn kernel_name(kernel: DrizzleKernel) -> &'static str {
    match kernel {
        DrizzleKernel::Square => "square",
        DrizzleKernel::Point => "point",
        DrizzleKernel::Gaussian => "gaussian",
    }
}

/// Rebuild a [`TransformModel`] (source → reference) from a flat row-major
/// 9-element 3×3 matrix `[m00, m01, m02, m10, m11, m12, m20, m21, m22]`.
///
/// `kind` is purely informational on the native side (the warp uses the matrix
/// directly), so we tag a general matrix as [`TransformKind::Homography`]: it is
/// the only family whose bottom row is unconstrained, and reporting it as such
/// is honest about the most general matrix we accept.
fn transform_from_row_major(m: &[f64]) -> Result<TransformModel, String> {
    if m.len() != 9 {
        return Err(format!(
            "transform must be a row-major 3x3 (9 elements), got {}",
            m.len()
        ));
    }
    if !m.iter().all(|v| v.is_finite()) {
        return Err("transform contains a non-finite element".to_string());
    }
    let matrix = [
        [m[0], m[1], m[2]],
        [m[3], m[4], m[5]],
        [m[6], m[7], m[8]],
    ];
    Ok(TransformModel {
        matrix,
        kind: TransformKind::Homography,
    })
}

/// Decode an [`ImageData`] (the linear masters / mosaics the pipeline emits,
/// `U16` and `F32`) into a flat channel-interleaved `f64` buffer.
///
/// Any other pixel type is a hard error: drizzle needs the real linear samples,
/// and silently producing an empty buffer would mis-size the integration.
fn decode_image_f64(image: &ImageData, path: &str) -> Result<Vec<f64>, String> {
    match image.pixel_type {
        PixelType::U16 => image
            .as_u16()
            .map(|v| v.into_iter().map(|x| x as f64).collect())
            .ok_or_else(|| format!("'{path}' could not be decoded as U16")),
        PixelType::F32 => image
            .as_f32()
            .map(|v| v.into_iter().map(|x| x as f64).collect())
            .ok_or_else(|| format!("'{path}' could not be decoded as F32")),
        other => Err(format!(
            "'{path}' is {other:?}; drizzle requires a U16 or F32 frame"
        )),
    }
}

// =============================================================================
// api_combine_channels implementation
// =============================================================================

fn combine_channels_impl(
    args: CombineChannelsArgs,
) -> Result<CombineChannelsResult, String> {
    if args.inputs.is_empty() {
        return Err("no input channels supplied to combine".to_string());
    }
    if args.output_fits.trim().is_empty() {
        return Err("outputFits is required".to_string());
    }

    // Read every single-channel master. We hold them in an owned `Vec<ImageData>`
    // so the `&[&ImageData]` slice `combine_channels` borrows stays valid.
    let images: Vec<ImageData> = args
        .inputs
        .iter()
        .map(|p| {
            read_fits(Path::new(p))
                .map(|(image, _header)| image)
                .map_err(|e| format!("failed to read '{p}': {e:?}"))
        })
        .collect::<Result<_, _>>()?;

    // Resolve the weight table: a named palette wins, else the explicit weights.
    let weights: Vec<[f64; 3]> = if let Some(palette) = args.palette.as_ref() {
        let p = palette.trim().to_ascii_lowercase();
        match p.as_str() {
            "sho" => {
                let w = sho_palette();
                if images.len() != w.len() {
                    return Err(format!(
                        "SHO palette expects {} inputs (S II, Hα, O III) but {} were supplied",
                        w.len(),
                        images.len()
                    ));
                }
                w
            }
            "hoo" => {
                let w = hoo_palette();
                if images.len() != w.len() {
                    return Err(format!(
                        "HOO palette expects {} inputs (Hα, O III) but {} were supplied",
                        w.len(),
                        images.len()
                    ));
                }
                w
            }
            other => return Err(format!("unknown palette '{other}'; expected sho or hoo")),
        }
    } else {
        match args.weights {
            Some(w) if !w.is_empty() => w,
            _ => {
                return Err(
                    "either palette or a non-empty weights table is required".to_string()
                )
            }
        }
    };

    let refs: Vec<&ImageData> = images.iter().collect();
    let composite = combine_channels(&refs, &weights)
        .map_err(|e| format!("channel combine failed: {e}"))?;

    let out_path = Path::new(&args.output_fits);
    ensure_parent_dir(out_path)?;
    let mut header = FitsHeader::new();
    header.set_string("IMAGETYP", "MASTER_LIGHT");
    header.set_string("FRAMETYP", "MASTER");
    header.set_string("CALSTAT", "Nightshade channel combine");
    if let Some(palette) = args.palette.as_ref() {
        header.set_string("PALETTE", palette.trim());
    }
    header.add_history("Nightshade narrowband channel combination");
    write_fits(out_path, &composite, &header)
        .map_err(|e| format!("failed to write composite: {e:?}"))?;

    Ok(CombineChannelsResult {
        output_path: args.output_fits,
        width: composite.width,
        height: composite.height,
    })
}

// =============================================================================
// Shared helpers
// =============================================================================

/// Ensure the parent directory of `path` exists, creating it if necessary.
///
/// Mirrors the `ensure_parent_dir` in [`crate::api::post_session`]; duplicated
/// here so this module stays self-contained (its `pub(super)` sibling is private
/// to that module).
fn ensure_parent_dir(path: &Path) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("failed to create output directory '{}': {e}", parent.display()))?;
        }
    }
    Ok(())
}
