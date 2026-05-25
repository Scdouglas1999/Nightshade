//! Animation timing for the event-driven render loop (design §9.3).
//!
//! Three animation classes:
//! - **Twinkle** — continuous while [`RenderConfig::twinkle`] and atmosphere are on.
//! - **Selection pulse** — sin envelope while a selection is active (auto-stops after a timeout).
//! - **Pop-in** — one-shot ease when [`RenderConfig::magnitude_limit`] changes (600 ms).

use std::time::{Duration, Instant};

use crate::scene::SelectedObject;
use crate::types::RenderConfig;

/// Pop-in duration after a magnitude-limit change (design §9.3).
pub const POP_IN_DURATION: Duration = Duration::from_millis(600);

/// Selection pulse effect duration before the loop goes idle on pulse alone.
pub const SELECTION_PULSE_DURATION: Duration = Duration::from_secs(30);

/// Target interval between twinkle frames (~60 Hz).
pub const TWINKLE_FRAME_INTERVAL: Duration = Duration::from_millis(16);

/// Sin period for the selection ring pulse (seconds).
const SELECTION_PULSE_PERIOD: f32 = 1.5;

/// Per-frame animation values passed to the renderer / shaders.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AnimationState {
    /// Twinkle shader phase (radians, wraps freely).
    pub twinkle_phase: f32,
    /// Selection ring pulse alpha in \[0, 1\].
    pub selection_pulse: f32,
    /// Pop-in / fade alpha in \[0, 1\] (1 = fully visible).
    pub pop_in: f32,
}

impl AnimationState {
    /// All effects inactive (loop fully idle aside from dirty commands).
    pub const INACTIVE: Self = Self {
        twinkle_phase: 0.0,
        selection_pulse: 0.0,
        pop_in: 1.0,
    };

    /// True when any timed or continuous effect is driving frames.
    pub fn any_active(self) -> bool {
        self.selection_pulse > 0.0
            || self.pop_in < 1.0
            || self.twinkle_phase != 0.0
    }
}

/// Owns animation clocks and [`RenderConfig`] fields relevant to wake scheduling.
#[derive(Debug, Clone)]
pub struct AnimationSet {
    config: RenderConfig,
    selection: Option<SelectedObject>,
    selection_started: Option<Instant>,
    pop_in: Option<PopInAnim>,
    twinkle_phase: f32,
    last_tick: Instant,
}

#[derive(Debug, Clone)]
struct PopInAnim {
    started: Instant,
    #[allow(dead_code)] // reserved for shader magnitude cross-fade (Phase 5)
    from_mag: f32,
    #[allow(dead_code)]
    to_mag: f32,
}

impl AnimationSet {
    /// New set driven by the given render config.
    pub fn new(config: RenderConfig) -> Self {
        Self {
            config,
            selection: None,
            selection_started: None,
            pop_in: None,
            twinkle_phase: 0.0,
            last_tick: Instant::now(),
        }
    }

    /// Current render config used for twinkle gating.
    pub fn config(&self) -> RenderConfig {
        self.config
    }

    /// Whether continuous twinkle should keep the loop awake (~60 fps).
    pub fn twinkle_active(&self) -> bool {
        self.config.twinkle && self.config.show_atmosphere && self.config.show_stars
    }

    /// True when any animation requires periodic wakeups (twinkle or in-flight timed effects).
    pub fn needs_wake(&self) -> bool {
        self.needs_wake_at(Instant::now())
    }

    /// Whether any animation needs periodic wakeups at `now`.
    pub fn needs_wake_at(&self, now: Instant) -> bool {
        self.twinkle_active() || self.pop_in.is_some() || self.selection_pulse_active_at(now)
    }

    /// Next instant the loop should wake to advance animations, if any.
    pub fn next_deadline(&self) -> Option<Instant> {
        let mut next = None;

        if self.twinkle_active() {
            next = Some(self.last_tick + TWINKLE_FRAME_INTERVAL);
        }

        if let Some(pop) = &self.pop_in {
            let end = pop.started + POP_IN_DURATION;
            next = Some(match next {
                Some(n) => n.min(end),
                None => end,
            });
        }

        if self.selection_pulse_active_at(Instant::now()) {
            if let Some(started) = self.selection_started {
                let end = started + SELECTION_PULSE_DURATION;
                next = Some(match next {
                    Some(n) => n.min(end),
                    None => end,
                });
            }
            let pulse_tick = self.last_tick + TWINKLE_FRAME_INTERVAL;
            next = Some(match next {
                Some(n) => n.min(pulse_tick),
                None => pulse_tick,
            });
        }

        next
    }

    /// Duration until [`Self::next_deadline`], or a long sleep when fully idle.
    pub fn next_wakeup(&self) -> Duration {
        match self.next_deadline() {
            Some(deadline) => deadline
                .saturating_duration_since(Instant::now())
                .max(Duration::from_millis(1)),
            None => Duration::from_secs(3600),
        }
    }

    /// Apply a command's side effects on animation state (call before [`crate::bus::PlanetariumCommand::apply_dirty`]).
    pub fn on_command(&mut self, cmd: &crate::bus::PlanetariumCommand, now: Instant) {
        use crate::bus::PlanetariumCommand;

        match cmd {
            PlanetariumCommand::SetConfig(cfg) => {
                let old_mag = self.config.magnitude_limit;
                self.config = *cfg;
                if (cfg.magnitude_limit - old_mag).abs() > f32::EPSILON {
                    self.pop_in = Some(PopInAnim {
                        started: now,
                        from_mag: old_mag,
                        to_mag: cfg.magnitude_limit,
                    });
                }
                if !self.twinkle_active() {
                    // Avoid stale phase waking shaders after twinkle disabled.
                    self.twinkle_phase = 0.0;
                }
            }
            PlanetariumCommand::SetSelection(sel) => {
                self.selection = sel.clone();
                self.selection_started = sel.as_ref().map(|_| now);
            }
            _ => {}
        }
    }

