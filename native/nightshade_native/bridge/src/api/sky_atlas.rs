//! Sky-atlas (Pillar A — "Your Sky") FFI surface.
//!
//! This module exposes the HEALPix-tiled, out-of-core, **additive** all-sky
//! accumulator ([`nightshade_imaging::sky_atlas`]) to Dart through the same
//! **JSON-in / JSON-out** boundary the rest of the post-session / finishing
//! surface uses (see [`crate::api::post_session`] for the canonical template and
//! the rationale: regenerating `flutter_rust_bridge` bindings is heavyweight, so
//! every knob rides inside the JSON payload and never triggers another regen).
//!
//! The keystone is built; this is its bridge. Two entry shapes are exposed:
//!
//! * [`api_sky_atlas`] — the **dispatcher** matching `docs/nightshade_5_0_contracts.md`
//!   §2.1, switched on an `"action"` field (`fold` / `finalize` / `tilePng` /
//!   `coverage` / `exportDelta` / `info`). The Dart `SkyAtlasService` calls this.
//! * Four **named convenience wrappers** — [`api_sky_atlas_add_frame`],
//!   [`api_sky_atlas_query_cutout`], [`api_sky_atlas_region_info`],
//!   [`api_sky_atlas_growth`] — the higher-level operations a UI wants directly:
//!   fold one plate-solved capture, co-add a cone into a sharable cutout, summarise
//!   a region, and report a deepening growth curve.
//!
//! Every call is **stateless per call** (the atlas state lives entirely in the
//! on-disk tile sidecars under `<atlasRoot>/tiles/<order>/<tileId>.nst`); the
//! calls are CPU- / IO-bound and synchronous, run off the Dart UI isolate. Every
//! failure mode (bad action, unreadable frame, degenerate WCS, no coverage, write
//! failure) surfaces as `Err(String)` — never a silent partial fold.

use nightshade_imaging::registration::Interpolator;
use nightshade_imaging::sky_atlas::{
    merge_tiles, merge_tiles_subtract, tile_center, AtlasError, SkyAtlas, SkyTileAccumulator,
    TileId, TileProvenance, ATLAS_HEALPIX_ORDER,
};
use nightshade_imaging::wcs_sip::SipWcs;
use nightshade_imaging::{
    add_wcs_headers, master_accumulation::AccumulationMode, master_accumulation::OnlineClip,
    read_image, write_fits, FitsHeader, ImageData, WcsInfo,
};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::api::post_session::write_preview_png;

/// Default resident-tile memory budget for a fold (512 MiB). A 1024² mono
/// accumulator is ~50 MB; the atlas processes tiles one at a time, so the budget
/// only bounds the (currently single) resident buffer — generous headroom for the
/// largest channel counts and a future batched variant.
const DEFAULT_MEMORY_BUDGET_BYTES: u64 = 512 * 1024 * 1024;

// =============================================================================
// Shared JSON helpers
// =============================================================================

/// Parse an interpolator token (`bilinear` | `catmullRom` | `lanczos3`), falling
/// back to Lanczos-3 (the atlas / mosaic default) when unset or empty.
fn parse_interp(s: &str) -> Result<Interpolator, String> {
    match s.trim().to_ascii_lowercase().as_str() {
        "" | "lanczos3" | "lanczos" => Ok(Interpolator::Lanczos3),
        "catmullrom" | "catmull-rom" | "catmull" => Ok(Interpolator::CatmullRom),
        "bilinear" | "linear" => Ok(Interpolator::Bilinear),
        other => Err(format!("unknown interpolator '{other}'")),
    }
}

/// Resolve the accumulation mode from optional online-clip thresholds. Both
/// present ⇒ a clipped running mean; either absent ⇒ a pure running weighted mean
/// (the federation-exact mode, matching the master's `online_clip` contract).
fn mode_from_clip(low: Option<f64>, high: Option<f64>) -> AccumulationMode {
    match (low, high) {
        (Some(low), Some(high)) => AccumulationMode::RunningWeightedMean {
            clip: Some(OnlineClip { low, high }),
        },
        _ => AccumulationMode::RunningWeightedMean { clip: None },
    }
}

/// Map a [`nightshade_imaging::sky_atlas::AtlasError`] to a human FFI string.
fn describe_atlas_error(e: &AtlasError) -> String {
    e.to_string()
}

/// Ensure the parent directory of `path` exists, creating it if necessary.
fn ensure_parent_dir(path: &Path) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent).map_err(|e| {
                format!(
                    "failed to create output directory '{}': {e}",
                    parent.display()
                )
            })?;
        }
    }
    Ok(())
}

/// A tile's local TAN grid is CD-only ([`SipWcs::tan_only`]); project it onto the
/// CD-matrix [`WcsInfo`] the FITS writer stamps so a finalized tile carries its
/// astrometry on disk.
fn wcs_info_from_tile(wcs: &SipWcs) -> WcsInfo {
    WcsInfo {
        crval1: wcs.crval1,
        crval2: wcs.crval2,
        crpix1: wcs.crpix1,
        crpix2: wcs.crpix2,
        cd1_1: wcs.cd1_1,
        cd1_2: wcs.cd1_2,
        cd2_1: wcs.cd2_1,
        cd2_2: wcs.cd2_2,
    }
}

/// Open the atlas rooted at `atlas_root` for `order` with the default memory
/// budget, rejecting an empty root loudly.
fn open_atlas(atlas_root: &str, order: u32) -> Result<SkyAtlas, String> {
    if atlas_root.trim().is_empty() {
        return Err("atlasRoot is required".to_string());
    }
    Ok(SkyAtlas::open(
        atlas_root,
        order,
        DEFAULT_MEMORY_BUDGET_BYTES,
    ))
}

/// Read a light frame and (best-effort) convert it to the linear `F32`/`U16`
/// layout the atlas resampler decodes. A frame the atlas cannot decode folds as
/// no contribution, so the only hard error here is an unreadable file.
fn read_frame(path: &str) -> Result<ImageData, String> {
    let read = read_image(Path::new(path)).map_err(|e| format!("failed to read '{path}': {e}"))?;
    Ok(read.image)
}

/// Enumerate every tile sidecar id present on disk for this atlas/order by
/// walking `<root>/tiles/<order>/`. Returns an ascending, deduplicated id list.
/// A missing directory (atlas never folded into) yields an empty list, not an
/// error — a brand-new atlas legitimately has no tiles yet.
fn list_tiles_on_disk(atlas: &SkyAtlas) -> Result<Vec<TileId>, String> {
    // `tile_path(0)` gives `<root>/tiles/<order>/0.nst`; its parent is the dir.
    let dir = match atlas.tile_path(0).parent() {
        Some(p) => p.to_path_buf(),
        None => return Ok(Vec::new()),
    };
    let entries = match std::fs::read_dir(&dir) {
        Ok(e) => e,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(e) => return Err(format!("failed to scan tile directory: {e}")),
    };
    let mut ids: Vec<TileId> = Vec::new();
    for entry in entries {
        let entry = entry.map_err(|e| format!("failed to read tile directory entry: {e}"))?;
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) != Some("nst") {
            continue;
        }
        if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
            if let Ok(id) = stem.parse::<TileId>() {
                ids.push(id);
            }
        }
    }
    ids.sort_unstable();
    ids.dedup();
    Ok(ids)
}

// =============================================================================
// api_sky_atlas — the dispatcher (contracts §2.1)
// =============================================================================

#[derive(Debug, Clone, Deserialize)]
#[flutter_rust_bridge::frb(ignore)]
struct AtlasAction {
    action: String,
}

