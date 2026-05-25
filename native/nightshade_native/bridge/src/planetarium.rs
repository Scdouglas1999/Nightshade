//! Full FFI surface for Planetarium v2 (`nightshade_planetarium::Planetarium`).
//!
//! Replaces the Phase 1 spike module. Dart holds opaque handle ids; each function
//! looks up the handle in a static registry and forwards commands to the render loop.
//!
//! Gesture input and hit-testing are deferred to Tasks 16–18 (not exposed here).

use std::collections::HashMap;
use std::sync::OnceLock;
use std::thread;
use std::time::{Duration, Instant};

use nightshade_planetarium::bus::PlanetariumCommand;
use nightshade_planetarium::scene::{
    LabelCategory, LabelHint, SceneSnapshot, SelectedObject,
};
use nightshade_planetarium::types::{
    AstroTime, Observer, RenderConfig, SkyProjection, ViewPose,
};
use nightshade_planetarium::{Planetarium, PlanetariumError};
use parking_lot::Mutex;

static REGISTRY: OnceLock<Mutex<HashMap<i64, Planetarium>>> = OnceLock::new();
static NEXT_ID: OnceLock<Mutex<i64>> = OnceLock::new();

const TEXTURE_POLL: Duration = Duration::from_millis(2);
const TEXTURE_TIMEOUT: Duration = Duration::from_secs(2);

fn registry() -> &'static Mutex<HashMap<i64, Planetarium>> {
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

fn with_planetarium<F, T>(handle: i64, f: F) -> Result<T, String>
where
    F: FnOnce(&Planetarium) -> Result<T, String>,
{
    let reg = registry().lock();
    let planetarium = reg
        .get(&handle)
        .ok_or_else(|| format!("planetarium handle {handle} not found"))?;
    f(planetarium)
}

fn wait_texture_id(planetarium: &Planetarium) -> Result<i64, String> {
    let deadline = Instant::now() + TEXTURE_TIMEOUT;
    loop {
        match planetarium.texture_id() {
            Ok(id) => return Ok(id),
            Err(PlanetariumError::NotAllocated) => {
                if Instant::now() >= deadline {
                    return Err(
                        "texture not allocated after resize — use a valid Flutter engine handle"
                            .to_string(),
                    );
                }
                thread::sleep(TEXTURE_POLL);
            }
            Err(err) => return Err(err.to_string()),
        }
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

/// Immutable per-frame scene snapshot for Dart overlays (FFI).
#[derive(Debug, Clone, PartialEq)]
pub struct SceneSnapshotDto {
    pub frame_id: u64,
    pub view_pose: ViewPoseDto,
    pub labels: Vec<LabelHintDto>,
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

impl From<SceneSnapshot> for SceneSnapshotDto {
    fn from(value: SceneSnapshot) -> Self {
        Self {
            frame_id: value.frame_id,
            view_pose: value.view_pose.into(),
            labels: value.labels.into_iter().map(Into::into).collect(),
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
    registry().lock().insert(id, planetarium);
    Ok(id)
}

/// Resize the render target and return the Flutter texture id once allocated.
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_resize(handle: i64, w: u32, h: u32, dpr: f32) -> Result<i64, String> {
    with_planetarium(handle, |planetarium| {
        planetarium
            .send(PlanetariumCommand::Resize {
                width: w,
                height: h,
                dpr,
            })
            .map_err(|e| e.to_string())?;
        wait_texture_id(planetarium)
    })
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
    use std::time::Duration;

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
        let snap = wait_snapshot_frame(handle);
        assert!(snap.frame_id > 0);
        assert!((snap.view_pose.ra_rad - 2.5).abs() < f64::EPSILON);
        planetarium_dispose(handle).expect("dispose");
    }

    #[test]
    fn resize_without_flutter_engine_fails_loud() {
        let handle = planetarium_create(0).expect("create");
        let err = planetarium_resize(handle, 64, 64, 1.0).unwrap_err();
        assert!(
            err.contains("texture not allocated"),
            "unexpected error: {err}"
        );
        planetarium_dispose(handle).expect("dispose");
    }

    #[test]
    fn dispose_unknown_handle_fails_loud() {
        let err = planetarium_dispose(9_999_999).unwrap_err();
        assert!(err.contains("not found"), "unexpected error: {err}");
    }
}
