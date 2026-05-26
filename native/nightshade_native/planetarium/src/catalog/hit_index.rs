//! Per-pack hit-test index: HEALPix cell → magnitude heap.
//!
//! Supports cone queries for tap selection: nearest visible star to a sky
//! direction within an angular radius and apparent-magnitude limit.

use std::cmp::Ordering;
use std::collections::{BTreeMap, BinaryHeap};

use crate::astrometry::frames::radec_from_icrs_dir;

use super::healpix::{pixel_for_direction, pixels_in_cone, HealpixError};
use super::StarRecord;

/// Result of a successful cone pick.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct HitPick<'a> {
    /// HEALPix pixel containing the star.
    pub healpix_id: u64,
    /// Matched catalog record.
    pub star: &'a StarRecord,
    /// Angular separation from the query direction (radians).
    pub separation_rad: f64,
}

/// Per-pack spatial index for direction-based hit testing.
#[derive(Debug, Clone)]
pub struct HitIndex {
    nside: u32,
    cells: BTreeMap<u64, CellIndex>,
}

#[derive(Debug, Clone)]
struct CellIndex {
    /// Brightest-first (built via [`CellIndex::from_unsorted`] magnitude heap).
    stars: Vec<StarRecord>,
}

/// Wrapper so [`BinaryHeap`] orders by ascending apparent magnitude (brightest pops first).
#[derive(Debug, Clone, Copy)]
struct MagOrder(StarRecord);

impl Eq for MagOrder {}

impl PartialEq for MagOrder {
    fn eq(&self, other: &Self) -> bool {
        self.0.mag == other.0.mag && self.0.hip_id == other.0.hip_id
    }
}

impl PartialOrd for MagOrder {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for MagOrder {
    fn cmp(&self, other: &Self) -> Ordering {
        self.0
            .mag
            .partial_cmp(&other.0.mag)
            .unwrap_or(Ordering::Equal)
            .reverse()
    }
}

impl HitIndex {
    /// Empty index at the given HEALPix resolution.
    #[must_use]
    pub fn new(nside: u32) -> Self {
        Self {
            nside,
            cells: BTreeMap::new(),
        }
    }

    /// HEALPix `nside` for this index.
    #[must_use]
    pub fn nside(&self) -> u32 {
        self.nside
    }

    /// Number of occupied HEALPix cells.
    #[must_use]
    pub fn cell_count(&self) -> usize {
        self.cells.len()
    }

    /// Total stars indexed across all cells.
    #[must_use]
    pub fn star_count(&self) -> usize {
        self.cells.values().map(|c| c.stars.len()).sum()
    }

    /// Insert or merge stars into the cell for `healpix_id`.
    pub fn insert_cell(&mut self, healpix_id: u64, stars: impl IntoIterator<Item = StarRecord>) {
        let incoming: Vec<_> = stars.into_iter().collect();
        if incoming.is_empty() {
            return;
        }
        match self.cells.get_mut(&healpix_id) {
            Some(cell) => {
                cell.stars.extend(incoming);
                cell.rebuild_heap_order();
            }
            None => {
                self.cells
                    .insert(healpix_id, CellIndex::from_unsorted(incoming));
            }
        }
    }

    /// Index a single star in the HEALPix cell for its [`StarRecord::icrs_dir`].
    pub fn insert_star(&mut self, star: StarRecord) -> Result<(), HealpixError> {
        let (ra_rad, dec_rad) = radec_from_icrs_dir(star.icrs_dir);
        let pixel = pixel_for_direction(ra_rad, dec_rad, self.nside)?;
        self.insert_cell(pixel, [star]);
        Ok(())
    }

    /// Nearest visible star to `(ra_rad, dec_rad)` within a spherical cone.
    ///
    /// Only stars with `mag <= mag_limit` are considered. Ties at equal angular
    /// separation prefer the brighter star (lower magnitude).
    pub fn pick_near(
        &self,
        ra_rad: f64,
        dec_rad: f64,
        cone_rad: f64,
        mag_limit: f32,
    ) -> Result<Option<HitPick<'_>>, HealpixError> {
        let query_dir = unit_dir(ra_rad, dec_rad);
        let pixels = pixels_in_cone(ra_rad, dec_rad, cone_rad, self.nside)?;

        let mut best: Option<(u64, usize, f64)> = None;

