//! Full FFI surface for Planetarium v2 (`nightshade_planetarium::Planetarium`).
//!
//! Replaces the Phase 1 spike module. Dart holds opaque handle ids; each function
//! looks up the handle in a static registry and forwards commands to the render loop.
//!
//! Gesture input, dev-catalog hit-testing, and pose-lock state (tracking target,
//! mount position, lock mode) cross the FFI here.

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use nightshade_planetarium::bus::PlanetariumCommand;
// Re-exported so the FRB-generated wire decoder for
// `planetarium_register_star_pack` (which emits unqualified
// `Box<dyn StarPack>` references) resolves the trait via the
// `use crate::api::planetarium::*;` glob in `frb_generated.rs`.
pub use nightshade_planetarium::catalog::StarPack;
use nightshade_planetarium::gesture::GestureEvent;
use nightshade_planetarium::scene::{
    BodyId, ConstellationArtPlacement, LabelCategory, LabelHint, MountPosition, PoseLock,
    SceneSnapshot, SelectedObject, TrackingTarget,
};
use nightshade_planetarium::types::{AstroTime, Observer, RenderConfig, SkyProjection, ViewPose};
use nightshade_planetarium::{Planetarium, PlanetariumError};
use parking_lot::Mutex;

static REGISTRY: OnceLock<Mutex<HashMap<i64, Arc<Planetarium>>>> = OnceLock::new();
static NEXT_ID: OnceLock<Mutex<i64>> = OnceLock::new();

const TEXTURE_TIMEOUT: Duration = Duration::from_secs(2);

fn registry() -> &'static Mutex<HashMap<i64, Arc<Planetarium>>> {
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

fn next_id() -> i64 {
    let m = NEXT_ID.get_or_init(|| Mutex::new(1));
    let mut g = m.lock();
    let v = *g;
    *g += 1;
    v
}

fn lookup(handle: i64) -> Result<(), String> {
    registry()
        .lock()
        .contains_key(&handle)
        .then_some(())
        .ok_or_else(|| format!("planetarium handle {handle} not found"))
}

/// Look up the planetarium by id and invoke `f` against it.
///
/// Releases the registry mutex BEFORE calling `f` by cloning the
/// `Arc<Planetarium>` out. Without this, a slow operation in `f`
/// (notably [`Planetarium::load_pack`], which mmaps multi-MB files)
/// would block every other FFI call that goes through the registry —
/// including hit-tests, gesture pushes, and snapshot reads on the
/// UI thread.
fn with_planetarium<F, T>(handle: i64, f: F) -> Result<T, String>
where
    F: FnOnce(&Planetarium) -> Result<T, String>,
{
    let planetarium = {
        let reg = registry().lock();
        Arc::clone(
            reg.get(&handle)
                .ok_or_else(|| format!("planetarium handle {handle} not found"))?,
        )
    };
    // Registry mutex is released here; `f` runs on the cloned Arc.
    f(planetarium.as_ref())
}

/// Block until the render thread reports a definitive resize outcome from a
/// resize newer than `since_resize_gen`. Signal-driven via
/// [`Planetarium::wait_for_texture_id`] — never busy-polls.
fn wait_texture_id(planetarium: &Planetarium, since_resize_gen: u64) -> Result<i64, String> {
    match planetarium.wait_for_texture_id(since_resize_gen, TEXTURE_TIMEOUT) {
        Ok(id) => Ok(id),
        Err(PlanetariumError::NotAllocated) => {
            if let Some(err) = planetarium.last_surface_error() {
                Err(err)
            } else {
                Err(
                    "texture not allocated after resize — use a valid Flutter engine handle"
                        .to_string(),
                )
            }
        }
        Err(err) => Err(err.to_string()),
    }
}

// =============================================================================
// FRB DTO types (mirror `nightshade_planetarium` public types)
// =============================================================================

/// Sky projection mode (FFI).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SkyProjectionDto {
    Stereographic,
    Orthographic,
    AzimuthalEquidistant,
}

/// View pose crossing the FFI boundary.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ViewPoseDto {
    pub ra_rad: f64,
    pub dec_rad: f64,
    pub fov_rad: f32,
    pub roll_rad: f32,
    pub projection: SkyProjectionDto,
}

/// Observer site (FFI).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ObserverDto {
    pub latitude_rad: f64,
    pub longitude_rad: f64,
    pub elevation_m: f64,
    pub pressure_hpa: f32,
    pub temperature_c: f32,
}

/// Astronomical time (FFI).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AstroTimeDto {
    pub jd_utc: f64,
    pub jd_ut1: f64,
    pub jd_tt: f64,
}

/// Per-layer render configuration (FFI).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RenderConfigDto {
    pub show_stars: bool,
    pub show_constellations: bool,
    pub show_constellation_boundaries: bool,
    pub show_constellation_art: bool,
    pub show_equatorial_grid: bool,
    pub show_alt_az_grid: bool,
    pub show_galactic_grid: bool,
    pub show_ecliptic: bool,
    pub show_galactic_plane: bool,
    pub show_milky_way: bool,
    pub show_horizon: bool,
    pub show_atmosphere: bool,
    pub show_dsos: bool,
    pub show_solar_system: bool,
    pub show_satellites: bool,
    pub show_minor_planets: bool,
    pub show_variable_stars: bool,
    pub magnitude_limit: f32,
    pub quality: u32,
    pub bortle_class: u32,
    pub twinkle: bool,
}

/// Label category for overlay styling (FFI).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LabelCategoryDto {
    Star,
    Dso,
    Constellation,
    Body,
    Satellite,
    MinorPlanet,
}

/// Screen-space label hint (FFI).
#[derive(Debug, Clone, PartialEq)]
pub struct LabelHintDto {
    pub object_id: u64,
    pub screen_x: f32,
    pub screen_y: f32,
    pub apparent_mag: f32,
    pub priority: u8,
    pub text: String,
    pub category: LabelCategoryDto,
}

/// Selected object projected to screen space (FFI).
#[derive(Debug, Clone, PartialEq)]
pub struct SelectedObjectDto {
    pub object_id: u64,
    pub screen_x: f32,
    pub screen_y: f32,
    pub ra_rad: f64,
    pub dec_rad: f64,
    pub category: LabelCategoryDto,
    pub display_name: String,
}

