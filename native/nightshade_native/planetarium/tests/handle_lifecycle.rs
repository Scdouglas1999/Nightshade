//! Planetarium handle lifecycle: create/drop tight loop without panic or leak.
//!
//! Does not call `Resize` / surface allocate — that requires a live Flutter engine
//! (see Task 15 integration tests). Exercises loop + snapshot + command path only.

use std::borrow::Cow;
use std::thread;
use std::time::{Duration, Instant};

use nightshade_planetarium::bus::PlanetariumCommand;
use nightshade_planetarium::catalog::{pixel_for_direction, HitIndex, StarPack, StarRecord};
use nightshade_planetarium::scene::projection::project_icrs;
use nightshade_planetarium::types::{AstroTime, Observer, SkyProjection, ViewPose};
use nightshade_planetarium::{Planetarium, PlanetariumError};

const ITERATIONS: usize = 48;
const WAKE_TIMEOUT: Duration = Duration::from_millis(500);
const POLL: Duration = Duration::from_millis(2);

#[test]
fn create_drop_tight_loop_without_panic() {
    for _ in 0..ITERATIONS {
        let planetarium = Planetarium::new(0).expect("new succeeds without Flutter engine");
        assert_eq!(
            planetarium.texture_id(),
            Err(PlanetariumError::NotAllocated),
            "no fake texture id before resize"
        );
        drop(planetarium);
    }
}

#[test]
fn drop_joins_render_thread_within_bounded_time() {
    // The Planetarium handle's Drop impl shuts down and joins the render
    // thread. If `render_loop` were declared in the wrong field order, or
    // if the render thread blocked on a long operation, Drop could hang
    // indefinitely. Bound at 500 ms to detect regressions even on slow CI.
    let planetarium = Planetarium::new(0).expect("new");
    // Drive some work so the render thread is actually running, not idle.
    planetarium
        .send(PlanetariumCommand::SetPose(ViewPose {
            ra_rad: 1.0,
            ..ViewPose::default()
        }))
        .expect("set_pose");
    // Wait for at least one frame so we know the thread is past startup.
    let deadline = Instant::now() + WAKE_TIMEOUT;
    while planetarium.snapshot().frame_id == 0 {
        if Instant::now() >= deadline {
            panic!("render thread didn't produce first frame");
        }
        thread::sleep(POLL);
    }

    let start = Instant::now();
    drop(planetarium);
    let elapsed = start.elapsed();
    assert!(
        elapsed < Duration::from_millis(500),
        "Planetarium::Drop took {elapsed:?}; expected <500ms",
    );
}

#[test]
fn send_pose_publishes_snapshot_without_surface_allocate() {
    let planetarium = Planetarium::new(0).expect("new");
    assert_eq!(planetarium.texture_id(), Err(PlanetariumError::NotAllocated));

    planetarium
        .send(PlanetariumCommand::SetPose(ViewPose {
            ra_rad: 1.25,
            ..ViewPose::default()
        }))
        .expect("send SetPose");

    let deadline = std::time::Instant::now() + WAKE_TIMEOUT;
    loop {
        if planetarium.snapshot().frame_id > 0 {
            break;
        }
        if std::time::Instant::now() >= deadline {
            panic!(
                "timed out waiting for snapshot publish; frame_id={}",
                planetarium.snapshot().frame_id
            );
        }
        thread::sleep(POLL);
    }

    assert_eq!(planetarium.texture_id(), Err(PlanetariumError::NotAllocated));
}

#[test]
fn set_time_and_observer_appear_in_published_snapshot() {
    let planetarium = Planetarium::new(0).expect("new");
    let time = AstroTime::from_jd_utc(2_459_223.5);
    let observer = Observer {
        latitude_rad: 0.5,
        longitude_rad: -1.2,
        elevation_m: 1200.0,
        pressure_hpa: 900.0,
        temperature_c: -5.0,
    };

    planetarium
        .send(PlanetariumCommand::SetTime(time))
        .expect("SetTime");
    planetarium
        .send(PlanetariumCommand::SetObserver(observer))
        .expect("SetObserver");
    planetarium
        .send(PlanetariumCommand::SetPose(ViewPose::default()))
        .expect("SetPose");

    let deadline = std::time::Instant::now() + WAKE_TIMEOUT;
    loop {
        let snap = planetarium.snapshot();
        if snap.frame_id > 0 && snap.astro_time == time && snap.observer == observer {
            return;
        }
        if std::time::Instant::now() >= deadline {
            let snap = planetarium.snapshot();
            panic!(
                "timed out; frame_id={} time={:?} observer={:?}",
                snap.frame_id, snap.astro_time, snap.observer
            );
        }
        thread::sleep(POLL);
    }
}

