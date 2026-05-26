//! Active catalog packs and pose + magnitude star queries.

use std::borrow::Cow;

use crate::astrometry::frames::radec_from_icrs_dir;
use crate::catalog::healpix::{bounding_pixels_for_fov, HealpixError};
use crate::catalog::tile::LodEntry;
use crate::catalog::{HitIndex, StarRecord};
use crate::scene::projection::project_icrs;
use crate::types::ViewPose;

/// A star record from an active pack that intersects a catalog query.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CatalogHit<'a> {
    /// Pack that supplied this star ([`StarPack::pack_id`]).
    pub pack_id: &'a str,
    /// Tile star record (ICRS direction, magnitude, HIP id, …).
    pub star: StarRecord,
}

/// HEALPix-tiled star catalog pack (HYG, Tycho-2, Gaia, …).
pub trait StarPack: Send + Sync {
    /// Stable pack identifier (matches on-disk manifest `pack-id`).
    fn pack_id(&self) -> &str;
    /// HEALPix `nside` for this pack's tiles ([`TileHeader::nside`](super::tile::TileHeader::nside)).
    fn nside(&self) -> u32;
    /// Stars in the tile for `healpix_id`, if that tile is available.
    fn stars_in_pixel(&self, healpix_id: u64) -> Option<Cow<'_, [StarRecord]>>;
    /// Per-tile LOD table when the pack uses magnitude bands (empty by default).
    fn lod_entries_for_pixel(&self, _healpix_id: u64) -> Option<Cow<'_, [LodEntry]>> {
        None
    }
    /// Direction-based pick index for all stars in this pack (built at registration).
    fn build_hit_index(&self) -> HitIndex {
        HitIndex::new(self.nside())
    }
}

struct ActivePack {
    pack: Box<dyn StarPack>,
    hit: HitIndex,
}

/// Owns the currently active star packs and answers visibility queries.
#[derive(Default)]
pub struct CatalogSet {
    packs: Vec<ActivePack>,
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
        let hit = pack.build_hit_index();
        self.packs.retain(|p| p.pack.pack_id() != id);
        self.packs.push(ActivePack { pack, hit });
    }

    /// Removes a pack by id. Returns `true` if a pack was removed.
    pub fn unregister(&mut self, pack_id: &str) -> bool {
        let before = self.packs.len();
        self.packs.retain(|p| p.pack.pack_id() != pack_id);
        self.packs.len() < before
    }

    /// Whether any star packs are registered (required for screen hit testing).
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.packs.is_empty()
    }

    /// Ids of currently registered packs (registration order).
    pub fn active_pack_ids(&self) -> impl Iterator<Item = &str> + '_ {
        self.packs.iter().map(|p| p.pack.pack_id())
    }

    /// Registered star packs (for render scene assembly).
    pub fn packs(&self) -> impl Iterator<Item = &dyn StarPack> + '_ {
        self.packs.iter().map(|p| p.pack.as_ref())
    }

    /// Nearest visible star to an ICRS direction across all pack hit indexes.
    pub fn pick_at_icrs(
        &self,
        ra_rad: f64,
        dec_rad: f64,
        cone_rad: f64,
        mag_limit: f32,
    ) -> Result<Option<CatalogHit<'_>>, HealpixError> {
        let mut best: Option<(CatalogHit<'_>, f64)> = None;

        for entry in &self.packs {
            let Some(pick) = entry.hit.pick_near(ra_rad, dec_rad, cone_rad, mag_limit)? else {
                continue;
            };
            let replace = match &best {
                None => true,
                Some((_, best_sep)) if pick.separation_rad < *best_sep - f64::EPSILON => true,
                Some((prev, best_sep))
                    if (pick.separation_rad - *best_sep).abs() <= f64::EPSILON =>
                {
                    pick.star.mag < prev.star.mag
                        || (pick.star.mag == prev.star.mag && pick.star.hip_id < prev.star.hip_id)
                }
                _ => false,
            };
            if replace {
                best = Some((
                    CatalogHit {
                        pack_id: entry.pack.pack_id(),
                        star: *pick.star,
                    },
                    pick.separation_rad,
                ));
            }
        }

        Ok(best.map(|(hit, _)| hit))
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
        for entry in &self.packs {
            let pack = entry.pack.as_ref();
            let pixels = bounding_pixels_for_fov(pose, pose.fov_rad, pack.nside())?;
            for &pixel in &pixels {
                let Some(stars) = pack.stars_in_pixel(pixel) else {
                    continue;
                };
                for star in stars.iter() {
                    if star.mag > mag_limit {
                        continue;
                    }
                    let (ra_rad, dec_rad) = radec_from_icrs_dir(star.icrs_dir);
                    if project_icrs(ra_rad, dec_rad, pose).is_some() {
                        hits.push(CatalogHit {
                            pack_id: pack.pack_id(),
                            star: *star,
                        });
                    }
                }
            }
        }
        Ok(hits.into_iter())
    }
}