/// Sky-atlas dispatcher. `args_json` carries an `"action"` selecting the
/// operation; the remaining fields are the action-specific payload documented in
/// `docs/nightshade_5_0_contracts.md` §2.1. Returns the action's JSON result.
pub fn api_sky_atlas(args_json: String) -> Result<String, String> {
    let action: AtlasAction =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid atlas args: {e}"))?;
    match action.action.as_str() {
        "fold" => {
            let args: FoldArgs =
                serde_json::from_str(&args_json).map_err(|e| format!("invalid fold args: {e}"))?;
            let result = fold_impl(args)?;
            serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
        }
        "finalize" => {
            let args: FinalizeArgs = serde_json::from_str(&args_json)
                .map_err(|e| format!("invalid finalize args: {e}"))?;
            let result = finalize_impl(args)?;
            serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
        }
        "tilePng" => {
            let args: TilePngArgs = serde_json::from_str(&args_json)
                .map_err(|e| format!("invalid tilePng args: {e}"))?;
            let result = tile_png_impl(args)?;
            serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
        }
        "coverage" => {
            let args: CoverageArgs = serde_json::from_str(&args_json)
                .map_err(|e| format!("invalid coverage args: {e}"))?;
            let result = coverage_impl(args)?;
            serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
        }
        "exportDelta" => {
            let args: ExportDeltaArgs = serde_json::from_str(&args_json)
                .map_err(|e| format!("invalid exportDelta args: {e}"))?;
            let result = export_delta_impl(args)?;
            serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
        }
        "info" => {
            let args: InfoArgs =
                serde_json::from_str(&args_json).map_err(|e| format!("invalid info args: {e}"))?;
            let result = info_impl(args)?;
            serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
        }
        other => Err(format!(
            "unknown atlas action '{other}'; expected fold/finalize/tilePng/coverage/exportDelta/info"
        )),
    }
}

// --- action "fold" --------------------------------------------------------

/// One plate-solved frame to fold: its path, integration weight, exposure, and
/// the full CD + SIP astrometry it was solved with.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct FoldFrameArgs {
    /// Light-frame path (FITS/XISF/etc.), already plate-solved.
    frame_path: String,
    /// Integration weight (≤ 0 ⇒ the frame folds as no contribution).
    #[serde(default = "default_weight")]
    weight: f64,
    /// Exposure seconds (for the integration-time provenance tally).
    #[serde(default)]
    exposure_sec: f64,
    /// The solved CD + SIP WCS for this frame.
    wcs: SipWcs,
}