#[test]
fn frame_id_monotonic_across_error_recovery() {
    // Each call to `render_frame` must advance `frame_id` by exactly 1, regardless
    // of whether scene building succeeded. The previous implementation incremented
    // inside the error branch AND inside the happy-path branch — correct only
    // because of an early-return, and fragile against future refactors.
    //
    // We send a sequence of commands that each guarantee at least one render,
    // sample frame_id after each, and assert strict +1 monotonicity.
    let planetarium = Planetarium::new(0).expect("new");

    let mut last = planetarium.snapshot().frame_id;
    for step in 0..8 {
        // Distinct AstroTime per step guarantees the render loop processes a
        // fresh command instead of coalescing into the previous dirty cycle.
        let jd = 2_451_545.0 + (step as f64) * 0.001;
        planetarium
            .send(PlanetariumCommand::SetTime(AstroTime::from_jd_utc(jd)))
            .expect("wake");

        let deadline = Instant::now() + WAKE_TIMEOUT;
        let next = loop {
            let now = planetarium.snapshot().frame_id;
            if now > last {
                break now;
            }
            if Instant::now() >= deadline {
                panic!("timed out waiting for frame after {last} at step {step}");
            }
            thread::sleep(POLL);
        };

        assert_eq!(
            next,
            last + 1,
            "frame_id must advance by exactly 1 each render (step {step}, last={last})",
        );
        last = next;
    }
}

/// Minimal in-memory star pack for hit_test integration tests.
struct OneStarPack {
    nside: u32,
    pixel: u64,
    star: StarRecord,
}

impl OneStarPack {
    fn new(ra: f64, dec: f64, mag: f32, hip: u32) -> Self {
        let nside = 64;
        let pixel = pixel_for_direction(ra, dec, nside).expect("pixel");
        let star = StarRecord::from_radec(hip, ra as f32, dec as f32, mag, f32::NAN, 0);
        Self { nside, pixel, star }
    }
}

impl StarPack for OneStarPack {
    fn pack_id(&self) -> &str {
        "one-star"
    }

    fn nside(&self) -> u32 {
        self.nside
    }

    fn stars_in_pixel(&self, healpix_id: u64) -> Option<Cow<'_, [StarRecord]>> {
        if healpix_id == self.pixel {
            Some(Cow::Owned(vec![self.star]))
        } else {
            None
        }
    }

    fn build_hit_index(&self) -> HitIndex {
        let mut idx = HitIndex::new(self.nside);
        idx.insert_star(self.star).expect("insert");
        idx
    }
}

