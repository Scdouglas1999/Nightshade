//! CatalogSet: active packs and pose + magnitude queries.

use std::collections::HashMap;

use nightshade_planetarium::catalog::{
    pixel_for_direction, CatalogHit, CatalogSet, StarPack, StarRecord,
};
use nightshade_planetarium::types::{SkyProjection, ViewPose};

struct FakePack {
    id: &'static str,
    nside: u32,
    tiles: HashMap<u64, Vec<StarRecord>>,
}

impl FakePack {
    fn with_stars(id: &'static str, nside: u32, stars: &[(&str, f64, f64, f32, u32)]) -> Self {
        let mut tiles: HashMap<u64, Vec<StarRecord>> = HashMap::new();
        for &(name, ra, dec, mag, hip) in stars {
            let pixel = pixel_for_direction(ra, dec, nside).expect(name);
            tiles.entry(pixel).or_default().push(StarRecord::from_radec(
                hip,
                ra as f32,
                dec as f32,
                mag,
                f32::NAN,
                0,
            ));
        }
        Self { id, nside, tiles }
    }
}

impl StarPack for FakePack {
    fn pack_id(&self) -> &str {
        self.id
    }

    fn nside(&self) -> u32 {
        self.nside
    }

    fn stars_in_pixel(&self, healpix_id: u64) -> Option<&[StarRecord]> {
        self.tiles.get(&healpix_id).map(Vec::as_slice)
    }
}

fn vega_pose() -> ViewPose {
    ViewPose {
        ra_rad: 4.872_013,
        dec_rad: 0.676_757,
        fov_rad: 0.35,
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    }
}

#[test]
fn register_fake_pack_query_returns_visible_star() {
    let vega = ("vega", 4.872_013, 0.676_757, 0.03_f32, 91262_u32);
    let polaris = ("polaris", 0.662_062, 1.557_896, 1.98_f32, 11767_u32);
    let pack = FakePack::with_stars("fake-stars", 64, &[vega, polaris]);

    let mut set = CatalogSet::new();
    set.register(Box::new(pack));

    assert_eq!(set.active_pack_ids().collect::<Vec<_>>(), vec!["fake-stars"]);

    let hits: Vec<CatalogHit<'_>> = set
        .query(vega_pose(), 6.0)
        .expect("query")
        .collect();

    let hips: Vec<u32> = hits.iter().map(|h| h.star.hip_id).collect();
    assert!(hips.contains(&91262), "Vega must be visible at Vega boresight");
    assert!(!hips.contains(&11767), "Polaris must be outside this FOV");
}

#[test]
fn magnitude_limit_filters_faint_stars() {
    let vega = ("vega", 4.872_013, 0.676_757, 0.03_f32, 91262_u32);
    let faint = ("faint", 4.88, 0.68, 4.5_f32, 1_u32);
    let pack = FakePack::with_stars("fake-stars", 64, &[vega, faint]);

    let mut set = CatalogSet::new();
    set.register(Box::new(pack));

    let hits: Vec<CatalogHit<'_>> = set
        .query(vega_pose(), 1.5)
        .expect("query")
        .collect();

    let hips: Vec<u32> = hits.iter().map(|h| h.star.hip_id).collect();
    assert!(hips.contains(&91262));
    assert!(!hips.contains(&1), "mag 4.5 star must be culled by mag limit 1.5");
}

#[test]
fn unregister_removes_pack_from_queries() {
    let vega = ("vega", 4.872_013, 0.676_757, 0.03_f32, 91262_u32);
    let pack = FakePack::with_stars("fake-stars", 64, &[vega]);

    let mut set = CatalogSet::new();
    set.register(Box::new(pack));
    assert!(set.unregister("fake-stars"));
    assert!(!set.unregister("fake-stars"));

    let hits: Vec<CatalogHit<'_>> = set.query(vega_pose(), 6.0).expect("query").collect();
    assert!(hits.is_empty());
}
