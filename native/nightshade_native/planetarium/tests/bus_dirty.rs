use nightshade_planetarium::bus::dirty::DirtyFlags;
use nightshade_planetarium::bus::PlanetariumCommand;
use nightshade_planetarium::gesture::GestureEvent;
use nightshade_planetarium::scene::{MountPosition, PoseLock, TrackingTarget};
use nightshade_planetarium::types::ViewPose;

#[test]
fn pose_command_marks_pose_dirty() {
    let mut d = DirtyFlags::empty();
    let cmd = PlanetariumCommand::SetPose(ViewPose::default());
    cmd.apply_dirty(&mut d);
    assert!(d.contains(DirtyFlags::POSE));
    assert!(!d.contains(DirtyFlags::TIME));
}

#[test]
fn push_gesture_command_marks_pose_dirty() {
    let mut d = DirtyFlags::empty();
    let cmd = PlanetariumCommand::PushGesture(GestureEvent::PanUpdate {
        dx: 0.01,
        dy: 0.0,
        vx: 0.0,
        vy: 0.0,
    });
    cmd.apply_dirty(&mut d);
    assert!(d.contains(DirtyFlags::POSE));
}

#[test]
fn selection_command_marks_selection_dirty() {
    let mut d = DirtyFlags::empty();
    let cmd = PlanetariumCommand::SetSelection(None);
    cmd.apply_dirty(&mut d);
    assert!(d.contains(DirtyFlags::SELECTION));
}

#[test]
fn mount_position_sets_mount_and_pose_dirty() {
    let mut d = DirtyFlags::empty();
    PlanetariumCommand::SetMountPosition(Some(MountPosition {
        ra_rad: 0.0,
        dec_rad: 0.0,
    }))
    .apply_dirty(&mut d);
    assert!(d.contains(DirtyFlags::MOUNT));
    assert!(d.contains(DirtyFlags::POSE));
}

#[test]
fn tracking_target_sets_pose_dirty() {
    let mut d = DirtyFlags::empty();
    PlanetariumCommand::SetTrackingTarget(Some(TrackingTarget {
        id: 1,
        ra_rad: 0.0,
        dec_rad: 0.0,
    }))
    .apply_dirty(&mut d);
    assert!(d.contains(DirtyFlags::POSE));
}

#[test]
fn pose_lock_sets_pose_dirty() {
    let mut d = DirtyFlags::empty();
    PlanetariumCommand::SetPoseLock(PoseLock::LockedToMount).apply_dirty(&mut d);
    assert!(d.contains(DirtyFlags::POSE));
}

#[test]
fn catalog_changed_sets_catalog_dirty() {
    let mut d = DirtyFlags::empty();
    PlanetariumCommand::CatalogChanged.apply_dirty(&mut d);
    assert!(d.contains(DirtyFlags::CATALOG));
}