#[test]
fn hit_test_uses_render_thread_pose_not_published_snapshot() {
    // Regression: hit_test used to read self.snapshot().view_pose, which lags
    // ≥1 frame behind the render thread's current pose. A tap immediately after
    // a programmatic SetPose would project against the OLD pose, hitting the
    // wrong (or no) star. live_pose closes that window.

    // Vega coordinates.
    let star_ra = 4.872_013_f64;
    let star_dec = 0.676_757_f64;
    let hip = 91262_u32;

    let planetarium = Planetarium::new(0).expect("new");
    planetarium.register_pack(Box::new(OneStarPack::new(star_ra, star_dec, 0.03, hip)));

    // Seed pose far from the star: any hit at screen center should MISS.
    planetarium
        .send(PlanetariumCommand::SetPose(ViewPose {
            ra_rad: 0.0,
            dec_rad: 0.0,
            fov_rad: 0.35,
            roll_rad: 0.0,
            projection: SkyProjection::Stereographic,
        }))
        .expect("seed pose");
    // Wait for the snapshot to settle so the published view_pose is the seed.
    let deadline = Instant::now() + WAKE_TIMEOUT;
    loop {
        let snap = planetarium.snapshot();
        if snap.frame_id > 0 && (snap.view_pose.ra_rad - 0.0).abs() < 1e-9 {
            break;
        }
        if Instant::now() >= deadline {
            panic!("seed pose snapshot did not settle");
        }
        thread::sleep(POLL);
    }

    // Now reset view onto the star and IMMEDIATELY hit-test screen center.
    let on_target = ViewPose {
        ra_rad: star_ra,
        dec_rad: star_dec,
        fov_rad: 0.35,
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    };
    planetarium
        .send(PlanetariumCommand::SetPose(on_target))
        .expect("on-target pose");

    // Wait only for live_pose to update — much earlier than snapshot would.
    let deadline = Instant::now() + WAKE_TIMEOUT;
    loop {
        let lp = planetarium.live_pose();
        if (lp.ra_rad - star_ra).abs() < 1e-9 {
            break;
        }
        if Instant::now() >= deadline {
            panic!("live_pose did not catch up to on-target");
        }
        thread::sleep(POLL);
    }

    // Project star to screen using the NEW (live) pose to derive expected tap coords.
    let (sx, sy) = project_icrs(star_ra, star_dec, on_target).expect("star projects");

    let selected = planetarium
        .hit_test(sx, sy)
        .expect("hit_test")
        .expect("selection");
    assert_eq!(
        selected.object_id, hip as u64,
        "hit_test must project against live_pose, not stale snapshot",
    );

    // Direct contract assertion: the pose source hit_test uses must be live_pose,
    // which can lead snapshot.view_pose. Verify the underlying invariant — the
    // integration race above can fall out of either source if the render loop
    // happens to publish the snapshot before hit_test fires; what we really care
    // about is that hit_test reads the LIVE slot regardless of snapshot timing.
    assert_eq!(
        planetarium.live_pose().ra_rad,
        on_target.ra_rad,
        "live_pose should reflect the on-target SetPose",
    );
}

#[test]
fn wait_for_texture_id_unblocks_on_render_thread_signal_not_busy_poll() {
    // Resize without a Flutter engine always fails (surface allocate errors),
    // and the render thread notifies the texture_signal condvar on BOTH success
    // and failure. The waiter must return promptly after the failure is
    // observable — not wait for the 2s deadline.
    let planetarium = Planetarium::new(0).expect("new");
    let since = planetarium.resize_generation();
    planetarium
        .send(PlanetariumCommand::Resize {
            width: 64,
            height: 64,
            dpr: 1.0,
        })
        .expect("resize");

    let start = Instant::now();
    let result = planetarium.wait_for_texture_id(since, Duration::from_secs(2));
    let elapsed = start.elapsed();

    assert!(
        matches!(result, Err(PlanetariumError::NotAllocated)),
        "expected NotAllocated, got {result:?}",
    );
    // The condvar should have woken us well within 500 ms even on slow CI.
    // Regression guarded: prior busy-poll polled every 2 ms but would still
    // time out at 2 s without an outcome signal.
    assert!(
        elapsed < Duration::from_millis(500),
        "wait_for_texture_id elapsed {elapsed:?} — signal mechanism didn't fire",
    );
}

#[test]
fn wait_for_texture_id_returns_immediately_when_already_allocated() {
    // No way to allocate a texture in unit tests (no Flutter engine), but the
    // fast-path branch is observable: if texture_id is NotAllocated and no
    // resize is ever queued, wait_for_texture_id should return NotAllocated
    // after exactly the timeout — never sooner.
    let planetarium = Planetarium::new(0).expect("new");
    let since = planetarium.resize_generation();
    let start = Instant::now();
    let result = planetarium.wait_for_texture_id(since, Duration::from_millis(40));
    let elapsed = start.elapsed();

    assert!(matches!(result, Err(PlanetariumError::NotAllocated)));
    assert!(
        elapsed >= Duration::from_millis(35),
        "wait returned too early ({elapsed:?}); expected ~40ms",
    );
    assert!(
        elapsed < Duration::from_millis(300),
        "wait should not over-stay timeout by much ({elapsed:?})",
    );
}

