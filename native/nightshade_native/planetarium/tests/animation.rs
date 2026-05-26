//! Animation timing and state-transition unit tests (design §9.3).

use std::time::{Duration, Instant};

use nightshade_planetarium::animation::{
    AnimationSet, AnimationState, POP_IN_DURATION, SELECTION_PULSE_DURATION, TWINKLE_FRAME_INTERVAL,
};
use nightshade_planetarium::bus::PlanetariumCommand;
use nightshade_planetarium::scene::{LabelCategory, SelectedObject, SmallString};
use nightshade_planetarium::types::RenderConfig;

fn idle_config() -> RenderConfig {
    RenderConfig {
        twinkle: false,
        show_atmosphere: false,
        ..RenderConfig::default()
    }
}

fn selected() -> SelectedObject {
    SelectedObject {
        object_id: 7,
        screen_x: 0.25,
        screen_y: 0.75,
        ra_rad: 1.0,
        dec_rad: 0.5,
        category: LabelCategory::Dso,
        display_name: SmallString::new("M42"),
    }
}

#[test]
fn pop_in_eases_from_zero_to_one() {
    let mut set = AnimationSet::new(RenderConfig::default());
    let t0 = Instant::now();
    set.on_command(
        &PlanetariumCommand::SetConfig(RenderConfig {
            magnitude_limit: 7.5,
            ..RenderConfig::default()
        }),
        t0,
    );
    let mid = set.state(t0 + POP_IN_DURATION / 2);
    assert!(mid.pop_in > 0.0 && mid.pop_in < 1.0);
    let end = set.state(t0 + POP_IN_DURATION);
    assert_eq!(end.pop_in, 1.0);
}

#[test]
fn selection_pulse_expires_after_duration() {
    let mut set = AnimationSet::new(idle_config());
    let t0 = Instant::now();
    set.on_command(&PlanetariumCommand::SetSelection(Some(selected())), t0);
    assert!(set.needs_wake_at(t0));
    let after = t0 + SELECTION_PULSE_DURATION + Duration::from_millis(1);
    assert!(!set.needs_wake_at(after));
    assert_eq!(set.state(after).selection_pulse, 0.0);
}

#[test]
fn clearing_selection_stops_pulse_wake() {
    let mut set = AnimationSet::new(idle_config());
    let t0 = Instant::now();
    set.on_command(&PlanetariumCommand::SetSelection(Some(selected())), t0);
    set.on_command(&PlanetariumCommand::SetSelection(None), t0);
    assert!(!set.needs_wake_at(t0));
}

#[test]
fn disabling_twinkle_zeros_phase() {
    let mut set = AnimationSet::new(RenderConfig::default());
    let t0 = Instant::now();
    set.advance(t0 + TWINKLE_FRAME_INTERVAL);
    assert_ne!(set.state(t0).twinkle_phase, 0.0);
    set.on_command(
        &PlanetariumCommand::SetConfig(RenderConfig {
            twinkle: false,
            ..RenderConfig::default()
        }),
        t0,
    );
    assert_eq!(set.state(t0).twinkle_phase, 0.0);
    assert_eq!(set.state(t0), AnimationState::INACTIVE);
}

#[test]
fn inactive_state_when_no_effects() {
    let set = AnimationSet::new(idle_config());
    assert_eq!(set.state(Instant::now()), AnimationState::INACTIVE);
}