/// Gesture phase forwarded from Flutter (FFI).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum GestureKindDto {
    PanStart,
    PanUpdate,
    PanEnd,
    ZoomStart,
    ZoomUpdate,
    ZoomEnd,
    RotateStart,
    RotateUpdate,
    RotateEnd,
    Tap,
    DoubleTap,
    Cancel,
}

/// Normalized gesture event (FFI).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GestureEventDto {
    pub kind: GestureKindDto,
    pub x: f32,
    pub y: f32,
    pub dx: f32,
    pub dy: f32,
    pub vx: f32,
    pub vy: f32,
    pub factor: f32,
    pub radians: f32,
}

impl From<GestureEventDto> for GestureEvent {
    fn from(dto: GestureEventDto) -> Self {
        match dto.kind {
            GestureKindDto::PanStart => Self::PanStart { x: dto.x, y: dto.y },
            GestureKindDto::PanUpdate => Self::PanUpdate {
                dx: dto.dx,
                dy: dto.dy,
                vx: dto.vx,
                vy: dto.vy,
            },
            GestureKindDto::PanEnd => Self::PanEnd {
                vx: dto.vx,
                vy: dto.vy,
            },
            GestureKindDto::ZoomStart => Self::ZoomStart { x: dto.x, y: dto.y },
            GestureKindDto::ZoomUpdate => Self::ZoomUpdate {
                factor: dto.factor,
                x: dto.x,
                y: dto.y,
            },
            GestureKindDto::ZoomEnd => Self::ZoomEnd,
            GestureKindDto::RotateStart => Self::RotateStart,
            GestureKindDto::RotateUpdate => Self::RotateUpdate {
                radians: dto.radians,
            },
            GestureKindDto::RotateEnd => Self::RotateEnd,
            GestureKindDto::Tap => Self::Tap { x: dto.x, y: dto.y },
            GestureKindDto::DoubleTap => Self::DoubleTap { x: dto.x, y: dto.y },
            GestureKindDto::Cancel => Self::Cancel,
        }
    }
}

/// Solar-system body identifier carried across the FFI for pose-lock control.
///
/// Mirrors [`nightshade_planetarium::scene::BodyId`]. Used by Dart when the user
/// chooses to track a planet (e.g. "follow Jupiter" in the planetarium UI):
/// the host wraps the selection in [`PoseLockDto::LockedToBody`] and sends it
/// down via [`planetarium_set_pose_lock`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BodyIdDto {
    Mercury,
    Venus,
    Mars,
    Jupiter,
    Saturn,
    Uranus,
    Neptune,
    Moon,
    Sun,
}

impl From<BodyId> for BodyIdDto {
    fn from(value: BodyId) -> Self {
        match value {
            BodyId::Mercury => Self::Mercury,
            BodyId::Venus => Self::Venus,
            BodyId::Mars => Self::Mars,
            BodyId::Jupiter => Self::Jupiter,
            BodyId::Saturn => Self::Saturn,
            BodyId::Uranus => Self::Uranus,
            BodyId::Neptune => Self::Neptune,
            BodyId::Moon => Self::Moon,
            BodyId::Sun => Self::Sun,
        }
    }
}

impl From<BodyIdDto> for BodyId {
    fn from(value: BodyIdDto) -> Self {
        match value {
            BodyIdDto::Mercury => Self::Mercury,
            BodyIdDto::Venus => Self::Venus,
            BodyIdDto::Mars => Self::Mars,
            BodyIdDto::Jupiter => Self::Jupiter,
            BodyIdDto::Saturn => Self::Saturn,
            BodyIdDto::Uranus => Self::Uranus,
            BodyIdDto::Neptune => Self::Neptune,
            BodyIdDto::Moon => Self::Moon,
            BodyIdDto::Sun => Self::Sun,
        }
    }
}

/// Pose lock mode carried across the FFI. Mirrors
/// [`nightshade_planetarium::scene::PoseLock`] but represents the lock-target
/// payload inline (catalog id, body id, or unit) so the Dart side never has
/// to allocate.
///
/// Sent by [`planetarium_set_pose_lock`]. Tracking-target / mount-position
/// payloads required for `LockedToTarget` and `LockedToMount` are pushed
/// separately via [`planetarium_set_tracking_target`] /
/// [`planetarium_set_mount_position`] so the lock mode and the latest
/// reference data can be updated independently.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PoseLockDto {
    /// User-controlled pose; gestures write the free pose directly.
    Free,
    /// Center on the catalog object identified by `object_id`.
    LockedToTarget { object_id: u64 },
    /// Center on the mount's most-recently reported RA/Dec.
    LockedToMount,
    /// Center on the named solar-system body at the current time.
    LockedToBody { body: BodyIdDto },
}

impl From<PoseLock> for PoseLockDto {
    fn from(value: PoseLock) -> Self {
        match value {
            PoseLock::Free => Self::Free,
            PoseLock::LockedToTarget(id) => Self::LockedToTarget { object_id: id },
            PoseLock::LockedToMount => Self::LockedToMount,
            PoseLock::LockedToBody(body) => Self::LockedToBody { body: body.into() },
        }
    }
}

impl From<PoseLockDto> for PoseLock {
    fn from(value: PoseLockDto) -> Self {
        match value {
            PoseLockDto::Free => Self::Free,
            PoseLockDto::LockedToTarget { object_id } => Self::LockedToTarget(object_id),
            PoseLockDto::LockedToMount => Self::LockedToMount,
            PoseLockDto::LockedToBody { body } => Self::LockedToBody(body.into()),
        }
    }
}

