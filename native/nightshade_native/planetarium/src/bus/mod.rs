//! Command channel and dirty-flag bus for the render loop.

pub mod dirty;
pub mod loop_thread;

use crate::gesture::GestureEvent;
use crate::scene::{MountPosition, PoseLock, SelectedObject, TrackingTarget};
use crate::types::{AstroTime, Observer, RenderConfig, ViewPose};
use dirty::DirtyFlags;

/// Commands sent from the FFI thread to the render loop.
#[derive(Debug, Clone)]
pub enum PlanetariumCommand {
    SetPose(ViewPose),
    SetTime(AstroTime),
    SetObserver(Observer),
    SetConfig(RenderConfig),
    SetSelection(Option<SelectedObject>),
    /// Mount-reported equatorial position (degrees/radians from FFI).
    SetMountPosition(Option<MountPosition>),
    /// Catalog tracking target coordinates for [`PoseLock::LockedToTarget`].
    SetTrackingTarget(Option<TrackingTarget>),
    /// View lock mode (free navigation vs mount/target/body tracking).
    SetPoseLock(PoseLock),
    PushGesture(GestureEvent),
    Resize {
        width: u32,
        height: u32,
        dpr: f32,
    },
    /// Star/DSO catalog registration changed on the handle; renderer should refresh catalog layers.
    CatalogChanged,
    Shutdown,
}

impl PlanetariumCommand {
    /// Apply the dirty flags implied by this command.
    pub fn apply_dirty(&self, d: &mut DirtyFlags) {
        match self {
            Self::SetPose(_) => *d |= DirtyFlags::POSE,
            Self::SetTime(_) => *d |= DirtyFlags::TIME,
            Self::SetObserver(_) => *d |= DirtyFlags::OBSERVER,
            Self::SetConfig(_) => *d |= DirtyFlags::CONFIG,
            Self::SetSelection(_) => *d |= DirtyFlags::SELECTION,
            Self::SetMountPosition(_) => *d |= DirtyFlags::MOUNT | DirtyFlags::POSE,
            Self::SetTrackingTarget(_) => *d |= DirtyFlags::POSE,
            Self::SetPoseLock(_) => *d |= DirtyFlags::POSE,
            Self::PushGesture(_) => *d |= DirtyFlags::POSE,
            Self::Resize { .. } => *d |= DirtyFlags::RESIZE,
            Self::CatalogChanged => *d |= DirtyFlags::CATALOG,
            Self::Shutdown => {}
        }
    }
}
