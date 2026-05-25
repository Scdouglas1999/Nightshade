//! Golden-image regression: three bright stars at 30° FOV.

use std::path::PathBuf;

use image::RgbaImage;
use nightshade_planetarium::renderer::{
    render_three_stars_rgba, three_star_instances, three_stars_view_pose, THREE_STARS_SIZE,
};
use nightshade_planetarium::scene::project_icrs;

const GOLDEN_RMSE_MAX: f64 = 0.005;

fn golden_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/golden/stars_three.png")
}

#[test]
fn three_stars_view_pose_projects_all_golden_instances() {
    let pose = three_stars_view_pose();
    for (i, inst) in three_star_instances().iter().enumerate() {
        let ra = f64::from(inst.icrs_dir[1].atan2(inst.icrs_dir[0]));
        let dec = f64::from(inst.icrs_dir[2].asin());
        let projected = project_icrs(ra, dec, pose);
        assert!(
            projected.is_some(),
            "golden star {i} must be inside 30° FOV at test boresight"
        );
    }
}

#[test]
fn three_stars_match_golden_png_rmse() {
    let golden_path = golden_path();
    assert!(
        golden_path.is_file(),
        "missing golden image at {} — run generate_stars_three_golden once",
        golden_path.display()
    );

    let golden = image::open(&golden_path)
        .expect("open golden png")
        .to_rgba8();
    assert_eq!(
        golden.dimensions(),
        (THREE_STARS_SIZE, THREE_STARS_SIZE),
        "golden dimensions must match render target"
    );

    let rendered = render_three_stars_rgba();
    assert_eq!(
        rendered.len(),
        (THREE_STARS_SIZE * THREE_STARS_SIZE * 4) as usize
    );

    let mut sum_sq = 0.0f64;
    let n = (THREE_STARS_SIZE * THREE_STARS_SIZE * 4) as f64;
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
        "RMSE {rmse:.6} exceeds {GOLDEN_RMSE_MAX}; re-run generate_stars_three_golden if intentional"
    );
}

/// One-shot helper to write `tests/golden/stars_three.png` after visual review.
#[test]
#[ignore = "run manually: cargo test -p nightshade_planetarium generate_stars_three_golden -- --ignored"]
fn generate_stars_three_golden() {
    let pixels = render_three_stars_rgba();
    let img =
        RgbaImage::from_raw(THREE_STARS_SIZE, THREE_STARS_SIZE, pixels).expect("rgba buffer size");
    let path = golden_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).expect("create golden dir");
    }
    img.save(&path).expect("save golden png");
    eprintln!("wrote {}", path.display());
}
