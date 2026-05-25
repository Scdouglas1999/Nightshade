//! HEALPix tile GPU residency with LRU eviction and FOV warmup ring.
//!
//! The renderer keeps a bounded set of uploaded tiles ([`TileResidency`]). On each
//! visibility update, tiles intersecting the field of view are touched and loaded
//! eagerly; tiles in the surrounding warmup ring are retained when possible so
//! small pans do not reload from disk.

use std::collections::BTreeMap;

use crate::catalog::healpix::{bounding_pixels_for_fov, HealpixError};
use crate::types::ViewPose;

/// HEALPix nested pixel id (opaque `u64`, matches [`super::tile::TileHeader::healpix_id`]).
pub type HealpixId = u64;

/// A tile whose star records are resident in the per-catalog GPU ring buffer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ResidentTile {
    /// HEALPix cell id for this upload.
    pub healpix_id: HealpixId,
    /// Slice index in the catalog's GPU ring buffer.
    pub gpu_slot: u32,
    /// Stars uploaded for this tile (from catalog blob).
    pub star_count: u32,
    /// Monotonic touch generation (higher = more recently used for LRU).
    pub touch_seq: u64,
}

/// Result of a [`TileResidency::sync_visibility`] call.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ResidencySync {
    /// Tiles newly loaded this frame (in ascending id order).
    pub loaded: Vec<HealpixId>,
    /// Tiles evicted to honor the capacity cap (ascending id order).
    pub evicted: Vec<HealpixId>,
}

/// LRU manager for resident HEALPix tiles.
#[derive(Debug)]
pub struct TileResidency {
    cap: usize,
    residents: BTreeMap<HealpixId, ResidentTile>,
    next_touch_seq: u64,
    next_gpu_slot: u32,
    eviction_count: u64,
}

impl TileResidency {
    /// Empty residency with a hard tile cap (`cap` must be > 0).
    #[must_use]
    pub fn new(cap: usize) -> Self {
        assert!(cap > 0, "tile residency cap must be > 0");
        Self {
            cap,
            residents: BTreeMap::new(),
            next_touch_seq: 0,
            next_gpu_slot: 0,
            eviction_count: 0,
        }
    }

    /// Maximum resident tiles.
    #[must_use]
    pub fn cap(&self) -> usize {
        self.cap
    }