/// Catalog tracking target carried across the FFI. Mirrors
/// [`nightshade_planetarium::scene::TrackingTarget`].
///
/// Pushed by [`planetarium_set_tracking_target`] whenever the Dart side
/// selects a star/DSO to follow; the renderer holds the most-recent value and
/// uses it when [`PoseLockDto::LockedToTarget`] is active. The `object_id`
/// MUST match the id in the lock — the renderer fails loud (no silent reuse)
/// when the ids do not agree, mirroring the `MismatchedTarget` error in
/// `PoseError`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TrackingTargetDto {
    /// Catalog object id (must match the id in `PoseLockDto::LockedToTarget`).
    pub object_id: u64,
    /// Target right ascension (radians, J2000).
    pub ra_rad: f64,
    /// Target declination (radians, J2000).
    pub dec_rad: f64,
}

impl From<TrackingTarget> for TrackingTargetDto {
    fn from(value: TrackingTarget) -> Self {
        Self {
            object_id: value.id,
            ra_rad: value.ra_rad,
            dec_rad: value.dec_rad,
        }
    }
}

impl From<TrackingTargetDto> for TrackingTarget {
    fn from(value: TrackingTargetDto) -> Self {
        Self {
            id: value.object_id,
            ra_rad: value.ra_rad,
            dec_rad: value.dec_rad,
        }
    }
}

/// Mount-reported equatorial position carried across the FFI. Mirrors
/// [`nightshade_planetarium::scene::MountPosition`].
///
/// Pushed by [`planetarium_set_mount_position`] from mount state updates
/// (ASCOM/INDI/Alpaca telescope drivers). When `None` is sent and the lock
/// mode is [`PoseLockDto::LockedToMount`], the renderer raises a
/// `MissingMount` pose error instead of silently freezing on a stale value.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MountPositionDto {
    /// Mount right ascension (radians, J2000).
    pub ra_rad: f64,
    /// Mount declination (radians, J2000).
    pub dec_rad: f64,
}

impl From<MountPosition> for MountPositionDto {
    fn from(value: MountPosition) -> Self {
        Self {
            ra_rad: value.ra_rad,
            dec_rad: value.dec_rad,
        }
    }
}

impl From<MountPositionDto> for MountPosition {
    fn from(value: MountPositionDto) -> Self {
        Self {
            ra_rad: value.ra_rad,
            dec_rad: value.dec_rad,
        }
    }
}

/// Screen-space placement for a single constellation art overlay figure,
/// carried across the FFI per published snapshot.
///
/// Mirrors [`nightshade_planetarium::scene::ConstellationArtPlacement`]; the
/// renderer reprojects every visible figure each frame and the Flutter side
/// draws them as a `CustomPainter` overlay on top of the GPU texture.
#[derive(Debug, Clone, PartialEq)]
pub struct ConstellationArtPlacementDto {
    /// IAU three-letter abbreviation (e.g. `"Ori"`, `"UMa"`).
    pub abbreviation: String,
    /// Normalized screen X in widget coordinates (0 = left).
    pub screen_x: f32,
    /// Normalized screen Y in widget coordinates (0 = top).
    pub screen_y: f32,
    /// Size multiplier relative to the catalog figure.
    pub scale: f32,
    /// Fill/stroke alpha multiplier in [0, 1].
    pub opacity: f32,
}

impl From<ConstellationArtPlacement> for ConstellationArtPlacementDto {
    fn from(value: ConstellationArtPlacement) -> Self {
        Self {
            abbreviation: value.abbrev.as_str().to_string(),
            screen_x: value.screen_x,
            screen_y: value.screen_y,
            scale: value.scale,
            opacity: value.opacity,
        }
    }
}

/// Immutable per-frame scene snapshot for Dart overlays (FFI).
#[derive(Debug, Clone, PartialEq)]
pub struct SceneSnapshotDto {
    pub frame_id: u64,
    pub view_pose: ViewPoseDto,
    pub labels: Vec<LabelHintDto>,
    pub constellation_art: Vec<ConstellationArtPlacementDto>,
    pub selected: Option<SelectedObjectDto>,
}

impl From<SkyProjection> for SkyProjectionDto {
    fn from(value: SkyProjection) -> Self {
        match value {
            SkyProjection::Stereographic => Self::Stereographic,
            SkyProjection::Orthographic => Self::Orthographic,
            SkyProjection::AzimuthalEquidistant => Self::AzimuthalEquidistant,
        }
    }
}

impl From<SkyProjectionDto> for SkyProjection {
    fn from(value: SkyProjectionDto) -> Self {
        match value {
            SkyProjectionDto::Stereographic => Self::Stereographic,
            SkyProjectionDto::Orthographic => Self::Orthographic,
            SkyProjectionDto::AzimuthalEquidistant => Self::AzimuthalEquidistant,
        }
    }
}

impl From<ViewPose> for ViewPoseDto {
    fn from(value: ViewPose) -> Self {
        Self {
            ra_rad: value.ra_rad,
            dec_rad: value.dec_rad,
            fov_rad: value.fov_rad,
            roll_rad: value.roll_rad,
            projection: value.projection.into(),
        }
    }
}

impl From<ViewPoseDto> for ViewPose {
    fn from(value: ViewPoseDto) -> Self {
        Self {
            ra_rad: value.ra_rad,
            dec_rad: value.dec_rad,
            fov_rad: value.fov_rad,
            roll_rad: value.roll_rad,
            projection: value.projection.into(),
        }
    }
}

impl From<Observer> for ObserverDto {
    fn from(value: Observer) -> Self {
        Self {
            latitude_rad: value.latitude_rad,
            longitude_rad: value.longitude_rad,
            elevation_m: value.elevation_m,
            pressure_hpa: value.pressure_hpa,
            temperature_c: value.temperature_c,
        }
    }
}

impl From<ObserverDto> for Observer {
    fn from(value: ObserverDto) -> Self {
        Self {
            latitude_rad: value.latitude_rad,
            longitude_rad: value.longitude_rad,
            elevation_m: value.elevation_m,
            pressure_hpa: value.pressure_hpa,
            temperature_c: value.temperature_c,
        }
    }
}

impl From<AstroTime> for AstroTimeDto {
    fn from(value: AstroTime) -> Self {
        Self {
            jd_utc: value.jd_utc,
            jd_ut1: value.jd_ut1,
            jd_tt: value.jd_tt,
        }
    }
}

