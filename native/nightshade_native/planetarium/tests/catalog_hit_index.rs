//! Hit-test index: cone pick for Polaris, Vega, Sirius (HIP ids).

use nightshade_planetarium::catalog::{HitIndex, StarRecord};

const POLARIS: (f64, f64, u32, f32) = (0.662_062, 1.557_896, 11767, 1.98);
const VEGA: (f64, f64, u32, f32) = (4.872_013, 0.676_757, 91262, 0.03);
const SIRIUS: (f64, f64, u32, f32) = (1.767_015, -0.291_808, 32349, -1.46);

fn star(ra: f64, dec: f64, mag: f32, hip: u32) -> StarRecord {
    let (sin_dec, cos_dec) = dec.sin_cos();
    let (sin_ra, cos_ra) = ra.sin_cos();
    StarRecord {
        hip_id: hip,
        flags: 0,
        icrs_dir: [
            (cos_dec * cos_ra) as f32,
            (cos_dec * sin_ra) as f32,
            sin_dec as f32,
        ],
        mag,
        bv: f32::NAN,
    }
}

fn bright_stars_index() -> HitIndex {
    let mut idx = HitIndex::new(8);
    for &(ra, dec, hip, mag) in &[POLARIS, VEGA, SIRIUS] {
        idx.insert_star(star(ra, dec, mag, hip))
            .expect("insert star");
    }
    assert_eq!(idx.star_count(), 3);
    idx
}

#[test]
fn pick_polaris_hip_11767() {
    let idx = bright_stars_index();
    let hit = idx
        .pick_near(POLARIS.0, POLARIS.1, 0.15, 6.0)
        .expect("query")
        .expect("polaris");
    assert_eq!(hit.star.hip_id, 11767);
}

#[test]
fn pick_vega_hip_91262() {
    let idx = bright_stars_index();
    let hit = idx
        .pick_near(VEGA.0, VEGA.1, 0.15, 6.0)
        .expect("query")
        .expect("vega");
    assert_eq!(hit.star.hip_id, 91262);
}

#[test]
fn pick_sirius_hip_32349() {
    let idx = bright_stars_index();
    let hit = idx
        .pick_near(SIRIUS.0, SIRIUS.1, 0.15, 6.0)
        .expect("query")
        .expect("sirius");
    assert_eq!(hit.star.hip_id, 32349);
}

#[test]
fn vega_boresight_does_not_pick_polaris() {
    let idx = bright_stars_index();
    let hit = idx
        .pick_near(VEGA.0, VEGA.1, 0.15, 6.0)
        .expect("query")
        .expect("hit");
    assert_ne!(hit.star.hip_id, 11767);
    assert_eq!(hit.star.hip_id, 91262);
}
