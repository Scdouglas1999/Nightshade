//! Pure gesture state machine: pan, zoom, rotate, tap (no GPU).
//!
//! Dart forwards normalized pointer events; this module updates [`ViewPose`] and
//! the render loop marks [`DirtyFlags::POSE`](crate::bus::dirty::DirtyFlags::POSE).

pub mod hit_test;
pub mod momentum;

pub use hit_test::{hit_test_screen, pick_cone_rad, HitTestError};
pub use momentum::{
    decelerate, remaining_weight, PanMomentum, MIN_RELEASE_SPEED, MOMENTUM_DURATION_SECS,
    STEP_FACTOR,
};

use crate::types::ViewPose;

/// Normalized gesture events from Flutter (design §11.1).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum GestureEvent {
    /// Pan gesture began at normalized screen `(x, y)`.
    PanStart {
        /// Normalized x in `[0, 1]`.
        x: f32,
        /// Normalized y in `[0, 1]`.
        y: f32,
    },
    /// Pan delta since last update (normalized screen space).
    PanUpdate {
        /// Horizontal delta since last event.
        dx: f32,
        /// Vertical delta since last event.
        dy: f32,
        /// Estimated horizontal velocity (px/s or normalized/s).
        vx: f32,
        /// Estimated vertical velocity.
        vy: f32,
    },
    /// Pan ended; velocity reserved for momentum (Task 71).
    PanEnd {
        /// Horizontal velocity at release.
        vx: f32,
        /// Vertical velocity at release.
        vy: f32,
    },
    /// Pinch/zoom began at focal point.
    ZoomStart {
        /// Focal x.
        x: f32,
        /// Focal y.
        y: f32,
    },
    /// Pinch scale update (`factor` > 1 zooms in — smaller FOV).
    ZoomUpdate {
        /// Multiplicative scale since gesture start (or last update).
        factor: f32,
        /// Focal x.
        x: f32,
        /// Focal y.
        y: f32,
    },
    /// Pinch ended.
    ZoomEnd,
    /// Two-finger rotation began.
    RotateStart,
    /// Rotation delta in radians.
    RotateUpdate {
        /// Delta rotation since last update.
        radians: f32,
    },
    /// Rotation ended.
    RotateEnd,
    /// Single tap at normalized screen position.
    Tap {
        /// Tap x.
        x: f32,
        /// Tap y.
        y: f32,
    },
    /// Double tap at normalized screen position.
    DoubleTap {
        /// Tap x.
        x: f32,
        /// Tap y.
        y: f32,
    },
    /// Platform cancelled the active gesture.
    Cancel,
}

/// Active gesture phase for the state machine.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActiveGesture {
    Pan,
    Zoom,
    Rotate,
}

/// Updates [`ViewPose`] from forwarded gesture events (minimal Phase 2 / Task 70 preview).
#[derive(Debug, Clone)]
pub struct GestureStateMachine {
    pose: ViewPose,
    active: Option<ActiveGesture>,
    momentum: PanMomentum,
}

impl GestureStateMachine {
    /// Creates a machine anchored at `initial`.
    pub fn new(initial: ViewPose) -> Self {
        Self {
            pose: initial,
            active: None,
            momentum: PanMomentum::new(),
        }
    }

    /// Whether pan momentum is still coasting after release.
    pub fn momentum_active(&self) -> bool {
        self.momentum.is_active()
    }

    /// Advance inertial pan for one frame (`dt_secs` wall time). Returns `true` when pose moved.
    pub fn tick_momentum(&mut self, dt_secs: f32) -> bool {
        if let Some((dx, dy)) = self.momentum.tick(dt_secs) {
            apply_pan_delta(&mut self.pose, dx, dy);
            return true;
        }
        false
    }

    /// Current view pose after applied gestures.
    pub fn pose(&self) -> ViewPose {
        self.pose
    }

    /// Replace the pose anchor without disturbing active momentum or in-progress gestures.
    ///
    /// Use after a programmatic pose update (e.g. `PlanetariumCommand::SetPose`)
    /// so that subsequent pan/zoom/rotate deltas accumulate on top of the new
    /// pose instead of the stale one. Unlike [`Self::new`], this does NOT clear
    /// in-flight pan coast — programmatic pose changes should not silently
    /// cancel a user's release-fling.
    pub fn set_pose_anchor(&mut self, pose: ViewPose) {
        self.pose = pose;
    }

    /// Whether a pan/zoom/rotate sequence is in progress.
    pub fn active_gesture(&self) -> Option<ActiveGesture> {
        self.active
    }

