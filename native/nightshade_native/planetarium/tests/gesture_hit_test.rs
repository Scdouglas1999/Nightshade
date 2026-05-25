//! Integration: Planetarium handle screen hit testing with catalog packs.

use std::collections::HashMap;

use std::thread;
use std::time::{Duration, Instant};

use nightshade_planetarium::bus::PlanetariumCommand;
use std::borrow::Cow;

use nightshade_planetarium::catalog::{pixel_for_direction, StarPack, StarRecord};
use nightshade_planetarium::gesture::HitTestError;
use nightshade_planetarium::scene::projection::project_icrs;
use nightshade_planetarium::types::{SkyProjection, ViewPose};
use nightshade_planetarium::Planetarium;

const WAKE_TIMEOUT: Duration = Duration::from_millis(500);
const POLL: Duration = Duration::from_millis(2);

fn wait_pose(planetarium: &Planetarium, expected_ra: f64) {
    let deadline = Instant::now() + WAKE_TIMEOUT;
    loop {
        let pose = planetarium.snapshot().view_pose;
        if (pose.ra_rad - expected_ra).abs() < f64::EPSILON {
            return;
        }
        if Instant::now() >= deadline {
            panic!(
                "timed out waiting for pose ra={expected_ra}; last ra={}",
                pose.ra_rad
            );
        }
        thread::sleep(POLL);
    }
}

struct FakePack {
    id: &'static str,
    nside: u32,
    tiles: HashMap<u64, Vec<StarRecord>>,
}

impl FakePack {
    fn with_stars(stars: &[(&str, f64, f64, f32, u32)]) -> Self {
        let nside = 64;
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
        Self {
            id: "fake-stars",
            nside,
            tiles,
        }
    }
}

impl StarPack for FakePack {
    fn pack_id(&self) -> &str {
        self.id
    }

    fn nside(&self) -> u32 {
        self.nside
    }

    fn stars_in_pixel(&self, healpix_id: u64) -> Option<Cow<'_, [StarRecord]>> {
        self.tiles
            .get(&healpix_id)
            .map(|t| Cow::Borrowed(t.as_slice()))
    }

    fn build_hit_index(&self) -> nightshade_planetarium::catalog::HitIndex {
        let mut idx = nightshade_planetarium::catalog::HitIndex::new(self.nside);
        for stars in self.tiles.values() {
            for &star in stars {
                idx.insert_star(star).expect("insert");
            }
        }
        idx
    }
}

#[test]
fn planetarium_hit_test_requires_catalog() {
    let planetarium = Planetarium::new(0).expect("create");
    let err = planetarium.hit_test(0.5, 0.5).unwrap_err();
    assert_eq!(err, HitTestError::NoCatalog);
}

#[test]
fn planetarium_hit_test_picks_vega_at_boresight() {
    let vega = (4.872_013, 0.676_757, 0.03_f32, 91262_u32);
    let pose = ViewPose {
        ra_rad: vega.0,
        dec_rad: vega.1,
        fov_rad: 0.35,
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    };

    let planetarium = Planetarium::new(0).expect("create");
    planetarium
        .send(PlanetariumCommand::SetPose(pose))
        .expect("set_pose");
    wait_pose(&planetarium, vega.0);
    planetarium.register_pack(Box::new(FakePack::with_stars(&[(
        "vega", vega.0, vega.1, vega.2, vega.3,
    )])));

    let snap_pose = planetarium.snapshot().view_pose;
    let (sx, sy) = project_icrs(vega.0, vega.1, snap_pose).expect("project");
    let selected = planetarium.hit_test(sx, sy).expect("hit").expect("vega");
    assert_eq!(selected.object_id, 91262);
}
