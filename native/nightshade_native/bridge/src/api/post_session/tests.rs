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
    let rejection_preview = image::open(&rejection_preview_path).expect("decode rejection preview");
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