        for healpix_id in pixels {
            let Some(cell) = self.cells.get(&healpix_id) else {
                continue;
            };
            for (idx, star) in cell.stars.iter().enumerate() {
                if star.mag > mag_limit {
                    break;
                }
                let sep = angular_separation_dirs(query_dir, star.icrs_dir);
                if sep > cone_rad {
                    continue;
                }
                let replace = match best {
                    None => true,
                    Some((_, _, best_sep)) if sep < best_sep - f64::EPSILON => true,
                    Some((_, best_idx, best_sep)) if (sep - best_sep).abs() <= f64::EPSILON => {
                        let best_star = &cell.stars[best_idx];
                        star.mag < best_star.mag
                            || (star.mag == best_star.mag && star.hip_id < best_star.hip_id)
                    }
                    _ => false,
                };
                if replace {
                    best = Some((healpix_id, idx, sep));
                }
            }
        }

        Ok(best.map(|(healpix_id, idx, separation_rad)| HitPick {
            healpix_id,
            star: &self.cells[&healpix_id].stars[idx],
            separation_rad,
        }))
    }
}

impl CellIndex {
    fn from_unsorted(stars: Vec<StarRecord>) -> Self {
        let mut cell = Self { stars };
        cell.rebuild_heap_order();
        cell
    }

    fn rebuild_heap_order(&mut self) {
        let mut heap = BinaryHeap::with_capacity(self.stars.len());
        for star in self.stars.drain(..) {
            heap.push(MagOrder(star));
        }
        self.stars.clear();
        self.stars.reserve(heap.len());
        while let Some(MagOrder(star)) = heap.pop() {
            self.stars.push(star);
        }
    }
}

#[inline]
fn unit_dir(ra_rad: f64, dec_rad: f64) -> [f64; 3] {
    let (sin_dec, cos_dec) = dec_rad.sin_cos();
    let (sin_ra, cos_ra) = ra_rad.sin_cos();
    [cos_dec * cos_ra, cos_dec * sin_ra, sin_dec]
}

#[inline]
fn angular_separation_dirs(a: [f64; 3], b: [f32; 3]) -> f64 {
    let dot = a[0] * f64::from(b[0]) + a[1] * f64::from(b[1]) + a[2] * f64::from(b[2]);
    dot.clamp(-1.0, 1.0).acos()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::StarRecord;

    const POLARIS: (f64, f64, u32) = (0.662_062, 1.557_896, 11767);
    const VEGA: (f64, f64, u32) = (4.872_013, 0.676_757, 91262);
    const SIRIUS: (f64, f64, u32) = (1.767_015, -0.291_808, 32349);

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

    fn index_with_bright_stars(nside: u32) -> HitIndex {
        let mut idx = HitIndex::new(nside);
        for &(ra, dec, hip) in &[POLARIS, VEGA, SIRIUS] {
            let mag = match hip {
                11767 => 1.98_f32,
                91262 => 0.03,
                32349 => -1.46,
                _ => 5.0,
            };
            idx.insert_star(star(ra, dec, mag, hip)).expect("insert");
        }
        idx
    }

    #[test]
    fn cell_heap_orders_brightest_first() {
        let cell = CellIndex::from_unsorted(vec![
            star(0.0, 0.0, 5.0, 1),
            star(0.0, 0.0, 1.0, 2),
            star(0.0, 0.0, 3.0, 3),
        ]);
        assert_eq!(cell.stars[0].hip_id, 2);
        assert_eq!(cell.stars[1].hip_id, 3);
        assert_eq!(cell.stars[2].hip_id, 1);
    }

    #[test]
    fn pick_near_polaris_vega_sirius() {
        let idx = index_with_bright_stars(8);
        let cone = 0.15_f64;
        let mag_limit = 6.0_f32;

        let polaris = idx
            .pick_near(POLARIS.0, POLARIS.1, cone, mag_limit)
            .expect("query")
            .expect("polaris hit");
        assert_eq!(polaris.star.hip_id, 11767);

        let vega = idx
            .pick_near(VEGA.0, VEGA.1, cone, mag_limit)
            .expect("query")
            .expect("vega hit");
        assert_eq!(vega.star.hip_id, 91262);

        let sirius = idx
            .pick_near(SIRIUS.0, SIRIUS.1, cone, mag_limit)
            .expect("query")
            .expect("sirius hit");
        assert_eq!(sirius.star.hip_id, 32349);
    }

    #[test]
    fn pick_near_prefers_nearest_over_brighter_in_cone() {
        let mut idx = HitIndex::new(64);
        let ra = VEGA.0;
        let dec = VEGA.1;
        idx.insert_star(star(ra, dec, 0.03, 91262)).expect("vega");
        idx.insert_star(star(ra + 0.001, dec + 0.001, -1.0, 1))
            .expect("faint offset");

        let hit = idx
            .pick_near(ra + 0.001, dec + 0.001, 0.05, 6.0)
            .expect("query")
            .expect("nearest");
        assert_eq!(hit.star.hip_id, 1, "offset faint star is angularly nearest");
    }
}
