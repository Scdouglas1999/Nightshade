//! Per-frame snapshot assembly and ArcSwap publish hook.

use crate::astrometry::frames::radec_from_icrs_dir;
use crate::astrometry::time::AstroTime;
use crate::catalog::constellation_lines::{icrs_dir_from_j2000, CONSTELLATIONS};
use crate::catalog::variable_stars::{brighter_than, icrs_dir, VariableStar};
use crate::catalog::CatalogSet;
use crate::scene::dev_catalog::DEV_STARS;
use crate::scene::lod::{frame_star_mag_limit, MagLimitConfig, QualityConfig};
use crate::scene::pose::{body_equatorial_rad, BodyId};
use crate::scene::projection::project_icrs;
use crate::scene::snapshot::ConstellationArtPlacement;
use crate::scene::{
    publish, LabelCategory, LabelHint, SceneSnapshot, SelectedObject, SmallString, SnapshotSlot,
};
use crate::types::{RenderConfig, ViewPose};

/// Upper bound on how many star labels enter the snapshot per frame. The
/// renderer can comfortably draw 100k stars, but the Dart-side
/// `LabelLayer` runs an overlap-resolution layout per label per frame —
/// at 10k+ labels the layout alone burns several ms. Stellarium-style
/// label density tops out well below 500 visible labels at any one zoom;
/// 400 leaves headroom while keeping per-frame `format!("HIP {hip_id}")`
/// allocations bounded.
const MAX_STAR_LABELS: usize = 400;

/// Inputs required to build and publish one frame snapshot.
#[derive(Debug, Clone)]
pub struct SnapshotInputs {
    /// Monotonic frame counter for this publish.
    pub frame_id: u64,
    /// Camera pose used for projection.
    pub view_pose: ViewPose,
    /// Astronomical time for this frame.
    pub astro_time: AstroTime,
    /// Observer site for this frame.
    pub observer: crate::types::Observer,
    /// Layer visibility and magnitude limit.
    pub render_config: RenderConfig,
    /// Active selection, if any (screen position is refreshed each frame).
    pub selected: Option<SelectedObject>,
}

/// Builds a [`SceneSnapshot`] with projected labels and constellation art from catalogs and astrometry.
pub fn build_snapshot(catalog: &CatalogSet, inputs: SnapshotInputs) -> SceneSnapshot {
    let labels = collect_all_labels(catalog, &inputs);
    let constellation_art = collect_constellation_art(&inputs.view_pose, &inputs.render_config);
    let selected = inputs
        .selected
        .map(|sel| project_selected(sel, inputs.view_pose));

    SceneSnapshot {
        frame_id: inputs.frame_id,
        view_pose: inputs.view_pose,
        astro_time: inputs.astro_time,
        observer: inputs.observer,
        labels,
        constellation_art,
        selected,
    }
}

/// Publishes a snapshot into the lock-free slot (called once per rendered frame).
pub fn publish_snapshot(slot: &SnapshotSlot, catalog: &CatalogSet, inputs: SnapshotInputs) {
    publish(slot, build_snapshot(catalog, inputs));
}

fn collect_all_labels(catalog: &CatalogSet, inputs: &SnapshotInputs) -> Vec<LabelHint> {
    let mut labels = Vec::new();
    labels.extend(collect_star_labels(
        catalog,
        &inputs.view_pose,
        &inputs.render_config,
    ));
    labels.extend(collect_constellation_name_labels(
        &inputs.view_pose,
        &inputs.render_config,
    ));
    labels.extend(collect_body_labels(
        inputs.astro_time,
        &inputs.view_pose,
        &inputs.render_config,
    ));
    labels.extend(collect_variable_star_labels(
        &inputs.view_pose,
        &inputs.render_config,
    ));
    labels
}