fn default_weight() -> f64 {
    1.0
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct FoldArgs {
    atlas_root: String,
    #[serde(default = "default_order")]
    order: u32,
    /// Contributor id; `""` for local.
    #[serde(default)]
    contributor: String,
    /// `bilinear` | `catmullRom` | `lanczos3` (default lanczos3).
    #[serde(default)]
    interp: String,
    /// ISO date / session label for the fold log.
    #[serde(default)]
    label: String,
    /// Optional online-clip thresholds (σ). Both present ⇒ clipped running mean.
    #[serde(default)]
    online_clip_low: Option<f64>,
    #[serde(default)]
    online_clip_high: Option<f64>,
    /// The frames to fold.
    frames: Vec<FoldFrameArgs>,
}

fn default_order() -> u32 {
    ATLAS_HEALPIX_ORDER
}

/// Per-tile fold summary returned to Dart for the `sky_tiles` index update.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct TileFoldSummary {
    tile_id: TileId,
    frames_added: usize,
    weight_added: f64,
    rejected: u64,
    coverage_mean: f64,
    center_ra: f64,
    center_dec: f64,
    total_frames: usize,
    integration_seconds: f64,
    channels: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct FoldResult {
    ok: bool,
    /// Ascending, deduplicated ids of every tile this fold touched.
    tiles_touched: Vec<TileId>,
    /// Per-tile fold + post-fold-state summaries.
    folds_by_tile: Vec<TileFoldSummary>,
    /// Frames whose footprint covered no tiles (dropped, not fatal).
    frames_skipped_no_coverage: usize,
}

fn fold_impl(args: FoldArgs) -> Result<FoldResult, String> {
    if args.frames.is_empty() {
        return Err("fold requires at least one frame".to_string());
    }
    let atlas = open_atlas(&args.atlas_root, args.order)?;
    let interp = parse_interp(&args.interp)?;
    let mode = mode_from_clip(args.online_clip_low, args.online_clip_high);
    let label = if args.label.trim().is_empty() {
        "fold"
    } else {
        args.label.trim()
    };

    // Aggregate per-tile results across every frame in this call. A tile touched
    // by N frames reports the summed fold tallies and its final post-fold state.
    use std::collections::BTreeMap;
    let mut frames_added: BTreeMap<TileId, usize> = BTreeMap::new();
    let mut weight_added: BTreeMap<TileId, f64> = BTreeMap::new();
    let mut rejected: BTreeMap<TileId, u64> = BTreeMap::new();
    let mut frames_skipped = 0usize;

    for frame_args in &args.frames {
        if !frame_args.wcs.is_invertible() {
            return Err(format!(
                "frame '{}' has a degenerate (non-invertible) WCS",
                frame_args.frame_path
            ));
        }
        let frame = read_frame(&frame_args.frame_path)?;
        match atlas.fold_frame(
            &frame,
            &frame_args.wcs,
            frame_args.weight,
            frame_args.exposure_sec,
            interp,
            mode,
            label,
            &args.contributor,
        ) {
            Ok(records) => {
                for (tid, rec) in records {
                    *frames_added.entry(tid).or_default() += rec.frames_added;
                    *weight_added.entry(tid).or_default() += rec.weight_added;
                    *rejected.entry(tid).or_default() += rec.rejected;
                }
            }
            Err(AtlasError::NoCoverage) => {
                // A frame whose footprint is off-sky / empty is dropped, not
                // fatal: the rest of the call still folds.
                frames_skipped += 1;
            }
            Err(e) => return Err(describe_atlas_error(&e)),
        }
    }

    // Load each touched tile once more for its post-fold summary (coverage mean,
    // running totals, geometry) — the index the Dart side persists to `sky_tiles`.
    let mut folds_by_tile = Vec::with_capacity(frames_added.len());
    let mut tiles_touched: Vec<TileId> = frames_added.keys().copied().collect();
    tiles_touched.sort_unstable();
    for &tid in &tiles_touched {
        let (center_ra, center_dec) = tile_center(tid, args.order);
        let (coverage_mean, total_frames, integration_seconds, channels) =
            match atlas.load_tile(tid).map_err(|e| describe_atlas_error(&e))? {
                Some(tile) => (
                    tile.coverage_mean(),
                    tile.provenance.total_frames,
                    tile.provenance.total_integration_seconds,
                    tile.channels,
                ),
                None => (0.0, 0, 0.0, 0),
            };
        folds_by_tile.push(TileFoldSummary {
            tile_id: tid,
            frames_added: frames_added.get(&tid).copied().unwrap_or(0),
            weight_added: weight_added.get(&tid).copied().unwrap_or(0.0),
            rejected: rejected.get(&tid).copied().unwrap_or(0),
            coverage_mean,
            center_ra,
            center_dec,
            total_frames,
            integration_seconds,
            channels,
        });
    }

    Ok(FoldResult {
        ok: true,
        tiles_touched,
        folds_by_tile,
        frames_skipped_no_coverage: frames_skipped,
    })
}

// --- action "finalize" ----------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct FinalizeArgs {
    atlas_root: String,
    #[serde(default = "default_order")]
    order: u32,
    tile_id: TileId,
    /// Output FITS path for the finalized `F32` tile raster.
    out_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct FinalizeResult {
    ok: bool,
    out_path: String,
    width: u32,
    height: u32,
    channels: u32,
}

fn finalize_impl(args: FinalizeArgs) -> Result<FinalizeResult, String> {
    if args.out_path.trim().is_empty() {
        return Err("finalize requires outPath".to_string());
    }
    let atlas = open_atlas(&args.atlas_root, args.order)?;
    let tile = atlas
        .load_tile(args.tile_id)
        .map_err(|e| describe_atlas_error(&e))?
        .ok_or_else(|| format!("tile {} has not been folded into yet", args.tile_id))?;
    let image = tile.finalize();
    let path = Path::new(&args.out_path);
    ensure_parent_dir(path)?;
    let mut header = FitsHeader::new();
    header.set_string("IMAGETYP", "MASTER_LIGHT");
    header.set_string("FRAMETYP", "MASTER");
    header.set_string("CALSTAT", "Nightshade sky-atlas tile");
    header.set_int("TILEID", args.tile_id as i64);
    header.set_int("HPXORDER", args.order as i64);
    header.set_int("NFRAMES", tile.provenance.total_frames as i64);
    header.set_float("EXPTIME", tile.provenance.total_integration_seconds);
    add_wcs_headers(&mut header, &wcs_info_from_tile(&tile.wcs));
    header.add_history(&format!(
        "Sky-atlas tile {} (order {}) finalized from {} frames across {} folds",
        args.tile_id,
        args.order,
        tile.provenance.total_frames,
        tile.provenance.folds.len()
    ));
    write_fits(path, &image, &header).map_err(|e| format!("failed to write tile FITS: {e:?}"))?;
    Ok(FinalizeResult {
        ok: true,
        out_path: args.out_path,
        width: image.width,
        height: image.height,
        channels: image.channels,
    })
}

// --- action "tilePng" -----------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct TilePngArgs {
    atlas_root: String,
    #[serde(default = "default_order")]
    order: u32,
    tile_id: TileId,
    out_path: String,
    /// Optional time-scrub anchor (ISO). When present, only folds at/before this
    /// instant contribute: the tile is rebuilt from its provenance fold log by
    /// retracting later folds, so the PNG shows the sky "as of" that date.
    #[serde(default)]
    as_of_iso: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct TilePngResult {
    ok: bool,
    out_path: String,
}

fn tile_png_impl(args: TilePngArgs) -> Result<TilePngResult, String> {
    if args.out_path.trim().is_empty() {
        return Err("tilePng requires outPath".to_string());
    }
    let atlas = open_atlas(&args.atlas_root, args.order)?;
    let tile = atlas
        .load_tile(args.tile_id)
        .map_err(|e| describe_atlas_error(&e))?
        .ok_or_else(|| format!("tile {} has not been folded into yet", args.tile_id))?;

    // Time-scrub: the running sums are linear and the fold log records each fold's
    // (signed) contribution, but the per-pixel deltas are not stored per fold —
    // only the per-fold scalar tallies are. So an `asOfIso` request is honoured
    // honestly at the granularity the accumulator supports: if every fold is
    // at/before the anchor the full tile is rendered; if the anchor predates the
    // tile's first fold there is nothing to show. We never fabricate a partial
    // per-pixel reconstruction the stored state cannot back.
    if let Some(as_of) = args.as_of_iso.as_ref().filter(|s| !s.trim().is_empty()) {
        let any_after = tile
            .provenance
            .folds
            .iter()
            .any(|f| iso_is_after(&f.label, as_of));
        let all_after = !tile.provenance.folds.is_empty()
            && tile
                .provenance
                .folds
                .iter()
                .all(|f| iso_is_after(&f.label, as_of));
        if all_after {
            return Err(format!(
                "tile {} has no folds at or before {as_of}",
                args.tile_id
            ));
        }
        if any_after {
            // Some folds are later than the anchor but we cannot retract them at
            // pixel granularity from the stored scalar log — surface that rather
            // than render a misleading "as-of" image.
            return Err(format!(
                "tile {} cannot be scrubbed to {as_of}: per-fold pixel deltas are not retained \
                 (export per-night deltas to reconstruct an as-of view)",
                args.tile_id
            ));
        }
    }

    let image = tile.finalize();
    let path = Path::new(&args.out_path);
    ensure_parent_dir(path)?;
    write_preview_png(&image, path)?;
    Ok(TilePngResult {
        ok: true,
        out_path: args.out_path,
    })
}

/// Best-effort lexicographic ISO-8601 comparison: returns `true` if `label`
/// parses as an ISO timestamp strictly after `anchor`. ISO-8601 in canonical
/// (zero-padded, UTC `Z`) form sorts lexicographically by instant, which is how
/// the fold labels are written by the Dart session layer. A `label` that is not
/// a timestamp (a free-form session id) is treated as **not after** the anchor
/// (it contributes), so a non-dated fold is never silently dropped.
fn iso_is_after(label: &str, anchor: &str) -> bool {
    let l = label.trim();
    // Only compare when the label looks like an ISO date/time (starts YYYY-MM).
    let looks_iso =
        l.len() >= 7 && l.as_bytes()[4] == b'-' && l[..4].chars().all(|c| c.is_ascii_digit());
    looks_iso && l > anchor.trim()
}

// --- action "coverage" ----------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct CoverageArgs {
    atlas_root: String,
    #[serde(default = "default_order")]
    order: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct TileCoverage {
    tile_id: TileId,
    center_ra: f64,
    center_dec: f64,
    coverage_mean: f64,
    total_frames: usize,
    integration_seconds: f64,
    last_fold_iso: Option<String>,
    channels: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct CoverageResult {
    ok: bool,
    tiles: Vec<TileCoverage>,
}

fn coverage_impl(args: CoverageArgs) -> Result<CoverageResult, String> {
    let atlas = open_atlas(&args.atlas_root, args.order)?;
    let ids = list_tiles_on_disk(&atlas)?;
    let mut tiles = Vec::with_capacity(ids.len());
    for tid in ids {
        let Some(tile) = atlas.load_tile(tid).map_err(|e| describe_atlas_error(&e))? else {
            continue;
        };
        let (center_ra, center_dec) = tile_center(tid, args.order);
        tiles.push(TileCoverage {
            tile_id: tid,
            center_ra,
            center_dec,
            coverage_mean: tile.coverage_mean(),
            total_frames: tile.provenance.total_frames,
            integration_seconds: tile.provenance.total_integration_seconds,
            last_fold_iso: tile
                .provenance
                .folds
                .last()
                .map(|f| f.label.clone())
                .filter(|s| !s.trim().is_empty()),
            channels: tile.channels,
        });
    }
    Ok(CoverageResult { ok: true, tiles })
}

// --- action "exportDelta" -------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct ExportDeltaArgs {
    atlas_root: String,
    #[serde(default = "default_order")]
    order: u32,
    tile_id: TileId,
    /// ISO anchor: only folds strictly after this instant are in the delta.
    since_iso: String,
    /// Output `.nst` path for the delta accumulator.
    out_path: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct ExportDeltaResult {
    ok: bool,
    out_path: String,
    frames_in_delta: usize,
    integration_seconds: f64,
}

fn export_delta_impl(args: ExportDeltaArgs) -> Result<ExportDeltaResult, String> {
    if args.out_path.trim().is_empty() {
        return Err("exportDelta requires outPath".to_string());
    }
    let atlas = open_atlas(&args.atlas_root, args.order)?;
    let tile = atlas
        .load_tile(args.tile_id)
        .map_err(|e| describe_atlas_error(&e))?
        .ok_or_else(|| format!("tile {} has not been folded into yet", args.tile_id))?;

    // The delta is the accumulator state attributable to folds after `sinceIso`.
    // With the per-fold scalar log (not per-fold pixel deltas) we can compute the
    // delta exactly only when the post-anchor folds are separable — which they are
    // not at pixel granularity from a single merged state. The honest, exact
    // export the federation layer actually consumes is therefore the **whole tile
    // accumulator** when every fold is post-anchor (the common "share my new
    // night" case), tagged with the post-anchor frame/second tallies. When older
    // folds are mixed in, exporting the whole state would over-share; we surface
    // that and direct the caller to export at fold time instead.
    // Fail closed: a fold is treated as pre-anchor (and therefore BLOCKS a
    // whole-tile export) unless its label is a recognizable date that is strictly
    // after `sinceIso`. An undatable free-form label (e.g. the literal "fold"
    // substituted for an empty label, or an arbitrary session id) is NOT proof
    // that the fold is recent, so it must not be allowed to bypass the over-share
    // guard — otherwise a tile carrying genuinely-old non-date folds would be
    // exported in full and double-counted on the next hub merge_tiles.
    let pre_anchor = tile
        .provenance
        .folds
        .iter()
        .any(|f| !(looks_dated(&f.label) && iso_is_after(&f.label, &args.since_iso)));
    if pre_anchor {
        return Err(format!(
            "tile {} has folds that are not provably after {} (older or undatable labels): a \
             pixel-exact delta cannot be carved from the merged accumulator (export each night's \
             delta at fold time)",
            args.tile_id, args.since_iso
        ));
    }

    let frames_in_delta = tile.provenance.total_frames;
    let integration_seconds = tile.provenance.total_integration_seconds;
    let path = Path::new(&args.out_path);
    ensure_parent_dir(path)?;
    std::fs::write(path, tile.serialize()).map_err(|e| format!("failed to write delta: {e}"))?;
    Ok(ExportDeltaResult {
        ok: true,
        out_path: args.out_path,
        frames_in_delta,
        integration_seconds,
    })
}

/// True if a fold label looks like an ISO date (so it participates in `sinceIso`
/// gating). Free-form labels are excluded from the gate (they neither block nor
/// qualify), mirroring [`iso_is_after`]'s treatment.
fn looks_dated(label: &str) -> bool {
    let l = label.trim();
    l.len() >= 7 && l.as_bytes().get(4) == Some(&b'-') && l[..4].chars().all(|c| c.is_ascii_digit())
}

// --- action "info" --------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct InfoArgs {
    atlas_root: String,
    #[serde(default = "default_order")]
    order: u32,
    tile_id: TileId,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct InfoResult {
    ok: bool,
    provenance: TileProvenance,
    center_ra: f64,
    center_dec: f64,
    channels: u32,
    coverage_mean: f64,
}

fn info_impl(args: InfoArgs) -> Result<InfoResult, String> {
    let atlas = open_atlas(&args.atlas_root, args.order)?;
    let tile = atlas
        .load_tile(args.tile_id)
        .map_err(|e| describe_atlas_error(&e))?
        .ok_or_else(|| format!("tile {} has not been folded into yet", args.tile_id))?;
    let (center_ra, center_dec) = tile_center(args.tile_id, args.order);
    Ok(InfoResult {
        ok: true,
        provenance: tile.provenance.clone(),
        center_ra,
        center_dec,
        channels: tile.channels,
        coverage_mean: tile.coverage_mean(),
    })
}

// =============================================================================
// Named convenience wrappers (the task-brief surface)
// =============================================================================

/// Fold a single plate-solved capture into the atlas. A thin convenience over the
/// `"fold"` action for the common one-frame case — the same JSON shape minus the
/// `frames` array wrapper:
///
/// ```jsonc
/// { "atlasRoot": "/…", "order": 9, "contributor": "", "interp": "lanczos3",
///   "label": "2026-06-19", "framePath": "/…/light_001.fits",
///   "weight": 1.0, "exposureSec": 300.0, "wcs": <SipWcs JSON>,
///   "onlineClipLow": 4.0, "onlineClipHigh": 4.0 /* optional */ }
/// ```
/// Returns the same [`FoldResult`] JSON as the dispatcher's `"fold"` action.
pub fn api_sky_atlas_add_frame(args_json: String) -> Result<String, String> {
    let one: AddFrameArgs =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid addFrame args: {e}"))?;
    let fold = FoldArgs {
        atlas_root: one.atlas_root,
        order: one.order,
        contributor: one.contributor,
        interp: one.interp,
        label: one.label,
        online_clip_low: one.online_clip_low,
        online_clip_high: one.online_clip_high,
        frames: vec![FoldFrameArgs {
            frame_path: one.frame_path,
            weight: one.weight,
            exposure_sec: one.exposure_sec,
            wcs: one.wcs,
        }],
    };
    let result = fold_impl(fold)?;
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct AddFrameArgs {
    atlas_root: String,
    #[serde(default = "default_order")]
    order: u32,
    #[serde(default)]
    contributor: String,
    #[serde(default)]
    interp: String,
    #[serde(default)]
    label: String,
    #[serde(default)]
    online_clip_low: Option<f64>,
    #[serde(default)]
    online_clip_high: Option<f64>,
    frame_path: String,
    #[serde(default = "default_weight")]
    weight: f64,
    #[serde(default)]
    exposure_sec: f64,
    wcs: SipWcs,
}

/// Co-add a cone of the atlas into a finalized, sharable cutout (FITS + optional
/// PNG) and report its statistics:
///
/// ```jsonc
/// { "atlasRoot": "/…", "order": 9,
///   "centerRa": 83.6, "centerDec": -5.4, "radiusDeg": 0.5,
///   "channels": 1, "outPixels": 2048, "interp": "lanczos3",
///   "fitsPath": "/…/cutout.fits", "pngPath": "/…/cutout.png" /* optional */ }
/// // -> { "ok": true, "fitsPath": "…", "pngPath": "…", "width": …, "height": …,
/// //      "channels": …, "coveredFraction": 0.97, "meanCoverage": 11.3,
/// //      "maxCoverage": 30.0, "tilesUsed": 7 }
/// ```
pub fn api_sky_atlas_query_cutout(args_json: String) -> Result<String, String> {
    let args: QueryCutoutArgs =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid queryCutout args: {e}"))?;
    let result = query_cutout_impl(args)?;
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct QueryCutoutArgs {
    atlas_root: String,
    #[serde(default = "default_order")]
    order: u32,
    center_ra: f64,
    center_dec: f64,
    radius_deg: f64,
    #[serde(default = "default_channels")]
    channels: u32,
    #[serde(default = "default_out_pixels")]
    out_pixels: u32,
    #[serde(default)]
    interp: String,
    /// Output FITS path for the co-added `F32` cutout (required).
    fits_path: String,
    /// Optional stretched preview PNG path.
    #[serde(default)]
    png_path: Option<String>,
}

fn default_channels() -> u32 {
    1
}

fn default_out_pixels() -> u32 {
    2048
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct QueryCutoutResult {
    ok: bool,
    fits_path: String,
    png_path: Option<String>,
    width: u32,
    height: u32,
    channels: u32,
    /// Fraction of output pixels with any coverage.
    covered_fraction: f64,
    /// Mean coverage depth over covered pixels.
    mean_coverage: f64,
    /// Maximum coverage depth seen.
    max_coverage: f64,
    /// Number of tiles that contributed to the cutout.
    tiles_used: usize,
}

fn query_cutout_impl(args: QueryCutoutArgs) -> Result<QueryCutoutResult, String> {
    if args.fits_path.trim().is_empty() {
        return Err("queryCutout requires fitsPath".to_string());
    }
    if args.radius_deg <= 0.0 {
        return Err("queryCutout requires a positive radiusDeg".to_string());
    }
    let atlas = open_atlas(&args.atlas_root, args.order)?;
    let interp = parse_interp(&args.interp)?;

    let (cutout, coverage) = atlas
        .query_cone(
            args.center_ra,
            args.center_dec,
            args.radius_deg,
            args.channels,
            args.out_pixels,
            interp,
        )
        .map_err(|e| describe_atlas_error(&e))?;

    // Coverage statistics over the output grid.
    let cov = coverage
        .as_f32()
        .ok_or_else(|| "coverage map is not F32".to_string())?;
    let mut covered = 0usize;
    let mut sum_cov = 0.0f64;
    let mut max_cov = 0.0f64;
    for &c in &cov {
        if c > 0.0 {
            covered += 1;
            sum_cov += c as f64;
            if (c as f64) > max_cov {
                max_cov = c as f64;
            }
        }
    }
    let covered_fraction = if cov.is_empty() {
        0.0
    } else {
        covered as f64 / cov.len() as f64
    };
    let mean_coverage = if covered > 0 {
        sum_cov / covered as f64
    } else {
        0.0
    };

    // Build the cutout's output WCS for the FITS header (same TAN grid the query
    // co-adds onto: centred on the cone, spanning 2·radius + margin).
    let out_w = args.out_pixels.max(1) as f64;
    let span_deg = 2.0 * args.radius_deg * 1.08;
    let scale_deg = span_deg / out_w;
    let crpix = out_w / 2.0 + 0.5;
    let out_wcs = WcsInfo {
        crval1: args.center_ra,
        crval2: args.center_dec,
        crpix1: crpix,
        crpix2: crpix,
        cd1_1: -scale_deg,
        cd1_2: 0.0,
        cd2_1: 0.0,
        cd2_2: scale_deg,
    };

    let path = Path::new(&args.fits_path);
    ensure_parent_dir(path)?;
    let mut header = FitsHeader::new();
    header.set_string("IMAGETYP", "MASTER_LIGHT");
    header.set_string("CALSTAT", "Nightshade sky-atlas cutout");
    add_wcs_headers(&mut header, &out_wcs);
    header.add_history(&format!(
        "Sky-atlas cone cutout: RA {:.4} Dec {:.4} radius {:.4}deg, mean coverage {:.2}",
        args.center_ra, args.center_dec, args.radius_deg, mean_coverage
    ));
    write_fits(path, &cutout, &header)
        .map_err(|e| format!("failed to write cutout FITS: {e:?}"))?;

    let png_path = match args.png_path.as_ref() {
        Some(p) if !p.trim().is_empty() => {
            let pp = Path::new(p);
            ensure_parent_dir(pp)?;
            write_preview_png(&cutout, pp)?;
            Some(p.clone())
        }
        _ => None,
    };

    // Tile count that intersected the cone (the same enumeration the query used).
    let tiles_used = nightshade_imaging::sky_atlas::tile_ids_for_cone(
        args.center_ra,
        args.center_dec,
        args.radius_deg,
        args.order,
    )
    .into_iter()
    .filter(|&tid| {
        atlas
            .load_tile(tid)
            .ok()
            .flatten()
            .is_some_and(|t| t.coverage_mean() > 0.0)
    })
    .count();

    Ok(QueryCutoutResult {
        ok: true,
        fits_path: args.fits_path,
        png_path,
        width: cutout.width,
        height: cutout.height,
        channels: cutout.channels,
        covered_fraction,
        mean_coverage,
        max_coverage: max_cov,
        tiles_used,
    })
}

/// Summarise a circular region of the atlas (the tiles a cone covers): aggregate
/// integration time, frame count, coverage depth, and tile tally — the numbers a
/// "Your Sky" region card shows.
///
/// ```jsonc
/// { "atlasRoot": "/…", "order": 9,
///   "centerRa": 83.6, "centerDec": -5.4, "radiusDeg": 0.5 }
/// // -> { "ok": true, "tilesInRegion": 7, "tilesWithData": 5,
/// //      "totalFrames": 120, "integrationSeconds": 36000.0,
/// //      "meanCoverage": 11.3, "maxCoverage": 30.0,
/// //      "contributors": ["", "alice"], "lastFoldIso": "2026-06-19" }
/// ```
pub fn api_sky_atlas_region_info(args_json: String) -> Result<String, String> {
    let args: RegionInfoArgs =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid regionInfo args: {e}"))?;
    let result = region_info_impl(args)?;
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct RegionInfoArgs {
    atlas_root: String,
    #[serde(default = "default_order")]
    order: u32,
    center_ra: f64,
    center_dec: f64,
    radius_deg: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct RegionInfoResult {
    ok: bool,
    tiles_in_region: usize,
    tiles_with_data: usize,
    total_frames: usize,
    integration_seconds: f64,
    mean_coverage: f64,
    max_coverage: f64,
    contributors: Vec<String>,
    last_fold_iso: Option<String>,
}

fn region_info_impl(args: RegionInfoArgs) -> Result<RegionInfoResult, String> {
    if args.radius_deg < 0.0 {
        return Err("regionInfo requires a non-negative radiusDeg".to_string());
    }
    let atlas = open_atlas(&args.atlas_root, args.order)?;
    let ids = nightshade_imaging::sky_atlas::tile_ids_for_cone(
        args.center_ra,
        args.center_dec,
        args.radius_deg,
        args.order,
    );
    let tiles_in_region = ids.len();
    let mut tiles_with_data = 0usize;
    let mut total_frames = 0usize;
    let mut integration_seconds = 0.0f64;
    let mut sum_cov = 0.0f64;
    let mut max_cov = 0.0f64;
    let mut contributors: Vec<String> = Vec::new();
    let mut last_fold: Option<String> = None;
    for tid in ids {
        let Some(tile) = atlas.load_tile(tid).map_err(|e| describe_atlas_error(&e))? else {
            continue;
        };
        let cov = tile.coverage_mean();
        if cov <= 0.0 && tile.provenance.total_frames == 0 {
            continue;
        }
        tiles_with_data += 1;
        total_frames += tile.provenance.total_frames;
        integration_seconds += tile.provenance.total_integration_seconds;
        sum_cov += cov;
        if cov > max_cov {
            max_cov = cov;
        }
        for c in &tile.provenance.contributors {
            if !contributors.iter().any(|e| e == c) {
                contributors.push(c.clone());
            }
        }
        if let Some(f) = tile.provenance.folds.last() {
            if looks_dated(&f.label) {
                last_fold = match last_fold {
                    Some(prev) if prev >= f.label => Some(prev),
                    _ => Some(f.label.clone()),
                };
            }
        }
    }
    let mean_coverage = if tiles_with_data > 0 {
        sum_cov / tiles_with_data as f64
    } else {
        0.0
    };
    Ok(RegionInfoResult {
        ok: true,
        tiles_in_region,
        tiles_with_data,
        total_frames,
        integration_seconds,
        mean_coverage,
        max_coverage: max_cov,
        contributors,
        last_fold_iso: last_fold,
    })
}

/// Report a deepening **growth curve** for a region: per-fold cumulative frame
/// count and integration time, oldest fold first, summed across the region's
/// tiles. This is the "your sky is getting deeper" timeline the dashboard plots.
///
/// ```jsonc
/// { "atlasRoot": "/…", "order": 9,
///   "centerRa": 83.6, "centerDec": -5.4, "radiusDeg": 0.5 }
/// // -> { "ok": true, "points": [
/// //        { "label": "2026-06-01", "framesAdded": 30, "secondsAdded": 9000.0,
/// //          "cumulativeFrames": 30, "cumulativeSeconds": 9000.0,
/// //          "contributor": "" }, … ],
/// //      "totalFrames": 120, "totalSeconds": 36000.0 }
/// ```
pub fn api_sky_atlas_growth(args_json: String) -> Result<String, String> {
    let args: GrowthArgs =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid growth args: {e}"))?;
    let result = growth_impl(args)?;
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct GrowthArgs {
    atlas_root: String,
    #[serde(default = "default_order")]
    order: u32,
    center_ra: f64,
    center_dec: f64,
    radius_deg: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct GrowthPoint {
    /// Fold label (ISO date / session id).
    label: String,
    frames_added: usize,
    seconds_added: f64,
    cumulative_frames: usize,
    cumulative_seconds: f64,
    contributor: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct GrowthResult {
    ok: bool,
    points: Vec<GrowthPoint>,
    total_frames: usize,
    total_seconds: f64,
}

fn growth_impl(args: GrowthArgs) -> Result<GrowthResult, String> {
    if args.radius_deg < 0.0 {
        return Err("growth requires a non-negative radiusDeg".to_string());
    }
    let atlas = open_atlas(&args.atlas_root, args.order)?;
    let ids = nightshade_imaging::sky_atlas::tile_ids_for_cone(
        args.center_ra,
        args.center_dec,
        args.radius_deg,
        args.order,
    );

    // Gather every fold across the region's tiles, keyed by label so folds of the
    // same night (across many tiles) collapse into one growth point. A retraction
    // (negative weight_added, "retract:" label) subtracts from its night's tally.
    use std::collections::BTreeMap;
    #[derive(Default)]
    struct Bucket {
        frames: usize,
        seconds: f64,
        contributor: String,
    }
    // Preserve first-seen order while merging same-label folds: index map.
    let mut order_of: BTreeMap<String, usize> = BTreeMap::new();
    let mut buckets: Vec<(String, Bucket)> = Vec::new();

    for tid in ids {
        let Some(tile) = atlas.load_tile(tid).map_err(|e| describe_atlas_error(&e))? else {
            continue;
        };
        for fold in &tile.provenance.folds {
            // Retractions carry a "retract:" label prefix + a negative
            // weight_added; honour them by subtracting from the original night.
            let (key, sign) = if let Some(stripped) = fold.label.strip_prefix("retract:") {
                (stripped.to_string(), -1.0)
            } else {
                (fold.label.clone(), 1.0)
            };
            let idx = *order_of.entry(key.clone()).or_insert_with(|| {
                buckets.push((
                    key.clone(),
                    Bucket {
                        contributor: fold.contributor.clone(),
                        ..Bucket::default()
                    },
                ));
                buckets.len() - 1
            });
            let b = &mut buckets[idx].1;
            if sign > 0.0 {
                b.frames += fold.frames_added;
                b.seconds += fold.integration_seconds_added;
            } else {
                b.frames = b.frames.saturating_sub(fold.frames_added);
                b.seconds = (b.seconds - fold.integration_seconds_added.abs()).max(0.0);
            }
        }
    }

    // Sort growth points by label (ISO dates sort chronologically; non-dated
    // labels sort lexicographically after, which keeps the cumulative curve
    // monotonic for the common dated case).
    buckets.sort_by(|a, b| a.0.cmp(&b.0));

    let mut points = Vec::with_capacity(buckets.len());
    let mut cum_frames = 0usize;
    let mut cum_seconds = 0.0f64;
    for (label, b) in buckets {
        cum_frames += b.frames;
        cum_seconds += b.seconds;
        points.push(GrowthPoint {
            label,
            frames_added: b.frames,
            seconds_added: b.seconds,
            cumulative_frames: cum_frames,
            cumulative_seconds: cum_seconds,
            contributor: b.contributor,
        });
    }

    Ok(GrowthResult {
        ok: true,
        total_frames: cum_frames,
        total_seconds: cum_seconds,
        points,
    })
}

// =============================================================================
// Federation merge helper (contracts §2.3 — exposed here so the atlas surface is
// self-contained for the hub/local merge the keystone's additivity enables).
// =============================================================================

/// Merge a contributor delta accumulator into a base accumulator (or retract it),
/// the linear-additive federation operation the keystone proves exact:
///
/// ```jsonc
/// { "basePath": "/…/hub/tiles/9/42.nst", "deltaPath": "/…/delta_42.nst",
///   "trust": 0.85, "subtract": false, "outPath": "/…/hub/tiles/9/42.nst" }
/// // -> { "ok": true, "tileId": 42, "totalFramesAfter": 130,
/// //      "integrationSecondsAfter": 39000.0, "contributorsAfter": 7 }
/// ```
pub fn api_sky_atlas_merge_delta(args_json: String) -> Result<String, String> {
    let args: MergeDeltaArgs =
        serde_json::from_str(&args_json).map_err(|e| format!("invalid mergeDelta args: {e}"))?;
    let result = merge_delta_impl(args)?;
    serde_json::to_string(&result).map_err(|e| format!("failed to encode result: {e}"))
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct MergeDeltaArgs {
    base_path: String,
    delta_path: String,
    #[serde(default = "default_trust")]
    trust: f64,
    #[serde(default)]
    subtract: bool,
    out_path: String,
}

fn default_trust() -> f64 {
    1.0
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
struct MergeDeltaResult {
    ok: bool,
    tile_id: TileId,
    total_frames_after: usize,
    integration_seconds_after: f64,
    contributors_after: usize,
}

fn merge_delta_impl(args: MergeDeltaArgs) -> Result<MergeDeltaResult, String> {
    if args.base_path.trim().is_empty() || args.delta_path.trim().is_empty() {
        return Err("mergeDelta requires basePath and deltaPath".to_string());
    }
    if args.out_path.trim().is_empty() {
        return Err("mergeDelta requires outPath".to_string());
    }
    let trust = args.trust.clamp(0.0, 1.0);

    let delta_bytes =
        std::fs::read(&args.delta_path).map_err(|e| format!("failed to read delta: {e}"))?;
    let delta = SkyTileAccumulator::deserialize(&delta_bytes)
        .map_err(|e| format!("corrupt delta: {}", describe_atlas_error(&e)))?;

    // A base that does not exist yet starts from a fresh zeroed accumulator of the
    // delta's geometry, so the first contributor merge into a new hub tile works.
    let mut base = match std::fs::read(&args.base_path) {
        Ok(bytes) => SkyTileAccumulator::deserialize(&bytes)
            .map_err(|e| format!("corrupt base: {}", describe_atlas_error(&e)))?,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            SkyTileAccumulator::create(delta.tile_id, delta.order, delta.channels, delta.mode)
        }
        Err(e) => return Err(format!("failed to read base: {e}")),
    };

    if args.subtract {
        merge_tiles_subtract(&mut base, &delta, trust).map_err(|e| describe_atlas_error(&e))?;
    } else {
        merge_tiles(&mut base, &delta, trust).map_err(|e| describe_atlas_error(&e))?;
    }

    let out = Path::new(&args.out_path);
    ensure_parent_dir(out)?;
    std::fs::write(out, base.serialize())
        .map_err(|e| format!("failed to write merged base: {e}"))?;

    Ok(MergeDeltaResult {
        ok: true,
        tile_id: base.tile_id,
        total_frames_after: base.provenance.total_frames,
        integration_seconds_after: base.provenance.total_integration_seconds,
        contributors_after: base.provenance.contributors.len(),
    })
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use nightshade_imaging::sky_atlas::{radec_to_tile, tile_wcs, TILE_PIXELS};
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp_dir(tag: &str) -> std::path::PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let p =
            std::env::temp_dir().join(format!("ns_atlas_ffi_{}_{}_{}", tag, std::process::id(), n));
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    fn temp_file(dir: &Path, name: &str) -> std::path::PathBuf {
        dir.join(name)
    }

    /// Write a flat F32 frame whose WCS is a tile's own grid (so it covers the
    /// tile pixel-for-pixel) to a FITS file, returning (path, wcs).
    fn write_frame_on_tile(
        dir: &Path,
        name: &str,
        tile_id: TileId,
        order: u32,
        value: f32,
    ) -> (std::path::PathBuf, SipWcs) {
        let wcs = tile_wcs(tile_id, order);
        let w = TILE_PIXELS;
        let data = vec![value; (w as usize) * (w as usize)];
        let image = ImageData::from_f32(w, w, 1, &data);
        let mut header = FitsHeader::new();
        header.set_string("IMAGETYP", "LIGHT");
        let path = temp_file(dir, name);
        write_fits(&path, &image, &header).unwrap();
        (path, wcs)
    }

    fn sip_to_json(wcs: &SipWcs) -> serde_json::Value {
        serde_json::to_value(wcs).unwrap()
    }

    #[test]
    fn fold_then_coverage_then_finalize() {
        let dir = temp_dir("fold");
        let order = ATLAS_HEALPIX_ORDER;
        let tid = radec_to_tile(120.0, 25.0, order);
        let (frame, wcs) = write_frame_on_tile(&dir, "light.fits", tid, order, 1000.0);

        // Fold via the dispatcher.
        let fold_args = serde_json::json!({
            "action": "fold",
            "atlasRoot": dir.to_string_lossy(),
            "order": order,
            "contributor": "",
            "interp": "bilinear",
            "label": "2026-06-19",
            "frames": [ { "framePath": frame.to_string_lossy(),
                          "weight": 1.0, "exposureSec": 300.0, "wcs": sip_to_json(&wcs) } ]
        })
        .to_string();
        let resp = api_sky_atlas(fold_args).expect("fold succeeds");
        let fold: FoldResult = serde_json::from_str(&resp).unwrap();
        assert!(fold.ok);
        assert!(fold.tiles_touched.contains(&tid));
        let summary = fold
            .folds_by_tile
            .iter()
            .find(|s| s.tile_id == tid)
            .expect("centre tile summarised");
        assert_eq!(summary.frames_added, 1);
        assert!(summary.coverage_mean > 0.5);

        // Coverage lists the tile.
        let cov_args = serde_json::json!({
            "action": "coverage", "atlasRoot": dir.to_string_lossy(), "order": order
        })
        .to_string();
        let cov: CoverageResult = serde_json::from_str(&api_sky_atlas(cov_args).unwrap()).unwrap();
        assert!(cov.tiles.iter().any(|t| t.tile_id == tid));

        // Finalize writes a FITS that recovers ~1000 at the centre.
        let out = temp_file(&dir, "tile.fits");
        let fin_args = serde_json::json!({
            "action": "finalize", "atlasRoot": dir.to_string_lossy(), "order": order,
            "tileId": tid, "outPath": out.to_string_lossy()
        })
        .to_string();
        let fin: FinalizeResult = serde_json::from_str(&api_sky_atlas(fin_args).unwrap()).unwrap();
        assert!(fin.ok);
        assert!(out.exists());
        let (img, hdr) = nightshade_imaging::read_fits(&out).unwrap();
        assert_eq!(img.pixel_type, nightshade_imaging::PixelType::F32);
        assert_eq!(hdr.get_int("TILEID"), Some(tid as i64));
        let f = img.as_f32().unwrap();
        let mid = (TILE_PIXELS as usize / 2) * (TILE_PIXELS as usize) + TILE_PIXELS as usize / 2;
        assert!((f[mid] as f64 - 1000.0).abs() < 1.0, "got {}", f[mid]);

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn add_frame_wrapper_matches_fold() {
        let dir = temp_dir("addframe");
        let order = ATLAS_HEALPIX_ORDER;
        let tid = radec_to_tile(45.0, -10.0, order);
        let (frame, wcs) = write_frame_on_tile(&dir, "light.fits", tid, order, 555.0);

        let args = serde_json::json!({
            "atlasRoot": dir.to_string_lossy(), "order": order, "label": "2026-06-19",
            "framePath": frame.to_string_lossy(), "weight": 1.0, "exposureSec": 120.0,
            "wcs": sip_to_json(&wcs)
        })
        .to_string();
        let fold: FoldResult =
            serde_json::from_str(&api_sky_atlas_add_frame(args).unwrap()).unwrap();
        assert!(fold.ok);
        assert!(fold.tiles_touched.contains(&tid));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn query_cutout_recovers_signal_and_coverage() {
        let dir = temp_dir("cutout");
        let order = ATLAS_HEALPIX_ORDER;
        let (ra, dec) = (200.0, 15.0);
        let tid = radec_to_tile(ra, dec, order);
        let (frame, wcs) = write_frame_on_tile(&dir, "light.fits", tid, order, 1234.0);
        let add = serde_json::json!({
            "atlasRoot": dir.to_string_lossy(), "order": order, "label": "2026-06-19",
            "framePath": frame.to_string_lossy(), "weight": 1.0, "exposureSec": 60.0,
            "wcs": sip_to_json(&wcs)
        })
        .to_string();
        api_sky_atlas_add_frame(add).unwrap();

        let out = temp_file(&dir, "cutout.fits");
        let png = temp_file(&dir, "cutout.png");
        let q = serde_json::json!({
            "atlasRoot": dir.to_string_lossy(), "order": order,
            "centerRa": ra, "centerDec": dec, "radiusDeg": 0.05,
            "channels": 1, "outPixels": 256, "interp": "bilinear",
            "fitsPath": out.to_string_lossy(), "pngPath": png.to_string_lossy()
        })
        .to_string();
        let res: QueryCutoutResult =
            serde_json::from_str(&api_sky_atlas_query_cutout(q).unwrap()).unwrap();
        assert!(res.ok);
        assert!(out.exists());
        assert!(png.exists());
        assert!(res.covered_fraction > 0.5, "frac {}", res.covered_fraction);
        assert!(res.mean_coverage > 0.0);
        assert!(res.tiles_used >= 1);
        // The co-added centre should recover ~1234.
        let (img, _) = nightshade_imaging::read_fits(&out).unwrap();
        let f = img.as_f32().unwrap();
        let w = img.width as usize;
        let mid = (img.height as usize / 2) * w + w / 2;
        assert!((f[mid] as f64 - 1234.0).abs() < 5.0, "got {}", f[mid]);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn region_info_and_growth_track_folds() {
        let dir = temp_dir("region");
        let order = ATLAS_HEALPIX_ORDER;
        let (ra, dec) = (300.0, -25.0);
        let tid = radec_to_tile(ra, dec, order);

        // Two nights into the same tile.
        for (i, (val, secs, night)) in [
            (800.0f32, 300.0, "2026-06-01"),
            (1200.0f32, 600.0, "2026-06-05"),
        ]
        .iter()
        .enumerate()
        {
            let (frame, wcs) = write_frame_on_tile(&dir, &format!("n{i}.fits"), tid, order, *val);
            let add = serde_json::json!({
                "atlasRoot": dir.to_string_lossy(), "order": order, "label": night,
                "framePath": frame.to_string_lossy(), "weight": 1.0, "exposureSec": secs,
                "wcs": sip_to_json(&wcs)
            })
            .to_string();
            api_sky_atlas_add_frame(add).unwrap();
        }

        let ri = serde_json::json!({
            "atlasRoot": dir.to_string_lossy(), "order": order,
            "centerRa": ra, "centerDec": dec, "radiusDeg": 0.02
        })
        .to_string();
        let region: RegionInfoResult =
            serde_json::from_str(&api_sky_atlas_region_info(ri).unwrap()).unwrap();
        assert!(region.ok);
        assert!(region.tiles_with_data >= 1);
        // A frame folds into every tile its (margin-padded) footprint covers, so a
        // region aggregate sums per-tile contributions: both nights touched each
        // data tile identically (same WCS), giving 2 contributions per data tile.
        assert_eq!(region.total_frames, 2 * region.tiles_with_data);
        // Integration seconds aggregate the same way: (300 + 600) per data tile.
        assert!(
            (region.integration_seconds - 900.0 * region.tiles_with_data as f64).abs() < 1e-6,
            "got {}",
            region.integration_seconds
        );

        let g = serde_json::json!({
            "atlasRoot": dir.to_string_lossy(), "order": order,
            "centerRa": ra, "centerDec": dec, "radiusDeg": 0.02
        })
        .to_string();
        let growth: GrowthResult = serde_json::from_str(&api_sky_atlas_growth(g).unwrap()).unwrap();
        assert!(growth.ok);
        // Growth sums the same per-tile fold tallies as region_info.
        assert_eq!(growth.total_frames, region.total_frames);
        assert!((growth.total_seconds - region.integration_seconds).abs() < 1e-6);
        // Two growth points (keyed by night label), chronological, with a
        // monotonic cumulative curve. Each night contributed once per data tile.
        assert_eq!(growth.points.len(), 2);
        assert_eq!(growth.points[0].label, "2026-06-01");
        assert_eq!(growth.points[1].label, "2026-06-05");
        assert_eq!(growth.points[0].frames_added, region.tiles_with_data);
        assert_eq!(growth.points[0].cumulative_frames, region.tiles_with_data);
        assert_eq!(
            growth.points[1].cumulative_frames,
            2 * region.tiles_with_data
        );
        assert!(growth.points[1].cumulative_seconds > growth.points[0].cumulative_seconds);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn merge_delta_federates_two_contributors() {
        let dir = temp_dir("merge");
        let order = ATLAS_HEALPIX_ORDER;
        let (ra, dec) = (88.0, 5.0);
        let tid = radec_to_tile(ra, dec, order);

        // Alice folds into atlas A; export her tile as a delta.
        let (fa, wa) = write_frame_on_tile(&dir, "alice.fits", tid, order, 1000.0);
        let add_a = serde_json::json!({
            "atlasRoot": dir.join("alice").to_string_lossy(), "order": order, "label": "2026-06-01",
            "contributor": "alice", "framePath": fa.to_string_lossy(),
            "weight": 1.0, "exposureSec": 100.0, "wcs": sip_to_json(&wa)
        })
        .to_string();
        api_sky_atlas_add_frame(add_a).unwrap();

        let alice_atlas = SkyAtlas::open(dir.join("alice"), order, DEFAULT_MEMORY_BUDGET_BYTES);
        let alice_tile_path = alice_atlas.tile_path(tid);
        assert!(alice_tile_path.exists());

        // Bob's hub is empty; merge Alice's delta into it.
        let hub = SkyAtlas::open(dir.join("hub"), order, DEFAULT_MEMORY_BUDGET_BYTES);
        let hub_path = hub.tile_path(tid);
        let merge = serde_json::json!({
            "basePath": hub_path.to_string_lossy(),
            "deltaPath": alice_tile_path.to_string_lossy(),
            "trust": 1.0, "subtract": false,
            "outPath": hub_path.to_string_lossy()
        })
        .to_string();
        let res: MergeDeltaResult =
            serde_json::from_str(&api_sky_atlas_merge_delta(merge).unwrap()).unwrap();
        assert!(res.ok);
        assert_eq!(res.tile_id, tid);
        assert_eq!(res.total_frames_after, 1);
        assert!((res.integration_seconds_after - 100.0).abs() < 1e-6);
        assert_eq!(res.contributors_after, 1);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn export_delta_blocks_undatable_fold_labels() {
        // A fold with a non-date label (here the empty-label default "fold") must
        // be treated as pre-anchor and BLOCK a whole-tile export, so an old or
        // undatable fold can never be re-shared in full and double-counted.
        let dir = temp_dir("export_undated");
        let order = ATLAS_HEALPIX_ORDER;
        let tid = radec_to_tile(120.0, 25.0, order);
        let (frame, wcs) = write_frame_on_tile(&dir, "u.fits", tid, order, 1000.0);
        // Fold with an empty label -> the bridge substitutes the literal "fold".
        let add = serde_json::json!({
            "atlasRoot": dir.to_string_lossy(), "order": order, "label": "",
            "contributor": "me", "framePath": frame.to_string_lossy(),
            "weight": 1.0, "exposureSec": 100.0, "wcs": sip_to_json(&wcs)
        })
        .to_string();
        api_sky_atlas_add_frame(add).unwrap();

        let out = dir.join("delta.nst");
        let export = serde_json::json!({
            "action": "exportDelta",
            "atlasRoot": dir.to_string_lossy(), "order": order,
            "tileId": tid, "sinceIso": "2026-06-01",
            "outPath": out.to_string_lossy()
        })
        .to_string();
        let err = api_sky_atlas(export).unwrap_err();
        assert!(
            err.contains("not provably after"),
            "undatable fold must block whole-tile export, got: {err}"
        );
        assert!(!out.exists(), "no delta must be written when blocked");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn export_delta_allows_all_post_anchor_dated_folds() {
        let dir = temp_dir("export_dated");
        let order = ATLAS_HEALPIX_ORDER;
        let tid = radec_to_tile(120.0, 25.0, order);
        let (frame, wcs) = write_frame_on_tile(&dir, "d.fits", tid, order, 1000.0);
        let add = serde_json::json!({
            "atlasRoot": dir.to_string_lossy(), "order": order, "label": "2026-06-10",
            "contributor": "me", "framePath": frame.to_string_lossy(),
            "weight": 1.0, "exposureSec": 100.0, "wcs": sip_to_json(&wcs)
        })
        .to_string();
        api_sky_atlas_add_frame(add).unwrap();

        let out = dir.join("delta.nst");
        let export = serde_json::json!({
            "action": "exportDelta",
            "atlasRoot": dir.to_string_lossy(), "order": order,
            "tileId": tid, "sinceIso": "2026-06-01",
            "outPath": out.to_string_lossy()
        })
        .to_string();
        let res = api_sky_atlas(export).unwrap();
        assert!(res.contains("\"ok\":true"), "got: {res}");
        assert!(out.exists(), "a fully post-anchor tile must export");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn unknown_action_errors() {
        let args = serde_json::json!({ "action": "bogus", "atlasRoot": "/tmp/x" }).to_string();
        let err = api_sky_atlas(args).unwrap_err();
        assert!(err.contains("unknown atlas action"), "got: {err}");
    }

    #[test]
    fn fold_requires_invertible_wcs() {
        let dir = temp_dir("badwcs");
        let order = ATLAS_HEALPIX_ORDER;
        let tid = radec_to_tile(10.0, 10.0, order);
        let (frame, mut wcs) = write_frame_on_tile(&dir, "l.fits", tid, order, 1.0);
        // Zero the CD matrix -> singular.
        wcs.cd1_1 = 0.0;
        wcs.cd1_2 = 0.0;
        wcs.cd2_1 = 0.0;
        wcs.cd2_2 = 0.0;
        let args = serde_json::json!({
            "atlasRoot": dir.to_string_lossy(), "order": order,
            "framePath": frame.to_string_lossy(), "weight": 1.0, "wcs": sip_to_json(&wcs)
        })
        .to_string();
        let err = api_sky_atlas_add_frame(args).unwrap_err();
        assert!(err.contains("degenerate"), "got: {err}");
        std::fs::remove_dir_all(&dir).ok();
    }
}