    /// Advance clocks; returns `true` when a render should run for animation alone.
    pub fn advance(&mut self, now: Instant) -> bool {
        let elapsed = now.saturating_duration_since(self.last_tick);
        self.last_tick = now;

        let mut ticked = false;

        if self.twinkle_active() && elapsed >= TWINKLE_FRAME_INTERVAL {
            const TWINKLE_RATE: f32 = 2.5;
            self.twinkle_phase += elapsed.as_secs_f32() * TWINKLE_RATE;
            ticked = true;
        }

        if self.pop_in.is_some() {
            if let Some(pop) = &self.pop_in {
                if now.saturating_duration_since(pop.started) >= POP_IN_DURATION {
                    self.pop_in = None;
                }
            }
            ticked = true;
        }

        if self.selection_pulse_active_at(now) {
            ticked = true;
        }

        ticked
    }

    /// Sample current uniforms for the renderer.
    pub fn state(&self, now: Instant) -> AnimationState {
        AnimationState {
            twinkle_phase: if self.twinkle_active() {
                self.twinkle_phase
            } else {
                0.0
            },
            selection_pulse: self.selection_pulse_alpha(now),
            pop_in: self.pop_in_alpha(now),
        }
    }

    fn selection_pulse_active_at(&self, now: Instant) -> bool {
        self.selection.is_some()
            && self
                .selection_started
                .is_some_and(|s| now.saturating_duration_since(s) < SELECTION_PULSE_DURATION)
    }

    fn selection_pulse_alpha(&self, now: Instant) -> f32 {
        let Some(started) = self.selection_started else {
            return 0.0;
        };
        if self.selection.is_none() {
            return 0.0;
        }
        let elapsed = now.saturating_duration_since(started);
        if elapsed >= SELECTION_PULSE_DURATION {
            return 0.0;
        }
        let t = elapsed.as_secs_f32();
        (t * std::f32::consts::TAU / SELECTION_PULSE_PERIOD).sin() * 0.5 + 0.5
    }

    fn pop_in_alpha(&self, now: Instant) -> f32 {
        let Some(pop) = &self.pop_in else {
            return 1.0;
        };
        let t = (now.saturating_duration_since(pop.started).as_secs_f32()
            / POP_IN_DURATION.as_secs_f32())
            .clamp(0.0, 1.0);
        smoothstep(t)
    }
}

impl Default for AnimationSet {
    fn default() -> Self {
        Self::new(RenderConfig::default())
    }
}

fn smoothstep(t: f32) -> f32 {
    t * t * (3.0 - 2.0 * t)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bus::PlanetariumCommand;
    use crate::scene::{LabelCategory, SmallString};
    use crate::types::RenderConfig;

    fn sel() -> SelectedObject {
        SelectedObject {
            object_id: 42,
            screen_x: 0.5,
            screen_y: 0.5,
            ra_rad: 0.0,
            dec_rad: 0.0,
            category: LabelCategory::Star,
            display_name: SmallString::new("Vega"),
        }
    }

    #[test]
    fn twinkle_inactive_when_config_disabled() {
        let set = AnimationSet::new(RenderConfig {
            twinkle: false,
            show_atmosphere: true,
            show_stars: true,
            ..RenderConfig::default()
        });
        assert!(!set.twinkle_active());
        assert!(!set.needs_wake());
    }

    #[test]
    fn twinkle_active_requires_atmosphere_and_stars() {
        let set = AnimationSet::new(RenderConfig {
            twinkle: true,
            show_atmosphere: false,
            show_stars: true,
            ..RenderConfig::default()
        });
        assert!(!set.twinkle_active());
    }

    #[test]
    fn pop_in_reaches_full_alpha_after_duration() {
        let mut set = AnimationSet::new(RenderConfig::default());
        let t0 = Instant::now();
        set.on_command(
            &PlanetariumCommand::SetConfig(RenderConfig {
                magnitude_limit: 8.0,
                ..RenderConfig::default()
            }),
            t0,
        );
        assert!(set.pop_in.is_some());
        let t1 = t0 + POP_IN_DURATION + Duration::from_millis(1);
        let state = set.state(t1);
        assert_eq!(state.pop_in, 1.0);
        set.advance(t1);
        assert!(set.pop_in.is_none());
    }

    #[test]
    fn selection_pulse_starts_on_set_selection() {
        let mut set = AnimationSet::new(RenderConfig::default());
        let t0 = Instant::now();
        set.on_command(&PlanetariumCommand::SetSelection(Some(sel())), t0);
        assert!(set.needs_wake());
        let alpha = set.state(t0).selection_pulse;
        assert!((0.0..=1.0).contains(&alpha));
    }

    #[test]
    fn advance_ticks_twinkle_on_interval() {
        let mut set = AnimationSet::new(RenderConfig::default());
        let t0 = Instant::now();
        assert!(!set.advance(t0));
        assert!(set.advance(t0 + TWINKLE_FRAME_INTERVAL));
        assert_ne!(set.state(t0 + TWINKLE_FRAME_INTERVAL).twinkle_phase, 0.0);
    }
}