fn collect_star_labels(
    catalog: &CatalogSet,
    view_pose: &ViewPose,
    config: &RenderConfig,
) -> Vec<LabelHint> {
    if !config.show_stars {
        return Vec::new();
    }

    if catalog.is_empty() {
        return collect_dev_star_labels(view_pose, config);
    }

    // Use the FOV-aware label cutoff. Without this we'd format a name for
    // every star up to the user's wide-field baseline (default 11.0 →
    // tens of thousands of allocations per frame). Label cutoff is one
    // magnitude brighter than the render cutoff because faint stars
    // shouldn't carry textual labels even when they're drawn — that
    // matches Stellarium's label density.
    let render_limit = frame_star_mag_limit(
        view_pose.fov_rad,
        QualityConfig::from_tier(config.quality),
        MagLimitConfig::new(config.magnitude_limit),
    );
    let label_limit = (render_limit - 1.0).max(2.0);

    // First pass: collect *only the brightest* candidates within the
    // visibility cone. The catalog query already iterates in pack-order;
    // we keep a fixed-size min-heap by (apparent_mag, hip_id) so the
    // output is the brightest `MAX_STAR_LABELS` after culling — without
    // formatting names for the rejects.
    let mut shortlist: Vec<(f32, u32, [f32; 3])> = Vec::with_capacity(MAX_STAR_LABELS + 8);
    let query = catalog
        .query(*view_pose, label_limit)
        .expect("catalog visibility query must not fail with registered packs");
    for hit in query {
        let mag = hit.star.mag;
        if shortlist.len() < MAX_STAR_LABELS {
            shortlist.push((mag, hit.star.hip_id, hit.star.icrs_dir));
            if shortlist.len() == MAX_STAR_LABELS {
                // First time at capacity: switch to max-mag eviction. Sort
                // ascending by magnitude so worst (faintest, highest mag)
                // is at the end.
                shortlist.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
            }
            continue;
        }
        // Compare against worst (faintest) entry.
        let worst_mag = shortlist.last().expect("non-empty").0;
        if mag >= worst_mag {
            continue;
        }
        // Insert in sorted order, pop the worst.
        let pos = shortlist
            .binary_search_by(|probe| {
                probe.0.partial_cmp(&mag).unwrap_or(std::cmp::Ordering::Equal)
            })
            .unwrap_or_else(|e| e);
        shortlist.insert(pos, (mag, hit.star.hip_id, hit.star.icrs_dir));
        shortlist.pop();
    }

    // Second pass: project, format names, build LabelHints. At most
    // `MAX_STAR_LABELS` allocations — bounded regardless of catalog size.
    let mut labels = Vec::with_capacity(shortlist.len());
    for (mag, hip_id, icrs_dir) in shortlist {
        let (ra_rad, dec_rad) = radec_from_icrs_dir(icrs_dir);
        let Some((screen_x, screen_y)) = project_icrs(ra_rad, dec_rad, *view_pose) else {
            continue;
        };
        labels.push(LabelHint {
            object_id: u64::from(hip_id),
            screen_x,
            screen_y,
            apparent_mag: mag,
            priority: label_priority(mag),
            text: star_display_name(hip_id),
            category: LabelCategory::Star,
        });
    }
    labels
}

fn collect_dev_star_labels(view_pose: &ViewPose, config: &RenderConfig) -> Vec<LabelHint> {
    let mut labels = Vec::with_capacity(DEV_STARS.len());
    for star in DEV_STARS {
        if star.mag > config.magnitude_limit {
            continue;
        }
        let Some((screen_x, screen_y)) = project_icrs(star.ra_rad, star.dec_rad, *view_pose) else {
            continue;
        };
        labels.push(LabelHint {
            object_id: star.hip,
            screen_x,
            screen_y,
            apparent_mag: star.mag,
            priority: label_priority(star.mag),
            text: SmallString::new(star.name),
            category: LabelCategory::Star,
        });
    }
    labels
}

fn collect_constellation_name_labels(
    view_pose: &ViewPose,
    config: &RenderConfig,
) -> Vec<LabelHint> {
    if !config.show_constellations {
        return Vec::new();
    }

    let mut labels = Vec::new();
    for (index, c) in CONSTELLATIONS.iter().enumerate() {
        let ra_rad = f64::from(c.center_ra_hours) * (std::f64::consts::PI / 12.0);
        let dec_rad = f64::from(c.center_dec_deg).to_radians();
        let Some((screen_x, screen_y)) = project_icrs(ra_rad, dec_rad, *view_pose) else {
            continue;
        };
        labels.push(LabelHint {
            object_id: constellation_object_id(index),
            screen_x,
            screen_y,
            apparent_mag: 4.0,
            priority: 40,
            text: SmallString::new(c.name),
            category: LabelCategory::Constellation,
        });
    }
    labels
}