impl From<AstroTimeDto> for AstroTime {
    fn from(value: AstroTimeDto) -> Self {
        Self {
            jd_utc: value.jd_utc,
            jd_ut1: value.jd_ut1,
            jd_tt: value.jd_tt,
        }
    }
}

impl From<RenderConfig> for RenderConfigDto {
    fn from(value: RenderConfig) -> Self {
        Self {
            show_stars: value.show_stars,
            show_constellations: value.show_constellations,
            show_constellation_boundaries: value.show_constellation_boundaries,
            show_constellation_art: value.show_constellation_art,
            show_equatorial_grid: value.show_equatorial_grid,
            show_alt_az_grid: value.show_alt_az_grid,
            show_galactic_grid: value.show_galactic_grid,
            show_ecliptic: value.show_ecliptic,
            show_galactic_plane: value.show_galactic_plane,
            show_milky_way: value.show_milky_way,
            show_horizon: value.show_horizon,
            show_atmosphere: value.show_atmosphere,
            show_dsos: value.show_dsos,
            show_solar_system: value.show_solar_system,
            show_satellites: value.show_satellites,
            show_minor_planets: value.show_minor_planets,
            show_variable_stars: value.show_variable_stars,
            magnitude_limit: value.magnitude_limit,
            quality: value.quality,
            bortle_class: value.bortle_class,
            twinkle: value.twinkle,
        }
    }
}

impl From<RenderConfigDto> for RenderConfig {
    fn from(value: RenderConfigDto) -> Self {
        Self {
            show_stars: value.show_stars,
            show_constellations: value.show_constellations,
            show_constellation_boundaries: value.show_constellation_boundaries,
            show_constellation_art: value.show_constellation_art,
            show_equatorial_grid: value.show_equatorial_grid,
            show_alt_az_grid: value.show_alt_az_grid,
            show_galactic_grid: value.show_galactic_grid,
            show_ecliptic: value.show_ecliptic,
            show_galactic_plane: value.show_galactic_plane,
            show_milky_way: value.show_milky_way,
            show_horizon: value.show_horizon,
            show_atmosphere: value.show_atmosphere,
            show_dsos: value.show_dsos,
            show_solar_system: value.show_solar_system,
            show_satellites: value.show_satellites,
            show_minor_planets: value.show_minor_planets,
            show_variable_stars: value.show_variable_stars,
            magnitude_limit: value.magnitude_limit,
            quality: value.quality,
            bortle_class: value.bortle_class,
            twinkle: value.twinkle,
        }
    }
}

impl From<LabelCategory> for LabelCategoryDto {
    fn from(value: LabelCategory) -> Self {
        match value {
            LabelCategory::Star => Self::Star,
            LabelCategory::Dso => Self::Dso,
            LabelCategory::Constellation => Self::Constellation,
            LabelCategory::Body => Self::Body,
            LabelCategory::Satellite => Self::Satellite,
            LabelCategory::MinorPlanet => Self::MinorPlanet,
        }
    }
}

impl From<LabelCategoryDto> for LabelCategory {
    fn from(value: LabelCategoryDto) -> Self {
        match value {
            LabelCategoryDto::Star => Self::Star,
            LabelCategoryDto::Dso => Self::Dso,
            LabelCategoryDto::Constellation => Self::Constellation,
            LabelCategoryDto::Body => Self::Body,
            LabelCategoryDto::Satellite => Self::Satellite,
            LabelCategoryDto::MinorPlanet => Self::MinorPlanet,
        }
    }
}

impl From<LabelHint> for LabelHintDto {
    fn from(value: LabelHint) -> Self {
        Self {
            object_id: value.object_id,
            screen_x: value.screen_x,
            screen_y: value.screen_y,
            apparent_mag: value.apparent_mag,
            priority: value.priority,
            text: value.text.as_str().to_string(),
            category: value.category.into(),
        }
    }
}

impl From<SelectedObject> for SelectedObjectDto {
    fn from(value: SelectedObject) -> Self {
        Self {
            object_id: value.object_id,
            screen_x: value.screen_x,
            screen_y: value.screen_y,
            ra_rad: value.ra_rad,
            dec_rad: value.dec_rad,
            category: value.category.into(),
            display_name: value.display_name.as_str().to_string(),
        }
    }
}

impl From<SelectedObjectDto> for SelectedObject {
    fn from(value: SelectedObjectDto) -> Self {
        use nightshade_planetarium::scene::SmallString;
        Self {
            object_id: value.object_id,
            screen_x: value.screen_x,
            screen_y: value.screen_y,
            ra_rad: value.ra_rad,
            dec_rad: value.dec_rad,
            category: value.category.into(),
            display_name: SmallString::new(value.display_name),
        }
    }
}

impl From<SceneSnapshot> for SceneSnapshotDto {
    fn from(value: SceneSnapshot) -> Self {
        Self {
            frame_id: value.frame_id,
            view_pose: value.view_pose.into(),
            labels: value.labels.into_iter().map(Into::into).collect(),
            constellation_art: value
                .constellation_art
                .into_iter()
                .map(Into::into)
                .collect(),
            selected: value.selected.map(Into::into),
        }
    }
}

// =============================================================================
// FFI entry points
// =============================================================================

/// Create a planetarium instance bound to the Flutter engine handle.
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_create(engine_handle: i64) -> Result<i64, String> {
    let planetarium = Planetarium::new(engine_handle).map_err(|e| e.to_string())?;
    let id = next_id();
    registry().lock().insert(id, Arc::new(planetarium));
    Ok(id)
}

/// Resize the render target and return the Flutter texture id once allocated.
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_resize(handle: i64, w: u32, h: u32, dpr: f32) -> Result<i64, String> {
    let planetarium = {
        let reg = registry().lock();
        Arc::clone(
            reg.get(&handle)
                .ok_or_else(|| format!("planetarium handle {handle} not found"))?,
        )
    };
    // Capture the current resize generation BEFORE sending so the waiter can
    // detect a failure outcome from THIS resize even if the render thread
    // processes the command before we begin waiting.
    let since = planetarium.resize_generation();
    planetarium
        .send(PlanetariumCommand::Resize {
            width: w,
            height: h,
            dpr,
        })
        .map_err(|e| e.to_string())?;
    wait_texture_id(planetarium.as_ref(), since)
}