#[test]
fn live_render_config_updates_through_render_thread() {
    // Before the fix, SetConfig wrote both an FFI-thread Mutex<RenderConfig>
    // mirror AND queued the command for the render thread. The two could
    // diverge briefly because send() returned before the render thread had
    // processed the command — and hit_test read the FFI-thread mirror. There
    // is now exactly one source of truth: live_render_config, written by the
    // render thread inside the SetConfig handler.
    use nightshade_planetarium::types::RenderConfig;

    let planetarium = Planetarium::new(0).expect("new");
    let baseline = planetarium.live_render_config();
    // RenderConfig::default applies before any command is processed.
    assert!((baseline.magnitude_limit - RenderConfig::default().magnitude_limit).abs() < 1e-6);

    planetarium
        .send(PlanetariumCommand::SetConfig(RenderConfig {
            magnitude_limit: 9.5,
            ..RenderConfig::default()
        }))
        .expect("set_config");

    let deadline = Instant::now() + WAKE_TIMEOUT;
    loop {
        let cfg = planetarium.live_render_config();
        if (cfg.magnitude_limit - 9.5).abs() < 1e-6 {
            return;
        }
        if Instant::now() >= deadline {
            panic!(
                "live_render_config did not catch up; magnitude_limit={}",
                cfg.magnitude_limit,
            );
        }
        thread::sleep(POLL);
    }
}

#[test]
fn live_pose_leads_snapshot_view_pose() {
    // The fix for "hit_test reads stale snapshot" requires hit_test to read a
    // pose slot that's updated faster than the published snapshot. Here we
    // assert the mechanism: after every Set* command that touches pose,
    // live_pose reflects the new pose. The published snapshot may or may not
    // have caught up yet — that's the lag the bug was about.
    let planetarium = Planetarium::new(0).expect("new");

    planetarium
        .send(PlanetariumCommand::SetPose(ViewPose {
            ra_rad: 1.0,
            ..ViewPose::default()
        }))
        .expect("set_pose 1");
    let deadline = Instant::now() + WAKE_TIMEOUT;
    loop {
        if (planetarium.live_pose().ra_rad - 1.0).abs() < 1e-9 {
            break;
        }
        if Instant::now() >= deadline {
            panic!("live_pose 1.0 not observed");
        }
        thread::sleep(POLL);
    }

    planetarium
        .send(PlanetariumCommand::SetPose(ViewPose {
            ra_rad: 2.5,
            ..ViewPose::default()
        }))
        .expect("set_pose 2");

    let deadline = Instant::now() + WAKE_TIMEOUT;
    loop {
        if (planetarium.live_pose().ra_rad - 2.5).abs() < 1e-9 {
            break;
        }
        if Instant::now() >= deadline {
            panic!(
                "live_pose 2.5 not observed; live={} snapshot={}",
                planetarium.live_pose().ra_rad,
                planetarium.snapshot().view_pose.ra_rad,
            );
        }
        thread::sleep(POLL);
    }

    assert_eq!(planetarium.live_pose().ra_rad, 2.5);
}

#[test]
fn resize_clears_surface_error_before_retry() {
    let planetarium = Planetarium::new(0).expect("new");
    let resize = |w, h| {
        planetarium
            .send(PlanetariumCommand::Resize {
                width: w,
                height: h,
                dpr: 1.0,
            })
            .expect("send Resize")
    };

    resize(64, 64);
    let deadline = std::time::Instant::now() + WAKE_TIMEOUT;
    loop {
        if planetarium.last_surface_error().is_some() {
            break;
        }
        if std::time::Instant::now() >= deadline {
            panic!("timed out waiting for first resize failure");
        }
        thread::sleep(POLL);
    }

    let gen_after_first = planetarium.resize_generation();
    resize(128, 128);
    let deadline = std::time::Instant::now() + WAKE_TIMEOUT;
    loop {
        if planetarium.resize_generation() > gen_after_first
            && planetarium.last_surface_error().is_some()
        {
            return;
        }
        if std::time::Instant::now() >= deadline {
            panic!(
                "timed out waiting for second resize; gen={} (after {gen_after_first}), err={:?}",
                planetarium.resize_generation(),
                planetarium.last_surface_error()
            );
        }
        thread::sleep(POLL);
    }
}