fn collect_body_labels(
    time: AstroTime,
    view_pose: &ViewPose,
    config: &RenderConfig,
) -> Vec<LabelHint> {
    if !config.show_solar_system {
        return Vec::new();
    }

    let bodies: &[(BodyId, &str, f32)] = &[
        (BodyId::Sun, "Sun", -26.7),
        (BodyId::Moon, "Moon", -12.0),
        (BodyId::Mercury, "Mercury", 0.0),
        (BodyId::Venus, "Venus", -4.0),
        (BodyId::Mars, "Mars", 0.0),
        (BodyId::Jupiter, "Jupiter", -2.0),
        (BodyId::Saturn, "Saturn", 0.5),
    ];

    let mut labels = Vec::with_capacity(bodies.len());
    for &(body, name, mag) in bodies {
        let (ra_rad, dec_rad) = match body_equatorial_rad(body, time) {
            Ok(v) => v,
            Err(err) => {
                tracing::error!("body label {name}: {err}");
                continue;
            }
        };
        let Some((screen_x, screen_y)) = project_icrs(ra_rad, dec_rad, *view_pose) else {
            continue;
        };
        labels.push(LabelHint {
            object_id: body_object_id(body),
            screen_x,
            screen_y,
            apparent_mag: mag,
            priority: label_priority(mag),
            text: SmallString::new(name),
            category: LabelCategory::Body,
        });
    }
    labels
}

fn collect_variable_star_labels(view_pose: &ViewPose, config: &RenderConfig) -> Vec<LabelHint> {
    if !config.show_variable_stars {
        return Vec::new();
    }

    let mut labels = Vec::new();
    for star in brighter_than(config.magnitude_limit) {
        let Some(label) = variable_star_label(star, view_pose) else {
            continue;
        };
        labels.push(label);
    }
    labels
}

fn variable_star_label(star: &VariableStar, view_pose: &ViewPose) -> Option<LabelHint> {
    let dir = icrs_dir(star);
    let (ra_rad, dec_rad) = radec_from_icrs_dir(dir);
    let (screen_x, screen_y) = project_icrs(ra_rad, dec_rad, *view_pose)?;
    Some(LabelHint {
        object_id: variable_star_object_id(star.name),
        screen_x,
        screen_y,
        apparent_mag: star.mag_max,
        priority: label_priority(star.mag_max),
        text: SmallString::new(star.name),
        category: LabelCategory::Star,
    })
}

fn collect_constellation_art(
    view_pose: &ViewPose,
    config: &RenderConfig,
) -> Vec<ConstellationArtPlacement> {
    if !config.show_constellation_art {
        return Vec::new();
    }

    let scale = art_scale_for_fov(view_pose.fov_rad);
    let mut placements = Vec::new();
    for c in CONSTELLATIONS {
        let ra_rad = f64::from(c.center_ra_hours) * (std::f64::consts::PI / 12.0);
        let dec_rad = f64::from(c.center_dec_deg).to_radians();
        let Some((screen_x, screen_y)) = project_icrs(ra_rad, dec_rad, *view_pose) else {
            continue;
        };
        let segment_visible = c.segments.iter().any(|seg| {
            let start = icrs_dir_from_j2000(seg.start_ra_hours, seg.start_dec_deg);
            let end = icrs_dir_from_j2000(seg.end_ra_hours, seg.end_dec_deg);
            let (ra_s, dec_s) = radec_from_icrs_dir(start);
            let (ra_e, dec_e) = radec_from_icrs_dir(end);
            project_icrs(ra_s, dec_s, *view_pose).is_some()
                || project_icrs(ra_e, dec_e, *view_pose).is_some()
        });
        if !segment_visible {
            continue;
        }
        placements.push(ConstellationArtPlacement {
            abbrev: SmallString::new(c.abbrev),
            screen_x,
            screen_y,
            scale,
            opacity: 0.2,
        });
    }
    placements
}

fn star_display_name(hip_id: u32) -> SmallString {
    DEV_STARS
        .iter()
        .find(|s| s.hip == u64::from(hip_id))
        .map(|s| SmallString::new(s.name))
        .unwrap_or_else(|| SmallString::new(format!("HIP {hip_id}")))
}

fn project_selected(mut sel: SelectedObject, view_pose: ViewPose) -> SelectedObject {
    if let Some((screen_x, screen_y)) = project_icrs(sel.ra_rad, sel.dec_rad, view_pose) {
        sel.screen_x = screen_x;
        sel.screen_y = screen_y;
    }
    sel
}

fn label_priority(apparent_mag: f32) -> u8 {
    (10.0 - apparent_mag).clamp(0.0, 255.0) as u8
}

fn art_scale_for_fov(fov_rad: f32) -> f32 {
    (fov_rad / std::f32::consts::FRAC_PI_2).clamp(0.35, 2.5)
}

const fn constellation_object_id(index: usize) -> u64 {
    0xC0_00_0000 | (index as u64)
}

const fn body_object_id(body: BodyId) -> u64 {
    0xB0_00_0000 | (body as u64)
}

fn variable_star_object_id(name: &str) -> u64 {
    let mut hash = 0xD0_00_0000_u64;
    for b in name.bytes() {
        hash = hash.wrapping_mul(31).wrapping_add(u64::from(b));
    }
    hash
}
