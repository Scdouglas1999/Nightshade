//! View-pose lock state machine: free navigation vs mount/target/body tracking.
//!
//! Locked modes center the view on a derived RA/Dec each frame:
//! `view_pose = lock_target(time, mount, catalog) + offset`.
//! See design §11.2.

use crate::astrometry::moon::moon_equatorial_j2000_from_jd_tt;
use crate::astrometry::vsop87::{planet_equatorial_rad, sun_equatorial_rad, VsopBody};
use crate::scene::ObjectId;
use crate::types::{AstroTime, ViewPose};

/// Solar-system body identifier for [`PoseLock::LockedToBody`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum BodyId {
    /// Mercury (VSOP87D).
    Mercury = 0,
    /// Venus (VSOP87D).
    Venus = 1,
    /// Mars (VSOP87D).
    Mars = 2,
    /// Jupiter (VSOP87D).
    Jupiter = 3,
    /// Saturn (VSOP87D).
    Saturn = 4,
    /// Uranus (VSOP87D).
    Uranus = 5,
    /// Neptune (VSOP87D).
    Neptune = 6,
    /// Earth's Moon (ELP2000-82B).
    Moon = 7,
    /// Sun (VSOP87D Earth heliocentric inverse).
    Sun = 8,
}

/// Pose lock mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PoseLock {
    /// User-controlled pose (gestures write [`PoseController::free_pose`]).
    Free,
    /// Center on a catalog object by id.
    LockedToTarget(ObjectId),
    /// Center on mount-reported RA/Dec.
    LockedToMount,
    /// Center on a solar-system body at `time`.
    LockedToBody(BodyId),
}

/// User offset applied on top of a locked target (pan / roll / zoom while tracking).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PoseOffset {
    /// RA offset (radians) added after lock centering.
    pub d_ra_rad: f64,
    /// Dec offset (radians) added after lock centering.
    pub d_dec_rad: f64,
    /// View roll (radians).
    pub d_roll_rad: f32,
    /// Field of view across the shorter axis (radians).
    pub fov_rad: f32,
}

impl Default for PoseOffset {
    fn default() -> Self {
        Self {
            d_ra_rad: 0.0,
            d_dec_rad: 0.0,
            d_roll_rad: 0.0,
            fov_rad: std::f32::consts::FRAC_PI_2,
        }
    }
}

/// Mount-reported equatorial position.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MountPosition {
    /// Mount RA (radians, J2000).
    pub ra_rad: f64,
    /// Mount Dec (radians, J2000).
    pub dec_rad: f64,
}

/// Catalog tracking target coordinates.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TrackingTarget {
    /// Catalog object id (must match lock id).
    pub id: ObjectId,
    /// Target RA (radians, J2000).
    pub ra_rad: f64,
    /// Target Dec (radians, J2000).
    pub dec_rad: f64,
}

/// Per-frame inputs for pose derivation.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PoseInputs {
    /// Current epoch.
    pub time: AstroTime,
    /// Mount position when lock is mount or for diagnostics.
    pub mount: Option<MountPosition>,
    /// Resolved catalog target when lock is target.
    pub target: Option<TrackingTarget>,
}

/// Errors when a lock mode lacks required inputs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum PoseError {
    /// [`PoseLock::LockedToMount`] but no mount position supplied.
    #[error("LockedToMount requires mount position")]
    MissingMount,
    /// [`PoseLock::LockedToTarget`] but target missing or id mismatch.
    #[error("LockedToTarget({0}) requires matching tracking target")]
    MissingTarget(ObjectId),
}

/// View-pose state machine (design §11.2).
#[derive(Debug, Clone, PartialEq)]
pub struct PoseController {
    lock: PoseLock,
    offset: PoseOffset,
    free_pose: ViewPose,
}

impl PoseController {
    /// New controller in [`PoseLock::Free`] at `initial`.
    #[must_use]
    pub fn new(initial: ViewPose) -> Self {
        let offset = PoseOffset {
            fov_rad: initial.fov_rad,
            d_roll_rad: initial.roll_rad,
            ..PoseOffset::default()
        };
        Self {
            lock: PoseLock::Free,
            offset,
            free_pose: initial,
        }
    }

