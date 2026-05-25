//! Active catalog packs and pose + magnitude star queries.

use crate::catalog::healpix::{bounding_pixels_for_fov, HealpixError};
use crate::catalog::StarRecord;
use crate::scene::projection::project_icrs;
use crate::types::ViewPose;

/// A star record from an active pack that intersects a catalog query.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CatalogHit<'a> {
    /// Pack that supplied this star ([`StarPack::pack_id`]).
    pub pack_id: &'a str,
    /// Tile star record (ICRS direction, magnitude, HIP id, …).
    pub star: &'a StarRecord,
}

/// HEALPix-tiled star catalog pack (HYG, Tycho-2, Gaia, …).
pub trait StarPack: Send + Sync {
    /// Stable pack identifier (matches on-disk manifest `pack-id`).
    fn pack_id(&self) -> &str;
    /// HEALPix `nside` for this pack's tiles ([`TileHeader::nside`](super::tile::TileHeader::nside)).
    fn nside(&self) -> u32;
    /// Stars in the tile for `healpix_id`, if that tile is loaded.
    fn stars_in_pixel(&self, healpix_id: u64) -> Option<&[StarRecord]>;
}

/// Owns the currently active star packs and answers visibility queries.
#[derive(Default)]
pub struct CatalogSet {
    packs: Vec<Box<dyn StarPack>>,
}

impl CatalogSet {
    /// Empty set (no packs registered).
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Registers a pack; replaces any existing pack with the same [`StarPack::pack_id`].
    pub fn register(&mut self, pack: Box<dyn StarPack>) {
        let id = pack.pack_id().to_owned();
        self.packs.retain(|p| p.pack_id() != id);
        self.packs.push(pack);
    }

    /// Removes a pack by id. Returns `true` if a pack was removed.
    pub fn unregister(&mut self, pack_id: &str) -> bool {
        let before = self.packs.len();
        self.packs.retain(|p| p.pack_id() != pack_id);
        self.packs.len() < before
    }

    /// Ids of currently registered packs (registration order).
    pub fn active_pack_ids(&self) -> impl Iterator<Item = &str> + '_ {
        self.packs.iter().map(|p| p.pack_id())
    }

    /// Stars from all active packs intersecting `pose` and `mag_limit`.
    ///
    /// Culling uses HEALPix FOV overlap, apparent magnitude, and the same screen
    /// projection rules as [`project_icrs`].
    pub fn query(
        &self,
        pose: ViewPose,
        mag_limit: f32,
    ) -> Result<impl Iterator<Item = CatalogHit<'_>> + '_, HealpixError> {
        let mut hits = Vec::new();
        for pack in &self.packs {
            let pixels = bounding_pixels_for_fov(pose, pose.fov_rad, pack.nside())?;
            for &pixel in &pixels {
                let Some(stars) = pack.stars_in_pixel(pixel) else {
                    continue;
                };
                for star in stars {
                    if star.mag > mag_limit {
                        continue;
                    }
                    let (ra_rad, dec_rad) = radec_from_icrs_dir(star.icrs_dir);
                    if project_icrs(ra_rad, dec_rad, pose).is_some() {
                        hits.push(CatalogHit {
                            pack_id: pack.pack_id(),
                            star,
                        });
                    }
                }
            }
        }
        Ok(hits.into_iter())
    }
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
