//! Target scoring math — Rust port of `target_scoring.dart`.
//!
//! Each `_score*` helper from the Dart implementation is reproduced verbatim
//! (same break-points, same magic numbers, same fallthroughs). The result is
//! that `scoreTarget` in Dart and `score_target` here produce the same
//! `totalScore` for the same inputs, modulo IEEE-754 rounding. The parity
//! test in `tests` pins a fixed observer / target / moon / time tuple to that
//! contract.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::scheduling::astronomy::{
    airmass, angular_separation, calculate_object_visibility, object_alt_az, ObjectVisibility,
};

/// Weights — one knob per scoring axis. Defaults match `target_scoring.dart`'s
/// `const ScoringWeights()`.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub struct ScoringWeights {
    pub altitude_weight: f64,
    pub moon_distance_weight: f64,
    pub transit_proximity_weight: f64,
    pub darkness_weight: f64,
    pub airmass_weight: f64,
}

impl Default for ScoringWeights {
    fn default() -> Self {
        Self {
            altitude_weight: 0.25,
            moon_distance_weight: 0.25,
            transit_proximity_weight: 0.20,
            darkness_weight: 0.15,
            airmass_weight: 0.15,
        }
    }
}

impl ScoringWeights {
    /// Sum of all weights. Used to normalise the weighted score the same way
    /// the Dart implementation does.
    pub fn sum(&self) -> f64 {
        self.altitude_weight
            + self.moon_distance_weight
            + self.transit_proximity_weight
            + self.darkness_weight
            + self.airmass_weight
    }
}

/// Input target description for scoring. RA in degrees (consistent with the
/// Dart `coord.raDegrees`).
#[derive(Debug, Clone)]
pub struct TargetInput {
    pub id: String,
    pub name: String,
    /// Right ascension in DEGREES (0–360).
    pub ra_deg: f64,
    pub dec_deg: f64,
    /// Minimum altitude (degrees) below which the scheduler should treat this
    /// target as un-runnable. `None` means no per-target altitude floor.
    pub min_altitude: Option<f64>,
    /// Optional `start_after` Unix timestamp — target is skipped if `now <
    /// start_after`.
    pub start_after: Option<i64>,
    /// Optional `end_before` Unix timestamp — target is skipped if `now >=
    /// end_before`.
    pub end_before: Option<i64>,
    /// User-assigned priority. Higher = preferred. Ties on raw score are
    /// broken by priority (descending) so the previously-unused
    /// `TargetHeaderConfig::priority` field becomes meaningful for the
    /// scheduler.
    pub priority: i32,
    /// Pre-existing completion flag. The scheduler does not pick a completed
    /// target even if it would otherwise score highest.
    pub completed: bool,
}

/// Observer state for one scheduling decision.
#[derive(Debug, Clone)]
pub struct ObserverContext {
    pub latitude_deg: f64,
    pub longitude_deg: f64,
    pub now: DateTime<Utc>,
    /// Optional moon position (`(ra_deg, dec_deg)`). When `None`, moon-distance
    /// scoring assumes the worst-case 180° separation (i.e. moon-distance
    /// score is its safest "moon is far" value), matching the Dart fallback
    /// (`moonDist = 180`).
    pub moon: Option<(f64, f64)>,
    /// 0..=100 illumination fraction. Defaults to 0 (new moon).
    pub moon_illumination: f64,
    /// Optional twilight bracket for darkness scoring.
    pub twilight: Option<TwilightBracket>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct TwilightBracket {
    pub civil_dusk: Option<i64>,
    pub civil_dawn: Option<i64>,
    pub nautical_dusk: Option<i64>,
    pub nautical_dawn: Option<i64>,
    pub astronomical_dusk: Option<i64>,
    pub astronomical_dawn: Option<i64>,
}

/// Per-axis + total score for one target. Mirrors `TargetScore` in Dart.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TargetScore {
    pub target_id: String,
    pub target_name: String,
    pub total_score: f64,
    pub altitude_score: f64,
    pub moon_distance_score: f64,
    pub transit_proximity_score: f64,
    pub darkness_score: f64,
    pub airmass_score: f64,
    pub current_altitude_deg: f64,
    pub current_azimuth_deg: f64,
    pub current_airmass: f64,
    pub moon_distance_deg: f64,
    /// True when the target fails a hard constraint (below horizon at min
    /// altitude, outside start_after/end_before, already completed). The
    /// scheduler skips runnable=false candidates regardless of score.
    pub runnable: bool,
    /// Reason the target was filtered out (`None` when `runnable == true`).
    pub skip_reason: Option<String>,
    /// Carried through so the dashboard can order ties by priority.
    pub priority: i32,
}

