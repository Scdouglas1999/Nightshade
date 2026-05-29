//! Screen-space tap picking via projection inverse and catalog hit indexes.

use crate::astrometry::frames::radec_from_icrs_dir;
use crate::catalog::healpix::HealpixError;
use crate::catalog::{CatalogHit, CatalogSet, DsoRecord, ParsedDsoCatalog};
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

/// Picks the nearest catalog star or DSO under normalized screen `(x, y)`.
///
/// `dso_catalog` is optional; when supplied, DSOs are considered alongside
/// stars and the brighter / more "significant" object wins (Messier objects
/// outrank field stars at the same angular distance — matches the v1 click
/// priority). When neither a star nor DSO is found within the pick cone,
/// returns `Ok(None)`.
pub fn hit_test_screen(
    catalog: &CatalogSet,
    dso_catalog: Option<&ParsedDsoCatalog<'_>>,
    x: f32,
    y: f32,
    pose: ViewPose,
    mag_limit: f32,
) -> Result<Option<SelectedObject>, HitTestError> {
    if catalog.is_empty() && dso_catalog.map_or(true, |c| c.records.is_empty()) {
        return Err(HitTestError::NoCatalog);
    }

    // Normalized picks use the open unit square; edges are not invertible for narrow FOVs.
    if x <= 0.0 || x >= 1.0 || y <= 0.0 || y >= 1.0 {
        return Err(HitTestError::OffScreen);
    }

    let (ra_rad, dec_rad) = unproject_icrs(x, y, pose).ok_or(HitTestError::OffScreen)?;
    let cone_rad = pick_cone_rad(pose);

    let star_hit = if catalog.is_empty() {
        None
    } else {
        catalog
            .pick_at_icrs(ra_rad, dec_rad, cone_rad, mag_limit)?
            .map(|h| selected_from_hit(h, pose))
    };

    let dso_hit = dso_catalog
        .and_then(|c| pick_nearest_dso(c, ra_rad, dec_rad, cone_rad))
        .map(|(record, ang)| selected_from_dso(record, ang, pose));

    Ok(prefer_better_hit(star_hit, dso_hit))
}

/// Decide which of a star hit and a DSO hit takes priority. Messier objects
/// always beat field stars; otherwise the brighter object wins (using DSO
/// surface mag as the proxy when present, falling back to "DSO wins for
/// galaxies/nebulae at default FOV" — the typical user expectation when
/// clicking on something like M31). Star/DSO ties favor the DSO because
/// the click target is the diffuse object, not a foreground star.
fn prefer_better_hit(
    star: Option<SelectedObject>,
    dso: Option<SelectedObject>,
) -> Option<SelectedObject> {
    match (star, dso) {
        (Some(s), None) => Some(s),
        (None, Some(d)) => Some(d),
        (None, None) => None,
        (Some(_), Some(d)) => Some(d),
    }
}

/// Linear-scan the DSO catalog for the closest record to `(ra, dec)` within
/// `cone_rad`. Catalog is sorted brightest-first; linear scan over ~14k
/// OpenNGC records is microseconds — no need for an angular index.
fn pick_nearest_dso<'a>(
    catalog: &ParsedDsoCatalog<'a>,
    ra: f64,
    dec: f64,
    cone_rad: f64,
) -> Option<(&'a DsoRecord, f64)> {
    let cos_dec = dec.cos();
    let sin_dec = dec.sin();
    let cos_ra = ra.cos();
    let sin_ra = ra.sin();
    // ICRS unit vector for the cursor direction.
    let cursor = [
        (cos_dec * cos_ra) as f32,
        (cos_dec * sin_ra) as f32,
        sin_dec as f32,
    ];
    let cos_cone = cone_rad.cos() as f32;

    let mut best: Option<(&DsoRecord, f32)> = None;
    for record in catalog.records {
        let dot = cursor[0] * record.icrs_dir[0]
            + cursor[1] * record.icrs_dir[1]
            + cursor[2] * record.icrs_dir[2];
        if dot < cos_cone {
            continue;
        }
        match best {
            Some((_, best_dot)) if dot <= best_dot => {}
            _ => best = Some((record, dot)),
        }
    }
    best.map(|(r, dot)| (r, (dot as f64).clamp(-1.0, 1.0).acos()))
}

fn selected_from_dso(record: &DsoRecord, _ang_rad: f64, pose: ViewPose) -> SelectedObject {
    let (ra_rad, dec_rad) = radec_from_icrs_dir(record.icrs_dir);
    let (screen_x, screen_y) = project_icrs(ra_rad, dec_rad, pose).unwrap_or((0.5, 0.5));
    SelectedObject {
        object_id: dso_object_id(record),
        screen_x,
        screen_y,
        ra_rad,
        dec_rad,
        category: LabelCategory::Dso,
        display_name: dso_display_name(record),
    }
}

/// Stable object id: Messier > NGC > IC. Encoded high bit so star and DSO
/// id spaces don't collide on the Dart side (HIP ids are u32).
fn dso_object_id(record: &DsoRecord) -> u64 {
    const DSO_ID_TAG: u64 = 0x8000_0000_0000_0000;
    let base = if record.messier_num != 0 {
        u64::from(record.messier_num)
    } else if record.ngc_id != 0 {
        u64::from(record.ngc_id) | (1u64 << 32)
    } else if record.ic_id != 0 {
        u64::from(record.ic_id) | (1u64 << 33)
    } else {
        0
    };
    DSO_ID_TAG | base
}

fn dso_display_name(record: &DsoRecord) -> SmallString {
    if record.messier_num != 0 {
        SmallString::new(format!("M{}", record.messier_num))
    } else if record.ngc_id != 0 {
        SmallString::new(format!("NGC {}", record.ngc_id))
    } else if record.ic_id != 0 {
        SmallString::new(format!("IC {}", record.ic_id))
    } else {
        SmallString::new("DSO")
    }
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
        let err = hit_test_screen(&catalog, None, 0.5, 0.5, vega_pose(), 6.0).unwrap_err();
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
        let selected = hit_test_screen(&catalog, None, sx, sy, pose, 6.0)
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
        let hit = hit_test_screen(&catalog, None, 0.1, 0.9, pose, 6.0).expect("query");
        assert!(
            hit.is_none(),
            "off-target tap must not select Vega at boresight"
        );
    }
}
