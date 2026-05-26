//! Screen-space tap picking via projection inverse and catalog hit indexes.

use crate::catalog::healpix::HealpixError;
use crate::catalog::{CatalogHit, CatalogSet};
use crate::scene::dev_catalog::DEV_STARS;
use crate::scene::projection::{project_icrs, unproject_icrs};
use crate::scene::{LabelCategory, SelectedObject, SmallString};
use crate::types::ViewPose;

/// Normalized screen radius (fraction of widget) for tap hit cone.
const PICK_RADIUS: f32 = 0.06;

/// Errors from screen hit testing (fail loud — no silent empty catalog).
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum HitTestError {
    /// No star packs registered on this planetarium instance.
    #[error("no catalog packs registered — load a star pack before hit testing")]
    NoCatalog,
    /// Tap lies outside the invertible projection disc.
    #[error("screen position is not invertible to sky coordinates")]
    OffScreen,
    /// HEALPix query failed.
    #[error("catalog hit query failed: {0}")]
    Healpix(#[from] HealpixError),
}

/// Angular cone radius (radians) for a normalized-screen pick disc.
#[must_use]
pub fn pick_cone_rad(pose: ViewPose) -> f64 {
    f64::from(pose.fov_rad) * f64::from(PICK_RADIUS) * 2.0
}

/// Picks the nearest catalog star under normalized screen `(x, y)`.
pub fn hit_test_screen(
    catalog: &CatalogSet,
    x: f32,
    y: f32,
    pose: ViewPose,
    mag_limit: f32,
) -> Result<Option<SelectedObject>, HitTestError> {
    if catalog.is_empty() {
        return Err(HitTestError::NoCatalog);
    }

    // Normalized picks use the open unit square; edges are not invertible for narrow FOVs.
    if x <= 0.0 || x >= 1.0 || y <= 0.0 || y >= 1.0 {
        return Err(HitTestError::OffScreen);
    }

    let (ra_rad, dec_rad) = unproject_icrs(x, y, pose).ok_or(HitTestError::OffScreen)?;
    let cone_rad = pick_cone_rad(pose);
    let hit = catalog
        .pick_at_icrs(ra_rad, dec_rad, cone_rad, mag_limit)?
        .map(|h| selected_from_hit(h, pose));
    Ok(hit)
}

fn selected_from_hit(hit: CatalogHit<'_>, pose: ViewPose) -> SelectedObject {
    let (ra_rad, dec_rad) = radec_from_icrs_dir(hit.star.icrs_dir);
    let (screen_x, screen_y) = project_icrs(ra_rad, dec_rad, pose).unwrap_or((0.5, 0.5));
    SelectedObject {
        object_id: u64::from(hit.star.hip_id),
        screen_x,
        screen_y,
        ra_rad,
        dec_rad,
        category: LabelCategory::Star,
        display_name: star_display_name(hit.star.hip_id),
    }
}

fn star_display_name(hip_id: u32) -> SmallString {
    DEV_STARS
        .iter()
        .find(|s| s.hip == u64::from(hip_id))
        .map(|s| SmallString::new(s.name))
        .unwrap_or_else(|| SmallString::new(format!("HIP {hip_id}")))
}

#[inline]
fn radec_from_icrs_dir(dir: [f32; 3]) -> (f64, f64) {
    let x = f64::from(dir[0]);
    let y = f64::from(dir[1]);
    let z = f64::from(dir[2]);
    let dec_rad = z.clamp(-1.0, 1.0).asin();
    let ra_rad = y.atan2(x);
    (ra_rad, dec_rad)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::borrow::Cow;
    use std::collections::HashMap;

    use crate::catalog::{pixel_for_direction, CatalogSet, StarPack, StarRecord};
    use crate::types::SkyProjection;

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

        fn stars_in_pixel(&self, healpix_id: u64) -> Option<Cow<'_, [StarRecord]>> {
            self.tiles
                .get(&healpix_id)
                .map(|t| Cow::Borrowed(t.as_slice()))
        }

        fn build_hit_index(&self) -> crate::catalog::HitIndex {
            let mut idx = crate::catalog::HitIndex::new(self.nside);
            for stars in self.tiles.values() {
                for &star in stars {
                    idx.insert_star(star).expect("insert star");
                }
            }
            idx
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
    fn no_catalog_fails_loud() {
        let catalog = CatalogSet::new();
        let err = hit_test_screen(&catalog, 0.5, 0.5, vega_pose(), 6.0).unwrap_err();
        assert_eq!(err, HitTestError::NoCatalog);
    }

    #[test]
    fn tap_near_vega_selects_hip_91262() {
        let vega = ("vega", 4.872_013, 0.676_757, 0.03_f32, 91262_u32);
        let polaris = ("polaris", 0.662_062, 1.557_896, 1.98_f32, 11767_u32);
        let pack = FakePack::with_stars("fake-stars", 64, &[vega, polaris]);

        let mut catalog = CatalogSet::new();
        catalog.register(Box::new(pack));

        let pose = vega_pose();
        let (sx, sy) = project_icrs(vega.1, vega.2, pose).expect("vega projected");
        let selected = hit_test_screen(&catalog, sx, sy, pose, 6.0)
            .expect("hit")
            .expect("vega selected");
        assert_eq!(selected.object_id, 91262);
        assert_eq!(selected.display_name.as_str(), "Vega");
    }

    #[test]
    fn tap_away_from_catalog_star_returns_none() {
        let vega = ("vega", 4.872_013, 0.676_757, 0.03_f32, 91262_u32);
        let pack = FakePack::with_stars("fake-stars", 64, &[vega]);
        let mut catalog = CatalogSet::new();
        catalog.register(Box::new(pack));

        let pose = vega_pose();
        let hit = hit_test_screen(&catalog, 0.1, 0.9, pose, 6.0).expect("query");
        assert!(
            hit.is_none(),
            "off-target tap must not select Vega at boresight"
        );
    }
}