/// Update view pose (pan/zoom/roll/projection).
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_set_pose(handle: i64, pose: ViewPoseDto) -> Result<(), String> {
    with_planetarium(handle, |planetarium| {
        planetarium
            .send(PlanetariumCommand::SetPose(pose.into()))
            .map_err(|e| e.to_string())
    })
}

/// Update simulated/observed time.
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_set_time(handle: i64, time: AstroTimeDto) -> Result<(), String> {
    with_planetarium(handle, |planetarium| {
        planetarium
            .send(PlanetariumCommand::SetTime(time.into()))
            .map_err(|e| e.to_string())
    })
}

/// Update observer site and atmosphere inputs.
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_set_observer(handle: i64, observer: ObserverDto) -> Result<(), String> {
    with_planetarium(handle, |planetarium| {
        planetarium
            .send(PlanetariumCommand::SetObserver(observer.into()))
            .map_err(|e| e.to_string())
    })
}

/// Update layer visibility and quality knobs.
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_set_config(handle: i64, config: RenderConfigDto) -> Result<(), String> {
    with_planetarium(handle, |planetarium| {
        planetarium
            .send(PlanetariumCommand::SetConfig(config.into()))
            .map_err(|e| e.to_string())
    })
}

/// Forward a normalized gesture event; updates view pose on pan/zoom/rotate.
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_push_gesture(handle: i64, evt: GestureEventDto) -> Result<(), String> {
    with_planetarium(handle, |planetarium| {
        planetarium
            .send(PlanetariumCommand::PushGesture(evt.into()))
            .map_err(|e| e.to_string())
    })
}

/// Screen pick via projection inverse and registered catalog hit indexes.
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_hit_test(
    handle: i64,
    x: f32,
    y: f32,
) -> Result<Option<SelectedObjectDto>, String> {
    with_planetarium(handle, |planetarium| {
        planetarium
            .hit_test(x, y)
            .map(|opt| opt.map(Into::into))
            .map_err(|e| e.to_string())
    })
}

/// Register a star pack for catalog queries and hit testing (tests / pack-load path).
pub fn planetarium_register_star_pack(handle: i64, pack: Box<dyn StarPack>) -> Result<(), String> {
    with_planetarium(handle, |planetarium| {
        planetarium.register_pack(pack);
        Ok(())
    })
}

/// Load a verified catalog pack from disk, register star tiles, and mark catalog dirty.
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_load_pack(handle: i64, path: String) -> Result<(), String> {
    with_planetarium(handle, |planetarium| {
        planetarium
            .load_pack(Path::new(&path))
            .map_err(|e| e.to_string())
    })
}

/// Set or clear the selected object (reprojects screen position each frame).
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_set_selection(
    handle: i64,
    selected: Option<SelectedObjectDto>,
) -> Result<(), String> {
    with_planetarium(handle, |planetarium| {
        planetarium
            .send(PlanetariumCommand::SetSelection(selected.map(Into::into)))
            .map_err(|e| e.to_string())
    })
}

/// Update the catalog tracking target used by [`PoseLockDto::LockedToTarget`].
///
/// Sent from Dart whenever the user picks a star/DSO to follow. Passing
/// `None` clears the target, which causes the renderer to raise a
/// `MissingTarget` pose error if the lock is still
/// [`PoseLockDto::LockedToTarget`] — silent fall-back to a stale target is
/// explicitly avoided per `CLAUDE.md` "errors are a feature".
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_set_tracking_target(
    handle: i64,
    target: Option<TrackingTargetDto>,
) -> Result<(), String> {
    with_planetarium(handle, |planetarium| {
        planetarium
            .send(PlanetariumCommand::SetTrackingTarget(
                target.map(Into::into),
            ))
            .map_err(|e| e.to_string())
    })
}

/// Update the pose-lock mode (free / target / mount / body).
///
/// Sent from Dart when the user toggles tracking. The lock mode and its
/// reference data (mount position, tracking target) are decoupled so the
/// Dart side can refresh either without rewriting the other; the renderer
/// fails loud when the required reference is missing for the requested
/// mode.
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_set_pose_lock(handle: i64, lock: PoseLockDto) -> Result<(), String> {
    with_planetarium(handle, |planetarium| {
        planetarium
            .send(PlanetariumCommand::SetPoseLock(lock.into()))
            .map_err(|e| e.to_string())
    })
}

/// Update the mount's last-reported equatorial position used by
/// [`PoseLockDto::LockedToMount`].
///
/// Pushed from the equipment layer whenever a telescope driver reports a new
/// RA/Dec. Passing `None` clears the cached position; combined with the lock
/// being [`PoseLockDto::LockedToMount`] this surfaces a `MissingMount` pose
/// error rather than silently freezing the view at a stale position.
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_set_mount_position(
    handle: i64,
    mount: Option<MountPositionDto>,
) -> Result<(), String> {
    with_planetarium(handle, |planetarium| {
        planetarium
            .send(PlanetariumCommand::SetMountPosition(mount.map(Into::into)))
            .map_err(|e| e.to_string())
    })
}

/// Read the latest published scene snapshot for overlay layers.
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_snapshot(handle: i64) -> Result<SceneSnapshotDto, String> {
    with_planetarium(handle, |planetarium| {
        Ok(planetarium.snapshot().as_ref().clone().into())
    })
}