    /// Applies one event. Returns `true` when `pose` changed (POSE dirty).
    pub fn apply(&mut self, evt: GestureEvent) -> bool {
        match evt {
            GestureEvent::PanStart { .. } => {
                self.momentum.cancel();
                self.active = Some(ActiveGesture::Pan);
                false
            }
            GestureEvent::PanUpdate { dx, dy, .. } => {
                self.active = Some(ActiveGesture::Pan);
                apply_pan_delta(&mut self.pose, dx, dy);
                true
            }
            GestureEvent::PanEnd { vx, vy } => {
                self.active = None;
                self.momentum.start(vx, vy);
                false
            }
            GestureEvent::ZoomStart { .. } => {
                self.momentum.cancel();
                self.active = Some(ActiveGesture::Zoom);
                false
            }
            GestureEvent::ZoomUpdate { factor, .. } => {
                self.active = Some(ActiveGesture::Zoom);
                if apply_zoom(&mut self.pose, factor) {
                    return true;
                }
                false
            }
            GestureEvent::ZoomEnd => {
                self.active = None;
                false
            }
            GestureEvent::RotateStart => {
                self.active = Some(ActiveGesture::Rotate);
                false
            }
            GestureEvent::RotateUpdate { radians } => {
                self.active = Some(ActiveGesture::Rotate);
                self.pose.roll_rad += radians;
                true
            }
            GestureEvent::RotateEnd => {
                self.active = None;
                false
            }
            GestureEvent::Tap { .. } | GestureEvent::DoubleTap { .. } => false,
            GestureEvent::Cancel => {
                self.momentum.cancel();
                self.active = None;
                false
            }
        }
    }
}

fn apply_pan_delta(pose: &mut ViewPose, dx: f32, dy: f32) {
    // `dx`/`dy` arrive as normalized screen-fraction deltas (pixelDelta /
    // widget extent) from the Dart side — see
    // `interactive_sky_view.dart` / `gesture_events.dart`.
    //
    // Stellarium "drag the sky" convention (which v1 also followed):
    //   mouse moves right (dx > 0) → sky scrolls right → camera looks
    //   further east → RA INCREASES.
    //   mouse moves down (dy > 0) → sky scrolls down → camera looks
    //   further south → Dec DECREASES.
    //
    // Earlier iteration inverted RA (gave the user the feeling that
    // grabbing the sky and dragging right moved it LEFT). Both signs
    // now match the "grab and throw" mental model.
    //
    // Scale: a full-screen drag rotates by ~one FOV, with cos(dec)
    // correction so peripheral panning near the poles stays cursor-locked.
    let fov = f64::from(pose.fov_rad);
    // `cos(dec)` collapses to zero at the poles; clamp the divisor so the
    // longitudinal step never explodes when looking nearly straight up.
    let cos_dec = pose.dec_rad.cos().abs().max(0.05);
    let d_ra = f64::from(dx) * fov / cos_dec;
    let d_dec = -f64::from(dy) * fov;
    pose.ra_rad = wrap_ra_rad(pose.ra_rad + d_ra);
    pose.dec_rad = (pose.dec_rad + d_dec)
        .clamp(-std::f64::consts::FRAC_PI_2, std::f64::consts::FRAC_PI_2);
}

fn apply_zoom(pose: &mut ViewPose, factor: f32) -> bool {
    if !factor.is_finite() || factor <= 0.0 {
        return false;
    }
    const MIN_FOV: f32 = 0.005;
    const MAX_FOV: f32 = std::f32::consts::PI;
    let next = (pose.fov_rad / factor).clamp(MIN_FOV, MAX_FOV);
    if (next - pose.fov_rad).abs() < f32::EPSILON {
        return false;
    }
    pose.fov_rad = next;
    true
}