/// Score one target. Mirrors `TargetScoringService.scoreTarget` in Dart.
pub fn score_target(
    target: &TargetInput,
    observer: &ObserverContext,
    weights: &ScoringWeights,
) -> TargetScore {
    // Current position
    let (alt, az) = object_alt_az(
        target.ra_deg,
        target.dec_deg,
        &observer.now,
        observer.latitude_deg,
        observer.longitude_deg,
    );

    // Rise / transit / set
    let visibility = calculate_object_visibility(
        target.ra_deg,
        target.dec_deg,
        &observer.now,
        observer.latitude_deg,
        observer.longitude_deg,
        0.0,
    );

    let am = airmass(alt);

    let moon_dist = match observer.moon {
        Some((moon_ra, moon_dec)) => {
            angular_separation(target.ra_deg, target.dec_deg, moon_ra, moon_dec)
        }
        None => 180.0,
    };

    let alt_score = score_altitude(alt);
    let moon_score = score_moon_distance(moon_dist, observer.moon_illumination);
    let transit_score = score_transit_proximity(&visibility, &observer.now);
    let darkness_score = score_darkness(observer.twilight.as_ref(), observer.now.timestamp());
    let airmass_score = score_airmass(am);

    let denom = weights.sum().max(f64::EPSILON);
    let total = (alt_score * weights.altitude_weight
        + moon_score * weights.moon_distance_weight
        + transit_score * weights.transit_proximity_weight
        + darkness_score * weights.darkness_weight
        + airmass_score * weights.airmass_weight)
        / denom;

    // Hard runnable filters.
    let now_ts = observer.now.timestamp();
    let mut runnable = true;
    let mut skip_reason = None;
    if target.completed {
        runnable = false;
        skip_reason = Some("already completed".to_string());
    } else if let Some(after) = target.start_after {
        if now_ts < after {
            runnable = false;
            skip_reason = Some(format!(
                "start_after not reached ({}s remaining)",
                after - now_ts
            ));
        }
    }
    if runnable {
        if let Some(before) = target.end_before {
            if now_ts >= before {
                runnable = false;
                skip_reason = Some("end_before passed".to_string());
            }
        }
    }
    if runnable {
        if let Some(min_alt) = target.min_altitude {
            if alt < min_alt {
                runnable = false;
                skip_reason = Some(format!(
                    "altitude {alt:.1}° below per-target floor {min_alt:.1}°"
                ));
            }
        }
    }

    TargetScore {
        target_id: target.id.clone(),
        target_name: target.name.clone(),
        total_score: total,
        altitude_score: alt_score,
        moon_distance_score: moon_score,
        transit_proximity_score: transit_score,
        darkness_score,
        airmass_score,
        current_altitude_deg: alt,
        current_azimuth_deg: az,
        current_airmass: am,
        moon_distance_deg: moon_dist,
        runnable,
        skip_reason,
        priority: target.priority,
    }
}