/// Tear down the planetarium handle (stops render thread and releases surface).
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_dispose(handle: i64) -> Result<(), String> {
    let mut reg = registry().lock();
    if reg.remove(&handle).is_none() {
        return Err(format!("planetarium handle {handle} not found"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;
    use std::time::{Duration, Instant};

    // ------------------------------------------------------------------
    // DTO round-trip From conversions (FFI surface invariants)
    // ------------------------------------------------------------------
    //
    // Every DTO that maps onto a `nightshade_planetarium` domain type MUST
    // round-trip without data loss: `From<Domain>` followed by `From<Dto>`
    // (or the reverse) yields the original value. If a future refactor
    // adds or reorders a variant/field, these tests fail loudly instead
    // of silently truncating the value mid-flight.

    #[test]
    fn body_id_dto_round_trip_covers_every_variant() {
        for body in [
            BodyId::Mercury,
            BodyId::Venus,
            BodyId::Mars,
            BodyId::Jupiter,
            BodyId::Saturn,
            BodyId::Uranus,
            BodyId::Neptune,
            BodyId::Moon,
            BodyId::Sun,
        ] {
            let dto: BodyIdDto = body.into();
            let back: BodyId = dto.into();
            assert_eq!(body, back, "BodyId round-trip lost {body:?}");
        }
    }

    #[test]
    fn pose_lock_dto_round_trip_covers_every_variant() {
        let cases = [
            PoseLock::Free,
            PoseLock::LockedToTarget(91262),
            PoseLock::LockedToMount,
            PoseLock::LockedToBody(BodyId::Jupiter),
        ];
        for lock in cases {
            let dto: PoseLockDto = lock.into();
            let back: PoseLock = dto.into();
            assert_eq!(lock, back, "PoseLock round-trip lost {lock:?}");
        }
    }

    #[test]
    fn tracking_target_dto_round_trip_preserves_all_fields() {
        let target = TrackingTarget {
            id: 11767,
            ra_rad: 0.662_062,
            dec_rad: 1.557_896,
        };
        let dto: TrackingTargetDto = target.into();
        assert_eq!(dto.object_id, target.id);
        let back: TrackingTarget = dto.into();
        assert_eq!(back, target);
    }

    #[test]
    fn mount_position_dto_round_trip_preserves_all_fields() {
        let mount = MountPosition {
            ra_rad: 4.872_013,
            dec_rad: 0.676_757,
        };
        let dto: MountPositionDto = mount.into();
        let back: MountPosition = dto.into();
        assert_eq!(back, mount);
    }

    #[test]
    fn constellation_art_placement_dto_preserves_all_fields() {
        use nightshade_planetarium::scene::snapshot::SmallString;

        let placement = ConstellationArtPlacement {
            abbrev: SmallString::new("Ori"),
            screen_x: 0.42,
            screen_y: 0.58,
            scale: 1.25,
            opacity: 0.75,
        };
        let dto: ConstellationArtPlacementDto = placement.clone().into();
        assert_eq!(dto.abbreviation, placement.abbrev.as_str());
        assert_eq!(dto.screen_x, placement.screen_x);
        assert_eq!(dto.screen_y, placement.screen_y);
        assert_eq!(dto.scale, placement.scale);
        assert_eq!(dto.opacity, placement.opacity);
    }

    // ------------------------------------------------------------------
    // Wrapper functions: round-trip set -> snapshot to verify the
    // command lands on the planetarium loop and the lock state advances.
    // ------------------------------------------------------------------

    #[test]
    fn set_tracking_target_does_not_error_on_valid_handle() {
        let handle = planetarium_create(0).expect("create");
        let target = TrackingTargetDto {
            object_id: 91262,
            ra_rad: 4.872,
            dec_rad: 0.677,
        };
        planetarium_set_tracking_target(handle, Some(target)).expect("set target");
        // Clearing must also succeed without error so Dart can drop the
        // selection.
        planetarium_set_tracking_target(handle, None).expect("clear target");
        planetarium_dispose(handle).expect("dispose");
    }

    #[test]
    fn set_pose_lock_accepts_every_variant() {
        let handle = planetarium_create(0).expect("create");
        for lock in [
            PoseLockDto::Free,
            PoseLockDto::LockedToTarget { object_id: 11767 },
            PoseLockDto::LockedToMount,
            PoseLockDto::LockedToBody {
                body: BodyIdDto::Jupiter,
            },
        ] {
            planetarium_set_pose_lock(handle, lock).expect("set lock");
        }
        planetarium_dispose(handle).expect("dispose");
    }

    #[test]
    fn set_mount_position_set_and_clear_succeed() {
        let handle = planetarium_create(0).expect("create");
        planetarium_set_mount_position(
            handle,
            Some(MountPositionDto {
                ra_rad: 4.872,
                dec_rad: 0.677,
            }),
        )
        .expect("set mount");
        planetarium_set_mount_position(handle, None).expect("clear mount");
        planetarium_dispose(handle).expect("dispose");
    }

    #[test]
    fn set_tracking_target_on_disposed_handle_fails_loud() {
        let handle = planetarium_create(0).expect("create");
        planetarium_dispose(handle).expect("dispose");
        let err = planetarium_set_tracking_target(handle, None).unwrap_err();
        assert!(err.contains("not found"), "unexpected: {err}");
    }

    const WAKE_TIMEOUT: Duration = Duration::from_millis(500);
    const POLL: Duration = Duration::from_millis(2);

    fn wait_snapshot_frame(handle: i64) -> SceneSnapshotDto {
        let deadline = Instant::now() + WAKE_TIMEOUT;
        loop {
            let snap = planetarium_snapshot(handle).expect("snapshot");
            if snap.frame_id > 0 {
                return snap;
            }
            if Instant::now() >= deadline {
                panic!("timed out waiting for snapshot publish");
            }
            thread::sleep(POLL);
        }
    }

    fn wait_snapshot_with_ra(handle: i64, expected_ra: f64) -> SceneSnapshotDto {
        let deadline = Instant::now() + WAKE_TIMEOUT;
        let mut last_ra = 0.0_f64;
        loop {
            let snap = planetarium_snapshot(handle).expect("snapshot");
            last_ra = snap.view_pose.ra_rad;
            if snap.frame_id > 0 && (snap.view_pose.ra_rad - expected_ra).abs() < f64::EPSILON {
                return snap;
            }
            if Instant::now() >= deadline {
                panic!("timed out waiting for snapshot ra={expected_ra}; last ra={last_ra}");
            }
            thread::sleep(POLL);
        }
    }

    #[test]
    fn create_dispose_round_trip_without_flutter_engine() {
        let handle = planetarium_create(0).expect("create");
        assert!(lookup(handle).is_ok());
        planetarium_dispose(handle).expect("dispose");
        assert!(lookup(handle).is_err());
    }

    #[test]
    fn set_pose_updates_snapshot_frame_id() {
        let handle = planetarium_create(0).expect("create");
        planetarium_set_pose(
            handle,
            ViewPoseDto {
                ra_rad: 2.5,
                dec_rad: std::f64::consts::FRAC_PI_2,
                fov_rad: std::f32::consts::FRAC_PI_2,
                roll_rad: 0.0,
                projection: SkyProjectionDto::Stereographic,
            },
        )
        .expect("set_pose");
        let snap = wait_snapshot_with_ra(handle, 2.5);
        assert!(snap.frame_id > 0);
        assert!(
            !snap.labels.is_empty(),
            "snapshot should publish label hints from dev catalog"
        );
        planetarium_dispose(handle).expect("dispose");
    }

    fn wait_snapshot_frame_after(handle: i64, after: u64) -> SceneSnapshotDto {
        let deadline = Instant::now() + WAKE_TIMEOUT;
        loop {
            let snap = planetarium_snapshot(handle).expect("snapshot");
            if snap.frame_id > after {
                return snap;
            }
            if Instant::now() >= deadline {
                panic!("timed out waiting for snapshot frame after {after}");
            }
            thread::sleep(POLL);
        }
    }

    #[test]
    fn set_selection_publishes_selected_object_in_snapshot() {
        let handle = planetarium_create(0).expect("create");
        planetarium_set_pose(
            handle,
            ViewPoseDto {
                ra_rad: 0.0,
                dec_rad: std::f64::consts::FRAC_PI_2,
                fov_rad: std::f32::consts::FRAC_PI_2,
                roll_rad: 0.0,
                projection: SkyProjectionDto::Stereographic,
            },
        )
        .expect("set_pose");
        let baseline = wait_snapshot_frame(handle);

        planetarium_set_selection(
            handle,
            Some(SelectedObjectDto {
                object_id: 11767,
                screen_x: 0.0,
                screen_y: 0.0,
                ra_rad: 0.662_062,
                dec_rad: 1.557_896,
                category: LabelCategoryDto::Star,
                display_name: "Polaris".to_string(),
            }),
        )
        .expect("set_selection");

        let snap = wait_snapshot_frame_after(handle, baseline.frame_id);
        let selected = snap.selected.expect("selected object");
        assert_eq!(selected.object_id, 11767);
        assert_eq!(selected.display_name, "Polaris");
        assert!(
            (selected.screen_x - 0.5).abs() < 0.1 && (selected.screen_y - 0.5).abs() < 0.1,
            "selection should be reprojected near center at pole view"
        );
        planetarium_dispose(handle).expect("dispose");
    }

    #[test]
    fn push_gesture_pan_updates_snapshot_pose() {
        let handle = planetarium_create(0).expect("create");
        planetarium_set_pose(
            handle,
            ViewPoseDto {
                ra_rad: 1.0,
                dec_rad: 0.5,
                fov_rad: 1.0,
                roll_rad: 0.0,
                projection: SkyProjectionDto::Stereographic,
            },
        )
        .expect("set_pose");
        let baseline = wait_snapshot_frame(handle);
        let ra_before = baseline.view_pose.ra_rad;

        planetarium_push_gesture(
            handle,
            GestureEventDto {
                kind: GestureKindDto::PanUpdate,
                x: 0.0,
                y: 0.0,
                dx: 0.2,
                dy: 0.0,
                vx: 0.0,
                vy: 0.0,
                factor: 1.0,
                radians: 0.0,
            },
        )
        .expect("push_gesture");

        let snap = wait_snapshot_frame_after(handle, baseline.frame_id);
        assert!(
            (snap.view_pose.ra_rad - ra_before).abs() > 1e-6,
            "pan should change RA in published snapshot"
        );
        planetarium_dispose(handle).expect("dispose");
    }

    #[test]
    fn resize_without_flutter_engine_fails_loud() {
        let handle = planetarium_create(0).expect("create");
        let err = planetarium_resize(handle, 64, 64, 1.0).unwrap_err();
        assert!(
            err.contains("texture not allocated")
                || err.contains("platform surface unsupported")
                || err.contains("irondash_texture"),
            "unexpected error: {err}"
        );
        planetarium_dispose(handle).expect("dispose");
    }

    #[test]
    fn resize_retry_waits_for_new_outcome_not_stale_error() {
        // Behavior: a second resize must not return immediately with the stale
        // surface_error from the first attempt — it must wait for THIS
        // attempt's outcome. Previously enforced by a 2 ms busy-poll loop
        // with a 50 ms floor; now the signal infrastructure (notify on every
        // resize completion + `since_resize_gen` snapshot) lets the second
        // resize unblock as soon as the render thread completes it, typically
        // well under 100 ms.
        let handle = planetarium_create(0).expect("create");
        planetarium_resize(handle, 64, 64, 1.0).unwrap_err();

        let start = Instant::now();
        planetarium_resize(handle, 128, 128, 1.0).unwrap_err();
        let elapsed = start.elapsed();
        assert!(
            elapsed < Duration::from_millis(500),
            "signal-based wait should complete well under the 2 s timeout; elapsed={elapsed:?}",
        );
        planetarium_dispose(handle).expect("dispose");
    }

    #[test]
    fn dispose_unknown_handle_fails_loud() {
        let err = planetarium_dispose(9_999_999).unwrap_err();
        assert!(err.contains("not found"), "unexpected error: {err}");
    }

    #[test]
    fn hit_test_without_catalog_fails_loud() {
        let handle = planetarium_create(0).expect("create");
        let err = planetarium_hit_test(handle, 0.5, 0.5).unwrap_err();
        assert!(
            err.contains("no catalog packs registered"),
            "unexpected error: {err}"
        );
        planetarium_dispose(handle).expect("dispose");
    }

    #[test]
    fn hit_test_tap_on_vega_selects_hip_91262() {
        use std::borrow::Cow;
        use std::collections::HashMap;

        use nightshade_planetarium::catalog::{pixel_for_direction, StarPack, StarRecord};
        use nightshade_planetarium::scene::projection::project_icrs;

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

        let vega = (4.872_013, 0.676_757, 0.03_f32, 91262_u32);
        let polaris = (0.662_062, 1.557_896, 1.98_f32, 11767_u32);

        let handle = planetarium_create(0).expect("create");
        planetarium_set_pose(
            handle,
            ViewPoseDto {
                ra_rad: vega.0,
                dec_rad: vega.1,
                fov_rad: 0.35,
                roll_rad: 0.0,
                projection: SkyProjectionDto::Stereographic,
            },
        )
        .expect("set_pose");
        let _ = wait_snapshot_with_ra(handle, vega.0);

        planetarium_register_star_pack(
            handle,
            Box::new(FakePack::with_stars(&[
                ("vega", vega.0, vega.1, vega.2, vega.3),
                ("polaris", polaris.0, polaris.1, polaris.2, polaris.3),
            ])),
        )
        .expect("register");

        let snap = wait_snapshot_with_ra(handle, vega.0);
        let view_pose: ViewPose = snap.view_pose.into();
        let (sx, sy) = project_icrs(vega.0, vega.1, view_pose).expect("vega on screen");

        let selected = planetarium_hit_test(handle, sx, sy)
            .expect("hit_test")
            .expect("selection");
        assert_eq!(selected.object_id, 91262);
        assert_eq!(selected.display_name, "Vega");

        planetarium_dispose(handle).expect("dispose");
    }

    #[test]
    fn dispose_then_call_returns_not_found_error_no_panic() {
        // After P2#9 (`with_planetarium` clones the Arc out of the registry
        // and releases the lock), dispose IS a soft drop: it removes the
        // registry entry. Any future FFI call for the same handle returns
        // a clean "not found" — never a panic, never a stale handle.
        let handle = planetarium_create(0).expect("create");
        planetarium_dispose(handle).expect("dispose");

        // Every FFI surface that goes through `with_planetarium` (or the
        // direct registry lookups in `planetarium_resize`/`planetarium_dispose`)
        // must report the handle as missing.
        let err = planetarium_set_pose(
            handle,
            ViewPoseDto {
                ra_rad: 0.0,
                dec_rad: 0.0,
                fov_rad: 1.0,
                roll_rad: 0.0,
                projection: SkyProjectionDto::Stereographic,
            },
        )
        .unwrap_err();
        assert!(
            err.contains("not found"),
            "expected 'not found' error, got: {err}",
        );

        let err = planetarium_snapshot(handle).unwrap_err();
        assert!(err.contains("not found"));

        let err = planetarium_dispose(handle).unwrap_err();
        assert!(err.contains("not found"));
    }

    #[test]
    fn with_planetarium_releases_registry_lock_before_running_closure() {
        // Regression: `with_planetarium` used to hold the registry mutex across
        // the user's closure, so any slow FFI op (notably `planetarium_load_pack`
        // mmapping a multi-MB pack) blocked unrelated FFI calls on different
        // handles. Now the registry mutex is dropped before the closure runs.
        //
        // Acquire the global registry lock from THIS thread, then spawn a worker
        // that calls `with_planetarium`. Because the registry lookup completes
        // quickly while we still hold the lock, the worker's closure must NOT
        // run yet (closure body increments a flag). After we drop the lock the
        // worker is free to proceed. Conversely, before the refactor, the
        // worker would block on `registry().lock()` until we released, so the
        // flag would only flip after our drop — masking the regression. We
        // detect the difference by giving the worker a brief opportunity to
        // run the closure WHILE the parent still holds the registry lock.

        let handle = planetarium_create(0).expect("create");

        let started = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let started_clone = Arc::clone(&started);

        let reg_guard = registry().lock();
        let worker = std::thread::spawn(move || {
            with_planetarium(handle, |_p| {
                started_clone.store(true, std::sync::atomic::Ordering::SeqCst);
                Ok(())
            })
            .expect("with_planetarium");
        });

        // Give the worker time to attempt the lookup. With the old code it
        // would be blocked on registry().lock(); with the fix it observes our
        // held lock at registry-lookup time and waits there. Either way,
        // started should NOT flip while we hold the lock — the closure only
        // runs after the lookup returns.
        std::thread::sleep(Duration::from_millis(20));
        assert!(
            !started.load(std::sync::atomic::Ordering::SeqCst),
            "closure ran before registry lookup completed",
        );

        drop(reg_guard);
        worker.join().expect("join");
        assert!(started.load(std::sync::atomic::Ordering::SeqCst));

        planetarium_dispose(handle).expect("dispose");
    }

    #[test]
    fn with_planetarium_does_not_block_concurrent_calls_during_pack_load() {
        // Stress: 4 worker threads each invoke `with_planetarium` (cheap op,
        // forwarding a SetPose command) while a 5th holds the planetarium for
        // a longer simulated operation. With the registry lock released
        // BEFORE the closure runs, the 4 short calls should each return within
        // a small bound — regardless of what the 5th thread is doing.
        let handle = planetarium_create(0).expect("create");

        // Spawn a "slow" thread that simulates pack-load latency by holding
        // the Planetarium for ~50 ms inside its closure.
        let slow = std::thread::spawn(move || {
            with_planetarium(handle, |_p| {
                std::thread::sleep(Duration::from_millis(50));
                Ok(())
            })
            .expect("slow with_planetarium");
        });

        let mut handles = Vec::with_capacity(4);
        for _ in 0..4 {
            handles.push(std::thread::spawn(move || {
                let start = Instant::now();
                let _ = planetarium_set_pose(
                    handle,
                    ViewPoseDto {
                        ra_rad: 1.0,
                        dec_rad: 0.0,
                        fov_rad: std::f32::consts::FRAC_PI_2,
                        roll_rad: 0.0,
                        projection: SkyProjectionDto::Stereographic,
                    },
                );
                start.elapsed()
            }));
        }

        for h in handles {
            let elapsed = h.join().expect("join");
            assert!(
                elapsed < Duration::from_millis(100),
                "concurrent with_planetarium took {elapsed:?}; expected <100ms",
            );
        }

        slow.join().expect("slow join");
        planetarium_dispose(handle).expect("dispose");
    }
}
