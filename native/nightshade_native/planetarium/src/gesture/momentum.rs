//! Pan release momentum with v1-matched deceleration (`interactive_sky_view.dart`).
//!
//! Flutter v1 uses an 800 ms `AnimationController`, `Curves.decelerate`, and per-frame
//! `delta = velocity * (1 - decelerate(t)) * 0.02`. Velocities are normalized screen
//! units per second (~50 px/s threshold at ~1000 px width → `0.05`).

/// Total momentum duration (v1: 800 ms).
pub const MOMENTUM_DURATION_SECS: f32 = 0.8;
/// Per-tick displacement scale (v1: `0.02`).
pub const STEP_FACTOR: f32 = 0.02;
/// Minimum release speed to start coasting (v1: 50 px/s ≈ 0.05 normalized at 1k width).
pub const MIN_RELEASE_SPEED: f32 = 0.05;

/// Flutter `Curves.decelerate` = `Cubic(0.0, 0.0, 0.2, 1.0)` — y along the bezier at `t`.
#[must_use]
pub fn decelerate(t: f32) -> f32 {
    let t = t.clamp(0.0, 1.0);
    let omt = 1.0 - t;
    let omt2 = omt * omt;
    let t2 = t * t;
    // y1 = 0, y2 = 1
    3.0 * omt2 * t * 0.0 + 3.0 * omt * t2 * 1.0 + t * t * t
}

/// Remaining displacement weight `1 - decelerate(progress)`.
#[must_use]
pub fn remaining_weight(progress: f32) -> f32 {
    1.0 - decelerate(progress.clamp(0.0, 1.0))
}

/// Post-release inertial pan decay.
#[derive(Debug, Clone, PartialEq)]
pub struct PanMomentum {
    vx: f32,
    vy: f32,
    progress: f32,
    active: bool,
}

impl Default for PanMomentum {
    fn default() -> Self {
        Self {
            vx: 0.0,
            vy: 0.0,
            progress: 0.0,
            active: false,
        }
    }
}

impl PanMomentum {
    /// Creates an idle momentum state.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Whether a pan coast is still in progress.
    #[must_use]
    pub fn is_active(&self) -> bool {
        self.active
    }

    /// Release velocity `(vx, vy)` in normalized screen units per second.
    #[must_use]
    pub fn velocity(&self) -> (f32, f32) {
        (self.vx, self.vy)
    }

    /// Animation progress in `[0, 1]`.
    #[must_use]
    pub fn progress(&self) -> f32 {
        self.progress
    }

    /// Begin coasting when `hypot(vx, vy) >=` [`MIN_RELEASE_SPEED`].
    pub fn start(&mut self, vx: f32, vy: f32) -> bool {
        if !vx.is_finite() || !vy.is_finite() {
            self.active = false;
            return false;
        }
        let speed = (vx * vx + vy * vy).sqrt();
        if speed < MIN_RELEASE_SPEED {
            self.active = false;
            return false;
        }
        self.vx = vx;
        self.vy = vy;
        self.progress = 0.0;
        self.active = true;
        true
    }

    /// Stop coasting (new pan/zoom/cancel).
    pub fn cancel(&mut self) {
        self.active = false;
        self.progress = 0.0;
        self.vx = 0.0;
        self.vy = 0.0;
    }

    /// Advance one frame by `dt_secs`; returns normalized pan delta when active.
    pub fn tick(&mut self, dt_secs: f32) -> Option<(f32, f32)> {
        if !self.active {
            return None;
        }
        let dt = if dt_secs.is_finite() && dt_secs > 0.0 {
            dt_secs.min(0.1)
        } else {
            return None;
        };

        self.progress = (self.progress + dt / MOMENTUM_DURATION_SECS).min(1.0);
        let remaining = remaining_weight(self.progress);
        let dx = self.vx * remaining * STEP_FACTOR;
        let dy = self.vy * remaining * STEP_FACTOR;

        if self.progress >= 1.0 - f32::EPSILON {
            self.active = false;
        }

        if dx == 0.0 && dy == 0.0 {
            return None;
        }

        Some((dx, dy))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decelerate_endpoints() {
        assert!((decelerate(0.0) - 0.0).abs() < 1e-6);
        assert!((decelerate(1.0) - 1.0).abs() < 1e-6);
    }

    #[test]
    fn decelerate_midpoint() {
        assert!((decelerate(0.5) - 0.5).abs() < 1e-6);
    }

    #[test]
    fn remaining_weight_decreases_over_progress() {
        let w0 = remaining_weight(0.0);
        let w_mid = remaining_weight(0.5);
        let w1 = remaining_weight(1.0);
        assert!((w0 - 1.0).abs() < 1e-6);
        assert!(w_mid > 0.0 && w_mid < 1.0);
        assert!(w1.abs() < 1e-6);
    }

    #[test]
    fn start_rejects_sub_threshold_velocity() {
        let mut m = PanMomentum::new();
        assert!(!m.start(0.04, 0.0));
        assert!(!m.is_active());
    }

    #[test]
    fn start_accepts_threshold_velocity() {
        let mut m = PanMomentum::new();
        assert!(m.start(0.05, 0.0));
        assert!(m.is_active());
    }

    #[test]
    fn tick_advances_progress_and_ends() {
        let mut m = PanMomentum::new();
        assert!(m.start(1.0, 0.0));
        let mut steps = 0;
        while m.is_active() && steps < 200 {
            let _ = m.tick(1.0 / 60.0);
            steps += 1;
        }
        assert!(!m.is_active());
        assert!((m.progress() - 1.0).abs() < 1e-4);
        assert!(steps > 0 && steps < 200);
    }

    #[test]
    fn cancel_clears_active_state() {
        let mut m = PanMomentum::new();
        assert!(m.start(1.0, 1.0));
        m.cancel();
        assert!(!m.is_active());
        assert!(m.tick(1.0 / 60.0).is_none());
    }
}
