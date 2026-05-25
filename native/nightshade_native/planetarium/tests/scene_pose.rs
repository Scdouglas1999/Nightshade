//! Pose controller state machine.

use nightshade_planetarium::astrometry::time::AstroTime;
use nightshade_planetarium::astrometry::vsop87::sun_equatorial_rad;
use nightshade_planetarium::scene::pose::{
    BodyId, MountPosition, PoseController, PoseError, PoseInputs, PoseLock, PoseOffset,
    TrackingTarget,
};
use nightshade_planetarium::types::{SkyProjection, ViewPose};

const JD_2000_JAN_1: f64 = 2_451_544.5;

fn test_pose() -> ViewPose {
    ViewPose {
        ra_rad: 1.0,
        dec_rad: 0.3,
        fov_rad: 0.4,
        roll_rad: 0.1,
        projection: SkyProjection::Stereographic,
    }
}

fn time_2000() -> AstroTime {
    AstroTime::from_jd_utc(JD_2000_JAN_1)
}

#[test]
fn free_mode_returns_free_pose() {
    let initial = test_pose();
    let ctrl = PoseController::new(initial);
    let inputs = PoseInputs {
        time: time_2000(),
        mount: None,
        target: None,
    };
    let pose = ctrl.derived_pose(&inputs).expect("free pose");
    assert_eq!(pose, initial);
}

#[test]
fn locked_to_mount_uses_mount_coords_plus_offset() {
    let mut ctrl = PoseController::new(test_pose());
    ctrl.set_lock(PoseLock::LockedToMount);
    ctrl.set_offset(PoseOffset {
        d_ra_rad: 0.05,
        d_dec_rad: -0.02,
        d_roll_rad: 0.0,
        fov_rad: 0.25,
    });

    let inputs = PoseInputs {
        time: time_2000(),
        mount: Some(MountPosition {
            ra_rad: 2.0,
            dec_rad: 0.5,
        }),
        target: None,
    };

    let pose = ctrl.derived_pose(&inputs).expect("mount lock");
    assert!((pose.ra_rad - 2.05).abs() < 1e-10);
    assert!((pose.dec_rad - 0.48).abs() < 1e-10);
    assert!((pose.fov_rad - 0.25).abs() < f32::EPSILON);
    assert_eq!(pose.projection, SkyProjection::Stereographic);
}

#[test]
fn locked_to_mount_errors_without_mount() {
    let mut ctrl = PoseController::new(test_pose());
    ctrl.set_lock(PoseLock::LockedToMount);
    let err = ctrl
        .derived_pose(&PoseInputs {
            time: time_2000(),
            mount: None,
            target: None,
        })
        .unwrap_err();
    assert!(matches!(err, PoseError::MissingMount));
}

#[test]
fn locked_to_target_uses_catalog_coords() {
    let target_id = 42_u64;
    let mut ctrl = PoseController::new(test_pose());
    ctrl.set_lock(PoseLock::LockedToTarget(target_id));

    let inputs = PoseInputs {
        time: time_2000(),
        mount: None,
        target: Some(TrackingTarget {
            id: target_id,
            ra_rad: 5.5,
            dec_rad: -0.4,
        }),
    };

    let pose = ctrl.derived_pose(&inputs).expect("target lock");
    assert!((pose.ra_rad - 5.5).abs() < 1e-10);
    assert!((pose.dec_rad + 0.4).abs() < 1e-10);
}

#[test]
fn locked_to_target_errors_on_id_mismatch() {
    let mut ctrl = PoseController::new(test_pose());
    ctrl.set_lock(PoseLock::LockedToTarget(99));
    let err = ctrl
        .derived_pose(&PoseInputs {
            time: time_2000(),
            mount: None,
            target: Some(TrackingTarget {
                id: 1,
                ra_rad: 0.0,
                dec_rad: 0.0,
            }),
        })
        .unwrap_err();
    assert!(matches!(err, PoseError::MissingTarget(99)));
}

#[test]
fn locked_to_body_sun_matches_vsop87() {
    let mut ctrl = PoseController::new(test_pose());
    ctrl.set_lock(PoseLock::LockedToBody(BodyId::Sun));
    let time = time_2000();
    let pose = ctrl
        .derived_pose(&PoseInputs {
            time,
            mount: None,
            target: None,
        })
        .expect("sun lock");

    let (exp_ra, exp_dec) = sun_equatorial_rad(time.jd_tt);
    assert!((pose.ra_rad - exp_ra).abs() < 1e-8);
    assert!((pose.dec_rad - exp_dec).abs() < 1e-8);
}

#[test]
fn locked_to_body_jupiter_produces_finite_pose() {
    let mut ctrl = PoseController::new(test_pose());
    ctrl.set_lock(PoseLock::LockedToBody(BodyId::Jupiter));
    let pose = ctrl
        .derived_pose(&PoseInputs {
            time: time_2000(),
            mount: None,
            target: None,
        })
        .expect("jupiter lock");
    assert!(pose.ra_rad.is_finite());
    assert!(pose.dec_rad.is_finite());
    assert!(pose.dec_rad >= -std::f64::consts::FRAC_PI_2);
    assert!(pose.dec_rad <= std::f64::consts::FRAC_PI_2);
}

#[test]
fn locked_to_body_moon_produces_finite_pose() {
    let mut ctrl = PoseController::new(test_pose());
    ctrl.set_lock(PoseLock::LockedToBody(BodyId::Moon));
    let pose = ctrl
        .derived_pose(&PoseInputs {
            time: time_2000(),
            mount: None,
            target: None,
        })
        .expect("moon lock");
    assert!(pose.ra_rad.is_finite() && pose.dec_rad.is_finite());
}

#[test]
fn set_free_pose_updates_free_mode_output() {
    let mut ctrl = PoseController::new(test_pose());
    let mut next = test_pose();
    next.ra_rad = 3.3;
    ctrl.set_free_pose(next);
    let pose = ctrl
        .derived_pose(&PoseInputs {
            time: time_2000(),
            mount: None,
            target: None,
        })
        .expect("updated free");
    assert!((pose.ra_rad - 3.3).abs() < 1e-10);
}