    /// Currently resident tiles (ascending HEALPix id).
    #[must_use]
    pub fn resident_ids(&self) -> impl Iterator<Item = HealpixId> + '_ {
        self.residents.keys().copied()
    }

    /// Number of resident tiles.
    #[must_use]
    pub fn len(&self) -> usize {
        self.residents.len()
    }

    /// `true` when no tiles are resident.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.residents.is_empty()
    }

    /// Lookup a resident tile.
    #[must_use]
    pub fn get(&self, healpix_id: HealpixId) -> Option<&ResidentTile> {
        self.residents.get(&healpix_id)
    }

    /// Total LRU evictions since construction.
    #[must_use]
    pub fn eviction_count(&self) -> u64 {
        self.eviction_count
    }

    /// Promote `healpix_id` to most-recently-used without loading.
    ///
    /// Returns `false` when the tile is not resident.
    pub fn touch(&mut self, healpix_id: HealpixId) -> bool {
        let Some(tile) = self.residents.get_mut(&healpix_id) else {
            return false;
        };
        self.next_touch_seq += 1;
        tile.touch_seq = self.next_touch_seq;
        true
    }

    /// Apply FOV + warmup visibility for `pose`, loading missing FOV tiles and
    /// evicting LRU entries outside the warmup ring when over capacity.
    ///
    /// `warmup_fov_scale` multiplies [`ViewPose::fov_rad`] for the prefetch ring
    /// (e.g. `1.5` keeps neighbors resident across small pans).
    pub fn sync_visibility(
        &mut self,
        pose: ViewPose,
        nside: u32,
        warmup_fov_scale: f32,
        load_tile: impl FnMut(HealpixId) -> u32,
    ) -> Result<ResidencySync, HealpixError> {
        let fov_pixels = bounding_pixels_for_fov(pose, pose.fov_rad, nside)?;
        let warmup_fov = pose.fov_rad * warmup_fov_scale;
        let ring_pixels = bounding_pixels_for_fov(pose, warmup_fov, nside)?;
        Ok(self.sync_pixel_sets(&fov_pixels, &ring_pixels, load_tile))
    }

    /// Core sync when FOV and warmup pixel sets are already known.
    pub fn sync_pixel_sets(
        &mut self,
        fov: &[HealpixId],
        warmup_ring: &[HealpixId],
        mut load_tile: impl FnMut(HealpixId) -> u32,
    ) -> ResidencySync {
        let mut delta = ResidencySync::default();

        for &id in fov {
            self.touch_or_load(id, &mut load_tile, &mut delta.loaded);
        }
        for &id in warmup_ring {
            if self.residents.contains_key(&id) {
                let _ = self.touch(id);
            }
        }

        while self.residents.len() > self.cap {
            let Some(evict_id) = self.pick_eviction_candidate(fov, warmup_ring) else {
                break;
            };
            self.residents.remove(&evict_id);
            self.eviction_count += 1;
            delta.evicted.push(evict_id);
        }

        delta.loaded.sort_unstable();
        delta.evicted.sort_unstable();
        delta
    }

    fn touch_or_load(
        &mut self,
        healpix_id: HealpixId,
        load_tile: &mut impl FnMut(HealpixId) -> u32,
        loaded: &mut Vec<HealpixId>,
    ) {
        if self.residents.contains_key(&healpix_id) {
            let _ = self.touch(healpix_id);
            return;
        }
        self.next_touch_seq += 1;
        let star_count = load_tile(healpix_id);
        let tile = ResidentTile {
            healpix_id,
            gpu_slot: self.next_gpu_slot,
            star_count,
            touch_seq: self.next_touch_seq,
        };
        self.next_gpu_slot = self.next_gpu_slot.wrapping_add(1);
        loaded.push(healpix_id);
        self.residents.insert(healpix_id, tile);
    }

    /// Eviction priority: stale (outside warmup) → warmup-only → FOV (last resort).
    fn pick_eviction_candidate(
        &self,
        fov: &[HealpixId],
        warmup_ring: &[HealpixId],
    ) -> Option<HealpixId> {
        let in_fov = |id: HealpixId| fov.contains(&id);
        let in_warmup = |id: HealpixId| warmup_ring.contains(&id);

        let mut best: Option<(u8, u64, HealpixId)> = None;
        for (&id, tile) in &self.residents {
            let tier = if in_fov(id) {
                2u8
            } else if in_warmup(id) {
                1
            } else {
                0
            };
            let replace = match best {
                None => true,
                Some((best_tier, best_seq, _)) => {
                    tier < best_tier || (tier == best_tier && tile.touch_seq < best_seq)
                }
            };
            if replace {
                best = Some((tier, tile.touch_seq, id));
            }
        }
        best.map(|(_, _, id)| id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::SkyProjection;

    #[test]
    fn touch_promotes_lru_order() {
        let mut res = TileResidency::new(4);
        for id in 0..3u64 {
            res.sync_pixel_sets(&[id], &[], |_| 1);
        }
        assert!(res.touch(0));
        assert!(res.touch(1));
        res.sync_pixel_sets(&[3], &[], |_| 1);
        res.sync_pixel_sets(&[4], &[], |_| 1);
        assert!(!res.get(2).is_some(), "tile 2 should be LRU-evicted");
        assert!(res.get(0).is_some(), "tile 0 was touched recently");
    }

    #[test]
    fn warmup_ring_retains_neighbor_across_small_pan() {
        let mut res = TileResidency::new(8);
        let pose_a = ViewPose {
            ra_rad: 0.0,
            dec_rad: 0.5,
            fov_rad: 0.25,
            roll_rad: 0.0,
            projection: SkyProjection::Stereographic,
        };
        let delta_a = res
            .sync_visibility(pose_a, 8, 1.5, |_| 10)
            .expect("sync a");
        assert!(!delta_a.loaded.is_empty());

        let fov_b = [pose_a.ra_rad + 0.08, pose_a.dec_rad];
        let pose_b = ViewPose {
            ra_rad: fov_b[0],
            dec_rad: fov_b[1],
            fov_rad: pose_a.fov_rad,
            roll_rad: 0.0,
            projection: SkyProjection::Stereographic,
        };
        let fov_pixels = crate::catalog::healpix::bounding_pixels_for_fov(pose_b, pose_b.fov_rad, 8)
            .expect("fov b");
        let ring_pixels =
            crate::catalog::healpix::bounding_pixels_for_fov(pose_b, pose_b.fov_rad * 1.5, 8)
                .expect("ring b");

        let overlap: Vec<u64> = fov_pixels
            .iter()
            .copied()
            .filter(|p| res.get(*p).is_some())
            .collect();
        assert!(
            !overlap.is_empty(),
            "small pan should keep some prior FOV tiles via warmup overlap"
        );

        let _ = res.sync_pixel_sets(&fov_pixels, &ring_pixels, |_| 10);
        for id in overlap {
            assert!(
                res.get(id).is_some(),
                "warmup overlap tile {id} should stay resident"
            );
        }
    }
}