    /// Current lock mode.
    #[must_use]
    pub fn lock(&self) -> PoseLock {
        self.lock
    }

    /// Set lock mode (does not reset offset or free pose).
    pub fn set_lock(&mut self, lock: PoseLock) {
        self.lock = lock;
    }

    /// Pose used in [`PoseLock::Free`] and as projection source when locked.
    #[must_use]
    pub fn free_pose(&self) -> ViewPose {
        self.free_pose
    }

    /// Replace free-navigation pose (gestures in free mode).
    pub fn set_free_pose(&mut self, pose: ViewPose) {
        self.free_pose = pose;
    }

    /// Tracking offset applied on locked modes.
    #[must_use]
    pub fn offset(&self) -> PoseOffset {
        self.offset
    }

    /// Replace tracking offset (pan while locked).
    pub fn set_offset(&mut self, offset: PoseOffset) {
        self.offset = offset;
    }

    /// Derive the view pose for the current lock and inputs.
    pub fn derived_pose(&self, inputs: &PoseInputs) -> Result<ViewPose, PoseError> {
        match self.lock {
            PoseLock::Free => Ok(self.free_pose),
            PoseLock::LockedToMount => {
                let mount = inputs.mount.ok_or(PoseError::MissingMount)?;
                Ok(self.locked_view_pose(mount.ra_rad, mount.dec_rad))
            }
            PoseLock::LockedToTarget(id) => {
                let target = inputs
                    .target
                    .filter(|t| t.id == id)
                    .ok_or(PoseError::MissingTarget(id))?;
                Ok(self.locked_view_pose(target.ra_rad, target.dec_rad))
            }
            PoseLock::LockedToBody(body) => {
                let (ra, dec) = body_equatorial_rad(body, inputs.time)?;
                Ok(self.locked_view_pose(ra, dec))
            }
        }
    }

    fn locked_view_pose(&self, ra_rad: f64, dec_rad: f64) -> ViewPose {
        ViewPose {
            ra_rad: wrap_ra_rad(ra_rad + self.offset.d_ra_rad),
            dec_rad: (dec_rad + self.offset.d_dec_rad)
                .clamp(-std::f64::consts::FRAC_PI_2, std::f64::consts::FRAC_PI_2),
            fov_rad: self.offset.fov_rad,
            roll_rad: self.offset.d_roll_rad,
            projection: self.free_pose.projection,
        }
    }
}

fn body_equatorial_rad(body: BodyId, time: AstroTime) -> Result<(f64, f64), PoseError> {
    match body {
        BodyId::Moon => {
            let moon = moon_equatorial_j2000_from_jd_tt(time.jd_tt);
            Ok((moon.ra_rad, moon.dec_rad))
        }
        BodyId::Sun => Ok(sun_equatorial_rad(time.jd_tt)),
        BodyId::Mercury => Ok(planet_equatorial_rad(VsopBody::Mercury, time.jd_tt)),
        BodyId::Venus => Ok(planet_equatorial_rad(VsopBody::Venus, time.jd_tt)),
        BodyId::Mars => Ok(planet_equatorial_rad(VsopBody::Mars, time.jd_tt)),
        BodyId::Jupiter => Ok(planet_equatorial_rad(VsopBody::Jupiter, time.jd_tt)),
        BodyId::Saturn => Ok(planet_equatorial_rad(VsopBody::Saturn, time.jd_tt)),
        BodyId::Uranus => Ok(planet_equatorial_rad(VsopBody::Uranus, time.jd_tt)),
        BodyId::Neptune => Ok(planet_equatorial_rad(VsopBody::Neptune, time.jd_tt)),
    }
}

fn wrap_ra_rad(ra: f64) -> f64 {
    let two_pi = std::f64::consts::TAU;
    let mut r = ra % two_pi;
    if r < 0.0 {
        r += two_pi;
    }
    r
}