fn wrap_ra_rad(ra: f64) -> f64 {
    let two_pi = std::f64::consts::TAU;
    let mut r = ra % two_pi;
    if r < 0.0 {
        r += two_pi;
    }
    r
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::SkyProjection;

    fn test_pose() -> ViewPose {
        ViewPose {
            ra_rad: 1.0,
            dec_rad: 0.5,
            fov_rad: 1.0,
            roll_rad: 0.0,
            projection: SkyProjection::Stereographic,
        }
    }

    #[test]
    fn pan_update_changes_ra_and_dec() {
        let mut sm = GestureStateMachine::new(test_pose());
        assert!(!sm.apply(GestureEvent::PanStart { x: 0.5, y: 0.5 }));
        let before = sm.pose();
        assert!(sm.apply(GestureEvent::PanUpdate {
            dx: 0.1,
            dy: -0.05,
            vx: 0.0,
            vy: 0.0,
        }));
        let after = sm.pose();
        assert_ne!(after.ra_rad, before.ra_rad);
        assert_ne!(after.dec_rad, before.dec_rad);
        assert_eq!(sm.active_gesture(), Some(ActiveGesture::Pan));
    }

    #[test]
    fn zoom_update_shrinks_fov_when_factor_above_one() {
        let mut sm = GestureStateMachine::new(test_pose());
        let fov_before = sm.pose().fov_rad;
        assert!(sm.apply(GestureEvent::ZoomUpdate {
            factor: 2.0,
            x: 0.5,
            y: 0.5,
        }));
        assert!(sm.pose().fov_rad < fov_before);
    }

    #[test]
    fn rotate_update_adds_roll() {
        let mut sm = GestureStateMachine::new(test_pose());
        assert!(sm.apply(GestureEvent::RotateUpdate { radians: 0.25 }));
        assert!((sm.pose().roll_rad - 0.25).abs() < f32::EPSILON);
    }

    #[test]
    fn cancel_clears_active_without_pose_change() {
        let mut sm = GestureStateMachine::new(test_pose());
        let _ = sm.apply(GestureEvent::PanStart { x: 0.0, y: 0.0 });
        let pose = sm.pose();
        assert!(!sm.apply(GestureEvent::Cancel));
        assert_eq!(sm.pose(), pose);
        assert_eq!(sm.active_gesture(), None);
    }

    #[test]
    fn pan_end_below_threshold_does_not_start_momentum() {
        let mut sm = GestureStateMachine::new(test_pose());
        let pose = sm.pose();
        let _ = sm.apply(GestureEvent::PanEnd { vx: 0.01, vy: 0.01 });
        assert!(!sm.momentum_active());
        assert_eq!(sm.pose(), pose);
    }

    #[test]
    fn pan_end_starts_momentum_coast() {
        let mut sm = GestureStateMachine::new(test_pose());
        let _ = sm.apply(GestureEvent::PanEnd { vx: 0.5, vy: 0.0 });
        assert!(sm.momentum_active());
    }

    #[test]
    fn tick_momentum_moves_pose_until_complete() {
        let mut sm = GestureStateMachine::new(test_pose());
        let ra0 = sm.pose().ra_rad;
        let _ = sm.apply(GestureEvent::PanEnd { vx: 1.0, vy: 0.0 });
        let mut moved = false;
        for _ in 0..120 {
            if sm.tick_momentum(1.0 / 60.0) {
                moved = true;
            }
            if !sm.momentum_active() {
                break;
            }
        }
        assert!(moved);
        assert!(!sm.momentum_active());
        assert_ne!(sm.pose().ra_rad, ra0);
    }

    #[test]
    fn pan_start_cancels_active_momentum() {
        let mut sm = GestureStateMachine::new(test_pose());
        let _ = sm.apply(GestureEvent::PanEnd { vx: 1.0, vy: 0.0 });
        assert!(sm.momentum_active());
        let _ = sm.apply(GestureEvent::PanStart { x: 0.5, y: 0.5 });
        assert!(!sm.momentum_active());
    }

    #[test]
    fn set_pose_anchor_preserves_active_momentum() {
        // Programmatic pose updates (e.g. Planetarium::SetPose driven by a
        // tracking target update) must NOT cancel an in-flight pan coast — the
        // user's release-fling continues over the new anchor.
        let mut sm = GestureStateMachine::new(test_pose());
        let _ = sm.apply(GestureEvent::PanEnd { vx: 1.0, vy: 0.0 });
        assert!(sm.momentum_active());

        let new_anchor = ViewPose {
            ra_rad: 2.5,
            dec_rad: -0.3,
            ..test_pose()
        };
        sm.set_pose_anchor(new_anchor);

        assert!(
            sm.momentum_active(),
            "set_pose_anchor must not cancel momentum",
        );
        assert_eq!(
            sm.pose().ra_rad,
            new_anchor.ra_rad,
            "new pan deltas accumulate on top of the new anchor",
        );
    }

    #[test]
    fn set_pose_anchor_preserves_active_gesture_kind() {
        // Mid-pan programmatic pose updates also must not flip `active` to None.
        let mut sm = GestureStateMachine::new(test_pose());
        let _ = sm.apply(GestureEvent::PanStart { x: 0.5, y: 0.5 });
        let _ = sm.apply(GestureEvent::PanUpdate {
            dx: 0.01,
            dy: 0.0,
            vx: 0.0,
            vy: 0.0,
        });
        assert_eq!(sm.active_gesture(), Some(ActiveGesture::Pan));

        sm.set_pose_anchor(ViewPose {
            ra_rad: 3.0,
            ..test_pose()
        });

        assert_eq!(
            sm.active_gesture(),
            Some(ActiveGesture::Pan),
            "set_pose_anchor must preserve in-flight gesture phase",
        );
    }
}
