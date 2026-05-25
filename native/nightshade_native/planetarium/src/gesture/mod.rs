//! Pure gesture state machine: pan, zoom, rotate, tap (no GPU).
//!
//! Dart forwards normalized pointer events; this module updates [`ViewPose`] and
//! the render loop marks [`DirtyFlags::POSE`](crate::bus::dirty::DirtyFlags::POSE).

pub mod hit_test;

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
pub(crate) enum ActiveGesture {
    Pan,
    Zoom,
    Rotate,
}

/// Updates [`ViewPose`] from forwarded gesture events (minimal Phase 2 / Task 70 preview).
#[derive(Debug, Clone)]
pub struct GestureStateMachine {
    pose: ViewPose,
    active: Option<ActiveGesture>,
}

impl GestureStateMachine {
    /// Creates a machine anchored at `initial`.
    pub fn new(initial: ViewPose) -> Self {
        Self {
            pose: initial,
            active: None,
        }
    }

    /// Current view pose after applied gestures.
    pub fn pose(&self) -> ViewPose {
        self.pose
    }

    /// Whether a pan/zoom/rotate sequence is in progress.
    pub fn active_gesture(&self) -> Option<ActiveGesture> {
        self.active
    }

    /// Applies one event. Returns `true` when `pose` changed (POSE dirty).
    pub fn apply(&mut self, evt: GestureEvent) -> bool {
        match evt {
            GestureEvent::PanStart { .. } => {
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
                // Minimal momentum nudge (full integration in Task 71).
                if vx.abs() > f32::EPSILON || vy.abs() > f32::EPSILON {
                    apply_pan_delta(&mut self.pose, vx * 0.016, vy * 0.016);
                    return true;
                }
                false
            }
            GestureEvent::ZoomStart { .. } => {
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
                self.active = None;
                false
            }
        }
    }
}

fn apply_pan_delta(pose: &mut ViewPose, dx: f32, dy: f32) {
    let pan_scale = f64::from(pose.fov_rad.to_degrees()) / 500.0;
    let d_ra_hours = -(f64::from(dx)) * pan_scale / 15.0;
    let d_dec_deg = f64::from(dy) * pan_scale;
    pose.ra_rad = wrap_ra_rad(pose.ra_rad + d_ra_hours * (std::f64::consts::PI / 12.0));
    let dec = pose.dec_rad + d_dec_deg.to_radians();
    pose.dec_rad = dec.clamp(
        -std::f64::consts::FRAC_PI_2,
        std::f64::consts::FRAC_PI_2,
    );
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
}
