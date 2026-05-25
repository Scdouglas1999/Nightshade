//! Tile residency eviction policy: tier ordering, LRU within tiers, and
//! anti-quadratic stress test for the eviction loop.

use std::collections::BTreeSet;
use std::time::Instant;

use nightshade_planetarium::catalog::TileResidency;

/// Eviction must drop a tile outside both the FOV and the warmup ring before
/// touching anything currently in view.
#[test]
fn eviction_respects_fov_protection() {
    let cap = 4;
    let mut res = TileResidency::new(cap);

    // Load three stale tiles (no FOV/warmup overlap declared on these calls).
    for id in [100u64, 200, 300] {
        res.sync_pixel_sets(&[id], &[], |_| 1);
    }
    assert_eq!(res.len(), 3);
    // Load one more — still at cap, no eviction yet.
    res.sync_pixel_sets(&[400u64], &[], |_| 1);
    assert_eq!(res.len(), cap);
    assert_eq!(res.eviction_count(), 0);

    // Now request a sync where tiles 100..400 are declared as the *current
    // FOV* (so they're FOV-protected) and we load TWO new tiles (500, 600).
    // The residency would jump to 6 with cap 4 → 2 evictions required. Both
    // 500 and 600 are FOV (just loaded). The pre-existing 100..400 are
    // declared FOV via the `fov` argument too — so everything is FOV tier.
    // The LRU-within-tier rule then breaks the tie: 100 and 200 (oldest)
    // must go.
    let fov = [100u64, 200, 300, 400, 500, 600];
    let delta = res.sync_pixel_sets(&fov, &[], |_| 1);

    assert_eq!(delta.evicted.len(), 2, "exactly 2 evictions to fit cap");
    // The two oldest FOV-tier tiles must go.
    let evicted: BTreeSet<u64> = delta.evicted.iter().copied().collect();
    assert_eq!(
        evicted,
        BTreeSet::from([100u64, 200]),
        "oldest FOV-tier tiles must evict first"
    );
    assert!(res.get(500).is_some(), "newly loaded FOV tile must remain");
    assert!(res.get(600).is_some(), "newly loaded FOV tile must remain");
}

/// Stale-tier tiles must be evicted before any warmup-protected tile.
#[test]
fn eviction_drops_stale_before_warmup() {
    let cap = 3;
    let mut res = TileResidency::new(cap);

    // Load three tiles.
    for id in [100u64, 200, 300] {
        res.sync_pixel_sets(&[id], &[], |_| 1);
    }
    assert_eq!(res.len(), cap);

    // Request a sync where 200, 300 are warmup-protected and 100 is stale.
    // Add one new FOV tile (400) → forces 1 eviction. The stale tile (100)
    // must lose.
    let delta = res.sync_pixel_sets(&[400u64], &[200u64, 300], |_| 1);
    assert_eq!(delta.evicted, vec![100u64]);
    assert!(res.get(200).is_some(), "warmup tile 200 must remain");
    assert!(res.get(300).is_some(), "warmup tile 300 must remain");
    assert!(res.get(400).is_some(), "new FOV tile 400 must be resident");
}

/// Within the stale (unprotected) tier, eviction follows strict LRU.
#[test]
fn eviction_respects_lru_order_within_stale_tier() {
    let cap = 3;
    let mut res = TileResidency::new(cap);

    for id in 1..=3u64 {
        res.sync_pixel_sets(&[id], &[], |_| 1);
    }
    assert_eq!(res.len(), cap);

    // Touch tile 1 → now most-recently-used.
    assert!(res.touch(1));

    // Load a 4th tile, forcing one eviction. Tile 2 is the LRU stale; tile 3
    // was loaded just before tile 1 was touched. Order: 2 < 3 < 1.
    let delta = res.sync_pixel_sets(&[4u64], &[], |_| 1);
    assert_eq!(
        delta.evicted,
        vec![2u64],
        "tile 2 (oldest stale) must evict"
    );
    assert!(res.get(1).is_some(), "tile 1 (touched) must remain");
    assert!(res.get(3).is_some(), "tile 3 (recent) must remain");
    assert!(res.get(4).is_some(), "tile 4 (new) must be resident");
}

/// Stress: with a 5000-cap residency, perform a single sync that forces
/// 5000 evictions across a 5000-id FOV plus 5000-id warmup ring. The
/// O(K · R · (F+W)) pre-fix implementation took minutes here on a debug
/// build; the current O(R log R + K) version finishes in milliseconds even
/// without optimizations.
///
/// Wall-clock budget: 5 s (in a debug build on a modest CI runner; release
/// completes in <50 ms). This catches a quadratic regression while leaving
/// generous headroom for slow CI.
#[test]
fn eviction_is_not_quadratic_at_ten_thousand_tiles() {
    const CAP: usize = 5_000;
    const TURNOVER: u64 = 5_000;

    let mut res = TileResidency::new(CAP);

    // Fill to capacity with stale tiles (ids 0..5000).
    let initial: Vec<u64> = (0..CAP as u64).collect();
    for chunk in initial.chunks(512) {
        res.sync_pixel_sets(chunk, &[], |_| 1);
    }
    assert_eq!(res.len(), CAP);

    // Single sync: load 5000 brand-new FOV tiles (10000..15000) with a
    // 5000-id warmup ring (15000..20000). That forces exactly 5000 evictions
    // from the stale tier (the initial set).
    let fov: Vec<u64> = (10_000..10_000 + TURNOVER).collect();
    let warmup: Vec<u64> = (15_000..15_000 + TURNOVER).collect();

    let start = Instant::now();
    let delta = res.sync_pixel_sets(&fov, &warmup, |_| 1);
    let elapsed = start.elapsed();

    assert_eq!(delta.loaded.len(), TURNOVER as usize);
    assert_eq!(delta.evicted.len(), TURNOVER as usize);
    assert_eq!(res.len(), CAP);

    assert!(
        elapsed.as_secs_f64() < 5.0,
        "eviction of {TURNOVER} tiles from a {CAP}-cap residency took {elapsed:?} \
         — almost certainly a quadratic regression in pick_eviction_candidate"
    );
}

/// Sanity: empty FOV + empty warmup → all tiles in the Stale tier, eviction
/// follows strict LRU.
#[test]
fn empty_fov_and_warmup_evicts_strict_lru() {
    let cap = 5;
    let mut res = TileResidency::new(cap);
    for id in 1..=5u64 {
        res.sync_pixel_sets(&[id], &[], |_| 1);
    }
    // Touch in order 5, 4, 3, 2, 1 → tile 1 is most recent; tile 5 is least.
    for id in (1..=5u64).rev() {
        assert!(res.touch(id));
    }

    let mut evicted = BTreeSet::new();
    for id in 6..=8u64 {
        let delta = res.sync_pixel_sets(&[id], &[], |_| 1);
        for e in delta.evicted {
            evicted.insert(e);
        }
    }
    assert_eq!(evicted, BTreeSet::from([5u64, 4, 3]));
    for id in [1u64, 2, 6, 7, 8] {
        assert!(res.get(id).is_some(), "tile {id} should remain");
    }
}