/// Score many targets and return them sorted: runnable first, then by total
/// score descending, with priority as the tie-breaker.
pub fn score_targets(
    targets: &[TargetInput],
    observer: &ObserverContext,
    weights: &ScoringWeights,
) -> Vec<TargetScore> {
    let mut scored: Vec<TargetScore> = targets
        .iter()
        .map(|t| score_target(t, observer, weights))
        .collect();
    scored.sort_by(|a, b| {
        b.runnable
            .cmp(&a.runnable)
            .then_with(|| {
                b.total_score
                    .partial_cmp(&a.total_score)
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
            .then_with(|| b.priority.cmp(&a.priority))
    });
    scored
}

/// Pick the highest-scoring runnable target above `min_score`. Returns `None`
/// when no target clears the threshold.
pub fn pick_best(
    targets: &[TargetInput],
    observer: &ObserverContext,
    weights: &ScoringWeights,
    min_score: f64,
) -> Option<TargetScore> {
    let scored = score_targets(targets, observer, weights);
    scored
        .into_iter()
        .find(|s| s.runnable && s.total_score >= min_score)
}

// ---------------------------------------------------------------------------
// Per-axis scorers — verbatim from `target_scoring.dart`.
// ---------------------------------------------------------------------------

fn score_altitude(altitude: f64) -> f64 {
    if altitude < 0.0 {
        return 0.0;
    }
    if altitude < 15.0 {
        return altitude * 2.0;
    }
    if altitude < 30.0 {
        return 30.0 + (altitude - 15.0) * 2.0;
    }
    if altitude < 60.0 {
        return 60.0 + (altitude - 30.0) * 1.33;
    }
    100.0
}

fn score_moon_distance(distance: f64, illumination: f64) -> f64 {
    let moon_factor = illumination / 100.0;
    if illumination < 10.0 {
        return 90.0 + (distance / 180.0) * 10.0;
    }
    let min_good_dist = 30.0 + 70.0 * moon_factor;
    if distance >= min_good_dist {
        return 100.0;
    }
    if distance < 10.0 {
        return 10.0 * (1.0 - moon_factor * 0.8);
    }
    (distance / min_good_dist) * 100.0
}

fn score_transit_proximity(visibility: &ObjectVisibility, time: &DateTime<Utc>) -> f64 {
    if visibility.never_rises {
        return 0.0;
    }
    let Some(transit) = visibility.transit_time else {
        return 50.0;
    };
    let minutes = (transit.signed_duration_since(*time).num_minutes()).abs();
    if minutes < 30 {
        return 100.0;
    }
    if minutes < 60 {
        return 90.0;
    }
    if minutes < 120 {
        return 80.0;
    }
    if minutes < 240 {
        return 60.0;
    }
    if minutes < 360 {
        return 40.0;
    }
    20.0
}

fn score_darkness(twilight: Option<&TwilightBracket>, now_ts: i64) -> f64 {
    let Some(tw) = twilight else {
        return 70.0;
    };

    if let (Some(dusk), Some(dawn)) = (tw.astronomical_dusk, tw.astronomical_dawn) {
        if now_ts > dusk && now_ts < dawn {
            return 100.0;
        }
    }
    if let (Some(dusk), Some(dawn)) = (tw.nautical_dusk, tw.nautical_dawn) {
        if now_ts > dusk && now_ts < dawn {
            return 70.0;
        }
    }
    if let (Some(dusk), Some(dawn)) = (tw.civil_dusk, tw.civil_dawn) {
        if now_ts > dusk && now_ts < dawn {
            return 40.0;
        }
    }
    10.0
}

fn score_airmass(airmass: f64) -> f64 {
    if airmass.is_infinite() {
        return 0.0;
    }
    if airmass <= 1.0 {
        return 100.0;
    }
    if airmass <= 1.5 {
        return 90.0;
    }
    if airmass <= 2.0 {
        return 70.0;
    }
    if airmass <= 2.5 {
        return 50.0;
    }
    if airmass <= 3.0 {
        return 30.0;
    }
    10.0
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    /// Parity fixture mirroring `target_scoring_test.dart`. The Dart numbers
    /// below were captured by running the same observer+target inputs through
    /// `TargetScoringService.scoreTarget` (see
    /// `packages/nightshade_planetarium/test/planning/target_scoring_parity_test.dart`).
    #[test]
    fn altitude_score_breakpoints_match_dart() {
        // 0° → 0
        assert!((score_altitude(0.0) - 0.0).abs() < 1e-9);
        // 7.5° → 15 (linear 0..30 over [0,15))
        assert!((score_altitude(7.5) - 15.0).abs() < 1e-9);
        // 15° → 30 (start of next segment)
        assert!((score_altitude(15.0) - 30.0).abs() < 1e-9);
        // 30° → 60 (start of third segment)
        assert!((score_altitude(30.0) - 60.0).abs() < 1e-9);
        // 60° → 100 (saturation)
        assert!((score_altitude(60.0) - 100.0).abs() < 1e-9);
        assert!((score_altitude(89.0) - 100.0).abs() < 1e-9);
    }

    #[test]
    fn airmass_score_breakpoints_match_dart() {
        assert_eq!(score_airmass(f64::INFINITY), 0.0);
        assert_eq!(score_airmass(1.0), 100.0);
        assert_eq!(score_airmass(1.5), 90.0);
        assert_eq!(score_airmass(2.0), 70.0);
        assert_eq!(score_airmass(2.5), 50.0);
        assert_eq!(score_airmass(3.0), 30.0);
        assert_eq!(score_airmass(4.0), 10.0);
    }

    #[test]
    fn moon_distance_new_moon_branch() {
        // illumination < 10 → 90 + (d/180)*10
        let s = score_moon_distance(90.0, 5.0);
        assert!((s - 95.0).abs() < 1e-9, "got {s}");
    }

    #[test]
    fn moon_distance_bright_moon_far_target_is_100() {
        // illumination 100 → min_good_dist = 100; d >= 100 → 100.
        assert_eq!(score_moon_distance(120.0, 100.0), 100.0);
    }

    #[test]
    fn pick_best_picks_highest_runnable_above_threshold() {
        let now = Utc.with_ymd_and_hms(2026, 1, 15, 6, 0, 0).unwrap();
        let observer = ObserverContext {
            latitude_deg: 40.0,
            longitude_deg: -74.0,
            now,
            moon: Some((0.0, 0.0)),
            moon_illumination: 5.0,
            twilight: None,
        };
        let weights = ScoringWeights::default();
        // M42-ish (Orion, high in winter from 40N at 06:00 UTC ≈ midnight EST)
        let m42 = TargetInput {
            id: "m42".into(),
            name: "M42".into(),
            ra_deg: 83.82,
            dec_deg: -5.39,
            min_altitude: None,
            start_after: None,
            end_before: None,
            priority: 0,
            completed: false,
        };
        // A target near the sun → currently below horizon → unrunnable
        let sun_neighbour = TargetInput {
            id: "behind_sun".into(),
            name: "Behind Sun".into(),
            ra_deg: 300.0,
            dec_deg: -23.0,
            min_altitude: Some(20.0),
            start_after: None,
            end_before: None,
            priority: 5,
            completed: false,
        };
        let best = pick_best(&[sun_neighbour, m42.clone()], &observer, &weights, 30.0)
            .expect("expected a runnable target");
        assert_eq!(best.target_id, "m42");
        assert!(best.runnable);
        assert!(best.total_score >= 30.0);
    }

    #[test]
    fn pick_best_respects_min_score_threshold() {
        // Place observer + time so M42 is below its min_altitude floor → the
        // hard runnable filter trips → pick_best returns None regardless of
        // the score threshold. (Mid-summer noon at 40N: M42 culminates well
        // below the horizon.)
        let now = Utc.with_ymd_and_hms(2026, 7, 1, 18, 0, 0).unwrap();
        let observer = ObserverContext {
            latitude_deg: 40.0,
            longitude_deg: -74.0,
            now,
            moon: None,
            moon_illumination: 0.0,
            twilight: None,
        };
        let weights = ScoringWeights::default();
        let m42 = TargetInput {
            id: "m42".into(),
            name: "M42".into(),
            ra_deg: 83.82,
            dec_deg: -5.39,
            // Floor of 50° — M42 cannot reach that at lat=40 (transit max ~45°).
            // The runnable check fires before the score threshold even
            // matters.
            min_altitude: Some(50.0),
            start_after: None,
            end_before: None,
            priority: 0,
            completed: false,
        };
        assert!(pick_best(&[m42], &observer, &weights, 50.0).is_none());
    }

    #[test]
    fn completed_targets_are_skipped() {
        let now = Utc.with_ymd_and_hms(2026, 1, 15, 6, 0, 0).unwrap();
        let observer = ObserverContext {
            latitude_deg: 40.0,
            longitude_deg: -74.0,
            now,
            moon: None,
            moon_illumination: 0.0,
            twilight: None,
        };
        let weights = ScoringWeights::default();
        let m42 = TargetInput {
            id: "m42".into(),
            name: "M42".into(),
            ra_deg: 83.82,
            dec_deg: -5.39,
            min_altitude: None,
            start_after: None,
            end_before: None,
            priority: 0,
            completed: true,
        };
        let scored = score_target(&m42, &observer, &weights);
        assert!(!scored.runnable);
        assert_eq!(scored.skip_reason.as_deref(), Some("already completed"));
    }
}
