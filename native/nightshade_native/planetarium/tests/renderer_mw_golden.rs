//! Golden-image regression: Milky Way band at galactic-center boresight.

use std::path::PathBuf;

use image::RgbaImage;
use nightshade_planetarium::renderer::{
    count_mw_visible_pixels, render_mw_golden_rgba, MW_GOLDEN_SIZE,
};

const GOLDEN_RMSE_MAX: f64 = 0.008;

fn golden_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/golden/mw_galactic_center.png")
}

#[test]
fn mw_golden_frame_has_visible_band_smoke() {
    let rgba = render_mw_golden_rgba();
    let visible = count_mw_visible_pixels(&rgba, 8);
    assert!(
        visible > 500,
        "MW smoke: expected band pixels, got {visible}"
    );
}

#[test]
fn mw_galactic_center_match_golden_png_rmse() {
    let golden_path = golden_path();
    assert!(
        golden_path.is_file(),
        "missing golden image at {} — run generate_mw_golden once",
        golden_path.display()
    );

    let golden = image::open(&golden_path)
        .expect("open golden png")
        .to_rgba8();
    assert_eq!(
        golden.dimensions(),
        (MW_GOLDEN_SIZE, MW_GOLDEN_SIZE),
        "golden dimensions must match render target"
    );

    let rendered = render_mw_golden_rgba();
    assert_eq!(
        rendered.len(),
        (MW_GOLDEN_SIZE * MW_GOLDEN_SIZE * 4) as usize
    );

    let mut sum_sq = 0.0f64;
    let n = (MW_GOLDEN_SIZE * MW_GOLDEN_SIZE * 4) as f64;
    for (i, chunk) in rendered.chunks_exact(4).enumerate() {
        let g = golden.as_raw();
        let dr = f64::from(chunk[0]) / 255.0 - f64::from(g[i * 4]) / 255.0;
        let dg = f64::from(chunk[1]) / 255.0 - f64::from(g[i * 4 + 1]) / 255.0;
        let db = f64::from(chunk[2]) / 255.0 - f64::from(g[i * 4 + 2]) / 255.0;
        let da = f64::from(chunk[3]) / 255.0 - f64::from(g[i * 4 + 3]) / 255.0;
        sum_sq += dr * dr + dg * dg + db * db + da * da;
    }
    let rmse = (sum_sq / n).sqrt();
    assert!(
        rmse < GOLDEN_RMSE_MAX,
        "RMSE {rmse:.6} exceeds {GOLDEN_RMSE_MAX}; re-run generate_mw_golden if intentional"
    );
}

/// One-shot helper to write `tests/golden/mw_galactic_center.png` after visual review.
#[test]
#[ignore = "run manually: cargo test -p nightshade_planetarium generate_mw_golden -- --ignored"]
fn generate_mw_golden() {
    let pixels = render_mw_golden_rgba();
    let img =
        RgbaImage::from_raw(MW_GOLDEN_SIZE, MW_GOLDEN_SIZE, pixels).expect("rgba buffer size");
    let path = golden_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).expect("create golden dir");
    }
    img.save(&path).expect("save golden png");
    eprintln!("wrote {}", path.display());
}
